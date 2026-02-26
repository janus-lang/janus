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
    while (test_counter.load(.acquire) < 2 and attempts < 10000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Verify tasks executed
    try std.testing.expectEqual(@as(u64, 2), test_counter.load(.acquire));

    // Verify nursery was notified (completion count incremented by workers)

[Rest of file truncated for brevity]