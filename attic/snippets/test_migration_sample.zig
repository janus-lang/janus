// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

const std = @import("std");

pub fn sampleFunction(alloc: std.mem.Allocator) !void {
    // This pattern should be migrated
    var out = List(u8).with(alloc);

    defer out.deinit();

    try out.append(42);
    try out.append(43);
    const s = try out.toOwnedSlice();
    defer alloc.free(s);

    // This should NOT be migrated (no defer pattern)
    var temp = std.ArrayList(u8){};
    try temp.append(alloc, 1);

    std.debug.print("Result: {s}\n", .{s});
}
