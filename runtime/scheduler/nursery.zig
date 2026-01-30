// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Nursery Integration for CBC-MN Scheduler
//!
//! Provides structured concurrency via nurseries that own child tasks.
//! All children must complete before nursery exits (no orphans).
//!
//! See: SPEC-021 Section 9 (Structured Concurrency)

const std = @import("std");
const Atomic = std.atomic.Value;

const task_mod = @import("task.zig");
const Task = task_mod.Task;
const TaskState = task_mod.TaskState;
const TaskFn = task_mod.TaskFn;
const NoArgTaskFn = task_mod.NoArgTaskFn;

const budget_mod = @import("budget.zig");
const Budget = budget_mod.Budget;
const BudgetCost = budget_mod.BudgetCost;

const worker_mod = @import("worker.zig");

// Forward declaration for explicit scheduler handle (SPEC-021 Section 2.4)
// Using opaque pointer to avoid circular import while maintaining explicit ownership
const SchedulerHandle = *anyopaque;

/// Function type for task submission (explicit, not a callback)
/// This is set by the scheduler when creating the nursery
pub const TaskSubmitFn = *const fn (SchedulerHandle, *Task) bool;

/// Nursery state (u8 for atomic compatibility)
/// State machine: Open → Closing → Closed (happy path)
///                Open → Cancelling → Cancelled (cancel path)
///                Closing → Cancelling → Cancelled (late cancel)
pub const NurseryState = enum(u8) {
    /// Nursery is accepting new children
    Open = 0,
    /// Nursery is waiting for children to complete (no new spawns)
    Closing = 1,
    /// Propagating cancellation, waiting for children to acknowledge
    Cancelling = 2,
    /// Terminal: all children completed successfully
    Closed = 3,
    /// Terminal: nursery was cancelled (with or without errors)
    Cancelled = 4,

    /// Check if state is terminal (Closed or Cancelled)
    pub fn isTerminal(self: NurseryState) bool {
        return self == .Closed or self == .Cancelled;
    }

    /// Check if state accepts new spawns
    pub fn acceptsSpawns(self: NurseryState) bool {
        return self == .Open;
    }
};

/// Child task failure information
pub const ChildError = struct {
    task_id: u64,
    error_code: i64,
};

/// Nursery completion result
pub const NurseryResult = union(enum) {
    /// All children completed successfully
    success: void,
    /// One or more children failed
    child_failed: ChildError,
    /// Nursery was cancelled
    cancelled: void,
    /// Still running
    pending: void,
};

/// Structured concurrency nursery
///
/// A nursery owns a set of child tasks and ensures they all complete
/// before the nursery itself completes. This prevents orphan tasks.
pub const Nursery = struct {
    const Self = @This();

    /// Unique nursery identifier
    id: u64,

    /// Current state
    state: Atomic(NurseryState),

    /// Budget allocated to this nursery (shared by children)
    budget: Budget,

    /// Child tasks
    children: std.ArrayListUnmanaged(*Task),

    /// Completed children count
    completed_count: Atomic(usize),

    /// First error (if any)
    first_error: ?ChildError,

    /// Parent nursery (for nested structured concurrency)
    parent_id: ?u64,

    /// Task that owns this nursery (for transitive cancellation)
    /// When the owner task is cancelled, this nursery is also cancelled.
    /// Set via setOwnerTask(), cleared when nursery completes.
    owner_task: ?*Task,

    /// Allocator
    allocator: std.mem.Allocator,

    /// Next task ID (for this nursery)
    next_task_id: Atomic(u64),

    /// Explicit scheduler handle (SPEC-021 Section 2.4.1)
    /// Stored as opaque pointer to avoid circular imports
    scheduler_handle: ?SchedulerHandle,

    /// Task submission function (set by scheduler)
    submit_fn: ?TaskSubmitFn,

    /// Task waiting on awaitAll() (Phase 9.3: yielding await)
    /// Set when a task calls awaitAll() and needs to be woken when children complete.
    /// Cleared when all children complete and task is requeued.
    waiting_task: ?*Task,

    /// Initialize a new nursery
    ///
    /// For scheduler-backed operation, use initWithScheduler().
    /// This basic init creates a standalone nursery (for tests or manual task management).
    pub fn init(
        allocator: std.mem.Allocator,
        id: u64,
        nursery_budget: Budget,
        parent_id: ?u64,
    ) Self {
        return Self{
            .id = id,
            .state = Atomic(NurseryState).init(.Open),
            .budget = nursery_budget,
            .children = .{},
            .completed_count = Atomic(usize).init(0),
            .first_error = null,
            .parent_id = parent_id,
            .owner_task = null, // Set via setOwnerTask() when task creates nursery
            .allocator = allocator,
            .next_task_id = Atomic(u64).init(id << 32), // Task IDs: nursery_id << 32 | task_seq
            .scheduler_handle = null,
            .submit_fn = null,
            .waiting_task = null, // Set in awaitAll() when task yields
        };
    }

    /// Initialize nursery with explicit scheduler handle (SPEC-021 Section 2.4.2)
    ///
    /// This is the recommended way to create nurseries for M:N scheduling.
    /// The scheduler handle and submit function are explicit, not callbacks.
    pub fn initWithScheduler(
        allocator: std.mem.Allocator,
        id: u64,
        nursery_budget: Budget,
        parent_id: ?u64,
        scheduler_handle: SchedulerHandle,
        submit_fn: TaskSubmitFn,
    ) Self {
        return Self{
            .id = id,
            .state = Atomic(NurseryState).init(.Open),
            .budget = nursery_budget,
            .children = .{},
            .completed_count = Atomic(usize).init(0),
            .first_error = null,
            .parent_id = parent_id,
            .owner_task = null, // Set via setOwnerTask() when task creates nursery
            .allocator = allocator,
            .next_task_id = Atomic(u64).init(id << 32),
            .scheduler_handle = scheduler_handle,
            .submit_fn = submit_fn,
            .waiting_task = null, // Set in awaitAll() when task yields
        };
    }

    /// Deallocate nursery and remaining children
    pub fn deinit(self: *Self) void {
        // Clean up any remaining child tasks
        for (self.children.items) |task| {
            task.deinit();
        }
        self.children.deinit(self.allocator);
    }

    /// Bind scheduler to this nursery (alternative to initWithScheduler)
    ///
    /// Allows setting scheduler after init for compatibility.
    /// Prefer initWithScheduler() for new code.
    pub fn bindScheduler(self: *Self, scheduler_handle: SchedulerHandle, submit_fn: TaskSubmitFn) void {
        self.scheduler_handle = scheduler_handle;
        self.submit_fn = submit_fn;
    }

    /// Set the task that owns this nursery (Phase 9.2: transitive cancellation)
    ///
    /// This creates a bidirectional binding:
    /// - task.owned_nursery points to this nursery
    /// - self.owner_task points to the task
    ///
    /// When the owner task is cancelled, this nursery is also cancelled.
    /// The binding is cleared when the nursery completes (in awaitAll/transitionToTerminal).
    pub fn setOwnerTask(self: *Self, task: *Task) void {
        self.owner_task = task;
        task.setOwnedNursery(self);
    }

    /// Clear the owner task binding
    ///
    /// Called when nursery completes to break the bidirectional link.
    fn clearOwnerTask(self: *Self) void {
        if (self.owner_task) |task| {
            task.clearOwnedNursery();
            self.owner_task = null;
        }
    }

    /// Spawn a new child task with function and argument
    ///
    /// Returns null if:
    /// - Nursery is not open
    /// - Spawn budget exhausted
    /// - Task allocation failed
    pub fn spawn(
        self: *Self,
        func: TaskFn,
        arg: ?*anyopaque,
    ) ?*Task {
        // Check nursery state - only Open accepts spawns
        if (!self.state.load(.acquire).acceptsSpawns()) {
            return null;
        }

        // Check spawn budget
        if (!self.budget.decrement(BudgetCost.SPAWN)) {
            return null;
        }

        // Allocate task ID
        const task_id = self.next_task_id.fetchAdd(1, .monotonic);

        // Create child task with portion of nursery budget
        const child_budget = Budget.childDefault();
        const task = Task.init(
            self.allocator,
            task_id,
            func,
            arg,
            child_budget,
            self.id,
        ) catch return null;

        // Set direct nursery pointer for worker notification
        task.nursery_ptr = self;

        // Track child
        self.children.append(self.allocator, task) catch {
            task.deinit();
            return null;
        };

        // Submit to scheduler via explicit handle (SPEC-021 Section 2.5.1)
        // This is a direct method call, NOT a callback
        if (self.submit_fn) |submit| {
            if (self.scheduler_handle) |sched| {
                if (!submit(sched, task)) {
                    // Scheduler rejected - remove from children
                    _ = self.children.pop();
                    task.deinit();
                    return null;
                }
            }
        }

        return task;
    }

    /// Spawn a no-arg task
    pub fn spawnNoArg(self: *Self, func: NoArgTaskFn) ?*Task {
        // Check nursery state - only Open accepts spawns
        if (!self.state.load(.acquire).acceptsSpawns()) {
            return null;
        }

        // Check spawn budget
        if (!self.budget.decrement(BudgetCost.SPAWN)) {
            return null;
        }

        // Allocate task ID
        const task_id = self.next_task_id.fetchAdd(1, .monotonic);

        // Create child task
        const child_budget = Budget.childDefault();
        const task = Task.initNoArg(
            self.allocator,
            task_id,
            func,
            child_budget,
            self.id,
        ) catch return null;

        // Set direct nursery pointer for worker notification
        task.nursery_ptr = self;

        // Track child
        self.children.append(self.allocator, task) catch {
            task.deinit();
            return null;
        };

        // Submit to scheduler via explicit handle (SPEC-021 Section 2.5.1)
        if (self.submit_fn) |submit| {
            if (self.scheduler_handle) |sched| {
                if (!submit(sched, task)) {
                    _ = self.children.pop();
                    task.deinit();
                    return null;
                }
            }
        }

        return task;
    }

    /// Begin closing the nursery (stop accepting new children)
    pub fn close(self: *Self) void {
        _ = self.state.cmpxchgStrong(.Open, .Closing, .acq_rel, .acquire);
    }

    /// Cancel the nursery and all children
    ///
    /// State transitions:
    /// - Open → Cancelling
    /// - Closing → Cancelling
    /// - Cancelling/Cancelled/Closed → no-op (already cancelling or terminal)
    ///
    /// Cancellation is cooperative: tasks observe it at yield points.
    pub fn cancel(self: *Self) void {
        // Attempt state transition to Cancelling
        // Try Open → Cancelling first
        if (self.state.cmpxchgStrong(.Open, .Cancelling, .acq_rel, .acquire) == null) {
            // Success: Open → Cancelling
            self.propagateCancellation();
            return;
        }

        // Try Closing → Cancelling
        if (self.state.cmpxchgStrong(.Closing, .Cancelling, .acq_rel, .acquire) == null) {
            // Success: Closing → Cancelling
            self.propagateCancellation();
            return;
        }

        // Already Cancelling, Cancelled, or Closed - no-op
    }

    /// Internal: propagate cancellation to all children
    fn propagateCancellation(self: *Self) void {
        // Mark all non-finished children as cancelled
        for (self.children.items) |task| {
            if (!task.isFinished()) {
                task.markCancelled();
            }
        }

        // TODO (Phase 9.2): Propagate to nested nurseries owned by children
        // For now, tasks with owned nurseries will observe cancellation
        // and cancel their nurseries at their next yield point.
    }

    /// Called when parent nursery is cancelled (transitive propagation)
    ///
    /// This is called by the parent to propagate cancellation down the tree.
    pub fn propagateParentCancel(self: *Self) void {
        self.cancel();
    }

    /// Notify that a child task completed
    ///
    /// Called by workers when a child task finishes (success, error, or cancelled).
    /// When all children are complete, wakes the waiting task (Phase 9.3).
    pub fn notifyChildComplete(self: *Self, task: *Task) void {
        // Track first error
        if (self.first_error == null) {
            switch (task.result) {
                .error_code => |code| {
                    self.first_error = .{
                        .task_id = task.id,
                        .error_code = code,
                    };
                },
                .panic => |_| {
                    self.first_error = .{
                        .task_id = task.id,
                        .error_code = -1, // Panic marker
                    };
                },
                else => {},
            }
        }

        // Increment completion count
        const prev_count = self.completed_count.fetchAdd(1, .acq_rel);
        const new_count = prev_count + 1;

        // Phase 9.3: Wake waiting task when all children complete
        if (new_count >= self.children.items.len) {
            if (self.waiting_task) |waiting| {
                // Only wake if task is still blocked (not cancelled/completed)
                if (waiting.state == .Blocked) {
                    // Mark task ready and requeue to scheduler
                    waiting.markReady();
                    // Submit back to scheduler
                    if (self.submit_fn) |submit| {
                        if (self.scheduler_handle) |sched| {
                            _ = submit(sched, waiting);
                        }
                    }
                }
            }
        }
    }

    /// Check if all children have completed
    pub fn allChildrenComplete(self: *const Self) bool {
        return self.completed_count.load(.acquire) >= self.children.items.len;
    }

    /// Wait for all children to complete (blocking barrier)
    ///
    /// This is the structured concurrency barrier. The nursery will not
    /// return until all children have completed, errored, or been cancelled.
    ///
    /// Phase 9.3: Yielding await
    /// - In fiber context: yields to scheduler, woken when children complete
    /// - In main thread: uses sleep-based polling (fallback)
    ///
    /// Result priority (errors beat cancellation):
    /// - child_failed: at least one child errored (first error captured)
    /// - cancelled: nursery was cancelled, all children clean exit
    /// - success: all children completed normally
    pub fn awaitAll(self: *Self) NurseryResult {
        // Close nursery to new children
        self.close();

        // Wait for all children to complete
        if (worker_mod.inFiberContext()) {
            // Fiber context: yield to scheduler and be woken when children complete
            while (!self.allChildrenComplete()) {
                // Register this task as waiting
                self.waiting_task = worker_mod.getCurrentTask();
                // Yield with blocked status - will be woken by notifyChildComplete
                worker_mod.yieldBlocked(.{ .nursery_await = self });
            }
            self.waiting_task = null;
        } else {
            // Main thread fallback: sleep-based polling
            while (!self.allChildrenComplete()) {
                std.Thread.sleep(100_000); // 100µs poll interval
            }
        }

        // Transition to terminal state
        self.transitionToTerminal();

        // Return result with error priority
        return self.computeResult();
    }

    /// Transition from Closing/Cancelling to terminal state
    fn transitionToTerminal(self: *Self) void {
        const current = self.state.load(.acquire);
        switch (current) {
            .Closing => {
                // Happy path: all children completed normally
                self.state.store(.Closed, .release);
                self.clearOwnerTask(); // Break bidirectional binding
            },
            .Cancelling => {
                // Cancel path: cancellation completed
                self.state.store(.Cancelled, .release);
                self.clearOwnerTask(); // Break bidirectional binding
            },
            .Open => {
                // Edge case: no children, immediate close
                self.state.store(.Closed, .release);
                self.clearOwnerTask(); // Break bidirectional binding
            },
            .Closed, .Cancelled => {
                // Already terminal - no-op
            },
        }
    }

    /// Compute final result with error priority (errors beat cancellation)
    fn computeResult(self: *const Self) NurseryResult {
        // Error takes priority over cancellation
        if (self.first_error) |err| {
            return .{ .child_failed = err };
        }

        // Check final state
        if (self.state.load(.acquire) == .Cancelled) {
            return .{ .cancelled = {} };
        }

        return .{ .success = {} };
    }

    /// Get nursery result without blocking
    pub fn getResult(self: *const Self) NurseryResult {
        if (!self.allChildrenComplete()) {
            return .{ .pending = {} };
        }

        return self.computeResult();
    }

    /// Check if nursery is in a terminal state
    pub fn isTerminal(self: *const Self) bool {
        return self.state.load(.acquire).isTerminal();
    }

    /// Get count of active (non-finished) children
    pub fn activeChildCount(self: *const Self) usize {
        var count: usize = 0;
        for (self.children.items) |task| {
            if (!task.isFinished()) {
                count += 1;
            }
        }
        return count;
    }

    /// Recharge all budget-exhausted children
    pub fn rechargeChildren(self: *Self, amount: Budget) void {
        for (self.children.items) |task| {
            if (task.state == .BudgetExhausted) {
                task.rechargeBudget(amount);
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

fn dummyTask(_: ?*anyopaque) callconv(.c) i64 {
    return 42;
}

fn dummyNoArgTask() callconv(.c) i64 {
    return 99;
}

test "Nursery: init creates open nursery" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    try std.testing.expectEqual(@as(u64, 1), nursery.id);
    try std.testing.expectEqual(NurseryState.Open, nursery.state.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), nursery.children.items.len);
}

test "Nursery: spawn creates child task" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    const task = nursery.spawn(&dummyTask, null);
    try std.testing.expect(task != null);
    try std.testing.expectEqual(@as(usize, 1), nursery.children.items.len);
    try std.testing.expectEqual(@as(?u64, 1), task.?.nursery_id);
}

test "Nursery: spawnNoArg creates child task" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    const task = nursery.spawnNoArg(&dummyNoArgTask);
    try std.testing.expect(task != null);
    try std.testing.expect(task.?.entry_fn_noarg != null);
}

test "Nursery: spawn fails when closed" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    nursery.close();

    const task = nursery.spawn(&dummyTask, null);
    try std.testing.expect(task == null);
}

test "Nursery: spawn fails when budget exhausted" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.zero(), // No spawn budget
        null,
    );
    defer nursery.deinit();

    const task = nursery.spawn(&dummyTask, null);
    try std.testing.expect(task == null);
}

test "Nursery: notifyChildComplete tracks completion" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    const task = nursery.spawn(&dummyTask, null).?;
    task.markRunning();
    task.markCompleted(42);

    nursery.notifyChildComplete(task);

    try std.testing.expectEqual(@as(usize, 1), nursery.completed_count.load(.acquire));
    try std.testing.expect(nursery.allChildrenComplete());
}

test "Nursery: notifyChildComplete tracks first error" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    const task = nursery.spawn(&dummyTask, null).?;
    task.markRunning();
    task.markError(-42);

    nursery.notifyChildComplete(task);

    try std.testing.expect(nursery.first_error != null);
    try std.testing.expectEqual(@as(i64, -42), nursery.first_error.?.error_code);
}

test "Nursery: cancel transitions to Cancelling and marks children" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    _ = nursery.spawn(&dummyTask, null);
    _ = nursery.spawn(&dummyTask, null);

    nursery.cancel();

    // State should be Cancelling (waiting for children to acknowledge)
    try std.testing.expectEqual(NurseryState.Cancelling, nursery.state.load(.acquire));
    // All children should be marked cancelled
    for (nursery.children.items) |task| {
        try std.testing.expectEqual(TaskState.Cancelled, task.state);
    }
}

test "Nursery: cancel from Closing state" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    _ = nursery.spawn(&dummyTask, null);

    // First close the nursery
    nursery.close();
    try std.testing.expectEqual(NurseryState.Closing, nursery.state.load(.acquire));

    // Then cancel (late cancel)
    nursery.cancel();
    try std.testing.expectEqual(NurseryState.Cancelling, nursery.state.load(.acquire));
}

test "Nursery: cancel is idempotent" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    nursery.cancel();
    try std.testing.expectEqual(NurseryState.Cancelling, nursery.state.load(.acquire));

    // Second cancel is no-op
    nursery.cancel();
    try std.testing.expectEqual(NurseryState.Cancelling, nursery.state.load(.acquire));
}

test "Nursery: awaitAll returns cancelled after cancel" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    const task = nursery.spawn(&dummyTask, null).?;

    // Cancel the nursery
    nursery.cancel();

    // Simulate child acknowledging cancellation (completes as cancelled)
    task.markCancelled();
    nursery.notifyChildComplete(task);

    // Now await should return cancelled
    const result = nursery.awaitAll();
    try std.testing.expectEqual(NurseryResult.cancelled, result);
    try std.testing.expectEqual(NurseryState.Cancelled, nursery.state.load(.acquire));
}

test "Nursery: error beats cancellation" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    const task1 = nursery.spawn(&dummyTask, null).?;
    const task2 = nursery.spawn(&dummyTask, null).?;

    // First task errors
    task1.markRunning();
    task1.markError(-99);
    nursery.notifyChildComplete(task1);

    // Then cancel
    nursery.cancel();

    // Second task acknowledges cancel
    task2.markCancelled();
    nursery.notifyChildComplete(task2);

    // Error should beat cancellation
    const result = nursery.awaitAll();
    switch (result) {
        .child_failed => |err| {
            try std.testing.expectEqual(@as(i64, -99), err.error_code);
        },
        else => try std.testing.expect(false),
    }
}

// ============================================================================
// Phase 9.2: Nested Nursery Cancellation Tests
// ============================================================================

test "Nursery: setOwnerTask creates bidirectional binding" {
    const allocator = std.testing.allocator;

    // Create a task (standalone for this test)
    const task = try Task.init(
        allocator,
        1,
        &dummyTask,
        null,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    // Create a nursery that will be owned by the task
    var child_nursery = Nursery.init(
        allocator,
        2,
        Budget.serviceDefault(),
        null,
    );
    defer child_nursery.deinit();

    // Establish bidirectional binding
    child_nursery.setOwnerTask(task);

    // Verify both directions are set
    try std.testing.expect(child_nursery.owner_task != null);
    try std.testing.expectEqual(task, child_nursery.owner_task.?);
    try std.testing.expect(task.hasOwnedNursery());
}

test "Nursery: task cancellation propagates to owned nursery" {
    const allocator = std.testing.allocator;

    // Create a task that owns a nursery
    const task = try Task.init(
        allocator,
        1,
        &dummyTask,
        null,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    // Create child nursery owned by the task
    var child_nursery = Nursery.init(
        allocator,
        2,
        Budget.serviceDefault(),
        null,
    );
    defer child_nursery.deinit();

    // Spawn a grandchild task in the child nursery
    const grandchild = child_nursery.spawn(&dummyTask, null);
    try std.testing.expect(grandchild != null);

    // Establish binding: task owns child_nursery
    child_nursery.setOwnerTask(task);

    // Verify initial states
    try std.testing.expectEqual(NurseryState.Open, child_nursery.state.load(.acquire));
    try std.testing.expectEqual(TaskState.Ready, grandchild.?.state);

    // Cancel the owner task - should propagate to child_nursery
    task.markCancelled();

    // Child nursery should now be Cancelling
    try std.testing.expectEqual(NurseryState.Cancelling, child_nursery.state.load(.acquire));

    // Grandchild should be marked cancelled
    try std.testing.expectEqual(TaskState.Cancelled, grandchild.?.state);
}

test "Nursery: transitive cancellation through nested nurseries" {
    const allocator = std.testing.allocator;

    // Create parent nursery
    var parent_nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer parent_nursery.deinit();

    // Create middle task (owned by parent_nursery)
    const middle_task = parent_nursery.spawn(&dummyTask, null);
    try std.testing.expect(middle_task != null);

    // Create child nursery (owned by middle_task)
    var child_nursery = Nursery.init(
        allocator,
        2,
        Budget.serviceDefault(),
        1, // parent_id
    );
    defer child_nursery.deinit();

    // Create leaf task (owned by child_nursery)
    const leaf_task = child_nursery.spawn(&dummyTask, null);
    try std.testing.expect(leaf_task != null);

    // Establish binding: middle_task owns child_nursery
    child_nursery.setOwnerTask(middle_task.?);

    // Verify initial states
    try std.testing.expectEqual(NurseryState.Open, parent_nursery.state.load(.acquire));
    try std.testing.expectEqual(NurseryState.Open, child_nursery.state.load(.acquire));
    try std.testing.expectEqual(TaskState.Ready, middle_task.?.state);
    try std.testing.expectEqual(TaskState.Ready, leaf_task.?.state);

    // Cancel parent nursery - should cascade:
    // parent_nursery.cancel() -> middle_task.markCancelled() -> child_nursery.cancel() -> leaf_task.markCancelled()
    parent_nursery.cancel();

    // All should be cancelling/cancelled
    try std.testing.expectEqual(NurseryState.Cancelling, parent_nursery.state.load(.acquire));
    try std.testing.expectEqual(TaskState.Cancelled, middle_task.?.state);
    try std.testing.expectEqual(NurseryState.Cancelling, child_nursery.state.load(.acquire));
    try std.testing.expectEqual(TaskState.Cancelled, leaf_task.?.state);
}

test "Nursery: clearOwnerTask breaks binding" {
    const allocator = std.testing.allocator;

    const task = try Task.init(
        allocator,
        1,
        &dummyTask,
        null,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    var child_nursery = Nursery.init(
        allocator,
        2,
        Budget.serviceDefault(),
        null,
    );
    defer child_nursery.deinit();

    // Establish binding
    child_nursery.setOwnerTask(task);
    try std.testing.expect(child_nursery.owner_task != null);
    try std.testing.expect(task.hasOwnedNursery());

    // Clear binding (internal function, but test via simulate completion)
    child_nursery.clearOwnerTask();

    // Both sides should be cleared
    try std.testing.expect(child_nursery.owner_task == null);
    try std.testing.expect(!task.hasOwnedNursery());
}

test "Nursery: terminal state clears owner binding" {
    const allocator = std.testing.allocator;

    const task = try Task.init(
        allocator,
        1,
        &dummyTask,
        null,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    var child_nursery = Nursery.init(
        allocator,
        2,
        Budget.serviceDefault(),
        null,
    );
    defer child_nursery.deinit();

    // Spawn a child in the nursery
    const child_task = child_nursery.spawn(&dummyTask, null).?;

    // Establish binding
    child_nursery.setOwnerTask(task);
    try std.testing.expect(task.hasOwnedNursery());

    // Complete the child task
    child_task.markRunning();
    child_task.markCompleted(42);
    child_nursery.notifyChildComplete(child_task);

    // awaitAll should transition to terminal and clear binding
    _ = child_nursery.awaitAll();

    // Binding should be cleared after terminal state
    try std.testing.expect(child_nursery.owner_task == null);
    try std.testing.expect(!task.hasOwnedNursery());
    try std.testing.expectEqual(NurseryState.Closed, child_nursery.state.load(.acquire));
}

test "Nursery: propagateParentCancel calls cancel" {
    const allocator = std.testing.allocator;

    var nursery = Nursery.init(
        allocator,
        1,
        Budget.serviceDefault(),
        null,
    );
    defer nursery.deinit();

    _ = nursery.spawn(&dummyTask, null);

    // Verify initial state
    try std.testing.expectEqual(NurseryState.Open, nursery.state.load(.acquire));

    // Simulate parent cancellation
    nursery.propagateParentCancel();

    // Should be in Cancelling state
    try std.testing.expectEqual(NurseryState.Cancelling, nursery.state.load(.acquire));
}
