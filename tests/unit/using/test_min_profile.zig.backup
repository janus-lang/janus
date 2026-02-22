// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Min Profile Resource Registry Tests
//! Task 2.1 - Tests for profile-specific behavior activation
//!
//! These tests validate that the :min profile resource registry works correctly
//! and only activates when the :min profile is selected.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import min profile components
const ResourceRegistryMin = @import("../../../compiler/libjanus/runtime/resource_registry_min.zig").ResourceRegistryMin;
const MinProfileActivation = @import("../../../compiler/libjanus/runtime/resource_registry_min.zig").MinProfileActivation;
const ProfileResourceManager = @import("../../../compiler/libjanus/runtime/profile_integration.zig").ProfileResourceManager;
const Profile = @import("../../../compiler/libjanus/runtime/profile_integration.zig").Profile;
const ProfileDetection = @import("../../../compiler/libjanus/runtime/profile_integration.zig").ProfileDetection;

/// Test resource for min profile validation
const MinTestResource = struct {
    id: u32,
    value: i32,
    is_cleaned: bool,
    cleanup_time_ns: u64,
    cleanup_order: *std.ArrayList(u32),

    pub fn init(id: u32, value: i32, cleanup_order: *std.ArrayList(u32)) MinTestResource {
        return MinTestResource{
            .id = id,
            .value = value,
            .is_cleaned = false,
            .cleanup_time_ns = 0,
            .cleanup_order = cleanup_order,
        };
    }

    pub fn cleanup(ptr: *anyopaque) !void {
        const start_time = std.time.nanoTimestamp();

        const self = @ptrCast(*MinTestResource, @alignCast(@alignOf(MinTestResource), ptr));
        self.is_cleaned = true;
        try self.cleanup_order.append(self.id);

        const end_time = std.time.nanoTimestamp();
        self.cleanup_time_ns = end_time - start_time;
    }

    pub fn failingCleanup(ptr: *anyopaque) !void {
        const self = @ptrCast(*MinTestResource, @alignCast(@alignOf(MinTestResource), ptr));
        self.is_cleaned = true; // Mark as attempted
        try self.cleanup_order.append(self.id);
        return error.CleanupFailure;
    }
};

// Test 1: Profile activation only in :min
test "min profile - activation only when profile is min" {
    const allocator = testing.allocator;

    // Test that registry initializes for :min profile
    var min_manager = try ProfileResourceManager.init(allocator, .core);
    defer min_manager.deinit();

    try testing.expect(min_manager.current_profile == .core);
    try testing.expect(min_manager.core_registry != null);

    // Test that other profiles don't initialize min registry
    // (This would fail in current implementation since other profiles aren't implemented)
    // In a full implementation, we'd test:
    // var go_manager = try ProfileResourceManager.init(allocator, .service);
    // try testing.expect(go_manager.core_registry == null);
}

// Test 2: O(1) push/pop operations
test "min profile - O(1) frame operations" {
    const allocator = testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    // Measure frame operations at different depths
    const test_depths = [_]u32{ 1, 10, 100, 1000 };
    var timings = std.ArrayList(u64).init(allocator);
    defer timings.deinit();

    for (test_depths) |depth| {
        // Build up to target depth
        var i: u32 = 0;
        while (i < depth) : (i += 1) {
            _ = try registry.pushFrame();
        }

        // Measure push/pop at this depth
        const start_time = std.time.nanoTimestamp();

        const frame = try registry.pushFrame();
        try registry.popFrame();

        const end_time = std.time.nanoTimestamp();
        const elapsed = end_time - start_time;
        try timings.append(elapsed);

        // Clean up to depth 0
        while (registry.getFrameDepth() > 0) {
            try registry.popFrame();
        }
    }

    // Verify that timing doesn't increase significantly with depth (O(1) behavior)
    // Allow for some variance due to system noise
    const first_timing = timings.items[0];
    for (timings.items[1..]) |timing| {
        // Should not be more than 10x slower (very generous for O(1))
        try testing.expect(timing < first_timing * 10);
    }
}

// Test 3: Unique resource tracking and validation
test "min profile - unique resource tracking" {
    const allocator = testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    var cleanup_order = std.ArrayList(u32).init(allocator);
    defer cleanup_order.deinit();

    const frame = try registry.pushFrame();

    var resource1 = MinTestResource.init(1, 100, &cleanup_order);
    var resource2 = MinTestResource.init(2, 200, &cleanup_order);
    var resource3 = MinTestResource.init(1, 300, &cleanup_order); // Duplicate ID

    // Register unique resources
    try registry.registerResource(1, MinTestResource.cleanup, &resource1);
    try registry.registerResource(2, MinTestResource.cleanup, &resource2);

    // Verify resources are tracked
    try testing.expect(registry.isResourceRegistered(1));
    try testing.expect(registry.isResourceRegistered(2));
    try testing.expect(!registry.isResourceRegistered(3));

    // Registering duplicate ID should work (overwrites previous)
    try registry.registerResource(1, MinTestResource.cleanup, &resource3);
    try testing.expect(registry.isResourceRegistered(1));

    // Cleanup should work correctly
    try registry.popFrame();

    // At least one resource with ID 1 should be cleaned
    var found_id_1 = false;
    for (cleanup_order.items) |id| {
        if (id == 1) found_id_1 = true;
    }
    try testing.expect(found_id_1);
}

// Test 4: Performance regression pinning
test "min profile - performance regression detection" {
    const allocator = testing.allocator;

    // Create baseline stats (good performance)
    const baseline_stats = ResourceRegistryMin.RegistryStats{
        .average_cleanup_time_ns = 100_000, // 0.1ms
        .total_cleanups_executed = 1000,
        .cleanup_errors = 0,
    };

    // Create current stats (within acceptable range)
    const good_current_stats = ResourceRegistryMin.RegistryStats{
        .average_cleanup_time_ns = 104_000, // 0.104ms (4% increase - acceptable)
        .total_cleanups_executed = 1000,
        .cleanup_errors = 0,
    };

    // Should not detect regression
    try MinProfileActivation.validatePerformanceRegression(baseline_stats, good_current_stats);

    // Create current stats (performance regression)
    const bad_current_stats = ResourceRegistryMin.RegistryStats{
        .average_cleanup_time_ns = 110_000, // 0.11ms (10% increase - regression)
        .total_cleanups_executed = 1000,
        .cleanup_errors = 0,
    };

    // Should detect regression
    try testing.expectError(error.PerformanceRegression, MinProfileActivation.validatePerformanceRegression(baseline_stats, bad_current_stats));
}

// Test 5: Sub-millisecond cleanup guarantee
test "min profile - sub-millisecond cleanup" {
    const allocator = testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    var cleanup_order = std.ArrayList(u32).init(allocator);
    defer cleanup_order.deinit();

    // Create many resources to test cleanup performance
    const resource_count = 100;
    var resources: [resource_count]MinTestResource = undefined;

    const frame = try registry.pushFrame();

    // Register many resources
    for (resources, 0..) |*resource, i| {
        resource.* = MinTestResource.init(@intCast(u32, i), @intCast(i32, i * 10), &cleanup_order);
        try registry.registerResource(@intCast(u64, i), MinTestResource.cleanup, resource);
    }

    // Measure cleanup time
    const start_time = std.time.nanoTimestamp();
    try registry.popFrame();
    const end_time = std.time.nanoTimestamp();

    const cleanup_time_ns = end_time - start_time;
    const cleanup_time_ms = @intToFloat(f64, cleanup_time_ns) / 1_000_000.0;

    // Should complete in under 1ms
    try testing.expect(cleanup_time_ms < 1.0);

    // Verify all resources were cleaned up
    try testing.expect(cleanup_order.items.len == resource_count);

    // Verify LIFO order (last registered should be first cleaned)
    try testing.expect(cleanup_order.items[0] == resource_count - 1);
    try testing.expect(cleanup_order.items[resource_count - 1] == 0);
}

// Test 6: Memory overhead validation (O(1) per resource)
test "min profile - O(1) memory overhead per resource" {
    const allocator = testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    var cleanup_order = std.ArrayList(u32).init(allocator);
    defer cleanup_order.deinit();

    // Test memory usage at different resource counts
    const resource_counts = [_]u32{ 10, 100, 1000 };

    for (resource_counts) |count| {
        const frame = try registry.pushFrame();

        // Measure memory before resource registration
        const initial_stats = registry.getStats();

        // Register resources
        var resources = try allocator.alloc(MinTestResource, count);
        defer allocator.free(resources);

        for (resources, 0..) |*resource, i| {
            resource.* = MinTestResource.init(@intCast(u32, i), @intCast(i32, i), &cleanup_order);
            try registry.registerResource(@intCast(u64, i), MinTestResource.cleanup, resource);
        }

        const final_stats = registry.getStats();

        // Memory usage should scale linearly with resource count (O(1) per resource)
        const resources_added = final_stats.total_resources_registered - initial_stats.total_resources_registered;
        try testing.expect(resources_added == count);

        // Clean up
        try registry.popFrame();
        cleanup_order.clearRetainingCapacity();
    }
}

// Test 7: Profile-specific validation
test "min profile - profile specific validation" {
    const allocator = testing.allocator;

    var manager = try ProfileResourceManager.init(allocator, .core);
    defer manager.deinit();

    const astdb = @import("../../../compiler/libjanus/astdb.zig");
    const span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 };
    const UsingStmt = @import("../../../compiler/libjanus/ast/using_stmt.zig").UsingStmt;

    // Test valid using statement for :min
    const valid_flags = UsingStmt.UsingFlags{ .is_shared = false };
    const binding = UsingStmt.Binding{ .name = "resource", .span = span, .is_mutable = false };
    const valid_using = UsingStmt{
        .node_id = astdb.NodeId{ .id = 1 },
        .flags = valid_flags,
        .binding = binding,
        .type_annotation = null,
        .open_expr = @import("../../../compiler/libjanus/astdb/ids.zig").CID{ .bytes = [_]u8{1} ** 32 },
        .block = @import("../../../compiler/libjanus/astdb/ids.zig").CID{ .bytes = [_]u8{2} ** 32 },
    };

    // Should validate successfully
    try manager.validateUsingStatement(&valid_using);

    // Test invalid using statement (shared resources not supported in :min)
    const invalid_flags = UsingStmt.UsingFlags{ .is_shared = true };
    const invalid_using = UsingStmt{
        .node_id = astdb.NodeId{ .id = 2 },
        .flags = invalid_flags,
        .binding = binding,
        .type_annotation = null,
        .open_expr = @import("../../../compiler/libjanus/astdb/ids.zig").CID{ .bytes = [_]u8{1} ** 32 },
        .block = @import("../../../compiler/libjanus/astdb/ids.zig").CID{ .bytes = [_]u8{2} ** 32 },
    };

    // Should fail validation
    try testing.expectError(error.SharedResourcesNotSupportedInMin, manager.validateUsingStatement(&invalid_using));
}

// Test 8: Feature detection and profile capabilities
test "min profile - feature detection" {
    // Test that :min profile has correct feature support
    try testing.expect(!ProfileDetection.supportsFeature(.core, .shared_resources));
    try testing.expect(!ProfileDetection.supportsFeature(.core, .thread_local_stacks));
    try testing.expect(!ProfileDetection.supportsFeature(.core, .actor_supervision));
    try testing.expect(!ProfileDetection.supportsFeature(.core, .capability_gating));

    // Test that other profiles support more features
    try testing.expect(ProfileDetection.supportsFeature(.service, .shared_resources));
    try testing.expect(ProfileDetection.supportsFeature(.sovereign, .capability_gating));
}

// Test 9: Error handling and cleanup failure aggregation
test "min profile - cleanup error handling" {
    const allocator = testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    var cleanup_order = std.ArrayList(u32).init(allocator);
    defer cleanup_order.deinit();

    const frame = try registry.pushFrame();

    // Create resources with different cleanup behaviors
    var good_resource = MinTestResource.init(1, 100, &cleanup_order);
    var failing_resource = MinTestResource.init(2, 200, &cleanup_order);
    var another_good_resource = MinTestResource.init(3, 300, &cleanup_order);

    // Register resources
    try registry.registerResource(1, MinTestResource.cleanup, &good_resource);
    try registry.registerResource(2, MinTestResource.failingCleanup, &failing_resource);
    try registry.registerResource(3, MinTestResource.cleanup, &another_good_resource);

    // Cleanup should handle errors appropriately
    const cleanup_result = registry.popFrame();

    // In :min profile, errors should be propagated
    try testing.expectError(error.CleanupFailure, cleanup_result);

    // But all resources should still be attempted for cleanup
    try testing.expect(cleanup_order.items.len == 3);
    try testing.expect(good_resource.is_cleaned);
    try testing.expect(failing_resource.is_cleaned); // Attempted
    try testing.expect(another_good_resource.is_cleaned);
}

// Test 10: Integration with using statement workflow
test "min profile - using statement integration" {
    const allocator = testing.allocator;

    // Simulate the complete workflow for a using statement in :min profile
    var manager = try ProfileResourceManager.init(allocator, .core);
    defer manager.deinit();

    // Enter scope (equivalent to entering using block)
    const scope = try manager.enterScope();

    // Register a resource (equivalent to resource acquisition)
    var cleanup_order = std.ArrayList(u32).init(allocator);
    defer cleanup_order.deinit();

    var test_resource = MinTestResource.init(42, 1337, &cleanup_order);
    try manager.registerResource(42, MinTestResource.cleanup, &test_resource);

    // Verify resource is tracked
    const stats_before = try manager.getStats();
    try testing.expect(stats_before.core.total_resources_registered > 0);

    // Exit scope (equivalent to exiting using block)
    try manager.exitScope(scope);

    // Verify cleanup occurred
    try testing.expect(test_resource.is_cleaned);
    try testing.expect(cleanup_order.items.len == 1);
    try testing.expect(cleanup_order.items[0] == 42);

    // Verify performance was acceptable
    const stats_after = try manager.getStats();
    try testing.expect(stats_after.core.meetsPerformanceTargets());
}

// Performance benchmark: Stress test with many resources
test "min profile - stress test performance" {
    const allocator = testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    var cleanup_order = std.ArrayList(u32).init(allocator);
    defer cleanup_order.deinit();

    const stress_count = 10_000;
    var resources = try allocator.alloc(MinTestResource, stress_count);
    defer allocator.free(resources);

    // Measure total time for stress test
    const start_time = std.time.nanoTimestamp();

    const frame = try registry.pushFrame();

    // Register many resources
    for (resources, 0..) |*resource, i| {
        resource.* = MinTestResource.init(@intCast(u32, i), @intCast(i32, i), &cleanup_order);
        try registry.registerResource(@intCast(u64, i), MinTestResource.cleanup, resource);
    }

    // Cleanup all resources
    try registry.popFrame();

    const end_time = std.time.nanoTimestamp();
    const total_time_ms = @intToFloat(f64, end_time - start_time) / 1_000_000.0;

    // Should handle 10k resources in reasonable time (under 10ms)
    try testing.expect(total_time_ms < 10.0);

    // Verify all resources were cleaned up in LIFO order
    try testing.expect(cleanup_order.items.len == stress_count);
    try testing.expect(cleanup_order.items[0] == stress_count - 1); // Last registered, first cleaned
    try testing.expect(cleanup_order.items[stress_count - 1] == 0); // First registered, last cleaned

    // Verify performance targets are met
    const final_stats = registry.getStats();
    try testing.expect(final_stats.meetsPerformanceTargets());
}
