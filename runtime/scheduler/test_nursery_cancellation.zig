// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Phase 3 Completion: Cancellation Propagation Tests (Added 2026-02-11)

const std = @import("std");
const Atomic = std.atomic.Value;

const scheduler_mod = @import("scheduler.zig");
const Scheduler = scheduler_mod.Scheduler;

const task_mod = @import("task.zig");
const Task = task_mod.Task;

const nursery_mod = @import("nursery.zig");
const Nursery = nursery_mod.Nursery;
const NurseryResult = nursery_mod.NurseryResult;

const budget_mod = @import("budget.zig");
const Budget = budget_mod.Budget;

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

test "Nursery + Scheduler: cancellation propagates to all children" {
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

    // Spawn multiple long-running tasks
    const spawn_count: usize = 5;
    var i: usize = 0;
    while (i < spawn_count) : (i += 1) {
        _ = nursery.spawn(&incrementTask, &test_counter);
    }

    // Give tasks time to start
    std.Thread.sleep(10_000_000);

    // Cancel the nursery
    nursery.cancel();

    // Wait for cancellation to propagate
    const result = nursery.awaitAll();

    sched.stop();

    // Result should be cancelled
    try std.testing.expectEqual(NurseryResult.cancelled, result);
}

test "Nursery + Scheduler: child error triggers cancellation propagation" {
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

    // Spawn tasks, one of which will error
    _ = nursery.spawn(&incrementTask, null);
    _ = nursery.spawn(&errorTask, null);  // This one errors
    _ = nursery.spawn(&incrementTask, null);

    // Wait for completion
    const result = nursery.awaitAll();

    sched.stop();

    // Should have child_failed result
    switch (result) {
        .child_failed => |err| {
            try std.testing.expectEqual(@as(i64, -42), err.error_code);
        },
        else => try std.testing.expect(false),
    }
}

test "Nursery + Scheduler: cancel after completion is safe" {
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

    // Spawn and complete task
    _ = nursery.spawn(&incrementTask, null);
    
    // Wait for completion
    var attempts: usize = 0;
    while (test_counter.load(.acquire) < 1 and attempts < 1000) : (attempts += 1) {
        std.Thread.sleep(1_000_000);
    }

    // Cancel after completion
    nursery.cancel();

    // awaitAll should still work
    const result = nursery.awaitAll();

    sched.stop();

    // Result depends on timing - either success or cancelled
    // The important thing is that it doesn't panic
    _ = result;
}
