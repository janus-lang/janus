// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Unit Test: Complete Dependency Tracking System
// Task 2.2: Dependency graph & invalidation validation

const std = @import("std");
const testing = std.testing;

test "Dependency tracking system integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test basic dependency set operations
    var deps = std.ArrayList([32]u8){};
    defer deps.deinit();

    const test_cid = [_]u8{1} ** 32;
    try deps.append(test_cid);

    // Verify dependency was recorded
    try testing.expectEqual(@as(usize, 1), deps.items.len);
    try testing.expectEqualSlices(u8, &test_cid, &deps.items[0]);

    // Test CID comparison for invalidation
    const same_cid = [_]u8{1} ** 32;
    const different_cid = [_]u8{2} ** 32;

    try testing.expect(std.mem.eql(u8, &test_cid, &same_cid));
    try testing.expect(!std.mem.eql(u8, &test_cid, &different_cid));
}

test "BLAKE3 CID invalidation simulation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simulate CID computation for different content
    var hasher1 = std.crypto.hash.Blake3.init(.{});
    hasher1.update("func main() { print(\"hello\"); }");
    var cid1: [32]u8 = undefined;
    hasher1.final(&cid1);

    var hasher2 = std.crypto.hash.Blake3.init(.{});
    hasher2.update("func main() { print(\"world\"); }"); // Different content
    var cid2: [32]u8 = undefined;
    hasher2.final(&cid2);

    var hasher3 = std.crypto.hash.Blake3.init(.{});
    hasher3.update("func main() {\n  print(\"hello\");\n}"); // Same semantic, different whitespace
    var cid3: [32]u8 = undefined;
    hasher3.final(&cid3);

    // Different semantic content should have different CIDs
    try testing.expect(!std.mem.eql(u8, &cid1, &cid2));

    // Same semantic content with different whitespace should have different raw CIDs
    // (This test shows why we need semantic normalization in the canonicalizer)
    try testing.expect(!std.mem.eql(u8, &cid1, &cid3));

    // Create dependency tracking simulation
    var query_deps = std.HashMap(u32, std.ArrayList([32]u8), std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator);
    defer {
        var iterator = query_deps.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        query_deps.deinit();
    }

    // Query 1 depends on cid1
    var deps_for_query1 = std.ArrayList([32]u8){};
    try deps_for_query1.append(cid1);
    try query_deps.put(1, deps_for_query1);

    // Query 2 depends on cid2
    var deps_for_query2 = std.ArrayList([32]u8){};
    try deps_for_query2.append(cid2);
    try query_deps.put(2, deps_for_query2);

    // Simulate invalidation when cid1 changes
    const changed_cids = [_][32]u8{cid1};
    var invalidated_queries = std.ArrayList(u32){};
    defer invalidated_queries.deinit();

    // Find queries that depend on changed CIDs
    var query_iterator = query_deps.iterator();
    while (query_iterator.next()) |entry| {
        const query_id = entry.key_ptr.*;
        const query_cid_deps = entry.value_ptr.*;

        for (changed_cids) |changed_cid| {
            for (query_cid_deps.items) |dep_cid| {
                if (std.mem.eql(u8, &changed_cid, &dep_cid)) {
                    try invalidated_queries.append(query_id);
                    break;
                }
            }
        }
    }

    // Should only invalidate query 1
    try testing.expectEqual(@as(usize, 1), invalidated_queries.items.len);
    try testing.expectEqual(@as(u32, 1), invalidated_queries.items[0]);
}

test "Performance overhead measurement" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Measure dependency tracking overhead
    const start_time = std.time.nanoTimestamp();

    // Simulate dependency recording for 1000 queries
    var all_deps = std.ArrayList(std.ArrayList([32]u8)){};
    defer {
        for (all_deps.items) |*deps_list| {
            deps_list.deinit();
        }
        all_deps.deinit();
    }

    for (0..1000) |i| {
        var deps_list = std.ArrayList([32]u8){};

        // Each query depends on 5 CIDs on average
        for (0..5) |j| {
            var test_cid: [32]u8 = [_]u8{0} ** 32;
            test_cid[0] = @as(u8, @intCast((i + j) % 256));
            try deps_list.append(test_cid);
        }

        try all_deps.append(deps_list);
    }

    const end_time = std.time.nanoTimestamp();
    const overhead_ns = end_time - start_time;
    const overhead_ms = @as(f64, @floatFromInt(overhead_ns)) / 1_000_000.0;

    // Dependency tracking for 1000 queries should be fast (< 100ms)
    try testing.expect(overhead_ms < 100.0);

    // Verify all dependencies were recorded
    try testing.expectEqual(@as(usize, 1000), all_deps.items.len);
    for (all_deps.items) |deps_list| {
        try testing.expectEqual(@as(usize, 5), deps_list.items.len);
    }
}
