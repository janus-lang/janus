<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Runtime Root Architecture

**Status:** Canonical
**Specification:** [SPEC-021](../../specs/SPEC-021-scheduler.md) Section 2
**Date:** 2026-01-29

---

## Overview

This document describes Janus's **Runtime Root Architecture** — a fundamental design decision that ensures **no invisible authority** in concurrent execution.

**The Core Principle:**

> **One global runtime root. Explicit scheduler handles everywhere else.**

This architecture gives Janus something that Go, Rust, Erlang, and Zig do not have:

**A first-class runtime root with explicit ownership of concurrency.**

---

## Why This Matters

### The Problem with Global Schedulers

Most runtimes have a hidden scheduler:

```go
// Go: Hidden runtime with implicit scheduler
go func() { ... }()  // Where does this run? Who knows!
```

```rust
// Tokio: Global runtime, implicit spawn
tokio::spawn(async { ... });  // Which executor? The ambient one!
```

This creates:

- **Hidden authority** — Magic happens somewhere
- **Test isolation problems** — Global state pollutes tests
- **Embedding difficulties** — Can't have multiple runtimes
- **Debugging nightmares** — Where did that goroutine come from?

### The Janus Solution

In Janus, **scheduling is explicit** and **authority is visible**:

```janus
// Authority is explicit and visible
nursery do
    spawn task_a()  // Uses nursery's scheduler handle
    spawn task_b()  // Same scheduler, visible relationship
end
```

---

## Architecture

### One Global Root

There is exactly **ONE** permitted global in the Janus runtime:

```zig
var GLOBAL_RT: ?*Runtime = null;  // The ONLY global
```

This is the **runtime root**, not a scheduler singleton.

### Runtime Owns Everything

The Runtime struct owns all subsystems:

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

**Why this distinction matters:**

| Concern | Global Scheduler | Runtime Root |
|---------|------------------|--------------|
| Test isolation | ❌ Hard | ✅ Easy |
| Multiple runtimes | ❌ Impossible | ✅ Natural |
| Embedding Janus | ❌ Painful | ✅ Clean |
| Capability routing | ❌ Implicit | ✅ Explicit |
| Future IO integration | ❌ Tangled | ✅ Layered |

### Explicit Handles, Not Callbacks

Nurseries store an **explicit scheduler handle**:

```zig
pub const Nursery = struct {
    scheduler: *Scheduler,      // Explicit reference
    parent_task: ?TaskId,       // Structured concurrency
    budget: Budget,             // Resource limits
};
```

**NOT callbacks:**

```zig
// FORBIDDEN
spawn_callback: *const fn (*Task) bool  // NO! Hidden authority
```

Task submission is a direct method call:

```zig
pub fn spawn(self: *Nursery, entry: TaskFn, arg: ?*anyopaque) !TaskId {
    return self.scheduler.spawn(.{
        .entry = entry,
        .arg = arg,
        .parent = self.parent_task,
    });
}
```

---

## Design Rules

### Rule 1: No Invisible Authority

Janus does **NOT** do:

- ❌ Hidden TLS (thread-local storage)
- ❌ Ambient globals
- ❌ Magical callbacks
- ❌ Implicit state

Even the scheduler must be passed or owned explicitly.

### Rule 2: GLOBAL_RT Is Optional

The global runtime is a **convenience for the default embedding**.

Alternative runtimes MAY exist for:

- Testing (isolated schedulers)
- Embedding (multiple independent runtimes)
- Sandboxing (restricted environments)

These MUST NOT rely on `GLOBAL_RT`.

### Rule 3: No Reach-Arounds

Subsystems MUST NOT access `GLOBAL_RT` directly:

```zig
// FORBIDDEN: Direct global access
fn nurserySpawn(...) {
    GLOBAL_RT.?.scheduler.spawn(...);  // NO! Hidden authority
}

// REQUIRED: Explicit parameter
fn nurserySpawn(scheduler: *Scheduler, ...) {
    scheduler.spawn(...);  // YES! Explicit
}
```

This prevents hidden coupling and maintains the explicit authority principle.

---

## Testing Support

The architecture supports **isolated test runtimes**:

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

A **single-threaded scheduler variant** is provided for deterministic tests:

```zig
const scheduler_impl = switch (builtin.mode) {
    .Debug => SingleThreadScheduler,  // Deterministic for tests
    else => WorkStealingScheduler,    // Full M:N
};
```

---

## Strategic Benefits

### 1. Scheduling Is Policy, Not Miracle

The scheduler is just another subsystem. It can be:

- Replaced (different implementations)
- Configured (per-application tuning)
- Extended (custom scheduling policies)

### 2. Concurrency Is a Resource, Not a Right

Tasks don't spawn themselves. They need:

- A nursery (structured scope)
- A scheduler handle (explicit authority)
- Budget (resource limits)

This enables **language-level DoS immunity**.

### 3. Runtime Behavior Is Inspectable

Because authority flows explicitly:

- You can trace task spawning
- You can profile scheduler behavior
- You can debug concurrency issues
- You can test in isolation

---

## Future-Proofing

This architecture enables:

- **Multi-runtime**: Embedding multiple Janus runtimes
- **Sandboxing**: Restricted execution environments
- **IO integration**: Adding event loops alongside scheduler
- **Capability evolution**: Richer authorization models
- **Profiling**: Runtime introspection and debugging

The architecture can **outgrow its first scheduler** without breaking existing code.

---

## Related Documents

- [SPEC-021: M:N Scheduler](../../specs/SPEC-021-scheduler.md) — Full specification
- [SPEC-022: Scheduling Capabilities](../../specs/SPEC-022-scheduling-capabilities.md) — Capability system
- [Philosophy: Strategic Pragmatism](../philosophy/STRATEGIC_PRAGMATISM.md) — Design principles

---

*"One runtime root. Explicit handles. No invisible authority."*

**Ratified:** 2026-01-29
**Authority:** Markus Maiwald
