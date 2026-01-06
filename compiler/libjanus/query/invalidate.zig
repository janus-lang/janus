// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Invalidation Engine
//! Task 2.4 - Apply ChangeSets from ASTDB (CID diff), revalidate precisely
//!
//! This module implements precise invalidation of cached query results
//! when source code changes. Only queries that are actually affected
//! by semantic changes are invalidated, making incremental analysis
//! lightning-fast even on massive codebases.

const std = @import("std");
const Allocator = std.mem.Allocator;
const context = @import("context.zig");
const deps = @import("deps.zig");
const memo = @import("memo.zig");
const astdb = @import("../astdb.zig");

const QueryCtx = context.QueryCtx;
const MemoKey = context.MemoKey;
const MemoTable = memo.MemoTable;
const DependencyTracker = deps.DependencyTracker;
const CID = @import("../astdb/ids.zig").CID;

/// Represents a semantic change in the codebase
pub const SemanticChange = struct {
    /// The entity that changed
    entity_cid: CID,
    /// Type of change
    change_type: ChangeType,
    /// Previous CID (for updates)
    previous_cid: ?CID,
    /// Timestamp of change
    timestamp: i64,
    /// Human-readable description
    description: []const u8,
    /// Severity of the change (affects invalidation priority)
    severity: ChangeSeverity,

    pub const ChangeType = enum {
        /// Entity was added
        added,
        /// Entity was modified
        modified,
        /// Entity was removed
        removed,
        /// Entity was moved/renamed
        moved,
    };

    pub const ChangeSeverity = enum {
        /// Cosmetic changes (whitespace, comments)
        cosmetic,
        /// Minor changes (variable renames, etc.)
        minor,
        /// Major changes (function signatures, types)
        major,
        /// Breaking changes (API changes, removals)
        breaking,
    };
};

/// Batch of semantic changes to process together
pub const ChangeSet = struct {
    changes: std.ArrayList(SemanticChange),
    batch_id: [16]u8, // UUID for this batch
    created_at: i64,
    allocator: Allocator,

    pub fn init(allocator: Allocator) ChangeSet {
        var batch_id: [16]u8 = undefined;
        std.crypto.random.bytes(&batch_id);

        return ChangeSet{
            .changes = std.ArrayList(SemanticChange).init(allocator),
            .batch_id = batch_id,
            .created_at = std.time.milliTimestamp(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ChangeSet) void {
        self.changes.deinit();
    }

    pub fn addChange(self: *ChangeSet, change: SemanticChange) !void {
        try self.changes.append(change);
    }

    /// Get all unique entities affected by this change set
    pub fn getAffectedEntities(self: ChangeSet) ![]CID {
        var entities = std.ArrayList(CID).init(self.allocator);
        defer entities.deinit();

        for (self.changes.items) |change| {
            // Check for duplicates
            var found = false;
            for (entities.items) |entity| {
                if (std.mem.eql(u8, &entity, &change.entity_cid)) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                try entities.append(change.entity_cid);
            }
        }

        return entities.toOwnedSlice();
    }
};

/// Result of an invalidation operation
pub const InvalidationResult = struct {
    /// Number of queries invalidated
    queries_invalidated: u32,
    /// Number of cache entries removed
    cache_entries_removed: u32,
    /// Time taken for invalidation (microseconds)
    invalidation_time_us: u64,
    /// Queries that were invalidated
    invalidated_queries: []MemoKey,
    /// Changes that triggered invalidation
    triggering_changes: []SemanticChange,

    pub fn deinit(self: *InvalidationResult, allocator: Allocator) void {
        allocator.free(self.invalidated_queries);
        allocator.free(self.triggering_changes);
    }
};

/// The main invalidation engine
pub const InvalidationEngine = struct {
    /// Dependency tracker for finding affected queries
    dependency_tracker: *DependencyTracker,
    /// Memo table for removing cached results
    memo_table: *MemoTable,
    /// Allocator
    allocator: Allocator,
    /// Statistics
    stats: EngineStats,
    /// Configuration
    config: EngineConfig,

    const EngineStats = struct {
        total_invalidations: u64 = 0,
        total_queries_invalidated: u64 = 0,
        total_cache_entries_removed: u64 = 0,
        average_invalidation_time_us: f64 = 0.0,
        precision_ratio: f64 = 1.0, // Ratio of precise to total invalidations
    };

    const EngineConfig = struct {
        /// Maximum time to spend on invalidation (microseconds)
        max_invalidation_time_us: u64 = 10_000, // 10ms
        /// Whether to perform deep dependency analysis
        deep_analysis: bool = true,
        /// Whether to batch invalidations for efficiency
        batch_invalidations: bool = true,
        /// Minimum severity level to trigger invalidation
        min_severity: SemanticChange.ChangeSeverity = .minor,
    };

    pub fn init(allocator: Allocator, dependency_tracker: *DependencyTracker, memo_table: *MemoTable) InvalidationEngine {
        return InvalidationEngine{
            .dependency_tracker = dependency_tracker,
            .memo_table = memo_table,
            .allocator = allocator,
            .stats = EngineStats{},
            .config = EngineConfig{},
        };
    }

    /// Process a single semantic change
    pub fn processChange(self: *InvalidationEngine, change: SemanticChange) !InvalidationResult {
        var change_set = ChangeSet.init(self.allocator);
        defer change_set.deinit();

        try change_set.addChange(change);
        return self.processChangeSet(change_set);
    }

    /// Process a batch of semantic changes
    pub fn processChangeSet(self: *InvalidationEngine, change_set: ChangeSet) !InvalidationResult {
        const start_time = std.time.microTimestamp();

        var invalidated_queries = std.ArrayList(MemoKey).init(self.allocator);
        var cache_entries_removed: u32 = 0;

        // Process each change in the set
        for (change_set.changes.items) |change| {
            // Skip changes below minimum severity threshold
            if (@enumToInt(change.severity) < @enumToInt(self.config.min_severity)) {
                continue;
            }

            // Determine if this is a semantic change that affects queries
            if (self.isSemanticChange(change)) {
                // Find affected queries through dependency tracking
                const affected = try self.dependency_tracker.findAffectedQueries(change.entity_cid);
                defer self.allocator.free(affected);

                // Invalidate each affected query
                for (affected) |memo_key| {
                    if (self.memo_table.remove(memo_key)) {
                        cache_entries_removed += 1;
                    }

                    // Add to invalidated list (check for duplicates)
                    var found = false;
                    for (invalidated_queries.items) |existing| {
                        if (existing.eql(memo_key)) {
                            found = true;
                            break;
                        }
                    }

                    if (!found) {
                        try invalidated_queries.append(memo_key);
                    }
                }
            }

            // If this is a removal, clean up dependencies
            if (change.change_type == .removed) {
                self.dependency_tracker.removeEntity(change.entity_cid);
            }
        }

        const end_time = std.time.microTimestamp();
        const invalidation_time = @intCast(u64, end_time - start_time);

        // Update statistics
        self.updateStats(invalidated_queries.items.len, cache_entries_removed, invalidation_time);

        // Create result
        const result = InvalidationResult{
            .queries_invalidated = @intCast(u32, invalidated_queries.items.len),
            .cache_entries_removed = cache_entries_removed,
            .invalidation_time_us = invalidation_time,
            .invalidated_queries = invalidated_queries.toOwnedSlice(),
            .triggering_changes = try self.allocator.dupe(SemanticChange, change_set.changes.items),
        };

        return result;
    }

    /// Determine if a change is semantic (affects query results)
    fn isSemanticChange(self: *InvalidationEngine, change: SemanticChange) bool {
        _ = self;

        return switch (change.severity) {
            .cosmetic => false, // Whitespace, comments don't affect semantics
            .minor, .major, .breaking => true,
        };
    }

    /// Update engine statistics
    fn updateStats(self: *InvalidationEngine, queries_invalidated: usize, cache_entries_removed: u32, time_us: u64) void {
        self.stats.total_invalidations += 1;
        self.stats.total_queries_invalidated += @intCast(u64, queries_invalidated);
        self.stats.total_cache_entries_removed += cache_entries_removed;

        // Update running average of invalidation time
        const total_ops = self.stats.total_invalidations;
        const old_avg = self.stats.average_invalidation_time_us;
        self.stats.average_invalidation_time_us = (old_avg * @intToFloat(f64, total_ops - 1) + @intToFloat(f64, time_us)) / @intToFloat(f64, total_ops);

        // Calculate precision ratio (precise invalidations / total invalidations)
        // This measures how well we're avoiding unnecessary invalidations
        if (queries_invalidated > 0) {
            self.stats.precision_ratio = @intToFloat(f64, self.stats.total_queries_invalidated) / @intToFloat(f64, self.stats.total_invalidations);
        }
    }

    /// Get current engine statistics
    pub fn getStats(self: InvalidationEngine) EngineStats {
        return self.stats;
    }

    /// Configure the invalidation engine
    pub fn configure(self: *InvalidationEngine, config: EngineConfig) void {
        self.config = config;
    }

    /// Perform a full invalidation (nuclear option)
    pub fn invalidateAll(self: *InvalidationEngine) !InvalidationResult {
        const start_time = std.time.microTimestamp();

        // Clear all cached queries
        const cache_stats = self.memo_table.getStats();
        const queries_invalidated = cache_stats.total_entries;

        self.memo_table.clear();
        self.dependency_tracker.clear();

        const end_time = std.time.microTimestamp();
        const invalidation_time = @intCast(u64, end_time - start_time);

        self.updateStats(queries_invalidated, queries_invalidated, invalidation_time);

        return InvalidationResult{
            .queries_invalidated = queries_invalidated,
            .cache_entries_removed = queries_invalidated,
            .invalidation_time_us = invalidation_time,
            .invalidated_queries = &[_]MemoKey{}, // Empty for full invalidation
            .triggering_changes = &[_]SemanticChange{}, // Empty for full invalidation
        };
    }
};

/// Utility functions for creating semantic changes
pub const ChangeBuilder = struct {
    /// Create a file content change
    pub fn fileContentChanged(file_cid: CID, description: []const u8) SemanticChange {
        return SemanticChange{
            .entity_cid = file_cid,
            .change_type = .modified,
            .previous_cid = null,
            .timestamp = std.time.milliTimestamp(),
            .description = description,
            .severity = .major,
        };
    }

    /// Create a symbol definition change
    pub fn symbolDefinitionChanged(symbol_cid: CID, previous_cid: CID, description: []const u8) SemanticChange {
        return SemanticChange{
            .entity_cid = symbol_cid,
            .change_type = .modified,
            .previous_cid = previous_cid,
            .timestamp = std.time.milliTimestamp(),
            .description = description,
            .severity = .major,
        };
    }

    /// Create a function signature change
    pub fn functionSignatureChanged(func_cid: CID, previous_cid: CID, description: []const u8) SemanticChange {
        return SemanticChange{
            .entity_cid = func_cid,
            .change_type = .modified,
            .previous_cid = previous_cid,
            .timestamp = std.time.milliTimestamp(),
            .description = description,
            .severity = .breaking,
        };
    }

    /// Create an entity removal change
    pub fn entityRemoved(entity_cid: CID, description: []const u8) SemanticChange {
        return SemanticChange{
            .entity_cid = entity_cid,
            .change_type = .removed,
            .previous_cid = null,
            .timestamp = std.time.milliTimestamp(),
            .description = description,
            .severity = .breaking,
        };
    }

    /// Create a cosmetic change (should not trigger invalidation)
    pub fn cosmeticChange(entity_cid: CID, description: []const u8) SemanticChange {
        return SemanticChange{
            .entity_cid = entity_cid,
            .change_type = .modified,
            .previous_cid = null,
            .timestamp = std.time.milliTimestamp(),
            .description = description,
            .severity = .cosmetic,
        };
    }
};

// Tests
test "InvalidationEngine basic operation" {
    const allocator = std.testing.allocator;

    var dependency_tracker = try DependencyTracker.init(allocator);
    defer dependency_tracker.deinit();

    var memo_table = try MemoTable.init(allocator);
    defer memo_table.deinit();

    var engine = InvalidationEngine.init(allocator, &dependency_tracker, &memo_table);

    const entity_cid = CID{ .bytes = [_]u8{1} ** 32 };
    const change = ChangeBuilder.fileContentChanged(entity_cid, "test file modified");

    const result = try engine.processChange(change);
    defer {
        var mut_result = result;
        mut_result.deinit(allocator);
    }

    try std.testing.expect(result.invalidation_time_us > 0);
}

test "ChangeSet operations" {
    const allocator = std.testing.allocator;

    var change_set = ChangeSet.init(allocator);
    defer change_set.deinit();

    const entity_cid = CID{ .bytes = [_]u8{1} ** 32 };
    const change = ChangeBuilder.fileContentChanged(entity_cid, "test change");

    try change_set.addChange(change);
    try std.testing.expect(change_set.changes.items.len == 1);

    const affected = try change_set.getAffectedEntities();
    defer allocator.free(affected);

    try std.testing.expect(affected.len == 1);
    try std.testing.expect(std.mem.eql(u8, &affected[0].bytes, &entity_cid.bytes));
}

test "Cosmetic changes do not trigger invalidation" {
    const allocator = std.testing.allocator;

    var dependency_tracker = try DependencyTracker.init(allocator);
    defer dependency_tracker.deinit();

    var memo_table = try MemoTable.init(allocator);
    defer memo_table.deinit();

    var engine = InvalidationEngine.init(allocator, &dependency_tracker, &memo_table);

    const entity_cid = CID{ .bytes = [_]u8{1} ** 32 };
    const cosmetic_change = ChangeBuilder.cosmeticChange(entity_cid, "whitespace change");

    const result = try engine.processChange(cosmetic_change);
    defer {
        var mut_result = result;
        mut_result.deinit(allocator);
    }

    // Cosmetic changes should not invalidate anything
    try std.testing.expect(result.queries_invalidated == 0);
}

test "Change severity filtering" {
    const allocator = std.testing.allocator;

    var dependency_tracker = try DependencyTracker.init(allocator);
    defer dependency_tracker.deinit();

    var memo_table = try MemoTable.init(allocator);
    defer memo_table.deinit();

    var engine = InvalidationEngine.init(allocator, &dependency_tracker, &memo_table);

    // Configure to only process major changes
    engine.configure(InvalidationEngine.EngineConfig{
        .min_severity = .major,
        .max_invalidation_time_us = 10_000,
        .deep_analysis = true,
        .batch_invalidations = true,
    });

    const entity_cid = CID{ .bytes = [_]u8{1} ** 32 };

    // Create a minor change (should be ignored)
    var minor_change = ChangeBuilder.fileContentChanged(entity_cid, "minor change");
    minor_change.severity = .minor;

    const result = try engine.processChange(minor_change);
    defer {
        var mut_result = result;
        mut_result.deinit(allocator);
    }

    // Should not invalidate anything due to severity filter
    try std.testing.expect(result.queries_invalidated == 0);
}
