// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Golden Test: Query Engine Dependencyation
// Task 2.2: Dependency graph & invalidation validation
// Requirements: SPEC-astdb-query.md section E-8, incremental compilation

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;

// Import query engine modules
const engine = @import("../../../compiler/libjanus/query/engine.zig");
const deps = @import("../../../compiler/libjanus/query/dependencies.zig");

test "Golden: Complete dependency tracking integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Set up dependency tracking infrastructure
    var dependency_graph = deps.DependencyGraph.init(allocator);
    defer dependency_graph.deinit();

    var memo_cache = engine.MemoCache.init(allocator);
    defer memo_cache.deinit();

    var performance_monitor = engine.PerformanceMonitor.init(allocator);
    defer performance_monitor.deinit();

    var dependency_tracker = deps.DependencyTracker.init(allocator);
    defer dependency_tracker.deinit();

    // Create test snapshot (placeholder)
    const snapshot = engine.Snapshot{};

    // Create query context with dependency tracking
    var query_ctx = engine.QueryContext{
        .allocator = allocator,
        .snapshot = &snapshot,
        .memo_cache = &memo_cache,
        .performance_monitor = &performance_monitor,
        .dependency_graph = &dependency_graph,
        .dependency_tracker = dependency_tracker,
    };

    // Test query execution with dependency tracking
    const query_key = engine.QueryKey{ .node_at = engine.SourcePos.fromLineCol(10, 5) };

    // Execute query (should record dependencies)
    var result = try query_ctx.execute(query_key);
    defer result.deinit(allocator);

    // Verify query was cached
    try testing.expect(!result.cache_hit); // First execution should not be cache hit

    // Execute same query again (should hit cache)
    var result2 = try query_ctx.execute(query_key);
    defer result2.deinit(allocator);

    try testing.expect(result2.cache_hit); // Second execution should be cache hit

    // Verify dependency graph has recorded the query
    const stats = dependency_graph.getStats();
    try testing.expectEqual(@as(u32, 1), stats.total_queries);
}

test "Golden: CID-based invalidation precision" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dependency_graph = deps.DependencyGraph.init(allocator);
    defer dependency_graph.deinit();

    var memo_cache = engine.MemoCache.init(allocator);
    defer memo_cache.deinit();

    var invalidation_monitor = deps.InvalidationMonitor.init();

    var invalidation_engine = deps.InvalidationEngine.init(allocator, &dependency_graph, &memo_cache, &invalidation_monitor);

    // Create test dependencies
    var deps_set = deps.DependencySet.init(allocator);
    defer deps_set.deinit();

    const test_cid1 = [_]u8{1} ** 32;
    const test_cid2 = [_]u8{2} ** 32;

    try deps_set.addCID(test_cid1);

    // Record dependencies for two different queries
    const query1 = engine.QueryKey{ .node_at = engine.SourcePos.fromLineCol(10, 5) };
    const query2 = engine.QueryKey{ .node_at = engine.SourcePos.fromLineCol(20, 10) };

    try dependency_graph.recordDependencies(query1, deps_set);

    var deps_set2 = deps.DependencySet.init(allocator);
    defer deps_set2.deinit();
    try deps_set2.addCID(test_cid2);
    try dependency_graph.recordDependencies(query2, deps_set2);

    // Add queries to cache (simulate cached results)
    const dummy_result1 = engine.QueryResult{
        .data = engine.QueryData{ .node_at = null },
        .dependencies = .empty,
        .execution_time_ns = 1000000,
        .cache_hit = false,
        .error_info = null,
    };

    const dummy_result2 = engine.QueryResult{
        .data = engine.QueryData{ .node_at = null },
        .dependencies = .empty,
        .execution_time_ns = 1000000,
        .cache_hit = false,
        .error_info = null,
    };

    try memo_cache.put(query1, &dummy_result1);
    try memo_cache.put(query2, &dummy_result2);

    // Verify both queries are cached
    try testing.expect(memo_cache.get(query1) != null);
    try testing.expect(memo_cache.get(query2) != null);

    // Invalidate only test_cid1
    const changed_cids = [_]engine.CID{test_cid1};
    const invalidation_result = try invalidation_engine.invalidate(&changed_cids);

    // Verify precise invalidation
    try testing.expectEqual(@as(u32, 1), invalidation_result.changed_cids_count);
    try testing.expectEqual(@as(u32, 1), invalidation_result.invalidated_queries_count);
    try testing.expectEqual(@as(u32, 1), invalidation_result.removed_from_cache_count);

    // Verify only query1 was invalidated (depends on test_cid1)
    try testing.expect(memo_cache.get(query1) == null); // Should be invalidated
    try testing.expect(memo_cache.get(query2) != null); // Should still be cached

    // Verify high invalidation efficiency
    try testing.expect(invalidation_result.efficiency() > 0.9);
}

test "Golden: Performance guardrails validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var performance_monitor = engine.PerformanceMonitor.init(allocator);
    defer performance_monitor.deinit();

    // Simulate query executions with timing
    const query_key = engine.QueryKey{ .type_of = @enumFromInt(1) };

    // Record multiple query executions
    performance_monitor.recordQuery(query_key, 5_000_000); // 5ms
    performance_monitor.recordQuery(query_key, 8_000_000); // 8ms
    performance_monitor.recordQuery(query_key, 12_000_000); // 12ms
    performance_monitor.recordQuery(query_key, 6_000_000); // 6ms
    performance_monitor.recordQuery(query_key, 9_000_000); // 9ms

    // Verify performance statistics
    const stats = performance_monitor.getStats(.type_of);
    try testing.expect(stats != null);

    const query_stats = stats.?;
    try testing.expectEqual(@as(u64, 5), query_stats.total_calls);

    // Verify average is within reasonable bounds (should be 8ms)
    const avg_time_ms = @as(f64, @floatFromInt(query_stats.averageTimeNs())) / 1_000_000.0;
    try testing.expect(avg_time_ms >= 7.0 and avg_time_ms <= 9.0);

    // Verify performance guardrail: average should be ≤10ms for interactive queries
    try testing.expect(avg_time_ms <= 10.0);
}

test "Golden: Dependency tracking overhead measurement" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Measure dependency tracking overhead
    var dependency_tracker = deps.DependencyTracker.init(allocator);
    defer dependency_tracker.deinit();

    var dependency_set = deps.DependencySet.init(allocator);
    defer dependency_set.deinit();

    const start_time = compat_time.nanoTimestamp();

    // Simulate dependency recording during query execution
    try dependency_tracker.startTracking(&dependency_set);

    // Record multiple dependencies
    for (0..100) |i| {
        var test_cid: engine.CID = [_]u8{0} ** 32;
        test_cid[0] = @as(u8, @intCast(i % 256));
        try dependency_tracker.recordCID(test_cid);
    }

    dependency_tracker.stopTracking();

    const end_time = compat_time.nanoTimestamp();
    const overhead_ns = end_time - start_time;

    // Verify dependency tracking overhead is minimal (< 1ms for 100 dependencies)
    const overhead_ms = @as(f64, @floatFromInt(overhead_ns)) / 1_000_000.0;
    try testing.expect(overhead_ms < 1.0);

    // Verify all dependencies were recorded
    try testing.expectEqual(@as(usize, 100), dependency_set.totalDependencies());
}

test "Golden: Transitive dependency invalidation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dependency_graph = deps.DependencyGraph.init(allocator);
    defer dependency_graph.deinit();

    // Create dependency chain: query1 → query2 → query3
    const query1 = engine.QueryKey{ .node_at = engine.SourcePos.fromLineCol(10, 5) };
    const query2 = engine.QueryKey{ .type_of = @enumFromInt(1) };
    const query3 = engine.QueryKey{ .def_of = engine.SourcePos.fromLineCol(20, 10) };

    // query1 depends on CID
    var deps1 = deps.DependencySet.init(allocator);
    defer deps1.deinit();
    const test_cid = [_]u8{1} ** 32;
    try deps1.addCID(test_cid);
    try dependency_graph.recordDependencies(query1, deps1);

    // query2 depends on query1
    var deps2 = deps.DependencySet.init(allocator);
    defer deps2.deinit();
    try deps2.addQuery(query1);
    try dependency_graph.recordDependencies(query2, deps2);

    // query3 depends on query2
    var deps3 = deps.DependencySet.init(allocator);
    defer deps3.deinit();
    try deps3.addQuery(query2);
    try dependency_graph.recordDependencies(query3, deps3);

    // Test transitive invalidation
    const changed_cids = [_]engine.CID{test_cid};
    var invalidated = try dependency_graph.getInvalidatedQueries(&changed_cids, allocator);
    defer invalidated.deinit();

    // Should invalidate all three queries transitively
    try testing.expectEqual(@as(usize, 3), invalidated.items.len);

    // Verify all queries are in the invalidated list
    var found_query1 = false;
    var found_query2 = false;
    var found_query3 = false;

    for (invalidated.items) |query| {
        if (query.eql(query1)) found_query1 = true;
        if (query.eql(query2)) found_query2 = true;
        if (query.eql(query3)) found_query3 = true;
    }

    try testing.expect(found_query1);
    try testing.expect(found_query2);
    try testing.expect(found_query3);
}
