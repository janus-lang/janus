// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! External Function Registry
//!
//! Tracks function signatures from external Zig modules imported via `use zig "path"`.
//! During the bootstrap phase, Janus IS Zig - these functions are compiled natively
//! by the build system and linked together. This registry provides the type information
//! needed to emit correct LLVM IR declarations.
//!
//! Philosophy: NOT FFI - Native Integration
//! - Bootstrap: Janus compiler = Zig → Zig modules are NATIVE
//! - Self-hosted: Janus compiler = Janus → Zig becomes GRAFTED (like C)

const std = @import("std");
const zig_parser = @import("zig_parser");

/// LLVM type string for function parameter/return types
pub const LLVMTypeStr = []const u8;

/// External function signature for LLVM emission
pub const ExternFnSig = struct {
    name: []const u8,
    param_types: []const LLVMTypeStr,
    return_type: LLVMTypeStr,
    source_path: []const u8, // Which Zig file it came from

    pub fn deinit(self: *ExternFnSig, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.param_types) |pt| {
            allocator.free(pt);
        }
        allocator.free(self.param_types);
        allocator.free(self.return_type);
        allocator.free(self.source_path);
    }
};

/// Registry of external functions from Zig modules
pub const ExternRegistry = struct {
    allocator: std.mem.Allocator,
    /// Function name → signature
    functions: std.StringHashMapUnmanaged(ExternFnSig),
    /// Paths of Zig files that have been registered
    registered_paths: std.StringHashMapUnmanaged(void),

    pub fn init(allocator: std.mem.Allocator) ExternRegistry {
        return .{
            .allocator = allocator,
            .functions = .{},
            .registered_paths = .{},
        };
    }

    pub fn deinit(self: *ExternRegistry) void {
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.functions.deinit(self.allocator);

        var path_it = self.registered_paths.keyIterator();
        while (path_it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.registered_paths.deinit(self.allocator);
    }

    /// Register functions from a Zig source file
    /// Returns the number of functions registered
    pub fn registerZigSource(self: *ExternRegistry, path: []const u8, source: []const u8) !usize {
        // Check if already registered
        if (self.registered_paths.contains(path)) {
            return 0;
        }

        // Parse the Zig source
        var parse_result = try zig_parser.parseZigSource(self.allocator, source);
        defer parse_result.deinit();

        var count: usize = 0;

        for (parse_result.functions.items) |func| {
            // Convert to ExternFnSig
            var param_types = try self.allocator.alloc(LLVMTypeStr, func.params.len);
            for (func.params, 0..) |param, i| {
                param_types[i] = try self.allocator.dupe(u8, param.janus_type.toLLVMType());
            }

            const sig = ExternFnSig{
                .name = try self.allocator.dupe(u8, func.name),
                .param_types = param_types,
                .return_type = try self.allocator.dupe(u8, func.return_type.toLLVMType()),
                .source_path = try self.allocator.dupe(u8, path),
            };

            const name_key = try self.allocator.dupe(u8, func.name);
            try self.functions.put(self.allocator, name_key, sig);
            count += 1;
        }

        // Mark path as registered
        const path_key = try self.allocator.dupe(u8, path);
        try self.registered_paths.put(self.allocator, path_key, {});

        return count;
    }

    /// Look up a function signature by name
    pub fn lookup(self: *const ExternRegistry, name: []const u8) ?*const ExternFnSig {
        return self.functions.getPtr(name);
    }

    /// Check if a function is registered
    pub fn contains(self: *const ExternRegistry, name: []const u8) bool {
        return self.functions.contains(name);
    }

    /// Get all registered function names
    pub fn getFunctionNames(self: *const ExternRegistry, allocator: std.mem.Allocator) ![]const []const u8 {
        var names: std.ArrayList([]const u8) = .empty;
        var it = self.functions.keyIterator();
        while (it.next()) |key| {
            try names.append(key.*);
        }
        return try names.toOwnedSlice(allocator);
    }
};

// Tests
test "register simple Zig functions" {
    const allocator = std.testing.allocator;

    const source =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\
        \\pub fn multiply(x: f64, y: f64) f64 {
        \\    return x * y;
        \\}
    ;

    var registry = ExternRegistry.init(allocator);
    defer registry.deinit();

    const count = try registry.registerZigSource("test.zig", source);
    try std.testing.expectEqual(@as(usize, 2), count);

    // Check add function
    if (registry.lookup("add")) |sig| {
        try std.testing.expectEqualStrings("add", sig.name);
        try std.testing.expectEqual(@as(usize, 2), sig.param_types.len);
        try std.testing.expectEqualStrings("i32", sig.param_types[0]);
        try std.testing.expectEqualStrings("i32", sig.param_types[1]);
        try std.testing.expectEqualStrings("i32", sig.return_type);
    } else {
        return error.TestFailed;
    }

    // Check multiply function
    if (registry.lookup("multiply")) |sig| {
        try std.testing.expectEqualStrings("multiply", sig.name);
        try std.testing.expectEqualStrings("double", sig.param_types[0]);
        try std.testing.expectEqualStrings("double", sig.return_type);
    } else {
        return error.TestFailed;
    }
}

test "no duplicate registration" {
    const allocator = std.testing.allocator;

    const source =
        \\pub fn foo() void {}
    ;

    var registry = ExternRegistry.init(allocator);
    defer registry.deinit();

    const count1 = try registry.registerZigSource("test.zig", source);
    try std.testing.expectEqual(@as(usize, 1), count1);

    // Second registration should return 0 (already registered)
    const count2 = try registry.registerZigSource("test.zig", source);
    try std.testing.expectEqual(@as(usize, 0), count2);
}
