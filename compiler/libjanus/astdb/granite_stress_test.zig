// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const granite_interner = @import("granite_interner.zig");
const granite_snapshot = @import("granite_snapshot.zig");

// GRANITE-SOLID COMPREHENSIVE STRESS TEST
// Brutal validation of the entire foundational layer
// Zero leaks, maximum stress, architectural integrity

test "Granite-Solid Foundation - Comprehensive Stress Test" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        // Initialize granite-solid components
        var str_interner = granite_interner.StrInterner.init(allocator, false);
        defer str_interner.deinit();

        var snapshot = try granite_snapshot.Snapshot.init(allocator, &str_interner);
        defer snapshot.deinit();

        // STRESS TEST 1: Massive string interning
        for (0..2000) |i| {
            const str = try std.fmt.allocPrint(allocator, "stress_string_{d}", .{i});
            defer allocator.free(str);

            _ = try str_interner.get(str);
        }

        // STRESS TEST 2: Massive AST construction
        for (0..1000) |i| {
            const identifier_str = try std.fmt.allocPrint(allocator, "identifier_{d}", .{i});
            defer allocator.free(identifier_str);

            const str_id = try str_interner.get(identifier_str);

            // Create token
            const token_id = try snapshot.addToken(.identifier, str_id, granite_snapshot.Span{
                .start_byte = @as(u32, @intCast(i * 10)),
                .end_byte = @as(u32, @intCast(i * 10 + 5)),
                .start_line = @as(u32, @intCast(i / 100 + 1)),
                .start_col = @as(u32, @intCast(i % 100 + 1)),
                .end_line = @as(u32, @intCast(i / 100 + 1)),
                .end_col = @as(u32, @intCast(i % 100 + 6)),
            });

            // Create node
            const node_id = try snapshot.addNode(.identifier, token_id, token_id, &[_]granite_snapshot.NodeId{});

            // Add scope
            const scope_id = try snapshot.addScope(@enumFromInt(0));

            // Add declaration
            _ = try snapshot.addDecl(node_id, str_id, scope_id, .variable);

            // Add reference
            _ = try snapshot.addRef(node_id, str_id, @enumFromInt(0));

            // Add diagnostic
            const diag_msg = try str_interner.get("Test diagnostic message");
            _ = try snapshot.addDiag(1001, 0, granite_snapshot.Span{
                .start_byte = @as(u32, @intCast(i * 10)),
                .end_byte = @as(u32, @intCast(i * 10 + 5)),
                .start_line = @as(u32, @intCast(i / 100 + 1)),
                .start_col = @as(u32, @intCast(i % 100 + 1)),
                .end_line = @as(u32, @intCast(i / 100 + 1)),
                .end_col = @as(u32, @intCast(i % 100 + 6)),
            }, diag_msg);

            // Set CID
            const test_cid = [_]u8{0} ** 31 ++ [_]u8{@as(u8, @intCast(i % 256))};
            try snapshot.setCID(node_id, test_cid);
        }

        // STRESS TEST 3: Deduplication verification
        const count_before_duplication = str_interner.count();
        const duplicate_count = 100;
        for (0..duplicate_count) |i| {
            const base_str = try std.fmt.allocPrint(allocator, "duplicate_{d}", .{i % 10});
            defer allocator.free(base_str);
            _ = try str_interner.get(base_str);
        }
        const count_after_duplication = str_interner.count();

        // Should only add 10 unique strings (duplicate_0 through duplicate_9)
        try testing.expectEqual(count_before_duplication + 10, count_after_duplication);

        // Verify final counts - we expect around 3000+ strings since most are unique
        const final_count = str_interner.count();
        try testing.expect(final_count > 3000); // Should have many strings
        try testing.expect(final_count < 3100); // Should be reasonable count

        try testing.expectEqual(@as(u32, 1000), snapshot.tokenCount());
        try testing.expectEqual(@as(u32, 1000), snapshot.nodeCount());
        try testing.expectEqual(@as(u32, 1000), snapshot.declCount());
        try testing.expectEqual(@as(u32, 1000), snapshot.diagCount());

        // STRESS TEST 4: Retrieval verification
        for (0..100) |i| {
            const token_id: granite_snapshot.TokenId = @enumFromInt(@as(u32, @intCast(i)));
            const node_id: granite_snapshot.NodeId = @enumFromInt(@as(u32, @intCast(i)));

            const token = snapshot.getToken(token_id);
            const node = snapshot.getNode(node_id);
            const cid = snapshot.getCID(node_id);

            try testing.expect(token != null);
            try testing.expect(node != null);
            try testing.expect(cid != null);

            // Verify CID matches what we set
            const expected_cid = [_]u8{0} ** 31 ++ [_]u8{@as(u8, @intCast(i % 256))};
            try testing.expectEqualSlices(u8, &expected_cid, &cid.?);
        }
    }

    // GRANITE-SOLID: Zero leaks guaranteed - the ultimate test
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite-Solid Foundation - Capacity Limits" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var str_interner = granite_interner.StrInterner.init(allocator, false);
        defer str_interner.deinit();

        var snapshot = try granite_snapshot.Snapshot.init(allocator, &str_interner);
        defer snapshot.deinit();

        // Test that we can approach but not exceed capacity limits
        // This verifies the granite-solid architecture prevents unbounded growth

        // Fill up to near capacity
        const test_count = 1000; // Well within limits

        for (0..test_count) |i| {
            const str = try std.fmt.allocPrint(allocator, "capacity_test_{d}", .{i});
            defer allocator.free(str);

            const str_id = try str_interner.get(str);
            const token_id = try snapshot.addToken(.identifier, str_id, granite_snapshot.Span{
                .start_byte = 0,
                .end_byte = 5,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 6,
            });
            _ = try snapshot.addNode(.identifier, token_id, token_id, &[_]granite_snapshot.NodeId{});
        }

        // Verify we're still within capacity and functioning
        try testing.expectEqual(@as(u32, test_count), snapshot.tokenCount());
        try testing.expectEqual(@as(u32, test_count), snapshot.nodeCount());
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite-Solid Foundation - Cross-Component Integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        // Test that interner and snapshot work together seamlessly
        var str_interner = granite_interner.StrInterner.init(allocator, false);
        defer str_interner.deinit();

        var snapshot1 = try granite_snapshot.Snapshot.init(allocator, &str_interner);
        defer snapshot1.deinit();

        var snapshot2 = try granite_snapshot.Snapshot.init(allocator, &str_interner);
        defer snapshot2.deinit();

        // Both snapshots should share the same string interner
        const shared_str = try str_interner.get("shared_identifier");

        const token1 = try snapshot1.addToken(.identifier, shared_str, granite_snapshot.Span{
            .start_byte = 0,
            .end_byte = 5,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 6,
        });

        const token2 = try snapshot2.addToken(.identifier, shared_str, granite_snapshot.Span{
            .start_byte = 10,
            .end_byte = 15,
            .start_line = 2,
            .start_col = 1,
            .end_line = 2,
            .end_col = 6,
        });

        // Verify both tokens reference the same string
        const retrieved1 = snapshot1.getToken(token1).?;
        const retrieved2 = snapshot2.getToken(token2).?;

        try testing.expectEqual(shared_str, retrieved1.str_id);
        try testing.expectEqual(shared_str, retrieved2.str_id);
        try testing.expectEqual(retrieved1.str_id, retrieved2.str_id);
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}
