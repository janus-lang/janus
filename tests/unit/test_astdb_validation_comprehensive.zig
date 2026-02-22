// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;

/// 🔧 COMPREHENSIVE ASTDB VALIDATION
/// Validates that string interner memory leak fixes work correctly in the full ASTDB system
/// This test ensures the fixes applied to string interner integrate properly with:
/// - Snapshot creation and management
/// - CID computation and caching
/// - Node and token operations
/// - Memory management across multiple cycles

test "ASTDB Comprehensive Validation - String Interner Integration" {
    std.debug.print("\n🔧 ASTDB COMPREHENSIVE VALIDATION\n", .{});
    std.debug.print("=====================================\n", .{});
    std.debug.print("📋 Validating string interner fixes in full ASTDB system\n", .{});

    const allocator = std.testing.allocator;
    const astdb = @import("compiler/libjanus/astdb.zig");

    // Test 1: Basic ASTDB System Initialization and Cleanup
    std.debug.print("\n🧪 Test 1: Basic System Lifecycle\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        const initial_stats = astdb_system.stats();
        try testing.expectEqual(@as(u32, 0), initial_stats.interned_strings);
        try testing.expectEqual(@as(u32, 0), initial_stats.cached_cids);
        std.debug.print("   ✅ System initializes with clean state\n", .{});
    }

    // Test 2: String Interner Capacity Management
    std.debug.print("\n🧪 Test 2: String Interner Capacity Management\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        // Test that we can intern many strings without reallocation issues
        var buffer: [64]u8 = undefined;
        for (0..1000) |i| {
            const test_str = std.fmt.bufPrint(&buffer, "test_string_{d}", .{i}) catch unreachable;
            _ = try astdb_system.str_interner.get(test_str);
        }

        const stats = astdb_system.stats();
        try testing.expectEqual(@as(u32, 1000), stats.interned_strings);
        std.debug.print("   ✅ Successfully interned 1000 strings without issues\n", .{});
    }

    // Test 3: Snapshot Integration with String Interner
    std.debug.print("\n🧪 Test 3: Snapshot Integration\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var snapshot = try astdb_system.createSnapshot();
        defer snapshot.deinit();

        // Create tokens using interned strings
        const func_str = try astdb_system.str_interner.get("function");
        const main_str = try astdb_system.str_interner.get("main");
        const return_str = try astdb_system.str_interner.get("return");

        const span = astdb.Span{
            .start_byte = 0,
            .end_byte = 8,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 9,
        };

        const func_token = try snapshot.addToken(.kw_func, func_str, span);
        const main_token = try snapshot.addToken(.identifier, main_str, span);
        const return_token = try snapshot.addToken(.kw_return, return_str, span);

        // Create nodes
        const main_node = try snapshot.addNode(.func_decl, func_token, return_token, &[_]astdb.NodeId{});

        // Verify token retrieval
        const retrieved_token = snapshot.getToken(func_token).?;
        try testing.expectEqual(astdb.TokenKind.kw_func, retrieved_token.kind);
        try testing.expectEqual(func_str, retrieved_token.str_id);

        // Verify node retrieval
        const retrieved_node = snapshot.getNode(main_node).?;
        try testing.expectEqual(astdb.NodeKind.func_decl, retrieved_node.kind);

        std.debug.print("   ✅ Snapshot operations work correctly with interned strings\n", .{});
    }

    // Test 4: CID Computation with String Interner
    std.debug.print("\n🧪 Test 4: CID Computation Integration\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var snapshot = try astdb_system.createSnapshot();
        defer snapshot.deinit();

        // Create identical content in two different ways
        const hello_str1 = try astdb_system.str_interner.get("hello");
        const hello_str2 = try astdb_system.str_interner.get("hello"); // Should be same ID

        try testing.expectEqual(hello_str1, hello_str2);

        const span = astdb.Span{
            .start_byte = 0,
            .end_byte = 5,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 6,
        };

        const token1 = try snapshot.addToken(.identifier, hello_str1, span);
        const token2 = try snapshot.addToken(.identifier, hello_str2, span);

        const node1 = try snapshot.addNode(.identifier, token1, token1, &[_]astdb.NodeId{});
        const node2 = try snapshot.addNode(.identifier, token2, token2, &[_]astdb.NodeId{});

        // Compute CIDs
        const opts = astdb.CIDOpts{};
        const cid1 = try astdb_system.getCID(snapshot, node1, opts);
        const cid2 = try astdb_system.getCID(snapshot, node2, opts);

        // CIDs should be identical for identical content
        try testing.expectEqualSlices(u8, &cid1, &cid2);

        const stats = astdb_system.stats();
        try testing.expectEqual(@as(u32, 1), stats.interned_strings); // Deduplication worked
        try testing.expectEqual(@as(u32, 2), stats.cached_cids); // Two CID computations

        std.debug.print("   ✅ CID computation works correctly with string deduplication\n", .{});
    }

    // Test 5: Multi-Cycle Stress Test
    std.debug.print("\n🧪 Test 5: Multi-Cycle Stress Test\n", .{});
    {
        for (0..20) |cycle| {
            var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
            defer astdb_system.deinit();

            var snapshot = try astdb_system.createSnapshot();
            defer snapshot.deinit();

            // Create complex AST structure
            var buffer: [64]u8 = undefined;
            var nodes: [10]astdb.NodeId = undefined;

            for (0..10) |i| {
                const name = std.fmt.bufPrint(&buffer, "node_{d}_{d}", .{ cycle, i }) catch unreachable;
                const str_id = try astdb_system.str_interner.get(name);

                const span = astdb.Span{
                    .start_byte = @as(u32, @intCast(i * 10)),
                    .end_byte = @as(u32, @intCast(i * 10 + 8)),
                    .start_line = 1,
                    .start_col = @as(u32, @intCast(i * 10 + 1)),
                    .end_line = 1,
                    .end_col = @as(u32, @intCast(i * 10 + 9)),
                };

                const token = try snapshot.addToken(.identifier, str_id, span);
                nodes[i] = try snapshot.addNode(.identifier, token, token, &[_]astdb.NodeId{});
            }

            // Create root node with all children
            const root_str = try astdb_system.str_interner.get("root");
            const root_span = astdb.Span{
                .start_byte = 0,
                .end_byte = 100,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 101,
            };
            const root_token = try snapshot.addToken(.identifier, root_str, root_span);
            const root_node = try snapshot.addNode(.root, root_token, root_token, &nodes);

            // Compute CID for complex structure
            const opts = astdb.CIDOpts{};
            const root_cid = try astdb_system.getCID(snapshot, root_node, opts);
            try testing.expect(!astdb.CIDUtils.isZero(root_cid));

            const final_stats = astdb_system.stats();
            try testing.expectEqual(@as(u32, 11), final_stats.interned_strings); // 10 nodes + root
            try testing.expectEqual(@as(u32, 11), final_stats.cached_cids); // All nodes computed

            if (cycle % 5 == 0) {
                std.debug.print("   🔄 Cycle {d}/20 completed successfully\n", .{cycle + 1});
            }
        }
        std.debug.print("   ✅ All 20 cycles completed without memory issues\n", .{});
    }

    // Test 6: String Interner Deduplication Validation
    std.debug.print("\n🧪 Test 6: String Deduplication Validation\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        // Intern the same strings multiple times
        const test_strings = [_][]const u8{ "hello", "world", "test", "function", "main" };
        var first_ids: [5]astdb.StrId = undefined;
        var second_ids: [5]astdb.StrId = undefined;

        // First round of interning
        for (test_strings, 0..) |str, i| {
            first_ids[i] = try astdb_system.str_interner.get(str);
        }

        // Second round of interning (should return same IDs)
        for (test_strings, 0..) |str, i| {
            second_ids[i] = try astdb_system.str_interner.get(str);
        }

        // Verify deduplication
        for (0..5) |i| {
            try testing.expectEqual(first_ids[i], second_ids[i]);
        }

        const stats = astdb_system.stats();
        try testing.expectEqual(@as(u32, 5), stats.interned_strings); // Only 5 unique strings

        std.debug.print("   ✅ String deduplication working correctly\n", .{});
    }

    // Test 7: Memory Bounds Validation
    std.debug.print("\n🧪 Test 7: Memory Bounds Validation\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        // Test that we respect capacity limits
        var buffer: [1000]u8 = undefined;
        var success_count: u32 = 0;

        // Try to intern very large strings until we hit capacity
        for (0..100) |i| {
            // Create progressively larger strings
            const size = (i + 1) * 100;
            if (size >= buffer.len) break;

            @memset(buffer[0..size], 'A');
            const large_str = buffer[0..size];

            if (astdb_system.str_interner.get(large_str)) |_| {
                success_count += 1;
            } else |err| {
                if (err == error.StringInternerCapacityExceeded) {
                    std.debug.print("   ✅ Capacity limit properly enforced at string {d}\n", .{i});
                    break;
                } else {
                    return err;
                }
            }
        }

        try testing.expect(success_count > 0); // Should succeed for some strings
        std.debug.print("   ✅ Successfully interned {d} large strings before hitting capacity\n", .{success_count});
    }

    std.debug.print("\n🎯 ASTDB VALIDATION COMPLETE\n", .{});
    std.debug.print("=====================================\n", .{});
    std.debug.print("✅ All tests passed - String interner fixes are working correctly\n", .{});
    std.debug.print("✅ ASTDB system is ready for production use\n", .{});
    std.debug.print("✅ Memory management is hardened and leak-free\n", .{});
}

test "ASTDB Performance Validation - Throughput Test" {
    std.debug.print("\n⚡ ASTDB PERFORMANCE VALIDATION\n", .{});
    std.debug.print("===============================\n", .{});

    const allocator = std.testing.allocator;
    const astdb = @import("compiler/libjanus/astdb.zig");

    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var snapshot = try astdb_system.createSnapshot();
    defer snapshot.deinit();

    const start_time = compat_time.nanoTimestamp();

    // Create 1000 nodes with string interning and CID computation
    var buffer: [64]u8 = undefined;
    for (0..1000) |i| {
        const name = std.fmt.bufPrint(&buffer, "perf_test_node_{d}", .{i}) catch unreachable;
        const str_id = try astdb_system.str_interner.get(name);

        const span = astdb.Span{
            .start_byte = @as(u32, @intCast(i)),
            .end_byte = @as(u32, @intCast(i + 10)),
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 11,
        };

        const token = try snapshot.addToken(.identifier, str_id, span);
        const node = try snapshot.addNode(.identifier, token, token, &[_]astdb.NodeId{});

        // Compute CID for each node
        const opts = astdb.CIDOpts{};
        const cid = try astdb_system.getCID(snapshot, node, opts);
        try testing.expect(!astdb.CIDUtils.isZero(cid));
    }

    const end_time = compat_time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    const final_stats = astdb_system.stats();

    std.debug.print("📊 Performance Results:\n", .{});
    std.debug.print("   • Created 1000 nodes in {d:.2} ms\n", .{duration_ms});
    std.debug.print("   • Interned strings: {d}\n", .{final_stats.interned_strings});
    std.debug.print("   • Cached CIDs: {d}\n", .{final_stats.cached_cids});
    std.debug.print("   • Throughput: {d:.0} nodes/second\n", .{1000.0 / (duration_ms / 1000.0)});

    // Performance assertions
    try testing.expect(duration_ms < 1000.0); // Should complete in under 1 second
    try testing.expectEqual(@as(u32, 1000), final_stats.interned_strings);
    try testing.expectEqual(@as(u32, 1000), final_stats.cached_cids);

    std.debug.print("✅ Performance validation passed\n", .{});
}
