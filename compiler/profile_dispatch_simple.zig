// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("astdb/astdb.zig");
const SemanticAnalyzer = @import("semantic_analyzer.zig");

// Simplified Profile-Aware Dispatch Integration
// Minimal working version to demonstrate the concept

const Profile = SemanticAnalyzer.Profile;

/// Dispatch strategy for function calls
pub const DispatchStrategy = enum {
    static_call, // Direct function call
    profile_dispatch, // Profile-aware tri-signature dispatch
};

/// Dispatch resolution result
pub const DispatchResolution = struct {
    strategy: DispatchStrategy,
    target_function: []const u8,
    inject_context: bool,
    inject_capability: bool,
    cost_estimate: u32,
};

/// Simple profile-aware dispatch resolver
pub const SimpleDispatchResolver = struct {
    const Self = @This();

    profile: Profile,

    pub fn init(profile: Profile) Self {
        return Self{ .profile = profile };
    }

    /// Resolve dispatch for a function call
    pub fn resolveDispatch(self: *Self, function_name: []const u8, allocator: std.mem.Allocator) !DispatchResolution {
        // Check if this is a standard library function
        if (self.isStandardLibraryFunction(function_name)) {
            return try self.resolveStandardLibraryDispatch(function_name, allocator);
        }

        // User function - direct call
        const target_function = try std.fmt.allocPrint(allocator, "janus_user_{s}", .{function_name});
        return DispatchResolution{
            .strategy = .static_call,
            .target_function = target_function,
            .inject_context = false,
            .inject_capability = false,
            .cost_estimate = 1,
        };
    }

    /// Check if function is in standard library
    fn isStandardLibraryFunction(self: *Self, function_name: []const u8) bool {
        _ = self;
        return std.mem.eql(u8, function_name, "print") or
            std.mem.eql(u8, function_name, "eprint");
    }

    /// Resolve standard library function dispatch
    fn resolveStandardLibraryDispatch(self: *Self, function_name: []const u8, allocator: std.mem.Allocator) !DispatchResolution {
        const profile_suffix = switch (self.profile) {
            .min => "min",
            .go => "go",
            .full => "full",
        };

        const target_function = try std.fmt.allocPrint(allocator, "janus_{s}_{s}", .{ function_name, profile_suffix });

        return DispatchResolution{
            .strategy = .profile_dispatch,
            .target_function = target_function,
            .inject_context = self.profile == .go,
            .inject_capability = self.profile == .full,
            .cost_estimate = switch (self.profile) {
                .min => 1,
                .go => 3,
                .full => 5,
            },
        };
    }
};

// Test the simple dispatch resolver
const testing = std.testing;

test "SimpleDispatchResolver: basic functionality" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test :min profile
    var resolver_min = SimpleDispatchResolver.init(.min);
    const resolution_min = try resolver_min.resolveDispatch("print", allocator);

    try testing.expectEqual(DispatchStrategy.profile_dispatch, resolution_min.strategy);
    try testing.expectEqualStrings("janus_print_min", resolution_min.target_function);
    try testing.expect(!resolution_min.inject_context);
    try testing.expect(!resolution_min.inject_capability);
    try testing.expectEqual(@as(u32, 1), resolution_min.cost_estimate);

    // Test :go profile
    var resolver_go = SimpleDispatchResolver.init(.go);
    const resolution_go = try resolver_go.resolveDispatch("print", allocator);

    try testing.expectEqual(DispatchStrategy.profile_dispatch, resolution_go.strategy);
    try testing.expectEqualStrings("janus_print_go", resolution_go.target_function);
    try testing.expect(resolution_go.inject_context);
    try testing.expect(!resolution_go.inject_capability);
    try testing.expectEqual(@as(u32, 3), resolution_go.cost_estimate);

    // Test :full profile
    var resolver_full = SimpleDispatchResolver.init(.full);
    const resolution_full = try resolver_full.resolveDispatch("print", allocator);

    try testing.expectEqual(DispatchStrategy.profile_dispatch, resolution_full.strategy);
    try testing.expectEqualStrings("janus_print_full", resolution_full.target_function);
    try testing.expect(!resolution_full.inject_context);
    try testing.expect(resolution_full.inject_capability);
    try testing.expectEqual(@as(u32, 5), resolution_full.cost_estimate);
}

test "SimpleDispatchResolver: user function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var resolver = SimpleDispatchResolver.init(.min);
    const resolution = try resolver.resolveDispatch("my_function", allocator);

    try testing.expectEqual(DispatchStrategy.static_call, resolution.strategy);
    try testing.expectEqualStrings("janus_user_my_function", resolution.target_function);
    try testing.expect(!resolution.inject_context);
    try testing.expect(!resolution.inject_capability);
    try testing.expectEqual(@as(u32, 1), resolution.cost_estimate);
}
