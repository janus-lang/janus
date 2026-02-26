// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// Use the correct import path from the working test
const astdb = @import("compiler/astdb/astdb.zig");

test "Working ASTDB Integration Test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    // Initialize ASTDB system
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();


    // Test string interning
    const hello_str = try db.str_interner.get("hello");
    const world_str = try db.str_interner.get("world");
    const hello_str2 = try db.str_interner.get("hello"); // Should deduplicate

    try testing.expectEqual(hello_str, hello_str2);


    // Get stats
    const stats = db.getStats();

}
