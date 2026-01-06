<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





<!--
---
title: "SPEC - Low-Level Memory Toolkit"
description: "Alignment, pointer, and raw byte primitives for std.mem."
author: Self Sovereign Society Foundation
date: 2025-09-24
license: |
  
  // Copyright (c) 2026 Self Sovereign Society Foundation
  // The full text of the license can be found in the LICENSE file at the root of the repository.
version: 0.1
---
-->

# 📜 SPEC – Low-Level Memory Toolkit

This specification outlines the foundational, low-level memory utilities that complement `std.mem`. It provides the tools for direct memory manipulation, alignment control, and a high-performance `ArenaAllocator`.

## 1. Alignment & Pointer Utilities

These are the tools for commanding memory layout.

### Functions

- `pub fn alignUp(comptime T: type, value: T, alignment: T) T`
  Rounds a value up to the nearest multiple of a given alignment.

- `pub fn alignDown(comptime T: type, value: T, alignment: T) T`
  Rounds a value down to the nearest multiple of a given alignment.

- `pub fn isAligned(comptime T: type, value: T, alignment: T) bool`
  Checks if a value is a multiple of a given alignment.

- `pub fn ptrCast(comptime DestType: type, ptr: anytype) DestType`
  Casts a pointer from one type to another.

## 2. Raw Byte Primitives

Untyped variants of the core primitives that operate on `[]u8` slices.

### Functions

- `pub fn copyBytes(dst: []u8, src: []const u8)`
  Copies bytes from `src` to `dst`. Panics if lengths mismatch.

- `pub fn eqlBytes(a: []const u8, b: []const u8) bool`
  Compares two byte slices for equality.

## 3. The Arena Allocator

A high-performance allocator for temporary allocations.

### Struct

`pub const ArenaAllocator = struct { ... };`

### Methods

- `pub fn init(backing_buffer: []u8) ArenaAllocator`
  Initializes an arena allocator with a fixed-size backing buffer.

- `pub fn allocator(self: *ArenaAllocator) *std.mem.Allocator`
  Returns a standard `Allocator` interface for the arena.

- `pub fn deinit(self: *ArenaAllocator)`
  Resets the arena, invalidating all allocations.
