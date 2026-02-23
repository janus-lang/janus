// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! CBC-MN Scheduler - Sovereign Index
//!
//! Capability-Budgeted Cooperative M:N Scheduler for Janus Runtime.
//!
//! This module provides lightweight task execution with:
//! - Budget-driven yielding (deterministic, portable)
//! - Work-stealing load balancing (Chase-Lev deque)
//! - Structured concurrency via nurseries
//! - Capability-gated spawning for DoS immunity
//!
//! ## Usage
//!
//! ```zig
//! const sched = @import("scheduler.zig");
//!
//! // Initialize scheduler with 4 workers
//! var scheduler = try sched.Scheduler.init(allocator, 4);
//! defer scheduler.deinit();
//!
//! // Create a nursery
//! var nursery = scheduler.createNursery(sched.Budget.serviceDefault());
//! defer nursery.deinit();
//!
//! // Spawn tasks
//! _ = nursery.spawn(&myTask, null);
//!
//! // Wait for completion
//! const result = nursery.awaitAll();
//! ```
//!
//! ## Architecture
//!
//! ```
//! scheduler.zig          # This file (Sovereign Index)
//! └── scheduler/
//!     ├── budget.zig     # Budget types and costs
//!     ├── task.zig       # Task struct and state machine
//!     ├── continuation.zig # x86_64 context switch
//!     ├── worker.zig     # Worker thread loop
//!     ├── deque.zig      # Chase-Lev work-stealing deque
//!     └── nursery.zig    # Structured concurrency
//! ```
//!
//! ## Specifications
//!
//! - SPEC-021: M:N Scheduler
//! - SPEC-022: Scheduling Capabilities

const std = @import("std");
const Atomic = std.atomic.Value;

// Re-export core types
pub const budget = @import("scheduler/budget.zig");
pub const Budget = budget.Budget;
pub const BudgetCost = budget.BudgetCost;

pub const task = @import("scheduler/task.zig");
pub const Task = task.Task;
pub const TaskState = task.TaskState;
pub const TaskResult = task.TaskResult;
pub const TaskFn = task.TaskFn;
pub const NoArgTaskFn = task.NoArgTaskFn;
pub const Priority = task.Priority;
pub const BlockedOn = task.BlockedOn;

pub const continuation = @import("scheduler/continuation.zig");
pub const Context = continuation.Context;

pub const worker = @import("scheduler/worker.zig");
pub const Worker = worker.Worker;
pub const WorkerState = worker.WorkerState;
pub const WorkerStats = worker.WorkerStats;

pub const deque = @import("scheduler/deque.zig");
pub const WorkStealingDeque = deque.WorkStealingDeque;

pub const nursery = @import("scheduler/nursery.zig");
pub const Nursery = nursery.Nursery;
pub const NurseryState = nursery.NurseryState;
pub const NurseryResult = nursery.NurseryResult;

pub const cancel_token = @import("scheduler/cancel_token.zig");
pub const CancelToken = cancel_token.CancelToken;
pub const CancelReason = cancel_token.CancelReason;
pub const CancellationError = cancel_token.CancellationError;
pub const CombinedToken = cancel_token.CombinedToken;

/// Default number of workers (typically = CPU cores)
const DEFAULT_WORKER_COUNT: usize = 4;

/// Default deque capacity per worker
const DEFAULT_DEQUE_CAPACITY: usize = 256;

/// Scheduler state (u8 for atomic compatibility)
pub const SchedulerState = enum(u8) {
    /// Not yet started
    Idle = 0,
    /// Running and accepting work
    Running = 1,
    /// Shutting down
    Stopping = 2,
    /// Fully stopped
    Stopped = 3,
};

/// M:N Scheduler
///
/// The central scheduler that manages workers and task distribution.
/// Implements work-stealing for load balancing across CPU cores.
pub const Scheduler = struct {
    const Self = @This();

    /// Workers array
    workers: []Worker,

    /// Worker threads
    threads: []std.Thread,

    /// Number of workers
    worker_count: usize,

    /// Scheduler state
    state: Atomic(SchedulerState),

    /// Shutdown signal (shared by all workers)
    shutdown: Atomic(bool),

    /// Next nursery ID
    next_nursery_id: Atomic(u64),

    /// Round-robin counter for task distribution
    next_worker: Atomic(usize),

    /// Allocator
    allocator: std.mem.Allocator,

    /// Initialize scheduler with specified number of workers
    pub fn init(allocator: std.mem.Allocator, worker_count: usize) !*Self {
        const count = if (worker_count == 0) DEFAULT_WORKER_COUNT else worker_count;

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .workers = undefined,
            .threads = undefined,
            .worker_count = count,
            .state = Atomic(SchedulerState).init(.Idle),
            .shutdown = Atomic(bool).init(false),
            .next_nursery_id = Atomic(u64).init(1),
            .next_worker = Atomic(usize).init(0),
            .allocator = allocator,
        };

        // Allocate workers
        self.workers = try allocator.alloc(Worker, count);
        errdefer allocator.free(self.workers);

        // Initialize workers (each needs reference to all workers for stealing)
        for (self.workers, 0..) |*w, i| {
            w.* = try Worker.init(
                allocator,
                i,
                self.workers,
                &self.shutdown,
                DEFAULT_DEQUE_CAPACITY,
            );
        }

        // Allocate thread handles
        self.threads = try allocator.alloc(std.Thread, count);

        return self;
    }

    /// Initialize with default worker count (CPU cores)
    pub fn initDefault(allocator: std.mem.Allocator) !*Self {
        const cpu_count = std.Thread.getCpuCount() catch DEFAULT_WORKER_COUNT;
        return init(allocator, cpu_count);
    }

    /// Deallocate scheduler
    pub fn deinit(self: *Self) void {
        // Ensure stopped
        if (self.state.load(.acquire) == .Running) {
            self.stop();
        }

        // Cleanup workers
        for (self.workers) |*w| {
            w.deinit();
        }

        self.allocator.free(self.workers);
        self.allocator.free(self.threads);
        self.allocator.destroy(self);
    }

    /// Start the scheduler (spawn worker threads)
    pub fn start(self: *Self) !void {
        if (self.state.load(.acquire) != .Idle) {
            return error.AlreadyRunning;
        }

        self.state.store(.Running, .release);
        self.shutdown.store(false, .release);

        // Spawn worker threads
        for (self.threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerThreadMain, .{&self.workers[i]});
        }
    }

    /// Stop the scheduler (signal shutdown and wait for workers)
    pub fn stop(self: *Self) void {
        if (self.state.load(.acquire) != .Running) {
            return;
        }

        self.state.store(.Stopping, .release);
        self.shutdown.store(true, .release);

        // Wait for all workers to stop
        for (self.threads) |thread| {
            thread.join();
        }

        self.state.store(.Stopped, .release);
    }

    /// Create a new nursery with explicit scheduler binding (SPEC-021 Section 2.4)
    ///
    /// The nursery stores an explicit handle to this scheduler.
    /// No callbacks - task submission is a direct method call.
    pub fn createNursery(self: *Self, nursery_budget: Budget) Nursery {
        const id = self.next_nursery_id.fetchAdd(1, .monotonic);
        // Use explicit scheduler handle instead of callback
        return Nursery.initWithScheduler(
            self.allocator,
            id,
            nursery_budget,
            null, // parent_id
            @ptrCast(self), // scheduler handle (opaque)
            &schedulerSubmitTask, // explicit submit function
        );
    }

    /// Submit a task to the scheduler
    ///
    /// Uses round-robin distribution to balance load.
    pub fn submitTask(self: *Self, t: *Task) bool {
        if (self.state.load(.acquire) != .Running) {
            return false;
        }

        // Round-robin worker selection
        const worker_idx = self.next_worker.fetchAdd(1, .monotonic) % self.worker_count;
        return self.workers[worker_idx].pushTask(t);
    }

    /// Get aggregated statistics from all workers
    pub fn getStats(self: *const Self) WorkerStats {
        var stats = WorkerStats{};
        for (self.workers) |*w| {
            stats.merge(w.getStats());
        }
        return stats;
    }

    /// Check if scheduler is running
    pub fn isRunning(self: *const Self) bool {
        return self.state.load(.acquire) == .Running;
    }

    /// Get number of workers
    pub fn getWorkerCount(self: *const Self) usize {
        return self.worker_count;
    }
};

/// Worker thread entry point
fn workerThreadMain(w: *Worker) void {
    w.run();
}

/// Task submission function for nurseries (SPEC-021 Section 2.5.1)
///
/// This is called by Nursery.spawn() with the explicit scheduler handle.
/// The handle is cast back to *Scheduler to submit the task.
/// This is a direct method call, NOT a callback pattern.
fn schedulerSubmitTask(scheduler_handle: *anyopaque, t: *Task) bool {
    const self: *Scheduler = @ptrCast(@alignCast(scheduler_handle));
    return self.submitTask(t);
}

// ============================================================================
// Profile-Specific Defaults
// ============================================================================

/// Get default budget for a profile
pub fn profileBudget(profile: Profile) Budget {
    return switch (profile) {
        .core => Budget.zero(), // :core has no concurrency
        .service => Budget.serviceDefault(),
        .cluster => Budget.clusterDefault(),
        .sovereign => Budget.serviceDefault(), // Explicit via capabilities
    };
}

/// Janus runtime profiles
pub const Profile = enum {
    /// No concurrency (sync only)
    core,
    /// Cooperative M:N (implicit caps)
    service,
    /// Actors + supervisors (rechargeable)
    cluster,
    /// Explicit capability gating
    sovereign,
};

// ============================================================================
// Tests
// ============================================================================

test "Scheduler: init creates idle scheduler" {
    const allocator = std.testing.allocator;

    const scheduler = try Scheduler.init(allocator, 2);
    defer scheduler.deinit();

    try std.testing.expectEqual(@as(usize, 2), scheduler.worker_count);
    try std.testing.expectEqual(SchedulerState.Idle, scheduler.state.load(.acquire));
}

test "Scheduler: createNursery allocates unique IDs" {
    const allocator = std.testing.allocator;

    const scheduler = try Scheduler.init(allocator, 1);
    defer scheduler.deinit();

    var n1 = scheduler.createNursery(Budget.serviceDefault());
    defer n1.deinit();

    var n2 = scheduler.createNursery(Budget.serviceDefault());
    defer n2.deinit();

    try std.testing.expect(n1.id != n2.id);
}

test "Budget: re-export works" {
    const b = Budget.serviceDefault();
    try std.testing.expect(!b.isExhausted());
}

test "Task: re-export works" {
    try std.testing.expectEqual(TaskState.Ready, TaskState.Ready);
}

test "profileBudget: returns correct defaults" {
    const core_budget = profileBudget(.core);
    try std.testing.expect(core_budget.isExhausted()); // Zero budget

    const service_budget = profileBudget(.service);
    try std.testing.expect(!service_budget.isExhausted());
}
