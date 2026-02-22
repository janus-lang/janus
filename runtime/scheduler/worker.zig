// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Worker Thread for CBC-MN Scheduler
//!
//! Each worker owns a local deque and can steal from others.
//! Implements the work-stealing loop with bounded steal attempts.
//!
//! See: SPEC-021 Section 7 (Work-Stealing Algorithm)

const std = @import("std");
const Atomic = std.atomic.Value;

const task_mod = @import("task.zig");
const Task = task_mod.Task;
const TaskState = task_mod.TaskState;

const nursery_mod = @import("nursery.zig");
const Nursery = nursery_mod.Nursery;

const deque_mod = @import("deque.zig");
const WorkStealingDeque = deque_mod.WorkStealingDeque;

const continuation_mod = @import("continuation.zig");
const Context = continuation_mod.Context;
const switchContext = continuation_mod.switchContext;

const budget_mod = @import("budget.zig");
const Budget = budget_mod.Budget;

// ============================================================================
// Thread-Local Worker Context (SPEC-021 Section 7.4)
// ============================================================================

/// Thread-local pointer to current worker's context
/// Used by tasks to yield back to the scheduler
threadlocal var tls_worker_context: ?*Context = null;

/// Thread-local pointer to current task's context
/// Used to save task state when yielding
threadlocal var tls_task_context: ?*Context = null;

/// Thread-local pointer to current task
/// Used by yield/cleanup to update task state
threadlocal var tls_current_task: ?*Task = null;

/// Yield from current task back to worker
/// Called by tasks when they want to voluntarily yield
pub fn yield() void {
    const worker_ctx = tls_worker_context orelse return;
    const task_ctx = tls_task_context orelse return;

    // Switch back to worker
    switchContext(task_ctx, worker_ctx);
}

/// Yield with completion status
/// Called by cleanup trampoline when task returns
///
/// Convention: negative return values are errors, non-negative are success.
pub fn yieldComplete(result: i64) void {
    if (tls_current_task) |task| {
        if (result < 0) {
            // Negative return = error
            task.markError(result);
        } else {
            // Non-negative return = success
            task.markCompleted(result);
        }
    }
    yield();
}

/// Yield with blocked status (Phase 9.3)
/// Called by awaitAll() when task needs to wait for children
///
/// The task will be marked as Blocked and yield to the scheduler.
/// It will be woken when all nursery children complete.
pub fn yieldBlocked(reason: task_mod.BlockedOn) void {
    if (tls_current_task) |task| {
        task.markBlocked(reason);
    }
    yield();
}

/// Check if currently running in fiber context
/// Returns true if called from within a task on a worker thread
pub fn inFiberContext() bool {
    return tls_current_task != null;
}

/// Get current task (if in fiber context)
/// Returns null if not running in a fiber
pub fn getCurrentTask() ?*Task {
    return tls_current_task;
}

/// Maximum steal attempts before backing off
const MAX_STEAL_ATTEMPTS: usize = 4;

/// Backoff configuration
const INITIAL_BACKOFF_NS: u64 = 1_000; // 1µs
const MAX_BACKOFF_NS: u64 = 1_000_000; // 1ms

/// Worker state (u8 for atomic compatibility)
pub const WorkerState = enum(u8) {
    /// Worker is idle, looking for work
    Idle = 0,
    /// Worker is executing a task
    Running = 1,
    /// Worker is shutting down
    Stopping = 2,
    /// Worker has terminated
    Stopped = 3,
};

/// Worker thread context
pub const Worker = struct {
    const Self = @This();

    /// Worker ID (0..N-1)
    id: usize,

    /// Local work queue (owned by this worker)
    local_queue: WorkStealingDeque(Task),

    /// Current state
    state: Atomic(WorkerState),

    /// Currently executing task (if any)
    current_task: ?*Task,

    /// Worker's own context (for switching back from tasks)
    context: Context,

    /// Reference to all workers (for stealing)
    workers: []Worker,

    /// Total number of workers
    worker_count: usize,

    /// Shutdown signal
    shutdown: *Atomic(bool),

    /// Statistics
    stats: WorkerStats,

    /// Allocator
    allocator: std.mem.Allocator,

    /// RNG for victim selection (deterministic seed for reproducibility)
    rng: std.Random.DefaultPrng,

    /// Initialize a worker
    pub fn init(
        allocator: std.mem.Allocator,
        id: usize,
        workers: []Worker,
        shutdown: *Atomic(bool),
        deque_capacity: usize,
    ) !Self {
        return Self{
            .id = id,
            .local_queue = try WorkStealingDeque(Task).init(allocator, deque_capacity),
            .state = Atomic(WorkerState).init(.Idle),
            .current_task = null,
            .context = Context.init(),
            .workers = workers,
            .worker_count = workers.len,
            .shutdown = shutdown,
            .stats = WorkerStats{},
            .allocator = allocator,
            // Deterministic seed based on worker ID for reproducible behavior
            .rng = std.Random.DefaultPrng.init(@as(u64, id) *% 0x9E3779B97F4A7C15),
        };
    }

    /// Cleanup worker resources
    pub fn deinit(self: *Self) void {
        self.local_queue.deinit();
    }

    /// Push a task to this worker's local queue
    pub fn pushTask(self: *Self, task: *Task) bool {
        return self.local_queue.push(task);
    }

    /// Main worker loop
    ///
    /// Runs until shutdown signal. Executes local tasks or steals from others.
    pub fn run(self: *Self) void {
        self.state.store(.Running, .release);

        while (!self.shutdown.load(.acquire)) {
            // Try to get work
            if (self.findWork()) |task| {
                self.executeTask(task);
            } else {
                // No work found - back off
                self.backoff();
            }
        }

        self.state.store(.Stopping, .release);

        // Drain remaining local tasks (mark as cancelled)
        while (self.local_queue.pop()) |task| {
            task.markCancelled();
            self.stats.tasks_cancelled += 1;
        }

        self.state.store(.Stopped, .release);
    }

    /// Find work: local queue first, then steal
    fn findWork(self: *Self) ?*Task {
        // 1. Try local queue first (LIFO for locality)
        if (self.local_queue.pop()) |task| {
            self.stats.local_pops += 1;
            return task;
        }

        // 2. Try to steal from other workers
        return self.trySteal();
    }

    /// Attempt to steal work from other workers
    fn trySteal(self: *Self) ?*Task {
        var attempts: usize = 0;
        const random = self.rng.random();

        while (attempts < MAX_STEAL_ATTEMPTS) : (attempts += 1) {
            // Pick a random victim (not self)
            var victim_id = random.uintLessThan(usize, self.worker_count);
            if (victim_id == self.id) {
                victim_id = (victim_id + 1) % self.worker_count;
            }

            // Skip if same worker (shouldn't happen but safety check)
            if (victim_id == self.id) continue;

            // Try to steal
            if (self.workers[victim_id].local_queue.steal()) |task| {
                self.stats.successful_steals += 1;
                return task;
            }

            self.stats.failed_steals += 1;
        }

        return null;
    }

    /// Execute a task until it yields or completes
    fn executeTask(self: *Self, task: *Task) void {
        // Check if task was cancelled between dequeue and execution (race protection)
        // This can happen if nursery.cancel() is called while task is in queue
        if (task.isFinished()) {
            // Task already done (cancelled or completed) - just notify nursery
            self.stats.tasks_cancelled += 1;
            self.notifyNurseryCompletion(task);
            return;
        }

        self.current_task = task;
        task.markRunning();
        self.stats.tasks_executed += 1;
        self.resetIdle();

        // Context switch to task
        // The task runs until it:
        // 1. Yields (budget exhausted, channel op, explicit yield)
        // 2. Completes (returns from entry function)
        // 3. Blocks (waiting on channel/IO)

        // Build task context from saved state
        var task_context = Context{
            .sp = task.sp,
            .regs = task.registers,
        };

        // Set up TLS for yield mechanism (SPEC-021 Section 7.4)
        // This allows the task to find its way back to us
        tls_worker_context = &self.context;
        tls_task_context = &task_context;
        tls_current_task = task;

        // Switch to task - this returns when task yields
        switchContext(&self.context, &task_context);

        // Clear TLS (we're back on the worker now)
        tls_worker_context = null;
        tls_task_context = null;
        tls_current_task = null;

        // Task has yielded back to us - save its state
        task.sp = task_context.sp;
        task.registers = task_context.regs;

        // Handle task state after yield
        self.handleTaskYield(task);

        self.current_task = null;
    }

    /// Handle task after it yields
    fn handleTaskYield(self: *Self, task: *Task) void {
        switch (task.state) {
            .Running => {
                // Task yielded but still runnable (budget check or explicit yield)
                if (task.budget.isExhausted()) {
                    task.markBudgetExhausted();
                    self.stats.budget_exhaustions += 1;
                    // Task will be recharged by supervisor/scheduler
                } else {
                    // Re-queue for later
                    task.state = .Ready;
                    _ = self.local_queue.push(task);
                }
            },
            .Blocked => {
                // Task is waiting on something - don't re-queue
                // It will be woken by channel/IO completion
                self.stats.tasks_blocked += 1;
            },
            .Completed, .Cancelled => {
                // Task is done - notify nursery (Phase 9.1)
                self.stats.tasks_completed += 1;
                self.notifyNurseryCompletion(task);
            },
            .BudgetExhausted => {
                // Already marked - supervisor will recharge
                self.stats.budget_exhaustions += 1;
            },
            .Ready => {
                // Shouldn't happen, but re-queue just in case
                _ = self.local_queue.push(task);
            },
        }
    }

    /// Notify parent nursery that a task has completed
    /// This is the worker → nursery notification path (Phase 9.1)
    fn notifyNurseryCompletion(self: *Self, task: *Task) void {
        _ = self; // Worker doesn't need to do anything else

        // Get nursery pointer from task (set by Nursery.spawn)
        if (task.nursery_ptr) |ptr| {
            const nursery: *Nursery = @ptrCast(@alignCast(ptr));
            nursery.notifyChildComplete(task);
        }
    }

    /// Backoff when no work available
    fn backoff(self: *Self) void {
        self.stats.idle_cycles += 1;

        // Exponential backoff with jitter
        const backoff_ns = @min(
            INITIAL_BACKOFF_NS << @min(self.stats.consecutive_idle, 10),
            MAX_BACKOFF_NS,
        );

        std.c.nanosleep(.{ .tv_sec = 0, .tv_nsec = @intCast(backoff_ns) });
        self.stats.consecutive_idle += 1;
    }

    /// Reset idle counter (called when work is found)
    fn resetIdle(self: *Self) void {
        self.stats.consecutive_idle = 0;
    }

    /// Get worker statistics
    pub fn getStats(self: *const Self) WorkerStats {
        return self.stats;
    }

    /// Check if worker is idle
    pub fn isIdle(self: *const Self) bool {
        return self.state.load(.acquire) == .Idle;
    }

    /// Check if worker has stopped
    pub fn isStopped(self: *const Self) bool {
        return self.state.load(.acquire) == .Stopped;
    }
};

/// Worker statistics for monitoring
pub const WorkerStats = struct {
    /// Tasks executed on this worker
    tasks_executed: u64 = 0,

    /// Tasks that completed
    tasks_completed: u64 = 0,

    /// Tasks that were cancelled
    tasks_cancelled: u64 = 0,

    /// Tasks that blocked
    tasks_blocked: u64 = 0,

    /// Budget exhaustions
    budget_exhaustions: u64 = 0,

    /// Successful steal operations
    successful_steals: u64 = 0,

    /// Failed steal attempts
    failed_steals: u64 = 0,

    /// Local queue pops
    local_pops: u64 = 0,

    /// Idle cycles
    idle_cycles: u64 = 0,

    /// Consecutive idle cycles (for backoff)
    consecutive_idle: u32 = 0,

    /// Merge stats from another worker
    pub fn merge(self: *WorkerStats, other: WorkerStats) void {
        self.tasks_executed += other.tasks_executed;
        self.tasks_completed += other.tasks_completed;
        self.tasks_cancelled += other.tasks_cancelled;
        self.tasks_blocked += other.tasks_blocked;
        self.budget_exhaustions += other.budget_exhaustions;
        self.successful_steals += other.successful_steals;
        self.failed_steals += other.failed_steals;
        self.local_pops += other.local_pops;
        self.idle_cycles += other.idle_cycles;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Worker: init creates idle worker" {
    const allocator = std.testing.allocator;

    var shutdown = Atomic(bool).init(false);
    var workers: [1]Worker = undefined;

    workers[0] = try Worker.init(allocator, 0, &workers, &shutdown, 16);
    defer workers[0].deinit();

    try std.testing.expectEqual(@as(usize, 0), workers[0].id);
    try std.testing.expectEqual(WorkerState.Idle, workers[0].state.load(.acquire));
    try std.testing.expect(workers[0].current_task == null);
}

test "Worker: push and pop task" {
    const allocator = std.testing.allocator;

    var shutdown = Atomic(bool).init(false);
    var workers: [1]Worker = undefined;

    workers[0] = try Worker.init(allocator, 0, &workers, &shutdown, 16);
    defer workers[0].deinit();

    // Create a dummy task
    const task = try Task.init(
        allocator,
        1,
        &dummyTaskFn,
        null,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    // Push and pop
    try std.testing.expect(workers[0].pushTask(task));
    try std.testing.expectEqual(task, workers[0].local_queue.pop().?);
}

test "WorkerStats: merge combines stats" {
    var stats1 = WorkerStats{
        .tasks_executed = 10,
        .successful_steals = 5,
    };

    const stats2 = WorkerStats{
        .tasks_executed = 20,
        .successful_steals = 3,
    };

    stats1.merge(stats2);

    try std.testing.expectEqual(@as(u64, 30), stats1.tasks_executed);
    try std.testing.expectEqual(@as(u64, 8), stats1.successful_steals);
}

fn dummyTaskFn(_: ?*anyopaque) callconv(.c) i64 {
    return 0;
}
