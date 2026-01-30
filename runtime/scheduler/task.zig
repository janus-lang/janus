// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Task representation for CBC-MN scheduler
//!
//! A Task is a lightweight unit of execution with its own stack and budget.
//! Tasks are managed by the scheduler and owned by nurseries.
//!
//! See: SPEC-021 Section 5 (Task Model)

const std = @import("std");
const budget_mod = @import("budget.zig");
const Budget = budget_mod.Budget;
const continuation_mod = @import("continuation.zig");
const worker_mod = @import("worker.zig");
const nursery_mod = @import("nursery.zig");
const Nursery = nursery_mod.Nursery;

/// Task execution states
///
/// State machine:
/// ```
///          ┌─────────┐
///          │  Ready  │◄────────────────────────┐
///          └────┬────┘                         │
///               │ schedule                     │ wake
///               ▼                              │
///          ┌─────────┐                    ┌────┴────┐
///          │ Running │───────yield───────►│ Blocked │
///          └────┬────┘                    └─────────┘
///               │                              ▲
///   ┌───────────┼───────────┐                  │
///   │           │           │                  │
///   ▼           ▼           ▼                  │
/// ┌──────────┐ ┌─────────┐ ┌───────────────┐  │
/// │Completed │ │Cancelled│ │BudgetExhausted├──┘
/// └──────────┘ └─────────┘ └───────────────┘
/// ```
pub const TaskState = enum {
    /// Can be scheduled for execution
    Ready,
    /// Currently executing on a worker
    Running,
    /// Waiting on channel/IO operation
    Blocked,
    /// Budget exhausted, needs recharge
    BudgetExhausted,
    /// Execution completed successfully
    Completed,
    /// Aborted by parent nursery
    Cancelled,
};

/// Task completion result
pub const TaskResult = union(enum) {
    /// Not yet completed
    pending: void,
    /// Completed with success value
    success: i64,
    /// Completed with error code
    error_code: i64,
    /// Task panicked
    panic: []const u8,
};

/// Task priority hint for scheduling
pub const Priority = enum {
    Low,
    Normal,
    High,
};

/// Blocked reason (when state == .Blocked)
pub const BlockedOn = union(enum) {
    /// Not blocked
    none: void,
    /// Waiting to send on channel
    channel_send: struct {
        channel: *anyopaque,
        value: i64,
    },
    /// Waiting to receive from channel
    channel_recv: *anyopaque,
    /// Waiting for another task
    task_join: u64,
    /// Waiting for I/O
    io: void,
    /// Waiting for nursery children to complete (Phase 9.3)
    nursery_await: *anyopaque,
};

/// Function signature for task entry point
pub const TaskFn = *const fn (?*anyopaque) callconv(.c) i64;

/// Function signature for no-arg task entry point
pub const NoArgTaskFn = *const fn () callconv(.c) i64;

/// Saved CPU registers for context switch (x86_64)
pub const SavedRegisters = extern struct {
    rbx: u64 = 0,
    rbp: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,
};

/// Task represents a lightweight execution unit
pub const Task = struct {
    /// Unique task identifier
    id: u64,

    /// Current execution state
    state: TaskState,

    /// Resource budget
    budget: Budget,

    /// Task priority hint
    priority: Priority,

    /// Completion result
    result: TaskResult,

    /// Blocked reason (valid when state == .Blocked)
    blocked_on: BlockedOn,

    /// Parent nursery ID (for structured concurrency)
    nursery_id: ?u64,

    /// Direct pointer to parent nursery (opaque to avoid circular imports)
    /// Set by Nursery.spawn() after task creation
    nursery_ptr: ?*anyopaque,

    /// Pointer to nursery owned by this task (for nested structured concurrency)
    /// When this task is cancelled, owned_nursery is also cancelled (transitive propagation)
    /// Set by the task when it creates a nursery block
    owned_nursery: ?*anyopaque,

    /// Entry point function
    entry_fn: ?TaskFn,

    /// Entry point argument
    entry_arg: ?*anyopaque,

    /// No-arg entry point (alternative)
    entry_fn_noarg: ?NoArgTaskFn,

    // ========================================================================
    // Fiber state (stackful continuation)
    // ========================================================================

    /// Dedicated stack memory
    stack: ?[]align(16) u8,

    /// Current stack pointer
    sp: usize,

    /// Saved registers
    registers: SavedRegisters,

    /// Allocator for stack
    allocator: std.mem.Allocator,

    /// Stack size constant
    pub const STACK_SIZE: usize = 8 * 1024; // 8KB

    /// Create a new task with function and argument
    pub fn init(
        allocator: std.mem.Allocator,
        id: u64,
        func: TaskFn,
        arg: ?*anyopaque,
        task_budget: Budget,
        nursery_id: ?u64,
    ) !*Task {
        const task = try allocator.create(Task);
        errdefer allocator.destroy(task);

        // Allocate stack (16-byte aligned for System V ABI)
        const stack = try allocator.alignedAlloc(u8, .@"16", STACK_SIZE);
        errdefer allocator.free(stack);

        task.* = Task{
            .id = id,
            .state = .Ready,
            .budget = task_budget,
            .priority = .Normal,
            .result = .{ .pending = {} },
            .blocked_on = .{ .none = {} },
            .nursery_id = nursery_id,
            .nursery_ptr = null, // Set by Nursery.spawn() after creation
            .owned_nursery = null, // Set when task creates a nursery block
            .entry_fn = func,
            .entry_arg = arg,
            .entry_fn_noarg = null,
            .stack = stack,
            .sp = @intFromPtr(stack.ptr) + stack.len,
            .registers = .{},
            .allocator = allocator,
        };

        // Setup initial stack frame
        task.setupStack();

        return task;
    }

    /// Create a new task with no-arg function
    pub fn initNoArg(
        allocator: std.mem.Allocator,
        id: u64,
        func: NoArgTaskFn,
        task_budget: Budget,
        nursery_id: ?u64,
    ) !*Task {
        const task = try allocator.create(Task);
        errdefer allocator.destroy(task);

        // Allocate stack (16-byte aligned for System V ABI)
        const stack = try allocator.alignedAlloc(u8, .@"16", STACK_SIZE);
        errdefer allocator.free(stack);

        task.* = Task{
            .id = id,
            .state = .Ready,
            .budget = task_budget,
            .priority = .Normal,
            .result = .{ .pending = {} },
            .blocked_on = .{ .none = {} },
            .nursery_id = nursery_id,
            .nursery_ptr = null, // Set by Nursery.spawn() after creation
            .owned_nursery = null, // Set when task creates a nursery block
            .entry_fn = null,
            .entry_arg = null,
            .entry_fn_noarg = func,
            .stack = stack,
            .sp = @intFromPtr(stack.ptr) + stack.len,
            .registers = .{},
            .allocator = allocator,
        };

        // Setup initial stack frame
        task.setupStack();

        return task;
    }

    /// Setup initial stack frame for task startup
    ///
    /// Initializes the fiber context so that when switched to,
    /// execution begins at the entry function.
    fn setupStack(self: *Task) void {
        const stack = self.stack orelse return;

        // Determine entry function
        if (self.entry_fn) |entry_fn| {
            // Task with argument
            var ctx = continuation_mod.Context.init();
            continuation_mod.initFiberContext(
                &ctx,
                stack,
                entry_fn,
                self.entry_arg,
                &taskCleanupTrampoline,
            );
            // Copy context to task
            self.sp = ctx.sp;
            self.registers = ctx.regs;
        } else if (self.entry_fn_noarg) |noarg_fn| {
            // Task without argument - wrap it
            var ctx = continuation_mod.Context.init();
            // Store the no-arg function pointer in entry_arg for the wrapper
            self.entry_arg = @ptrCast(@constCast(noarg_fn));
            continuation_mod.initFiberContext(
                &ctx,
                stack,
                &noArgWrapper,
                self.entry_arg,
                &taskCleanupTrampoline,
            );
            self.sp = ctx.sp;
            self.registers = ctx.regs;
        }
    }

    /// Wrapper for no-arg task functions
    fn noArgWrapper(arg: ?*anyopaque) callconv(.c) i64 {
        const fn_ptr: NoArgTaskFn = @ptrCast(@alignCast(arg));
        return fn_ptr();
    }

    /// Cleanup and deallocate task
    pub fn deinit(self: *Task) void {
        if (self.stack) |stack| {
            self.allocator.free(stack);
        }
        self.allocator.destroy(self);
    }

    /// Check if task can be scheduled
    pub fn canRun(self: *const Task) bool {
        return self.state == .Ready;
    }

    /// Check if task is finished (Completed or Cancelled)
    pub fn isFinished(self: *const Task) bool {
        return self.state == .Completed or self.state == .Cancelled;
    }

    /// Transition to running state
    pub fn markRunning(self: *Task) void {
        std.debug.assert(self.state == .Ready);
        self.state = .Running;
    }

    /// Transition to blocked state
    pub fn markBlocked(self: *Task, reason: BlockedOn) void {
        std.debug.assert(self.state == .Running);
        self.state = .Blocked;
        self.blocked_on = reason;
    }

    /// Transition to ready state (from blocked)
    pub fn markReady(self: *Task) void {
        std.debug.assert(self.state == .Blocked or self.state == .BudgetExhausted);
        self.state = .Ready;
        self.blocked_on = .{ .none = {} };
    }

    /// Transition to budget exhausted state
    pub fn markBudgetExhausted(self: *Task) void {
        std.debug.assert(self.state == .Running);
        self.state = .BudgetExhausted;
    }

    /// Transition to completed state
    pub fn markCompleted(self: *Task, result_value: i64) void {
        self.state = .Completed;
        self.result = .{ .success = result_value };
    }

    /// Transition to error state
    pub fn markError(self: *Task, error_code: i64) void {
        self.state = .Completed;
        self.result = .{ .error_code = error_code };
    }

    /// Transition to cancelled state
    /// Mark task as cancelled
    ///
    /// If this task owns a nursery, cancellation is propagated transitively
    /// to that nursery (and all its children). This ensures structured
    /// concurrency cleanup propagates through the entire task tree.
    pub fn markCancelled(self: *Task) void {
        self.state = .Cancelled;

        // Propagate cancellation to owned nursery (Phase 9.2: transitive cancellation)
        if (self.owned_nursery) |ptr| {
            const owned: *Nursery = @ptrCast(@alignCast(ptr));
            owned.propagateParentCancel();
        }
    }

    /// Set the nursery owned by this task
    ///
    /// Called when a task creates a nursery block. The owned nursery
    /// will be cancelled if this task is cancelled (transitive propagation).
    pub fn setOwnedNursery(self: *Task, nursery: *Nursery) void {
        self.owned_nursery = nursery;
    }

    /// Clear the owned nursery (called when nursery completes)
    pub fn clearOwnedNursery(self: *Task) void {
        self.owned_nursery = null;
    }

    /// Check if task owns a nursery
    pub fn hasOwnedNursery(self: *const Task) bool {
        return self.owned_nursery != null;
    }

    /// Recharge task budget
    pub fn rechargeBudget(self: *Task, amount: Budget) void {
        self.budget.add(amount);
        if (self.state == .BudgetExhausted) {
            self.state = .Ready;
        }
    }
};

/// Cleanup trampoline called when task returns
///
/// This is invoked by janus_fiber_entry after the task's entry function
/// returns. The result value is passed as the first argument.
///
/// Signature: fn(result: i64) callconv(.c) void
fn taskCleanupTrampoline(result: i64) callconv(.c) void {
    // Mark task complete and yield back to worker
    worker_mod.yieldComplete(result);

    // Should never reach here - yieldComplete switches context
    // Safety fallback: infinite loop
    while (true) {
        std.atomic.spinLoopHint();
    }
}

// ============================================================================
// Tests
// ============================================================================

fn dummyTask(_: ?*anyopaque) callconv(.c) i64 {
    return 42;
}

fn dummyNoArgTask() callconv(.c) i64 {
    return 42;
}

test "Task: init creates task in Ready state" {
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

    try std.testing.expectEqual(TaskState.Ready, task.state);
    try std.testing.expectEqual(@as(u64, 1), task.id);
    try std.testing.expect(task.stack != null);
}

test "Task: initNoArg creates task with no-arg function" {
    const allocator = std.testing.allocator;

    const task = try Task.initNoArg(
        allocator,
        2,
        &dummyNoArgTask,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    try std.testing.expectEqual(TaskState.Ready, task.state);
    try std.testing.expect(task.entry_fn_noarg != null);
    try std.testing.expect(task.entry_fn == null);
}

test "Task: state transitions" {
    const allocator = std.testing.allocator;

    const task = try Task.init(
        allocator,
        3,
        &dummyTask,
        null,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    // Ready -> Running
    task.markRunning();
    try std.testing.expectEqual(TaskState.Running, task.state);

    // Running -> Blocked
    task.markBlocked(.{ .channel_recv = @ptrFromInt(0x1000) });
    try std.testing.expectEqual(TaskState.Blocked, task.state);

    // Blocked -> Ready
    task.markReady();
    try std.testing.expectEqual(TaskState.Ready, task.state);
}

test "Task: completion states" {
    const allocator = std.testing.allocator;

    const task = try Task.init(
        allocator,
        4,
        &dummyTask,
        null,
        Budget.childDefault(),
        null,
    );
    defer task.deinit();

    task.markRunning();
    task.markCompleted(42);

    try std.testing.expectEqual(TaskState.Completed, task.state);
    try std.testing.expectEqual(TaskResult{ .success = 42 }, task.result);
    try std.testing.expect(task.isFinished());
}

test "Task: budget exhaustion" {
    const allocator = std.testing.allocator;

    const task = try Task.init(
        allocator,
        5,
        &dummyTask,
        null,
        Budget.zero(),
        null,
    );
    defer task.deinit();

    task.markRunning();
    task.markBudgetExhausted();

    try std.testing.expectEqual(TaskState.BudgetExhausted, task.state);

    // Recharge
    task.rechargeBudget(Budget.childDefault());
    try std.testing.expectEqual(TaskState.Ready, task.state);
    try std.testing.expect(!task.budget.isExhausted());
}
