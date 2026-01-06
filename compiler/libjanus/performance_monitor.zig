// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Performance monitoring and profiling for semantic resolution
pub const PerformanceMonitor = struct {
    allocator: Allocator,
    resolution_times: std.ArrayList(u64),
    diagnostic_times: std.ArrayList(u64),
    memory_usage: std.ArrayList(usize),
    cache_hits: u64,
    cache_misses: u64,

    pub fn init(allocator: Allocator) PerformanceMonitor {
        return PerformanceMonitor{
            .allocator = allocator,
            .resolution_times = std.ArrayList(u64).init(allocator),
            .diagnostic_times = std.ArrayList(u64).init(allocator),
            .memory_usage = std.ArrayList(usize).init(allocator),
            .cache_hits = 0,
            .cache_misses = 0,
        };
    }

    pub fn deinit(self: *PerformanceMonitor) void {
        self.resolution_times.deinit();
        self.diagnostic_times.deinit();
        self.memory_usage.deinit();
    }

    pub fn recordResolutionTime(self: *PerformanceMonitor, time_ns: u64) !void {
        try self.resolution_times.append(time_ns);
    }

    pub fn recordDiagnosticTime(self: *PerformanceMonitor, time_ns: u64) !void {
        try self.diagnostic_times.append(time_ns);
    }

    pub fn recordMemoryUsage(self: *PerformanceMonitor, bytes: usize) !void {
        try self.memory_usage.append(bytes);
    }

    pub fn recordCacheHit(self: *PerformanceMonitor) void {
        self.cache_hits += 1;
    }

    pub fn recordCacheMiss(self: *PerformanceMonitor) void {
        self.cache_misses += 1;
    }

    pub fn getAverageResolutionTime(self: *const PerformanceMonitor) f64 {
        if (self.resolution_times.items.len == 0) return 0.0;

        var total: u64 = 0;
        for (self.resolution_times.items) |time| {
            total += time;
        }

        return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(self.resolution_times.items.len));
    }

    pub fn getAverageDiagnosticTime(self: *const PerformanceMonitor) f64 {
        if (self.diagnostic_times.items.len == 0) return 0.0;

        var total: u64 = 0;
        for (self.diagnostic_times.items) |time| {
            total += time;
        }

        return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(self.diagnostic_times.items.len));
    }

    pub fn getCacheHitRate(self: *const PerformanceMonitor) f64 {
        const total = self.cache_hits + self.cache_misses;
        if (total == 0) return 0.0;

        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total));
    }

    pub fn getPerformanceReport(self: *const PerformanceMonitor, allocator: Allocator) ![]const u8 {
        const avg_resolution = self.getAverageResolutionTime();
        const avg_diagnostic = self.getAverageDiagnosticTime();
        const cache_hit_rate = self.getCacheHitRate();

        return std.fmt.allocPrint(allocator, "Performance Report:\n" ++
            "  Average Resolution Time: {d:.2} ns\n" ++
            "  Average Diagnostic Time: {d:.2} ns\n" ++
            "  Cache Hit Rate: {d:.1}%\n" ++
            "  Total Resolutions: {d}\n" ++
            "  Total Diagnostics: {d}\n" ++
            "  Memory Samples: {d}\n", .{
            avg_resolution,
            avg_diagnostic,
            cache_hit_rate * 100.0,
            self.resolution_times.items.len,
            self.diagnostic_times.items.len,
            self.memory_usage.items.len,
        });
    }

    pub fn checkPerformanceTargets(self: *const PerformanceMonitor) PerformanceStatus {
        const avg_resolution = self.getAverageResolutionTime();
        const avg_diagnostic = self.getAverageDiagnosticTime();

        const status = PerformanceStatus{
            .resolution_within_target = avg_resolution < 1_000_000, // <1ms
            .diagnostic_within_target = avg_diagnostic < 10_000_000, // <10ms
            .cache_hit_rate_good = self.getCacheHitRate() > 0.8, // >80%
        };

        return status;
    }

    pub const PerformanceStatus = struct {
        resolution_within_target: bool,
        diagnostic_within_target: bool,
        cache_hit_rate_good: bool,

        pub fn allTargetsMet(self: PerformanceStatus) bool {
            return self.resolution_within_target and
                self.diagnostic_within_target and
                self.cache_hit_rate_good;
        }
    };
};

/// Resolution cache for performance optimization
pub const ResolutionCache = struct {
    allocator: Allocator,
    resolution_cache: std.HashMap(CallSignatureHash, CachedResult, CallSignatureContext, std.hash_map.default_max_load_percentage),
    candidate_cache: std.HashMap(CandidateKey, CandidateSet, CandidateKeyContext, std.hash_map.default_max_load_percentage),
    conversion_cache: std.HashMap(ConversionKey, ConversionPath, ConversionKeyContext, std.hash_map.default_max_load_percentage),

    const CallSignatureHash = u64;
    const CandidateKey = struct {
        function_name: []const u8,
        scope_id: u32,
    };
    const ConversionKey = struct {
        from_types: []const u8, // Serialized type list
        to_types: []const u8,
    };

    // Placeholder types - would need actual imports
    const CachedResult = struct {
        success: bool,
        target_function: ?[]const u8,
        conversion_cost: u32,
        timestamp: i64,
    };

    const CandidateSet = struct {
        candidates: [][]const u8, // Simplified
        timestamp: i64,
    };

    const ConversionPath = struct {
        conversions: [][]const u8, // Simplified
        total_cost: u32,
        timestamp: i64,
    };

    const CallSignatureContext = struct {
        pub fn hash(self: @This(), key: CallSignatureHash) u64 {
            _ = self;
            return key;
        }

        pub fn eql(self: @This(), a: CallSignatureHash, b: CallSignatureHash) bool {
            _ = self;
            return a == b;
        }
    };

    const CandidateKeyContext = struct {
        pub fn hash(self: @This(), key: CandidateKey) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(key.function_name);
            hasher.update(std.mem.asBytes(&key.scope_id));
            return hasher.final();
        }

        pub fn eql(self: @This(), a: CandidateKey, b: CandidateKey) bool {
            _ = self;
            return std.mem.eql(u8, a.function_name, b.function_name) and a.scope_id == b.scope_id;
        }
    };

    const ConversionKeyContext = struct {
        pub fn hash(self: @This(), key: ConversionKey) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(key.from_types);
            hasher.update(key.to_types);
            return hasher.final();
        }

        pub fn eql(self: @This(), a: ConversionKey, b: ConversionKey) bool {
            _ = self;
            return std.mem.eql(u8, a.from_types, b.from_types) and
                std.mem.eql(u8, a.to_types, b.to_types);
        }
    };

    pub fn init(allocator: Allocator) ResolutionCache {
        return ResolutionCache{
            .allocator = allocator,
            .resolution_cache = std.HashMap(CallSignatureHash, CachedResult, CallSignatureContext, std.hash_map.default_max_load_percentage).init(allocator),
            .candidate_cache = std.HashMap(CandidateKey, CandidateSet, CandidateKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .conversion_cache = std.HashMap(ConversionKey, ConversionPath, ConversionKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *ResolutionCache) void {
        self.resolution_cache.deinit();
        self.candidate_cache.deinit();
        self.conversion_cache.deinit();
    }

    pub fn getCachedResolution(self: *ResolutionCache, signature_hash: CallSignatureHash) ?CachedResult {
        return self.resolution_cache.get(signature_hash);
    }

    pub fn cacheResolution(self: *ResolutionCache, signature_hash: CallSignatureHash, result: CachedResult) !void {
        try self.resolution_cache.put(signature_hash, result);
    }

    pub fn invalidateCache(self: *ResolutionCache) void {
        self.resolution_cache.clearRetainingCapacity();
        self.candidate_cache.clearRetainingCapacity();
        self.conversion_cache.clearRetainingCapacity();
    }

    pub fn getCacheStats(self: *const ResolutionCache) CacheStats {
        return CacheStats{
            .resolution_entries = self.resolution_cache.count(),
            .candidate_entries = self.candidate_cache.count(),
            .conversion_entries = self.conversion_cache.count(),
        };
    }

    pub const CacheStats = struct {
        resolution_entries: u32,
        candidate_entries: u32,
        conversion_entries: u32,

        pub fn totalEntries(self: CacheStats) u32 {
            return self.resolution_entries + self.candidate_entries + self.conversion_entries;
        }
    };
};

// Tests
test "PerformanceMonitor basic functionality" {
    var monitor = PerformanceMonitor.init(std.testing.allocator);
    defer monitor.deinit();

    // Record some performance data
    try monitor.recordResolutionTime(500_000); // 0.5ms
    try monitor.recordResolutionTime(800_000); // 0.8ms
    try monitor.recordDiagnosticTime(5_000_000); // 5ms

    monitor.recordCacheHit();
    monitor.recordCacheHit();
    monitor.recordCacheMiss();

    // Check averages
    const avg_resolution = monitor.getAverageResolutionTime();
    try std.testing.expect(avg_resolution == 650_000.0); // (500k + 800k) / 2

    const cache_hit_rate = monitor.getCacheHitRate();
    try std.testing.expect(cache_hit_rate > 0.66 and cache_hit_rate < 0.67); // 2/3

    // Check performance targets
    const status = monitor.checkPerformanceTargets();
    try std.testing.expect(status.resolution_within_target); // <1ms
    try std.testing.expect(status.diagnostic_within_target); // <10ms
}

test "ResolutionCache basic operations" {
    var cache = ResolutionCache.init(std.testing.allocator);
    defer cache.deinit();

    const signature_hash: u64 = 12345;
    const result = ResolutionCache.CachedResult{
        .success = true,
        .target_function = "add",
        .conversion_cost = 5,
        .timestamp = std.time.timestamp(),
    };

    // Cache and retrieve
    try cache.cacheResolution(signature_hash, result);
    const cached = cache.getCachedResolution(signature_hash).?;

    try std.testing.expect(cached.success);
    try std.testing.expect(cached.conversion_cost == 5);

    // Check stats
    const stats = cache.getCacheStats();
    try std.testing.expect(stats.resolution_entries == 1);
    try std.testing.expect(stats.totalEntries() == 1);
}
