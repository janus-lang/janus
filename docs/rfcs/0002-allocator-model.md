<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# RFC-0002 — Allocator Model

* Status: **Draft (0.1.15-foundational)**
* Owners: Language / Runtime
* Last updated: 2025-09-06
* Related: RFC-0001 Error Model, SPEC — Boot & Capabilities

## 0. Summary

This RFC defines:

1. The **default global allocator** used by Janus programs, its guarantees, and debug behavior.
2. The **minimal, stable allocator trait** that allows users to plug in custom allocators for performance-critical work without breaking 1.x.

We prioritize **caller sovereignty** and **predictable failure**: allocations are fallible by default (no implicit aborts), and programs may opt into “abort on OOM” policy explicitly.

---

## 1. Goals & Non-Goals

### Goals

* A small, stable allocator surface that works across native and WASM/WASI targets.
* A **thread-safe** default global allocator with predictable semantics.
* A trait that enables arenas, slabs, region/bump allocators, and specialized pools **without** rewriting clients for 0.2.0.
* Deterministic testing hooks (seeded failure injection) for CI.

### Non-Goals

* No GC and no implicit compaction/moving of objects behind the user’s back.
* No attempt to standardize advanced features (introspection, quarantine, usable\_size) in 0.1.15; these may arrive as optional extension traits later.

---

## 2. Definitions

* **Layout**: `(size, align)` where `align` is a power of two, `align ≥ MIN_ALIGN`.
* **Allocator**: An object with a vtable of three primitives: `allocate`, `reallocate`, `deallocate`.
* **Global allocator**: Process-wide default used when no explicit allocator is provided.
* **Ownership**: A pointer must be deallocated by **the same allocator** that produced it (cross-allocator free is UB).

---

## 3. Default Global Allocator

### 3.1 Behavior (normative)

* **Thread-safe** across all supported targets.
* **Fallible**: operations return `!AllocError`; no implicit process aborts.
* **Alignment**: guarantees the requested power-of-two alignment; if the request is `< MIN_ALIGN`, it is rounded **up** to `MIN_ALIGN`.
* **Zeroing**: honors the `Zeroed` flag on allocate/reallocate (new bytes zeroed on growth).
* **Determinism**: supports seeded **failure injection** in test/debug builds.
* **WASM/WASI**: implemented over the host’s memory APIs; still thread-safe (within host limits).

### 3.2 MIN\_ALIGN

* 64-bit targets: `MIN_ALIGN = 8`
* 32-bit targets: `MIN_ALIGN = 4`
* WASM: `MIN_ALIGN = pointer_size`

### 3.3 OOM Policy

* **Default**: fallible, return `error.OutOfMemory`.
* **Optional** (build/runtime flag): **Abort on OOM** (AOOM). In AOOM, the allocator aborts the process on OOM; this is opt-in and primarily for small tools/services with simple failure semantics.

### 3.4 Debug ergonomics

In **debug** builds the global allocator:

* Poisons fresh memory with a non-zero pattern unless `Zeroed` is set.
* Poisons freed memory with a different pattern.
* Optionally keeps a small quarantine (bounded) to catch UAF; disabled by default.
* Honors failure injection: `JANUS_ALLOC_FAIL_AFTER=N` and `JANUS_ALLOC_FAIL_RATE=1/1000`.

---

## 4. The Allocator Trait (stable for 1.x)

> Minimal, explicit, no surprises. Everything else can be layered on top.

```zig
// Core types
pub const Layout = struct {
    size:  usize,
    align: u32,          // power of two; rounded up to MIN_ALIGN
};

pub const AllocFlags = packed struct {
    zeroed: bool = false, // guarantee zeroed bytes on success
};

pub const ReallocFlags = packed struct {
    move_ok:        bool = true,  // if false, only in-place growth/shrink is allowed
    zero_tail:      bool = false, // if growing and move_ok, new bytes must be zeroed
};

// The minimal stable trait (vtable-based; FFI-friendly)
pub const Allocator = struct {
    ctx:    *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        allocate:   fn(ctx: *anyopaque, layout: Layout, flags: AllocFlags)
                     ![*]u8, // non-null on success; length == layout.size
        reallocate: fn(ctx: *anyopaque,
                       ptr:  [*]u8,
                       old:  Layout,
                       new:  Layout,
                       flags: ReallocFlags)
                     ![*]u8, // may return same or new address
        deallocate: fn(ctx: *anyopaque, ptr: [*]u8, layout: Layout) void,
        // capability bits (stable shape; values may evolve)
        caps:       fn(ctx: *anyopaque) AllocCaps,
    };

    pub const AllocCaps = packed struct {
        thread_safe:     bool, // safe for concurrent use without external sync
        deterministic:   bool, // same sequence under same seed (if any)
        supports_zeroed: bool, // honors zeroed/zero_tail without emulation
    };
};
```

### 4.1 Semantics

* **allocate**:

  * On success: returns a pointer aligned to `layout.align`, valid for exactly `layout.size` bytes.
  * Must honor `flags.zeroed`. If not natively supported, the allocator may zero manually.
* **reallocate**:

  * If `move_ok == false`, the allocator **must** attempt in-place resize; failure returns `error.OutOfMemory` (no move attempted).
  * If `move_ok == true`, the allocator may allocate a new region, copy `min(old.size, new.size)` bytes, free the old, and return the new pointer.
  * If growing and `zero_tail == true`, newly added bytes must be zeroed on success.
* **deallocate**:

  * Never fails. Pointer must come from the **same** allocator with **exact** `layout` originally used or last returned by `reallocate`. Passing the wrong layout is **UB**.

**Notes**

* `[*]u8` (pointer + known length) makes the returned span size-aware and reduces size confusion at call sites.
* We explicitly do **not** provide `usable_size` in the minimal trait; use higher-level helpers if needed.

---

## 5. Using Allocators

### 5.1 Global vs explicit allocators

* **Global**: `janus.mem.global()` returns an `Allocator` that is thread-safe and suitable for general use.
* **Explicit**: Performance-critical components may accept an `*Allocator` parameter to use arenas/slabs without touching the global.

**Rule of thumb:** APIs that may allocate **large or many** objects should accept an explicit allocator parameter; tiny helpers may use the global.

### 5.2 Passing layout correctly

* The **caller** is responsible for providing the correct `Layout` on `deallocate` and `reallocate`.
* Library helpers (`janus.mem.layoutOf(T)`, `arrayLayout(T, n)`) reduce mistakes.

### 5.3 Zeroing and secrets

* For sensitive data, call `zero_tail=true` when growing, and explicitly wipe before `deallocate`.
* A future **SecureAllocator** extension trait may guarantee in-kernel zeroization; not part of this RFC.

---

## 6. Global Allocator Selection & Bootstrap

* The global allocator is initialized before `main` runs.
* Selection precedence:

  1. **Build flag** (e.g., `--alloc=system|jemalloc|mimalloc|wasi|debug|tracking`)
  2. **Environment** (e.g., `JANUS_ALLOC=debug`, `JANUS_ALLOC_AOOM=1`)
  3. **Platform default**:

     * Native: System allocator (libc `malloc/free`) or bundled high-quality allocator when configured.
     * WASM/WASI: host allocator.
* Changing the global allocator **after threads start** is **undefined**; changing before first allocation is allowed (advanced users only).

---

## 7. Error Handling & OOM Strategy

* All allocator operations are **fallible** (`!AllocError`).
* Library code must **propagate** OOM without converting to panics.
* Users may opt into **AOOM** (abort on OOM) via flag/env for simple programs.
* RFC-0001 (Error Model) defines when it’s acceptable to use crash-only patterns; allocator APIs do not crash implicitly.

---

## 8. Concurrency & Determinism

* `Allocator.caps().thread_safe == true` if it supports concurrent calls without external synchronization.
* Deterministic allocators (e.g., test arenas) should set `deterministic==true` and expose seeding via their constructors.
* The **global** allocator is thread-safe; determinism depends on chosen backend.

---

## 9. Debugging Facilities (non-normative defaults)

* Poisoning patterns (e.g., `0xCC` fresh, `0xDD` freed) in debug builds.
* Optional bounded quarantine to catch UAF.
* Failure injection via:

  * `JANUS_ALLOC_FAIL_AFTER=N`  (fail the Nth allocate/reallocate)
  * `JANUS_ALLOC_FAIL_RATE=1/1000` (probabilistic)

These are **implementation details** of the default debug allocator and do not affect the trait.

---

## 10. Examples

### 10.1 Implementing a bump (arena) allocator

```zig
const Bump = struct {
    buf:   []u8,
    head:  usize,
    caps:  Allocator.AllocCaps = .{ .thread_safe=false, .deterministic=true, .supports_zeroed=false },

    fn allocate(ctx: *anyopaque, layout: Layout, flags: AllocFlags) ![*]u8 {
        const self = @ptrCast(*Bump, ctx);
        const aligned = alignForward(self.head, layout.align);
        const end = aligned + layout.size;
        if (end > self.buf.len) return error.OutOfMemory;
        const p = self.buf[aligned..end];
        self.head = end;
        if (flags.zeroed) @memset(p, 0);
        return p;
    }

    fn reallocate(ctx: *anyopaque, ptr: [*]u8, old: Layout, new: Layout, flags: ReallocFlags) ![*]u8 {
        // Arena cannot shrink/grow in place; only move_ok flow
        if (!flags.move_ok) return error.OutOfMemory;
        const self = @ptrCast(*Bump, ctx);
        const fresh = try allocate(ctx, new, .{ .zeroed = flags.zero_tail });
        @memcpy(fresh[0..@min(old.size, new.size)], ptr[0..@min(old.size, new.size)]);
        // Note: the arena is monotonic; deallocate is a no-op
        return fresh;
    }

    fn deallocate(ctx: *anyopaque, ptr: [*]u8, layout: Layout) void {
        _ = ctx; _ = ptr; _ = layout; // no-op; reset happens out-of-band
    }

    fn caps(ctx: *anyopaque) Allocator.AllocCaps {
        return @ptrCast(*Bump, ctx).caps;
    }

    pub fn asAllocator(self: *Bump) Allocator {
        return .{ .ctx = self, .vtable = &.{
            .allocate   = allocate,
            .reallocate = reallocate,
            .deallocate = deallocate,
            .caps       = caps,
        }};
    }
};
```

### 10.2 Using an explicit allocator in an API

```zig
pub fn parseJson(alloc: *Allocator, input: []const u8) !JsonValue {
    const lay = Layout{ .size = input.len * 2, .align = 8 };
    const tmp = try alloc.vtable.allocate(alloc.ctx, lay, .{ .zeroed = false });
    defer alloc.vtable.deallocate(alloc.ctx, tmp, lay);
    // ... parse using tmp scratch ...
}
```

---

## 11. Compatibility Guarantees

* The shape of `Allocator`, `Layout`, `AllocFlags`, `ReallocFlags`, the three vtable functions, and `AllocCaps` is **frozen for 1.x**.
* 1.x may add **optional extension traits** (e.g., `Introspect`, `SecureAllocator`) without breaking existing allocators/clients.
* 0.2.0 may add new convenience helpers, but the core trait will remain source-compatible.

---

## 12. Open Questions

* Should we add an **adopt** API to transfer ownership across allocators (opt-in, unsafe)? *Leaning no for 0.1.15.*
* Do we standardize a **stats/introspection** extension trait in 1.x (live bytes, fragmentation, high-water marks)?
* Should `BootInit` gain an optional allocator provider in 1.x? (Current stance: keep allocator independent of Boot to avoid widening the core context; revisit post-0.1.15 if needed.)

---

## 13. Migration & Policy

* Libraries that currently hard-code a specific allocator should:

  * Accept `*Allocator` in public APIs for large allocations, and
  * Fall back to `janus.mem.global()` when none is provided.
* For safety-critical code, avoid AOOM and propagate `error.OutOfMemory`.
* CI should run with a debug allocator + failure injection to catch OOM handling regressions.

---

**End of RFC-0002 — Allocator Model**
