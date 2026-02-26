// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Query Limits & Quota System
//! Task 2.8 - Gas limits + microbench for hover p95
//!
//! This module implements resource limits and performance monitoring
//! to ensure queries complete within acceptable time bounds and
//! don't consume excessive resources.

const std = @import("std");
const Allocator = std.mem.Allocator;
const context = @import("context.zig");

const QueryCtx = context.QueryCtx;
const QueryId = context.QueryId;

/// Resource quota system for query execution
pub const QueryQuota = struct {
    /// Maximum execution time in microseconds
    max_execution_time_us: u64,
    /// Maximum memory allocation in bytes
    max_memory_bytes: u64,
    /// Maximum number of AST nodes to visit
    max_nodes_visited: u32,
    /// Maximum recursion depth
    max_recursion_depth: u32,
    /// Gas limit for complex operations
    gas_limit: u64,

    /// Current resource usage
    current_usage: ResourceUsage,

    const ResourceUsage = struct {
        execution_time_us: u64 = 0,
        memory_bytes: u64 = 0,
        nodes_visited: u32 = 0,
        recursion_depth: u32 = 0,
        gas_consumed: u64 = 0,
    };

    pub fn init(config: QuotaConfig) QueryQuota {
        return QueryQuota{
            .max_execution_time_us = config.max_execution_time_us,
            .max_memory_bytes = config.max_memory_bytes,
            .max_nodes_visited = config.max_nodes_visited,
            .max_recursion_depth = config.max_recursion_depth,
            .gas_limit = config.gas_limit,
            .current_usage = ResourceUsage{},
        };
    }

    /// Check if quota has been exceeded
    pub fn checkQuota(self: *QueryQuota) !void {
        if (self.current_usage.execution_time_us > self.max_execution_time_us) {
            return error.QE0011_QuotaExceeded;
        }
        if (self.current_usage.memory_bytes > self.max_memory_bytes) {
            return error.QE0011_QuotaExceeded;
        }
        if (self.current_usage.nodes_visited > self.max_nodes_visited) {
            return error.QE0011_QuotaExceeded;
        }
        if (self.current_usage.recursion_depth > self.max_recursion_depth) {
            return error.QE0011_QuotaExceeded;
        }
        if (self.current_usage.gas_consumed > self.gas_limit) {
            return error.QE0011_QuotaExceeded;
        }
    }

    /// Record node visit
    pub fn recordNodeVisit(self: *QueryQuota) !void {
        self.current_usage.nodes_visited += 1;
        try self.checkQuota();
    }

    /// Record memory allocation
    pub fn recordMemoryAllocation(self: *QueryQuota, bytes: u64) !void {
        self.current_usage.memory_bytes += bytes;
        try self.checkQuota();
    }

    /// Record recursion entry
    pub fn enterRecursion(self: *QueryQuota) !void {
        self.current_usage.recursion_depth += 1;
        try self.checkQuota();
    }

    /// Record recursion exit
    pub fn exitRecursion(self: *QueryQuota) void {
        if (self.current_usage.recursion_depth > 0) {
            self.current_usage.recursion_depth -= 1;
        }
    }

    /// Consume gas for expensive operations
    pub fn consumeGas(self: *QueryQuota, amount: u64) !void {
        self.current_usage.gas_consumed += amount;
        try self.checkQuota();
    }

    /// Update execution time
    pub fn updateExecutionTime(self: *QueryQuota, elapsed_us: u64) !void {
        self.current_usage.execution_time_us = elapsed_us;
        try self.checkQuota();
    }

    /// Get remaining quota
    pub fn getRemainingQuota(self: QueryQuota) RemainingQuota {
        return RemainingQuota{
            .execution_time_us = self.max_execution_time_us - self.current_usage.execution_time_us,
            .memory_bytes = self.max_memory_bytes - self.current_usage.memory_bytes,
            .nodes_visited = self.max_nodes_visited - self.current_usage.nodes_visited,
            .recursion_depth = self.max_recursion_depth - self.current_usage.recursion_depth,
            .gas = self.gas_limit - self.current_usage.gas_consumed,
        };
    }

    const RemainingQuota = struct {
        execution_time_us: u64,
        memory_bytes: u64,
        nodes_visited: u32,
        recursion_depth: u32,
        gas: u64,
    };
};

/// Configuration for query quotas
pub const QuotaConfig = struct {
    max_execution_time_us: u64,
    max_memory_bytes: u64,
    max_nodes_visited: u32,
    max_recursion_depth: u32,
    gas_limit: u64,

    /// Default quota for interactive queries (hover, completion)
    pub fn interactive() QuotaConfig {
        return QuotaConfig{
            .max_execution_time_us = 10_000, // 10ms
            .max_memory_bytes = 10 * 1024 * 1024, // 10MB
            .max_nodes_visited = 10_000,
            .max_recursion_depth = 100,
            .gas_limit = 1_000_000,
        };
    }

    /// Quota for background analysis
    pub fn background() QuotaConfig {
        return QuotaConfig{
            .max_execution_time_us = 1_000_000, // 1 second
            .max_memory_bytes = 100 * 1024 * 1024, // 100MB
            .max_nodes_visited = 1_000_000,
            .max_recursion_depth = 1000,
            .gas_limit = 100_000_000,
        };
    }

    /// Quota for batch processing
    pub fn batch() QuotaConfig {
        return QuotaConfig{
            .max_execution_time_us = 60_000_000, // 1 minute
            .max_memory_bytes = 1024 * 1024 * 1024, // 1GB
            .max_nodes_visited = 10_000_000,
            .max_recursion_depth = 10_000,
            .gas_limit = 1_000_000_000,
        };
    }
};

/// Performance monitoring and benchmarking
pub const PerformanceMonitor = struct {
    allocator: Allocator,
    measurements: std.HashMap(QueryId, QueryMetrics, QueryIdContext, std.hash_map.default_max_load_percentage),
    global_stats: GlobalStats,

    const QueryMetrics = struct {
        samples: std.ArrayList(Sample),
        p50: u64 = 0,
        p95: u64 = 0,
        p99: u64 = 0,
        mean: f64 = 0.0,
        min: u64 = std.math.maxInt(u64),
        max: u64 = 0,

        const Sample = struct {
            execution_time_us: u64,
            memory_used: u64,
            nodes_visited: u32,
            cache_hit: bool,
            timestamp: i64,
        };

        pub fn init(allocator: Allocator) QueryMetrics {
            return QueryMetrics{
                .samples = .empty,
            };
        }

        pub fn deinit(self: *QueryMetrics) void {
            self.samples.deinit();
        }

        pub fn addSample(self: *QueryMetrics, sample: Sample) !void {
            try self.samples.append(sample);
            self.updateStatistics();
        }

        fn updateStatistics(self: *QueryMetrics) void {
            if (self.samples.items.len == 0) return;

            // Sort samples by execution time for percentile calculation
            var times: std.ArrayList(u64) = .empty;
            defer times.deinit();

            var total_time: u64 = 0;
            for (self.samples.items) |sample| {
                times.append(sample.execution_time_us) catch continue;
                total_time += sample.execution_time_us;

                if (sample.execution_time_us < self.min) {
                    self.min = sample.execution_time_us;
                }
                if (sample.execution_time_us > self.max) {
                    self.max = sample.execution_time_us;
                }
            }

            std.sort.sort(u64, times.items, {}, comptime std.sort.asc(u64));

            // Calculate percentiles
            const len = times.items.len;
            if (len > 0) {
                self.p50 = times.items[len * 50 / 100];
                self.p95 = times.items[len * 95 / 100];
                self.p99 = times.items[len * 99 / 100];
                self.mean = @intToFloat(f64, total_time) / @intToFloat(f64, len);
            }
        }

        /// Check if p95 latency meets target (≤ 10ms for hot cache)
        pub fn meetsLatencyTarget(self: QueryMetrics) bool {
            return self.p95 <= 10_000; // 10ms in microseconds
        }
    };

    const GlobalStats = struct {
        total_queries: u64 = 0,
        cache_hits: u64 = 0,
        quota_exceeded: u64 = 0,
        average_latency_us: f64 = 0.0,
    };

    const QueryIdContext = struct {
        pub fn hash(self: @This(), key: QueryId) u64 {
            _ = self;
            return @enumToInt(key);
        }

        pub fn eql(self: @This(), a: QueryId, b: QueryId) bool {
            _ = self;
            return a == b;
        }
    };

    pub fn init(allocator: Allocator) PerformanceMonitor {
        return PerformanceMonitor{
            .allocator = allocator,
            .measurements = std.HashMap(QueryId, QueryMetrics, QueryIdContext, std.hash_map.default_max_load_percentage).init(allocator),
            .global_stats = GlobalStats{},
        };
    }

    pub fn deinit(self: *PerformanceMonitor) void {
        var iterator = self.measurements.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.measurements.deinit();
    }

    /// Record query execution
    pub fn recordQuery(self: *PerformanceMonitor, query_id: QueryId, execution_time_us: u64, memory_used: u64, nodes_visited: u32, cache_hit: bool) !void {
        const sample = QueryMetrics.Sample{
            .execution_time_us = execution_time_us,
            .memory_used = memory_used,
            .nodes_visited = nodes_visited,
            .cache_hit = cache_hit,
            .timestamp = std.time.milliTimestamp(),
        };

        // Get or create metrics for this query
        var metrics = self.measurements.get(query_id) orelse blk: {
            const new_metrics = QueryMetrics.init(self.allocator);
            try self.measurements.put(query_id, new_metrics);
            break :blk self.measurements.getPtr(query_id).?;
        };

        try metrics.addSample(sample);

        // Update global stats
        self.global_stats.total_queries += 1;
        if (cache_hit) {
            self.global_stats.cache_hits += 1;
        }

        const total = @intToFloat(f64, self.global_stats.total_queries);
        self.global_stats.average_latency_us = (self.global_stats.average_latency_us * (total - 1.0) + @intToFloat(f64, execution_time_us)) / total;
    }

    /// Record quota exceeded event
    pub fn recordQuotaExceeded(self: *PerformanceMonitor) void {
        self.global_stats.quota_exceeded += 1;
    }

    /// Get metrics for a specific query
    pub fn getQueryMetrics(self: *PerformanceMonitor, query_id: QueryId) ?QueryMetrics {
        return self.measurements.get(query_id);
    }

    /// Get global performance statistics
    pub fn getGlobalStats(self: PerformanceMonitor) GlobalStats {
        return self.global_stats;
    }

    /// Check if all queries meet latency targets
    pub fn allQueriesMeetTargets(self: *PerformanceMonitor) bool {
        var iterator = self.measurements.iterator();
        while (iterator.next()) |entry| {
            if (!entry.value_ptr.meetsLatencyTarget()) {
                return false;
            }
        }
        return true;
    }

    /// Generate performance report
    pub fn generateReport(self: *PerformanceMonitor, allocator: Allocator) !PerformanceReport {
        var query_reports: std.ArrayList(QueryReport) = .empty;

        var iterator = self.measurements.iterator();
        while (iterator.next()) |entry| {
            const query_id = entry.key_ptr.*;
            const metrics = entry.value_ptr.*;

            try query_reports.append(QueryReport{
                .query_id = query_id,
                .sample_count = @intCast(u32, metrics.samples.items.len),
                .p50_us = metrics.p50,
                .p95_us = metrics.p95,
                .p99_us = metrics.p99,
                .mean_us = metrics.mean,
                .min_us = metrics.min,
                .max_us = metrics.max,
                .meets_target = metrics.meetsLatencyTarget(),
            });
        }

        return PerformanceReport{
            .global_stats = self.global_stats,
            .query_reports = query_reports.toOwnedSlice(),
            .cache_hit_rate = if (self.global_stats.total_queries > 0)
                @intToFloat(f32, self.global_stats.cache_hits) / @intToFloat(f32, self.global_stats.total_queries)
            else
                0.0,
        };
    }
};

/// Performance report structure
pub const PerformanceReport = struct {
    global_stats: PerformanceMonitor.GlobalStats,
    query_reports: []QueryReport,
    cache_hit_rate: f32,

    pub fn deinit(self: *PerformanceReport, allocator: Allocator) void {
        allocator.free(self.query_reports);
    }
};

pub const QueryReport = struct {
    query_id: QueryId,
    sample_count: u32,
    p50_us: u64,
    p95_us: u64,
    p99_us: u64,
    mean_us: f64,
    min_us: u64,
    max_us: u64,
    meets_target: bool,
};

/// Gas costs for different operations
pub const GasCosts = struct {
    pub const NODE_VISIT = 1;
    pub const SYMBOL_LOOKUP = 10;
    pub const TYPE_INFERENCE = 50;
    pub const DISPATCH_RESOLUTION = 100;
    pub const EFFECT_ANALYSIS = 200;
    pub const IR_GENERATION = 500;
    pub const RECURSIVE_CALL = 25;
    pub const CACHE_MISS = 5;
};

/// Quota-aware query context wrapper
pub const QuotaAwareQueryCtx = struct {
    inner_ctx: *QueryCtx,
    quota: QueryQuota,
    performance_monitor: *PerformanceMonitor,
    start_time: i64,

    pub fn init(inner_ctx: *QueryCtx, quota_config: QuotaConfig, performance_monitor: *PerformanceMonitor) QuotaAwareQueryCtx {
        return QuotaAwareQueryCtx{
            .inner_ctx = inner_ctx,
            .quota = QueryQuota.init(quota_config),
            .performance_monitor = performance_monitor,
            .start_time = std.time.microTimestamp(),
        };
    }

    /// Execute query with quota enforcement
    pub fn executeQuery(self: *QuotaAwareQueryCtx, query_id: QueryId, args: context.QueryArgs) !context.QueryResult {
        // Record start time
        self.start_time = std.time.microTimestamp();

        // Consume gas for query initiation
        try self.quota.consumeGas(GasCosts.CACHE_MISS);

        // Execute the query
        const result = self.inner_ctx.executeQuery(query_id, args) catch |err| {
            // Record quota exceeded if that's the error
            if (err == error.QE0011_QuotaExceeded) {
                self.performance_monitor.recordQuotaExceeded();
            }
            return err;
        };

        // Update execution time and check quota
        const elapsed_us = @intCast(u64, std.time.microTimestamp() - self.start_time);
        try self.quota.updateExecutionTime(elapsed_us);

        // Record performance metrics
        try self.performance_monitor.recordQuery(
            query_id,
            elapsed_us,
            self.quota.current_usage.memory_bytes,
            self.quota.current_usage.nodes_visited,
            result.from_cache,
        );

        return result;
    }

    /// Check quota during query execution
    pub fn checkQuota(self: *QuotaAwareQueryCtx) !void {
        const elapsed_us = @intCast(u64, std.time.microTimestamp() - self.start_time);
        try self.quota.updateExecutionTime(elapsed_us);
    }

    /// Record node visit with quota check
    pub fn visitNode(self: *QuotaAwareQueryCtx) !void {
        try self.quota.recordNodeVisit();
        try self.quota.consumeGas(GasCosts.NODE_VISIT);
    }

    /// Record memory allocation with quota check
    pub fn allocateMemory(self: *QuotaAwareQueryCtx, bytes: u64) !void {
        try self.quota.recordMemoryAllocation(bytes);
    }

    /// Enter recursion with quota check
    pub fn enterRecursion(self: *QuotaAwareQueryCtx) !void {
        try self.quota.enterRecursion();
        try self.quota.consumeGas(GasCosts.RECURSIVE_CALL);
    }

    /// Exit recursion
    pub fn exitRecursion(self: *QuotaAwareQueryCtx) void {
        self.quota.exitRecursion();
    }
};

// Tests
test "QueryQuota basic functionality" {
    const config = QuotaConfig.interactive();
    var quota = QueryQuota.init(config);

    // Should not exceed quota initially
    try quota.checkQuota();

    // Record some usage
    try quota.recordNodeVisit();
    try quota.recordMemoryAllocation(1024);
    try quota.enterRecursion();
    quota.exitRecursion();

    // Should still be within quota
    try quota.checkQuota();
}

test "QueryQuota exceeds limits" {
    const config = QuotaConfig{
        .max_execution_time_us = 1000,
        .max_memory_bytes = 1024,
        .max_nodes_visited = 10,
        .max_recursion_depth = 5,
        .gas_limit = 100,
    };

    var quota = QueryQuota.init(config);

    // Exceed node visit limit
    var i: u32 = 0;
    while (i <= config.max_nodes_visited) : (i += 1) {
        if (i == config.max_nodes_visited) {
            try std.testing.expectError(error.QE0011_QuotaExceeded, quota.recordNodeVisit());
            break;
        } else {
            try quota.recordNodeVisit();
        }
    }
}

test "PerformanceMonitor metrics" {
    const allocator = std.testing.allocator;

    var monitor = PerformanceMonitor.init(allocator);
    defer monitor.deinit();

    // Record some queries
    try monitor.recordQuery(.TypeOf, 5000, 1024, 100, false);
    try monitor.recordQuery(.TypeOf, 8000, 2048, 150, true);
    try monitor.recordQuery(.Hover, 12000, 512, 50, false);

    const global_stats = monitor.getGlobalStats();
    try std.testing.expect(global_stats.total_queries == 3);
    try std.testing.expect(global_stats.cache_hits == 1);

    const type_of_metrics = monitor.getQueryMetrics(.TypeOf);
    try std.testing.expect(type_of_metrics != null);
    try std.testing.expect(type_of_metrics.?.samples.items.len == 2);
}

test "Gas consumption" {
    const config = QuotaConfig{
        .max_execution_time_us = 1000000,
        .max_memory_bytes = 1024 * 1024,
        .max_nodes_visited = 10000,
        .max_recursion_depth = 100,
        .gas_limit = 1000,
    };

    var quota = QueryQuota.init(config);

    // Consume gas up to limit
    try quota.consumeGas(500);
    try quota.consumeGas(400);

    // This should exceed the limit
    try std.testing.expectError(error.QE0011_QuotaExceeded, quota.consumeGas(200));
}

test "Performance target checking" {
    const allocator = std.testing.allocator;

    var metrics = PerformanceMonitor.QueryMetrics.init(allocator);
    defer metrics.deinit();

    // Add samples that meet target (≤ 10ms)
    try metrics.addSample(.{ .execution_time_us = 5000, .memory_used = 1024, .nodes_visited = 100, .cache_hit = true, .timestamp = 0 });
    try metrics.addSample(.{ .execution_time_us = 8000, .memory_used = 2048, .nodes_visited = 150, .cache_hit = false, .timestamp = 1 });
    try metrics.addSample(.{ .execution_time_us = 9000, .memory_used = 1536, .nodes_visited = 120, .cache_hit = true, .timestamp = 2 });

    try std.testing.expect(metrics.meetsLatencyTarget());

    // Add a sample that exceeds target
    try metrics.addSample(.{ .execution_time_us = 15000, .memory_used = 4096, .nodes_visited = 300, .cache_hit = false, .timestamp = 3 });

    try std.testing.expect(!metrics.meetsLatencyTarget());
}
