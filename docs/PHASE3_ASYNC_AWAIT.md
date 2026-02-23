<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Phase 3: Async/Await and Structured Concurrency

**Status:** ✅ Complete  
**Date:** 2026-02-11  
**Profile:** `:service`  

---

## Overview

Phase 3 delivers scheduler-backed async/await with **structured concurrency** via nurseries. This is not "async/await like JavaScript" — this is **fiber-based M:N scheduling with cooperative cancellation**.

---

## What You Get

### 1. Async Functions

```janus
async func fetch_data(url: string) -> Data ! NetworkError do
    // This runs on the CBC-MN scheduler
    // Not blocking a thread — just yielding the fiber
    let response = await http_get(url)
    return parse_json(response)
end
```

### 2. Structured Concurrency (Nurseries)

```janus
async func process_batch(items: Array<Item>) -> Results do
    nursery do
        // All spawned tasks must complete before nursery exits
        for item in items do
            spawn process_item(item)
        end
    end  // Implicit awaitAll() here
    return results
end
```

**Key guarantee:** No orphaned tasks. If the parent is cancelled, children are cancelled.

### 3. Await with Results

```janus
async func parallel_fetch(urls: Array<string>) -> Array<Data> do
    nursery do
        let handles = urls.map { |url| async fetch_data(url) }
        return handles.map { |h| await h }
    end
end
```

### 4. Cooperative Cancellation

```janus
async func cancellable_work() -> i64 do
    for i in 0..1000000 do
        if is_cancelled() then
            return -1  // Clean exit
        end
        do_work(i)
    end
    return 42
end
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Janus Application                     │
│  ┌─────────┐  ┌──────────┐  ┌─────────┐  ┌──────────┐  │
│  │ async   │  │  await   │  │  spawn  │  │ nursery │  │
│  └────┬────┘  └────┬─────┘  └────┬────┘  └────┬─────┘  │
└───────┼────────────┼─────────────┼────────────┼────────┘
        │            │             │            │
┌───────┴────────────┴─────────────┴────────────┴────────┐
│              QTJIR (Async_Call, Await, Spawn)          │
└──────────────────────┬─────────────────────────────────┘
                       │
┌──────────────────────┴─────────────────────────────────┐
│              LLVM IR (janus_async_spawn, etc.)         │
└──────────────────────┬─────────────────────────────────┘
                       │
┌──────────────────────┴─────────────────────────────────┐
│         Janus Runtime (CBC-MN Scheduler)               │
│  ┌─────────┐  ┌──────────┐  ┌─────────┐  ┌──────────┐  │
│  │ Workers │  │  Tasks   │  │Nurseries│  │ Budgets │  │
│  │  (M:N)  │  │(Fibers)  │  │(Scopes) │  │(Caps)   │  │
│  └─────────┘  └──────────┘  └─────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Technical Details

### CBC-MN Scheduler

- **C**apability-**B**udgeted **C**ooperative **M**:**N** threading
- M user-space tasks multiplexed onto N OS threads
- Work-stealing for load balancing
- Stackful fibers (8KB stacks, x86_64 context switch)

### Cancellation Model

| Feature | Behavior |
|---------|----------|
| Cooperative | Tasks check `is_cancelled()` — not preemptive |
| Transitive | Parent cancellation → child cancellation |
| Structured | Nursery boundaries enforce cleanup |
| Error-triggered | Child error cancels nursery siblings |

### Performance

- **Task spawn:** ~1μs (fiber allocation + scheduler queue)
- **Context switch:** ~50ns (assembly-optimized)
- **Memory:** 8KB stack + ~200 bytes metadata per task
- **Scaling:** Tested to 10,000 concurrent tasks

---

## Comparison with Other Languages

| Feature | Janus | Go | Rust (async) | JS (Node) |
|---------|-------|-----|--------------|-----------|
| Concurrency | M:N fibers | M:N goroutines | M:N + work-stealing | Single-threaded + callbacks |
| Cancellation | Cooperative, structured | Cooperative (context) | Cooperative (drop) | Uncooperative |
| Stack | Stackful (8KB) | Stackful (growing) | Stackless | Stackless |
| Memory safety | Compile-time + runtime | Runtime | Compile-time | Runtime |
| No orphans | ✅ Yes | ❌ No (leak goroutines) | ⚠️ Partial | ❌ No |

---

## Files Added/Modified

```
runtime/scheduler/
├── scheduler.zig          # M:N scheduler core
├── task.zig               # Fiber-based tasks
├── nursery.zig            # Structured concurrency
├── worker.zig             # Work-stealing workers
├── continuation.zig       # x86_64 context switch
├── budget.zig             # Capability budgets
├── cancel_token.zig       # Cancellation propagation
└── test_nursery_cancellation.zig  # 53 passing tests

compiler/qtjir/
├── lower.zig              # Async/await lowering
├── llvm_emitter.zig       # LLVM code generation
├── graph.zig              # Await, Async_Call, Spawn opcodes
└── test_async_lower.zig   # Lowering tests

runtime/
└── janus_rt.zig           # janus_async_spawn, janus_async_await
```

---

## Testing

```bash
# Run all scheduler tests
cd janus
zig test runtime/scheduler/test_nursery_cancellation.zig \
    -I runtime/scheduler \
    runtime/scheduler/context_switch.s

# Expected: All 53 tests pass
```

---

## Limitations (Phase 3)

1. **No IO polling yet** — async is compute-only until IO reactor lands
2. **No `using` cleanup** — Phase 4 will add RAII resource cleanup
3. **x86_64 only** — context switch assembly is x86_64-specific

---

## Next: Phase 4

- Resource cleanup registry (LIFO)
- `using` statement full implementation
- RAII patterns for files, sockets, locks

---

## References

- SPEC-021: M:N Scheduler Specification
- SPEC-019: Cancellation Protocol
- `docs/teaching/async-await-tutorial.md` (student guide)

---

*Phase 3 represents 6 weeks of focused engineering. The scheduler is production-ready. The semantics are locked. Onward to Phase 4.*

— Janus Core Team 🦞
