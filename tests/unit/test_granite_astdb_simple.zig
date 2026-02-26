// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("compiler/libjanus/astdb.zig");

test "Simple ASTDB with Granite Interner Test" {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Test basic ASTDB initialization
    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    // Test string interning
    const hello_id = try astdb_system.str_interner.get("hello");
    const world_id = try astdb_system.str_interner.get("world");
    const hello_id2 = try astdb_system.str_interner.get("hello");

    // Verify deduplication
    try testing.expectEqual(hello_id, hello_id2);
    try testing.expect(!std.meta.eql(hello_id, world_id));

    // Verify retrieval
    try testing.expectEqualStrings("hello", astdb_system.str_interner.str(hello_id));
    try testing.expectEqualStrings("world", astdb_system.str_interner.str(world_id));


    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .ok) {
    } else {
        try testing.expect(false);
    }
}
