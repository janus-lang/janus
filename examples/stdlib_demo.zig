// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - Tri-Signature Pattern Demo
// Demonstrates the tri-signature pattern in action

const std = @import("std");

// Mock implementations for demonstration
const MockContext = struct {
    cancelled: bool = false,

    pub fn is_done(self: @This()) bool {
        return self.cancelled;
    }
};

const MockCapability = struct {
    id_value: []const u8,

    pub fn id(self: @This()) []const u8 {
        return self.id_value;
    }

    pub fn allows_path(self: @This(), path: []const u8) bool {
        _ = self;
        return path.len > 0; // Simple validation
    }
};

// =============================================================================
// TRI-SIGNATURE PATTERN DEMONSTRATION
// =============================================================================

/// File read operations with tri-signature pattern
const FileOps = struct {
    /// :min profile - Simple synchronous file reading
    pub fn read_min(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
        if (path.len == 0) return error.InvalidPath;
        return try std.fmt.allocPrint(allocator, "Content from {s} (:min profile)", .{path});
    }

    /// :go profile - Context-aware file reading
    pub fn read_go(path: []const u8, ctx: MockContext, allocator: std.mem.Allocator) ![]u8 {
        if (path.len == 0) return error.InvalidPath;
        if (ctx.is_done()) return error.ContextCancelled;
        return try std.fmt.allocPrint(allocator, "Content from {s} (:go profile, context active)", .{path});
    }

    /// :full profile - Capability-gated file reading
    pub fn read_full(path: []const u8, cap: MockCapability, allocator: std.mem.Allocator) ![]u8 {
        if (path.len == 0) return error.InvalidPath;
        if (!cap.allows_path(path)) return error.CapabilityRequired;
        return try std.fmt.allocPrint(allocator, "Content from {s} (:full profile, capability: {s})", .{ path, cap.id() });
    }

    /// Universal dispatch function
    pub fn read(args: anytype) ![]u8 {
        const ArgsType = @TypeOf(args);
        const args_info = @typeInfo(ArgsType);

        if (args_info != .Struct) {
            @compileError("read requires struct arguments");
        }

        const fields = args_info.Struct.fields;

        // Dispatch based on argument signature
        if (fields.len == 2) {
            // :min profile: read(.{ .path = path, .allocator = allocator })
            return read_min(args.path, args.allocator);
        } else if (fields.len == 3 and @hasField(ArgsType, "ctx")) {
            // :go profile: read(.{ .path = path, .ctx = ctx, .allocator = allocator })
            return read_go(args.path, args.ctx, args.allocator);
        } else if (fields.len == 3 and @hasField(ArgsType, "cap")) {
            // :full profile: read(.{ .path = path, .cap = cap, .allocator = allocator })
            return read_full(args.path, args.cap, args.allocator);
        } else {
            @compileError("Invalid arguments for read - check profile requirements");
        }
    }
};

// =============================================================================
// DEMONSTRATION FUNCTIONS
// =============================================================================

pub fn demonstrate_tri_signature_pattern(allocator: std.mem.Allocator) !void {
    std.log.info("=== Tri-Signature Pattern Demonstration ===");

    // Test :min profile
    {
        std.log.info("\n--- :min Profile ---");
        const content = try FileOps.read(.{ .path = "/test/file.txt", .allocator = allocator });
        defer allocator.free(content);
        std.log.info("Result: {s}", .{content});
    }

    // Test :go profile
    {
        std.log.info("\n--- :go Profile ---");
        const ctx = MockContext{};
        const content = try FileOps.read(.{ .path = "/test/file.txt", .ctx = ctx, .allocator = allocator });
        defer allocator.free(content);
        std.log.info("Result: {s}", .{content});
    }

    // Test :full profile
    {
        std.log.info("\n--- :full Profile ---");
        const cap = MockCapability{ .id_value = "fs-read-cap" };
        const content = try FileOps.read(.{ .path = "/test/file.txt", .cap = cap, .allocator = allocator });
        defer allocator.free(content);
        std.log.info("Result: {s}", .{content});
    }

    std.log.info("\n=== Demonstration Complete ===");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try demonstrate_tri_signature_pattern(allocator);
}

// =============================================================================
// TESTS
// =============================================================================

test "tri-signature pattern dispatch" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test :min profile dispatch
    {
        const content = try FileOps.read(.{ .path = "/test/file.txt", .allocator = allocator });
        defer allocator.free(content);
        try testing.expect(std.mem.indexOf(u8, content, ":min profile") != null);
    }

    // Test :go profile dispatch
    {
        const ctx = MockContext{};
        const content = try FileOps.read(.{ .path = "/test/file.txt", .ctx = ctx, .allocator = allocator });
        defer allocator.free(content);
        try testing.expect(std.mem.indexOf(u8, content, ":go profile") != null);
    }

    // Test :full profile dispatch
    {
        const cap = MockCapability{ .id_value = "test-cap" };
        const content = try FileOps.read(.{ .path = "/test/file.txt", .cap = cap, .allocator = allocator });
        defer allocator.free(content);
        try testing.expect(std.mem.indexOf(u8, content, ":full profile") != null);
        try testing.expect(std.mem.indexOf(u8, content, "test-cap") != null);
    }
}

test "profile-specific behavior" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test context cancellation in :go profile
    {
        const cancelled_ctx = MockContext{ .cancelled = true };
        try testing.expectError(error.ContextCancelled, FileOps.read_go("/test/file.txt", cancelled_ctx, allocator));
    }

    // Test capability validation in :full profile
    {
        const cap = MockCapability{ .id_value = "test-cap" };

        // Should succeed for valid path
        const content = try FileOps.read_full("/test/file.txt", cap, allocator);
        defer allocator.free(content);
        try testing.expect(content.len > 0);

        // Should fail for empty path (triggers capability check failure)
        try testing.expectError(error.InvalidPath, FileOps.read_full("", cap, allocator));
    }
}

test "argument validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test invalid path handling across all profiles
    try testing.expectError(error.InvalidPath, FileOps.read_min("", allocator));

    const ctx = MockContext{};
    try testing.expectError(error.InvalidPath, FileOps.read_go("", ctx, allocator));

    const cap = MockCapability{ .id_value = "test-cap" };
    try testing.expectError(error.InvalidPath, FileOps.read_full("", cap, allocator));
}
