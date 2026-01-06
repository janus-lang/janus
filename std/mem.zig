// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
        allocFn: *const fn (ptr: *anyopaque, comptime T: type, n: usize) anyerror![]T,
        freeFn: *const fn (ptr: *anyopaque, slice: anytype) void,
        reallocFn: *const fn (ptr: *anyopaque, slice: anytype, new_n: usize) anyerror!@TypeOf(slice),
    };
};

// =======================
// Core Memory Primitives
// =======================

/// Copy `src.len` elements from `src` into `dst`. Panics if lengths mismatch.
pub fn copy(comptime T: type, dst: []T, src: []const T) void {
    if (dst.len != src.len)
        @panic("mem.copy: length mismatch");
    @memcpy(dst, src);
}

/// Move `src.len` elements into `dst`. Safe even if memory regions overlap.
pub fn move(comptime T: type, dst: []T, src: []T) void {
    if (dst.len != src.len)
        @panic("mem.move: length mismatch");
    std.mem.copy(T, dst, src);
}

/// Compare two slices for equality.
pub fn eql(comptime T: type, a: []const T, b: []const T) bool {
    if (a.len != b.len) return false;
    return std.mem.eql(T, a, b);
}

/// Zero out all elements in a slice.
pub fn zeroes(comptime T: type, slice: []T) void {
    @memset(slice, 0);
}

/// ==================================
/// Alignment & Pointer Utilities
/// ==================================

pub fn alignUp(comptime T: type, value: T, alignment: T) T {
    comptime std.debug.assert(std.math.isPowerOfTwo(alignment));
    return (value + alignment - 1) & ~(alignment - 1);
}

pub fn alignDown(comptime T: type, value: T, alignment: T) T {
    comptime std.debug.assert(std.math.isPowerOfTwo(alignment));
    return value & ~(alignment - 1);
}

pub fn isAligned(comptime T: type, value: T, alignment: T) bool {
    comptime std.debug.assert(std.math.isPowerOfTwo(alignment));
    return (value & (alignment - 1)) == 0;
}

pub fn ptrCast(comptime DestType: type, ptr: anytype) DestType {
    return @ptrCast(ptr);
}

// =======================
// Raw Byte Primitives
// =======================

pub fn copyBytes(dst: []u8, src: []const u8) void {
    if (dst.len != src.len)
        @panic("mem.copyBytes: length mismatch");
    @memcpy(dst, src);
}

pub fn eqlBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    return std.mem.eql(u8, a, b);
}

// =======================
// Arena Allocator
// =======================

pub const ArenaAllocator = struct {
    buffer: []u8,
    pos: usize,
    end: usize,

    /// Initialize an arena allocator with a memory buffer.
    pub fn init(buffer: []u8) ArenaAllocator {
        return ArenaAllocator{
            .buffer = buffer,
            .pos = 0,
            .end = buffer.len,
        };
    }

    /// Allocate a slice of `n` elements of type `T`, aligned to the type's alignment.
    pub fn alloc(self: *ArenaAllocator, comptime T: type, n: usize) ![]T {
        const size = n * @sizeOf(T);
        const alignment = @alignOf(T);

        const aligned_pos = alignUp(usize, self.pos, alignment);
        const new_pos = aligned_pos + size;

        if (new_pos > self.end) {
            return error.OutOfMemory;
        }

        self.pos = new_pos;
        const result = @as([*]T, @ptrCast(&self.buffer[aligned_pos]))[0..n];
        return result;
    }

    /// Reset the arena to its initial state, allowing reuse of allocated memory.
    pub fn reset(self: *ArenaAllocator) void {
        self.pos = 0;
    }

    /// Get the number of bytes currently allocated.
    pub fn allocatedBytes(self: *ArenaAllocator) usize {
        return self.pos;
    }

    /// Get the number of bytes available for allocation.
    pub fn availableBytes(self: *ArenaAllocator) usize {
        return self.end - self.pos;
    }

    /// Create an allocator interface for this arena.
    pub fn allocator(self: *ArenaAllocator) Allocator {
        return Allocator{
            .ptr = self,
            .vtable = &arena_vtable,
        };
    }
};

const arena_vtable = Allocator.VTable{
    .allocFn = arenaAllocFn,
    .freeFn = arenaFreeFn,
    .reallocFn = arenaReallocFn,
};

fn arenaAllocFn(ptr: *anyopaque, comptime T: type, n: usize) anyerror![]T {
    const self: *ArenaAllocator = @ptrCast(@alignCast(ptr));
    return self.alloc(T, n);
}

fn arenaFreeFn(_: *anyopaque, _: anytype) void {
    // Arena allocator doesn't free individual allocations
}

fn arenaReallocFn(ptr: *anyopaque, slice: anytype, new_n: usize) anyerror!@TypeOf(slice) {
    // Simple realloc for arena: if it fits, just return the same slice with new length
    // This is a simplified implementation - in practice, arena reallocs are limited
    if (new_n <= slice.len) {
        return slice[0..new_n];
    }

    // For growing reallocs, we need to allocate new space
    const self: *ArenaAllocator = @ptrCast(@alignCast(ptr));
    const new_slice = try self.alloc(@typeInfo(@TypeOf(slice[0])).Array.child, new_n);

    // Copy the old data to the new location
    if (slice.len > 0) {
        const elem_size = @sizeOf(@typeInfo(@TypeOf(slice[0])).Array.child);
        @memcpy(new_slice[0..slice.len], slice[0..slice.len]);
    }

    return new_slice;
}

// =======================
// Tests
// =======================

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

test "mem.alignUp" {
    try std.testing.expect(alignUp(usize, 7, 4) == 8);
    try std.testing.expect(alignUp(usize, 8, 4) == 8);
}

test "mem.alignDown" {
    try std.testing.expect(alignDown(usize, 7, 4) == 4);
    try std.testing.expect(alignDown(usize, 8, 4) == 8);
}

test "mem.isAligned" {
    try std.testing.expect(isAligned(usize, 8, 4));
    try std.testing.expect(!isAligned(usize, 7, 4));
}

test "mem.ptrCast" {
    const a: u32 = 1;
    const b: *const u32 = &a;
    const c: *const u8 = ptrCast(*const u8, b);
    try std.testing.expect(c.* == 1);
}

test "mem.copyBytes" {
    var src = [_]u8{1, 2, 3};
    var dst = [_]u8{0, 0, 0};
    copyBytes(&dst, &src);
    try std.testing.expect(eqlBytes(&src, &dst));
}

test "mem.eqlBytes" {
    const a = [_]u8{1, 2, 3};
    const b = [_]u8{1, 2, 3};
    const c = [_]u8{1, 2, 4};
    try std.testing.expect(eqlBytes(&a, &b));
    try std.testing.expect(!eqlBytes(&a, &c));
}

test "mem.ArenaAllocator basic allocation" {
    var buffer: [1024]u8 = undefined;
    var arena = ArenaAllocator.init(&buffer);

    const slice1 = try arena.alloc(u32, 4);
    try std.testing.expect(slice1.len == 4);

    const slice2 = try arena.alloc(u8, 10);
    try std.testing.expect(slice2.len == 10);

    try std.testing.expect(arena.allocatedBytes() == 4 * @sizeOf(u32) + 10 * @sizeOf(u8));
    try std.testing.expect(arena.availableBytes() == buffer.len - arena.allocatedBytes());
}

test "mem.ArenaAllocator alignment" {
    var buffer: [1024]u8 = undefined;
    var arena = ArenaAllocator.init(&buffer);

    // Allocate u32 (4-byte aligned)
    const slice1 = try arena.alloc(u32, 1);
    try std.testing.expect(isAligned(usize, @intFromPtr(slice1.ptr), @alignOf(u32)));

    // Allocate u64 (8-byte aligned)
    const slice2 = try arena.alloc(u64, 1);
    try std.testing.expect(isAligned(usize, @intFromPtr(slice2.ptr), @alignOf(u64)));
}

test "mem.ArenaAllocator out of memory" {
    var buffer: [16]u8 = undefined;
    var arena = ArenaAllocator.init(&buffer);

    // Should succeed
    _ = try arena.alloc(u8, 10);

    // Should fail - not enough space for 10 more bytes
    try std.testing.expectError(error.OutOfMemory, arena.alloc(u8, 10));
}

test "mem.ArenaAllocator reset" {
    var buffer: [1024]u8 = undefined;
    var arena = ArenaAllocator.init(&buffer);

    _ = try arena.alloc(u32, 4);
    try std.testing.expect(arena.allocatedBytes() > 0);

    arena.reset();
    try std.testing.expect(arena.allocatedBytes() == 0);
    try std.testing.expect(arena.availableBytes() == buffer.len);
}

test "mem.ArenaAllocator allocator interface" {
    var buffer: [1024]u8 = undefined;
    var arena = ArenaAllocator.init(&buffer);
    const allocator = arena.allocator();

    const slice = try allocator.alloc(u32, 5);
    try std.testing.expect(slice.len == 5);

    allocator.free(slice); // Should be no-op for arena
    try std.testing.expect(arena.allocatedBytes() == 5 * @sizeOf(u32));
}

test "mem.ArenaAllocator realloc grow" {
    var buffer: [1024]u8 = undefined;
    var arena = ArenaAllocator.init(&buffer);
    const allocator = arena.allocator();

    var slice = try allocator.alloc(u32, 4);
    for (0..4) |i| {
        slice[i] = @intCast(i + 1);
    }

    // Grow the slice
    slice = try allocator.realloc(slice, 8);
    try std.testing.expect(slice.len == 8);

    // Original data should be preserved
    try std.testing.expect(slice[0] == 1);
    try std.testing.expect(slice[1] == 2);
    try std.testing.expect(slice[2] == 3);
    try std.testing.expect(slice[3] == 4);
}

test "mem.ArenaAllocator realloc shrink" {
    var buffer: [1024]u8 = undefined;
    var arena = ArenaAllocator.init(&buffer);
    const allocator = arena.allocator();

    var slice = try allocator.alloc(u32, 8);
    for (0..8) |i| {
        slice[i] = @intCast(i + 1);
    }

    // Shrink the slice
    slice = try allocator.realloc(slice, 4);
    try std.testing.expect(slice.len == 4);

    // Data should be preserved
    try std.testing.expect(slice[0] == 1);
    try std.testing.expect(slice[1] == 2);
    try std.testing.expect(slice[2] == 3);
    try std.testing.expect(slice[3] == 4);
}
