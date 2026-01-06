// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Tests for memo table and cycle detection
// Task 2.2 - Validates EARS: repeated calls same QID → cache hit; cycle produces QE0007

const std = @import("std");
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;

const context = @import("../../../compiler/libjanus/query/context.zig");
const memo = @import("../../../compiler/libjanus/query/memo.zig");

test "memo table cache hit on repeated calls" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var memo_table = try memo.MemoTable.init(allocator);
    defer memo_table.deinit();

    // Create test key and result
    const test_key = context.MemoKey{ .hash = [_]u8{1} ** 32 };
    const test_result = context.CachedResult{
        .data = context.QueryResultData{ .symbol_info = context.SymbolInfo{ .name = "test" } },
        .dependencies = &.{},
    };

    // First call should be a miss
    try expect(memo_table.get(test_key) == null);

    // Put result in cache
    try memo_table.put(test_key, test_result);

    // Second call should be a hit
    const cached = memo_table.get(test_key);
    try expect(cached != null);

    // Verify cache statistics
    const stats = memo_table.getStats();
    try expectEqual(@as(u32, 1), stats.total_entries);
    try expectEqual(@as(u32, 1), stats.total_hits);
    try expectEqual(@as(u32, 1), stats.total_misses);
}

test "cycle detector prevents infinite recursion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var cycle_detector = memo.CycleDetector.init(allocator);
    defer cycle_detector.deinit();

    const query_key = context.MemoKey{ .hash = [_]u8{2} ** 32 };

    // Start tracking query
    try cycle_detector.startQuery(query_key);

    // Try to start same query again (should detect cycle)
    try expectError(error.QE0007_Cycle, cycle_detector.startQuery(query_key));

    // Clean up
    cycle_detector.endQuery(query_key);
}

test "cycle detector transitive dependency cycle" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var cycle_detector = memo.CycleDetector.init(allocator);
    defer cycle_detector.deinit();

    const query_a = context.MemoKey{ .hash = [_]u8{3} ** 32 };
    const query_b = context.MemoKey{ .hash = [_]u8{4} ** 32 };
    const query_c = context.MemoKey{ .hash = [_]u8{5} ** 32 };

    // Start queries A -> B -> C
    try cycle_detector.startQuery(query_a);
    try cycle_detector.addDependency(query_a, query_b);

    try cycle_detector.startQuery(query_b);
    try cycle_detector.addDependency(query_b, query_c);

    try cycle_detector.startQuery(query_c);

    // Try to add C -> A dependency (should detect cycle)
    try expectError(error.QE0007_Cycle, cycle_detector.addDependency(query_c, query_a));

    // Clean up
    cycle_detector.endQuery(query_c);
    cycle_detector.endQuery(query_b);
    cycle_detector.endQuery(query_a);
}

test "memo table sharding distributes load" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var memo_table = try memo.MemoTable.init(allocator);
    defer memo_table.deinit();

    // Add multiple entries with different keys
    var i: u8 = 0;
    while (i < 10) : (i += 1) {
        const key = context.MemoKey{ .hash = [_]u8{i} ** 32 };
        const result = context.CachedResult{
            .data = context.QueryResultData{ .symbol_info = context.SymbolInfo{ .name = "test" } },
            .dependencies = &.{},
        };

        try memo_table.put(key, result);
    }

    // Verify all entries are accessible
    i = 0;
    while (i < 10) : (i += 1) {
        const key = context.MemoKey{ .hash = [_]u8{i} ** 32 };
        try expect(memo_table.get(key) != null);
    }

    const stats = memo_table.getStats();
    try expectEqual(@as(u32, 10), stats.total_entries);
}

test "cache statistics accuracy" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var memo_table = try memo.MemoTable.init(allocator);
    defer memo_table.deinit();

    const key1 = context.MemoKey{ .hash = [_]u8{6} ** 32 };
    const key2 = context.MemoKey{ .hash = [_]u8{7} ** 32 };
    const result = context.CachedResult{
        .data = context.QueryResultData{ .symbol_info = context.SymbolInfo{ .name = "test" } },
        .dependencies = &.{},
    };

    // Miss on key1
    _ = memo_table.get(key1);

    // Put key1
    try memo_table.put(key1, result);

    // Hit on key1
    _ = memo_table.get(key1);

    // Miss on key2
    _ = memo_table.get(key2);

    const stats = memo_table.getStats();
    try expectEqual(@as(u32, 1), stats.total_entries);
    try expectEqual(@as(u32, 1), stats.total_hits);
    try expectEqual(@as(u32, 2), stats.total_misses);

    // Hit rate should be 1/3 = 0.333...
    const hit_rate = stats.hitRate();
    try expect(hit_rate > 0.33 and hit_rate < 0.34);
}

test "memo table clear removes all entries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var memo_table = try memo.MemoTable.init(allocator);
    defer memo_table.deinit();

    // Add some entries
    var i: u8 = 0;
    while (i < 5) : (i += 1) {
        const key = context.MemoKey{ .hash = [_]u8{i} ** 32 };
        const result = context.CachedResult{
            .data = context.QueryResultData{ .symbol_info = context.SymbolInfo{ .name = "test" } },
            .dependencies = &.{},
        };
        try memo_table.put(key, result);
    }

    // Verify entries exist
    var stats = memo_table.getStats();
    try expectEqual(@as(u32, 5), stats.total_entries);

    // Clear cache
    memo_table.clear();

    // Verify all entries removed
    stats = memo_table.getStats();
    try expectEqual(@as(u32, 0), stats.total_entries);

    // Verify gets return null
    i = 0;
    while (i < 5) : (i += 1) {
        const key = context.MemoKey{ .hash = [_]u8{i} ** 32 };
        try expect(memo_table.get(key) == null);
    }
}
