<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC — Ownership at the Boundary

- Status: **Normative (0.1.25)**
- Related: RFC-0002 Allocator Model, RFC-0001 Error Model

------

## 0. The Doctrine

**Ownership is absolute.**
 A buffer belongs to the allocator that created it. Freeing it with any other allocator is **undefined behavior** (UB in release, trap in debug).

At module boundaries, this doctrine must remain unbroken. If memory crosses a boundary, so must the means of returning it.

------

## 1. Core Patterns

### 1.1 Pass the Allocator with the Buffer

The most direct form. The caller hands both the pointer and the allocator to the callee.

```janus
struct Buffer {
    ptr: [*]u8,
    layout: Layout,
    alloc: *Allocator,
}

// The callee may inspect or transform the buffer but must
// return ownership intact or explicitly deallocate via `alloc`.
```

### 1.2 Pass a Deallocator Callback

Where API ergonomics demand decoupling, pass a closure or function pointer to free the buffer.

```janus
struct OwnedSlice {
    data: [*]u8,
    len: usize,
    dealloc: fn(ptr: [*]u8, layout: Layout) void,
}
```

This allows the producer to embed knowledge of allocator + layout without leaking that detail to the consumer.

### 1.3 Transfer by Copy

If ownership transfer is impossible or unsafe, copy the data into the consumer’s own allocator domain.
 Rule: **Copy, don’t lie.**

------

## 2. Golden Rules

1. **Never free across allocators.** If the origin is unknown, treat the memory as read-only and copy.
2. **Layouts are sacred.** Always pass the correct `(size, align)` with the buffer.
3. **Debug traps are teachers.** Double-free, cross-allocator free, or invalid layout *must* trap in debug builds.
4. **AOOM is caller policy.** A consumer may decide to abort on OOM, but the producer may never assume it.

------

## 3. Examples

### 3.1 Producer/Consumer with Allocator

```janus
pub fn produce(a: *Allocator) !Buffer {
    const lay = Layout{ .size = 1024, .align = 8 };
    const ptr = try a.allocate(lay, .{});
    return Buffer{ .ptr = ptr, .layout = lay, .alloc = a };
}

pub fn consume(buf: Buffer) void {
    // ... use buf.ptr ...
    buf.alloc.deallocate(buf.ptr, buf.layout);
}
```

### 3.2 API with Deallocator

```janus
pub fn readFile(path: []const u8, alloc: *Allocator) !OwnedSlice {
    const lay = Layout{ .size = 4096, .align = 8 };
    const ptr = try alloc.allocate(lay, .{});
    // fill ptr...
    return OwnedSlice{
        .data = ptr,
        .len = lay.size,
        .dealloc = fn(p: [*]u8, l: Layout) void {
            alloc.deallocate(p, l);
        },
    };
}

pub fn useFile(slice: OwnedSlice) void {
    // ... process slice.data ...
    slice.dealloc(slice.data, Layout{ .size = slice.len, .align = 8 });
}
```

------

## 4. Anti-Patterns (Forbidden)

- **Returning raw `[ \* ]u8`** without allocator/layout context.
- **Assuming caller will free with global allocator.**
- **Mixing AOOM and fallible policies in the same call chain without clear documentation.**

------

## 5. Debug Culture

- CI must run with **debug allocator + failure injection**.
- Any violation (double-free, cross-allocator, invalid layout) must **trap**.
- Violations in release are UB by design; the traps are there to teach and catch them early.

------

## 6. Closing Doctrine

**Ownership at the boundary is not a suggestion.**
 It is a **law of survival** for Janus programs.

Break it, and you invite chaos: leaks, UAF, nondeterminism.
 Honor it, and your programs will remain composable, safe, and brutally honest.

------

**End of SPEC — Ownership at the Boundary**
