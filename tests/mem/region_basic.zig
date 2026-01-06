// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

const std = @import("std");
const region = @import("mem/region.zig");

test "region alloc frees on scope exit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    try region.withRegion(A, struct {
        fn run(a: std.mem.Allocator) !void {
            var list = std.ArrayList(u8){};
            defer list.deinit(a);
            try list.append(a, 1);
            try list.append(a, 2);
        }
    }.run);
}
