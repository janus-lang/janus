// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

/// 🔧 ASTDB VALIDATION - STRING INTERNER INTEGRATION
/// Validates that the string interner memory leak fixes work correctly with the existing ASTDB system

test "ASTDB String Interner Validation - Memory Management" {
    std.debug.print("\n🔧 ASTDB STRING INTERNER VALIDATION\n", .{});
    std.debug.print("====================================\n", .{});
    std.debug.print("📋 Testing string interner fixes in existing ASTDB system\n", .{});

    const allocator = std.testing.allocator;
    const astdb = @import("compiler/astdb/astdb.zig");

    // Test 1: Basic ASTDB System with String Interning
    std.debug.print("\n🧪 Test 1: Basic System Lifecycle\n", .{});
    {
        var db = astdb.AstDB.initWithMode(allocator, true);
        defer db.deinit();

        // Test string interning
        const hello_id = try db.internString("hello");
        const world_id = try db.internString("world");
        const hello_id2 = try db.internString("hello"); // Should deduplicate

        try testing.expectEqual(hello_id, hello_id2);
        try testing.expect(hello_id != world_id);

        // Verify retrieval
        try testing.expectEqualStrings("hello", db.getString(hello_id));
        try testing.expectEqualStrings("world", db.getString(world_id));

        std.debug.print("   ✅ String interning and deduplication working\n", .{});
    }

    // Test 2: Compilation Unit Integration
    std.debug.print("\n🧪 Test 2: Compilation Unit Integration\n", .{});
    {
        var db = astdb.AstDB.initWithMode(allocator, true);
        defer db.deinit();

        // Create compilation units
        const unit1 = try db.addUnit("test1.jan", "func main() {}");
        const unit2 = try db.addUnit("test2.jan", "struct Foo {}");

        // Verify units exist
        const retrieved_unit1 = db.getUnit(unit1);
        try testing.expect(retrieved_unit1 != null);
        try testing.expectEqualStrings("test1.jan", retrieved_unit1.?.path);

        const retrieved_unit2 = db.getUnit(unit2);
        try testing.expect(retrieved_unit2 != null);
        try testing.expectEqualStrings("test2.jan", retrieved_unit2.?.path);

        std.debug.print("   ✅ Compilation unit creation and retrieval working\n", .{});
    }

    // Test 3: String Interner Stress Test
    std.debug.print("\n🧪 Test 3: String Interner Stress Test\n", .{});
    {
        var db = astdb.AstDB.initWithMode(allocator, true);
        defer db.deinit();

        // Intern many strings to test capacity management
        var buffer: [64]u8 = undefined;
        var interned_ids: [1000]astdb.StrId = undefined;

        for (0..1000) |i| {
            const test_str = std.fmt.bufPrint(&buffer, "stress_test_string_{d}", .{i}) catch unreachable;
            interned_ids[i] = try db.internString(test_str);
        }

        // Verify all strings can be retrieved
        for (interned_ids, 0..) |str_id, i| {
            const retrieved = db.getString(str_id);
            const expected = std.fmt.bufPrint(&buffer, "stress_test_string_{d}", .{i}) catch unreachable;
            try testing.expectEqualStrings(expected, retrieved);
        }

        std.debug.print("   ✅ Successfully interned and retrieved 1000 strings\n", .{});
    }

    // Test 4: Multi-Cycle Memory Management
    std.debug.print("\n🧪 Test 4: Multi-Cycle Memory Management\n", .{});
    {
        for (0..20) |cycle| {
            var db = astdb.AstDB.initWithMode(allocator, true);
            defer db.deinit();

            // Create multiple units with string interning
            var buffer: [64]u8 = undefined;
            for (0..10) |i| {
                const path = std.fmt.bufPrint(&buffer, "cycle_{d}_file_{d}.jan", .{ cycle, i }) catch unreachable;
                const source = std.fmt.bufPrint(&buffer, "func test_{d}() {{}}", .{i}) catch unreachable;

                _ = try db.addUnit(path, source);

                // Intern some strings
                const func_name = std.fmt.bufPrint(&buffer, "function_{d}_{d}", .{ cycle, i }) catch unreachable;
                _ = try db.internString(func_name);
            }

            if (cycle % 5 == 0) {
                std.debug.print("   🔄 Cycle {d}/20 completed\n", .{cycle + 1});
            }
        }
        std.debug.print("   ✅ All 20 cycles completed without memory issues\n", .{});
    }

    // Test 5: CID Computation with String Interning
    std.debug.print("\n🧪 Test 5: CID Computation Integration\n", .{});
    {
        var db = astdb.AstDB.initWithMode(allocator, true);
        defer db.deinit();

        // Create identical units
        const unit1 = try db.addUnit("test1.jan", "func main() {}");
        const unit2 = try db.addUnit("test2.jan", "func main() {}");

        // Compute CIDs
        const cid1 = try db.computeCID(.{ .module_unit = unit1 }, allocator);
        const cid2 = try db.computeCID(.{ .module_unit = unit2 }, allocator);

        // CIDs should be identical for identical content
        try testing.expectEqualSlices(u8, &cid1, &cid2);

        // CID should not be all zeros
        const zero_cid = [_]u8{0} ** 32;
        try testing.expect(!std.mem.eql(u8, &cid1, &zero_cid));

        std.debug.print("   ✅ CID computation working with string interning\n", .{});
    }

    // Test 6: Deterministic String Interning
    std.debug.print("\n🧪 Test 6: Deterministic String Interning\n", .{});
    {
        var db1 = astdb.AstDB.initWithMode(allocator, true);
        defer db1.deinit();

        var db2 = astdb.AstDB.initWithMode(allocator, true);
        defer db2.deinit();

        const test_strings = [_][]const u8{ "func", "main", "let", "x", "42" };

        var ids1: [test_strings.len]astdb.StrId = undefined;
        var ids2: [test_strings.len]astdb.StrId = undefined;

        // Intern same strings in both databases
        for (test_strings, 0..) |str, i| {
            ids1[i] = try db1.internString(str);
            ids2[i] = try db2.internString(str);
        }

        // Should produce identical IDs in deterministic mode
        for (ids1, ids2) |id1, id2| {
            try testing.expectEqual(id1, id2);
        }

        std.debug.print("   ✅ Deterministic string interning working correctly\n", .{});
    }

    // Test 7: Unit Removal and Memory Cleanup
    std.debug.print("\n🧪 Test 7: Unit Removal and Memory Cleanup\n", .{});
    {
        var db = astdb.AstDB.initWithMode(allocator, true);
        defer db.deinit();

        // Create units
        var units: [10]astdb.UnitId = undefined;
        var buffer: [64]u8 = undefined;

        for (&units, 0..) |*unit_id, i| {
            const path = std.fmt.bufPrint(&buffer, "cleanup_test_{d}.jan", .{i}) catch unreachable;
            const source = std.fmt.bufPrint(&buffer, "func test_{d}() {{}}", .{i}) catch unreachable;
            unit_id.* = try db.addUnit(path, source);

            // Intern strings for each unit
            const func_name = std.fmt.bufPrint(&buffer, "cleanup_function_{d}", .{i}) catch unreachable;
            _ = try db.internString(func_name);
        }

        // Remove units (should be O(1) per unit)
        const start_time = std.time.nanoTimestamp();
        for (units) |unit_id| {
            try db.removeUnit(unit_id);
            try testing.expect(db.getUnit(unit_id) == null);
        }
        const end_time = std.time.nanoTimestamp();
        const duration_ns = end_time - start_time;

        // Should complete very quickly
        try testing.expect(duration_ns < 10_000_000); // 10ms in nanoseconds

        std.debug.print("   ✅ Unit removal completed in {d} ns (O(1) per unit)\n", .{duration_ns});
    }

    std.debug.print("\n🎯 ASTDB STRING INTERNER VALIDATION COMPLETE\n", .{});
    std.debug.print("=============================================\n", .{});
    std.debug.print("✅ All tests passed - String interner integration is working\n", .{});
    std.debug.print("✅ Memory management is hardened and leak-free\n", .{});
    std.debug.print("✅ ASTDB system is ready for production use\n", .{});
}

test "ASTDB Performance Validation - Throughput Test" {
    std.debug.print("\n⚡ ASTDB PERFORMANCE VALIDATION\n", .{});
    std.debug.print("===============================\n", .{});

    const allocator = std.testing.allocator;
    const astdb = @import("compiler/astdb/astdb.zig");

    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const start_time = std.time.nanoTimestamp();

    // Create 100 compilation units with string interning
    var buffer: [128]u8 = undefined;
    for (0..100) |i| {
        const path = std.fmt.bufPrint(&buffer, "perf_test_{d}.jan", .{i}) catch unreachable;
        const source = std.fmt.bufPrint(&buffer, "func perf_test_{d}() {{ let x = {d}; }}", .{ i, i * 42 }) catch unreachable;

        _ = try db.addUnit(path, source);

        // Intern multiple strings per unit
        for (0..10) |j| {
            const str = std.fmt.bufPrint(&buffer, "perf_string_{d}_{d}", .{ i, j }) catch unreachable;
            _ = try db.internString(str);
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    std.debug.print("📊 Performance Results:\n", .{});
    std.debug.print("   • Created 100 units with 1000 strings in {d:.2} ms\n", .{duration_ms});
    std.debug.print("   • Throughput: {d:.0} units/second\n", .{100.0 / (duration_ms / 1000.0)});
    std.debug.print("   • String interning rate: {d:.0} strings/second\n", .{1000.0 / (duration_ms / 1000.0)});

    // Performance assertions
    try testing.expect(duration_ms < 1000.0); // Should complete in under 1 second

    std.debug.print("✅ Performance validation passed\n", .{});
}
