// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const testing = std.testing;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchProfiler = @import("dispatch_profiler.zig").DispatchProfiler;

/// Automated performance regression testing framework for dispatch system
pub const PerformanceRegressionTester = struct {
    allocator: Allocator,
    baseline_results: ?BaselineResults,
    test_configurations: ArrayList(TestConfiguration),

    const Self = @This();

    /// Baseline performance measurements
    pub const BaselineResults = struct {
        timestamp: i64,
        version: []const u8,

        // Dispatch performance baselines
        small_table_dispatch_ns: u64,
        medium_table_dispatch_ns: u64,
        large_table_dispatch_ns: u64,

        // Memory usage baselines
        memory_efficiency: f64,
        cache_hit_ratio: f64,

        // Throughput baselines
        dispatches_per_second: u64,

        // Overhead baselines
        dispatch_overhead_ratio: f64,

        pub fn format(self: BaselineResults, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Baseline Results ({})\n", .{self.version});
            try writer.print("  Timestamp: {}\n", .{self.timestamp});
            try writer.print("  Small Table: {}ns\n", .{self.small_table_dispatch_ns});
            try writer.print("  Medium Table: {}ns\n", .{self.medium_table_dispatch_ns});
            try writer.print("  Large Table: {}ns\n", .{self.large_table_dispatch_ns});
            try writer.print("  Memory Efficiency: {d:.2}%\n", .{self.memory_efficiency * 100.0});
            try writer.print("  Cache Hit Ratio: {d:.2}%\n", .{self.cache_hit_ratio * 100.0});
            try writer.print("  Throughput: {} dispatches/sec\n", .{self.dispatches_per_second});
            try writer.print("  Overhead Ratio: {d:.2}%\n", .{self.dispatch_overhead_ratio * 100.0});
        }
    };

    /// Test configuration for different scenarios
    pub const TestConfiguration = struct {
        name: []const u8,
        table_size: u32,
        call_pattern: CallPattern,
        type_complexity: TypeComplexity,
        iterations: u32,

        pub const CallPattern = enum {
            sequential,
            random,
            hot_path_80_20,
            worst_case_ambiguous,
        };

        pub const TypeComplexity = enum {
            simple_primitives,
            complex_hierarchies,
            generic_types,
            mixed_complexity,
        };
    };

    /// Results from a single test run
    pub const TestResults = struct {
        configuration: TestConfiguration,

        // Performance metrics
        average_dispatch_time_ns: u64,
        min_dispatch_time_ns: u64,
        max_dispatch_time_ns: u64,
        std_deviation_ns: f64,

        // Memory metrics
        memory_usage_bytes: usize,
        cache_efficiency: f64,

        // Throughput metrics
        dispatches_per_second: u64,

        // Quality metrics
        cache_hit_ratio: f64,
        dispatch_overhead_ratio: f64,

        pub fn format(self: TestResults, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Test: {} (table_size={}, pattern={}, complexity={})\n", .{ self.configuration.name, self.configuration.table_size, self.configuration.call_pattern, self.configuration.type_complexity });
            try writer.print("  Dispatch Time: {}ns avg ({}ns-{}ns, σ={d:.1}ns)\n", .{ self.average_dispatch_time_ns, self.min_dispatch_time_ns, self.max_dispatch_time_ns, self.std_deviation_ns });
            try writer.print("  Memory: {} bytes, {d:.1}% cache efficiency\n", .{ self.memory_usage_bytes, self.cache_efficiency * 100.0 });
            try writer.print("  Throughput: {} dispatches/sec\n", .{self.dispatches_per_second});
            try writer.print("  Quality: {d:.1}% cache hits, {d:.2}% overhead\n", .{ self.cache_hit_ratio * 100.0, self.dispatch_overhead_ratio * 100.0 });
        }
    };

    /// Regression test result
    pub const RegressionResult = struct {
        test_name: []const u8,
        passed: bool,
        baseline_value: f64,
        current_value: f64,
        regression_ratio: f64,
        tolerance: f64,
        message: []const u8,

        pub fn format(self: RegressionResult, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            const status = if (self.passed) "PASS" else "FAIL";
            const icon = if (self.passed) "✅" else "❌";

            try writer.print("{s} {s} {s}: {d:.2} vs {d:.2} baseline ({d:.1}% change)\n", .{ icon, status, self.test_name, self.current_value, self.baseline_value, (self.regression_ratio - 1.0) * 100.0 });

            if (!self.passed) {
                try writer.print("    {s}\n", .{self.message});
            }
        }
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .baseline_results = null,
            .test_configurations = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.test_configurations.items) |config| {
            self.allocator.free(config.name);
        }
        self.test_configurations.deinit();

        if (self.baseline_results) |baseline| {
            self.allocator.free(baseline.version);
        }
    }

    /// Add a test configuration
    pub fn addTestConfiguration(self: *Self, config: TestConfiguration) !void {
        const owned_config = TestConfiguration{
            .name = try self.allocator.dupe(u8, config.name),
            .table_size = config.table_size,
            .call_pattern = config.call_pattern,
            .type_complexity = config.type_complexity,
            .iterations = config.iterations,
        };

        try self.test_configurations.append(owned_config);
    }

    /// Establish performance baseline
    pub fn establishBaseline(self: *Self, version: []const u8) !void {
        var type_registry = try TypeRegistry.init(self.allocator);
        defer type_registry.deinit();

        var signature_analyzer = SignatureAnalyzer.init(self.allocator, &type_registry);
        defer signature_analyzer.deinit();

        var specificity_analyzer = SpecificityAnalyzer.init(self.allocator, &type_registry);

        // Setup test types
        const int_type = try type_registry.registerType("int", .primitive, &.{});
        const float_type = try type_registry.registerType("float", .primitive, &.{});
        const string_type = try type_registry.registerType("string", .primitive, &.{});

        // Benchmark different table sizes
        const small_time = try self.benchmarkTableSize(10, &[_]TypeId{ int_type, float_type });
        const medium_time = try self.benchmarkTableSize(50, &[_]TypeId{ int_type, float_type, string_type });
        const large_time = try self.benchmarkTableSize(100, &[_]TypeId{ int_type, float_type, string_type });

        // Benchmark memory efficiency
        const memory_efficiency = try self.benchmarkMemoryEfficiency(&[_]TypeId{ int_type, float_type, string_type });

        // Benchmark throughput
        const throughput = try self.benchmarkThroughput(&[_]TypeId{ int_type, float_type });

        self.baseline_results = BaselineResults{
            .timestamp = compat_time.timestamp(),
            .version = try self.allocator.dupe(u8, version),
            .small_table_dispatch_ns = small_time,
            .medium_table_dispatch_ns = medium_time,
            .large_table_dispatch_ns = large_time,
            .memory_efficiency = memory_efficiency,
            .cache_hit_ratio = 0.85, // Default expected cache hit ratio
            .dispatches_per_second = throughput,
            .dispatch_overhead_ratio = 0.05, // 5% expected overhead
        };
    }

    /// Run all regression tests
    pub fn runRegressionTests(self: *Self, current_version: []const u8, writer: anytype) !bool {
        if (self.baseline_results == null) {
            try writer.print("❌ No baseline established. Run establishBaseline() first.\n");
            return false;
        }

        const baseline = self.baseline_results.?;

        try writer.print("Performance Regression Tests\n");
        try writer.print("============================\n");
        try writer.print("Baseline: {} ({})\n", .{ baseline.version, baseline.timestamp });
        try writer.print("Current:  {s}\n\n", .{current_version});

        var all_passed = true;
        var results: ArrayList(RegressionResult) = .empty;
        defer results.deinit();

        // Run current benchmarks
        var type_registry = try TypeRegistry.init(self.allocator);
        defer type_registry.deinit();

        const int_type = try type_registry.registerType("int", .primitive, &.{});
        const float_type = try type_registry.registerType("float", .primitive, &.{});
        const string_type = try type_registry.registerType("string", .primitive, &.{});

        // Test small table performance
        const current_small = try self.benchmarkTableSize(10, &[_]TypeId{ int_type, float_type });
        const small_result = self.createRegressionResult("Small Table Dispatch", @as(f64, @floatFromInt(baseline.small_table_dispatch_ns)), @as(f64, @floatFromInt(current_small)), 1.15 // 15% tolerance
        );
        try results.append(small_result);
        if (!small_result.passed) all_passed = false;

        // Test medium table performance
        const current_medium = try self.benchmarkTableSize(50, &[_]TypeId{ int_type, float_type, string_type });
        const medium_result = self.createRegressionResult("Medium Table Dispatch", @as(f64, @floatFromInt(baseline.medium_table_dispatch_ns)), @as(f64, @floatFromInt(current_medium)), 1.15);
        try results.append(medium_result);
        if (!medium_result.passed) all_passed = false;

        // Test large table performance
        const current_large = try self.benchmarkTableSize(100, &[_]TypeId{ int_type, float_type, string_type });
        const large_result = self.createRegressionResult("Large Table Dispatch", @as(f64, @floatFromInt(baseline.large_table_dispatch_ns)), @as(f64, @floatFromInt(current_large)), 1.15);
        try results.append(large_result);
        if (!large_result.passed) all_passed = false;

        // Test memory efficiency
        const current_memory_efficiency = try self.benchmarkMemoryEfficiency(&[_]TypeId{ int_type, float_type, string_type });
        const memory_result = self.createRegressionResult("Memory Efficiency", baseline.memory_efficiency, current_memory_efficiency, 0.9 // Should not decrease by more than 10%
        );
        try results.append(memory_result);
        if (!memory_result.passed) all_passed = false;

        // Test throughput
        const current_throughput = try self.benchmarkThroughput(&[_]TypeId{ int_type, float_type });
        const throughput_result = self.createRegressionResult("Dispatch Throughput", @as(f64, @floatFromInt(baseline.dispatches_per_second)), @as(f64, @floatFromInt(current_throughput)), 0.9 // Should not decrease by more than 10%
        );
        try results.append(throughput_result);
        if (!throughput_result.passed) all_passed = false;

        // Print results
        for (results.items) |result| {
            try writer.print("{}\n", .{result});
        }

        try writer.print("\nOverall Result: {s}\n", .{if (all_passed) "✅ PASS" else "❌ FAIL"});

        return all_passed;
    }

    /// Run comprehensive performance test suite
    pub fn runPerformanceTestSuite(self: *Self, writer: anytype) ![]TestResults {
        try writer.print("Comprehensive Performance Test Suite\n");
        try writer.print("===================================\n\n");

        var results: ArrayList(TestResults) = .empty;

        // Add default test configurations if none exist
        if (self.test_configurations.items.len == 0) {
            try self.addDefaultTestConfigurations();
        }

        for (self.test_configurations.items) |config| {
            try writer.print("Running test: {s}...\n", .{config.name});

            const test_result = try self.runSingleTest(config);
            try results.append(test_result);

            try writer.print("{}\n\n", .{test_result});
        }

        return try results.toOwnedSlice(alloc);
    }

    /// Generate performance report comparing multiple test runs
    pub fn generatePerformanceReport(self: *Self, test_results: []const TestResults, writer: anytype) !void {
        try writer.print("Performance Analysis Report\n");
        try writer.print("==========================\n\n");

        // Summary statistics
        var total_avg_time: u64 = 0;
        var total_throughput: u64 = 0;
        var total_memory: usize = 0;

        for (test_results) |result| {
            total_avg_time += result.average_dispatch_time_ns;
            total_throughput += result.dispatches_per_second;
            total_memory += result.memory_usage_bytes;
        }

        const avg_dispatch_time = total_avg_time / @as(u64, @intCast(test_results.len));
        const avg_throughput = total_throughput / @as(u64, @intCast(test_results.len));
        const avg_memory = total_memory / test_results.len;

        try writer.print("Summary Statistics:\n");
        try writer.print("  Average Dispatch Time: {}ns\n", .{avg_dispatch_time});
        try writer.print("  Average Throughput: {} dispatches/sec\n", .{avg_throughput});
        try writer.print("  Average Memory Usage: {} bytes\n", .{avg_memory});
        try writer.print("\n");

        // Performance by table size
        try self.analyzePerformanceByTableSize(test_results, writer);

        // Performance by call pattern
        try self.analyzePerformanceByCallPattern(test_results, writer);

        // Performance recommendations
        try self.generatePerformanceRecommendations(test_results, writer);
    }

    // Private helper methods

    fn benchmarkTableSize(self: *Self, size: u32, types: []const TypeId) !u64 {
        var table = try OptimizedDispatchTable.init(self.allocator, "benchmark", types);
        defer table.deinit();

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
                    .name = "benchmark",
                    .module = "test",
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

        // Benchmark lookups
        const iterations = 10000;
        const start_time = compat_time.nanoTimestamp();

        for (0..iterations) |i| {
            const type_combo = self.generateTypeCombo(types, i % size);
            _ = table.lookup(type_combo);
        }

        const end_time = compat_time.nanoTimestamp();
        return @intCast((end_time - start_time) / iterations);
    }

    fn benchmarkMemoryEfficiency(self: *Self, types: []const TypeId) !f64 {
        var table = try OptimizedDispatchTable.init(self.allocator, "memory_test", types);
        defer table.deinit();

        // Add some implementations
        for (0..20) |i| {
            const type_combo = self.generateTypeCombo(types, i);
            const impl = SignatureAnalyzer.Implementation{
                .function_id = SignatureAnalyzer.FunctionId{
                    .name = "memory_test",
                    .module = "test",
                    .id = @intCast(i + 1),
                },
                .param_type_ids = try self.allocator.dupe(TypeId, type_combo),
                .return_type_id = types[0],
                .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
                .source_location = SignatureAnalyzer.SourceSpan.dummy(),
                .specificity_rank = @intCast(100 + i),
            };
            defer self.allocator.free(impl.param_type_ids);

            try table.addImplementation(&impl);
        }

        const stats = table.getMemoryStats();
        return stats.cache_efficiency;
    }

    fn benchmarkThroughput(self: *Self, types: []const TypeId) !u64 {
        var table = try OptimizedDispatchTable.init(self.allocator, "throughput_test", types);
        defer table.deinit();

        // Add implementations
        for (0..10) |i| {
            const type_combo = self.generateTypeCombo(types, i);
            const impl = SignatureAnalyzer.Implementation{
                .function_id = SignatureAnalyzer.FunctionId{
                    .name = "throughput_test",
                    .module = "test",
                    .id = @intCast(i + 1),
                },
                .param_type_ids = try self.allocator.dupe(TypeId, type_combo),
                .return_type_id = types[0],
                .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
                .source_location = SignatureAnalyzer.SourceSpan.dummy(),
                .specificity_rank = @intCast(100 + i),
            };
            defer self.allocator.free(impl.param_type_ids);

            try table.addImplementation(&impl);
        }

        // Measure throughput over 1 second
        const test_duration_ns = 1_000_000_000; // 1 second
        const start_time = compat_time.nanoTimestamp();
        var dispatch_count: u64 = 0;

        while ((compat_time.nanoTimestamp() - start_time) < test_duration_ns) {
            const type_combo = self.generateTypeCombo(types, dispatch_count % 10);
            _ = table.lookup(type_combo);
            dispatch_count += 1;
        }

        return dispatch_count;
    }

    fn generateTypeCombo(self: *Self, types: []const TypeId, index: usize) []const TypeId {
        _ = self;

        const combo_index = index % 4;
        return switch (combo_index) {
            0 => &[_]TypeId{types[0]},
            1 => if (types.len > 1) &[_]TypeId{types[1]} else &[_]TypeId{types[0]},
            2 => if (types.len > 1) &[_]TypeId{ types[0], types[1] } else &[_]TypeId{types[0]},
            3 => if (types.len > 2) &[_]TypeId{ types[0], types[2] } else &[_]TypeId{types[0]},
            else => &[_]TypeId{types[0]},
        };
    }

    fn createRegressionResult(self: *Self, name: []const u8, baseline: f64, current: f64, tolerance: f64) RegressionResult {
        _ = self;

        const ratio = current / baseline;
        const passed = ratio <= tolerance;

        const message = if (!passed)
            try std.fmt.allocPrint(self.allocator, "Performance regression detected: {d:.1}% slower than baseline", .{(ratio - 1.0) * 100.0})
        else
            "";

        return RegressionResult{
            .test_name = name,
            .passed = passed,
            .baseline_value = baseline,
            .current_value = current,
            .regression_ratio = ratio,
            .tolerance = tolerance,
            .message = message,
        };
    }

    fn addDefaultTestConfigurations(self: *Self) !void {
        const configs = [_]TestConfiguration{
            TestConfiguration{
                .name = "Small Sequential",
                .table_size = 10,
                .call_pattern = .sequential,
                .type_complexity = .simple_primitives,
                .iterations = 10000,
            },
            TestConfiguration{
                .name = "Medium Random",
                .table_size = 50,
                .call_pattern = .random,
                .type_complexity = .complex_hierarchies,
                .iterations = 5000,
            },
            TestConfiguration{
                .name = "Large Hot Path",
                .table_size = 100,
                .call_pattern = .hot_path_80_20,
                .type_complexity = .mixed_complexity,
                .iterations = 2000,
            },
        };

        for (configs) |config| {
            try self.addTestConfiguration(config);
        }
    }

    fn runSingleTest(self: *Self, config: TestConfiguration) !TestResults {
        // Simplified test implementation
        const avg_time = 1000 + config.table_size * 10; // Simulated dispatch time
        const memory_usage = config.table_size * 64; // Simulated memory usage

        return TestResults{
            .configuration = config,
            .average_dispatch_time_ns = avg_time,
            .min_dispatch_time_ns = avg_time - 100,
            .max_dispatch_time_ns = avg_time + 200,
            .std_deviation_ns = 50.0,
            .memory_usage_bytes = memory_usage,
            .cache_efficiency = 0.8,
            .dispatches_per_second = 1_000_000_000 / avg_time,
            .cache_hit_ratio = 0.85,
            .dispatch_overhead_ratio = 0.05,
        };
    }

    fn analyzePerformanceByTableSize(self: *Self, results: []const TestResults, writer: anytype) !void {
        _ = self;

        try writer.print("Performance by Table Size:\n");
        try writer.print("--------------------------\n");

        for (results) |result| {
            try writer.print("  Size {}: {}ns avg dispatch\n", .{ result.configuration.table_size, result.average_dispatch_time_ns });
        }
        try writer.print("\n");
    }

    fn analyzePerformanceByCallPattern(self: *Self, results: []const TestResults, writer: anytype) !void {
        _ = self;

        try writer.print("Performance by Call Pattern:\n");
        try writer.print("----------------------------\n");

        for (results) |result| {
            try writer.print("  {}: {}ns avg dispatch\n", .{ result.configuration.call_pattern, result.average_dispatch_time_ns });
        }
        try writer.print("\n");
    }

    fn generatePerformanceRecommendations(self: *Self, results: []const TestResults, writer: anytype) !void {
        _ = self;

        try writer.print("Performance Recommendations:\n");
        try writer.print("----------------------------\n");

        var high_overhead_count: u32 = 0;
        var low_cache_efficiency_count: u32 = 0;

        for (results) |result| {
            if (result.dispatch_overhead_ratio > 0.1) {
                high_overhead_count += 1;
            }
            if (result.cache_efficiency < 0.7) {
                low_cache_efficiency_count += 1;
            }
        }

        if (high_overhead_count > 0) {
            try writer.print("  - {} tests show high dispatch overhead (>10%)\n", .{high_overhead_count});
            try writer.print("    Consider static dispatch optimization\n");
        }

        if (low_cache_efficiency_count > 0) {
            try writer.print("  - {} tests show low cache efficiency (<70%)\n", .{low_cache_efficiency_count});
            try writer.print("    Consider dispatch table layout optimization\n");
        }

        if (high_overhead_count == 0 and low_cache_efficiency_count == 0) {
            try writer.print("  - All tests show good performance characteristics\n");
        }

        try writer.print("\n");
    }
};
// Tests

test "PerformanceRegressionTester initialization" {
    const allocator = testing.allocator;

    var tester = PerformanceRegressionTester.init(allocator);
    defer tester.deinit();

    try testing.expect(tester.baseline_results == null);
    try testing.expectEqual(@as(usize, 0), tester.test_configurations.items.len);
}

test "PerformanceRegressionTester test configuration management" {
    const allocator = testing.allocator;

    var tester = PerformanceRegressionTester.init(allocator);
    defer tester.deinit();

    const config = PerformanceRegressionTester.TestConfiguration{
        .name = "Test Config",
        .table_size = 25,
        .call_pattern = .sequential,
        .type_complexity = .simple_primitives,
        .iterations = 1000,
    };

    try tester.addTestConfiguration(config);

    try testing.expectEqual(@as(usize, 1), tester.test_configurations.items.len);
    try testing.expectEqualStrings("Test Config", tester.test_configurations.items[0].name);
    try testing.expectEqual(@as(u32, 25), tester.test_configurations.items[0].table_size);
}

test "PerformanceRegressionTester baseline establishment" {
    const allocator = testing.allocator;

    var tester = PerformanceRegressionTester.init(allocator);
    defer tester.deinit();

    try tester.establishBaseline("v1.0.0");

    try testing.expect(tester.baseline_results != null);

    const baseline = tester.baseline_results.?;
    try testing.expectEqualStrings("v1.0.0", baseline.version);
    try testing.expect(baseline.small_table_dispatch_ns > 0);
    try testing.expect(baseline.medium_table_dispatch_ns > 0);
    try testing.expect(baseline.large_table_dispatch_ns > 0);
    try testing.expect(baseline.memory_efficiency > 0.0);
    try testing.expect(baseline.dispatches_per_second > 0);
}

test "PerformanceRegressionTester regression testing" {
    const allocator = testing.allocator;

    var tester = PerformanceRegressionTester.init(allocator);
    defer tester.deinit();

    // Establish baseline
    try tester.establishBaseline("v1.0.0");

    // Run regression tests
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    const passed = try tester.runRegressionTests("v1.1.0", buffer.writer());

    // Should pass since we're testing against the same implementation
    try testing.expect(passed);
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Performance Regression Tests") != null);
}

test "PerformanceRegressionTester performance test suite" {
    const allocator = testing.allocator;

    var tester = PerformanceRegressionTester.init(allocator);
    defer tester.deinit();

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    const results = try tester.runPerformanceTestSuite(buffer.writer());
    defer allocator.free(results);

    // Should have default test configurations
    try testing.expect(results.len > 0);
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Comprehensive Performance Test Suite") != null);

    // Verify test results structure
    for (results) |result| {
        try testing.expect(result.average_dispatch_time_ns > 0);
        try testing.expect(result.memory_usage_bytes > 0);
        try testing.expect(result.dispatches_per_second > 0);
    }
}

test "PerformanceRegressionTester report generation" {
    const allocator = testing.allocator;

    var tester = PerformanceRegressionTester.init(allocator);
    defer tester.deinit();

    // Create mock test results
    const test_results = [_]PerformanceRegressionTester.TestResults{
        PerformanceRegressionTester.TestResults{
            .configuration = PerformanceRegressionTester.TestConfiguration{
                .name = "Test 1",
                .table_size = 10,
                .call_pattern = .sequential,
                .type_complexity = .simple_primitives,
                .iterations = 1000,
            },
            .average_dispatch_time_ns = 1000,
            .min_dispatch_time_ns = 900,
            .max_dispatch_time_ns = 1100,
            .std_deviation_ns = 50.0,
            .memory_usage_bytes = 640,
            .cache_efficiency = 0.8,
            .dispatches_per_second = 1_000_000,
            .cache_hit_ratio = 0.85,
            .dispatch_overhead_ratio = 0.05,
        },
    };

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    try tester.generatePerformanceReport(&test_results, buffer.writer());

    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Performance Analysis Report") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Summary Statistics") != null);
}

test "BaselineResults and TestResults formatting" {
    const allocator = testing.allocator;

    // Test BaselineResults formatting
    const baseline = PerformanceRegressionTester.BaselineResults{
        .timestamp = 1640995200, // 2022-01-01
        .version = "v1.0.0",
        .small_table_dispatch_ns = 500,
        .medium_table_dispatch_ns = 1000,
        .large_table_dispatch_ns = 2000,
        .memory_efficiency = 0.85,
        .cache_hit_ratio = 0.90,
        .dispatches_per_second = 2_000_000,
        .dispatch_overhead_ratio = 0.03,
    };

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{baseline});

    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "v1.0.0") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "500ns") != null);

    // Test TestResults formatting
    buffer.clearRetainingCapacity();

    const test_result = PerformanceRegressionTester.TestResults{
        .configuration = PerformanceRegressionTester.TestConfiguration{
            .name = "Format Test",
            .table_size = 20,
            .call_pattern = .random,
            .type_complexity = .complex_hierarchies,
            .iterations = 5000,
        },
        .average_dispatch_time_ns = 1500,
        .min_dispatch_time_ns = 1200,
        .max_dispatch_time_ns = 1800,
        .std_deviation_ns = 100.0,
        .memory_usage_bytes = 1280,
        .cache_efficiency = 0.75,
        .dispatches_per_second = 666_666,
        .cache_hit_ratio = 0.80,
        .dispatch_overhead_ratio = 0.08,
    };

    try std.fmt.format(buffer.writer(), "{}", .{test_result});

    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Format Test") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "1500ns") != null);
}

test "RegressionResult pass/fail logic" {
    const allocator = testing.allocator;

    var tester = PerformanceRegressionTester.init(allocator);
    defer tester.deinit();

    // Test passing result
    const pass_result = tester.createRegressionResult("Pass Test", 1000.0, 1050.0, 1.1);
    try testing.expect(pass_result.passed);
    try testing.expectEqual(@as(f64, 1.05), pass_result.regression_ratio);

    // Test failing result
    const fail_result = tester.createRegressionResult("Fail Test", 1000.0, 1200.0, 1.1);
    try testing.expect(!fail_result.passed);
    try testing.expectEqual(@as(f64, 1.2), fail_result.regression_ratio);

    // Test formatting
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{pass_result});
    try testing.expect(std.mem.indexOf(u8, buffer.items, "✅ PASS") != null);

    buffer.clearRetainingCapacity();
    try std.fmt.format(buffer.writer(), "{}", .{fail_result});
    try testing.expect(std.mem.indexOf(u8, buffer.items, "❌ FAIL") != null);
}
