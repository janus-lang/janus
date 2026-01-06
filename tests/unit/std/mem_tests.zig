// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

const mem = @import("janus/mem.zig"); // placeholder import for janus.mem package

test "Buffer.init and Buffer.deinit basic lifecycle" {
    // Use a testing allocator to verify allocations & frees
    var gpa = std.testing.allocator;

    // Attempt to allocate a Buffer of 128 bytes with 8-byte alignment
    var buf = try mem.Buffer.init(&gpa, 128, 8);

    // Verify allocator is captured correctly
    try testing.expectEqual(&gpa, buf.alloc);

    // Verify layout correctness
    try testing.expectEqual(@as(usize, 128), buf.layout.size);
    try testing.expectEqual(@as(u32, 8), buf.layout.align);

    // Verify slice length matches size
    const slice = buf.asSlice();
    try testing.expectEqual(@as(usize, 128), slice.len);

    // Clean up (frees via captured allocator)
    buf.deinit();

    // Allocator should now report zero outstanding allocations
    try testing.expectEqual(@as(usize, 0), gpa.deallocCount());
}
