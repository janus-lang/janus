// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Memory Management Tests - The First Battle Standard
//!
//! These tests enforce RFC-0002 Allocator Model and SPEC-ownership-boundary.
//! They plant the flag and force the implementation to march toward it.
//!
//! Built under the Atomic Forge Protocol - every test is a failing mold first.

const std = @import("std");
const testing = std.testing;

// This import will fail until janus.mem is implemented
const janus_mem = @import("janus_mem");

// SpyAllocator - Records allocator calls to verify Buffer behavior
const SpyAllocator = struct {
    // The real allocator we will forward calls to
    real_alloc: std.mem.Allocator,

    // State for recording calls
    last_alloc_align: u29 = 0,
    last_alloc_size: usize = 0,
    last_freed_slice: []u8 = &[_]u8{},
    last_allocated_slice: []u8 = &[_]u8{},

    pub fn allocator(self: *SpyAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
        .remap = std.mem.Allocator.noRemap,
    };

    fn alloc(ptr: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *SpyAllocator = @ptrCast(@alignCast(ptr));

        // Record the allocation parameters
        self.last_alloc_size = len;
        self.last_alloc_align = @as(u29, 1) << @truncate(@intFromEnum(ptr_align));

        // Forward to real allocator
        const result = self.real_alloc.vtable.alloc(self.real_alloc.ptr, len, ptr_align, ret_addr);
        if (result) |slice_ptr| {
            // Record the allocated slice
            self.last_allocated_slice = slice_ptr[0..len];
        }
        return result;
    }

    fn resize(ptr: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *SpyAllocator = @ptrCast(@alignCast(ptr));
        return self.real_alloc.vtable.resize(self.real_alloc.ptr, buf, buf_align, new_len, ret_addr);
    }

    fn free(ptr: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *SpyAllocator = @ptrCast(@alignCast(ptr));

        // Record the freed slice
        self.last_freed_slice = buf;

        // Forward to real allocator
        self.real_alloc.vtable.free(self.real_alloc.ptr, buf, buf_align, ret_addr);
    }
};

test "global allocator must exist and conform to the Allocator trait" {
    // SPECIFICATION: RFC-0002 Section 3 - Default Global Allocator
    // The global allocator must be accessible via janus.mem.global()
    const global_alloc = janus_mem.global();

    // SPECIFICATION: RFC-0002 Section 4 - The Allocator Trait
    // The returned Allocator must have a valid vtable
    try testing.expect(@intFromPtr(global_alloc.vtable) != 0);

    // SPECIFICATION: All three core functions must be present
    try testing.expect(@intFromPtr(global_alloc.vtable.allocate) != 0);
    try testing.expect(@intFromPtr(global_alloc.vtable.reallocate) != 0);
    try testing.expect(@intFromPtr(global_alloc.vtable.deallocate) != 0);
    try testing.expect(@intFromPtr(global_alloc.vtable.caps) != 0);

    // SPECIFICATION: Global allocator must be thread-safe
    const caps = global_alloc.vtable.caps(global_alloc.ctx);
    try testing.expect(caps.thread_safe == true);
}

test "Buffer.init must allocate and store ownership correctly" {
    // SPECIFICATION: SPEC-std-mem Section 1.1 - Buffer type
    // Buffer must store allocator provenance and layout
    var spy = SpyAllocator{ .real_alloc = std.heap.c_allocator };
    const spy_alloc = spy.allocator();

    // Create Buffer with SpyAllocator
    var spy_alloc_mut = spy_alloc;
    var buf = try janus_mem.Buffer.init(&spy_alloc_mut, 128, 8);
    defer buf.deinit();

    // SPECIFICATION: Buffer must store the allocator pointer
    try testing.expect(buf.alloc == &spy_alloc_mut);

    // SPECIFICATION: Buffer must store correct layout
    try testing.expectEqual(@as(usize, 128), buf.layout.size);
    try testing.expectEqual(@as(u32, 8), buf.layout.alignment);

    // SPECIFICATION: SpyAllocator must record correct alignment
    try testing.expectEqual(@as(u29, 8), spy.last_alloc_align);
    try testing.expectEqual(@as(usize, 128), spy.last_alloc_size);

    // SPECIFICATION: Buffer slice view must match allocation size
    const slice = buf.asSlice();
    try testing.expectEqual(@as(usize, 128), slice.len);
    try testing.expectEqual(@as(usize, 128), buf.len());

    // SPECIFICATION: Memory must be writable
    slice[0] = 0x42;
    slice[127] = 0xFF;
    try testing.expectEqual(@as(u8, 0x42), slice[0]);
    try testing.expectEqual(@as(u8, 0xFF), slice[127]);
}

test "Buffer.deinit must release allocation correctly" {
    // SPECIFICATION: SPEC-ownership-boundary - Ownership is absolute
    // Only the correct allocator may free the memory
    var spy = SpyAllocator{ .real_alloc = std.heap.c_allocator };
    const spy_alloc = spy.allocator();

    {
        var spy_alloc_mut = spy_alloc;
        var buf = try janus_mem.Buffer.init(&spy_alloc_mut, 256, 16);

        // Use the buffer to ensure it's valid
        const slice = buf.asSlice();
        slice[0] = 0xAA;
        try testing.expectEqual(@as(u8, 0xAA), slice[0]);

        // SPECIFICATION: SpyAllocator must record correct allocation parameters
        try testing.expectEqual(@as(u29, 16), spy.last_alloc_align);
        try testing.expectEqual(@as(usize, 256), spy.last_alloc_size);

        // Store the allocated slice for comparison
        const allocated_slice = spy.last_allocated_slice;

        // Call deinit and then verify the freed slice matches the allocated slice
        buf.deinit();

        // SPECIFICATION: The freed slice must be identical to the allocated slice
        try testing.expectEqual(allocated_slice.ptr, spy.last_freed_slice.ptr);
        try testing.expectEqual(allocated_slice.len, spy.last_freed_slice.len);
    }
}

// OwnedSlice test temporarily removed - struct was deleted per mandate
// test "OwnedSlice must preserve ownership across boundaries" {
//     // SPECIFICATION: SPEC-std-mem Section 1.2 - OwnedSlice type
//     // OwnedSlice must carry deallocator for boundary crossing
//     var gpa = std.testing.allocator;
//
//     // Create buffer and convert to OwnedSlice
//     const buf = try janus_mem.Buffer.init(&gpa, 64, 4);
//     var owned_slice = janus_mem.OwnedSlice.fromBuffer(buf);
//     defer owned_slice.deinit();
//
//     // SPECIFICATION: OwnedSlice must provide slice view
//     const slice = owned_slice.asSlice();
//     try testing.expectEqual(@as(usize, 64), slice.len);
//     try testing.expectEqual(@as(usize, 64), owned_slice.len);
//     slice[0] = 0xBB;
//     slice[63] = 0xCC;
//     try testing.expectEqual(@as(u8, 0xBB), slice[0]);
//     try testing.expectEqual(@as(u8, 0xCC), slice[63]);
// }

test "Allocator trait must support basic allocation lifecycle" {
    // SPECIFICATION: RFC-0002 Section 4.1 - Allocator semantics
    // Test the core allocate/deallocate cycle
    const global_alloc = janus_mem.global();

    const layout = janus_mem.Layout{ .size = 1024, .alignment = 8 };
    const flags = janus_mem.AllocFlags{ .zeroed = false };

    // SPECIFICATION: allocate must return aligned, valid memory
    const ptr = try global_alloc.vtable.allocate(global_alloc.ctx, layout, flags);
    defer global_alloc.vtable.deallocate(global_alloc.ctx, ptr, layout);

    // SPECIFICATION: Memory must be writable for full size
    ptr[0] = 0xDE;
    ptr[1023] = 0xAD;
    try testing.expectEqual(@as(u8, 0xDE), ptr[0]);
    try testing.expectEqual(@as(u8, 0xAD), ptr[1023]);

    // SPECIFICATION: Pointer must be properly aligned
    const addr = @intFromPtr(ptr);
    try testing.expectEqual(@as(usize, 0), addr % layout.alignment);
}

test "Allocator trait must honor zeroed flag" {
    // SPECIFICATION: RFC-0002 Section 4.1 - zeroed flag semantics
    const global_alloc = janus_mem.global();

    const layout = janus_mem.Layout{ .size = 512, .alignment = 8 };
    const flags = janus_mem.AllocFlags{ .zeroed = true };

    // SPECIFICATION: zeroed=true must guarantee zero-initialized memory
    const ptr = try global_alloc.vtable.allocate(global_alloc.ctx, layout, flags);
    defer global_alloc.vtable.deallocate(global_alloc.ctx, ptr, layout);

    // SPECIFICATION: All bytes must be zero
    for (0..layout.size) |i| {
        try testing.expectEqual(@as(u8, 0), ptr[i]);
    }
}

test "Allocator trait must support reallocate operations" {
    // SPECIFICATION: RFC-0002 Section 4.1 - reallocate semantics
    const global_alloc = janus_mem.global();

    const old_layout = janus_mem.Layout{ .size = 128, .alignment = 8 };
    const new_layout = janus_mem.Layout{ .size = 256, .alignment = 8 };
    const alloc_flags = janus_mem.AllocFlags{ .zeroed = false };
    const realloc_flags = janus_mem.ReallocFlags{ .move_ok = true, .zero_tail = false };

    // SPECIFICATION: Initial allocation
    var ptr = try global_alloc.vtable.allocate(global_alloc.ctx, old_layout, alloc_flags);

    // Write test pattern to original memory
    ptr[0] = 0xAA;
    ptr[127] = 0xBB;

    // SPECIFICATION: reallocate must preserve existing data
    ptr = try global_alloc.vtable.reallocate(global_alloc.ctx, ptr, old_layout, new_layout, realloc_flags);
    defer global_alloc.vtable.deallocate(global_alloc.ctx, ptr, new_layout);

    // SPECIFICATION: Original data must be preserved
    try testing.expectEqual(@as(u8, 0xAA), ptr[0]);
    try testing.expectEqual(@as(u8, 0xBB), ptr[127]);

    // SPECIFICATION: New memory must be accessible
    ptr[255] = 0xCC;
    try testing.expectEqual(@as(u8, 0xCC), ptr[255]);
}
