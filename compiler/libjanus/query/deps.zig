// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Dependency Tracking - Records query dependencies for precise invalidation
// Task 2.3 - Implements dependency recording and invalidation precision

const std = @import("std");
const Allocator = std.mem.Allocator;
const context = @import("context.zig");

/// Dependency tracker for query invalidation
pub const DependencyTracker = struct {
    allocator: Allocator,
    current_query: ?context.MemoKey,
    dependencies: std.HashMap(context.MemoKey, DependencySet, MemoKeyContext, std.hash_map.default_max_load_percentage),
    reverse_dependencies: std.HashMap(Dependency, DependencySet, DependencyContext, std.hash_map.default_max_load_percentage),
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        self.* = Self{
            .allocator = allocator,
            .current_query = null,
            .dependencies = std.HashMap(context.MemoKey, DependencySet, MemoKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .reverse_dependencies = std.HashMap(Dependency, DependencySet, DependencyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = std.Thread.Mutex{},
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up dependency sets
        var dep_iterator = self.dependencies.iterator();
        while (dep_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }

        var rev_iterator = self.reverse_dependencies.iterator();
        while (rev_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }

        self.dependencies.deinit();
        self.reverse_dependencies.deinit();
        self.allocator.destroy(self);
    }

    /// Start tracking dependencies for a query
    pub fn startQuery(self: *Self, query_key: context.MemoKey) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.current_query = query_key;

        // Initialize dependency set if not exists
        if (!self.dependencies.contains(query_key)) {
            const dep_set = DependencySet.init(self.allocator);
            self.dependencies.put(query_key, dep_set) catch {};
        }
    }

    /// Stop tracking dependencies for current query
    pub fn endQuery(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.current_query = null;
    }

    /// Record a dependency on a CID
    pub fn recordCIDDependency(self: *Self, cid: context.CID) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.current_query) |query_key| {
            const dependency = Dependency{ .cid = cid };
            self.addDependency(query_key, dependency);
        }
    }

    /// Record a dependency on another query
    pub fn recordQueryDependency(self: *Self, dep_query_key: context.MemoKey) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.current_query) |query_key| {
            const dependency = Dependency{ .query = dep_query_key };
            self.addDependency(query_key, dependency);
        }
    }

    /// Get all dependencies for a query
    pub fn getDependencies(self: *Self, query_key: context.MemoKey) []Dependency {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.dependencies.get(query_key)) |dep_set| {
            return dep_set.items;
        }
        return &.{};
    }

    /// Get all queries that depend on a given dependency
    pub fn getDependents(self: *Self, dependency: Dependency) []context.MemoKey {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.reverse_dependencies.get(dependency)) |dep_set| {
            return dep_set.items;
        }
        return &.{};
    }

    /// Invalidate queries based on changed CIDs
    pub fn invalidateByChangedCIDs(self: *Self, changed_cids: []const context.CID, memo_table: *@import("memo.zig").MemoTable) InvalidationResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        var invalidated_queries = std.ArrayList(context.MemoKey).init(self.allocator);
        var processed = std.HashMap(context.MemoKey, void, MemoKeyContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer processed.deinit();

        // Find all queries that depend on changed CIDs
        for (changed_cids) |cid| {
            const dependency = Dependency{ .cid = cid };
            const dependents = self.getDependents(dependency);

            for (dependents) |query_key| {
                if (!processed.contains(query_key)) {
                    self.invalidateQueryRecursive(query_key, &invalidated_queries, &processed, memo_table);
                }
            }
        }

        return InvalidationResult{
            .invalidated_queries = invalidated_queries.toOwnedSlice() catch &.{},
            .total_invalidated = @intCast(invalidated_queries.items.len),
        };
    }

    /// Remove all dependencies for a query (when query is removed)
    pub fn removeDependencies(self: *Self, query_key: context.MemoKey) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.dependencies.fetchRemove(query_key)) |entry| {
            const dep_set = entry.value;

            // Remove reverse dependencies
            for (dep_set.items) |dependency| {
                if (self.reverse_dependencies.getPtr(dependency)) |rev_set| {
                    self.removeDependentFromSet(rev_set, query_key);
                }
            }

            dep_set.deinit();
        }
    }

    fn addDependency(self: *Self, query_key: context.MemoKey, dependency: Dependency) void {
        // Add to forward dependencies
        if (self.dependencies.getPtr(query_key)) |dep_set| {
            dep_set.append(dependency) catch {};
        }

        // Add to reverse dependencies
        if (!self.reverse_dependencies.contains(dependency)) {
            const rev_set = DependencySet.init(self.allocator);
            self.reverse_dependencies.put(dependency, rev_set) catch {};
        }

        if (self.reverse_dependencies.getPtr(dependency)) |rev_set| {
            rev_set.append(query_key) catch {};
        }
    }

    fn invalidateQueryRecursive(
        self: *Self,
        query_key: context.MemoKey,
        invalidated_list: *std.ArrayList(context.MemoKey),
        processed: *std.HashMap(context.MemoKey, void, MemoKeyContext, std.hash_map.default_max_load_percentage),
        memo_table: *@import("memo.zig").MemoTable,
    ) void {
        if (processed.contains(query_key)) return;

        processed.put(query_key, {}) catch {};
        invalidated_list.append(query_key) catch {};

        // Remove from memo table
        memo_table.remove(query_key);

        // Find queries that depend on this query and invalidate them too
        const query_dependency = Dependency{ .query = query_key };
        const dependents = self.getDependents(query_dependency);

        for (dependents) |dependent_query| {
            self.invalidateQueryRecursive(dependent_query, invalidated_list, processed, memo_table);
        }
    }

    fn removeDependentFromSet(self: *Self, dep_set: *DependencySet, query_key: context.MemoKey) void {
        _ = self;
        var i: usize = 0;
        while (i < dep_set.items.len) {
            if (dep_set.items[i].eql(query_key)) {
                _ = dep_set.swapRemove(i);
                return;
            }
            i += 1;
        }
    }
};

/// Dependency types
pub const Dependency = union(enum) {
    cid: context.CID,
    query: context.MemoKey,

    pub fn eql(self: Dependency, other: Dependency) bool {
        if (@intFromEnum(self) != @intFromEnum(other)) return false;

        return switch (self) {
            .cid => |cid| std.mem.eql(u8, &cid, &other.cid),
            .query => |query| query.eql(other.query),
        };
    }
};

/// Set of dependencies
const DependencySet = std.ArrayList(Dependency);

/// Hash map context for MemoKey
const MemoKeyContext = struct {
    pub fn hash(self: @This(), key: context.MemoKey) u64 {
        _ = self;
        return std.mem.readInt(u64, key.hash[0..8], .little);
    }

    pub fn eql(self: @This(), a: context.MemoKey, b: context.MemoKey) bool {
        _ = self;
        return a.eql(b);
    }
};

/// Hash map context for Dependency
const DependencyContext = struct {
    pub fn hash(self: @This(), dep: Dependency) u64 {
        _ = self;
        return switch (dep) {
            .cid => |cid| std.mem.readInt(u64, cid[0..8], .little),
            .query => |query| std.mem.readInt(u64, query.hash[0..8], .little),
        };
    }

    pub fn eql(self: @This(), a: Dependency, b: Dependency) bool {
        _ = self;
        return a.eql(b);
    }
};

/// Result of invalidation operation
pub const InvalidationResult = struct {
    invalidated_queries: []context.MemoKey,
    total_invalidated: u32,

    pub fn deinit(self: InvalidationResult, allocator: Allocator) void {
        allocator.free(self.invalidated_queries);
    }
};

/// Change set from ASTDB for invalidation
pub const ChangeSet = struct {
    changed_cids: []const context.CID,
    removed_cids: []const context.CID,

    pub fn isEmpty(self: ChangeSet) bool {
        return self.changed_cids.len == 0 and self.removed_cids.len == 0;
    }
};

/// Dependency analysis for debugging and optimization
pub const DependencyAnalysis = struct {
    total_queries: u32,
    total_dependencies: u32,
    max_dependency_depth: u32,
    circular_dependencies: []CircularDependency,

    const CircularDependency = struct {
        cycle: []context.MemoKey,
    };
};

/// Analyze dependency graph for cycles and statistics
pub fn analyzeDependencies(tracker: *DependencyTracker, allocator: Allocator) !DependencyAnalysis {
    tracker.mutex.lock();
    defer tracker.mutex.unlock();

    var analysis = DependencyAnalysis{
        .total_queries = @intCast(tracker.dependencies.count()),
        .total_dependencies = 0,
        .max_dependency_depth = 0,
        .circular_dependencies = &.{},
    };

    // Count total dependencies
    var dep_iterator = tracker.dependencies.iterator();
    while (dep_iterator.next()) |entry| {
        analysis.total_dependencies += @intCast(entry.value_ptr.items.len);
    }

    // TODO: Implement cycle detection and depth analysis
    // This would require a more sophisticated graph traversal algorithm

    return analysis;
}
