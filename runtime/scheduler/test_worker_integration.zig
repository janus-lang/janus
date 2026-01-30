// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Worker Integration Tests
//!
//! Tests that verify end-to-end task execution through the worker loop.
//! These tests spawn actual tasks and run them through context switches.

const std = @import("std");
const Atomic = std.atomic.Value;

const task_mod = @import("task.zig");
const Task = task_mod.Task;
const TaskState = task_mod.TaskState;

const worker_mod = @import("worker.zig");
const Worker = worker_mod.Worker;

const budget_mod = @import("budget.zig");
const Budget = budget_mod.Budget;

// ============================================================================
// Test Fixtures
// ============================================================================

/// Counter incremented by test tasks
var test_counter: Atomic(u64) = Atomic(u64).init(0);

/// Flag set when task runs
var task_executed: Atomic(bool) = Atomic(bool).init(false);

/// Task result value
var task_result_value: Atomic(i64) = Atomic(i64).init(0);

/// Simple task that increments counter and returns
fn simpleTask(_: ?*anyopaque) callconv(.c) i64 {
    _ = test_counter.fetchAdd(1, .seq_cst);
    task_executed.store(true, .seq_cst);
    return 42;
}

/// Task that adds argument value to counter
fn adderTask(arg: ?*anyopaque) callconv(.c) i64 {
    const value = if (arg) |ptr| @as(*i64, @ptrCast(@alignCast(ptr))).* else 0;
    _ = test_counter.fetchAdd(@as(u64, @intCast(value)), .seq_cst);
    task_result_value.store(value * 2, .seq_cst);
    return value * 2;
}

/// Task that yields multiple times
fn yieldingTask(_: ?*anyopaque) callconv(.c) i64 {
    _ = test_counter.fetchAdd(1, .seq_cst);
    worker_mod.yield();
    _ = test_counter.fetchAdd(1, .seq_cst);
    worker_mod.yield();
    _ = test_counter.fetchAdd(1, .seq_cst);
    return 3;
}

// ============================================================================
// Tests
// ============================================================================

test "Worker integration: execute single task" {
    const allocator = std.testing.allocator;

    // Reset test state
    test_counter.store(0, .seq_cst);
    task_executed.store(false, .seq_cst);

    // Create shutdown signal
    var shutdown = Atomic(bool).init(false);

    // Create worker
    var workers: [1]Worker = undefined;
    workers[0] = try Worker.init(allocator, 0, &workers, &shutdown, 16);
    defer workers[0].deinit();

    // Create task
    const task = try Task.init(
        allocator,
        1,
        &simpleTask,
        null,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    // Push task to worker's queue
    try std.testing.expect(workers[0].pushTask(task));

    // Run worker in separate thread so we can signal shutdown after task completes
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(w: *Worker) void {
            w.run();
        }
    }.run, .{&workers[0]});

    // Wait for task to execute (with timeout)
    var attempts: usize = 0;
    while (!task_executed.load(.seq_cst) and attempts < 1000) : (attempts += 1) {
        std.Thread.sleep(1_000_000); // 1ms
    }

    // Signal shutdown
    shutdown.store(true, .release);
    thread.join();

    // Verify task executed
    try std.testing.expect(task_executed.load(.seq_cst));
    try std.testing.expectEqual(@as(u64, 1), test_counter.load(.seq_cst));
    try std.testing.expectEqual(TaskState.Completed, task.state);
}

test "Worker integration: task with argument" {
    const allocator = std.testing.allocator;

    // Reset test state
    test_counter.store(0, .seq_cst);
    task_result_value.store(0, .seq_cst);

    var shutdown = Atomic(bool).init(false);
    var workers: [1]Worker = undefined;
    workers[0] = try Worker.init(allocator, 0, &workers, &shutdown, 16);
    defer workers[0].deinit();

    // Create task with argument
    var arg_value: i64 = 21;
    const task = try Task.init(
        allocator,
        1,
        &adderTask,
        @ptrCast(&arg_value),
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    try std.testing.expect(workers[0].pushTask(task));

    // Run worker in separate thread
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(w: *Worker) void {
            w.run();
        }
    }.run, .{&workers[0]});

    // Wait for task to complete
    var attempts: usize = 0;
    while (task.state != .Completed and attempts < 1000) : (attempts += 1) {
        std.Thread.sleep(1_000_000);
    }

    shutdown.store(true, .release);
    thread.join();

    // Verify argument was passed and result computed
    try std.testing.expectEqual(@as(u64, 21), test_counter.load(.seq_cst));
    try std.testing.expectEqual(@as(i64, 42), task_result_value.load(.seq_cst));
}

test "Worker integration: multiple tasks sequential" {
    const allocator = std.testing.allocator;

    test_counter.store(0, .seq_cst);

    var shutdown = Atomic(bool).init(false);
    var workers: [1]Worker = undefined;
    workers[0] = try Worker.init(allocator, 0, &workers, &shutdown, 16);
    defer workers[0].deinit();

    // Create multiple tasks
    var tasks: [3]*Task = undefined;
    for (&tasks, 0..) |*task_ptr, i| {
        task_ptr.* = try Task.init(
            allocator,
            @intCast(i + 1),
            &simpleTask,
            null,
            Budget.childDefault(),
            null,
        );
        try std.testing.expect(workers[0].pushTask(task_ptr.*));
    }
    defer for (tasks) |task| task.deinit();

    // Run worker in separate thread
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(w: *Worker) void {
            w.run();
        }
    }.run, .{&workers[0]});

    // Wait for all tasks to complete
    var attempts: usize = 0;
    while (test_counter.load(.seq_cst) < 3 and attempts < 1000) : (attempts += 1) {
        std.Thread.sleep(1_000_000);
    }

    shutdown.store(true, .release);
    thread.join();

    // All tasks should have executed
    try std.testing.expectEqual(@as(u64, 3), test_counter.load(.seq_cst));

    // All tasks should be completed
    for (tasks) |task| {
        try std.testing.expectEqual(TaskState.Completed, task.state);
    }
}

test "Worker integration: task yield and resume" {
    const allocator = std.testing.allocator;

    test_counter.store(0, .seq_cst);

    var shutdown = Atomic(bool).init(false);
    var workers: [1]Worker = undefined;
    workers[0] = try Worker.init(allocator, 0, &workers, &shutdown, 16);
    defer workers[0].deinit();

    const task = try Task.init(
        allocator,
        1,
        &yieldingTask,
        null,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    try std.testing.expect(workers[0].pushTask(task));

    // Run worker in separate thread
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(w: *Worker) void {
            w.run();
        }
    }.run, .{&workers[0]});

    // Wait for task to complete (yields 3 times)
    var attempts: usize = 0;
    while (task.state != .Completed and attempts < 1000) : (attempts += 1) {
        std.Thread.sleep(1_000_000);
    }

    shutdown.store(true, .release);
    thread.join();

    // Task increments counter 3 times (with yields in between)
    try std.testing.expectEqual(@as(u64, 3), test_counter.load(.seq_cst));
    try std.testing.expectEqual(TaskState.Completed, task.state);
}

test "Worker stats: track execution" {
    const allocator = std.testing.allocator;

    test_counter.store(0, .seq_cst);

    var shutdown = Atomic(bool).init(false);
    var workers: [1]Worker = undefined;
    workers[0] = try Worker.init(allocator, 0, &workers, &shutdown, 16);
    defer workers[0].deinit();

    // Create and push tasks
    var tasks: [2]*Task = undefined;
    for (&tasks, 0..) |*task_ptr, i| {
        task_ptr.* = try Task.init(
            allocator,
            @intCast(i + 1),
            &simpleTask,
            null,
            Budget.childDefault(),
            null,
        );
        try std.testing.expect(workers[0].pushTask(task_ptr.*));
    }
    defer for (tasks) |task| task.deinit();

    // Run worker in separate thread
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(w: *Worker) void {
            w.run();
        }
    }.run, .{&workers[0]});

    // Wait for tasks to complete
    var attempts: usize = 0;
    while (test_counter.load(.seq_cst) < 2 and attempts < 1000) : (attempts += 1) {
        std.Thread.sleep(1_000_000);
    }

    shutdown.store(true, .release);
    thread.join();

    // Check stats
    const stats = workers[0].getStats();
    try std.testing.expect(stats.tasks_executed >= 2);
    try std.testing.expect(stats.local_pops >= 2);
}
