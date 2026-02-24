// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! CBC-MN Scheduler - Sovereign Index
//!
//! Capability-Budgeted Cooperative M:N Scheduler.
//! Coordinates multiple worker threads with work-stealing load balancing.
//!
//! See: SPEC-021 M:N Scheduler

const std = @import("std");
const Atomic = std.atomic.Value;

pub const task_mod = @import("task.zig");
pub const Task = task_mod.Task;
pub const TaskState = task_mod.TaskState;
pub const TaskFn = task_mod.TaskFn;
pub const NoArgTaskFn = task_mod.NoArgTaskFn;
pub const SavedRegisters = task_mod.SavedRegisters;

pub const worker_mod = @import("worker.zig");
pub const Worker = worker_mod.Worker;
pub const WorkerState = worker_mod.WorkerState;
pub const WorkerStats = worker_mod.WorkerStats;

pub const budget_mod = @import("budget.zig");
pub const Budget = budget_mod.Budget;
pub const BudgetCost = budget_mod.BudgetCost;

pub const deque_mod = @import("deque.zig");
pub const WorkStealingDeque = deque_mod.WorkStealingDeque;

pub const continuation_mod = @import("continuation.zig");
pub const Context = continuation_mod.Context;
pub const switchContext = continuation_mod.switchContext;
pub const initFiberContext = continuation_mod.initFiberContext;

pub const nursery_mod = @import("nursery.zig");
pub const compat_time = @import("compat_time");
pub const Nursery = nursery_mod.Nursery;
pub const NurseryState = nursery_mod.NurseryState;
pub const NurseryResult = nursery_mod.NurseryResult;

// Re-export yield for tasks
pub const yield = worker_mod.yield;
pub const yieldComplete = worker_mod.yieldComplete;

// ============================================================================
// Scheduler Configuration
// ============================================================================

/// Scheduler configuration options
pub const SchedulerConfig = struct {
    /// Number of worker threads (0 = auto-detect CPU count)
    worker_count: usize = 0,

    /// Capacity of each worker's local deque
    deque_capacity: usize = 256,

    /// Capacity of the global submission queue
    global_queue_capacity: usize = 1024,

    /// Deterministic seed for reproducible scheduling (0 = random)
    deterministic_seed: u64 = 0,
};

// ============================================================================
// Scheduler
// ============================================================================

/// The M:N Scheduler - coordinates workers and manages task distribution
pub const Scheduler = struct {
    const Self = @This();

    /// Allocator for scheduler resources
    allocator: std.mem.Allocator,

    /// Worker threads
    workers: []Worker,

    /// OS thread handles
    threads: []std.Thread,

    /// Global submission queue (for external task submission)
    global_queue: WorkStealingDeque(Task),

    /// Shutdown signal
    shutdown: Atomic(bool),

    /// Number of active workers
    active_workers: Atomic(usize),

    /// Round-robin counter for task distribution
    next_worker: Atomic(usize),

    /// Configuration
    config: SchedulerConfig,

    /// Scheduler state
    state: Atomic(SchedulerState),

    /// Initialize the scheduler with given configuration
    pub fn init(allocator: std.mem.Allocator, config: SchedulerConfig) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Determine worker count
        const worker_count = if (config.worker_count == 0)
            @max(1, std.Thread.getCpuCount() catch 1)
        else
            config.worker_count;

        // Allocate workers array
        const workers = try allocator.alloc(Worker, worker_count);
        errdefer allocator.free(workers);

        // Allocate thread handles array
        const threads = try allocator.alloc(std.Thread, worker_count);
        errdefer allocator.free(threads);

        self.* = Self{
            .allocator = allocator,
            .workers = workers,
            .threads = threads,
            .global_queue = try WorkStealingDeque(Task).init(allocator, config.global_queue_capacity),
            .shutdown = Atomic(bool).init(false),
            .active_workers = Atomic(usize).init(0),
            .next_worker = Atomic(usize).init(0),
            .config = config,
            .state = Atomic(SchedulerState).init(.Created),
        };

        // Initialize workers
        for (self.workers, 0..) |*worker, i| {
            worker.* = try Worker.init(
                allocator,
                i,
                self.workers,
                &self.shutdown,
                config.deque_capacity,
            );
        }

        return self;
    }

    /// Clean up scheduler resources
    pub fn deinit(self: *Self) void {
        // Ensure stopped
        if (self.state.load(.acquire) == .Running) {
            self.stop();
        }

        // Clean up workers
        for (self.workers) |*worker| {
            worker.deinit();
        }

        // Free arrays
        self.allocator.free(self.workers);
        self.allocator.free(self.threads);

        // Clean up global queue
        self.global_queue.deinit();

        // Free self
        self.allocator.destroy(self);
    }

    /// Start the scheduler (spawns worker threads)
    pub fn start(self: *Self) !void {
        if (self.state.cmpxchgStrong(.Created, .Running, .acq_rel, .acquire)) |_| {
            return error.AlreadyStarted;
        }

        // Spawn worker threads
        for (self.threads, self.workers) |*thread, *worker| {
            thread.* = try std.Thread.spawn(.{}, workerThreadEntry, .{ self, worker });
            _ = self.active_workers.fetchAdd(1, .acq_rel);
        }
    }

    /// Stop the scheduler (signals shutdown and waits for workers)
    pub fn stop(self: *Self) void {
        // Signal shutdown
        self.shutdown.store(true, .release);
        _ = self.state.cmpxchgStrong(.Running, .Stopping, .acq_rel, .acquire);

        // Wait for all workers to stop
        for (self.threads) |thread| {
            thread.join();
        }

        self.state.store(.Stopped, .release);
    }

    /// Submit a task to the scheduler
    ///
    /// The task will be distributed to a worker for execution.
    /// Returns false if the scheduler is not running or queue is full.
    pub fn submit(self: *Self, task: *Task) bool {
        if (self.state.load(.acquire) != .Running) {
            return false;
        }

        // Round-robin distribution to workers
        const worker_idx = self.next_worker.fetchAdd(1, .monotonic) % self.workers.len;
        return self.workers[worker_idx].pushTask(task);
    }

    /// Submit a task to the global queue (for work stealing)
    pub fn submitGlobal(self: *Self, task: *Task) bool {
        if (self.state.load(.acquire) != .Running) {
            return false;
        }
        return self.global_queue.push(task);
    }

    /// Create and submit a new task
    pub fn spawn(
        self: *Self,
        func: TaskFn,
        arg: ?*anyopaque,
        task_budget: Budget,
    ) !*Task {
        const task = try Task.init(
            self.allocator,
            self.generateTaskId(),
            func,
            arg,
            task_budget,
            null,
        );
        errdefer task.deinit();

        if (!self.submit(task)) {
            task.deinit();
            return error.SubmissionFailed;
        }

        return task;
    }

    /// Get aggregate statistics from all workers
    pub fn getStats(self: *const Self) WorkerStats {
        var total = WorkerStats{};
        for (self.workers) |*worker| {
            total.merge(worker.getStats());
        }
        return total;
    }

    /// Get number of workers
    pub fn workerCount(self: *const Self) usize {
        return self.workers.len;
    }

    /// Check if scheduler is running
    pub fn isRunning(self: *const Self) bool {
        return self.state.load(.acquire) == .Running;
    }

    // ========================================================================
    // Internal
    // ========================================================================

    /// Worker thread entry point
    fn workerThreadEntry(self: *Self, worker: *Worker) void {
        // Run the worker loop
        worker.run();

        // Decrement active workers
        _ = self.active_workers.fetchSub(1, .acq_rel);
    }

    /// Generate a unique task ID
    fn generateTaskId(self: *Self) u64 {
        // Simple counter-based ID
        const counter = struct {
            var value: Atomic(u64) = Atomic(u64).init(1);
        };
        _ = self;
        return counter.value.fetchAdd(1, .monotonic);
    }
};

/// Scheduler state
pub const SchedulerState = enum(u8) {
    /// Scheduler created but not started
    Created = 0,
    /// Scheduler is running
    Running = 1,
    /// Scheduler is stopping
    Stopping = 2,
    /// Scheduler has stopped
    Stopped = 3,
};

// ============================================================================
// Tests
// ============================================================================

test "Scheduler: init and deinit" {
    const allocator = std.testing.allocator;

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 16,
    });
    defer sched.deinit();

    try std.testing.expectEqual(@as(usize, 2), sched.workerCount());
    try std.testing.expectEqual(SchedulerState.Created, sched.state.load(.acquire));
}

test "Scheduler: start and stop" {
    const allocator = std.testing.allocator;

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 2,
        .deque_capacity = 16,
    });
    defer sched.deinit();

    try sched.start();
    try std.testing.expectEqual(SchedulerState.Running, sched.state.load(.acquire));
    try std.testing.expect(sched.isRunning());

    sched.stop();
    try std.testing.expectEqual(SchedulerState.Stopped, sched.state.load(.acquire));
    try std.testing.expect(!sched.isRunning());
}

test "Scheduler: submit task" {
    const allocator = std.testing.allocator;

    const sched = try Scheduler.init(allocator, .{
        .worker_count = 1,
        .deque_capacity = 16,
    });
    defer sched.deinit();

    try sched.start();

    // Create and submit task
    const task = try Task.init(
        allocator,
        1,
        &dummyTask,
        null,
        Budget.childDefault(),
        null,
    );

    try std.testing.expect(sched.submit(task));

    // Wait for task to complete
    var attempts: usize = 0;
    while (task.state != .Completed and attempts < 1000) : (attempts += 1) {
        compat_time.sleep(1_000_000);
    }

    sched.stop();

    // Verify task completed
    try std.testing.expectEqual(TaskState.Completed, task.state);
    task.deinit();
}

fn dummyTask(_: ?*anyopaque) callconv(.c) i64 {
    return 42;
}
