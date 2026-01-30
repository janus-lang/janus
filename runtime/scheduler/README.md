# CBC-MN Scheduler

**Capability-Budgeted Cooperative M:N Scheduler**

## Overview

This module implements the Janus runtime scheduler for the `:service`, `:cluster`, and `:sovereign` profiles. It provides lightweight task execution with work-stealing load balancing and structured concurrency via nurseries.

## Core Innovation

**Budget-driven scheduling** instead of time ticks:
- Deterministic execution order
- No OS timer dependency
- Language-level DoS immunity via capability gating

**Structured Concurrency** via nursery integration:
- No orphan tasks - every task belongs to a nursery
- Transitive cancellation propagates through task trees
- Cooperative yield at await points (no spin-waiting)

## Architecture

```
scheduler.zig                       # Sovereign Index (public API)
├── budget.zig                      # Budget types and costs
├── task.zig                        # Task struct and state machine
├── continuation.zig                # Context switch (Zig API)
├── context_switch.s                # x86_64 assembly implementation
├── worker.zig                      # Worker thread loop + TLS yield
├── deque.zig                       # Chase-Lev work-stealing deque
├── nursery.zig                     # Structured concurrency container
├── test_context_switch.zig         # Context switch unit tests
├── test_worker_integration.zig     # Worker integration tests
├── test_nursery_integration.zig    # Nursery + scheduler tests
├── test_nursery_correctness.zig    # Nursery state machine tests
└── CONTEXT-SWITCH-INVARIANTS.md    # Assembly contract documentation
```

## Key Concepts

### Budget
Abstract resource units: ops, memory, spawn_count, channel_ops, syscalls.
Task yields when any budget component exhausts.

### Task States
```
Ready → Running → Blocked/BudgetExhausted/Completed/Cancelled
```

### Work Stealing
- Local deque per worker (LIFO for locality)
- Stealers take from top (FIFO for fairness)
- Chase-Lev lock-free algorithm

### Context Switch (x86_64)
External assembly implementation (`context_switch.s`):
- System V AMD64 ABI compliant
- Saves/restores callee-saved registers (rbx, rbp, r12-r15)
- Explicit stack pointer management
- Fiber entry trampoline for first execution

See `CONTEXT-SWITCH-INVARIANTS.md` for the full contract.

---

## Structured Concurrency (Phase 9)

### The 5-State Nursery Machine

```
                    spawn()
    ┌───────┐      ─────────►     ┌─────────┐
    │ Open  │                     │ Open    │
    │(empty)│                     │(active) │
    └───┬───┘                     └────┬────┘
        │                              │
        │ close()                      │ close()
        ▼                              ▼
    ┌───────┐                     ┌─────────┐
    │Closed │◄──── awaitAll() ────│ Closing │
    └───────┘                     └────┬────┘
                                       │
                         cancel()      │ error in child
                              │        │
                              ▼        ▼
                         ┌─────────────────┐
                         │   Cancelling    │
                         └────────┬────────┘
                                  │
                                  │ all done
                                  ▼
                         ┌─────────────────┐
                         │   Cancelled     │
                         └─────────────────┘
```

### Bidirectional Task-Nursery Binding

```
┌─────────────────────┐                 ┌─────────────────────┐
│       Task A        │                 │     Nursery N       │
│                     │  owned_nursery  │                     │
│ Creates and owns ───┼────────────────►│ owner_task ─────────┤
│ nursery N           │                 │ (backpointer)       │
│                     │◄────────────────┼─────────────────────┤
│ If cancelled,       │  propagates     │ Contains child      │
│ nursery cancelled   │  cancellation   │ tasks T1, T2, T3... │
└─────────────────────┘                 └─────────────────────┘
```

When Task A is cancelled:
1. `task.markCancelled()` sets state to Cancelled
2. Checks `owned_nursery` - finds Nursery N
3. Calls `nursery.propagateParentCancel()`
4. Nursery marks ALL children as Cancelled (transitive!)

### Yielding awaitAll (Phase 9.3)

The `awaitAll()` function operates in two modes:

**Fiber Context (inside worker thread):**
```zig
// When called from within a task running on a worker
if (worker_mod.inFiberContext()) {
    while (!self.allChildrenComplete()) {
        self.waiting_task = worker_mod.getCurrentTask();
        worker_mod.yieldBlocked(.{ .nursery_await = self });
        // Task is now Blocked, scheduler runs other tasks
        // When all children complete, notifyChildComplete wakes us
    }
}
```

**Main Thread Fallback:**
```zig
// When called from main thread (e.g., in tests)
while (!self.allChildrenComplete()) {
    std.Thread.sleep(100_000); // 100µs polling
}
```

### Worker → Nursery Notification Path

```
Task completes on worker
        │
        ▼
worker.notifyNurseryCompletion(task)
        │
        ▼
nursery.notifyChildComplete(task)
        │
        ├── Captures error (if any)
        ├── Increments completed_count atomically
        │
        └── If all children done AND waiting_task exists:
                │
                ▼
            Wake waiting_task:
              1. Mark Ready
              2. Submit to scheduler
```

### Race Protection

Tasks may be cancelled between dequeue and execution. The worker handles this:

```zig
fn executeTask(self: *Self, task: *Task) void {
    // Check if task was cancelled while in queue
    if (task.isFinished()) {
        self.stats.tasks_cancelled += 1;
        self.notifyNurseryCompletion(task);
        return;  // Don't try to run it
    }

    task.markRunning();  // Safe now - task is definitely Ready
    // ... execute task
}
```

---

## Async/Await Lowering (Phase 9.4)

### QTJIR Opcode Targets

The async/await syntax lowers to these QTJIR opcodes:

| Janus Syntax | QTJIR Opcode | Runtime Target |
|--------------|--------------|----------------|
| `nursery { ... }` | `Nursery_Begin` / `Nursery_End` | `Nursery.init()` / `awaitAll()` |
| `spawn expr` | `Spawn` | `nursery.spawn(fn, arg)` |
| `await expr` | `Await` | `awaitAll()` (implicit at nursery end) |
| `async fn()` | `Async_Call` | `spawn` + channel for result |

### Lowering Example

```janus
// Janus source
nursery {
    spawn compute(x)
    spawn compute(y)
}
// Implicit await here
```

```
// QTJIR
%1 = Nursery_Begin
%2 = Spawn @compute, %x
%3 = Spawn @compute, %y
%4 = Nursery_End %1    // Generates awaitAll()
```

### Runtime Function Mapping

```zig
// compiler/qtjir/async_lower.zig maps to:
extern fn janus_nursery_create() -> *Nursery;
extern fn janus_nursery_spawn(n: *Nursery, fn: TaskFn, arg: ?*anyopaque) -> *Task;
extern fn janus_nursery_await(n: *Nursery) -> NurseryResult;
extern fn janus_nursery_destroy(n: *Nursery) -> void;
```

---

## Testing

Run scheduler tests:
```bash
zig build test-context-switch       # Context switch assembly tests (27 tests)
zig build test-worker-integration   # Worker integration tests (41 tests)
zig build test-nursery-integration  # Nursery + scheduler tests (8 tests)
zig build test-nursery-correctness  # Nursery state machine tests (5 tests)
zig build test-async-lower          # Async/await lowering tests (4 tests)
```

Run all scheduler tests:
```bash
zig build test-context-switch test-worker-integration test-nursery-integration test-nursery-correctness test-async-lower
```

E2E integration tests:
```bash
zig build test-async-e2e            # Full async/await E2E tests (10 tests)
```

### Test Categories

| Test File | Count | Purpose |
|-----------|-------|---------|
| test_context_switch.zig | 27 | Assembly contract verification |
| test_worker_integration.zig | 41 | Worker loop + scheduling |
| test_nursery_integration.zig | 8 | Nursery ↔ scheduler integration |
| test_nursery_correctness.zig | 5 | State machine + cancellation |
| async_lower_test.zig | 4 | QTJIR opcode lowering |
| async_await_e2e_test.zig | 10 | Full compilation pipeline |

**Total: 95 scheduler-related tests**

---

## Specifications

- SPEC-021: M:N Scheduler (Budget Model, Work-Stealing, Nursery Integration)
- SPEC-022: Scheduling Capabilities (CapSpawn, CapBudget, Profile Matrix)

## Profile Behavior

| Profile | Scheduler | Budget | Nurseries |
|---------|-----------|--------|-----------|
| :core | Disabled | N/A | Forbidden |
| :service | Enabled | Implicit | Cooperative |
| :cluster | Enabled + Actors | Rechargeable | Supervised |
| :sovereign | Enabled | Explicit caps | Full control |

---

## Teaching: How Structured Concurrency Works

### The Problem with Unstructured Concurrency

```
// Dangerous: Who owns this task? When does it complete?
go compute(x)  // Fire and forget - orphan!
```

### The Janus Solution: Nurseries

```janus
// Safe: Nursery owns all spawned tasks
nursery {
    spawn compute(x)  // Child of nursery
    spawn compute(y)  // Child of nursery
}  // <- Can't exit until ALL children complete
```

**Guarantees:**
1. **No orphans** - Every task has a parent nursery
2. **Clean exit** - Nursery block waits for all children
3. **Error propagation** - Child error → nursery error → caller sees it
4. **Cancellation** - Cancel nursery → all children cancelled (transitively!)

### Nested Nurseries = Task Trees

```janus
nursery {           // Level 1
    spawn {
        nursery {   // Level 2 - owned by Level 1 task
            spawn work_a()
            spawn work_b()
        }
    }
}
```

If Level 1 is cancelled:
- Level 1 task is cancelled
- Level 1 task's `owned_nursery` (Level 2) is cancelled
- Level 2 children (work_a, work_b) are cancelled
- **Cancellation cascades through the entire tree!**

---

*"Budget is the new tick. Capability is the new trust. Nursery is the new scope."*
