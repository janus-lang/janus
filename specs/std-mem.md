<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC — Standard Memory Primitives (`janus.mem`)

* Status: **Draft (0.1.25)**
* Related: RFC-0002 Allocator Model, SPEC — Ownership at the Boundary
* Scope: Standard library package `janus.mem`

---

## 0. Purpose

The `janus.mem` package defines *ownership-safe memory primitives* that encode allocator provenance into first-class types.

Goals:

* **Codify ownership at the boundary.** No more naked `[ * ]u8` in APIs.
* **Reduce boilerplate.** Provide canonical ways to initialize, deinitialize, and pass owned memory.
* **Enforce caller sovereignty.** Every buffer carries its allocator.

---

## 1. Types

### 1.1 `Buffer`

Represents a raw, owned span of bytes allocated from a specific allocator.

```zig
pub const Buffer = struct {
    ptr:    [*]u8,
    layout: Layout,
    alloc:  *Allocator,

    pub fn init(alloc: *Allocator, size: usize, align: usize) !Buffer;
    pub fn deinit(self: *Buffer) void;
    pub fn asSlice(self: *Buffer) []u8;
    pub fn len(self: *Buffer) usize;
};
```

**Semantics:**

* `init` allocates memory of given `size` and `align`.
* `deinit` frees the memory using the captured allocator.
* `asSlice` produces a slice view (`[]u8`) of the buffer.
* `len` returns the current size (from layout).

---

### 1.2 `OwnedSlice`

Represents a slice of data with a dedicated deallocator.
Useful for crossing API boundaries where layout is opaque.

```zig
pub const OwnedSlice = struct {
    data:    [*]u8,
    len:     usize,
    dealloc: fn(ptr: [*]u8, layout: Layout) void,

    pub fn fromBuffer(buf: Buffer) OwnedSlice;
    pub fn deinit(self: *OwnedSlice) void;
    pub fn asSlice(self: *OwnedSlice) []u8;
};
```

**Semantics:**

* `fromBuffer` creates an `OwnedSlice` from a `Buffer`, embedding its deallocator.
* `deinit` invokes the stored deallocator with the captured layout.
* `asSlice` produces a slice view (`[]u8`).

---

## 2. Design Rules

1. **No naked pointers in APIs.** Always wrap them in `Buffer` or `OwnedSlice`.
2. **Ownership is absolute.** Only `deinit` may free the memory.
3. **Layout fidelity.** `Buffer` stores full `Layout`; `OwnedSlice` assumes layout from origin.
4. **Debug enforcement.** Double-free or cross-allocator free traps in debug.

---

## 3. Examples

### 3.1 Using `Buffer`

```zig
const buf = try Buffer.init(alloc, 1024, 8);
defer buf.deinit();

// Safe slice access
const slice = buf.asSlice();
slice[0] = 42;
```

### 3.2 Crossing Boundaries with `OwnedSlice`

```zig
fn producer(alloc: *Allocator) !OwnedSlice {
    const buf = try Buffer.init(alloc, 256, 8);
    return OwnedSlice.fromBuffer(buf);
}

fn consumer(os: OwnedSlice) void {
    const data = os.asSlice();
    // process data...
    os.deinit(); // frees via captured dealloc
}
```

---

## 4. Testing Strategy

* **Unit tests** for allocation, deallocation, slice length, and allocator provenance.
* **Failure injection tests**: allocation fails deterministically.
* **Debug tests**: double-free and cross-allocator traps.

---

**End of SPEC — Standard Memory Primitives**
