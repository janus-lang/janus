// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const Allocator = std.mem.Allocator;

// Type system imports
const TypeId = @import("type_registry.zig").TypeId;
const DispatchEntry = @import("dispatch_table_manager.zig").DispatchEntry;
const CandidateIR = @import("ir_dispatch.zig").CandidateIR;

/// Inline cache manager for hot path dispatch optimization
pub const InlineCacheManager = struct {
    allocator: Allocator,

    // Global cache statistics for adaptive behavior
    global_stats: GlobalCacheStats,

    // Cache configuration
    config: CacheConfig,

    const CacheConfig = struct {
        initial_cache_size: u8 = 1,
        max_cache_size: u8 = 8,
        resize_threshold: f32 = 0.3, // Miss rate threshold for resizing
        hot_path_threshold: u64 = 1000, // Calls needed to be considered hot
    };

    const GlobalCacheStats = struct {
        total_caches_created: u32 = 0,
        total_cache_hits: u64 = 0,
        total_cache_misses: u64 = 0,
        total_resizes: u32 = 0,

        pub fn getHitRate(self: *const GlobalCacheStats) f32 {
            const total = self.total_cache_hits + self.total_cache_misses;
            if (total == 0) return 0.0;
            return @as(f32, @floatFromInt(self.total_cache_hits)) / @as(f32, @floatFromInt(total));
        }
    };

    pub fn init(allocator: Allocator) InlineCacheManager {
        return InlineCacheManager{
            .allocator = allocator,
            .global_stats = GlobalCacheStats{},
            .config = CacheConfig{},
        };
    }

    /// Create a new inline cache for a dispatch family
    pub fn createCache(
        self: *InlineCacheManager,
        family_name: []const u8,
        candidates: []const CandidateIR,
    ) !InlineCache {
        std.debug.print("⚡ Creating inline cache for {s} ({} candidates)\n", .{ family_name, candidates.len });

        const cache = InlineCache{
            .family_name = try self.allocator.dupe(u8, family_name),
            .entries = try self.allocator.alloc(CacheEntry, self.config.initial_cache_size),
            .cache_size = self.config.initial_cache_size,
            .max_size = self.config.max_cache_size,
            .stats = CacheStats{},
            .allocator = self.allocator,
        };

        // Initialize cache entries
        for (cache.entries) |*entry| {
            entry.* = CacheEntry{
                .type_id = TypeId{ .id = 0 }, // Invalid type ID
                .entry = null,
                .access_count = 0,
                .last_access = 0,
            };
        }

        self.global_stats.total_caches_created += 1;

        std.debug.print("✅ Inline cache created: size {}, max {}\n", .{ cache.cache_size, cache.max_size });

        return cache;
    }

    /// Get global cache statistics
    pub fn getGlobalStats(self: *const InlineCacheManager) GlobalCacheStats {
        return self.global_stats;
    }

    /// Update global statistics from a cache operation
    pub fn recordCacheHit(self: *InlineCacheManager) void {
        self.global_stats.total_cache_hits += 1;
    }

    pub fn recordCacheMiss(self: *InlineCacheManager) void {
        self.global_stats.total_cache_misses += 1;
    }

    pub fn recordCacheResize(self: *InlineCacheManager) void {
        self.global_stats.total_resizes += 1;
    }
};

/// Inline cache for a specific dispatch family
pub const InlineCache = struct {
    family_name: []const u8,
    entries: []CacheEntry,
    cache_size: u8,
    max_size: u8,
    stats: CacheStats,
    allocator: Allocator,

    /// Lookup a dispatch entry in the cache
    pub fn lookup(self: *InlineCache, type_id: TypeId) ?*const DispatchEntry {
        const timestamp = compat_time.nanoTimestamp();

        // Search cache entries
        for (self.entries, 0..) |*entry, i| {
            if (entry.entry != null and entry.type_id.equals(type_id)) {
                // Cache hit
                entry.access_count += 1;
                entry.last_access = @intCast(timestamp);
                self.stats.hits += 1;

                // Move to front (simple optimization)
                if (i > 0) {
                    const temp = self.entries[i];
                    self.entries[i] = self.entries[0];
                    self.entries[0] = temp;
                }

                return entry.entry;
            }
        }

        // Cache miss
        self.stats.misses += 1;
        return null;
    }

    /// Insert a new entry into the cache
    pub fn insert(self: *InlineCache, type_id: TypeId, entry: *const DispatchEntry) void {
        const timestamp = compat_time.nanoTimestamp();

        // Find insertion point (LRU eviction)
        var insert_index: usize = 0;
        var oldest_access: u64 = std.math.maxInt(u64);

        for (self.entries, 0..) |*cache_entry, i| {
            if (cache_entry.entry == null) {
                // Empty slot found
                insert_index = i;
                break;
            } else if (cache_entry.last_access < oldest_access) {
                // Track oldest entry for eviction
                oldest_access = cache_entry.last_access;
                insert_index = i;
            }
        }

        // Insert new entry
        self.entries[insert_index] = CacheEntry{
            .type_id = type_id,
            .entry = entry,
            .access_count = 1,
            .last_access = @intCast(timestamp),
        };

        if (oldest_access != std.math.maxInt(u64)) {
            self.stats.evictions += 1;
        }

        self.stats.insertions += 1;
    }

    /// Check if cache should be resized based on performance
    pub fn shouldResize(self: *const InlineCache) bool {
        const total_accesses = self.stats.hits + self.stats.misses;
        if (total_accesses < 100) return false; // Need sufficient data

        const miss_rate = @as(f32, @floatFromInt(self.stats.misses)) / @as(f32, @floatFromInt(total_accesses));
        const resize_threshold: f32 = 0.3; // 30% miss rate threshold

        return miss_rate > resize_threshold and self.cache_size < self.max_size;
    }

    /// Resize the cache to improve performance
    pub fn resize(self: *InlineCache, new_size: u8) !void {
        if (new_size <= self.cache_size or new_size > self.max_size) {
            return; // Invalid resize request
        }

        std.debug.print("📈 Resizing cache for {s}: {} → {}\n", .{ self.family_name, self.cache_size, new_size });

        // Create new larger cache
        const new_entries = try self.allocator.alloc(CacheEntry, new_size);

        // Initialize new entries
        for (new_entries) |*entry| {
            entry.* = CacheEntry{
                .type_id = TypeId{ .id = 0 },
                .entry = null,
                .access_count = 0,
                .last_access = 0,
            };
        }

        // Copy existing entries (keep most recently used)
        var copied: u8 = 0;
        var sorted_indices = try self.allocator.alloc(usize, self.cache_size);
        defer self.allocator.free(sorted_indices);

        // Sort by access count (descending)
        for (0..self.cache_size) |i| {
            sorted_indices[i] = i;
        }

        std.sort.insertion(usize, sorted_indices, self, compareByAccessCount);

        // Copy top entries to new cache
        for (sorted_indices) |old_index| {
            if (copied >= new_size) break;
            if (self.entries[old_index].entry != null) {
                new_entries[copied] = self.entries[old_index];
                copied += 1;
            }
        }

        // Replace old cache
        self.allocator.free(self.entries);
        self.entries = new_entries;
        self.cache_size = new_size;

        self.stats.resizes += 1;

        std.debug.print("✅ Cache resized: {} entries copied\n", .{copied});
    }

    /// Compare cache entries by access count (for sorting)
    fn compareByAccessCount(self: *const InlineCache, a: usize, b: usize) bool {
        return self.entries[a].access_count > self.entries[b].access_count;
    }

    /// Get cache performance statistics
    pub fn getStats(self: *const InlineCache) CacheStats {
        return self.stats;
    }

    /// Get cache hit rate
    pub fn getHitRate(self: *const InlineCache) f32 {
        const total = self.stats.hits + self.stats.misses;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.stats.hits)) / @as(f32, @floatFromInt(total));
    }

    /// Get cache efficiency metrics
    pub fn getEfficiencyMetrics(self: *const InlineCache) EfficiencyMetrics {
        const total_accesses = self.stats.hits + self.stats.misses;
        const hit_rate = self.getHitRate();

        return EfficiencyMetrics{
            .hit_rate = hit_rate,
            .miss_rate = 1.0 - hit_rate,
            .eviction_rate = if (total_accesses > 0)
                @as(f32, @floatFromInt(self.stats.evictions)) / @as(f32, @floatFromInt(total_accesses))
            else
                0.0,
            .utilization = self.calculateUtilization(),
            .average_access_count = self.calculateAverageAccessCount(),
        };
    }

    /// Calculate cache utilization (percentage of slots used)
    fn calculateUtilization(self: *const InlineCache) f32 {
        var used_slots: u8 = 0;
        for (self.entries) |entry| {
            if (entry.entry != null) {
                used_slots += 1;
            }
        }
        return @as(f32, @floatFromInt(used_slots)) / @as(f32, @floatFromInt(self.cache_size));
    }

    /// Calculate average access count for cached entries
    fn calculateAverageAccessCount(self: *const InlineCache) f32 {
        var total_accesses: u64 = 0;
        var used_slots: u32 = 0;

        for (self.entries) |entry| {
            if (entry.entry != null) {
                total_accesses += entry.access_count;
                used_slots += 1;
            }
        }

        if (used_slots == 0) return 0.0;
        return @as(f32, @floatFromInt(total_accesses)) / @as(f32, @floatFromInt(used_slots));
    }

    /// Clear all cache entries
    pub fn clear(self: *InlineCache) void {
        for (self.entries) |*entry| {
            entry.* = CacheEntry{
                .type_id = TypeId{ .id = 0 },
                .entry = null,
                .access_count = 0,
                .last_access = 0,
            };
        }

        self.stats.clears += 1;

        std.debug.print("🧹 Cache cleared for {s}\n", .{self.family_name});
    }

    pub fn deinit(self: *InlineCache) void {
        self.allocator.free(self.family_name);
        self.allocator.free(self.entries);
    }
};

/// Individual cache entry
pub const CacheEntry = struct {
    type_id: TypeId,
    entry: ?*const DispatchEntry,
    access_count: u32,
    last_access: u64, // Timestamp for LRU
};

/// Cache performance statistics
pub const CacheStats = struct {
    hits: u64 = 0,
    misses: u64 = 0,
    insertions: u64 = 0,
    evictions: u64 = 0,
    resizes: u32 = 0,
    clears: u32 = 0,

    pub fn reset(self: *CacheStats) void {
        self.* = CacheStats{};
    }
};

/// Cache efficiency metrics
pub const EfficiencyMetrics = struct {
    hit_rate: f32,
    miss_rate: f32,
    eviction_rate: f32,
    utilization: f32,
    average_access_count: f32,
};

// Tests
test "InlineCacheManager basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = InlineCacheManager.init(allocator);

    // Create mock candidates
    const TypeCheckIR = @import("ir_dispatch.zig").TypeCheckIR;
    const FunctionRef = @import("ir_dispatch.zig").FunctionRef;
    const FunctionSignature = @import("ir_dispatch.zig").FunctionSignature;

    const candidates = [_]CandidateIR{
        CandidateIR{
            .function_ref = FunctionRef{
                .name = "process_int",
                .mangled_name = "_Z11process_inti",
                .signature = FunctionSignature{
                    .parameters = @constCast(&[_]TypeId{TypeId.I32}),
                    .return_type = TypeId.STRING,
                    .is_variadic = false,
                },
            },
            .conversion_path = &[_]@import("ir_dispatch.zig").ConversionStep{},
            .match_score = 10,
            .type_check_ir = TypeCheckIR{
                .check_kind = .exact_match,
                .target_type = TypeId.I32,
                .parameter_index = 0,
            },
        },
    };

    // Create cache
    var cache = try manager.createCache("test_process", &candidates);
    defer cache.deinit();

    // Test initial state
    try std.testing.expectEqual(@as(u8, 1), cache.cache_size);
    try std.testing.expectEqual(@as(f32, 0.0), cache.getHitRate());

    // Create mock dispatch entry
    const mock_entry = DispatchEntry{
        .type_id = TypeId.I32,
        .function_name = "process_int",
        .mangled_name = "_Z11process_inti",
        .match_score = 10,
        .conversion_cost = 0,
    };

    // Test cache miss
    const lookup1 = cache.lookup(TypeId.I32);
    try std.testing.expect(lookup1 == null);

    // Insert entry
    cache.insert(TypeId.I32, &mock_entry);

    // Test cache hit
    const lookup2 = cache.lookup(TypeId.I32);
    try std.testing.expect(lookup2 != null);
    try std.testing.expectEqualStrings("process_int", lookup2.?.function_name);

    // Verify statistics
    const stats = cache.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.hits);
    try std.testing.expectEqual(@as(u64, 1), stats.misses);
    try std.testing.expectEqual(@as(u64, 1), stats.insertions);

    // Test hit rate
    try std.testing.expectEqual(@as(f32, 0.5), cache.getHitRate());

    // Test efficiency metrics
    const metrics = cache.getEfficiencyMetrics();
    try std.testing.expectEqual(@as(f32, 0.5), metrics.hit_rate);
    try std.testing.expectEqual(@as(f32, 0.5), metrics.miss_rate);
    try std.testing.expectEqual(@as(f32, 1.0), metrics.utilization);

    std.debug.print("✅ InlineCache basic functionality test passed\n", .{});
}

test "InlineCache resize functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = InlineCacheManager.init(allocator);

    const candidates: []const CandidateIR = &[_]CandidateIR{};
    var cache = try manager.createCache("resize_test", candidates);
    defer cache.deinit();

    // Test resize
    try cache.resize(4);
    try std.testing.expectEqual(@as(u8, 4), cache.cache_size);

    const stats = cache.getStats();
    try std.testing.expectEqual(@as(u32, 1), stats.resizes);

    std.debug.print("✅ InlineCache resize test passed\n", .{});
}

test "InlineCache LRU eviction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = InlineCacheManager.init(allocator);

    const candidates: []const CandidateIR = &[_]CandidateIR{};
    var cache = try manager.createCache("lru_test", candidates);
    defer cache.deinit();

    // Create mock entries
    const entry1 = DispatchEntry{
        .type_id = TypeId.I32,
        .function_name = "func1",
        .mangled_name = "_Z5func1i",
        .match_score = 10,
        .conversion_cost = 0,
    };

    const entry2 = DispatchEntry{
        .type_id = TypeId.F64,
        .function_name = "func2",
        .mangled_name = "_Z5func2d",
        .match_score = 10,
        .conversion_cost = 0,
    };

    // Fill cache (size 1)
    cache.insert(TypeId.I32, &entry1);

    // Insert second entry (should evict first)
    cache.insert(TypeId.F64, &entry2);

    // Verify eviction
    const lookup1 = cache.lookup(TypeId.I32);
    try std.testing.expect(lookup1 == null); // Should be evicted

    const lookup2 = cache.lookup(TypeId.F64);
    try std.testing.expect(lookup2 != null); // Should be present

    const stats = cache.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.evictions);

    std.debug.print("✅ InlineCache LRU eviction test passed\n", .{});
}
