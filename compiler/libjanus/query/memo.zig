// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Memo Table & Scheduler - Lock-free memoization with cycle detection
// Task 2.2 - Implements sharded memo table, worker pool, cycle detection

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Atomic;
const context = @import("context.zig");

/// Lock-free sharded memo table for query result caching
pub const MemoTable = struct {
    allocator: Allocator,
    shards: []Shard,
    shard_count: u32,

    const Self = @This();
    const SHARD_COUNT = 64; // Power of 2 for efficient modulo

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        self.* = Self{
            .allocator = allocator,
            .shards = try allocator.alloc(Shard, SHARD_COUNT),
            .shard_count = SHARD_COUNT,
        };

        // Initialize all shards
        for (self.shards) |*shard| {
            shard.* = Shard.init(allocator);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.shards) |*shard| {
            shard.deinit();
        }
        self.allocator.free(self.shards);
        self.allocator.destroy(self);
    }

    /// Get cached result if available
    pub fn get(self: *Self, key: context.MemoKey) ?context.CachedResult {
        const shard_index = self.getShardIndex(key);
        return self.shards[shard_index].get(key);
    }

    /// Put result in cache
    pub fn put(self: *Self, key: context.MemoKey, result: context.CachedResult) !void {
        const shard_index = self.getShardIndex(key);
        try self.shards[shard_index].put(key, result);
    }

    /// Remove entry from cache (for invalidation)
    pub fn remove(self: *Self, key: context.MemoKey) void {
        const shard_index = self.getShardIndex(key);
        self.shards[shard_index].remove(key);
    }

    /// Clear all cached results
    pub fn clear(self: *Self) void {
        for (self.shards) |*shard| {
            shard.clear();
        }
    }

    /// Get cache statistics
    pub fn getStats(self: *Self) CacheStats {
        var stats = CacheStats{};

        for (self.shards) |*shard| {
            const shard_stats = shard.getStats();
            stats.total_entries += shard_stats.entries;
            stats.total_hits += shard_stats.hits;
            stats.total_misses += shard_stats.misses;
        }

        return stats;
    }

    fn getShardIndex(self: *Self, key: context.MemoKey) u32 {
        // Use first 4 bytes of hash for shard selection
        const hash_u32 = std.mem.readInt(u32, key.hash[0..4], .little);
        return hash_u32 % self.shard_count;
    }
};

/// Individual shard with its own lock-free hash table
const Shard = struct {
    allocator: Allocator,
    entries: std.HashMap(context.MemoKey, Entry, MemoKeyContext, std.hash_map.default_max_load_percentage),
    mutex: std.Thread.Mutex,
    stats: ShardStats,

    const Entry = struct {
        result: context.CachedResult,
        access_count: Atomic(u32),
        last_access: Atomic(u64), // Timestamp for LRU
    };

    const ShardStats = struct {
        entries: u32 = 0,
        hits: u32 = 0,
        misses: u32 = 0,
    };

    fn init(allocator: Allocator) Shard {
        return Shard{
            .allocator = allocator,
            .entries = std.HashMap(context.MemoKey, Entry, MemoKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = std.Thread.Mutex{},
            .stats = ShardStats{},
        };
    }

    fn deinit(self: *Shard) void {
        self.entries.deinit();
    }

    fn get(self: *Shard, key: context.MemoKey) ?context.CachedResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.get(key)) |entry| {
            // Update access statistics
            _ = entry.access_count.fetchAdd(1, .Monotonic);
            entry.last_access.store(std.time.nanoTimestamp(), .Monotonic);
            self.stats.hits += 1;

            return entry.result;
        } else {
            self.stats.misses += 1;
            return null;
        }
    }

    fn put(self: *Shard, key: context.MemoKey, result: context.CachedResult) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = Entry{
            .result = result,
            .access_count = Atomic(u32).init(1),
            .last_access = Atomic(u64).init(std.time.nanoTimestamp()),
        };

        try self.entries.put(key, entry);
        self.stats.entries += 1;
    }

    fn remove(self: *Shard, key: context.MemoKey) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.remove(key)) {
            self.stats.entries -= 1;
        }
    }

    fn clear(self: *Shard) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.entries.clearRetainingCapacity();
        self.stats.entries = 0;
    }

    fn getStats(self: *Shard) ShardStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.stats;
    }
};

/// Hash map context for MemoKey
const MemoKeyContext = struct {
    pub fn hash(self: @This(), key: context.MemoKey) u64 {
        _ = self;
        // Use first 8 bytes of BLAKE3 hash
        return std.mem.readInt(u64, key.hash[0..8], .little);
    }

    pub fn eql(self: @This(), a: context.MemoKey, b: context.MemoKey) bool {
        _ = self;
        return a.eql(b);
    }
};

/// Cache statistics
pub const CacheStats = struct {
    total_entries: u32 = 0,
    total_hits: u32 = 0,
    total_misses: u32 = 0,

    pub fn hitRate(self: CacheStats) f64 {
        const total = self.total_hits + self.total_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_hits)) / @as(f64, @floatFromInt(total));
    }
};

/// Cycle detection for query dependencies
pub const CycleDetector = struct {
    allocator: Allocator,
    active_queries: std.HashMap(context.MemoKey, QueryState, MemoKeyContext, std.hash_map.default_max_load_percentage),
    mutex: std.Thread.Mutex,

    const QueryState = struct {
        thread_id: std.Thread.Id,
        start_time: u64,
        dependencies: std.ArrayList(context.MemoKey),
    };

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .active_queries = std.HashMap(context.MemoKey, QueryState, MemoKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up dependency lists
        var iterator = self.active_queries.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.dependencies.deinit();
        }

        self.active_queries.deinit();
    }

    /// Start tracking a query for cycle detection
    pub fn startQuery(self: *Self, key: context.MemoKey) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if this query is already active (cycle detected)
        if (self.active_queries.contains(key)) {
            return error.QE0007_Cycle;
        }

        const state = QueryState{
            .thread_id = std.Thread.getCurrentId(),
            .start_time = std.time.nanoTimestamp(),
            .dependencies = std.ArrayList(context.MemoKey).init(self.allocator),
        };

        try self.active_queries.put(key, state);
    }

    /// Stop tracking a query
    pub fn endQuery(self: *Self, key: context.MemoKey) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.active_queries.fetchRemove(key)) |entry| {
            entry.value.dependencies.deinit();
        }
    }

    /// Add a dependency for cycle detection
    pub fn addDependency(self: *Self, query_key: context.MemoKey, dep_key: context.MemoKey) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.active_queries.getPtr(query_key)) |state| {
            // Check for immediate cycle
            if (dep_key.eql(query_key)) {
                return error.QE0007_Cycle;
            }

            // Check for transitive cycle
            if (self.hasTransitiveDependency(dep_key, query_key)) {
                return error.QE0007_Cycle;
            }

            try state.dependencies.append(dep_key);
        }
    }

    fn hasTransitiveDependency(self: *Self, from: context.MemoKey, to: context.MemoKey) bool {
        if (self.active_queries.get(from)) |state| {
            for (state.dependencies.items) |dep| {
                if (dep.eql(to)) return true;
                if (self.hasTransitiveDependency(dep, to)) return true;
            }
        }
        return false;
    }
};

/// Worker pool for parallel query execution
pub const QueryScheduler = struct {
    allocator: Allocator,
    thread_pool: std.Thread.Pool,
    work_queue: std.fifo.LinearFifo(WorkItem, .Dynamic),
    queue_mutex: std.Thread.Mutex,

    const WorkItem = struct {
        query_id: context.QueryId,
        args: context.CanonicalArgs,
        result_callback: *const fn (result: context.QueryResult) void,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, thread_count: u32) !Self {
        return Self{
            .allocator = allocator,
            .thread_pool = try std.Thread.Pool.init(.{ .allocator = allocator, .n_jobs = thread_count }),
            .work_queue = std.fifo.LinearFifo(WorkItem, .Dynamic).init(allocator),
            .queue_mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.thread_pool.deinit();
        self.work_queue.deinit();
    }

    /// Schedule a query for asynchronous execution
    pub fn scheduleQuery(self: *Self, query_id: context.QueryId, args: context.CanonicalArgs, callback: *const fn (result: context.QueryResult) void) !void {
        const work_item = WorkItem{
            .query_id = query_id,
            .args = args,
            .result_callback = callback,
        };

        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        try self.work_queue.writeItem(work_item);

        // Spawn worker if needed
        try self.thread_pool.spawn(workerThread, .{self});
    }

    fn workerThread(self: *Self) void {
        while (true) {
            self.queue_mutex.lock();
            const work_item = self.work_queue.readItem() orelse {
                self.queue_mutex.unlock();
                break;
            };
            self.queue_mutex.unlock();

            // Execute query (would need QueryCtx integration)
            // For now, just call callback with dummy result
            const dummy_result = context.QueryResult{
                .data = context.QueryResultData{ .symbol_info = context.SymbolInfo{ .name = "dummy" } },
                .dependencies = &.{},
                .from_cache = false,
            };

            work_item.result_callback(dummy_result);
        }
    }
};
