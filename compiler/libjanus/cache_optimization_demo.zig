// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchBenchmarkSuite = @import("dispatch_benchmarks.zig").DispatchBenchmarkSuite;
const PerformanceRegressionTests = @import("dispatch_benchmarks.zig").PerformanceRegressionTests;

/// Demonstration of cache-friendly dispatch table optimizations
pub fn runCacheOptimizationDemo(allocator: Allocator, writer: anytype) !void {
    try writer.print("Cache-Friendly Dispatch Table Optimization Demo\n");
    try writer.print("===============================================\n\n");

    // Initialize components
    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    // Register test types
    const int_type = try type_registry.registerType("int", .primitive, &.{});
    const float_type = try type_registry.registerType("float", .primitive, &.{});
    const string_type = try type_registry.registerType("string", .primitive, &.{});
    const bool_type = try type_registry.registerType("bool", .primitive, &.{});

    try writer.print("1. Cache-Line Alignment Demonstration\n");
    try writer.print("-------------------------------------\n");

    var table = try OptimizedDispatchTable.init(allocator, "demo_func", &[_]TypeId{int_type});
    defer table.deinit();

    // Show memory alignment
    try writer.print("DispatchEntry size: {} bytes (cache-line aligned)\n", .{@sizeOf(OptimizedDispatchTable.DispatchEntry)});
    try writer.print("DecisionTreeNode size: {} bytes (cache-line aligned)\n", .{@sizeOf(OptimizedDispatchTable.DecisionTreeNode)});

    // Add implementations to demonstrate layout
    const implementations = [_]SignatureAnalyzer.Implementation{
        SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{ .name = "demo_func", .module = "demo", .id = 1 },
            .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{int_type}),
            .return_type_id = int_type,
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 100,
        },
        SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{ .name = "demo_func", .module = "demo", .id = 2 },
            .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{float_type}),
            .return_type_id = float_type,
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 100,
        },
        SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{ .name = "demo_func", .module = "demo", .id = 3 },
            .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{string_type}),
            .return_type_id = string_type,
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 100,
        },
    };

    defer {
        for (implementations) |impl| {
            allocator.free(impl.param_type_ids);
        }
    }

    for (implementations) |*impl| {
        try table.addImplementation(impl);
    }

    const initial_stats = table.getMemoryStats();
    try writer.print("Initial memory stats: {}\n", .{initial_stats});

    // Demonstrate entry alignment
    if (table.entries.len > 0) {
        const entry_ptr = @intFromPtr(table.entries.ptr);
        try writer.print("Entry array alignment: {} bytes ({})\n", .{ entry_ptr % 64, if (entry_ptr % 64 == 0) "aligned" else "misaligned" });
    }

    try writer.print("\n2. Decision Tree Optimization\n");
    try writer.print("-----------------------------\n");

    if (table.decision_tree) |tree| {
        try writer.print("Decision tree built for {} implementations\n", .{table.entry_count});
        try writer.print("Tree root discriminator: type index {}, type id {}\n", .{ tree.discriminator_type_index, tree.discriminator_type_id });
    } else {
        try writer.print("No decision tree (table too small)\n");
    }

    try writer.print("\n3. Lookup Performance Comparison\n");
    try writer.print("---------------------------------\n");

    // Create test cases
    const test_cases = [_][]const TypeId{
        &[_]TypeId{int_type},
        &[_]TypeId{float_type},
        &[_]TypeId{string_type},
    };

    const benchmark_results = try table.benchmarkLookupStrategies(&test_cases, 10000);
    try writer.print("{}\n", .{benchmark_results});

    try writer.print("\n4. Layout Optimization Demo\n");
    try writer.print("---------------------------\n");

    // Simulate different call frequencies
    const args = [_]TypeId{int_type};
    for (0..100) |_| {
        _ = table.lookup(&args); // Make int_type hot
    }

    const float_args = [_]TypeId{float_type};
    for (0..10) |_| {
        _ = table.lookup(&float_args); // Make float_type warm
    }

    const string_args = [_]TypeId{string_type};
    for (0..1) |_| {
        _ = table.lookup(&string_args); // Make string_type cold
    }

    try writer.print("Before optimization:\n");
    for (table.entries[0..table.entry_count], 0..) |entry, i| {
        try writer.print("  Entry {}: call frequency = {}\n", .{ i, entry.call_frequency });
    }

    // Optimize layout based on frequency
    try table.optimizeLayout();

    try writer.print("After optimization (hot entries first):\n");
    for (table.entries[0..table.entry_count], 0..) |entry, i| {
        try writer.print("  Entry {}: call frequency = {}\n", .{ i, entry.call_frequency });
    }

    const optimized_stats = table.getMemoryStats();
    try writer.print("Optimized memory stats: {}\n", .{optimized_stats});

    try writer.print("\n5. Comprehensive Benchmark Suite\n");
    try writer.print("---------------------------------\n");

    var benchmark_suite = try DispatchBenchmarkSuite.init(allocator);
    defer benchmark_suite.deinit();

    try benchmark_suite.runComprehensiveBenchmark(writer);

    try writer.print("\n6. Performance Regression Testing\n");
    try writer.print("----------------------------------\n");

    var regression_tests = PerformanceRegressionTests.init(allocator);

    try writer.print("Establishing performance baseline...\n");
    try regression_tests.establishBaseline();

    try writer.print("Running regression tests...\n");
    const passed = try regression_tests.runRegressionTests(writer);

    if (passed) {
        try writer.print("\n✅ All optimizations maintain performance within acceptable bounds\n");
    } else {
        try writer.print("\n❌ Performance regressions detected\n");
    }

    try writer.print("\nDemo completed successfully!\n");
}

test "Cache optimization demo runs without errors" {
    const allocator = testing.allocator;

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    try runCacheOptimizationDemo(allocator, buffer.writer());

    // Verify demo produced output
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Cache-Friendly Dispatch Table Optimization Demo") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Demo completed successfully!") != null);
}
