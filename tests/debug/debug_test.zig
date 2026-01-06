// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

test "Debug Test - Force Output" {
    std.debug.print("🔍 DEBUG TEST RUNNING\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arena_allocator = arena.allocator();
        const duped = try arena_allocator.dupe(u8, "hello");
        _ = duped;

        std.debug.print("✅ Arena dupe completed\n", .{});
    }

    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("❌ MEMORY LEAK DETECTED\n", .{});
        return error.MemoryLeak;
    }

    std.debug.print("✅ NO LEAKS DETECTED\n", .{});
}
