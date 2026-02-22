// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const DispatchTableGenerator = @import("dispatch_table_generator.zig").DispatchTableGenerator;

/// RuntimeDispatch - High-performance runtime dispatch engine with caching
///
/// This engine provides O(1) dispatch for common cases and O(log n) dispatch for
/// complex subtype relationships. It includes an LRU cache for recent dispatch
/// decisions and comprehensive performance monitoring.
pub const RuntimeDispatch = struct {
    /// Dispatch cache with LRU eviction policy
    pub const DispatchCache = struct {
        /// Cache entry linking dispatch key to resolved function
        pub const CacheEntry = struct {
            key: CacheKey,
            function_id: SignatureAnalyzer.FunctionId,
            hit_count: u32,
            last_access_time: u64,

            pub fn init(key: CacheKey, function_id: SignatureAnalyzer.FunctionId, timestamp: u64) CacheEntry {
                return CacheEntry{
                    .key = key,
                    .function_id = function_id,
                    .hit_count = 1,
                    .last_access_time = timestamp,
                };
            }
        };

        /// Cache key combining signature and argument types
        pub const CacheKey = struct {
            signature_hash: u64,
            arg_type_hash: u64,

            pub fn init(signature_hash: u64, arg_types: []const TypeRegistry.TypeId) CacheKey {
                var hasher = std.hash.Wyhash.init(0);
                for (arg_types) |type_id| {
                    hasher.update(std.mem.asBytes(&type_id));
                }

                return CacheKey{
                    .signature_hash = signature_hash,
                    .arg_type_hash = hasher.final(),
                };
            }

            pub fn hash(self: CacheKey) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hasher.update(std.mem.asBytes(&self.signature_hash));
                hasher.update(std.mem.asBytes(&self.arg_type_hash));
                return hasher.final();
            }

            pub fn eql(self: CacheKey, other: CacheKey) bool {
                return self.signature_hash == other.signature_hash and
                    self.arg_type_hash == other.arg_type_hash;
            }
        };

        /// Context for CacheKey HashMap
        pub const CacheKeyContext = struct {
            pub fn hash(self: @This(), key: CacheKey) u64 {
                _ = self;
                return key.hash();
            }

            pub fn eql(self: @This(), a: CacheKey, b: CacheKey) bool {
                _ = self;
                return a.eql(b);
            }
        };

        entries: std.HashMap(CacheKey, CacheEntry, CacheKeyContext, std.hash_map.default_max_load_percentage),
        lru_list: std.DoublyLinkedList(CacheKey),
        max_size: usize,
        allocator: std.mem.Allocator,

        // Statistics
        hits: u64,
        misses: u64,
        evictions: u64,

        pub fn init(allocator: std.mem.Allocator, max_size: usize) DispatchCache {
            return DispatchCache{
                .entries = std.HashMap(CacheKey, CacheEntry, CacheKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
                .lru_list = std.DoublyLinkedList(CacheKey){},
                .max_size = max_size,
                .allocator = allocator,
                .hits = 0,
                .misses = 0,
                .evictions = 0,
            };
        }

        pub fn deinit(self: *DispatchCache) void {
            // Clean up LRU list nodes
            while (self.lru_list.pop()) |node| {
                self.allocator.destroy(node);
            }
            self.entries.deinit();
        }

        /// Get cached dispatch result
        pub fn get(self: *DispatchCache, key: CacheKey, timestamp: u64) ?SignatureAnalyzer.FunctionId {
            if (self.entries.getPtr(key)) |entry| {
                self.hits += 1;
                entry.hit_count += 1;
                entry.last_access_time = timestamp;
                self.moveToFront(key);
                return entry.function_id;
            }

            self.misses += 1;
            return null;
        }

        /// Cache a dispatch result
        pub fn put(self: *DispatchCache, key: CacheKey, function_id: SignatureAnalyzer.FunctionId, timestamp: u64) !void {
            // Check if already exists
            if (self.entries.contains(key)) {
                // Update existing entry
                if (self.entries.getPtr(key)) |entry| {
                    entry.function_id = function_id;
                    entry.last_access_time = timestamp;
                    self.moveToFront(key);
                }
                return;
            }

            // Evict if at capacity
            if (self.entries.count() >= self.max_size) {
                try self.evictLRU();
            }

            // Add new entry
            const entry = CacheEntry.init(key, function_id, timestamp);
            try self.entries.put(key, entry);

            // Add to front of LRU list
            const node = try self.allocator.create(std.DoublyLinkedList(CacheKey).Node);
            node.data = key;
            self.lru_list.prepend(node);
        }

        /// Move cache key to front of LRU list
        fn moveToFront(self: *DispatchCache, key: CacheKey) void {
            // Find and remove the node
            var current = self.lru_list.first;
            while (current) |node| {
                if (node.data.eql(key)) {
                    self.lru_list.remove(node);
                    self.lru_list.prepend(node);
                    break;
                }
                current = node.next;
            }
        }

        /// Evict least recently used entry
        fn evictLRU(self: *DispatchCache) !void {
            if (self.lru_list.pop()) |node| {
                _ = self.entries.remove(node.data);
                self.allocator.destroy(node);
                self.evictions += 1;
            }
        }

        /// Get cache statistics
        pub fn getStats(self: *const DispatchCache) CacheStats {
            const total_requests = self.hits + self.misses;
            const hit_rate = if (total_requests > 0)
                @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total_requests))
            else
                0.0;

            return CacheStats{
                .hits = self.hits,
                .misses = self.misses,
                .evictions = self.evictions,
                .hit_rate = hit_rate,
                .current_size = self.entries.count(),
                .max_size = self.max_size,
            };
        }

        pub const CacheStats = struct {
            hits: u64,
            misses: u64,
            evictions: u64,
            hit_rate: f32,
            current_size: usize,
            max_size: usize,
        };
    };

    /// Performance monitoring and tracing
    pub const PerformanceMonitor = struct {
        /// Dispatch timing record
        pub const DispatchTiming = struct {
            signature_hash: u64,
            arg_type_count: u32,
            dispatch_time_ns: u64,
            cache_hit: bool,
            tree_depth_traversed: u32,
            timestamp: u64,
        };

        timings: std.ArrayList(DispatchTiming),
        total_dispatches: u64,
        total_time_ns: u64,
        max_time_ns: u64,
        min_time_ns: u64,
        allocator: std.mem.Allocator,

        // Configuration
        max_timing_records: usize = 10000,
        enable_detailed_tracing: bool = false,

        pub fn init(allocator: std.mem.Allocator) PerformanceMonitor {
            return PerformanceMonitor{
                .timings = .empty,
                .total_dispatches = 0,
                .total_time_ns = 0,
                .max_time_ns = 0,
                .min_time_ns = std.math.maxInt(u64),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *PerformanceMonitor) void {
            self.timings.deinit();
        }

        /// Record a dispatch timing
        pub fn recordDispatch(
            self: *PerformanceMonitor,
            signature_hash: u64,
            arg_type_count: u32,
            dispatch_time_ns: u64,
            cache_hit: bool,
            tree_depth_traversed: u32,
        ) !void {
            self.total_dispatches += 1;
            self.total_time_ns += dispatch_time_ns;
            self.max_time_ns = @max(self.max_time_ns, dispatch_time_ns);
            self.min_time_ns = @min(self.min_time_ns, dispatch_time_ns);

            if (self.enable_detailed_tracing and self.timings.items.len < self.max_timing_records) {
                try self.timings.append(DispatchTiming{
                    .signature_hash = signature_hash,
                    .arg_type_count = arg_type_count,
                    .dispatch_time_ns = dispatch_time_ns,
                    .cache_hit = cache_hit,
                    .tree_depth_traversed = tree_depth_traversed,
                    .timestamp = @intCast(std.time.milliTimestamp()),
                });
            }
        }

        /// Get performance statistics
        pub fn getStats(self: *const PerformanceMonitor) PerformanceStats {
            const avg_time_ns = if (self.total_dispatches > 0)
                self.total_time_ns / self.total_dispatches
            else
                0;

            return PerformanceStats{
                .total_dispatches = self.total_dispatches,
                .average_time_ns = avg_time_ns,
                .max_time_ns = self.max_time_ns,
                .min_time_ns = if (self.min_time_ns == std.math.maxInt(u64)) 0 else self.min_time_ns,
                .total_time_ns = self.total_time_ns,
            };
        }

        pub const PerformanceStats = struct {
            total_dispatches: u64,
            average_time_ns: u64,
            max_time_ns: u64,
            min_time_ns: u64,
            total_time_ns: u64,
        };
    };

    /// Main runtime dispatch engine
    dispatch_tables: std.HashMap(u64, DispatchTableGenerator.DispatchTable, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    cache: DispatchCache,
    performance_monitor: PerformanceMonitor,
    type_registry: *const TypeRegistry,
    allocator: std.mem.Allocator,

    // Configuration
    enable_caching: bool = true,
    enable_performance_monitoring: bool = true,
    cache_size: usize = 1024,

    pub fn init(allocator: std.mem.Allocator, type_registry: *const TypeRegistry) RuntimeDispatch {
        return RuntimeDispatch{
            .dispatch_tables = std.HashMap(u64, DispatchTableGenerator.DispatchTable, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .cache = DispatchCache.init(allocator, 1024),
            .performance_monitor = PerformanceMonitor.init(allocator),
            .type_registry = type_registry,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RuntimeDispatch) void {
        // Clean up dispatch tables
        var table_iterator = self.dispatch_tables.iterator();
        while (table_iterator.next()) |entry| {
            var table = entry.value_ptr;
            table.deinit(self.allocator);
        }
        self.dispatch_tables.deinit();

        self.cache.deinit();
        self.performance_monitor.deinit();
    }

    /// Register a dispatch table for a signature
    pub fn registerDispatchTable(self: *RuntimeDispatch, signature_hash: u64, table: DispatchTableGenerator.DispatchTable) !void {
        try self.dispatch_tables.put(signature_hash, table);
    }

    /// Perform runtime dispatch
    pub fn dispatch(
        self: *RuntimeDispatch,
        signature_hash: u64,
        arg_types: []const TypeRegistry.TypeId,
    ) ?SignatureAnalyzer.FunctionId {
        const start_time = if (self.enable_performance_monitoring) std.time.nanoTimestamp() else 0;
        var cache_hit = false;
        var tree_depth_traversed: u32 = 0;

        // Check cache first if enabled
        if (self.enable_caching) {
            const cache_key = DispatchCache.CacheKey.init(signature_hash, arg_types);
            if (self.cache.get(cache_key, @intCast(std.time.milliTimestamp()))) |cached_result| {
                cache_hit = true;

                if (self.enable_performance_monitoring) {
                    const end_time = std.time.nanoTimestamp();
                    const dispatch_time = @as(u64, @intCast(end_time - start_time));
                    self.performance_monitor.recordDispatch(
                        signature_hash,
                        @intCast(arg_types.len),
                        dispatch_time,
                        cache_hit,
                        tree_depth_traversed,
                    ) catch {};
                }

                return cached_result;
            }
        }

        // Lookup in dispatch table
        const result = self.lookupInTable(signature_hash, arg_types, &tree_depth_traversed);

        // Cache the result if found and caching is enabled
        if (result != null and self.enable_caching) {
            const cache_key = DispatchCache.CacheKey.init(signature_hash, arg_types);
            self.cache.put(cache_key, result.?, @intCast(std.time.milliTimestamp())) catch {};
        }

        // Record performance metrics
        if (self.enable_performance_monitoring) {
            const end_time = std.time.nanoTimestamp();
            const dispatch_time = @as(u64, @intCast(end_time - start_time));
            self.performance_monitor.recordDispatch(
                signature_hash,
                @intCast(arg_types.len),
                dispatch_time,
                cache_hit,
                tree_depth_traversed,
            ) catch {};
        }

        return result;
    }

    /// Lookup function in dispatch table
    fn lookupInTable(
        self: *RuntimeDispatch,
        signature_hash: u64,
        arg_types: []const TypeRegistry.TypeId,
        tree_depth: *u32,
    ) ?SignatureAnalyzer.FunctionId {
        const table = self.dispatch_tables.get(signature_hash) orelse return null;

        // Try exact match first
        const type_combo = DispatchTableGenerator.TypeCombination{ .types = arg_types };
        const combo_hash = type_combo.hash();

        // Binary search in sorted exact matches
        if (self.binarySearchExactMatch(table.exact_matches, combo_hash)) |function_id| {
            return function_id;
        }

        // Fall back to decision tree for subtype matching
        if (table.decision_tree) |tree| {
            return self.traverseDecisionTree(tree, arg_types, tree_depth);
        }

        return null;
    }

    /// Binary search in exact match table
    fn binarySearchExactMatch(
        self: *RuntimeDispatch,
        exact_matches: []const DispatchTableGenerator.DispatchTable.ExactMatch,
        target_hash: u64,
    ) ?SignatureAnalyzer.FunctionId {
        _ = self;

        var left: usize = 0;
        var right: usize = exact_matches.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const mid_hash = exact_matches[mid].type_combination_hash;

            if (mid_hash == target_hash) {
                return exact_matches[mid].function_id;
            } else if (mid_hash < target_hash) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        return null;
    }

    /// Traverse decision tree for subtype-based dispatch
    fn traverseDecisionTree(
        self: *RuntimeDispatch,
        tree: *const DispatchTableGenerator.DispatchTable.DecisionTree,
        arg_types: []const TypeRegistry.TypeId,
        depth: *u32,
    ) ?SignatureAnalyzer.FunctionId {
        depth.* += 1;

        // If we've reached a leaf or exhausted parameters
        if (tree.param_index >= arg_types.len or tree.type_branches.count() == 0) {
            return tree.leaf_function;
        }

        const arg_type = arg_types[tree.param_index];

        // Try exact type match first
        if (tree.type_branches.get(arg_type)) |subtree| {
            if (self.traverseDecisionTree(subtree, arg_types, depth)) |result| {
                return result;
            }
        }

        // Try subtype matches
        var iterator = tree.type_branches.iterator();
        while (iterator.next()) |entry| {
            const branch_type = entry.key_ptr.*;
            if (self.type_registry.isSubtype(arg_type, branch_type)) {
                if (self.traverseDecisionTree(entry.value_ptr.*, arg_types, depth)) |result| {
                    return result;
                }
            }
        }

        // Return leaf function if no specific match found
        return tree.leaf_function;
    }

    /// Get comprehensive runtime statistics
    pub fn getStatistics(self: *const RuntimeDispatch) RuntimeStats {
        return RuntimeStats{
            .cache_stats = self.cache.getStats(),
            .performance_stats = self.performance_monitor.getStats(),
            .table_count = self.dispatch_tables.count(),
            .total_memory_bytes = self.calculateTotalMemoryUsage(),
        };
    }

    /// Calculate total memory usage
    fn calculateTotalMemoryUsage(self: *const RuntimeDispatch) usize {
        var total: usize = 0;

        // Cache memory
        total += self.cache.entries.count() * @sizeOf(DispatchCache.CacheEntry);

        // Dispatch tables memory
        var table_iterator = self.dispatch_tables.iterator();
        while (table_iterator.next()) |entry| {
            total += entry.value_ptr.metadata.total_memory_bytes;
        }

        // Performance monitor memory
        total += self.performance_monitor.timings.items.len * @sizeOf(PerformanceMonitor.DispatchTiming);

        return total;
    }

    /// Clear all caches and reset statistics
    pub fn reset(self: *RuntimeDispatch) void {
        self.cache.entries.clearAndFree();
        while (self.cache.lru_list.pop()) |node| {
            self.allocator.destroy(node);
        }
        self.cache.hits = 0;
        self.cache.misses = 0;
        self.cache.evictions = 0;

        self.performance_monitor.timings.clearAndFree();
        self.performance_monitor.total_dispatches = 0;
        self.performance_monitor.total_time_ns = 0;
        self.performance_monitor.max_time_ns = 0;
        self.performance_monitor.min_time_ns = std.math.maxInt(u64);
    }

    /// Enable or disable performance monitoring
    pub fn setPerformanceMonitoring(self: *RuntimeDispatch, enabled: bool) void {
        self.enable_performance_monitoring = enabled;
        self.performance_monitor.enable_detailed_tracing = enabled;
    }

    /// Configure cache size
    pub fn setCacheSize(self: *RuntimeDispatch, size: usize) void {
        self.cache_size = size;
        self.cache.max_size = size;

        // Evict entries if current size exceeds new limit
        while (self.cache.entries.count() > size) {
            self.cache.evictLRU() catch break;
        }
    }

    pub const RuntimeStats = struct {
        cache_stats: DispatchCache.CacheStats,
        performance_stats: PerformanceMonitor.PerformanceStats,
        table_count: usize,
        total_memory_bytes: usize,
    };
};

// ===== TESTS =====

test "RuntimeDispatch basic dispatch" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var runtime_dispatch = RuntimeDispatch.init(std.testing.allocator, &type_registry);
    defer runtime_dispatch.deinit();

    // Create a simple dispatch table
    var table = DispatchTableGenerator.DispatchTable{
        .signature_hash = 12345,
        .implementation_count = 1,
        .exact_matches = try std.testing.allocator.alloc(DispatchTableGenerator.DispatchTable.ExactMatch, 1),
        .decision_tree = null,
        .metadata = DispatchTableGenerator.DispatchTable.TableMetadata{
            .total_memory_bytes = 100,
            .exact_match_coverage = 1.0,
            .max_tree_depth = 0,
            .cache_efficiency_estimate = 1.0,
        },
    };

    const i32_id = type_registry.getTypeId("i32").?;
    var arg_types = [_]TypeRegistry.TypeId{i32_id};
    const type_combo = DispatchTableGenerator.TypeCombination{ .types = arg_types[0..] };

    table.exact_matches[0] = DispatchTableGenerator.DispatchTable.ExactMatch{
        .type_combination_hash = type_combo.hash(),
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "test", .id = 1 },
    };

    try runtime_dispatch.registerDispatchTable(12345, table);

    // Test dispatch
    const result = runtime_dispatch.dispatch(12345, &arg_types);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("test", result.?.name);
}

test "RuntimeDispatch cache functionality" {
    var cache = RuntimeDispatch.DispatchCache.init(std.testing.allocator, 2);
    defer cache.deinit();

    const key1 = RuntimeDispatch.DispatchCache.CacheKey.init(100, &[_]TypeRegistry.TypeId{1});
    const key2 = RuntimeDispatch.DispatchCache.CacheKey.init(200, &[_]TypeRegistry.TypeId{2});
    const key3 = RuntimeDispatch.DispatchCache.CacheKey.init(300, &[_]TypeRegistry.TypeId{3});

    const func1 = SignatureAnalyzer.FunctionId{ .name = "func1", .module = "test", .id = 1 };
    const func2 = SignatureAnalyzer.FunctionId{ .name = "func2", .module = "test", .id = 2 };
    const func3 = SignatureAnalyzer.FunctionId{ .name = "func3", .module = "test", .id = 3 };

    // Test cache miss
    try std.testing.expect(cache.get(key1, 1000) == null);
    try std.testing.expectEqual(@as(u64, 1), cache.misses);

    // Test cache put and hit
    try cache.put(key1, func1, 1000);
    const result1 = cache.get(key1, 1001);
    try std.testing.expect(result1 != null);
    try std.testing.expectEqualStrings("func1", result1.?.name);
    try std.testing.expectEqual(@as(u64, 1), cache.hits);

    // Test cache eviction (capacity is 2)
    try cache.put(key2, func2, 1002);
    try cache.put(key3, func3, 1003); // Should evict key1

    try std.testing.expect(cache.get(key1, 1004) == null); // Should be evicted
    try std.testing.expect(cache.get(key2, 1004) != null); // Should still be there
    try std.testing.expect(cache.get(key3, 1004) != null); // Should still be there

    const stats = cache.getStats();
    try std.testing.expect(stats.evictions > 0);
    try std.testing.expect(stats.current_size <= 2);
}

test "RuntimeDispatch performance monitoring" {
    var monitor = RuntimeDispatch.PerformanceMonitor.init(std.testing.allocator);
    defer monitor.deinit();

    monitor.enable_detailed_tracing = true;

    // Record some dispatch timings
    try monitor.recordDispatch(100, 2, 1000, false, 3);
    try monitor.recordDispatch(200, 1, 500, true, 0);
    try monitor.recordDispatch(100, 2, 1500, false, 2);

    const stats = monitor.getStats();
    try std.testing.expectEqual(@as(u64, 3), stats.total_dispatches);
    try std.testing.expectEqual(@as(u64, 3000), stats.total_time_ns);
    try std.testing.expectEqual(@as(u64, 1000), stats.average_time_ns);
    try std.testing.expectEqual(@as(u64, 1500), stats.max_time_ns);
    try std.testing.expectEqual(@as(u64, 500), stats.min_time_ns);

    // Check detailed tracing
    try std.testing.expectEqual(@as(usize, 3), monitor.timings.items.len);
}

test "RuntimeDispatch cache key operations" {
    const key1 = RuntimeDispatch.DispatchCache.CacheKey.init(100, &[_]TypeRegistry.TypeId{ 1, 2 });
    const key2 = RuntimeDispatch.DispatchCache.CacheKey.init(100, &[_]TypeRegistry.TypeId{ 1, 2 });
    const key3 = RuntimeDispatch.DispatchCache.CacheKey.init(100, &[_]TypeRegistry.TypeId{ 2, 1 });

    // Same keys should be equal and have same hash
    try std.testing.expect(key1.eql(key2));
    try std.testing.expectEqual(key1.hash(), key2.hash());

    // Different keys should not be equal
    try std.testing.expect(!key1.eql(key3));
    try std.testing.expect(key1.hash() != key3.hash());
}

test "RuntimeDispatch binary search" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var runtime_dispatch = RuntimeDispatch.init(std.testing.allocator, &type_registry);
    defer runtime_dispatch.deinit();

    // Create sorted exact matches
    var exact_matches = [_]DispatchTableGenerator.DispatchTable.ExactMatch{
        .{ .type_combination_hash = 100, .function_id = .{ .name = "func1", .module = "test", .id = 1 } },
        .{ .type_combination_hash = 200, .function_id = .{ .name = "func2", .module = "test", .id = 2 } },
        .{ .type_combination_hash = 300, .function_id = .{ .name = "func3", .module = "test", .id = 3 } },
    };

    // Test successful searches
    const result1 = runtime_dispatch.binarySearchExactMatch(&exact_matches, 100);
    try std.testing.expect(result1 != null);
    try std.testing.expectEqualStrings("func1", result1.?.name);

    const result2 = runtime_dispatch.binarySearchExactMatch(&exact_matches, 200);
    try std.testing.expect(result2 != null);
    try std.testing.expectEqualStrings("func2", result2.?.name);

    const result3 = runtime_dispatch.binarySearchExactMatch(&exact_matches, 300);
    try std.testing.expect(result3 != null);
    try std.testing.expectEqualStrings("func3", result3.?.name);

    // Test unsuccessful search
    const result4 = runtime_dispatch.binarySearchExactMatch(&exact_matches, 150);
    try std.testing.expect(result4 == null);
}

test "RuntimeDispatch statistics and configuration" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var runtime_dispatch = RuntimeDispatch.init(std.testing.allocator, &type_registry);
    defer runtime_dispatch.deinit();

    // Test initial statistics
    const initial_stats = runtime_dispatch.getStatistics();
    try std.testing.expectEqual(@as(usize, 0), initial_stats.table_count);
    try std.testing.expectEqual(@as(f32, 0.0), initial_stats.cache_stats.hit_rate);

    // Test configuration changes
    runtime_dispatch.setPerformanceMonitoring(false);
    try std.testing.expect(!runtime_dispatch.enable_performance_monitoring);

    runtime_dispatch.setCacheSize(512);
    try std.testing.expectEqual(@as(usize, 512), runtime_dispatch.cache_size);
    try std.testing.expectEqual(@as(usize, 512), runtime_dispatch.cache.max_size);

    // Test reset
    runtime_dispatch.reset();
    const reset_stats = runtime_dispatch.getStatistics();
    try std.testing.expectEqual(@as(u64, 0), reset_stats.performance_stats.total_dispatches);
}

test "RuntimeDispatch memory usage calculation" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var runtime_dispatch = RuntimeDispatch.init(std.testing.allocator, &type_registry);
    defer runtime_dispatch.deinit();

    // Add some cache entries
    const key = RuntimeDispatch.DispatchCache.CacheKey.init(100, &[_]TypeRegistry.TypeId{1});
    const func = SignatureAnalyzer.FunctionId{ .name = "test", .module = "test", .id = 1 };
    try runtime_dispatch.cache.put(key, func, 1000);

    // Record some performance data
    try runtime_dispatch.performance_monitor.recordDispatch(100, 1, 1000, false, 0);

    const memory_usage = runtime_dispatch.calculateTotalMemoryUsage();
    try std.testing.expect(memory_usage > 0);

    const stats = runtime_dispatch.getStatistics();
    try std.testing.expectEqual(memory_usage, stats.total_memory_bytes);
}
