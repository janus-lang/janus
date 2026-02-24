// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Nursery + Scheduler Integration Tests (Phase 9.1)
//!
//! Tests that verify nurseries work correctly with the M:N scheduler,
//! including worker → nursery notification and state machine transitions.
//!
//! See: SPEC-021-scheduler-nursery-state-machine.md

const std = @import("std");
const Atomic = std.atomic.Value;

const scheduler_mod = @import("scheduler.zig");
const Scheduler = scheduler_mod.Scheduler;

const task_mod = @import("task.zig");
const Task = task_mod.Task;
const TaskState = task_mod.TaskState;

const nursery_mod = @import("nursery.zig");
const Nursery = nursery_mod.Nursery;
const NurseryState = nursery_mod.NurseryState;
const NurseryResult = nursery_mod.NurseryResult;

const budget_mod = @import("budget.zig");
const compat_time = @import("compat_time");
const Budget = budget_mod.Budget;

// ============================================================================
// Test Fixtures
// ============================================================================

/// Shared counter for verification
var test_counter: Atomic(u64) = Atomic(u64).init(0);

/// Simple task that increments counter
fn incrementTask(_: ?*anyopaque) callconv(.c) i64 {
    _ = test_counter.fetchAdd(1, .seq_cst);
    return 1;
}

/// Task that errors
fn errorTask(_: ?*anyopaque) callconv(.c) i64 {
    _ = test_counter.fetchAdd(1, .seq_cst);
    return -42; // Error code
}

/// Scheduler submit function adapter
fn schedulerSubmit(handle: *anyopaque, task: *Task) bool {
    const sched: *Scheduler = @ptrCast(@alignCast(handle));
    return sched.submit(task);
}

// ============================================================================
// Tests
// ============================================================================

test "Nursery + Scheduler: basic spawn and completion" {
    const allocator = std.testing.allocator;
    test_counter.store(0, .seq_cst);

    // Create and start scheduler
    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 32,
    });
    defer sched.deinit();
    try sched.start();

    // Create nursery bound to scheduler
    var nursery = Nursery.initWithScheduler(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
        sched,
        &schedulerSubmit,
    );
    defer nursery.deinit();

    // Spawn tasks through nursery
    const task1 = nursery.spawn(&incrementTask, null);
    const task2 = nursery.spawn(&incrementTask, null);

    try std.testing.expect(task1 != null);
    try std.testing.expect(task2 != null);
    try std.testing.expectEqual(@as(usize, 2), nursery.children.items.len);

    // Wait for tasks to complete
    var attempts: usize = 0;
    while (test_counter.load(.seq_cst) < 2 and attempts < 10000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Verify tasks executed
    try std.testing.expectEqual(@as(u64, 2), test_counter.load(.seq_cst));

    // Verify nursery was notified (completion count incremented by workers)
    try std.testing.expectEqual(@as(usize, 2), nursery.completed_count.load(.acquire));
    try std.testing.expect(nursery.allChildrenComplete());
}

test "Nursery + Scheduler: awaitAll blocks until completion" {
    const allocator = std.testing.allocator;
    test_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 32,
    });
    defer sched.deinit();
    try sched.start();

    var nursery = Nursery.initWithScheduler(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
        sched,
        &schedulerSubmit,
    );
    defer nursery.deinit();

    // Spawn tasks
    _ = nursery.spawn(&incrementTask, null);
    _ = nursery.spawn(&incrementTask, null);
    _ = nursery.spawn(&incrementTask, null);

    // awaitAll should block until all complete
    const result = nursery.awaitAll();

    sched.stop();

    // Verify success result
    try std.testing.expectEqual(NurseryResult.success, result);
    try std.testing.expectEqual(NurseryState.Closed, nursery.state.load(.acquire));
    try std.testing.expectEqual(@as(u64, 3), test_counter.load(.seq_cst));
}

test "Nursery + Scheduler: cancel propagates to children" {
    const allocator = std.testing.allocator;
    test_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 32,
    });
    defer sched.deinit();
    try sched.start();

    var nursery = Nursery.initWithScheduler(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
        sched,
        &schedulerSubmit,
    );
    defer nursery.deinit();

    // Spawn a task
    const task = nursery.spawn(&incrementTask, null);
    try std.testing.expect(task != null);

    // Cancel the nursery
    nursery.cancel();

    // State should be Cancelling
    try std.testing.expectEqual(NurseryState.Cancelling, nursery.state.load(.acquire));

    // Child should be marked cancelled
    try std.testing.expectEqual(TaskState.Cancelled, task.?.state);

    sched.stop();
}

test "Nursery + Scheduler: error captured by awaitAll" {
    const allocator = std.testing.allocator;
    test_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 32,
    });
    defer sched.deinit();
    try sched.start();

    var nursery = Nursery.initWithScheduler(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
        sched,
        &schedulerSubmit,
    );
    defer nursery.deinit();

    // Spawn normal and error tasks
    _ = nursery.spawn(&incrementTask, null);
    _ = nursery.spawn(&errorTask, null);

    // Wait for completion
    const result = nursery.awaitAll();

    sched.stop();

    // Should have error result
    switch (result) {
        .child_failed => |err| {
            try std.testing.expectEqual(@as(i64, -42), err.error_code);
        },
        else => try std.testing.expect(false),
    }
}

test "Nursery + Scheduler: spawn fails when closed" {
    const allocator = std.testing.allocator;

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 1,
        .deque_capacity = 32,
    });
    defer sched.deinit();
    try sched.start();

    var nursery = Nursery.initWithScheduler(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
        sched,
        &schedulerSubmit,
    );
    defer nursery.deinit();

    // Close the nursery
    nursery.close();

    // Spawn should fail
    const task = nursery.spawn(&incrementTask, null);
    try std.testing.expect(task == null);

    sched.stop();
}

test "Nursery + Scheduler: spawn fails when cancelling" {
    const allocator = std.testing.allocator;

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 1,
        .deque_capacity = 32,
    });
    defer sched.deinit();
    try sched.start();

    var nursery = Nursery.initWithScheduler(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
        sched,
        &schedulerSubmit,
    );
    defer nursery.deinit();

    // Cancel the nursery
    nursery.cancel();

    // Spawn should fail
    const task = nursery.spawn(&incrementTask, null);
    try std.testing.expect(task == null);

    sched.stop();
}

test "Nursery + Scheduler: worker notification increments count" {
    const allocator = std.testing.allocator;
    test_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 32,
    });
    defer sched.deinit();
    try sched.start();

    var nursery = Nursery.initWithScheduler(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
        sched,
        &schedulerSubmit,
    );
    defer nursery.deinit();

    // Spawn multiple tasks
    const count = 5;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        _ = nursery.spawn(&incrementTask, null);
    }

    // Wait for completion
    var attempts: usize = 0;
    while (nursery.completed_count.load(.acquire) < count and attempts < 10000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Workers should have notified nursery for each completion
    try std.testing.expectEqual(@as(usize, count), nursery.completed_count.load(.acquire));
}

test "Nursery + Scheduler: state machine transition order" {
    const allocator = std.testing.allocator;
    test_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 1,
        .deque_capacity = 32,
    });
    defer sched.deinit();
    try sched.start();

    var nursery = Nursery.initWithScheduler(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
        sched,
        &schedulerSubmit,
    );
    defer nursery.deinit();

    // Initial state: Open
    try std.testing.expectEqual(NurseryState.Open, nursery.state.load(.acquire));

    // Spawn a task
    _ = nursery.spawn(&incrementTask, null);

    // Close: Open -> Closing
    nursery.close();
    try std.testing.expectEqual(NurseryState.Closing, nursery.state.load(.acquire));

    // Wait for completion and awaitAll
    _ = nursery.awaitAll();

    // Final state: Closed
    try std.testing.expectEqual(NurseryState.Closed, nursery.state.load(.acquire));

    sched.stop();
}
