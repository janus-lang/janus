// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    // Try to import ASTDB
    const astdb = @import("compiler/libjanus/astdb.zig");

    // Initialize ASTDB system
    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    // Test string interning
    const hello_str = try astdb_system.str_interner.get("hello");
    const hello_str2 = try astdb_system.str_interner.get("hello");

    if (hello_str == hello_str2) {
    } else {
    }

}
