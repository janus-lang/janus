// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

test "Minimal Arena Test - Understanding the Leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arena_allocator = arena.allocator();
        _ = try arena_allocator.alloc(u8, 100);
    }

    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("❌ MEMORY LEAK DETECTED IN MINIMAL ARENA TEST\n", .{});
        return error.MemoryLeak;
    }

    std.debug.print("✅ MINIMAL ARENA TEST PASSED - NO LEAKS\n", .{});
}

test "Even More Minimal Test - Just GPA" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        const memory = try allocator.alloc(u8, 100);
        defer allocator.free(memory);
    }

    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("❌ MEMORY LEAK DETECTED IN MINIMAL GPA TEST\n", .{});
        return error.MemoryLeak;
    }

    std.debug.print("✅ MINIMAL GPA TEST PASSED - NO LEAKS\n", .{});
}
