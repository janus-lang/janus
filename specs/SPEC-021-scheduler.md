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

## 2. Terminology

| Term | Definition |
|------|------------|
| **Task** | A lightweight unit of execution with its own stack and budget |
| **Worker** | An OS thread that executes tasks from its local deque |
| **Fiber** | A stackful continuation (task implementation detail) |
| **Budget** | Abstract resource units that gate task execution |
| **Deque** | Double-ended queue supporting owner push/pop and stealer steal |
| **Nursery** | Structured concurrency scope that owns spawned tasks |

---

## 3. Budget Model

### 3.1 Budget Structure

[SCHED:3.1.1] Every task SHALL have an associated budget with the following components:

```
Budget := {
    ops:          u32,    // Operation count (abstract instructions)
    memory:       usize,  // Memory allocation budget (bytes)
    spawn_count:  u16,    // Child task spawn limit
    channel_ops:  u16,    // Channel send/recv operations
    syscalls:     u16,    // System call budget
}
```

[SCHED:3.1.2] Budget components MUST be non-negative integers. A component value of 0 indicates exhaustion.

### 3.2 Budget Exhaustion

[SCHED:3.2.1] When any budget component reaches 0, the task MUST yield to the scheduler.

[SCHED:3.2.2] A task with exhausted budget SHALL be marked `BudgetExhausted` and MUST NOT resume until its budget is recharged.

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

## 4. Yield Points

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

## 5. Task Model

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
Continuation := {
    stack:     []align(16) u8,  // Dedicated stack memory
    sp:        usize,           // Stack pointer
    ip:        usize,           // Instruction pointer
    registers: SavedRegisters,  // Callee-saved registers
}
```

[SCHED:5.3.2] Stack size SHALL default to 8KB per task.

[SCHED:5.3.3] Stack overflow SHALL be detected via guard pages when available.

[SCHED:5.3.4] Future optimization MAY use stackless coroutines (state machine transformation) when Zig 0.16+ async is available.

---

## 6. Worker Model

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

---

## 7. Work-Stealing Algorithm

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

## 8. Nursery Integration

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

## 9. Determinism Guarantees

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

## 10. Profile Integration

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

## 11. QTJIR Integration

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

## 12. Runtime Interface

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

## 13. Performance Requirements

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

## 14. Error Handling

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

## 15. Security Considerations

### 15.1 DoS Prevention

[SCHED:15.1.1] Budget caps SHALL prevent resource exhaustion attacks.

[SCHED:15.1.2] Capability gating SHALL prevent unauthorized spawning.

### 15.2 Isolation

[SCHED:15.2.1] Tasks SHALL NOT access other tasks' stacks.

[SCHED:15.2.2] Task results SHALL only be accessible to parent nursery.

---

## 16. Future Work

### 16.1 Stackless Coroutines

When Zig 0.16+ provides stable async/await, the scheduler MAY optimize to stackless coroutines for reduced memory overhead.

### 16.2 Preemptive Mode

A future `:realtime` profile MAY add timer-based preemption for hard real-time requirements.

### 16.3 Distributed Scheduling

`:cluster` profile MAY extend scheduling across network boundaries for actor distribution.

---

**Ratified:** 2026-01-29
**Authority:** Markus Maiwald + Voxis Forge
