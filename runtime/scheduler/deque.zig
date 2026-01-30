// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Chase-Lev Work-Stealing Deque
//!
//! Lock-free double-ended queue for work-stealing schedulers.
//! Owner thread pushes/pops from bottom (LIFO for locality).
//! Stealers steal from top (FIFO for fairness).
//!
//! Based on: "Dynamic Circular Work-Stealing Deque" - Chase & Lev, SPAA 2005
//!
//! See: SPEC-021 Section 7 (Work-Stealing Algorithm)

const std = @import("std");
const Atomic = std.atomic.Value;

/// Work-stealing deque for task pointers
pub fn WorkStealingDeque(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Circular buffer of task pointers
        buffer: []Atomic(?*T),

        /// Bottom index (owner writes, stealers read)
        bottom: Atomic(isize),

        /// Top index (stealers CAS, owner reads)
        top: Atomic(isize),

        /// Capacity (power of 2)
        capacity: usize,

        /// Bit mask for circular indexing
        mask: usize,

        /// Allocator
        allocator: std.mem.Allocator,

        /// Initialize deque with given capacity (rounded to power of 2)
        pub fn init(allocator: std.mem.Allocator, min_capacity: usize) !Self {
            // Round up to power of 2
            const capacity = std.math.ceilPowerOfTwo(usize, min_capacity) catch min_capacity;

            const buffer = try allocator.alloc(Atomic(?*T), capacity);
            for (buffer) |*slot| {
                slot.* = Atomic(?*T).init(null);
            }

            return Self{
                .buffer = buffer,
                .bottom = Atomic(isize).init(0),
                .top = Atomic(isize).init(0),
                .capacity = capacity,
                .mask = capacity - 1,
                .allocator = allocator,
            };
        }

        /// Deallocate deque
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
        }

        /// Owner: Push task to bottom (O(1))
        ///
        /// Only called by the owner thread.
        /// Returns false if deque is full.
        pub fn push(self: *Self, task: *T) bool {
            const b = self.bottom.load(.monotonic);
            const t = self.top.load(.acquire);

            // Check if full
            if (b - t >= @as(isize, @intCast(self.capacity))) {
                return false; // Deque full
            }

            // Store task at bottom
            const idx = @as(usize, @intCast(b)) & self.mask;
            self.buffer[idx].store(task, .unordered);

            // Use release store to ensure task is visible before incrementing bottom
            // This acts as a release fence
            self.bottom.store(b + 1, .release);

            return true;
        }

        /// Owner: Pop task from bottom (O(1))
        ///
        /// Only called by the owner thread.
        /// Returns null if empty.
        pub fn pop(self: *Self) ?*T {
            const b = self.bottom.load(.monotonic) - 1;
            // Use seq_cst store to synchronize with stealers
            self.bottom.store(b, .seq_cst);

            const t = self.top.load(.monotonic);

            if (t <= b) {
                // Non-empty
                const idx = @as(usize, @intCast(b)) & self.mask;
                const task = self.buffer[idx].load(.unordered);

                if (t == b) {
                    // Last element - race with stealers
                    // Try to claim it with CAS on top
                    if (self.top.cmpxchgStrong(t, t + 1, .seq_cst, .monotonic)) |_| {
                        // Lost race to stealer
                        self.bottom.store(t + 1, .monotonic);
                        return null;
                    }
                    // Won race
                    self.bottom.store(t + 1, .monotonic);
                }

                return task;
            } else {
                // Empty
                self.bottom.store(t, .monotonic);
                return null;
            }
        }

        /// Stealer: Steal task from top (O(1))
        ///
        /// Can be called by any thread.
        /// Lock-free using CAS.
        /// Returns null if empty or contended.
        pub fn steal(self: *Self) ?*T {
            // Use seq_cst load to synchronize with owner's seq_cst store
            const t = self.top.load(.seq_cst);
            const b = self.bottom.load(.acquire);

            if (t < b) {
                // Non-empty - try to steal
                const idx = @as(usize, @intCast(t)) & self.mask;
                const task = self.buffer[idx].load(.unordered);

                // Try to increment top (claim the task)
                if (self.top.cmpxchgStrong(t, t + 1, .seq_cst, .monotonic)) |_| {
                    // CAS failed - another stealer got it
                    return null;
                }

                // Successfully stolen
                return task;
            }

            // Empty
            return null;
        }

        /// Check if deque is empty
        pub fn isEmpty(self: *Self) bool {
            const b = self.bottom.load(.monotonic);
            const t = self.top.load(.monotonic);
            return b <= t;
        }

        /// Get current length (approximate, may be stale)
        pub fn len(self: *Self) usize {
            const b = self.bottom.load(.monotonic);
            const t = self.top.load(.monotonic);
            const diff = b - t;
            return if (diff > 0) @intCast(diff) else 0;
        }

        /// Clear all tasks (owner only)
        pub fn clear(self: *Self) void {
            while (self.pop()) |_| {}
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const TestItem = struct {
    value: i32,
};

test "WorkStealingDeque: push and pop" {
    const allocator = std.testing.allocator;

    // Note: Deque stores *TestItem, so T = TestItem, push takes *TestItem
    var deque = try WorkStealingDeque(TestItem).init(allocator, 16);
    defer deque.deinit();

    var item1 = TestItem{ .value = 1 };
    var item2 = TestItem{ .value = 2 };
    var item3 = TestItem{ .value = 3 };

    try std.testing.expect(deque.push(&item1));
    try std.testing.expect(deque.push(&item2));
    try std.testing.expect(deque.push(&item3));

    try std.testing.expectEqual(@as(usize, 3), deque.len());

    // Pop in LIFO order
    try std.testing.expectEqual(&item3, deque.pop().?);
    try std.testing.expectEqual(&item2, deque.pop().?);
    try std.testing.expectEqual(&item1, deque.pop().?);
    try std.testing.expect(deque.pop() == null);
}

test "WorkStealingDeque: steal takes from top (FIFO)" {
    const allocator = std.testing.allocator;

    var deque = try WorkStealingDeque(TestItem).init(allocator, 16);
    defer deque.deinit();

    var item1 = TestItem{ .value = 1 };
    var item2 = TestItem{ .value = 2 };
    var item3 = TestItem{ .value = 3 };

    _ = deque.push(&item1);
    _ = deque.push(&item2);
    _ = deque.push(&item3);

    // Steal takes oldest (FIFO)
    try std.testing.expectEqual(&item1, deque.steal().?);
    try std.testing.expectEqual(&item2, deque.steal().?);
    try std.testing.expectEqual(&item3, deque.steal().?);
    try std.testing.expect(deque.steal() == null);
}

test "WorkStealingDeque: empty deque" {
    const allocator = std.testing.allocator;

    var deque = try WorkStealingDeque(TestItem).init(allocator, 16);
    defer deque.deinit();

    try std.testing.expect(deque.isEmpty());
    try std.testing.expect(deque.pop() == null);
    try std.testing.expect(deque.steal() == null);
}

test "WorkStealingDeque: capacity power of 2" {
    const allocator = std.testing.allocator;

    // Request 10, should get 16
    var deque = try WorkStealingDeque(TestItem).init(allocator, 10);
    defer deque.deinit();

    try std.testing.expectEqual(@as(usize, 16), deque.capacity);
    try std.testing.expectEqual(@as(usize, 15), deque.mask);
}

test "WorkStealingDeque: full deque" {
    const allocator = std.testing.allocator;

    var deque = try WorkStealingDeque(TestItem).init(allocator, 4);
    defer deque.deinit();

    var items: [4]TestItem = undefined;
    for (&items, 0..) |*item, i| {
        item.value = @intCast(i);
    }

    // Fill the deque
    for (&items) |*item| {
        try std.testing.expect(deque.push(item));
    }

    // Should be full now
    var extra = TestItem{ .value = 99 };
    try std.testing.expect(!deque.push(&extra));
}

test "WorkStealingDeque: interleaved push/pop/steal" {
    const allocator = std.testing.allocator;

    var deque = try WorkStealingDeque(TestItem).init(allocator, 16);
    defer deque.deinit();

    var item1 = TestItem{ .value = 1 };
    var item2 = TestItem{ .value = 2 };
    var item3 = TestItem{ .value = 3 };

    _ = deque.push(&item1);
    _ = deque.push(&item2);

    // Steal one
    try std.testing.expectEqual(&item1, deque.steal().?);

    // Push another
    _ = deque.push(&item3);

    // Pop (LIFO) should get item3
    try std.testing.expectEqual(&item3, deque.pop().?);

    // Pop should get item2
    try std.testing.expectEqual(&item2, deque.pop().?);

    try std.testing.expect(deque.isEmpty());
}
