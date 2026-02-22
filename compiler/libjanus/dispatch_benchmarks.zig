// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const testing = std.testing;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchMemoryProfiler = @import("optimized_dispatch_tables.zig").DispatchMemoryProfiler;

/// Comprehensive benchmark suite for dispatch table optimization
pub const DispatchBenchmarkSuite = struct {
    allocator: Allocator,
    type_registry: TypeRegistry,
    profiler: DispatchMemoryProfiler,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var type_registry = try TypeRegistry.init(allocator);
        var profiler = DispatchMemoryProfiler.init(allocator);

        return Self{
            .allocator = allocator,
            .type_registry = type_registry,
            .profiler = profiler,
        };
    }

    pub fn deinit(self: *Self) void {
        self.profiler.deinit();
        self.type_registry.deinit();
    }

    /// Run comprehensive benchmark comparing different strategies
    pub fn runComprehensiveBenchmark(self: *Self, writer: anytype) !void {
        try writer.print("Dispatch Table Optimization Benchmark Suite\n");
        try writer.print("==========================================\n\n");

        // Setup test types
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});
        const string_type = try self.type_registry.registerType("string", .primitive, &.{});
        const bool_type = try self.type_registry.registerType("bool", .primitive, &.{});

        // Test different table sizes
        const table_sizes = [_]u32{ 5, 10, 25, 50, 100 };

        for (table_sizes) |size| {
            try writer.print("Testing table size: {} implementations\n", .{size});
            try writer.print("----------------------------------------\n");

            const results = try self.benchmarkTableSize(size, &[_]TypeId{ int_type, float_type, string_type, bool_type });
            try writer.print("{}\n\n", .{results});
        }

        // Test different access patterns
        try writer.print("Testing access patterns\n");
        try writer.print("----------------------\n");

        const access_results = try self.benchmarkAccessPatterns(&[_]TypeId{ int_type, float_type, string_type });
        try writer.print("{}\n\n", .{access_results});

        // Memory usage analysis
        try writer.print("Memory Usage Analysis\n");
        try writer.print("--------------------\n");
        try self.profiler.generateReport(writer);
    }

    /// Benchmark different table sizes
    fn benchmarkTableSize(self: *Self, size: u32, types: []const TypeId) !BenchmarkResults {
        var table = try OptimizedDispatchTable.init(self.allocator, "benchmark_func", types);
        defer table.deinit();

        try self.profiler.registerTable(&table);
        defer self.profiler.unregisterTable(&table);

        // Create implementations
        var implementations: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer {
            for (implementations.items) |impl| {
                self.allocator.free(impl.param_type_ids);
            }
            implementations.deinit();
        }

        for (0..size) |i| {
            const type_combo = self.generateTypeCombo(types, i);
            const impl = SignatureAnalyzer.Implementation{
                .function_id = SignatureAnalyzer.FunctionId{
                    .name = "benchmark_func",
                    .module = "benchmark",
                    .id = @intCast(i + 1),
                },
                .param_type_ids = try self.allocator.dupe(TypeId, type_combo),
                .return_type_id = types[0],
                .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
                .source_location = SignatureAnalyzer.SourceSpan.dummy(),
                .specificity_rank = @intCast(100 + i),
            };

            try implementations.append(impl);
            try table.addImplementation(&implementations.items[implementations.items.len - 1]);
        }

        // Generate test cases
        var test_cases: ArrayList([]const TypeId) = .empty;
        defer {
            for (test_cases.items) |case| {
                self.allocator.free(case);
            }
            test_cases.deinit();
        }

        for (0..@min(size, 20)) |i| {
            const test_case = try self.allocator.dupe(TypeId, self.generateTypeCombo(types, i));
            try test_cases.append(test_case);
        }

        // Run benchmarks
        const lookup_results = try table.benchmarkLookupStrategies(test_cases.items, 10000);
        const memory_stats = table.getMemoryStats();

        return BenchmarkResults{
            .table_size = size,
            .lookup_performance = lookup_results,
            .memory_usage = memory_stats,
            .cache_efficiency = memory_stats.cache_efficiency,
        };
    }

    /// Benchmark different access patterns
    fn benchmarkAccessPatterns(self: *Self, types: []const TypeId) !AccessPatternResults {
        var table = try OptimizedDispatchTable.init(self.allocator, "pattern_func", types);
        defer table.deinit();

        // Create implementations
        const impl_count = 20;
        var implementations: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer {
            for (implementations.items) |impl| {
                self.allocator.free(impl.param_type_ids);
            }
            implementations.deinit();
        }

        for (0..impl_count) |i| {
            const type_combo = self.generateTypeCombo(types, i);
            const impl = SignatureAnalyzer.Implementation{
                .function_id = SignatureAnalyzer.FunctionId{
                    .name = "pattern_func",
                    .module = "pattern",
                    .id = @intCast(i + 1),
                },
                .param_type_ids = try self.allocator.dupe(TypeId, type_combo),
                .return_type_id = types[0],
                .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
                .source_location = SignatureAnalyzer.SourceSpan.dummy(),
                .specificity_rank = @intCast(100 + i),
            };

            try implementations.append(impl);
            try table.addImplementation(&implementations.items[implementations.items.len - 1]);
        }

        // Test different access patterns
        const sequential_time = try self.benchmarkSequentialAccess(&table, types);
        const random_time = try self.benchmarkRandomAccess(&table, types);
        const hot_path_time = try self.benchmarkHotPathAccess(&table, types);

        return AccessPatternResults{
            .sequential_access_ns = sequential_time,
            .random_access_ns = random_time,
            .hot_path_access_ns = hot_path_time,
        };
    }

    /// Benchmark sequential access pattern
    fn benchmarkSequentialAccess(self: *Self, table: *OptimizedDispatchTable, types: []const TypeId) !u64 {
        const iterations = 10000;
        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |i| {
            const type_combo = self.generateTypeCombo(types, i % types.len);
            _ = table.lookup(type_combo);
        }

        return @intCast(std.time.nanoTimestamp() - start_time);
    }

    /// Benchmark random access pattern
    fn benchmarkRandomAccess(self: *Self, table: *OptimizedDispatchTable, types: []const TypeId) !u64 {
        const iterations = 10000;
        var rng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));

        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            const random_index = rng.random().uintLessThan(usize, types.len);
            const type_combo = self.generateTypeCombo(types, random_index);
            _ = table.lookup(type_combo);
        }

        return @intCast(std.time.nanoTimestamp() - start_time);
    }

    /// Benchmark hot path access pattern (80/20 rule)
    fn benchmarkHotPathAccess(self: *Self, table: *OptimizedDispatchTable, types: []const TypeId) !u64 {
        const iterations = 10000;
        var rng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));

        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            // 80% of accesses go to first 20% of implementations
            const is_hot_path = rng.random().float(f32) < 0.8;
            const index = if (is_hot_path)
                rng.random().uintLessThan(usize, @max(1, types.len / 5))
            else
                rng.random().uintLessThan(usize, types.len);

            const type_combo = self.generateTypeCombo(types, index);
            _ = table.lookup(type_combo);
        }

        return @intCast(std.time.nanoTimestamp() - start_time);
    }

    /// Generate type combination for testing
    fn generateTypeCombo(self: *Self, types: []const TypeId, index: usize) []const TypeId {
        _ = self;

        // Generate different type combinations based on index
        const combo_index = index % 4;

        return switch (combo_index) {
            0 => &[_]TypeId{types[0]},
            1 => if (types.len > 1) &[_]TypeId{types[1]} else &[_]TypeId{types[0]},
            2 => if (types.len > 1) &[_]TypeId{ types[0], types[1] } else &[_]TypeId{types[0]},
            3 => if (types.len > 2) &[_]TypeId{ types[0], types[2] } else &[_]TypeId{types[0]},
            else => &[_]TypeId{types[0]},
        };
    }

    /// Results from table size benchmarking
    pub const BenchmarkResults = struct {
        table_size: u32,
        lookup_performance: OptimizedDispatchTable.BenchmarkResults,
        memory_usage: OptimizedDispatchTable.MemoryStats,
        cache_efficiency: f32,

        pub fn format(self: BenchmarkResults, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Table Size: {} implementations\n", .{self.table_size});
            try writer.print("Lookup Performance:\n");
            try writer.print("  Linear Search: {} ns\n", .{self.lookup_performance.linear_search_ns});
            try writer.print("  Decision Tree: {} ns\n", .{self.lookup_performance.decision_tree_ns});
            try writer.print("  Compressed Pattern: {} ns\n", .{self.lookup_performance.compressed_pattern_ns});
            try writer.print("Memory Usage: {}\n", .{self.memory_usage});
            try writer.print("Cache Efficiency: {d:.1}%\n", .{self.cache_efficiency * 100.0});

            // Performance analysis
            if (self.lookup_performance.decision_tree_ns > 0 and self.lookup_performance.linear_search_ns > 0) {
                const speedup = @as(f32, @floatFromInt(self.lookup_performance.linear_search_ns)) / @as(f32, @floatFromInt(self.lookup_performance.decision_tree_ns));
                try writer.print("Decision Tree Speedup: {d:.2}x\n", .{speedup});
            }
        }
    };

    /// Results from access pattern benchmarking
    pub const AccessPatternResults = struct {
        sequential_access_ns: u64,
        random_access_ns: u64,
        hot_path_access_ns: u64,

        pub fn format(self: AccessPatternResults, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Access Pattern Performance:\n");
            try writer.print("  Sequential: {} ns\n", .{self.sequential_access_ns});
            try writer.print("  Random: {} ns\n", .{self.random_access_ns});
            try writer.print("  Hot Path (80/20): {} ns\n", .{self.hot_path_access_ns});

            // Calculate relative performance
            const baseline = @as(f32, @floatFromInt(self.sequential_access_ns));
            const random_ratio = @as(f32, @floatFromInt(self.random_access_ns)) / baseline;
            const hot_path_ratio = @as(f32, @floatFromInt(self.hot_path_access_ns)) / baseline;

            try writer.print("  Random vs Sequential: {d:.2}x\n", .{random_ratio});
            try writer.print("  Hot Path vs Sequential: {d:.2}x\n", .{hot_path_ratio});
        }
    };
};

/// Performance regression test suite
pub const PerformanceRegressionTests = struct {
    allocator: Allocator,
    baseline_results: ?BenchmarkBaseline,

    const Self = @This();

    pub const BenchmarkBaseline = struct {
        small_table_lookup_ns: u64,
        medium_table_lookup_ns: u64,
        large_table_lookup_ns: u64,
        memory_efficiency: f32,
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .baseline_results = null,
        };
    }

    /// Establish performance baseline
    pub fn establishBaseline(self: *Self) !void {
        var benchmark_suite = try DispatchBenchmarkSuite.init(self.allocator);
        defer benchmark_suite.deinit();

        // Setup test types
        const int_type = try benchmark_suite.type_registry.registerType("int", .primitive, &.{});
        const float_type = try benchmark_suite.type_registry.registerType("float", .primitive, &.{});
        const string_type = try benchmark_suite.type_registry.registerType("string", .primitive, &.{});

        const types = [_]TypeId{ int_type, float_type, string_type };

        // Benchmark different table sizes
        const small_results = try benchmark_suite.benchmarkTableSize(10, &types);
        const medium_results = try benchmark_suite.benchmarkTableSize(50, &types);
        const large_results = try benchmark_suite.benchmarkTableSize(100, &types);

        self.baseline_results = BenchmarkBaseline{
            .small_table_lookup_ns = small_results.lookup_performance.decision_tree_ns,
            .medium_table_lookup_ns = medium_results.lookup_performance.decision_tree_ns,
            .large_table_lookup_ns = large_results.lookup_performance.decision_tree_ns,
            .memory_efficiency = (small_results.cache_efficiency + medium_results.cache_efficiency + large_results.cache_efficiency) / 3.0,
        };
    }

    /// Run regression tests against baseline
    pub fn runRegressionTests(self: *Self, writer: anytype) !bool {
        if (self.baseline_results == null) {
            try writer.print("No baseline established. Run establishBaseline() first.\n");
            return false;
        }

        const baseline = self.baseline_results.?;

        var benchmark_suite = try DispatchBenchmarkSuite.init(self.allocator);
        defer benchmark_suite.deinit();

        // Setup test types
        const int_type = try benchmark_suite.type_registry.registerType("int", .primitive, &.{});
        const float_type = try benchmark_suite.type_registry.registerType("float", .primitive, &.{});
        const string_type = try benchmark_suite.type_registry.registerType("string", .primitive, &.{});

        const types = [_]TypeId{ int_type, float_type, string_type };

        // Run current benchmarks
        const small_results = try benchmark_suite.benchmarkTableSize(10, &types);
        const medium_results = try benchmark_suite.benchmarkTableSize(50, &types);
        const large_results = try benchmark_suite.benchmarkTableSize(100, &types);

        const current_memory_efficiency = (small_results.cache_efficiency + medium_results.cache_efficiency + large_results.cache_efficiency) / 3.0;

        // Check for regressions (allow 10% tolerance)
        const tolerance = 1.1;
        var passed = true;

        try writer.print("Performance Regression Test Results\n");
        try writer.print("===================================\n");

        // Small table test
        const small_ratio = @as(f32, @floatFromInt(small_results.lookup_performance.decision_tree_ns)) / @as(f32, @floatFromInt(baseline.small_table_lookup_ns));
        try writer.print("Small Table (10 impls): {d:.2}x baseline", .{small_ratio});
        if (small_ratio > tolerance) {
            try writer.print(" - REGRESSION!\n");
            passed = false;
        } else {
            try writer.print(" - PASS\n");
        }

        // Medium table test
        const medium_ratio = @as(f32, @floatFromInt(medium_results.lookup_performance.decision_tree_ns)) / @as(f32, @floatFromInt(baseline.medium_table_lookup_ns));
        try writer.print("Medium Table (50 impls): {d:.2}x baseline", .{medium_ratio});
        if (medium_ratio > tolerance) {
            try writer.print(" - REGRESSION!\n");
            passed = false;
        } else {
            try writer.print(" - PASS\n");
        }

        // Large table test
        const large_ratio = @as(f32, @floatFromInt(large_results.lookup_performance.decision_tree_ns)) / @as(f32, @floatFromInt(baseline.large_table_lookup_ns));
        try writer.print("Large Table (100 impls): {d:.2}x baseline", .{large_ratio});
        if (large_ratio > tolerance) {
            try writer.print(" - REGRESSION!\n");
            passed = false;
        } else {
            try writer.print(" - PASS\n");
        }

        // Memory efficiency test
        const memory_ratio = current_memory_efficiency / baseline.memory_efficiency;
        try writer.print("Memory Efficiency: {d:.2}x baseline", .{memory_ratio});
        if (memory_ratio < 0.9) { // Memory efficiency should not decrease significantly
            try writer.print(" - REGRESSION!\n");
            passed = false;
        } else {
            try writer.print(" - PASS\n");
        }

        try writer.print("\nOverall Result: {s}\n", .{if (passed) "PASS" else "FAIL"});

        return passed;
    }
};
// Tests

test "DispatchBenchmarkSuite basic functionality" {
    const allocator = testing.allocator;

    var benchmark_suite = try DispatchBenchmarkSuite.init(allocator);
    defer benchmark_suite.deinit();

    // Test that benchmark suite initializes correctly
    try testing.expect(benchmark_suite.allocator.ptr == allocator.ptr);
}

test "DispatchBenchmarkSuite table size benchmarking" {
    const allocator = testing.allocator;

    var benchmark_suite = try DispatchBenchmarkSuite.init(allocator);
    defer benchmark_suite.deinit();

    // Setup test types
    const int_type = try benchmark_suite.type_registry.registerType("int", .primitive, &.{});
    const float_type = try benchmark_suite.type_registry.registerType("float", .primitive, &.{});

    const types = [_]TypeId{ int_type, float_type };

    // Run benchmark for small table
    const results = try benchmark_suite.benchmarkTableSize(5, &types);

    // Verify results
    try testing.expectEqual(@as(u32, 5), results.table_size);
    try testing.expect(results.lookup_performance.linear_search_ns > 0);
    try testing.expect(results.lookup_performance.compressed_pattern_ns > 0);
    try testing.expect(results.memory_usage.total_bytes > 0);
    try testing.expect(results.cache_efficiency >= 0.0);
    try testing.expect(results.cache_efficiency <= 1.0);
}

test "DispatchBenchmarkSuite access pattern benchmarking" {
    const allocator = testing.allocator;

    var benchmark_suite = try DispatchBenchmarkSuite.init(allocator);
    defer benchmark_suite.deinit();

    // Setup test types
    const int_type = try benchmark_suite.type_registry.registerType("int", .primitive, &.{});
    const float_type = try benchmark_suite.type_registry.registerType("float", .primitive, &.{});

    const types = [_]TypeId{ int_type, float_type };

    // Run access pattern benchmark
    const results = try benchmark_suite.benchmarkAccessPatterns(&types);

    // Verify all access patterns were tested
    try testing.expect(results.sequential_access_ns > 0);
    try testing.expect(results.random_access_ns > 0);
    try testing.expect(results.hot_path_access_ns > 0);
}

test "PerformanceRegressionTests baseline and regression testing" {
    const allocator = testing.allocator;

    var regression_tests = PerformanceRegressionTests.init(allocator);

    // Establish baseline
    try regression_tests.establishBaseline();
    try testing.expect(regression_tests.baseline_results != null);

    const baseline = regression_tests.baseline_results.?;
    try testing.expect(baseline.small_table_lookup_ns > 0);
    try testing.expect(baseline.medium_table_lookup_ns > 0);
    try testing.expect(baseline.large_table_lookup_ns > 0);
    try testing.expect(baseline.memory_efficiency >= 0.0);
    try testing.expect(baseline.memory_efficiency <= 1.0);

    // Run regression tests
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    const passed = try regression_tests.runRegressionTests(buffer.writer());

    // Should pass since we're testing against the same implementation
    try testing.expect(passed);
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Performance Regression Test Results") != null);
}

test "Benchmark result formatting" {
    const allocator = testing.allocator;

    // Create test benchmark results
    const lookup_results = OptimizedDispatchTable.BenchmarkResults{
        .linear_search_ns = 1000,
        .decision_tree_ns = 500,
        .compressed_pattern_ns = 750,
        .cache_misses = 10,
    };

    const memory_stats = OptimizedDispatchTable.MemoryStats{
        .total_bytes = 2048,
        .entry_bytes = 1024,
        .tree_bytes = 512,
        .metadata_bytes = 512,
        .cache_lines_used = 32,
        .cache_efficiency = 0.75,
    };

    const benchmark_results = DispatchBenchmarkSuite.BenchmarkResults{
        .table_size = 25,
        .lookup_performance = lookup_results,
        .memory_usage = memory_stats,
        .cache_efficiency = 0.75,
    };

    // Test formatting
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{benchmark_results});

    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Table Size: 25") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Decision Tree Speedup") != null);

    // Test access pattern results formatting
    buffer.clearRetainingCapacity();

    const access_results = DispatchBenchmarkSuite.AccessPatternResults{
        .sequential_access_ns = 1000,
        .random_access_ns = 1200,
        .hot_path_access_ns = 900,
    };

    try std.fmt.format(buffer.writer(), "{}", .{access_results});

    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Access Pattern Performance") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Random vs Sequential") != null);
}
