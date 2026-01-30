<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# SPEC-021: Capability-Budgeted Cooperative M:N Scheduler (CBC-MN)

**Version:** 1.0.0
**Status:** DRAFT
**Authority:** Constitutional
**Supersedes:** None
**Depends On:** SPEC-002 (Profiles), SPEC-003 (Runtime), SPEC-019 (:service Profile)

---

## 1. Introduction

This specification defines the **Capability-Budgeted Cooperative M:N Scheduler** (CBC-MN), a novel runtime scheduler for the Janus language that enables lightweight concurrent execution with language-level DoS immunity.

### 1.1 Design Philosophy

[SCHED:1.1.1] The scheduler uses **budget units** as the yield primitive, NOT time ticks. This provides:

- **Determinism**: Same input produces same execution order
- **Portability**: No OS timer dependency
- **Fairness**: CPU-bound and IO-bound tasks treated equivalently
- **DoS Resistance**: Budget caps prevent runaway tasks

[SCHED:1.1.2] The scheduler implements **capability-gated spawning**: tasks MUST hold a capability token to spawn children or consume budget. No capability = no spawn = language-level DoS immunity.

### 1.2 Scope

This specification covers:

- Task representation and lifecycle
- Budget model and yield semantics
- Work-stealing algorithm
- Worker thread management
- Nursery integration
- Determinism guarantees

---

## 2. Runtime Root Architecture

### 2.1 Design Principle

[SCHED:2.1.1] **No Invisible Authority**: Even the scheduler MUST be passed or owned explicitly. Janus does NOT do:
- Hidden TLS (thread-local storage)
- Ambient globals
- Magical callbacks
- Implicit state

[SCHED:2.1.2] **Single Runtime Root**: There SHALL be exactly ONE global root: the `Runtime`. The scheduler is a subsystem of Runtime, not a standalone global.

```
CORRECT:    GLOBAL_RT: ?*Runtime  (one global)
FORBIDDEN:  GLOBAL_SCHEDULER: ?*Scheduler  (hidden authority)
```

### 2.2 Runtime Structure

[SCHED:2.2.1] The Runtime SHALL own all subsystems:

```zig
pub const Runtime = struct {
    scheduler:   *Scheduler,     // M:N task scheduler
    allocator:   Allocator,      // Memory allocation
    // Future subsystems:
    // io_context:  *IoContext,  // Event loop
    // cap_context: *CapContext, // Capability store
    // profiler:    *Profiler,   // Runtime profiling
};
```

[SCHED:2.2.2] Only ONE global variable is permitted:

```zig
var GLOBAL_RT: ?*Runtime = null;  // The ONLY global
```

[SCHED:2.2.3] **Scope Clarification**: The global Runtime is a convenience for the default embedding. Alternative runtimes MAY exist (for testing, embedding, sandboxing) and MUST NOT rely on `GLOBAL_RT`. The global is optional infrastructure, not mandatory architecture.

[SCHED:2.2.4] **Reach-Around Prohibition**: Subsystems MUST NOT access `GLOBAL_RT` directly. All access SHALL be via explicit parameters or derived handles. This prevents hidden coupling and maintains the explicit authority principle.

```zig
// FORBIDDEN: Direct global access from subsystem
fn nurserySpawn(...) {
    GLOBAL_RT.?.scheduler.spawn(...);  // NO! Hidden authority
}

// REQUIRED: Explicit parameter
fn nurserySpawn(scheduler: *Scheduler, ...) {
    scheduler.spawn(...);  // YES! Explicit
}
```

### 2.3 Scheduler as Subsystem

[SCHED:2.3.1] The scheduler is NOT special. It is a subsystem like any other, owned by Runtime.

[SCHED:2.3.2] Benefits of this architecture:

| Concern | Global Scheduler | Runtime Root (required) |
|---------|------------------|-------------------------|
| Test isolation | ❌ Hard | ✅ Easy |
| Multiple runtimes | ❌ Impossible | ✅ Natural |
| Embedding Janus | ❌ Painful | ✅ Clean |
| Capability routing | ❌ Implicit | ✅ Explicit |
| Future IO integration | ❌ Tangled | ✅ Layered |

### 2.4 Nursery-Scheduler Binding

[SCHED:2.4.1] Nurseries SHALL store an explicit scheduler handle, NOT use callbacks:

```zig
// CORRECT: Explicit handle
pub const Nursery = struct {
    scheduler: *Scheduler,      // Explicit reference
    parent_task: ?TaskId,       // Structured concurrency
    budget: Budget,             // Resource limits
};

// FORBIDDEN: Callback-based
// spawn_callback: *const fn (*Task) bool  // NO!
```

[SCHED:2.4.2] Nursery creation SHALL derive scheduler from Runtime:

```zig
pub fn nurseryEnter(rt: *Runtime) Nursery {
    return Nursery{
        .scheduler = rt.scheduler,
        .parent_task = rt.scheduler.currentTask(),
        .budget = Budget.default(),
    };
}
```

### 2.5 Task Submission

[SCHED:2.5.1] Task submission SHALL be a direct method call, NOT a callback:

```zig
// CORRECT: Direct method
pub fn spawn(self: *Nursery, entry: TaskFn, arg: ?*anyopaque) !TaskId {
    return self.scheduler.spawn(.{
        .entry = entry,
        .arg = arg,
        .parent = self.parent_task,
        .budget = self.budget.childBudget(),
    });
}

// FORBIDDEN: Callback indirection
// self.spawn_callback(task)  // NO!
```

### 2.6 Runtime Lifecycle

[SCHED:2.6.1] Runtime lifecycle exports:

```c
// Initialize runtime (creates scheduler, etc.)
void janus_rt_init(RuntimeConfig config);

// Shutdown runtime (stops scheduler, frees resources)
void janus_rt_shutdown(void);

// Get runtime reference (for internal use)
Runtime* janus_rt_get(void);
```

[SCHED:2.6.2] Scheduler-specific exports SHALL NOT exist at the public API level. All scheduling operations go through Runtime or Nursery interfaces.

### 2.7 Testing Support

[SCHED:2.7.1] The architecture SHALL support isolated test runtimes:

```zig
test "isolated scheduler test" {
    // Create isolated runtime for this test
    var test_rt = try Runtime.init(test_allocator, .{
        .worker_count = 1,
        .deterministic_seed = 42,
    });
    defer test_rt.deinit();

    // Test uses isolated runtime, no global state
    var nursery = test_rt.createNursery(Budget.default());
    _ = nursery.spawn(&testTask, null);
    const result = nursery.awaitAll();
    try testing.expectEqual(.success, result);
}
```

[SCHED:2.7.2] Single-threaded scheduler variant SHALL be provided for deterministic tests:

```zig
const scheduler_impl = switch (builtin.mode) {
    .Debug => SingleThreadScheduler,  // Deterministic for tests
    else => WorkStealingScheduler,    // Full M:N
};
```

---

## 3. C ABI Adapter Layer (RtNursery Contract)

### 3.1 Purpose and Scope

[SCHED:3.1.1] The C ABI Adapter Layer exists for exactly ONE reason: **translate Janus runtime semantics into a hostile C ABI without leaking impurity inward.**

[SCHED:3.1.2] The adapter layer:
- **IS**: An opaque handle for C, an adapter between scheduler.Nursery and C exports, a lifetime owner
- **IS NOT**: A scheduler, a policy object, a concurrency abstraction, part of Janus semantics

[SCHED:3.1.3] If someone tries to "extend" RtNursery, they are violating this specification.

### 3.2 RtNursery Structure

[SCHED:3.2.1] The adapter structure SHALL be minimal:

```zig
const RtNursery = struct {
    nursery: scheduler.Nursery,
};
```

[SCHED:3.2.2] The adapter SHALL NOT contain:
- Callbacks
- TLS fields
- Error state
- Bookkeeping beyond the wrapped nursery

**Rationale:** scheduler.Nursery already encodes structured concurrency. The adapter only exists to own it and translate results.

### 3.3 Thread-Local Storage Containment

[SCHED:3.3.1] TLS is allowed **ONLY** to support the legacy C ABI illusion: "There is a current nursery."

[SCHED:3.3.2] TLS containment rules (INVARIANT):
- TLS lives **ONLY** in `janus_rt.zig`
- TLS is **NEVER** visible to scheduler code
- TLS stack stores **RtNursery pointers only**

[SCHED:3.3.3] Canonical TLS form:

```zig
threadlocal var rt_nursery_stack: std.ArrayListUnmanaged(*RtNursery) = .{};
```

[SCHED:3.3.4] This is **ABI glue**, not architecture. Janus code never sees this. Scheduler never sees this. Only C exports do.

### 3.4 Task Function Signatures

[SCHED:3.4.1] **Scheduler owns the type.** The gasket adapts.

[SCHED:3.4.2] Canonical scheduler task type:

```zig
pub const TaskFn = *const fn (?*anyopaque) callconv(.c) i64;
pub const NoArgTaskFn = *const fn () callconv(.c) i64;
```

[SCHED:3.4.3] The C ABI may use different return types (e.g., `i32`). The adapter is responsible for widening/narrowing at the boundary:

```zig
// C function returns i32
extern fn c_task_fn(arg: ?*anyopaque) callconv(.c) i32;

// Adapter widens to i64
fn wrappedTask(arg: ?*anyopaque) callconv(.c) i64 {
    const rc: i32 = c_task_fn(arg);
    return @as(i64, rc);
}
```

**Rationale:** Never let a foreign ABI dictate internal invariants. Scheduler semantics must remain uniform.

### 3.5 C Export Contracts (Frozen)

[SCHED:3.5.1] These exports are NOT negotiable. Everything else adapts to them.

#### Creation

```c
void* janus_nursery_create(void);
```

**Semantics:**
1. Fetch `GLOBAL_RT` (auto-initialize if needed)
2. Create `scheduler.Nursery` via Runtime
3. Wrap in `RtNursery`
4. Push pointer onto TLS stack
5. Return opaque pointer

Failure → return `NULL`

#### Spawn

```c
int janus_nursery_spawn(TaskFn fn, void* arg);
```

**Semantics:**
1. Lookup top of TLS stack
2. Call `RtNursery.nursery.spawn(...)`
3. Map: success → `0`, failure → `-1`

No allocation here. No threading. No blocking.

#### Await

```c
long janus_nursery_await_all(void);
```

**Semantics:**
1. Pop RtNursery from TLS stack
2. Call `nursery.awaitAll()`
3. Destroy RtNursery
4. Return status code

This is the **only synchronization point**.

### 3.6 Error Mapping (Canonical)

[SCHED:3.6.1] Error mapping SHALL be explicit and boring:

| Scheduler Result     | C Return |
|---------------------|----------|
| `.success`          | `0`      |
| `.cancelled`        | `-1`     |
| `.child_failed`     | error_code from child (negative) |
| `.panic`            | `-2`     |
| `.budget_exceeded`  | `-3`     |
| `.pending`          | `-4` (should never happen after awaitAll) |

[SCHED:3.6.2] This table SHALL NOT change without a major version bump.

### 3.7 Architectural Leverage

[SCHED:3.7.1] Once this contract is frozen:
- The scheduler can change internally
- The nursery implementation can evolve
- Zig async can replace stackful continuations
- The M:N engine can be swapped

**Without touching the C ABI. Without touching janus_rt exports. Without breaking compiler output.**

---

## 4. Terminology

| Term | Definition |
|------|------------|
| **Task** | A lightweight unit of execution with its own stack and budget |
| **Worker** | An OS thread that executes tasks from its local deque |
| **Fiber** | A stackful continuation (task implementation detail) |
| **Budget** | Abstract resource units that gate task execution |
| **Deque** | Double-ended queue supporting owner push/pop and stealer steal |
| **Nursery** | Structured concurrency scope that owns spawned tasks |
| **RtNursery** | C ABI adapter wrapping scheduler.Nursery (Section 3) |

---

## 5. Budget Model

### 5.1 Budget Structure

[SCHED:5.1.1] Every task SHALL have an associated budget with the following components:

```
Budget := {
    ops:          u32,    // Operation count (abstract instructions)
    memory:       usize,  // Memory allocation budget (bytes)
    spawn_count:  u16,    // Child task spawn limit
    channel_ops:  u16,    // Channel send/recv operations
    syscalls:     u16,    // System call budget
}
```

[SCHED:5.1.2] Budget components MUST be non-negative integers. A component value of 0 indicates exhaustion.

### 5.2 Budget Exhaustion

[SCHED:5.2.1] When any budget component reaches 0, the task MUST yield to the scheduler.

[SCHED:5.2.2] A task with exhausted budget SHALL be marked `BudgetExhausted` and MUST NOT resume until its budget is recharged.

[SCHED:3.2.3] Budget recharge mechanisms:
- **Parent recharge**: Parent nursery may grant additional budget
- **Supervisor recharge**: In `:cluster` profile, supervisors may recharge child budgets
- **Capability grant**: Holding `CapBudget` allows self-recharge up to capability limit

### 3.3 Budget Costs

[SCHED:3.3.1] The following operations SHALL decrement budget:

| Operation | `ops` | `memory` | `spawn_count` | `channel_ops` | `syscalls` |
|-----------|-------|----------|---------------|---------------|------------|
| Loop iteration | 1 | 0 | 0 | 0 | 0 |
| Function call | 1 | 0 | 0 | 0 | 0 |
| Allocation | 1 | size | 0 | 0 | 0 |
| Spawn | 1 | 0 | 1 | 0 | 0 |
| Channel send | 1 | 0 | 0 | 1 | 0 |
| Channel recv | 1 | 0 | 0 | 1 | 0 |
| File I/O | 1 | 0 | 0 | 0 | 1 |
| Network I/O | 1 | 0 | 0 | 0 | 1 |

---

## 5. Yield Points

### 4.1 Compiler-Inserted Yield Checks

[SCHED:4.1.1] The compiler SHALL insert yield checks at the following locations:

1. **Loop back-edges**: Every `YIELD_INTERVAL` iterations (default: 1024)
2. **Function calls**: Before each call instruction
3. **Channel operations**: Before send/recv
4. **Memory allocations**: After allocation succeeds
5. **Explicit yield**: At `yield` statements

[SCHED:4.1.2] Yield check pseudocode:

```
fn yield_check():
    task := current_task()
    if task.budget.ops == 0:
        task.state := BudgetExhausted
        scheduler_yield()
    else:
        task.budget.ops -= 1
```

### 4.2 Voluntary Yield

[SCHED:4.2.1] A task MAY yield voluntarily by:
- Executing `yield` statement
- Performing a blocking channel operation
- Awaiting an async operation

[SCHED:4.2.2] Voluntary yield SHALL NOT consume budget (already at yield point).

### 4.3 Yield Interval Configuration

[SCHED:4.3.1] The yield interval SHOULD be configurable per-profile:

| Profile | Default `YIELD_INTERVAL` |
|---------|--------------------------|
| `:service` | 1024 |
| `:cluster` | 512 |
| `:sovereign` | User-defined |

---

## 6. Task Model

### 5.1 Task Structure

[SCHED:5.1.1] A task SHALL contain:

```
Task := {
    id:              u64,               // Unique identifier
    state:           TaskState,         // Execution state
    budget:          Budget,            // Resource budget
    continuation:    Continuation,      // Execution context
    nursery_parent:  ?*Nursery,         // Owning nursery (structured concurrency)
    capability_ctx:  *CapabilityContext,// Granted capabilities
    priority:        Priority,          // Scheduling hint
    result:          TaskResult,        // Completion result
}
```

### 5.2 Task States

[SCHED:5.2.1] Task state machine:

```
             ┌─────────┐
             │  Ready  │◄────────────────────────┐
             └────┬────┘                         │
                  │ schedule                     │ wake
                  ▼                              │
             ┌─────────┐                    ┌────┴────┐
             │ Running │───────yield───────►│ Blocked │
             └────┬────┘                    └─────────┘
                  │                              ▲
      ┌───────────┼───────────┐                  │
      │           │           │                  │
      ▼           ▼           ▼                  │
┌──────────┐ ┌─────────┐ ┌───────────────┐      │
│Completed │ │Cancelled│ │BudgetExhausted├──────┘
└──────────┘ └─────────┘ └───────────────┘  recharge
```

[SCHED:5.2.2] State transitions:
- `Ready → Running`: Worker picks task from deque
- `Running → Blocked`: Task awaits channel/IO
- `Running → BudgetExhausted`: Budget component reaches 0
- `Running → Completed`: Task returns
- `Running → Cancelled`: Parent nursery cancels
- `Blocked → Ready`: Awaited operation completes
- `BudgetExhausted → Ready`: Budget recharged

### 5.3 Continuation (Stackful Fibers)

[SCHED:5.3.1] Phase 1 implementation SHALL use stackful fibers:

```
Context := {
    sp:   usize,           // Stack pointer (offset 0)
    regs: SavedRegisters,  // Callee-saved registers (offset 8)
}

SavedRegisters := {  // 48 bytes, must match assembly
    rbx: u64,        // offset 0  (Context offset 8)
    rbp: u64,        // offset 8  (Context offset 16)
    r12: u64,        // offset 16 (Context offset 24)
    r13: u64,        // offset 24 (Context offset 32)
    r14: u64,        // offset 32 (Context offset 40)
    r15: u64,        // offset 40 (Context offset 48)
}
```

[SCHED:5.3.2] Stack size SHALL default to 8KB per task.

[SCHED:5.3.3] Stack overflow SHALL be detected via guard pages when available.

[SCHED:5.3.4] Future optimization MAY use stackless coroutines (state machine transformation) when Zig 0.16+ async is available.

### 5.4 Context Switch (x86_64 Assembly)

[SCHED:5.4.1] Context switch SHALL be implemented in external assembly (`context_switch.s`).

[SCHED:5.4.2] The `janus_context_switch(from, to)` function SHALL:
- Save callee-saved registers (rbx, rbp, r12-r15) to `from->regs`
- Save stack pointer to `from->sp`
- Restore stack pointer from `to->sp`
- Restore callee-saved registers from `to->regs`
- Return via `ret` (pops return address from new stack)

[SCHED:5.4.3] The `janus_fiber_entry` trampoline SHALL:
- Read entry function pointer from r12
- Read argument pointer from r13
- Call `entry_fn(arg)` with proper calling convention
- Return (pops cleanup function from stack)

[SCHED:5.4.4] Invariants document: See `CONTEXT-SWITCH-INVARIANTS.md` for:
- What MUST be preserved (callee-saved registers)
- What MAY be clobbered (caller-saved registers, flags)
- Stack ownership rules
- Allowed callers
- Initialization invariants
- Safety guarantees

[SCHED:5.4.5] New fiber initialization SHALL:
- Push cleanup function address to stack
- Push `janus_fiber_entry` address to stack
- Set r12 = entry function pointer
- Set r13 = argument pointer
- Set sp to 16-byte aligned stack position

---

## 7. Worker Model

### 6.1 Worker Structure

[SCHED:6.1.1] Each worker SHALL maintain:

```
Worker := {
    id:            u8,                    // Worker index
    thread:        std.Thread,            // OS thread handle
    local_deque:   WorkStealingDeque,     // Local task queue
    current_task:  ?*Task,                // Currently running task
    saved_sp:      usize,                 // Worker stack pointer (for switch)
    steal_enabled: atomic(bool),          // Work stealing permission
    steal_rng:     Xoshiro256,            // Deterministic RNG for victim selection
    stats:         WorkerStats,           // Performance counters
}
```

### 6.2 Worker Count

[SCHED:6.2.1] Default worker count SHALL equal CPU core count.

[SCHED:6.2.2] Worker count MAY be configured via scheduler initialization.

[SCHED:6.2.3] Worker count MUST be at least 1.

### 6.3 Worker Loop

[SCHED:6.3.1] Worker loop pseudocode:

```
fn worker_loop(scheduler):
    while not scheduler.shutdown:
        // 1. Try local deque
        if task := local_deque.pop():
            execute(task)
            continue

        // 2. Try global queue
        if task := scheduler.global_queue.try_pop():
            execute(task)
            continue

        // 3. Try stealing
        if task := try_steal(scheduler):
            execute(task)
            continue

        // 4. Park until work available
        scheduler.work_available.wait()
```

### 6.4 Thread-Local Yield Mechanism

[SCHED:6.4.1] Each worker thread SHALL maintain thread-local pointers for yield:

```
threadlocal tls_worker_context: ?*Context  // Worker's saved context
threadlocal tls_task_context:   ?*Context  // Current task's context
threadlocal tls_current_task:   ?*Task     // Currently executing task
```

[SCHED:6.4.2] Before switching to a task, worker SHALL:
1. Set `tls_worker_context` to address of worker's context
2. Set `tls_task_context` to address of task's context
3. Set `tls_current_task` to the task pointer

[SCHED:6.4.3] After task yields back, worker SHALL:
1. Clear all thread-local pointers to null
2. Save task's updated context (sp, registers)
3. Handle task state transition

[SCHED:6.4.4] The `yield()` function SHALL:
1. Read worker context from `tls_worker_context`
2. Read task context from `tls_task_context`
3. Call `switchContext(task_ctx, worker_ctx)`

[SCHED:6.4.5] The `yieldComplete(result)` function SHALL:
1. Mark current task as completed with result
2. Call `yield()` to switch back to worker

---

## 8. Work-Stealing Algorithm

### 7.1 Deque Structure (Chase-Lev)

[SCHED:7.1.1] The work-stealing deque SHALL implement the Chase-Lev algorithm:

- **Owner operations** (single-threaded):
  - `push(task)`: Add to bottom (O(1))
  - `pop()`: Remove from bottom (O(1), LIFO)

- **Stealer operations** (multi-threaded):
  - `steal()`: Remove from top (O(1), FIFO, lock-free)

[SCHED:7.1.2] Memory ordering requirements:
- `push`: Release fence before bottom increment
- `pop`: Sequential consistency for bottom decrement, CAS for last element
- `steal`: Acquire load of top, Sequential consistency CAS

### 7.2 Steal Protocol

[SCHED:7.2.1] Steal attempt procedure:

```
fn try_steal(scheduler) -> ?*Task:
    if not steal_enabled.load():
        return null

    max_attempts := min(scheduler.worker_count - 1, 4)

    for attempt in 0..max_attempts:
        victim_id := select_victim(attempt)
        if victim_id == self.id:
            continue

        victim := scheduler.workers[victim_id]
        if task := victim.local_deque.steal():
            stats.tasks_stolen += 1
            return task

        stats.steals_failed += 1

    return null
```

### 7.3 Victim Selection

[SCHED:7.3.1] Victim selection strategies:

| Strategy | Description | Use Case |
|----------|-------------|----------|
| `RandomVictim` | Use deterministic RNG | Default, good balance |
| `RoundRobin` | Cycle through workers | Deterministic tests |
| `LeastLoaded` | Steal from busiest | High contention |

[SCHED:7.3.2] Default strategy SHALL be `RandomVictim` with deterministic seed for reproducibility.

### 7.4 Steal Bounds

[SCHED:7.4.1] Maximum steal attempts per cycle SHALL be bounded to prevent thundering herd.

[SCHED:7.4.2] When all steals fail, worker SHALL use exponential backoff (1μs → 1ms) before parking.

---

## 9. Nursery Integration

### 8.1 Nursery-Scheduler Binding

[SCHED:8.1.1] When `Nursery_Begin` executes:
1. Create `Nursery` struct with budget pool
2. Register nursery with scheduler
3. Push onto thread-local nursery stack

[SCHED:8.1.2] When `spawn` executes:
1. Verify active nursery exists
2. Check spawn budget (`budget_pool.spawn_count > 0`)
3. Allocate child budget from pool
4. Create task with nursery as parent
5. Push task to local deque

[SCHED:8.1.3] When `Nursery_End` executes:
1. Mark nursery as `Closing` (no new spawns)
2. Wait for all child tasks to complete
3. Propagate first error if any child failed
4. Cleanup nursery resources
5. Pop from nursery stack

### 8.2 Budget Inheritance

[SCHED:8.2.1] Child task budget SHALL be allocated from parent nursery's budget pool:

```
child_budget := Budget{
    ops:         min(pool.ops, DEFAULT_OPS),
    memory:      min(pool.memory, DEFAULT_MEMORY),
    spawn_count: 0,  // Children cannot spawn by default
    channel_ops: min(pool.channel_ops, DEFAULT_CHANNEL_OPS),
    syscalls:    min(pool.syscalls, DEFAULT_SYSCALLS),
}
pool.ops -= child_budget.ops
pool.memory -= child_budget.memory
// etc.
```

### 8.3 Cancellation

[SCHED:8.3.1] When a nursery is cancelled:
1. Set all child tasks to `Cancelled` state
2. Interrupt blocked children
3. Wait for all children to acknowledge cancellation
4. Release resources

---

## 10. Determinism Guarantees

### 9.1 Reproducibility Requirements

[SCHED:9.1.1] Given the same:
- Input data
- Scheduler seed
- Worker count
- Budget configuration

The execution order of tasks SHALL be identical across runs.

### 9.2 Non-Determinism Sources

[SCHED:9.2.1] The following MAY introduce non-determinism and MUST be controlled:
- Random victim selection → Use seeded PRNG
- OS thread scheduling → Accept at steal boundaries
- Timer resolution → Do not use timers for yield

### 9.3 Testing Support

[SCHED:9.3.1] Scheduler SHALL support a `deterministic_seed` configuration:

```zig
const config = SchedulerConfig{
    .worker_count = 4,
    .deterministic_seed = 42,  // Same seed = same execution
};
```

---

## 11. Profile Integration

### 10.1 Profile Behavior Matrix

| Profile | Scheduler | Capabilities | Budget | Notes |
|---------|-----------|--------------|--------|-------|
| `:core` | None | Forbidden | N/A | Single-threaded only |
| `:service` | CBC-MN | Implicit | Default | Cooperative M:N |
| `:cluster` | CBC-MN + Actors | Supervisor | Rechargeable | Actor mailboxes |
| `:sovereign` | CBC-MN | Explicit | Custom | Full control |

### 10.2 Profile-Specific Rules

[SCHED:10.2.1] **:core Profile**: Scheduler MUST NOT be used. `spawn` and `nursery` are syntax errors.

[SCHED:10.2.2] **:service Profile**: Scheduler with implicit capabilities. Tasks receive default budget. No explicit capability management required.

[SCHED:10.2.3] **:cluster Profile**: Supervisor tasks may recharge child budgets. Actor mailboxes as special channels.

[SCHED:10.2.4] **:sovereign Profile**: Full capability gating. User must explicitly grant `CapSpawn`, `CapBudget` to enable spawning.

---

## 12. QTJIR Integration

### 11.1 New Opcodes

[SCHED:11.1.1] The following opcodes SHALL be added to QTJIR:

| Opcode | Inputs | Output | Description |
|--------|--------|--------|-------------|
| `Budget_Check` | - | - | Check if budget exhausted, yield if so |
| `Budget_Decrement` | cost | - | Subtract cost from current budget |
| `Yield` | - | - | Voluntary yield to scheduler |
| `Task_Create` | func, args, budget | task_id | Create new task |
| `Task_Join` | task_id | result | Wait for task completion |

### 11.2 Tenancy

[SCHED:11.2.1] Tasks scheduled via CBC-MN SHALL have tenancy `CPU_Parallel`.

---

## 13. Runtime Interface

### 12.1 C-Compatible Exports

[SCHED:12.1.1] The following functions SHALL be exported for LLVM interop:

```c
// Scheduler lifecycle
void* janus_scheduler_create(SchedulerConfig config);
void janus_scheduler_shutdown(void* scheduler);

// Task management (via nursery)
int janus_scheduler_spawn(void* func, void* arg);
int janus_scheduler_yield(void);

// Budget management
Budget janus_budget_get_current(void);
int janus_budget_recharge(Budget amount);
```

---

## 14. Performance Requirements

### 13.1 Benchmarks

[SCHED:13.1.1] The scheduler SHALL meet the following performance targets:

| Metric | Target | Measurement |
|--------|--------|-------------|
| Context switch latency | < 1μs | Fiber switch time |
| Task spawn throughput | > 1M/sec | Tasks spawned per second |
| Memory per task | < 16KB | Stack + metadata |
| Work-steal latency | < 10μs | Steal operation time |

### 13.2 Scalability

[SCHED:13.2.1] Scheduler SHALL support:
- At least 1,000,000 concurrent tasks
- At least 256 worker threads
- Linear scaling up to CPU core count

---

## 15. Error Handling

### 14.1 Scheduler Errors

[SCHED:14.1.1] Scheduler error conditions:

| Error | Cause | Recovery |
|-------|-------|----------|
| `SpawnBudgetExhausted` | No spawn budget | Recharge or fail |
| `MemoryBudgetExhausted` | No memory budget | Recharge or fail |
| `NurseryNotActive` | Spawn outside nursery | Compile error |
| `StackOverflow` | Fiber stack exhausted | Task panic |
| `WorkerPanic` | Worker thread panic | Restart worker |

---

## 16. Security Considerations

### 15.1 DoS Prevention

[SCHED:15.1.1] Budget caps SHALL prevent resource exhaustion attacks.

[SCHED:15.1.2] Capability gating SHALL prevent unauthorized spawning.

### 15.2 Isolation

[SCHED:15.2.1] Tasks SHALL NOT access other tasks' stacks.

[SCHED:15.2.2] Task results SHALL only be accessible to parent nursery.

---

## 17. Future Work

### 16.1 Stackless Coroutines

When Zig 0.16+ provides stable async/await, the scheduler MAY optimize to stackless coroutines for reduced memory overhead.

### 16.2 Preemptive Mode

A future `:realtime` profile MAY add timer-based preemption for hard real-time requirements.

### 16.3 Distributed Scheduling

`:cluster` profile MAY extend scheduling across network boundaries for actor distribution.

---

**Ratified:** 2026-01-29
**Authority:** Markus Maiwald + Voxis Forge
