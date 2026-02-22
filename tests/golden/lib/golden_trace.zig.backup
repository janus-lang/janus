// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("../../../compiler/libjanus/astdb.zig");

// Golden Test Framework - Build Trace and Performance Monitoring
// Task 3: Golden Test Integration - Stage counters and cache statistics
// Requirements: No-work rebuild verification, performance pinning

pub const StageCounters = struct {
    parse: u32 = 0,
    sema: u32 = 0,
    ir: u32 = 0,
    codegen: u32 = 0,

    pub fn reset(self: *StageCounters) void {
        self.parse = 0;
        self.sema = 0;
        self.ir = 0;
        self.codegen = 0;
    }

    pub fn total(self: StageCounters) u32 {
        return self.parse + self.sema + self.ir + self.codegen;
    }
};

pub const QueryStats = struct {
    hits: u32 = 0,
    misses: u32 = 0,

    pub fn reset(self: *QueryStats) void {
        self.hits       self.misses = 0;
    }

    pub fn recordHit(self: *QueryStats) void {
        self.hits += 1;
    }

    pub fn recordMiss(self: *QueryStats) void {
        self.misses += 1;
    }

    pub fn hitRate(self: QueryStats) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }
};

pub const PerformanceMetrics = struct {
    hover_latency_ns: u64 = 0,
    query_latency_ns: u64 = 0,
    build_time_ns: u64 = 0,
    memory_peak_bytes: u64 = 0,

    pub fn reset(self: *PerformanceMetrics) void {
        self.hover_latency_ns = 0;
        self.query_latency_ns = 0;
        self.build_time_ns = 0;
        self.memory_peak_bytes = 0;
    }
};

pub const RebuildTrace = struct {
    run1: RunTrace,
    run2: RunTrace,

    pub const RunTrace = struct {
        stages: StageCounters,
        queries: QueryStats,
        performance: PerformanceMetrics,
        timestamp_ns: u64,
    };

    pub fn formatAsJSON(self: RebuildTrace, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator,
            \\{{
            \\  "run1": {{
            \\    "parse": {},
            \\    "sema": {},
            \\    "ir": {},
            \\    "codegen": {},
            \\    "q_hits": {},
            \\    "q_misses": {},
            \\    "hover_latency_ms": {d:.2},
            \\    "build_time_ms": {d:.2}
            \\  }},
            \\  "run2": {{
            \\    "parse": {},
            \\    "sema": {},
            \\    "ir": {},
            \\    "codegen": {},
            \\    "q_hits": {},
            \\    "q_misses": {},
            \\    "hover_latency_ms": {d:.2},
            \\    "build_time_ms": {d:.2}
            \\  }}
            \\}}
        , .{
            self.run1.stages.parse, self.run1.stages.sema, self.run1.stages.ir, self.run1.stages.codegen,
            self.run1.queries.hits, self.run1.queries.misses,
            @as(f64, @floatFromInt(self.run1.performance.hover_latency_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(self.run1.performance.build_time_ns)) / 1_000_000.0,

            self.run2.stages.parse, self.run2.stages.sema, self.run2.stages.ir, self.run2.stages.codegen,
            self.run2.queries.hits, self.run2.queries.misses,
            @as(f64, @floatFromInt(self.run2.performance.hover_latency_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(self.run2.performance.build_time_ns)) / 1_000_000.0,
        });
    }

    pub fn validateNoWorkRebuild(self: RebuildTrace) bool {
        return self.run2.stages.parse == 0 and
               self.run2.stages.sema == 0 and
               self.run2.stages.ir == 0 and
               self.run2.stages.codegen == 0 and
               self.run2.queries.misses == 0;
    }

    pub fn validatePerformanceTargets(self: RebuildTrace) bool {
        const hover_target_ns = 10 * 1_000_000; // 10ms
        return self.run1.performance.hover_latency_ns <= hover_target_ns and
               self.run2.performance.hover_latency_ns <= hover_target_ns;
    }
};

pub const BuildTracer = struct {
    allocator: std.mem.Allocator,
    current_run: RebuildTrace.RunTrace,
    run_history: std.ArrayList(RebuildTrace.RunTrace),
    timer: std.time.Timer,

    pub fn init(allocator: std.mem.Allocator) !BuildTracer {
        return BuildTracer{
            .allocator = allocator,
            .current_run = RebuildTrace.RunTrace{
                .stages = StageCounters{},
                .queries = QueryStats{},
                .performance = PerformanceMetrics{},
                .timestamp_ns = 0,
            },
            .run_history = std.ArrayList(RebuildTrace.RunTrace).init(allocator),
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn deinit(self: *BuildTracer) void {
        self.run_history.deinit();
    }

    pub fn startRun(self: *BuildTracer) void {
        self.current_run.stages.reset();
        self.current_run.queries.reset();
        self.current_run.performance.reset();
        self.current_run.timestamp_ns = self.timer.read();
    }

    pub fn endRun(self: *BuildTracer) !void {
        const end_time = self.timer.read();
        self.current_run.performance.build_time_ns = end_time - self.current_run.timestamp_ns;

        try self.run_history.append(self.current_run);
    }

    pub fn recordStage(self: *BuildTracer, stage: enum { parse, sema, ir, codegen }) void {
        switch (stage) {
            .parse => self.current_run.stages.parse += 1,
            .sema => self.current_run.stages.sema += 1,
            .ir => self.current_run.stages.ir += 1,
            .codegen => self.current_run.stages.codegen += 1,
        }
    }

    pub fn recordQueryHit(self: *BuildTracer) void {
        self.current_run.queries.recordHit();
    }

    pub fn recordQueryMiss(self: *BuildTracer) void {
        self.current_run.queries.recordMiss();
    }

    pub fn recordHoverLatency(self: *BuildTracer, latency_ns: u64) void {
        self.current_run.performance.hover_latency_ns = latency_ns;
    }

    pub fn recordMemoryPeak(self: *BuildTracer, bytes: u64) void {
        self.current_run.performance.memory_peak_bytes = @max(
            self.current_run.performance.memory_peak_bytes,
            bytes
        );
    }

    pub fn getTrace(self: *BuildTracer) ?RebuildTrace {
        if (self.run_history.items.len < 2) return null;

        const len = self.run_history.items.len;
        return RebuildTrace{
            .run1 = self.run_history.items[len - 2],
            .run2 = self.run_history.items[len - 1],
        };
    }

    pub fn getLastRun(self: *BuildTracer) ?RebuildTrace.RunTrace {
        if (self.run_history.items.len == 0) return null;
        return self.run_history.items[self.run_history.items.len - 1];
    }

    pub fn clearHistory(self: *BuildTracer) void {
        self.run_history.clearRetainingCapacity();
    }

    /// Simulate a build stage for testing
    pub fn simulateStage(self: *BuildTracer, stage: enum { parse, sema, ir, codegen }, work_units: u32) void {
        for (0..work_units) |_| {
            self.recordStage(stage);
        }
    }

    /// Simulate query operations for testing
    pub fn simulateQueries(self: *BuildTracer, hits: u32, misses: u32) void {
        for (0..hits) |_| {
            self.recordQueryHit();
        }
        for (0..misses) |_| {
            self.recordQueryMiss();
        }
    }

    /// Measure hover latency with timing
    pub fn measureHoverLatency(self: *BuildTracer, query_engine: *astdb.QueryEngine, node_id: astdb.NodeId) !u64 {
        const start_time = self.timer.read();

        // Simulate hover query
        _ = query_engine.tokenSpan(node_id);

        const end_time = self.timer.read();
        const latency = end_time - start_time;

        self.recordHoverLatency(latency);
        return latency;
    }
};

/// Invalidation tracking for precision testing
pub const InvalidationTracker = struct {
    allocator: std.mem.Allocator,
    invalidated_queries: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) InvalidationTracker {
        return InvalidationTracker{
            .allocator = allocator,
            .invalidated_queries = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *InvalidationTracker) void {
        for (self.invalidated_queries.items) |query| {
            self.allocator.free(query);
        }
        self.invalidated_queries.deinit();
    }

    pub fn recordInvalidation(self: *InvalidationTracker, query_name: []const u8) !void {
        const owned_name = try self.allocator.dupe(u8, query_name);
        try self.invalidated_queries.append(owned_name);
    }

    pub fn contains(self: *InvalidationTracker, query_name: []const u8) bool {
        for (self.invalidated_queries.items) |invalidated| {
            if (std.mem.eql(u8, invalidated, query_name)) {
                return true;
            }
        }
        return false;
    }

    pub fn clear(self: *InvalidationTracker) void {
        for (self.invalidated_queries.items) |query| {
            self.allocator.free(query);
        }
        self.invalidated_queries.clearRetainingCapacity();
    }

    pub fn count(self: *InvalidationTracker) u32 {
        return @as(u32, @intCast(self.invalidated_queries.items.len));
    }
};

test "BuildTracer functionality" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tracer = try BuildTracer.init(allocator);
    defer tracer.deinit();

    // Simulate first run
    tracer.startRun();
    tracer.simulateStage(.parse, 5);
    tracer.simulateStage(.sema, 3);
    tracer.simulateStage(.ir, 2);
    tracer.simulateStage(.codegen, 1);
    tracer.simulateQueries(10, 5);
    tracer.recordHoverLatency(8_000_000); // 8ms
    try tracer.endRun();

    // Simulate second run (no-work rebuild)
    tracer.startRun();
    tracer.simulateStage(.parse, 0);
    tracer.simulateStage(.sema, 0);
    tracer.simulateStage(.ir, 0);
    tracer.simulateStage(.codegen, 0);
    tracer.simulateQueries(15, 0); // All cache hits
    tracer.recordHoverLatency(2_000_000); // 2ms
    try tracer.endRun();

    // Get trace
    const trace = tracer.getTrace().?;

    // Verify first run had work
    try testing.expectEqual(@as(u32, 5), trace.run1.stages.parse);
    try testing.expectEqual(@as(u32, 3), trace.run1.stages.sema);
    try testing.expectEqual(@as(u32, 5), trace.run1.queries.misses);

    // Verify second run had no work
    try testing.expectEqual(@as(u32, 0), trace.run2.stages.parse);
    try testing.expectEqual(@as(u32, 0), trace.run2.stages.sema);
    try testing.expectEqual(@as(u32, 0), trace.run2.queries.misses);
    try testing.expectEqual(@as(u32, 15), trace.run2.queries.hits);

    // Verify no-work rebuild validation
    try testing.expect(trace.validateNoWorkRebuild());

    // Verify performance targets
    try testing.expect(trace.validatePerformanceTargets());

    // Test JSON formatting
    const json = try trace.formatAsJSON(allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"parse\": 0") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"q_hits\": 15") != null);

    std.log.info("✅ BuildTracer functionality test passed", .{});
}

test "InvalidationTracker functionality" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tracker = InvalidationTracker.init(allocator);
    defer tracker.deinit();

    // Record some invalidations
    try tracker.recordInvalidation("Q.TypeOf(main)");
    try tracker.recordInvalidation("Q.IROf(add)");
    try tracker.recordInvalidation("Q.Dispatch(call_site_1)");

    // Test contains
    try testing.expect(tracker.contains("Q.TypeOf(main)"));
    try testing.expect(tracker.contains("Q.IROf(add)"));
    try testing.expect(!tracker.contains("Q.TypeOf(helper)"));

    // Test count
    try testing.expectEqual(@as(u32, 3), tracker.count());

    // Test clear
    tracker.clear();
    try testing.expectEqual(@as(u32, 0), tracker.count());
    try testing.expect(!tracker.contains("Q.TypeOf(main)"));

    std.log.info("✅ InvalidationTracker functionality test passed", .{});
}
