# SPEC-021-scheduler: Nursery State Machine

**Status:** Draft (Phase 9 Prerequisite)
**Version:** 0.1.0
**Related:** SPEC-021-scheduler.md Section 9

---

## 1. Overview

This document formally specifies the nursery state machine for the CBC-MN scheduler.
A nursery is a **structured concurrency domain** that owns child tasks and ensures
no orphans escape.

### 1.1 Key Invariants (Non-Negotiable)

These invariants MUST hold at all times:

1. **No Orphan Tasks**: Every task belongs to exactly one nursery
2. **Completion Barrier**: Nursery cannot close until ALL children finish
3. **Transitive Cancellation**: Parent cancellation propagates to all descendants
4. **LIFO Cleanup**: Nested nurseries close inner-to-outer
5. **First Error Wins**: First child error is captured; others are logged

---

## 2. State Machine

### 2.1 States

```
┌─────────────────────────────────────────────────────────────────────┐
│                       NURSERY STATE MACHINE                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│    ┌──────────┐      close()      ┌──────────┐                      │
│    │   Open   │ ─────────────────▶│ Closing  │                      │
│    └────┬─────┘                   └────┬─────┘                      │
│         │                              │                            │
│         │ cancel() or                  │ all_children_complete()    │
│         │ parent_cancelled()           │                            │
│         │                              ▼                            │
│         │                         ┌──────────┐                      │
│         │                         │  Closed  │ (Terminal: Success)  │
│         │                         └──────────┘                      │
│         │                                                           │
│         │ cancel() or parent_cancelled()                            │
│         ▼                                                           │
│    ┌──────────────┐   all_children_complete()   ┌─────────────────┐ │
│    │  Cancelling  │ ───────────────────────────▶│   Cancelled     │ │
│    └──────────────┘                             │  (Terminal)     │ │
│                                                 └─────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 State Definitions

| State | Code | Description |
|-------|------|-------------|
| **Open** | 0 | Accepting new children via `spawn()` |
| **Closing** | 1 | Rejecting new children, waiting for existing to complete |
| **Cancelling** | 2 | Propagating cancellation, waiting for children to acknowledge |
| **Closed** | 3 | Terminal: all children completed successfully |
| **Cancelled** | 4 | Terminal: nursery was cancelled (with or without errors) |

### 2.3 State Transitions

| From | To | Trigger | Action |
|------|----|---------|--------|
| Open | Closing | `close()` called | Reject new spawns |
| Open | Cancelling | `cancel()` or parent cancelled | Mark all children cancelled |
| Closing | Closed | Last child completes | Release barrier waiters |
| Closing | Cancelling | `cancel()` while closing | Mark remaining children cancelled |
| Cancelling | Cancelled | Last child completes/acknowledges | Release barrier waiters |

### 2.4 Forbidden Transitions

These transitions are **undefined behavior** if triggered:

- Closed → any state (terminal)
- Cancelled → any state (terminal)
- Cancelling → Open (no resurrection)
- Closing → Open (no resurrection)

---

## 3. Child Task Lifecycle Integration

### 3.1 Spawn Semantics

```
spawn(func, arg) -> ?*Task:
    IF state != Open:
        RETURN null  // Nursery not accepting children
    IF !budget.decrement(SPAWN_COST):
        RETURN null  // Budget exhausted

    task = allocate_task(func, arg)
    task.nursery_id = self.id

    children.append(task)
    scheduler.submit(task)

    RETURN task
```

### 3.2 Child Completion Notification

When a worker executes a task to completion:

```
worker.on_task_complete(task):
    IF task.nursery_id:
        nursery = lookup_nursery(task.nursery_id)
        nursery.notify_child_complete(task)
```

Nursery handling:

```
notify_child_complete(task):
    // Capture first error (atomic CAS)
    IF task.result.is_error() AND first_error == null:
        first_error = ChildError(task.id, task.result.error_code)

    // Increment completion counter (atomic)
    completed_count.fetch_add(1, .acq_rel)

    // Check for state transition
    IF completed_count >= children.len:
        transition_to_terminal()
```

### 3.3 Terminal State Transition

```
transition_to_terminal():
    MATCH state:
        Closing  -> state = Closed
        Cancelling -> state = Cancelled
```

---

## 4. Cancellation Semantics

### 4.1 Cancellation Trigger

Cancellation can be triggered by:

1. **Explicit**: `nursery.cancel()` called by parent task
2. **Propagated**: Parent nursery entered Cancelling state
3. **Error-induced**: First child error triggers cancellation (configurable)

### 4.2 Cancellation Propagation Algorithm

```
cancel():
    // Atomic state transition
    IF !state.cmpxchg(Open, Cancelling) AND
       !state.cmpxchg(Closing, Cancelling):
        RETURN  // Already cancelling or terminal

    // Mark all non-finished children
    FOR task IN children:
        IF !task.is_finished():
            task.mark_cancelled()

    // Propagate to nested nurseries (transitive)
    FOR task IN children:
        IF task.owns_nursery:
            task.owned_nursery.propagate_parent_cancel()
```

### 4.3 Cooperative Cancellation

Tasks observe cancellation **cooperatively** at yield points:

- Budget check (loop back-edges)
- Channel operations
- Explicit `yield()`
- Memory allocation

**No forced preemption**. Tasks run to the next yield point before observing cancellation.

```
// Inside task execution
yield_point():
    IF current_task.state == Cancelled:
        // Cleanup local resources (defer stack)
        // Return from task with CancelledResult
        RETURN_EARLY with .cancelled
```

### 4.4 Cancellation vs Error Priority

| Scenario | Result |
|----------|--------|
| Child errors, then cancel | `child_failed` (error wins) |
| Cancel, then child errors | `child_failed` (error wins) |
| Cancel, all children clean exit | `cancelled` |
| Normal completion | `success` |

**Rationale**: Errors carry diagnostic information; cancellation is an expected outcome.

---

## 5. Await Semantics

### 5.1 awaitAll (Barrier)

```
await_all() -> NurseryResult:
    // Transition to closing
    close()

    // Yield until all children complete
    WHILE !all_children_complete():
        scheduler.yield_waiting_for(self.completion_event)

    // Return aggregate result
    IF first_error:
        RETURN .child_failed(first_error)
    IF state == Cancelled:
        RETURN .cancelled
    RETURN .success
```

### 5.2 Non-Blocking Check

```
try_get_result() -> ?NurseryResult:
    IF !all_children_complete():
        RETURN null  // Still pending

    // Same result logic as await_all
```

---

## 6. Nested Nursery Semantics

### 6.1 Parent-Child Relationship

```
parent_nursery {
    // Task A runs and creates child_nursery
    spawn task_a() {
        child_nursery {
            spawn task_b()
            spawn task_c()
        }
    }
}
```

Relationship:
- `child_nursery.parent_id = parent_nursery.id`
- `task_a` **owns** `child_nursery`
- `parent_nursery` does NOT directly see `task_b`, `task_c`

### 6.2 Cancellation Propagation (Transitive)

```
parent_nursery.cancel()
    └── marks task_a cancelled
        └── task_a.owned_nursery (child_nursery) receives parent_cancelled()
            └── child_nursery.cancel()
                └── marks task_b, task_c cancelled
```

### 6.3 LIFO Cleanup Order

On `parent_nursery.await_all()`:

1. `task_a` reaches its `child_nursery.await_all()`
2. `task_b`, `task_c` complete (or cancel)
3. `child_nursery` transitions to terminal
4. `task_a` continues past `await_all()`, completes
5. `parent_nursery` transitions to terminal

**Inner nurseries ALWAYS close before outer nurseries.**

---

## 7. Memory Model

### 7.1 Atomic Fields

| Field | Type | Ordering | Justification |
|-------|------|----------|---------------|
| `state` | `Atomic(NurseryState)` | `acq_rel` | State machine synchronization |
| `completed_count` | `Atomic(usize)` | `acq_rel` | Cross-worker completion tracking |
| `first_error` | Non-atomic (CAS-guarded) | N/A | Set once, read after barrier |

### 7.2 Synchronization Points

1. **spawn()**: Memory barrier after child list append
2. **notify_child_complete()**: Acquire barrier before reading state
3. **await_all()**: Full barrier before returning result

---

## 8. Error Aggregation Policy

### 8.1 Default Policy: First Error Wins

```
NurseryResult = union(enum) {
    success: void,
    child_failed: ChildError,  // First error only
    cancelled: void,
    pending: void,
};
```

### 8.2 Future Extension: Error Collection

For Phase 10+, consider:

```
NurseryResultExtended = union(enum) {
    success: void,
    child_failed: []ChildError,  // All errors
    cancelled: []ChildError,     // Cancelled with some errors
    pending: void,
};
```

**Not in scope for Phase 9.**

---

## 9. Implementation Checklist

Phase 9 is complete when:

- [ ] `NurseryState` includes `Cancelling` state (4 → 5 states)
- [ ] Worker calls `nursery.notifyChildComplete()` on task finish
- [ ] `awaitAll()` yields to scheduler instead of spinning
- [ ] `cancel()` propagates to nested nurseries
- [ ] Tasks observe cancellation at yield points
- [ ] All existing tests pass
- [ ] New tests: nested nursery cancellation, concurrent completion, error priority

---

## 10. Test Scenarios

### 10.1 Basic Completion

```
nursery {
    spawn { return 1 }
    spawn { return 2 }
} // await_all: success
```

### 10.2 Child Error

```
nursery {
    spawn { return 1 }
    spawn { return error.Failed }
} // await_all: child_failed
```

### 10.3 Explicit Cancel

```
nursery {
    spawn { while true { yield() } }
    cancel()
} // await_all: cancelled
```

### 10.4 Nested Cancel Propagation

```
outer_nursery {
    spawn {
        inner_nursery {
            spawn { while true { yield() } }
        }
    }
    cancel()  // Should cancel inner_nursery's children too
}
```

### 10.5 LIFO Cleanup Order

```
outer_nursery {
    spawn {
        defer { log("inner cleanup") }
        inner_nursery {
            spawn { return 1 }
        }
        log("inner done")
    }
    defer { log("outer cleanup") }
}
// Log order: "inner done", "inner cleanup", "outer cleanup"
```

---

*"The nursery is not a container. It is a promise."*
