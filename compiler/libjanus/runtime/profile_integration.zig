// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Profile Integration for Resource Management
//! Task 2.1 - Profile-gated registry activation with regression pinning
//!
//! This module provides profile-aware resource management that activates
//! different registry implementations based on the current compilation profile.

const std = @import("std");
const compat_time = @import("compat_time");
const Allocator = std.mem.Allocator;
const ResourceRegistryMin = @import("resource_registry_min.zig").ResourceRegistryMin;
const UsingStmt = @import("../ast/using_stmt.zig").UsingStmt;

/// Profile-aware resource manager
pub const ProfileResourceManager = struct {
    allocator: Allocator,
    current_profile: Profile,
    min_registry: ?ResourceRegistryMin,
    performance_baseline: ?PerformanceBaseline,

    const Self = @This();

    pub fn init(allocator: Allocator, profile: Profile) !Self {
        var manager = Self{
            .allocator = allocator,
            .current_profile = profile,
            .min_registry = null,
            .performance_baseline = null,
        };

        // Initialize profile-specific registry
        try manager.initializeForProfile();

        return manager;
    }

    pub fn deinit(self: *Self) void {
        if (self.min_registry) |*registry| {
            registry.deinit();
        }
    }

    /// Initialize registry for the current profile
    fn initializeForProfile(self: *Self) !void {
        switch (self.current_profile) {
            .min => {
                self.min_registry = ResourceRegistryMin.init(self.allocator);

                // Load performance baseline for regression detection
                self.performance_baseline = try self.loadPerformanceBaseline();
            },
            .go => {
                // :go profile would use thread-local registries
                // Not implemented in this task
            },
            .elixir => {
                // :elixir profile would use actor-aware registries
                // Not implemented in this task
            },
            .full => {
                // :full profile would use capability-gated registries
                // Not implemented in this task
            },
        }
    }

    /// Enter a new resource scope
    pub fn enterScope(self: *Self) !ResourceScope {
        return switch (self.current_profile) {
            .min => blk: {
                if (self.min_registry) |*registry| {
                    const frame = try registry.pushFrame();
                    break :blk ResourceScope{
                        .profile = .min,
                        .min_frame = frame,
                        .scope_id = self.generateScopeId(),
                    };
                } else {
                    return error.RegistryNotInitialized;
                }
            },
            else => error.ProfileNotImplemented,
        };
    }

    /// Exit the current resource scope
    pub fn exitScope(self: *Self, scope: ResourceScope) !void {
        switch (scope.profile) {
            .min => {
                if (self.min_registry) |*registry| {
                    try registry.popFrame();

                    // Check for performance regression
                    try self.checkPerformanceRegression();
                } else {
                    return error.RegistryNotInitialized;
                }
            },
            else => return error.ProfileNotImplemented,
        }
    }

    /// Register a resource in the current scope
    pub fn registerResource(self: *Self, resource_id: u64, cleanup_fn: ResourceRegistryMin.CleanupFunction, resource_ptr: *anyopaque) !void {
        switch (self.current_profile) {
            .min => {
                if (self.min_registry) |*registry| {
                    try registry.registerResource(resource_id, cleanup_fn, resource_ptr);
                } else {
                    return error.RegistryNotInitialized;
                }
            },
            else => return error.ProfileNotImplemented,
        }
    }

    /// Validate that using statement is compatible with current profile
    pub fn validateUsingStatement(self: *Self, using_stmt: *const UsingStmt) !void {
        if (!using_stmt.isValidForProfile(self.current_profile)) {
            return error.IncompatibleWithProfile;
        }

        // Profile-specific validation
        switch (self.current_profile) {
            .min => {
                // :min profile doesn't support shared resources
                if (using_stmt.flags.is_shared) {
                    return error.SharedResourcesNotSupportedInMin;
                }

                // Validate performance constraints
                try self.validateMinProfileConstraints(using_stmt);
            },
            else => {
                // Other profiles not implemented yet
            },
        }
    }

    /// Get current registry statistics
    pub fn getStats(self: *Self) !RegistryStats {
        return switch (self.current_profile) {
            .min => blk: {
                if (self.min_registry) |*registry| {
                    break :blk RegistryStats{
                        .profile = .min,
                        .min_stats = registry.getStats(),
                    };
                } else {
                    return error.RegistryNotInitialized;
                }
            },
            else => error.ProfileNotImplemented,
        };
    }

    /// Check for performance regression against baseline
    fn checkPerformanceRegression(self: *Self) !void {
        if (self.performance_baseline) |baseline| {
            if (self.min_registry) |*registry| {
                const current_stats = registry.getStats();

                // Use the regression validation from the min registry
                const MinProfileActivation = @import("resource_registry_min.zig").MinProfileActivation;
                try MinProfileActivation.validatePerformanceRegression(baseline.min_stats, current_stats);
            }
        }
    }

    /// Validate constraints specific to :min profile
    fn validateMinProfileConstraints(self: *Self, using_stmt: *const UsingStmt) !void {
        _ = self;

        // Check for features that would degrade :min performance
        if (using_stmt.semantic_info) |info| {
            // Too many dependencies can slow down cleanup
            if (info.dependencies.len > 10) {
                return error.TooManyDependenciesForMin;
            }

            // Complex effects might not be suitable for :min
            if (info.open_effects.len + info.close_effects.len > 5) {
                return error.TooManyEffectsForMin;
            }
        }
    }

    /// Load performance baseline for regression detection
    fn loadPerformanceBaseline(self: *Self) !?PerformanceBaseline {
        _ = self;

        // In a real implementation, this would load from a file or database
        // For now, return a reasonable baseline
        return PerformanceBaseline{
            .min_stats = ResourceRegistryMin.RegistryStats{
                .average_cleanup_time_ns = 500_000, // 0.5ms baseline
                .max_cleanup_time_ns = 1_000_000, // 1ms max
            },
        };
    }

    /// Generate unique scope ID
    fn generateScopeId(self: *Self) u64 {
        _ = self;
        return @intCast(u64, compat_time.nanoTimestamp());
    }
};

/// Profile enumeration
pub const Profile = enum {
    min,
    go,
    elixir,
    full,

    /// Get profile from string
    pub fn fromString(profile_str: []const u8) ?Profile {
        if (std.mem.eql(u8, profile_str, "min")) return .min;
        if (std.mem.eql(u8, profile_str, "go")) return .go;
        if (std.mem.eql(u8, profile_str, "elixir")) return .elixir;
        if (std.mem.eql(u8, profile_str, "full")) return .full;
        return null;
    }

    /// Get profile name
    pub fn toString(self: Profile) []const u8 {
        return switch (self) {
            .min => "min",
            .go => "go",
            .elixir => "elixir",
            .full => "full",
        };
    }
};

/// Resource scope handle
pub const ResourceScope = struct {
    profile: Profile,
    scope_id: u64,

    // Profile-specific frame handles
    min_frame: ?*@import("resource_registry_min.zig").ResourceFrame = null,
    // go_frame: ?*GoResourceFrame = null,     // Future
    // elixir_frame: ?*ElixirResourceFrame = null, // Future
    // full_frame: ?*FullResourceFrame = null, // Future
};

/// Registry statistics across profiles
pub const RegistryStats = union(Profile) {
    min: ResourceRegistryMin.RegistryStats,
    // go: GoRegistryStats,     // Future
    // elixir: ElixirRegistryStats, // Future
    // full: FullRegistryStats, // Future
};

/// Performance baseline for regression detection
const PerformanceBaseline = struct {
    min_stats: ResourceRegistryMin.RegistryStats,
    // go_stats: GoRegistryStats,     // Future
    // elixir_stats: ElixirRegistryStats, // Future
    // full_stats: FullRegistryStats, // Future
};

/// Profile detection utilities
pub const ProfileDetection = struct {
    /// Detect current profile from compilation flags
    pub fn detectCurrentProfile() Profile {
        // In a real implementation, this would check compilation flags
        // For now, default to :min for testing
        return .min;
    }

    /// Check if profile supports feature
    pub fn supportsFeature(profile: Profile, feature: Feature) bool {
        return switch (feature) {
            .shared_resources => switch (profile) {
                .min => false,
                .go, .elixir, .full => true,
            },
            .thread_local_stacks => switch (profile) {
                .min => false,
                .go, .elixir, .full => true,
            },
            .actor_supervision => switch (profile) {
                .min, .go => false,
                .elixir, .full => true,
            },
            .capability_gating => switch (profile) {
                .min, .go, .elixir => false,
                .full => true,
            },
        };
    }

    const Feature = enum {
        shared_resources,
        thread_local_stacks,
        actor_supervision,
        capability_gating,
    };
};

/// Integration with using statement semantic analysis
pub const UsingIntegration = struct {
    /// Create profile-aware resource manager for using statement resolution
    pub fn createManagerForUsing(allocator: Allocator, using_stmt: *const UsingStmt) !ProfileResourceManager {
        const profile = ProfileDetection.detectCurrentProfile();

        var manager = try ProfileResourceManager.init(allocator, profile);

        // Validate using statement against profile
        try manager.validateUsingStatement(using_stmt);

        return manager;
    }

    /// Generate profile-specific cleanup code
    pub fn generateCleanupCode(profile: Profile, using_stmt: *const UsingStmt, allocator: Allocator) ![]const u8 {
        return switch (profile) {
            .min => try generateMinCleanupCode(using_stmt, allocator),
            else => error.ProfileNotImplemented,
        };
    }

    /// Generate cleanup code for :min profile
    fn generateMinCleanupCode(using_stmt: *const UsingStmt, allocator: Allocator) ![]const u8 {
        // Generate simple defer-based cleanup for :min profile
        return std.fmt.allocPrint(allocator,
            \\defer {{
            \\    {s}.close() catch |err| {{
            \\        // :min profile - simple error propagation
            \\        return err;
            \\    }};
            \\}}
        , .{using_stmt.binding.name});
    }
};

// Tests
test "ProfileResourceManager - min profile initialization" {
    const allocator = std.testing.allocator;

    var manager = try ProfileResourceManager.init(allocator, .min);
    defer manager.deinit();

    try std.testing.expect(manager.current_profile == .min);
    try std.testing.expect(manager.min_registry != null);
}

test "ProfileResourceManager - scope operations" {
    const allocator = std.testing.allocator;

    var manager = try ProfileResourceManager.init(allocator, .min);
    defer manager.deinit();

    // Enter scope
    const scope = try manager.enterScope();
    try std.testing.expect(scope.profile == .min);
    try std.testing.expect(scope.min_frame != null);

    // Exit scope
    try manager.exitScope(scope);
}

test "ProfileResourceManager - using statement validation" {
    const allocator = std.testing.allocator;

    var manager = try ProfileResourceManager.init(allocator, .min);
    defer manager.deinit();

    const astdb = @import("../astdb.zig");
    const span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 };

    // Valid using statement for :min
    const valid_flags = UsingStmt.UsingFlags{ .is_shared = false };
    const binding = UsingStmt.Binding{ .name = "resource", .span = span, .is_mutable = false };
    const valid_using = UsingStmt{
        .node_id = astdb.NodeId{ .id = 1 },
        .flags = valid_flags,
        .binding = binding,
        .type_annotation = null,
        .open_expr = @import("../astdb/ids.zig").CID{ .bytes = [_]u8{1} ** 32 },
        .block = @import("../astdb/ids.zig").CID{ .bytes = [_]u8{2} ** 32 },
    };

    // Should validate successfully
    try manager.validateUsingStatement(&valid_using);

    // Invalid using statement for :min (shared resource)
    const invalid_flags = UsingStmt.UsingFlags{ .is_shared = true };
    const invalid_using = UsingStmt{
        .node_id = astdb.NodeId{ .id = 4 },
        .flags = invalid_flags,
        .binding = binding,
        .type_annotation = null,
        .open_expr = @import("../astdb/ids.zig").CID{ .bytes = [_]u8{1} ** 32 },
        .block = @import("../astdb/ids.zig").CID{ .bytes = [_]u8{2} ** 32 },
    };

    // Should fail validation
    try std.testing.expectError(error.SharedResourcesNotSupportedInMin, manager.validateUsingStatement(&invalid_using));
}

test "ProfileDetection - feature support" {
    try std.testing.expect(!ProfileDetection.supportsFeature(.min, .shared_resources));
    try std.testing.expect(ProfileDetection.supportsFeature(.go, .shared_resources));
    try std.testing.expect(ProfileDetection.supportsFeature(.full, .capability_gating));
    try std.testing.expect(!ProfileDetection.supportsFeature(.min, .capability_gating));
}

test "Profile - string conversion" {
    try std.testing.expect(Profile.fromString("min") == .min);
    try std.testing.expect(Profile.fromString("go") == .go);
    try std.testing.expect(Profile.fromString("invalid") == null);

    try std.testing.expectEqualStrings("min", Profile.min.toString());
    try std.testing.expectEqualStrings("full", Profile.full.toString());
}

test "UsingIntegration - cleanup code generation" {
    const allocator = std.testing.allocator;

    const astdb = @import("../astdb.zig");
    const span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 };
    const flags = UsingStmt.UsingFlags{ .is_shared = false };
    const binding = UsingStmt.Binding{ .name = "file", .span = span, .is_mutable = false };

    const using_stmt = UsingStmt{
        .node_id = astdb.NodeId{ .id = 5 },
        .flags = flags,
        .binding = binding,
        .type_annotation = null,
        .open_expr = @import("../astdb/ids.zig").CID{ .bytes = [_]u8{1} ** 32 },
        .block = @import("../astdb/ids.zig").CID{ .bytes = [_]u8{2} ** 32 },
    };

    const cleanup_code = try UsingIntegration.generateCleanupCode(.min, &using_stmt, allocator);
    defer allocator.free(cleanup_code);

    // Should contain the resource name and simple error handling
    try std.testing.expect(std.mem.indexOf(u8, cleanup_code, "file.close()") != null);
    try std.testing.expect(std.mem.indexOf(u8, cleanup_code, "defer") != null);
}
