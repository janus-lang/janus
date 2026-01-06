<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# RFC-0002 — Allocator Model (v0.1.25 Finalized Pre-1.0)

* Status: **Finalized Pre-1.0 (0.1.25)**
* Owners: Language / Runtime
* Last updated: 2025-09-07
* Related: RFC-0001 Error Model, SPEC — Boot & Capabilities

---

## 0. Summary

This RFC defines:

1. The **default global allocator** used by Janus programs, its guarantees, and debug behavior.
2. The **minimal, stable allocator trait** that enables arenas, slabs, bump allocators, and pools.
3. The **final 1.0-frozen decisions** around ownership, error semantics, and separation from Boot/AppContext.

Principle: **Caller sovereignty.** Allocations are **fallible by default**, no implicit aborts. Programs may opt into **Abort-on-OOM** explicitly.

---

## 1. Goals & Non-Goals

### Goals

* A small, stable allocator surface that works across native + WASM/WASI.
* A **thread-safe** default global allocator with predictable semantics.
* Trait enabling custom allocators without breaking 1.x.
* Deterministic testing hooks (seeded failure injection) for CI.

### Non-Goals

* No GC, no hidden compaction/moving.
* No introspection, fragmentation stats, or advanced metrics in 1.0 (future extension traits possible).

---

## 2. Definitions

* **Layout:** `(size, align)` where `align` is a power of two, `≥ MIN_ALIGN`.
* **Allocator:** Object with vtable of `allocate`, `reallocate`, `deallocate`.
* **Global allocator:** Process-wide default if no explicit allocator provided.
* **Ownership:** A pointer must be freed by **the same allocator** that produced it. Cross-allocator free = **UB (release)** / **trap (debug)**.

---

## 3. Default Global Allocator

### 3.1 Behavior

* **Thread-safe** across all supported targets.
* **Fallible**: return `!AllocError`; no implicit aborts.
* **Alignment**: rounds up to `MIN_ALIGN`.
* **Zeroing**: honors flags.
* **Determinism**: supports seeded failure injection in debug/test builds.
* **WASM/WASI**: wraps host memory APIs; thread-safe within host limits.

### 3.2 MIN\_ALIGN

* 64-bit: 8
* 32-bit: 4
* WASM: pointer size

### 3.3 OOM Policy

* **Default:** fallible, return `error.OutOfMemory`.
* **Optional:** AOOM (Abort-on-OOM) opt-in via build/runtime flag.

### 3.4 Debug Ergonomics

* Poison fresh memory with pattern (unless `Zeroed`).
* Poison freed memory with different pattern.
* Optional bounded quarantine.
* Failure injection:

  * `JANUS_ALLOC_FAIL_AFTER=N`
  * `JANUS_ALLOC_FAIL_RATE=1/1000`

---

## 4. The Allocator Trait (frozen for 1.x)

```janus
pub const Layout = struct {
    size:  usize,
    align: u32, // rounded up to MIN_ALIGN
};

pub const AllocFlags = packed struct {
    zeroed: bool = false,
};

pub const ReallocFlags = packed struct {
    move_ok:   bool = true,
    zero_tail: bool = false,
};

pub const Allocator = struct {
    ctx:    *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        allocate:   fn(ctx: *anyopaque, layout: Layout, flags: AllocFlags)
                     ![*]u8,
        reallocate: fn(ctx: *anyopaque, ptr: [*]u8, old: Layout, new: Layout, flags: ReallocFlags)
                     ![*]u8,
        deallocate: fn(ctx: *anyopaque, ptr: [*]u8, layout: Layout) void,
        caps:       fn(ctx: *anyopaque) AllocCaps,
    };

    pub const AllocCaps = packed struct {
        thread_safe:     bool,
        deterministic:   bool,
        supports_zeroed: bool,
    };
};
```

### 4.1 Error Enum

```janus
enum AllocatorError {
  OutOfMemory,
  InvalidLayout,
  DoubleFree,         // debug trap; UB in release
  CrossAllocatorFree, // debug trap; UB in release
}
```

### 4.2 Semantics

* `allocate`: aligned, size-aware span.
* `reallocate`:

  * `move_ok=false` → must attempt in-place, fail otherwise.
  * Failure preserves original block.
  * `zero_tail=true` → new bytes zeroed.
* `deallocate`: never fails; layout must match. Wrong allocator/layout = UB (debug trap).
* `[ * ]u8` return prevents silent size confusion.

---

## 5. Using Allocators

* **Global:** `janus.mem.global()` → default allocator.
* **Explicit:** heavy APIs should accept `*Allocator`.
* **Hygiene:**

  * `#[must_use]` on allocate/reallocate results.
  * If buffers cross APIs, pass `(ptr, layout, allocator)` or a deallocator callback.

---

## 6. Global Allocator Selection

Precedence:

1. Build flag (`--alloc=system|jemalloc|mimalloc|wasi|debug|tracking`)
2. Env (`JANUS_ALLOC=debug`)
3. Platform default (system malloc / host allocator)

Changing allocator after threads start = UB.

---

## 7. Error Handling & OOM Strategy

* Always fallible (`!AllocError`).
* Never panic/abort implicitly.
* AOOM opt-in for simple tools.
* RFC-0001 governs supervised crash patterns; allocators themselves stay honest.

---

## 8. Concurrency & Determinism

* `caps.thread_safe=true` → safe for concurrent use.
* Deterministic allocators expose seeding.
* Global allocator always thread-safe.

---

## 9. Debugging Facilities

* Poison patterns, optional quarantine.
* Failure injection env vars (see §3.4).
* Debug builds **must trap** on double-free, cross-allocator free, invalid layout.

---

## 10. Examples

* Arena allocator example.
* API usage with explicit allocator (unchanged).

---

## 11. Compatibility Guarantees

* Shape of `Allocator`, `Layout`, flags, vtable functions, and `AllocatorError` is **frozen for 1.x**.
* Extension traits (stats, secure zeroization) may appear later without breaking clients.

---

## 12. Finalized Decisions

* **No `adopt` API**: ownership absolute.
* **No stats/introspection** in 1.0.
* **Allocator not part of Boot/AppContext**.

---

## 13. Migration & Policy

* APIs: accept explicit allocator or default to global.
* CI: run tests under debug allocator with failure injection.
* Safety-critical code: propagate OOM, avoid AOOM.

---

## 14. Post-1.0 Backlog

* `AllocatorProbe` stats layer.
* Pool helpers, SecureAllocator, recycling strategies.
* Optional ergonomic helpers.

---

**End of RFC-0002 — Allocator Model (v0.1.25 Finalized Pre-1.0)**
