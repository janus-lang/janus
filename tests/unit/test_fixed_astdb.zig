// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

/// 🔧 TESTING FIXED ASTDB SYSTEM
/// Validate that memory leak fixes work in the real ASTDB system

test "Fixed ASTDB System - Memory Leak Validation" {
    std.debug.print("\n🔧 FIXED ASTDB SYSTEM - MEMORY LEAK VALIDATION\n", .{});
    std.debug.print("==============================================\n", .{});

    const allocator = std.testing.allocator;

    std.debug.print("📋 Testing fixed ASTDB system with stress load\n", .{});

    const astdb = @import("compiler/libjanus/astdb.zig");

    // Test multiple cycles to ensure no accumulating leaks
    for (0..10) |cycle| {
        std.debug.print("🔄 Cycle {d}/10\n", .{cycle + 1});

        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        // Stress test string interning
        for (0..100) |i| {
            var buffer: [64]u8 = undefined;
            const test_str = std.fmt.bufPrint(&buffer, "cycle_{d}_string_{d}", .{ cycle, i }) catch unreachable;
            _ = try astdb_system.str_interner.get(test_str);
        }

        // Test CID cache operations
        const stats = astdb_system.getStats();
        std.debug.print("   📊 Strings: {d}, CIDs: {d}\n", .{ stats.interned_strings, stats.cached_cids });
    }

    std.debug.print("✅ ASTDB system stress test completed\n", .{});
    std.debug.print("🎯 If this test shows zero leaks, ASTDB memory management is HARDENED\n", .{});
}
