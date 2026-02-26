// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("astdb/astdb.zig");
const SemanticAnalyzer = @import("semantic_analyzer.zig");
const CCodeGenerator = @import("libjanus/passes/codegen/c.zig");

// Profile-Aware Dispatch Integration - Clean Implementation
// Connects semantic analysis → dispatch resolution → C code generation

const AstDB = astdb.AstDB;
const NodeId = astdb.NodeId;
const UnitId = astdb.UnitId;
const Profile = SemanticAnalyzer.Profile;
const SemanticInfo = SemanticAnalyzer.SemanticInfo;

/// Dispatch strategy for function calls
pub const DispatchStrategy = enum {
    static_call, // Direct function call (no dispatch needed)
    profile_dispatch, // Profile-aware tri-signature dispatch
    dynamic_dispatch, // Full dynamic dispatch with type checking
};

/// Dispatch resolution result
pub const DispatchResolution = struct {
    strategy: DispatchStrategy,
    target_function: []const u8,
    inject_context: bool,
    inject_capability: bool,
    inject_allocator: bool,
    capability_type: ?[]const u8,
    cost_estimate: u32, // Cycles
};

/// Profile-aware dispatch resolver
pub const ProfileDispatchResolver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    profile: Profile,

    pub fn init(allocator: std.mem.Allocator, profile: Profile) Self {
        return Self{
            .allocator = allocator,
            .profile = profile,
        };
    }

    /// Resolve dispatch strategy for a function call
    pub fn resolveDispatch(self: *Self, function_name: []const u8) !DispatchResolution {
        // Check if this is a standard library function
        if (self.isStandardLibraryFunction(function_name)) {
            return try self.resolveStandardLibraryDispatch(function_name);
        }

        // User function - direct call with allocator injection
        const target_function = try std.fmt.allocPrint(self.allocator, "janus_user_{s}", .{function_name});

        return DispatchResolution{
            .strategy = .static_call,
            .target_function = target_function,
            .inject_context = false,
            .inject_capability = false,
            .inject_allocator = true,
            .capability_type = null,
            .cost_estimate = 1, // Direct call
        };
    }

    /// Check if function is in standard library
    fn isStandardLibraryFunction(self: *Self, function_name: []const u8) bool {
        _ = self;

        const stdlib_functions = [_][]const u8{
            "print", "eprint", "println", "eprintln",
        };

        for (stdlib_functions) |stdlib_func| {
            if (std.mem.eql(u8, function_name, stdlib_func)) {
                return true;
            }
        }

        return false;
    }

    /// Resolve standard library function dispatch
    fn resolveStandardLibraryDispatch(self: *Self, function_name: []const u8) !DispatchResolution {
        const profile_suffix = switch (self.profile) {
            .min => "min",
            .go => "go",
            .full => "full",
        };

        const target_function = try std.fmt.allocPrint(self.allocator, "janus_{s}_{s}", .{ function_name, profile_suffix });

        // Determine parameter injection based on profile and function
        const inject_context = self.profile == .go;
        const inject_capability = self.profile == .full;
        const capability_type = if (inject_capability) self.getCapabilityType(function_name) else null;

        return DispatchResolution{
            .strategy = .profile_dispatch,
            .target_function = target_function,
            .inject_context = inject_context,
            .inject_capability = inject_capability,
            .inject_allocator = true, // Always inject allocator
            .capability_type = capability_type,
            .cost_estimate = self.estimateProfileDispatchCost(),
        };
    }

    /// Get capability type for function
    fn getCapabilityType(self: *Self, function_name: []const u8) []const u8 {
        _ = self;

        if (std.mem.eql(u8, function_name, "print") or std.mem.eql(u8, function_name, "println")) {
            return "StdoutWriteCapability";
        }

        if (std.mem.eql(u8, function_name, "eprint") or std.mem.eql(u8, function_name, "eprintln")) {
            return "StderrWriteCapability";
        }

        return "GenericCapability";
    }

    /// Estimate cost of profile dispatch
    fn estimateProfileDispatchCost(self: *Self) u32 {
        return switch (self.profile) {
            .min => 1, // Direct call
            .go => 3, // Context check + call
            .full => 5, // Capability validation + call
        };
    }
};

/// Dispatch table for a compilation unit
pub const DispatchTable = struct {
    const Self = @This();

    entries: std.ArrayList(DispatchEntry),
    allocator: std.mem.Allocator,

    const DispatchEntry = struct {
        function_name: []const u8,
        resolution: DispatchResolution,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .entries = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entries.deinit();
    }

    pub fn addEntry(self: *Self, function_name: []const u8, resolution: DispatchResolution) !void {
        try self.entries.append(DispatchEntry{
            .function_name = function_name,
            .resolution = resolution,
        });
    }

    pub fn getResolution(self: *const Self, function_name: []const u8) ?DispatchResolution {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.function_name, function_name)) {
                return entry.resolution;
            }
        }
        return null;
    }

    /// Generate dispatch statistics
    pub fn generateStats(self: *const Self) DispatchStats {
        var stats = DispatchStats{};

        for (self.entries.items) |entry| {
            switch (entry.resolution.strategy) {
                .static_call => stats.static_calls += 1,
                .profile_dispatch => stats.profile_dispatches += 1,
                .dynamic_dispatch => stats.dynamic_dispatches += 1,
            }

            stats.total_cost += entry.resolution.cost_estimate;
        }

        return stats;
    }
};

/// Dispatch statistics
pub const DispatchStats = struct {
    static_calls: u32 = 0,
    profile_dispatches: u32 = 0,
    dynamic_dispatches: u32 = 0,
    total_cost: u32 = 0,

    pub fn getTotalCalls(self: DispatchStats) u32 {
        return self.static_calls + self.profile_dispatches + self.dynamic_dispatches;
    }

    pub fn getAverageCost(self: DispatchStats) f32 {
        const total = self.getTotalCalls();
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.total_cost)) / @as(f32, @floatFromInt(total));
    }
};

// Tests for profile-aware dispatch integration
const testing = std.testing;

test "ProfileDispatchResolver: standard library function resolution" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test different profiles
    const profiles = [_]Profile{ .min, .go, .full };

    for (profiles) |profile| {
        var resolver = ProfileDispatchResolver.init(allocator, profile);
        const resolution = try resolver.resolveDispatch("print");

        // Should be profile dispatch for stdlib functions
        try testing.expectEqual(DispatchStrategy.profile_dispatch, resolution.strategy);

        // Should have profile-specific target
        const expected_target = switch (profile) {
            .min => "janus_print_min",
            .go => "janus_print_go",
            .full => "janus_print_full",
        };
        try testing.expectEqualStrings(expected_target, resolution.target_function);

        // Should have appropriate parameter injection
        switch (profile) {
            .min => {
                try testing.expect(!resolution.inject_context);
                try testing.expect(!resolution.inject_capability);
                try testing.expect(resolution.inject_allocator);
            },
            .go => {
                try testing.expect(resolution.inject_context);
                try testing.expect(!resolution.inject_capability);
                try testing.expect(resolution.inject_allocator);
            },
            .full => {
                try testing.expect(!resolution.inject_context);
                try testing.expect(resolution.inject_capability);
                try testing.expect(resolution.inject_allocator);
                try testing.expectEqualStrings("StdoutWriteCapability", resolution.capability_type.?);
            },
        }
    }
}

test "ProfileDispatchResolver: user function resolution" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var resolver = ProfileDispatchResolver.init(allocator, .min);
    const resolution = try resolver.resolveDispatch("my_function");

    // Should be static call for user functions
    try testing.expectEqual(DispatchStrategy.static_call, resolution.strategy);
    try testing.expectEqualStrings("janus_user_my_function", resolution.target_function);
    try testing.expect(!resolution.inject_context);
    try testing.expect(!resolution.inject_capability);
    try testing.expect(resolution.inject_allocator);
    try testing.expectEqual(@as(u32, 1), resolution.cost_estimate);
}

test "DispatchTable: statistics generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var table = DispatchTable.init(allocator);
    defer table.deinit();

    // Add some test entries
    try table.addEntry("print", DispatchResolution{
        .strategy = .profile_dispatch,
        .target_function = "janus_print_min",
        .inject_context = false,
        .inject_capability = false,
        .inject_allocator = true,
        .capability_type = null,
        .cost_estimate = 1,
    });

    try table.addEntry("user_func", DispatchResolution{
        .strategy = .static_call,
        .target_function = "janus_user_user_func",
        .inject_context = false,
        .inject_capability = false,
        .inject_allocator = true,
        .capability_type = null,
        .cost_estimate = 1,
    });

    const stats = table.generateStats();

    try testing.expectEqual(@as(u32, 2), stats.getTotalCalls());
    try testing.expectEqual(@as(u32, 1), stats.static_calls);
    try testing.expectEqual(@as(u32, 1), stats.profile_dispatches);
    try testing.expectEqual(@as(u32, 0), stats.dynamic_dispatches);
    try testing.expectEqual(@as(f32, 1.0), stats.getAverageCost());
}
