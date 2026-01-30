# Nursery/Spawn Correctness Guarantees

**Status:** Design Document (Pre-Implementation)
**Author:** Voxis Forge + Markus Maiwald
**Date:** 2026-01-29
**Related:** SPEC-019, 09-using-statement-concurrency

---

## Why This Matters

Janus's nursery/spawn system is **first-class in the world**. Unlike:
- **Go:** No structured concurrency. Goroutines can be orphaned.
- **Rust:** Fragmented async ecosystem. Tokio vs async-std vs others.
- **Python/JS:** Unstructured promises/tasks leak freely.

Janus gets this **right**.

---

## Core Invariants (MUST HOLD)

### Invariant 1: No Orphaned Tasks

```janus
nursery do
    spawn task1()
    spawn task2()
end  // ← Nursery CANNOT exit until ALL tasks complete
```

**Proof obligation:** At nursery exit, `active_task_count == 0`.

**Violation consequence:** Resource leaks, zombie tasks, memory exhaustion.

---

### Invariant 2: Fail-Fast Sibling Cancellation

```janus
nursery do
    spawn fetch_user()    // succeeds
    spawn fetch_broken()  // FAILS with error
    spawn fetch_posts()   // MUST be cancelled
end  // ← All tasks cancelled, error propagated
```

**Semantics:**
1. First task failure triggers cancellation of ALL siblings
2. Cancellation is **cooperative** (check cancellation token)
3. Resources in cancelled tasks are cleaned up (LIFO)
4. Original error propagates to nursery scope

**Proof obligation:** On failure, all sibling tasks enter cancelled state and cleanup.

---

### Invariant 3: LIFO Resource Cleanup

```janus
nursery do
    spawn do
        using r1 := open("first") do
            using r2 := open("second") do
                // work
            end  // r2.close()
        end  // r1.close()
    end
end
```

**Order guarantee:** Resources close in **reverse acquisition order**.

**Why it matters:** Later resources often depend on earlier resources. Closing in wrong order causes use-after-free or undefined behavior.

---

### Invariant 4: Spawn Only Inside Nursery

```janus
func bad() !void do
    spawn task()  // COMPILE ERROR: spawn outside nursery
end

func good() !void do
    nursery do
        spawn task()  // OK: spawn inside nursery
    end
end
```

**Enforcement:** Static analysis at semantic phase.

**Proof obligation:** Every `spawn` node has an enclosing `nursery` scope.

---

### Invariant 5: Await Only Inside Async

```janus
func bad() !void do
    await fetch()  // COMPILE ERROR: await in non-async function
end

async func good() !void do
    await fetch()  // OK: await inside async
end
```

**Enforcement:** Static analysis at semantic phase.

**Proof obligation:** Every `await` node is inside `async func` or `main`.

---

## State Machine: Nursery Lifecycle

```
     ┌─────────────────────────────────────────────────────┐
     │                    NURSERY                          │
     │                                                     │
     │   ┌─────────┐    spawn    ┌──────────┐             │
     │   │  INIT   │───────────▶│  RUNNING  │             │
     │   └─────────┘             └──────────┘             │
     │                               │                     │
     │                    ┌──────────┼──────────┐          │
     │                    ▼          ▼          ▼          │
     │              ┌─────────┐ ┌─────────┐ ┌─────────┐   │
     │              │ TASK 1  │ │ TASK 2  │ │ TASK N  │   │
     │              └────┬────┘ └────┬────┘ └────┬────┘   │
     │                   │           │           │         │
     │           ┌───────┴───────────┴───────────┴───┐    │
     │           ▼                                   ▼    │
     │    ┌────────────┐                    ┌────────────┐│
     │    │ ALL SUCCESS│                    │ ANY FAILURE││
     │    └──────┬─────┘                    └──────┬─────┘│
     │           │                                 │       │
     │           │                    ┌────────────┘       │
     │           │                    ▼                    │
     │           │             ┌─────────────┐             │
     │           │             │ CANCEL ALL  │             │
     │           │             │  SIBLINGS   │             │
     │           │             └──────┬──────┘             │
     │           │                    │                    │
     │           ▼                    ▼                    │
     │   ┌─────────────────────────────────────────┐      │
     │   │             CLEANUP (LIFO)              │      │
     │   └─────────────────────────────────────────┘      │
     │                        │                            │
     │                        ▼                            │
     │                 ┌─────────────┐                     │
     │                 │    EXIT     │                     │
     │                 └─────────────┘                     │
     └─────────────────────────────────────────────────────┘
```

---

## State Machine: Task Lifecycle

```
                    ┌─────────┐
                    │ PENDING │
                    └────┬────┘
                         │ schedule
                         ▼
                    ┌─────────┐
          ┌────────│ RUNNING │────────┐
          │        └────┬────┘        │
          │ cancel      │ complete   │ error
          ▼             ▼             ▼
    ┌───────────┐ ┌───────────┐ ┌───────────┐
    │ CANCELLING│ │ COMPLETED │ │  FAILED   │
    └─────┬─────┘ └───────────┘ └─────┬─────┘
          │                           │
          │   cleanup                 │ propagate
          ▼                           ▼
    ┌───────────┐              ┌───────────────┐
    │ CANCELLED │              │ NURSERY ERROR │
    └───────────┘              └───────────────┘
```

---

## Implementation Strategy

### Phase 1: Task Registry

```zig
const TaskRegistry = struct {
    tasks: std.ArrayList(Task),
    active_count: std.atomic.Atomic(u32),
    cancellation_token: CancellationToken,

    const Task = struct {
        id: TaskId,
        state: TaskState,
        frame: anyframe,
        resources: ResourceStack,
    };

    const TaskState = enum {
        pending,
        running,
        completed,
        failed,
        cancelling,
        cancelled,
    };
};
```

### Phase 2: Nursery Scope

```zig
const NurseryScope = struct {
    registry: TaskRegistry,
    error_state: ?anyerror,

    fn spawn(self: *NurseryScope, task_fn: anytype) !void {
        // Register task
        // Schedule on event loop
        // Increment active_count
    }

    fn awaitAll(self: *NurseryScope) !void {
        // Wait for active_count == 0
        // If error_state set, propagate
    }

    fn cancelAll(self: *NurseryScope, reason: anyerror) void {
        // Set cancellation_token
        // Wait for all tasks to acknowledge
        // Cleanup resources LIFO
    }
};
```

### Phase 3: Cancellation Cooperation

Tasks must periodically check cancellation:

```janus
async func long_running() !void do
    for i in 0..1000000 do
        check_cancelled()  // Implicit or explicit
        do_work(i)
    end
end
```

Compiler inserts cancellation checks at:
- Loop boundaries
- Await points
- Function entry

---

## Testing Strategy

### Property Tests

1. **No Orphans Property:**
   ```
   forall nursery n, tasks ts:
     spawn_all(n, ts) && exit(n) => active_count(n) == 0
   ```

2. **Fail-Fast Property:**
   ```
   forall nursery n, task t_fail, tasks ts:
     spawn(n, t_fail) && fails(t_fail) => all_cancelled(ts)
   ```

3. **LIFO Cleanup Property:**
   ```
   forall resources rs acquired in order [r1, r2, r3]:
     cleanup_order(rs) == [r3, r2, r1]
   ```

### Stress Tests

- 100k concurrent spawns
- Nested nurseries (depth 10)
- Rapid spawn/cancel cycles
- Memory pressure scenarios

### Chaos Tests

- Random task failures
- Random cancellations
- OOM during spawn
- Timeout during cleanup

---

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| N1001 | SpawnOutsideNursery | `spawn` used outside nursery block |
| N1002 | AwaitOutsideAsync | `await` used in non-async function |
| N2001 | NurseryTimeout | Nursery exceeded configured timeout |
| N2002 | CancellationFailed | Task didn't respond to cancellation |
| N3001 | OrphanedTask | Task escaped nursery (should be impossible) |
| N3002 | CleanupFailed | Resource cleanup raised error |

---

## Open Questions

1. **Cancellation timeout:** How long to wait for cooperative cancellation?
2. **Nested nurseries:** Can inner nursery escape outer cancellation?
3. **Error aggregation:** How to report multiple task failures?
4. **Backpressure:** What happens when spawn rate exceeds capacity?

---

## References

- SPEC-019: :service Profile
- 09-using-statement-concurrency: Resource Management Design
- Trio (Python): https://trio.readthedocs.io/
- Structured Concurrency: https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/

---

**This document captures the correctness guarantees that MUST hold for nursery/spawn. Implementation proceeds only after these invariants are understood and testable.**
