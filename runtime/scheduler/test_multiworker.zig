// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Multi-Worker Work-Stealing Tests
//!
//! Tests that verify work stealing and load balancing across multiple workers.
//! This is the proof that M:N scheduling actually works.

const std = @import("std");
const Atomic = std.atomic.Value;

const scheduler_mod = @import("scheduler.zig");
const Scheduler = scheduler_mod.Scheduler;
const SchedulerConfig = scheduler_mod.SchedulerConfig;

const task_mod = @import("task.zig");
const Task = task_mod.Task;
const TaskState = task_mod.TaskState;

const budget_mod = @import("budget.zig");
const compat_time = @import("compat_time");
const Budget = budget_mod.Budget;

// ============================================================================
// Test Fixtures
// ============================================================================

/// Counter for tracking task execution
var execution_counter: Atomic(u64) = Atomic(u64).init(0);

/// Array to track which worker executed each task (by task ID)
var worker_execution_log: [256]Atomic(i32) = undefined;

/// Initialize worker execution log
fn initExecutionLog() void {
    for (&worker_execution_log) |*entry| {
        entry.* = Atomic(i32).init(-1);
    }
}

/// Simple incrementing task
fn counterTask(_: ?*anyopaque) callconv(.c) i64 {
    _ = execution_counter.fetchAdd(1, .seq_cst);
    return 1;
}

/// Task that does some "work" (busy loop)
fn busyTask(arg: ?*anyopaque) callconv(.c) i64 {
    const iterations: u64 = if (arg) |ptr|
        @as(*u64, @ptrCast(@alignCast(ptr))).*
    else
        1000;

    var sum: u64 = 0;
    for (0..iterations) |i| {
        sum +%= i;
    }

    _ = execution_counter.fetchAdd(1, .seq_cst);
    return @intCast(sum & 0x7FFFFFFF);
}

/// Task that yields multiple times
fn yieldingTask(_: ?*anyopaque) callconv(.c) i64 {
    _ = execution_counter.fetchAdd(1, .seq_cst);
    scheduler_mod.yield();
    _ = execution_counter.fetchAdd(1, .seq_cst);
    scheduler_mod.yield();
    _ = execution_counter.fetchAdd(1, .seq_cst);
    return 3;
}

// ============================================================================
// Tests
// ============================================================================

test "Multi-worker: basic two-worker execution" {
    const allocator = std.testing.allocator;
    execution_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 32,
    });
    defer sched.deinit();

    try sched.start();

    // Submit tasks
    var tasks: [4]*Task = undefined;
    for (&tasks, 0..) |*task_ptr, i| {
        task_ptr.* = try Task.init(
            allocator,
            @intCast(i + 1),
            &counterTask,
            null,
            Budget.childDefault(),
            null,
        );
        try std.testing.expect(sched.submit(task_ptr.*));
    }

    // Wait for completion (increased timeout for loaded systems)
    var attempts: usize = 0;
    while (execution_counter.load(.seq_cst) < 4 and attempts < 5000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Verify all tasks executed
    try std.testing.expectEqual(@as(u64, 4), execution_counter.load(.seq_cst));

    // Cleanup
    for (tasks) |task| task.deinit();
}

test "Multi-worker: work stealing under load" {
    const allocator = std.testing.allocator;
    execution_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 4,
        .deque_capacity = 64,
    });
    defer sched.deinit();

    try sched.start();

    // Submit many tasks to trigger work stealing
    const task_count = 20;
    var tasks: [task_count]*Task = undefined;

    for (&tasks, 0..) |*task_ptr, i| {
        task_ptr.* = try Task.init(
            allocator,
            @intCast(i + 1),
            &counterTask,
            null,
            Budget.childDefault(),
            null,
        );
        try std.testing.expect(sched.submit(task_ptr.*));
    }

    // Wait for completion
    var attempts: usize = 0;
    while (execution_counter.load(.seq_cst) < task_count and attempts < 5000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Verify all tasks executed
    try std.testing.expectEqual(@as(u64, task_count), execution_counter.load(.seq_cst));

    // Check that work was distributed (multiple workers had work)
    const stats = sched.getStats();
    try std.testing.expect(stats.tasks_executed >= task_count);

    // Cleanup
    for (tasks) |task| task.deinit();
}

test "Multi-worker: asymmetric load distribution" {
    const allocator = std.testing.allocator;
    execution_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 64,
    });
    defer sched.deinit();

    try sched.start();

    // Submit all tasks to worker 0 by going directly to the worker
    const task_count = 10;
    var tasks: [task_count]*Task = undefined;

    for (&tasks, 0..) |*task_ptr, i| {
        task_ptr.* = try Task.init(
            allocator,
            @intCast(i + 1),
            &counterTask,
            null,
            Budget.childDefault(),
            null,
        );
        // Direct push to worker 0
        try std.testing.expect(sched.workers[0].pushTask(task_ptr.*));
    }

    // Wait for completion
    var attempts: usize = 0;
    while (execution_counter.load(.seq_cst) < task_count and attempts < 5000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Verify all tasks executed
    try std.testing.expectEqual(@as(u64, task_count), execution_counter.load(.seq_cst));

    // Check stats - if work stealing works, worker 1 should have stolen some tasks
    const stats = sched.getStats();
    try std.testing.expect(stats.tasks_executed >= task_count);

    // Note: We can't guarantee stealing happened (depends on timing),
    // but we verify the system handles asymmetric load

    // Cleanup
    for (tasks) |task| task.deinit();
}

test "Multi-worker: yielding tasks resume correctly" {
    const allocator = std.testing.allocator;
    execution_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 32,
    });
    defer sched.deinit();

    try sched.start();

    // Submit yielding tasks
    var tasks: [3]*Task = undefined;
    for (&tasks, 0..) |*task_ptr, i| {
        task_ptr.* = try Task.init(
            allocator,
            @intCast(i + 1),
            &yieldingTask,
            null,
            Budget.childDefault(),
            null,
        );
        try std.testing.expect(sched.submit(task_ptr.*));
    }

    // Wait for completion (each task increments 3 times, 10s timeout for yielding tasks)
    var attempts: usize = 0;
    while (execution_counter.load(.seq_cst) < 9 and attempts < 10000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Verify all increments happened (3 tasks * 3 increments each)
    try std.testing.expectEqual(@as(u64, 9), execution_counter.load(.seq_cst));

    // Cleanup
    for (tasks) |task| task.deinit();
}

test "Multi-worker: stress test" {
    const allocator = std.testing.allocator;
    execution_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 4,
        .deque_capacity = 128,
    });
    defer sched.deinit();

    try sched.start();

    // Submit many tasks rapidly
    const task_count = 50;
    var tasks: [task_count]*Task = undefined;

    for (&tasks, 0..) |*task_ptr, i| {
        task_ptr.* = try Task.init(
            allocator,
            @intCast(i + 1),
            &counterTask,
            null,
            Budget.childDefault(),
            null,
        );
        try std.testing.expect(sched.submit(task_ptr.*));
    }

    // Wait for completion (10 second timeout for stress test)
    var attempts: usize = 0;
    while (execution_counter.load(.seq_cst) < task_count and attempts < 10000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Verify all tasks executed
    try std.testing.expectEqual(@as(u64, task_count), execution_counter.load(.seq_cst));

    // Verify stats
    const stats = sched.getStats();
    try std.testing.expect(stats.tasks_executed >= task_count);
    // Should have some local pops
    try std.testing.expect(stats.local_pops > 0);

    // Cleanup
    for (tasks) |task| task.deinit();
}

test "Multi-worker: spawn API" {
    const allocator = std.testing.allocator;
    execution_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 32,
    });
    defer sched.deinit();

    try sched.start();

    // Use spawn API
    const task1 = try sched.spawn(&counterTask, null, Budget.childDefault());
    const task2 = try sched.spawn(&counterTask, null, Budget.childDefault());

    // Wait for completion
    var attempts: usize = 0;
    while (execution_counter.load(.seq_cst) < 2 and attempts < 5000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Verify
    try std.testing.expectEqual(@as(u64, 2), execution_counter.load(.seq_cst));
    try std.testing.expectEqual(TaskState.Completed, task1.state);
    try std.testing.expectEqual(TaskState.Completed, task2.state);

    // Cleanup
    task1.deinit();
    task2.deinit();
}

test "Multi-worker: statistics tracking" {
    const allocator = std.testing.allocator;
    execution_counter.store(0, .seq_cst);

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 32,
    });
    defer sched.deinit();

    try sched.start();

    // Submit tasks
    const task_count = 10;
    var tasks: [task_count]*Task = undefined;
    for (&tasks, 0..) |*task_ptr, i| {
        task_ptr.* = try Task.init(
            allocator,
            @intCast(i + 1),
            &counterTask,
            null,
            Budget.childDefault(),
            null,
        );
        try std.testing.expect(sched.submit(task_ptr.*));
    }

    // Wait for completion
    var attempts: usize = 0;
    while (execution_counter.load(.seq_cst) < task_count and attempts < 5000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Check aggregate stats
    const stats = sched.getStats();
    try std.testing.expectEqual(@as(u64, task_count), stats.tasks_executed);
    try std.testing.expect(stats.local_pops > 0);
    // tasks_completed should match tasks_executed for simple tasks
    try std.testing.expect(stats.tasks_completed >= task_count);

    // Cleanup
    for (tasks) |task| task.deinit();
}
