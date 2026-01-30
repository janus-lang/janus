<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Async Executor Architecture

**Document Type:** Design Document
**Status:** Approved
**Version:** 1.0.0
**Date:** 2026-01-29
**Author:** Janus Core Team
**Related Spec:** SPEC-020-async-executor

---

## Executive Summary

This document describes Janus's **Async Executor Architecture** - an abstraction layer that decouples concurrency semantics from execution backends. This design enables:

1. **Backend Flexibility:** Same code runs on threads, fibers, or async I/O
2. **Future-Proofing:** Ready for Zig 0.16's revolutionary `std.Io` interface
3. **Mechanism over Policy:** Users choose execution model, not the runtime

---

## 1. Design Philosophy

### 1.1 The Allocator Pattern

Zig's `Allocator` pattern revolutionized memory management:

```zig
// Old way: Global allocator (hidden cost)
var list = ArrayList(i32).init();

// Zig way: Explicit allocator (revealed cost)
var list = ArrayList(i32).init(allocator);
```

**Key insight:** The *caller* controls allocation strategy.

### 1.2 The Executor Pattern

We apply the same pattern to concurrency:

```janus
// Old way: Runtime chooses (Go, Crystal)
go func() { ... }()  // What threads? How many? Who knows.

// Janus way: Caller chooses
exec.spawn(func)  // Explicitly: threaded, evented, or blocking
```

**Key insight:** The *caller* controls execution strategy.

### 1.3 Why This Matters

| Aspect | Go/Crystal Approach | Janus Approach |
|--------|---------------------|----------------|
| Thread model | Runtime decides | User decides |
| Testing | Hope for determinism | Inject `blocking` for deterministic tests |
| Debugging | Stack traces across green threads | Choose `threaded` for clear stacks |
| Performance | One-size-fits-all | Tune per workload |
| Embedded | May not fit | Use `blocking` for single-threaded |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Janus Source Code                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  nursery do                                          │   │
│  │      spawn task_a()                                  │   │
│  │      spawn task_b()                                  │   │
│  │  end                                                 │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Executor Interface                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ Blocking │  │ Threaded │  │ Evented  │  │  Fibers  │    │
│  │ (0.15+)  │  │ (0.15+)  │  │ (0.16+)  │  │ (Future) │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Platform Primitives                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ Direct   │  │ pthreads │  │ io_uring │  │ Custom   │    │
│  │ Calls    │  │ Win32    │  │ kqueue   │  │ Scheduler│    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Executor Backends

### 3.1 Blocking Executor

**Purpose:** Sequential execution for debugging and deterministic tests.

```zig
pub const BlockingExecutor = struct {
    pub fn spawn(self: *@This(), func: anytype, args: anytype) TaskHandle {
        // Execute synchronously, immediately
        const result = @call(.auto, func, args);
        return TaskHandle.completed(result);
    }

    pub fn concurrent(self: *@This(), tasks: []const Task) void {
        // Run sequentially
        for (tasks) |task| {
            task.run();
        }
    }
};
```

**Use Cases:**
- Unit tests (deterministic execution order)
- Debugging (clear stack traces)
- Single-threaded embedded systems
- WASM targets

### 3.2 Threaded Executor

**Purpose:** True parallelism via OS threads. Current default.

```zig
pub const ThreadedExecutor = struct {
    thread_pool: ThreadPool,

    pub fn spawn(self: *@This(), func: anytype, args: anytype) !TaskHandle {
        const thread = try std.Thread.spawn(.{}, func, args);
        return TaskHandle.init(thread);
    }

    pub fn concurrent(self: *@This(), tasks: []const Task) !void {
        var handles: [MAX_CONCURRENT]TaskHandle = undefined;
        for (tasks, 0..) |task, i| {
            handles[i] = try self.spawn(task.func, task.args);
        }
        for (handles[0..tasks.len]) |handle| {
            handle.join();
        }
    }
};
```

**Use Cases:**
- CPU-bound parallelism
- Current production workloads
- Maximum compatibility

**Overhead:** ~8KB stack per thread, OS scheduler latency

### 3.3 Evented Executor (Zig 0.16+)

**Purpose:** High-concurrency I/O via kernel event queues.

```zig
pub const EventedExecutor = struct {
    io: std.Io,  // Zig 0.16's new interface

    pub fn spawn(self: *@This(), func: anytype, args: anytype) !TaskHandle {
        return try self.io.async(func, args);
    }

    pub fn concurrent(self: *@This(), tasks: []const Task) !void {
        try self.io.concurrent(tasks);  // Zig handles multiplexing
    }
};
```

**Platforms:**
- Linux: `io_uring` (kernel 5.1+)
- macOS: `kqueue`
- Windows: `IOCP`

**Use Cases:**
- 100K+ concurrent connections
- I/O-bound services
- Network servers

**Not Available:** Zig 0.15.x (returns `error.ExecutorUnavailable`)

### 3.4 Fiber Executor (Future)

**Purpose:** Massive concurrency with cooperative scheduling.

```zig
pub const FiberExecutor = struct {
    scheduler: FiberScheduler,

    pub fn spawn(self: *@This(), func: anytype, args: anytype) !TaskHandle {
        const fiber = try self.scheduler.createFiber(func, args);
        return TaskHandle.init(fiber);
    }

    pub fn yield(self: *@This()) void {
        self.scheduler.yield();  // Cooperative switch
    }
};
```

**Use Cases:**
- Million+ concurrent tasks
- Game servers
- Simulation workloads

**Status:** Planned for `:sovereign` dogfooding

---

## 4. Channel System

### 4.1 Design Goals

| Goal | Rationale |
|------|-----------|
| Type-safe | `Channel[T]` prevents type confusion |
| Non-nullable | No nil channel blocking forever (Go's trap) |
| Backend-agnostic | Works with any Executor |
| Capability-gated | `CapChannel` required for creation |

### 4.2 Implementation Layers

```
┌─────────────────────────────────────────┐
│           Janus Channel API             │
│  send(), recv(), close(), select        │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│        Synchronization Layer            │
│  Mutex, Condition Variables, Atomics    │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│         Buffer Management               │
│  Ring buffer for buffered channels      │
└─────────────────────────────────────────┘
```

### 4.3 Unbuffered vs Buffered

**Unbuffered (Synchronous):**
```janus
let ch = Channel[i32].new(allocator)
// send() blocks until recv() ready
// recv() blocks until send() ready
// Rendezvous semantics
```

**Buffered (Asynchronous):**
```janus
let ch = Channel[i32].buffered(allocator, capacity: 10)
// send() blocks only when buffer full
// recv() blocks only when buffer empty
// Decouples producer/consumer timing
```

### 4.4 Channel State Machine

```
                    ┌─────────────┐
                    │   Created   │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
       ┌─────────────┐           ┌─────────────┐
       │   Empty     │◄─────────►│   HasData   │
       │ (recv waits)│  send()   │(send may    │
       └─────────────┘  recv()   │ wait if full│
              │                   └─────────────┘
              │ close()                 │ close()
              ▼                         ▼
       ┌─────────────┐           ┌─────────────┐
       │   Closed    │           │   Draining  │
       │  (empty)    │           │(has data)   │
       └─────────────┘           └──────┬──────┘
                                        │ recv() until empty
                                        ▼
                                 ┌─────────────┐
                                 │   Closed    │
                                 │  (empty)    │
                                 └─────────────┘
```

---

## 5. Select Implementation

### 5.1 Algorithm

Select uses a **multi-wait** pattern:

1. **Lock all channels** (sorted by address to prevent deadlock)
2. **Check for ready operations**
3. **If none ready and no default:** Sleep on condition variable
4. **When woken:** Re-check all channels
5. **Execute first ready case**
6. **Unlock all channels**

### 5.2 Fairness

```zig
// Prevent starvation: rotate starting index
fn selectFair(cases: []SelectCase, last_selected: *usize) ?usize {
    const start = (last_selected.* + 1) % cases.len;
    var i: usize = 0;
    while (i < cases.len) : (i += 1) {
        const idx = (start + i) % cases.len;
        if (cases[idx].isReady()) {
            last_selected.* = idx;
            return idx;
        }
    }
    return null;
}
```

### 5.3 Timeout Integration

```zig
fn selectWithTimeout(cases: []SelectCase, timeout_ns: ?u64) !?usize {
    const deadline = if (timeout_ns) |t|
        std.time.nanoTimestamp() + t
    else
        null;

    while (true) {
        if (selectFair(cases, &last)) |idx| return idx;

        if (deadline) |d| {
            const remaining = d - std.time.nanoTimestamp();
            if (remaining <= 0) return null;  // Timeout
            condition.timedWait(mutex, remaining);
        } else {
            condition.wait(mutex);
        }
    }
}
```

---

## 6. Zig 0.16 Migration

### 6.1 Feature Detection

```zig
const has_std_io = @hasDecl(std, "Io");

pub const Executor = if (has_std_io) struct {
    // 0.16+ implementation with std.Io
    io: std.Io,
    // ...
} else struct {
    // 0.15.x fallback
    threaded: ThreadedExecutor,
    // ...
};
```

### 6.2 Gradual Adoption

```janus
// Code that works on both versions:
func process(exec: Executor) !void do
    nursery do
        spawn task()
    end
end

// 0.15.x: Uses ThreadedExecutor
// 0.16.x: Can use EventedExecutor if available
```

### 6.3 Platform Matrix

| Platform | 0.15.x | 0.16.x |
|----------|--------|--------|
| Linux | threaded | evented (io_uring) |
| macOS | threaded | evented (kqueue) |
| Windows | threaded | evented (IOCP) |
| WASM | blocking | blocking |
| Embedded | blocking | blocking |

---

## 7. Comparison with Competitors

### 7.1 vs Go

| Aspect | Go | Janus |
|--------|-----|-------|
| Scheduler | Built-in, non-configurable | User-selectable backend |
| Channels | Nil allowed (blocks forever) | Non-nullable |
| Structured concurrency | None (goroutines leak) | Nurseries |
| Testing | Hope for determinism | Inject blocking executor |

### 7.2 vs Rust/Tokio

| Aspect | Rust/Tokio | Janus |
|--------|------------|-------|
| Runtime | Choose at project start | Choose at call site |
| Async | Colored functions | Same code, different executor |
| Complexity | Pin, poll, futures | spawn/await simplicity |

### 7.3 vs Crystal

| Aspect | Crystal | Janus |
|--------|---------|-------|
| Threading | Single-threaded default | Multi-threaded capable |
| Parallelism | Experimental | Production-ready |
| Syntax | Ruby-like | Lua-like (simpler) |

---

## 8. Security Considerations

### 8.1 Capability Requirements

| Operation | Capability | Reason |
|-----------|------------|--------|
| `spawn` | CapSpawn | Thread resource consumption |
| `Channel.new` | CapChannel | Memory + sync primitives |
| `Executor.evented` | CapIo | Kernel I/O access |

### 8.2 Resource Limits

```janus
// Executor with limits
let exec = Executor.threaded(config: .{
    .max_threads = 100,
    .stack_size = 64 * 1024,
})

// Channel with limits
let ch = Channel[Msg].buffered(allocator, capacity: 1000)
```

### 8.3 Deadlock Prevention

1. **Lock ordering:** Channels locked by address
2. **Timeout support:** All operations can timeout
3. **Capability gates:** Prevent unauthorized spawning

---

## 9. Implementation Roadmap

### Phase 3: Channels (Current Focus)

```
Week 1: Channel[T] type, send/recv
Week 2: Buffered channels, close semantics
Week 3: Integration tests, race detection
```

### Phase 4: Select

```
Week 4: Parser support for select syntax
Week 5: Runtime implementation
Week 6: Timeout and default cases
```

### Phase 5: Executor Abstraction

```
Week 7: Executor interface
Week 8: Backend implementations
Week 9: Nursery integration
```

### Phase 6: Zig 0.16 Preparation

```
Week 10: Feature detection
Week 11: EventedExecutor stub
Week 12: Migration documentation
```

---

## 10. Open Questions

1. **Should channels be ref-counted?**
   - Pro: Easier to pass around
   - Con: Hidden allocation cost

2. **Should select support priorities?**
   - Pro: More control
   - Con: Complexity, non-determinism

3. **Should we support channel iteration?**
   ```janus
   for msg in ch do  // Like Go's range over channel
       process(msg)
   end
   ```

---

## 11. References

- [Zig's New Async I/O](https://kristoff.it/blog/zig-new-async-io/)
- [CSP Original Paper](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf)
- [Go Channel Implementation](https://go.dev/src/runtime/chan.go)
- [Kotlin Structured Concurrency](https://kotlinlang.org/docs/coroutines-basics.html)

---

**Document History:**
- 2026-01-29: Initial version
