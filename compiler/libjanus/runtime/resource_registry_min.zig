// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Resource Registry for :min Profile
//! Task 2.1 - Implement basic resource registry for `:min` profile
//!
//! This module provides O(1) resource tracking for the minimal profile,
//! focusing on simplicity, performance, and zero-overhead resource management.

const std = @import("std");
const Allocator = std.mem.Allocator;
const UsingStmt = @import("../ast/using_stmt.zig").UsingStmt;

/// Minimal resource registry for :min profile
/// Optimized for single-threaded, deterministic resource management
pub const ResourceRegistryMin = struct {
    /// Stack-based resource frames for O(1) operations
    frame_stack: FrameStack,
    /// Current active frame
    current_frame: ?*ResourceFrame,
    /// Allocator for frame management
    allocator: Allocator,
    /// Registry statistics
    stats: RegistryStats,
    /// Configuration flags
    config: RegistryConfig,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .frame_stack = FrameStack.init(allocator),
            .current_frame = null,
            .allocator = allocator,
            .stats = RegistryStats{},
            .config = RegistryConfig.forMinProfile(),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up any remaining frames
        while (self.current_frame) |frame| {
            self.popFrame() catch {};
        }
        self.frame_stack.deinit();
    }

    /// Push a new resource frame (entering a new scope)
    pub fn pushFrame(self: *Self) !*ResourceFrame {
        const frame = try self.frame_stack.allocateFrame();
        frame.parent = self.current_frame;
        self.current_frame = frame;

        self.stats.total_frames_created += 1;
        return frame;
    }

    /// Pop the current resource frame (exiting scope)
    pub fn popFrame(self: *Self) !void {
        const frame = self.current_frame orelse return error.NoActiveFrame;

        // Execute cleanup for all resources in LIFO order
        try self.cleanupFrame(frame);

        // Restore parent frame
        self.current_frame = frame.parent;

        // Deallocate frame
        self.frame_stack.deallocateFrame(frame);

        self.stats.total_frames_destroyed += 1;
    }

    /// Register a resource in the current frame
    pub fn registerResource(self: *Self, resource_id: u64, cleanup_fn: CleanupFunction, resource_ptr: *anyopaque) !void {
        const frame = self.current_frame orelse return error.NoActiveFrame;

        try frame.addResource(ResourceEntry{
            .resource_id = resource_id,
            .cleanup_fn = cleanup_fn,
            .resource_ptr = resource_ptr,
            .registration_order = frame.next_order_id,
        });

        frame.next_order_id += 1;
        self.stats.total_resources_registered += 1;
    }

    /// Unregister a resource (for manual cleanup)
    pub fn unregisterResource(self: *Self, resource_id: u64) !void {
        const frame = self.current_frame orelse return error.NoActiveFrame;

        if (frame.removeResource(resource_id)) {
            self.stats.total_resources_unregistered += 1;
        } else {
            return error.ResourceNotFound;
        }
    }

    /// Check if a resource is registered
    pub fn isResourceRegistered(self: *Self, resource_id: u64) bool {
        var current = self.current_frame;
        while (current) |frame| {
            if (frame.hasResource(resource_id)) {
                return true;
            }
            current = frame.parent;
        }
        return false;
    }

    /// Get the current frame depth
    pub fn getFrameDepth(self: *Self) u32 {
        var depth: u32 = 0;
        var current = self.current_frame;
        while (current) |frame| {
            depth += 1;
            current = frame.parent;
        }
        return depth;
    }

    /// Execute cleanup for a frame in LIFO order
    fn cleanupFrame(self: *Self, frame: *ResourceFrame) !void {
        const start_time = std.time.nanoTimestamp();

        // Sort resources by registration order (descending for LIFO)
        frame.sortResourcesLIFO();

        var cleanup_errors = std.ArrayList(CleanupError).init(self.allocator);
        defer cleanup_errors.deinit();

        // Execute cleanup in LIFO order
        for (frame.resources.items) |resource| {
            const cleanup_start = std.time.nanoTimestamp();

            resource.cleanup_fn(resource.resource_ptr) catch |err| {
                try cleanup_errors.append(CleanupError{
                    .resource_id = resource.resource_id,
                    .error_type = err,
                    .cleanup_time_ns = std.time.nanoTimestamp() - cleanup_start,
                });
                self.stats.cleanup_errors += 1;
            };

            self.stats.total_cleanups_executed += 1;
        }

        const total_cleanup_time = std.time.nanoTimestamp() - start_time;
        self.updateCleanupStats(total_cleanup_time, cleanup_errors.items.len);

        // Handle cleanup errors if any occurred
        if (cleanup_errors.items.len > 0) {
            try self.handleCleanupErrors(cleanup_errors.items);
        }
    }

    /// Handle cleanup errors according to :min profile policy
    fn handleCleanupErrors(self: *Self, errors: []const CleanupError) !void {
        if (errors.len == 1) {
            // Single error - propagate directly
            return errors[0].error_type;
        } else {
            // Multiple errors - create aggregate error
            return error.MultipleCleanupFailures;
        }
    }

    /// Update cleanup performance statistics
    fn updateCleanupStats(self: *Self, cleanup_time_ns: u64, error_count: usize) void {
        self.stats.total_cleanup_time_ns += cleanup_time_ns;

        // Update running average
        const total_cleanups = self.stats.total_frames_destroyed;
        if (total_cleanups > 0) {
            self.stats.average_cleanup_time_ns = self.stats.total_cleanup_time_ns / total_cleanups;
        }

        // Track maximum cleanup time
        if (cleanup_time_ns > self.stats.max_cleanup_time_ns) {
            self.stats.max_cleanup_time_ns = cleanup_time_ns;
        }

        // Update error rate
        if (error_count > 0) {
            self.stats.frames_with_errors += 1;
        }
    }

    /// Get registry statistics
    pub fn getStats(self: *Self) RegistryStats {
        return self.stats;
    }

    /// Validate registry invariants (debug mode)
    pub fn validateInvariants(self: *Self) !void {
        if (!self.config.enable_validation) return;

        // Check frame stack consistency
        var frame_count: u32 = 0;
        var current = self.current_frame;
        while (current) |frame| {
            frame_count += 1;

            // Validate frame integrity
            try frame.validateIntegrity();

            // Check for cycles in parent chain
            if (frame_count > self.config.max_frame_depth) {
                return error.FrameStackCorruption;
            }

            current = frame.parent;
        }
    }
};

/// Resource frame for scope-based resource management
const ResourceFrame = struct {
    /// Parent frame (null for root frame)
    parent: ?*ResourceFrame,
    /// Resources in this frame
    resources: std.ArrayList(ResourceEntry),
    /// Next order ID for LIFO tracking
    next_order_id: u32,
    /// Frame creation timestamp
    created_at: i64,
    /// Allocator for resource list
    allocator: Allocator,

    pub fn init(allocator: Allocator) ResourceFrame {
        return ResourceFrame{
            .parent = null,
            .resources = std.ArrayList(ResourceEntry).init(allocator),
            .next_order_id = 0,
            .created_at = std.time.milliTimestamp(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ResourceFrame) void {
        self.resources.deinit();
    }

    /// Add a resource to this frame
    pub fn addResource(self: *ResourceFrame, resource: ResourceEntry) !void {
        try self.resources.append(resource);
    }

    /// Remove a resource from this frame
    pub fn removeResource(self: *ResourceFrame, resource_id: u64) bool {
        for (self.resources.items, 0..) |resource, i| {
            if (resource.resource_id == resource_id) {
                _ = self.resources.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Check if a resource exists in this frame
    pub fn hasResource(self: *ResourceFrame, resource_id: u64) bool {
        for (self.resources.items) |resource| {
            if (resource.resource_id == resource_id) {
                return true;
            }
        }
        return false;
    }

    /// Sort resources in LIFO order (reverse registration order)
    pub fn sortResourcesLIFO(self: *ResourceFrame) void {
        std.sort.sort(ResourceEntry, self.resources.items, {}, struct {
            fn lessThan(context: void, a: ResourceEntry, b: ResourceEntry) bool {
                _ = context;
                return a.registration_order > b.registration_order; // Descending order
            }
        }.lessThan);
    }

    /// Validate frame integrity
    pub fn validateIntegrity(self: *ResourceFrame) !void {
        // Check for duplicate resource IDs
        var seen_ids = std.HashMap(u64, void, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage).init(self.allocator);
        defer seen_ids.deinit();

        for (self.resources.items) |resource| {
            if (seen_ids.contains(resource.resource_id)) {
                return error.DuplicateResourceId;
            }
            try seen_ids.put(resource.resource_id, {});
        }

        // Validate registration order sequence
        for (self.resources.items, 0..) |resource, i| {
            if (resource.registration_order >= self.next_order_id) {
                return error.InvalidRegistrationOrder;
            }
        }
    }
};

/// Resource entry in a frame
const ResourceEntry = struct {
    /// Unique resource identifier
    resource_id: u64,
    /// Cleanup function pointer
    cleanup_fn: CleanupFunction,
    /// Pointer to the actual resource
    resource_ptr: *anyopaque,
    /// Registration order for LIFO cleanup
    registration_order: u32,
};

/// Cleanup function signature
pub const CleanupFunction = *const fn (resource_ptr: *anyopaque) anyerror!void;

/// Stack for managing resource frames
const FrameStack = struct {
    /// Pre-allocated frame pool for O(1) allocation
    frame_pool: std.ArrayList(*ResourceFrame),
    /// Free frames available for reuse
    free_frames: std.ArrayList(*ResourceFrame),
    /// Allocator for frame pool
    allocator: Allocator,

    const INITIAL_POOL_SIZE = 16;
    const MAX_POOL_SIZE = 1024;

    pub fn init(allocator: Allocator) FrameStack {
        return FrameStack{
            .frame_pool = std.ArrayList(*ResourceFrame).init(allocator),
            .free_frames = std.ArrayList(*ResourceFrame).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FrameStack) void {
        // Clean up all frames in pool
        for (self.frame_pool.items) |frame| {
            frame.deinit();
            self.allocator.destroy(frame);
        }
        self.frame_pool.deinit();
        self.free_frames.deinit();
    }

    /// Allocate a frame (O(1) from pool or O(1) allocation)
    pub fn allocateFrame(self: *FrameStack) !*ResourceFrame {
        if (self.free_frames.items.len > 0) {
            // Reuse from pool
            const frame = self.free_frames.pop();
            frame.resources.clearRetainingCapacity();
            frame.next_order_id = 0;
            frame.created_at = std.time.milliTimestamp();
            return frame;
        } else {
            // Allocate new frame
            const frame = try self.allocator.create(ResourceFrame);
            frame.* = ResourceFrame.init(self.allocator);
            try self.frame_pool.append(frame);
            return frame;
        }
    }

    /// Deallocate a frame (O(1) return to pool)
    pub fn deallocateFrame(self: *FrameStack, frame: *ResourceFrame) void {
        // Return to free pool if not at capacity
        if (self.free_frames.items.len < MAX_POOL_SIZE) {
            frame.parent = null;
            self.free_frames.append(frame) catch {
                // If append fails, just let it be garbage collected
            };
        }
        // If pool is full, frame will be cleaned up in deinit()
    }
};

/// Registry statistics for monitoring
pub const RegistryStats = struct {
    /// Total frames created
    total_frames_created: u64 = 0,
    /// Total frames destroyed
    total_frames_destroyed: u64 = 0,
    /// Total resources registered
    total_resources_registered: u64 = 0,
    /// Total resources unregistered
    total_resources_unregistered: u64 = 0,
    /// Total cleanups executed
    total_cleanups_executed: u64 = 0,
    /// Total cleanup errors
    cleanup_errors: u64 = 0,
    /// Frames that had cleanup errors
    frames_with_errors: u64 = 0,
    /// Total cleanup time (nanoseconds)
    total_cleanup_time_ns: u64 = 0,
    /// Average cleanup time per frame
    average_cleanup_time_ns: u64 = 0,
    /// Maximum cleanup time observed
    max_cleanup_time_ns: u64 = 0,

    /// Calculate cleanup success rate
    pub fn getCleanupSuccessRate(self: RegistryStats) f64 {
        if (self.total_cleanups_executed == 0) return 1.0;
        const successful = self.total_cleanups_executed - self.cleanup_errors;
        return @intToFloat(f64, successful) / @intToFloat(f64, self.total_cleanups_executed);
    }

    /// Check if performance targets are met
    pub fn meetsPerformanceTargets(self: RegistryStats) bool {
        const max_cleanup_time_ms = @intToFloat(f64, self.max_cleanup_time_ns) / 1_000_000.0;
        return max_cleanup_time_ms <= 1.0; // Sub-millisecond target
    }
};

/// Registry configuration
const RegistryConfig = struct {
    /// Enable validation checks (debug mode)
    enable_validation: bool,
    /// Maximum frame depth before error
    max_frame_depth: u32,
    /// Enable performance monitoring
    enable_performance_monitoring: bool,

    pub fn forMinProfile() RegistryConfig {
        return RegistryConfig{
            .enable_validation = false, // Disabled for performance in :min
            .max_frame_depth = 1000,
            .enable_performance_monitoring = true,
        };
    }

    pub fn forDebug() RegistryConfig {
        return RegistryConfig{
            .enable_validation = true,
            .max_frame_depth = 100,
            .enable_performance_monitoring = true,
        };
    }
};

/// Cleanup error information
const CleanupError = struct {
    resource_id: u64,
    error_type: anyerror,
    cleanup_time_ns: u64,
};

/// Profile-specific activation for :min
pub const MinProfileActivation = struct {
    /// Check if we're running in :min profile
    pub fn isMinProfile() bool {
        // This would check the current compilation profile
        // For now, assume we're in :min profile
        return true;
    }

    /// Initialize registry only if in :min profile
    pub fn initIfMinProfile(allocator: Allocator) ?ResourceRegistryMin {
        if (isMinProfile()) {
            return ResourceRegistryMin.init(allocator);
        }
        return null;
    }

    /// Regression pinning - ensure no performance degradation
    pub fn validatePerformanceRegression(old_stats: RegistryStats, new_stats: RegistryStats) !void {
        // Check that performance hasn't regressed by more than 5%
        const old_avg_ms = @intToFloat(f64, old_stats.average_cleanup_time_ns) / 1_000_000.0;
        const new_avg_ms = @intToFloat(f64, new_stats.average_cleanup_time_ns) / 1_000_000.0;

        if (new_avg_ms > old_avg_ms * 1.05) {
            return error.PerformanceRegression;
        }

        // Check that success rate hasn't decreased
        if (new_stats.getCleanupSuccessRate() < old_stats.getCleanupSuccessRate() * 0.95) {
            return error.ReliabilityRegression;
        }
    }
};

// Tests
test "ResourceRegistryMin - basic frame operations" {
    const allocator = std.testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    // Initially no frames
    try std.testing.expect(registry.getFrameDepth() == 0);

    // Push a frame
    const frame1 = try registry.pushFrame();
    try std.testing.expect(registry.getFrameDepth() == 1);
    try std.testing.expect(registry.current_frame == frame1);

    // Push another frame
    const frame2 = try registry.pushFrame();
    try std.testing.expect(registry.getFrameDepth() == 2);
    try std.testing.expect(registry.current_frame == frame2);
    try std.testing.expect(frame2.parent == frame1);

    // Pop frames
    try registry.popFrame();
    try std.testing.expect(registry.getFrameDepth() == 1);
    try std.testing.expect(registry.current_frame == frame1);

    try registry.popFrame();
    try std.testing.expect(registry.getFrameDepth() == 0);
    try std.testing.expect(registry.current_frame == null);
}

test "ResourceRegistryMin - resource registration" {
    const allocator = std.testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    const frame = try registry.pushFrame();

    // Mock cleanup function
    const mockCleanup = struct {
        fn cleanup(ptr: *anyopaque) !void {
            const resource = @ptrCast(*u32, @alignCast(@alignOf(u32), ptr));
            resource.* = 999; // Mark as cleaned up
        }
    }.cleanup;

    var test_resource: u32 = 42;

    // Register resource
    try registry.registerResource(1, mockCleanup, &test_resource);
    try std.testing.expect(registry.isResourceRegistered(1));
    try std.testing.expect(!registry.isResourceRegistered(2));

    // Unregister resource
    try registry.unregisterResource(1);
    try std.testing.expect(!registry.isResourceRegistered(1));
}

test "ResourceRegistryMin - LIFO cleanup order" {
    const allocator = std.testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    var cleanup_order = std.ArrayList(u32).init(allocator);
    defer cleanup_order.deinit();

    const frame = try registry.pushFrame();

    // Mock cleanup that records order
    const MockCleanup = struct {
        order: *std.ArrayList(u32),
        id: u32,

        fn cleanup(ptr: *anyopaque) !void {
            const self = @ptrCast(*@This(), @alignCast(@alignOf(@This()), ptr));
            try self.order.append(self.id);
        }
    };

    var cleanup1 = MockCleanup{ .order = &cleanup_order, .id = 1 };
    var cleanup2 = MockCleanup{ .order = &cleanup_order, .id = 2 };
    var cleanup3 = MockCleanup{ .order = &cleanup_order, .id = 3 };

    // Register resources in order 1, 2, 3
    try registry.registerResource(1, MockCleanup.cleanup, &cleanup1);
    try registry.registerResource(2, MockCleanup.cleanup, &cleanup2);
    try registry.registerResource(3, MockCleanup.cleanup, &cleanup3);

    // Pop frame should cleanup in LIFO order: 3, 2, 1
    try registry.popFrame();

    try std.testing.expect(cleanup_order.items.len == 3);
    try std.testing.expect(cleanup_order.items[0] == 3);
    try std.testing.expect(cleanup_order.items[1] == 2);
    try std.testing.expect(cleanup_order.items[2] == 1);
}

test "ResourceRegistryMin - performance validation" {
    const allocator = std.testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    const start_time = std.time.nanoTimestamp();

    // Simulate rapid frame operations
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        _ = try registry.pushFrame();
        try registry.popFrame();
    }

    const end_time = std.time.nanoTimestamp();
    const elapsed_ms = @intToFloat(f64, end_time - start_time) / 1_000_000.0;

    // Should complete 1000 frame operations in under 1ms
    try std.testing.expect(elapsed_ms < 1.0);

    const stats = registry.getStats();
    try std.testing.expect(stats.meetsPerformanceTargets());
}

test "ResourceRegistryMin - profile activation" {
    const allocator = std.testing.allocator;

    // Test profile-specific initialization
    if (MinProfileActivation.initIfMinProfile(allocator)) |registry| {
        var reg = registry;
        defer reg.deinit();

        try std.testing.expect(reg.config.enable_validation == false); // :min optimizations
        try std.testing.expect(reg.config.enable_performance_monitoring == true);
    }
}

test "ResourceRegistryMin - O(1) operations validation" {
    const allocator = std.testing.allocator;

    var registry = ResourceRegistryMin.init(allocator);
    defer registry.deinit();

    // Test that operations remain O(1) regardless of frame depth
    const depths = [_]u32{ 1, 10, 100 };

    for (depths) |depth| {
        // Build frame stack
        var i: u32 = 0;
        while (i < depth) : (i += 1) {
            _ = try registry.pushFrame();
        }

        const start_time = std.time.nanoTimestamp();

        // These operations should be O(1)
        _ = try registry.pushFrame();
        try registry.registerResource(i, struct {
            fn cleanup(ptr: *anyopaque) !void {
                _ = ptr;
            }
        }.cleanup, @intToPtr(*anyopaque, 0x1000));
        try registry.popFrame();

        const end_time = std.time.nanoTimestamp();
        const elapsed_ns = end_time - start_time;

        // Should complete in under 1000ns regardless of depth
        try std.testing.expect(elapsed_ns < 1000);

        // Clean up frames
        while (registry.getFrameDepth() > 0) {
            try registry.popFrame();
        }
    }
}
