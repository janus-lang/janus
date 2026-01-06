<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





<!--
---
title: SPEC - std.mem
description: The granite foundation of Janus memory primitives.
author: Self Sovereign Society Foundation
date: 2025-09-24
license: |
  
  // Copyright (c) 2026 Self Sovereign Society Foundation
  // The full text of the license can be found in the LICENSE file at the root of the repository.
version: 0.1
---
-->

# 📜 SPEC – std.mem

## Charter

- Provide the absolute minimum memory primitives: `copy`, `move`, `eql`, `zeroes`.
- Define the canonical allocator interface, to be used consistently across `std.*`.
- No GC, no hidden runtime tricks. Explicit control, revealed complexity.
- Performance is not negotiable: these must compile down to optimal raw instructions.

## Zig Code — `std/mem.zig`

```zig
const std = @import("std");

/// =======================
/// Canonical Allocator API
/// =======================

pub const Allocator = struct {
    /// Allocate a slice of `n` elements of type `T`.
    pub fn alloc(self: *Allocator, comptime T: type, n: usize) ![]T {
        return self.vtable.allocFn(self.ptr, T, n);
    }

    /// Free a previously allocated slice.
    pub fn free(self: *Allocator, slice: anytype) void {
        self.vtable.freeFn(self.ptr, slice);
    }

    /// Reallocate a slice to a new size.
    pub fn realloc(self: *Allocator, slice: anytype, new_n: usize) !@TypeOf(slice) {
        return self.vtable.reallocFn(self.ptr, slice, new_n);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        allocFn: fn (ptr: *anyopaque, comptime T: type, n: usize) anyerror![]T,
        freeFn: fn (ptr: *anyopaque, slice: anytype) void,
        reallocFn: fn (ptr: *anyopaque, slice: anytype, new_n: usize) anyerror!@TypeOf(slice),
    };
};

/// =======================
/// Core Memory Primitives
/// =======================

/// Copy `src.len` elements from `src` into `dst`. Panics if lengths mismatch.
pub fn copy(comptime T: type, dst: []T, src: []const T) void {
    if (dst.len != src.len)
        @panic("mem.copy: length mismatch");
    @memcpy(dst.ptr, src.ptr, dst.len * @sizeOf(T));
}

/// Move `src.len` elements into `dst`. Safe even if memory regions overlap.
pub fn move(comptime T: type, dst: []T, src: []T) void {
    if (dst.len != src.len)
        @panic("mem.move: length mismatch");
    @memmove(dst.ptr, src.ptr, dst.len * @sizeOf(T));
}

/// Compare two slices for equality.
pub fn eql(comptime T: type, a: []const T, b: []const T) bool {
    if (a.len != b.len) return false;
    return @memcmp(a.ptr, b.ptr, a.len * @sizeOf(T)) == 0;
}

/// Zero out all elements in a slice.
pub fn zeroes(comptime T: type, slice: []T) void {
    @memset(slice.ptr, 0, slice.len * @sizeOf(T));
}
```

## 🧪 Tests

```zig
test "mem.copy copies slices" {
    var src = [_]u8{1, 2, 3};
    var dst = [_]u8{0, 0, 0};
    copy(u8, &dst, &src);
    try std.testing.expect(eql(u8, &src, &dst));
}

test "mem.move handles overlap" {
    var buf = [_]u8{1, 2, 3, 4, 5};
    const src = buf[0..3]; // 1,2,3
    const dst = buf[1..4]; // overlap region
    move(u8, dst, src);
    try std.testing.expectEqualSlices(u8, &[_]u8{1, 1, 2, 3}, buf[0..4]);
}

test "mem.eql detects equality" {
    const a = [_]u8{1, 2, 3};
    const b = [_]u8{1, 2, 3};
    const c = [_]u8{1, 2, 4};
    try std.testing.expect(eql(u8, &a, &b));
    try std.testing.expect(!eql(u8, &a, &c));
}

test "mem.zeroes clears memory" {
    var buf = [_]u8{1, 2, 3};
    zeroes(u8, &buf);
    try std.testing.expectEqualSlices(u8, &[_]u8{0, 0, 0}, &buf);
}
```

## ⚔️ Doctrinal Integrity

- **Allocator is canonical**: explicit, passed everywhere, no hidden mallocs.
- **Raw primitives** (`copy`, `move`, `eql`, `zeroes`) are brutally honest, map to machine instructions.
- **Laws of physics**: you see every allocation, every free, every movement of bytes.
- **Alignment with Odin/Zig**: memory as finite, explicit resource. No GC lies, no managed fog.
