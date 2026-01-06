// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("compiler/libjanus/astdb.zig");

test "Simple ASTDB with Granite Interner Test" {
    std.debug.print("\n🔧 SIMPLE ASTDB WITH GRANITE INTERNER TEST\n", .{});

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

    std.debug.print("✅ ASTDB with granite interner works\n", .{});

    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .ok) {
        std.debug.print("🎉 ZERO MEMORY LEAKS WITH GRANITE INTERNER\n", .{});
    } else {
        std.debug.print("❌ MEMORY LEAKS STILL DETECTED\n", .{});
        try testing.expect(false);
    }
}
