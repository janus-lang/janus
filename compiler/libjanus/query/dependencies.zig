// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Query Dependency Tracking & Invalidation Engine
// Task 2.2: Dependency graph & invalidation implementation
// Requirements: SPEC-astdb-query.md section E-8, incremental compilation

const std = @import("std");
const compat_time = @import("compat_time");
const Allocator = std.mem.Allocator;
const engine = @import("engine.zig");

const QueryKey = engine.QueryKey;
const CID = engine.CID;

/// Dependency set for a single query result
pub const DependencySet = struct {
    /// CIDs that this query depends on
    cids: std.ArrayList(CID),

    /// Other queries that this query depends on (transitive dependencies)
    queries: std.ArrayList(QueryKey),

    /// Timestamp when dependencies were recorded
    recorded_at: i64,

    allocator: Allocator,

    pub fn init(allocator: Allocator) DependencySet {
        return DependencySet{
            .cids = .empty,
            .queries = .empty,
            .recorded_at = compat_time.timestamp(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DependencySet) void {
        self.cids.deinit();
        self.queries.deinit();
    }

    /// Add a CID dependency
    pub fn addCID(self: *DependencySet, cid: CID) !void {
        // Avoid duplicates
        for (self.cids.items) |existing_cid| {
            if (std.mem.eql(u8, &existing_cid, &cid)) return;
        }
        try self.cids.append(cid);
    }

    /// Add a query dependency
    pub fn addQuery(self: *DependencySet, query_key: QueryKey) !void {
        // Avoid duplicates
        for (self.queries.items) |existing_query| {
            if (existing_query.eql(query_key)) return;
        }
        try self.queries.append(query_key);
    }

    /// Check if this dependency set depends on a specific CID
    pub fn dependsOnCID(self: *const DependencySet, cid: CID) bool {
        for (self.cids.items) |dep_cid| {
            if (std.mem.eql(u8, &dep_cid, &cid)) return true;
        }
        return false;
    }

    /// Check if this dependency set depends on a specific query
    pub fn dependsOnQuery(self: *const DependencySet, query_key: QueryKey) bool {
        for (self.queries.items) |dep_query| {
            if (dep_query.eql(query_key)) return true;
        }
        return false;
    }

    /// Get total dependency count
    pub fn totalDependencies(self: *const DependencySet) usize {
        return self.cids.items.len + self.queries.items.len;
    }

    /// Clone dependency set for caching
    pub fn clone(self: *const DependencySet) !DependencySet {
        var cloned = DependencySet.init(self.allocator);

        for (self.cids.items) |cid| {
            try cloned.cids.append(cid);
        }

        for (self.queries.items) |query| {
            try cloned.queries.append(query);
        }

        cloned.recorded_at = self.recorded_at;
        return cloned;
    }
};

/// Dependency tracker for recording dependencies during query execution
pub const DependencyTracker = struct {
    /// Current dependency set being built
    current_deps: ?*DependencySet,

    /// Stack of dependency sets for nested queries
    dep_stack: std.ArrayList(*DependencySet),

    allocator: Allocator,

    pub fn init(allocator: Allocator) DependencyTracker {
        return DependencyTracker{
            .current_deps = null,
            .dep_stack = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DependencyTracker) void {
        self.dep_stack.deinit();
    }

    /// Start tracking dependencies for a query
    pub fn startTracking(self: *DependencyTracker, deps: *DependencySet) !void {
        // Push current deps to stack if any
        if (self.current_deps) |current| {
            try self.dep_stack.append(current);
        }

        self.current_deps = deps;
    }

    /// Stop tracking dependencies and restore previous context
    pub fn stopTracking(self: *DependencyTracker) void {
        if (self.dep_stack.items.len > 0) {
            self.current_deps = self.dep_stack.pop();
        } else {
            self.current_deps = null;
        }
    }

    /// Record a CID dependency
    pub fn recordCID(self: *DependencyTracker, cid: CID) !void {
        if (self.current_deps) |deps| {
            try deps.addCID(cid);
        }
    }

    /// Record a query dependency
    pub fn recordQuery(self: *DependencyTracker, query_key: QueryKey) !void {
        if (self.current_deps) |deps| {
            try deps.addQuery(query_key);
        }
    }

    /// Check if currently tracking dependencies
    pub fn isTracking(self: *const DependencyTracker) bool {
        return self.current_deps != null;
    }
};

/// Dependency graph for managing query invalidation
pub const DependencyGraph = struct {
    /// Map from query key to its dependencies
    query_deps: std.HashMap(QueryKey, DependencySet, QueryKeyContext, std.hash_map.default_max_load_percentage),

    /// Reverse index: CID -> queries that depend on it
    cid_to_queries: std.HashMap(CID, std.ArrayList(QueryKey), CIDContext, std.hash_map.default_max_load_percentage),

    /// Reverse index: Query -> queries that depend on it
    query_to_queries: std.HashMap(QueryKey, std.ArrayList(QueryKey), QueryKeyContext, std.hash_map.default_max_load_percentage),

    allocator: Allocator,

    const QueryKeyContext = struct {
        pub fn hash(self: @This(), key: QueryKey) u64 {
            _ = self;
            return key.hash();
        }

        pub fn eql(self: @This(), a: QueryKey, b: QueryKey) bool {
            _ = self;
            return a.eql(b);
        }
    };

    const CIDContext = struct {
        pub fn hash(self: @This(), key: CID) u64 {
            _ = self;
            return std.hash_map.hashString(&key);
        }

        pub fn eql(self: @This(), a: CID, b: CID) bool {
            _ = self;
            return std.mem.eql(u8, &a, &b);
        }
    };

    pub fn init(allocator: Allocator) DependencyGraph {
        return DependencyGraph{
            .query_deps = std.HashMap(QueryKey, DependencySet, QueryKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .cid_to_queries = std.HashMap(CID, std.ArrayList(QueryKey), CIDContext, std.hash_map.default_max_load_percentage).init(allocator),
            .query_to_queries = std.HashMap(QueryKey, std.ArrayList(QueryKey), QueryKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DependencyGraph) void {
        // Clean up query dependencies
        var query_iter = self.query_deps.iterator();
        while (query_iter.next()) |entry| {
            var deps = entry.value_ptr;
            deps.deinit();
        }
        self.query_deps.deinit();

        // Clean up CID reverse index
        var cid_iter = self.cid_to_queries.iterator();
        while (cid_iter.next()) |entry| {
            var queries = entry.value_ptr;
            queries.deinit();
        }
        self.cid_to_queries.deinit();

        // Clean up query reverse index
        var query_rev_iter = self.query_to_queries.iterator();
        while (query_rev_iter.next()) |entry| {
            var queries = entry.value_ptr;
            queries.deinit();
        }
        self.query_to_queries.deinit();
    }

    /// Record dependencies for a query
    pub fn recordDependencies(self: *DependencyGraph, query_key: QueryKey, deps: DependencySet) !void {
        // Clone the dependency set for storage
        const cloned_deps = try deps.clone();
        try self.query_deps.put(query_key, cloned_deps);

        // Update reverse indexes for CID dependencies
        for (deps.cids.items) |cid| {
            var queries = self.cid_to_queries.getPtr(cid) orelse blk: {
                const new_queries = std.ArrayList(QueryKey).empty;
                try self.cid_to_queries.put(cid, new_queries);
                break :blk self.cid_to_queries.getPtr(cid).?;
            };

            // Avoid duplicates
            var found = false;
            for (queries.items) |existing_query| {
                if (existing_query.eql(query_key)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try queries.append(query_key);
            }
        }

        // Update reverse indexes for query dependencies
        for (deps.queries.items) |dep_query| {
            var queries = self.query_to_queries.getPtr(dep_query) orelse blk: {
                const new_queries = std.ArrayList(QueryKey).empty;
                try self.query_to_queries.put(dep_query, new_queries);
                break :blk self.query_to_queries.getPtr(dep_query).?;
            };

            // Avoid duplicates
            var found = false;
            for (queries.items) |existing_query| {
                if (existing_query.eql(query_key)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try queries.append(query_key);
            }
        }
    }

    /// Get queries that need to be invalidated when CIDs change
    pub fn getInvalidatedQueries(self: *DependencyGraph, changed_cids: []const CID, allocator: Allocator) !std.ArrayList(QueryKey) {
        var invalidated: std.ArrayList(QueryKey) = .empty;
        var visited = std.HashMap(QueryKey, void, QueryKeyContext, std.hash_map.default_max_load_percentage).init(allocator);
        defer visited.deinit();

        // Find directly affected queries
        for (changed_cids) |cid| {
            if (self.cid_to_queries.get(cid)) |queries| {
                for (queries.items) |query_key| {
                    if (!visited.contains(query_key)) {
                        try invalidated.append(query_key);
                        try visited.put(query_key, {});

                        // Recursively find transitively affected queries
                        try self.findTransitivelyAffected(query_key, &invalidated, &visited);
                    }
                }
            }
        }

        return invalidated;
    }

    /// Recursively find queries that are transitively affected
    fn findTransitivelyAffected(self: *DependencyGraph, query_key: QueryKey, invalidated: *std.ArrayList(QueryKey), visited: *std.HashMap(QueryKey, void, QueryKeyContext, std.hash_map.default_max_load_percentage)) !void {
        if (self.query_to_queries.get(query_key)) |dependent_queries| {
            for (dependent_queries.items) |dependent_query| {
                if (!visited.contains(dependent_query)) {
                    try invalidated.append(dependent_query);
                    try visited.put(dependent_query, {});

                    // Recurse for transitive dependencies
                    try self.findTransitivelyAffected(dependent_query, invalidated, visited);
                }
            }
        }
    }

    /// Get dependency statistics
    pub fn getStats(self: *const DependencyGraph) DependencyStats {
        var total_cid_deps: usize = 0;
        var total_query_deps: usize = 0;

        var query_iter = self.query_deps.iterator();
        while (query_iter.next()) |entry| {
            const deps = entry.value_ptr;
            total_cid_deps += deps.cids.items.len;
            total_query_deps += deps.queries.items.len;
        }

        return DependencyStats{
            .total_queries = self.query_deps.count(),
            .total_cid_dependencies = total_cid_deps,
            .total_query_dependencies = total_query_deps,
            .cid_index_entries = self.cid_to_queries.count(),
            .query_index_entries = self.query_to_queries.count(),
        };
    }

    /// Remove dependencies for a query (when it's evicted from cache)
    pub fn removeDependencies(self: *DependencyGraph, query_key: QueryKey) void {
        if (self.query_deps.getPtr(query_key)) |deps| {
            // Remove from CID reverse index
            for (deps.cids.items) |cid| {
                if (self.cid_to_queries.getPtr(cid)) |queries| {
                    var i: usize = 0;
                    while (i < queries.items.len) {
                        if (queries.items[i].eql(query_key)) {
                            _ = queries.swapRemove(i);
                        } else {
                            i += 1;
                        }
                    }
                }
            }

            // Remove from query reverse index
            for (deps.queries.items) |dep_query| {
                if (self.query_to_queries.getPtr(dep_query)) |queries| {
                    var i: usize = 0;
                    while (i < queries.items.len) {
                        if (queries.items[i].eql(query_key)) {
                            _ = queries.swapRemove(i);
                        } else {
                            i += 1;
                        }
                    }
                }
            }

            // Remove the dependency set
            deps.deinit();
            _ = self.query_deps.remove(query_key);
        }
    }
};

/// Dependency statistics for monitoring and optimization
pub const DependencyStats = struct {
    total_queries: u32,
    total_cid_dependencies: usize,
    total_query_dependencies: usize,
    cid_index_entries: u32,
    query_index_entries: u32,

    pub fn averageCIDDepsPerQuery(self: DependencyStats) f64 {
        if (self.total_queries == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_cid_dependencies)) / @as(f64, @floatFromInt(self.total_queries));
    }

    pub fn averageQueryDepsPerQuery(self: DependencyStats) f64 {
        if (self.total_queries == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_query_dependencies)) / @as(f64, @floatFromInt(self.total_queries));
    }
};

/// Invalidation engine that coordinates cache invalidation
pub const InvalidationEngine = struct {
    dependency_graph: *DependencyGraph,
    memo_cache: *engine.MemoCache,
    performance_monitor: *InvalidationMonitor,
    allocator: Allocator,

    pub fn init(allocator: Allocator, dependency_graph: *DependencyGraph, memo_cache: *engine.MemoCache, performance_monitor: *InvalidationMonitor) InvalidationEngine {
        return InvalidationEngine{
            .dependency_graph = dependency_graph,
            .memo_cache = memo_cache,
            .performance_monitor = performance_monitor,
            .allocator = allocator,
        };
    }

    /// Invalidate queries based on changed CIDs
    pub fn invalidate(self: *InvalidationEngine, changed_cids: []const CID) !InvalidationResult {
        const start_time = compat_time.nanoTimestamp();

        // Find queries to invalidate
        var invalidated_queries = try self.dependency_graph.getInvalidatedQueries(changed_cids, self.allocator);
        defer invalidated_queries.deinit();

        // Remove invalidated queries from cache
        var removed_count: u32 = 0;
        for (invalidated_queries.items) |query_key| {
            if (self.memo_cache.cache.contains(query_key)) {
                _ = self.memo_cache.cache.remove(query_key);
                self.dependency_graph.removeDependencies(query_key);
                removed_count += 1;
            }
        }

        const end_time = compat_time.nanoTimestamp();
        const invalidation_time_ns = end_time - start_time;

        // Record performance metrics
        self.performance_monitor.recordInvalidation(@as(u32, @intCast(changed_cids.len)), @as(u32, @intCast(invalidated_queries.items.len)), removed_count, invalidation_time_ns);

        return InvalidationResult{
            .changed_cids_count = @as(u32, @intCast(changed_cids.len)),
            .invalidated_queries_count = @as(u32, @intCast(invalidated_queries.items.len)),
            .removed_from_cache_count = removed_count,
            .invalidation_time_ns = invalidation_time_ns,
        };
    }
};

/// Result of an invalidation operation
pub const InvalidationResult = struct {
    changed_cids_count: u32,
    invalidated_queries_count: u32,
    removed_from_cache_count: u32,
    invalidation_time_ns: u64,

    pub fn efficiency(self: InvalidationResult) f64 {
        if (self.invalidated_queries_count == 0) return 1.0;
        return @as(f64, @floatFromInt(self.removed_from_cache_count)) / @as(f64, @floatFromInt(self.invalidated_queries_count));
    }
};

/// Performance monitoring for invalidation operations
pub const InvalidationMonitor = struct {
    total_invalidations: u64,
    total_changed_cids: u64,
    total_invalidated_queries: u64,
    total_removed_from_cache: u64,
    total_invalidation_time_ns: u64,

    pub fn init() InvalidationMonitor {
        return InvalidationMonitor{
            .total_invalidations = 0,
            .total_changed_cids = 0,
            .total_invalidated_queries = 0,
            .total_removed_from_cache = 0,
            .total_invalidation_time_ns = 0,
        };
    }

    pub fn recordInvalidation(self: *InvalidationMonitor, changed_cids: u32, invalidated_queries: u32, removed_from_cache: u32, invalidation_time_ns: u64) void {
        self.total_invalidations += 1;
        self.total_changed_cids += changed_cids;
        self.total_invalidated_queries += invalidated_queries;
        self.total_removed_from_cache += removed_from_cache;
        self.total_invalidation_time_ns += invalidation_time_ns;
    }

    pub fn averageInvalidationTimeMs(self: *const InvalidationMonitor) f64 {
        if (self.total_invalidations == 0) return 0.0;
        const avg_ns = self.total_invalidation_time_ns / self.total_invalidations;
        return @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;
    }

    pub fn averageQueriesPerInvalidation(self: *const InvalidationMonitor) f64 {
        if (self.total_invalidations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_invalidated_queries)) / @as(f64, @floatFromInt(self.total_invalidations));
    }

    pub fn cacheEfficiency(self: *const InvalidationMonitor) f64 {
        if (self.total_invalidated_queries == 0) return 1.0;
        return @as(f64, @floatFromInt(self.total_removed_from_cache)) / @as(f64, @floatFromInt(self.total_invalidated_queries));
    }

    pub fn printReport(self: *const InvalidationMonitor) void {
        std.debug.print("\n=== Invalidation Performance Report ===\n");
        std.debug.print("Total invalidations: {}\n", .{self.total_invalidations});
        std.debug.print("Average invalidation time: {d:.2}ms\n", .{self.averageInvalidationTimeMs()});
        std.debug.print("Average queries per invalidation: {d:.1}\n", .{self.averageQueriesPerInvalidation()});
        std.debug.print("Cache efficiency: {d:.1}%\n", .{self.cacheEfficiency() * 100.0});
    }
};

test "Dependency tracking basic functionality" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test DependencySet
    var deps = DependencySet.init(allocator);
    defer deps.deinit();

    const test_cid = [_]u8{1} ** 32;
    try deps.addCID(test_cid);

    try testing.expect(deps.dependsOnCID(test_cid));
    try testing.expectEqual(@as(usize, 1), deps.totalDependencies());

    // Test DependencyTracker
    var tracker = DependencyTracker.init(allocator);
    defer tracker.deinit();

    try testing.expect(!tracker.isTracking());

    try tracker.startTracking(&deps);
    try testing.expect(tracker.isTracking());

    tracker.stopTracking();
    try testing.expect(!tracker.isTracking());
}

test "Dependency graph invalidation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    // Create test dependencies
    var deps = DependencySet.init(allocator);
    defer deps.deinit();

    const test_cid = [_]u8{1} ** 32;
    try deps.addCID(test_cid);

    const query_key = QueryKey{ .node_at = engine.SourcePos.fromLineCol(10, 5) };
    try graph.recordDependencies(query_key, deps);

    // Test invalidation
    const changed_cids = [_]CID{test_cid};
    var invalidated = try graph.getInvalidatedQueries(&changed_cids, allocator);
    defer invalidated.deinit();

    try testing.expectEqual(@as(usize, 1), invalidated.items.len);
    try testing.expect(invalidated.items[0].eql(query_key));

    // Test stats
    const stats = graph.getStats();
    try testing.expectEqual(@as(u32, 1), stats.total_queries);
    try testing.expectEqual(@as(usize, 1), stats.total_cid_dependencies);
}

test "Invalidation engine performance" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var monitor = InvalidationMonitor.init();

    // Record some invalidations
    monitor.recordInvalidation(2, 5, 4, 1_000_000); // 1ms
    monitor.recordInvalidation(1, 3, 3, 2_000_000); // 2ms

    try testing.expectEqual(@as(u64, 2), monitor.total_invalidations);
    try testing.expectEqual(1.5, monitor.averageInvalidationTimeMs());
    try testing.expectEqual(4.0, monitor.averageQueriesPerInvalidation());

    const efficiency = monitor.cacheEfficiency();
    try testing.expect(efficiency > 0.8); // Should be high efficiency
}
