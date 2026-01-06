// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const List = @import("mem/ctx/List.zig").List;

test "List[T] context-bound operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var xs = List(u32).with(A);
    defer xs.deinit();

    try xs.append(1);
    try xs.append(2);
    const slice = try xs.toOwnedSlice();
    defer A.free(slice);

    try std.testing.expectEqual(@as(usize, 2), slice.len);
    try std.testing.expectEqual(@as(u32, 1), slice[0]);
}
