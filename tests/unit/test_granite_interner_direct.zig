// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const granite_interner = @import("compiler/libjanus/astdb/granite_interner.zig");

test "Direct Granite Interner Test" {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Test granite interner directly
    var interner = try granite_interner.StrInterner.init(allocator, true);
    defer interner.deinit();

    // Test string interning
    const hello_id = try interner.get("hello");
    const world_id = try interner.get("world");
    const hello_id2 = try interner.get("hello");

    // Verify deduplication
    try testing.expectEqual(hello_id, hello_id2);
    try testing.expect(!std.meta.eql(hello_id, world_id));

    // Verify retrieval
    try testing.expectEqualStrings("hello", interner.str(hello_id));
    try testing.expectEqualStrings("world", interner.str(world_id));


    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .ok) {
    } else {
        try testing.expect(false);
    }
}
