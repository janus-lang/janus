// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const DispatchProfiler = @import("dispatch_profiler.zig").DispatchProfiler;
const PerformanceRegressionTester = @import("performance_regression_tests.zig").PerformanceRegressionTester;

/// Comprehensive demonstration of dispatch performance monitoring and profiling
pub fn runDispatchPerformanceDemo(allocator: Allocator, writer: anytype) !void {
    try writer.print("Dispatch Performance Monitoring & Profiling Demo\n");
    try writer.print("===============================================\n\n");

    // Initialize components
    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var profiler = DispatchProfiler.init(allocator);
    defer profiler.deinit();

    // Register test types
    const int_type = try type_registry.registerType("int", .primitive, &.{});
    const float_type = try type_registry.registerType("float", .primitive, &.{});
    const string_type = try type_registry.registerType("string", .primitive, &.{});

    try writer.print("1. Performance Counter Demonstration\n");
    try writer.print("------------------------------------\n");

    // Show initial counters
    try writer.print("Initial counters: {}\n\n", .{profiler.getCounters()});

    try writer.print("2. Call Site Registration and Tracking\n");
    try writer.print("--------------------------------------\n");

    // Register call sites
    const add_call_site = try profiler.registerCallSite("add", DispatchProfiler.SourceLocation{
        .file = "math.janus",
        .line = 10,
        .column = 5,
    });

    const process_call_site = try profiler.registerCallSite("process", DispatchProfiler.SourceLocation{
        .file = "data.janus",
        .line = 25,
        .column = 12,
    });

    try writer.print("Registered call sites: {} and {}\n\n", .{ add_call_site, process_call_site });

    try writer.print("3. Function Family Registration\n");
    try writer.print("-------------------------------\n");

    // Create mock implementations
    const add_int_impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "add", .module = "math", .id = 1 },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{ int_type, int_type }),
        .return_type_id = int_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(add_int_impl.param_type_ids);

    const add_float_impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "add", .module = "math", .id = 2 },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{ float_type, float_type }),
        .return_type_id = float_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(add_float_impl.param_type_ids);

    const process_impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "process", .module = "data", .id = 3 },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{string_type}),
        .return_type_id = string_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(process_impl.param_type_ids);

    // Register function families
    const add_implementations = [_]*const SignatureAnalyzer.Implementation{ &add_int_impl, &add_float_impl };
    const process_implementations = [_]*const SignatureAnalyzer.Implementation{&process_impl};

    try profiler.registerFunctionFamily("add", &add_implementations);
    try profiler.registerFunctionFamily("process", &process_implementations);

    try writer.print("Registered function families: 'add' (2 impls), 'process' (1 impl)\n\n");

    try writer.print("4. Dispatch Recording Simulation\n");
    try writer.print("---------------------------------\n");

    // Simulate various dispatch scenarios

    // Fast static dispatches
    for (0..50) |_| {
        try profiler.recordDispatch(add_call_site, &[_]TypeId{ int_type, int_type }, &add_int_impl, 100, 1000, true);
    }

    // Slower dynamic dispatches
    for (0..20) |_| {
        try profiler.recordDispatch(add_call_site, &[_]TypeId{ float_type, float_type }, &add_float_impl, 300, 1500, false);
    }

    // Hot path simulation (many calls to process)
    for (0..2000) |_| {
        try profiler.recordDispatch(process_call_site, &[_]TypeId{string_type}, &process_impl, 80, 800, true);
    }

    // Some failed dispatches
    for (0..5) |_| {
        try profiler.recordDispatch(add_call_site, &[_]TypeId{string_type}, null, 500, 0, false);
    }

    // Some ambiguous dispatches
    for (0..3) |_| {
        try profiler.recordAmbiguousDispatch(add_call_site, "add");
    }

    try writer.print("Simulated dispatch scenarios:\n");
    try writer.print("  - 50 fast static int additions\n");
    try writer.print("  - 20 slower dynamic float additions\n");
    try writer.print("  - 2000 hot path string processing calls\n");
    try writer.print("  - 5 failed dispatches\n");
    try writer.print("  - 3 ambiguous dispatches\n\n");

    try writer.print("5. Performance Analysis\n");
    try writer.print("-----------------------\n");

    const counters = profiler.getCounters();
    try writer.print("Updated counters: {}\n\n", .{counters});

    // Show performance metrics
    try writer.print("Performance Metrics:\n");
    try writer.print("  Dispatch Overhead: {d:.2}%\n", .{counters.getDispatchOverheadRatio() * 100.0});
    try writer.print("  Cache Hit Ratio: {d:.1}%\n", .{counters.getCacheHitRatio() * 100.0});
    try writer.print("  Success Rate: {d:.1}%\n", .{@as(f64, @floatFromInt(counters.static_dispatches + counters.dynamic_dispatches)) /
        @as(f64, @floatFromInt(counters.static_dispatches + counters.dynamic_dispatches + counters.failed_dispatches)) * 100.0});
    try writer.print("\n");

    try writer.print("6. Comprehensive Performance Report\n");
    try writer.print("-----------------------------------\n");

    try profiler.generateReport(writer);

    try writer.print("7. Performance Regression Testing\n");
    try writer.print("---------------------------------\n");

    var regression_tester = PerformanceRegressionTester.init(allocator);
    defer regression_tester.deinit();

    // Establish baseline
    try writer.print("Establishing performance baseline...\n");
    try regression_tester.establishBaseline("v1.0.0");

    if (regression_tester.baseline_results) |baseline| {
        try writer.print("Baseline established: {}\n\n", .{baseline});
    }

    // Run regression tests
    try writer.print("Running regression tests...\n");
    const regression_passed = try regression_tester.runRegressionTests("v1.1.0", writer);

    if (regression_passed) {
        try writer.print("\n✅ All regression tests passed!\n\n");
    } else {
        try writer.print("\n❌ Some regression tests failed!\n\n");
    }

    try writer.print("8. Comprehensive Performance Test Suite\n");
    try writer.print("---------------------------------------\n");

    const test_results = try regression_tester.runPerformanceTestSuite(writer);
    defer allocator.free(test_results);

    try writer.print("9. Performance Analysis Report\n");
    try writer.print("------------------------------\n");

    try regression_tester.generatePerformanceReport(test_results, writer);

    try writer.print("10. Performance Optimization Recommendations\n");
    try writer.print("--------------------------------------------\n");

    // Analyze current performance and provide recommendations
    if (counters.getDispatchOverheadRatio() > 0.1) {
        try writer.print("🔧 High dispatch overhead detected ({d:.1}%)\n", .{counters.getDispatchOverheadRatio() * 100.0});
        try writer.print("   Recommendation: Consider static dispatch optimization for hot paths\n");
    }

    if (counters.dynamic_dispatches > counters.static_dispatches) {
        try writer.print("🔧 More dynamic than static dispatches\n");
        try writer.print("   Recommendation: Review type annotations for better static resolution\n");
    }

    if (counters.failed_dispatches > 0) {
        try writer.print("🔧 {} failed dispatches detected\n", .{counters.failed_dispatches});
        try writer.print("   Recommendation: Review function signatures and type compatibility\n");
    }

    if (counters.ambiguous_dispatches > 0) {
        try writer.print("🔧 {} ambiguous dispatches detected\n", .{counters.ambiguous_dispatches});
        try writer.print("   Recommendation: Add more specific implementations or type constraints\n");
    }

    // Check for hot paths
    var hot_path_detected = false;
    var call_site_iter = profiler.call_sites.iterator();
    while (call_site_iter.next()) |entry| {
        if (entry.value_ptr.is_hot_path) {
            if (!hot_path_detected) {
                try writer.print("🔥 Hot paths detected:\n");
                hot_path_detected = true;
            }
            try writer.print("   - {} ({} calls, {d:.1}ns avg)\n", .{ entry.value_ptr.signature_name, entry.value_ptr.call_count, entry.value_ptr.average_dispatch_time });
        }
    }

    if (hot_path_detected) {
        try writer.print("   Recommendation: Consider specialization or caching for hot paths\n");
    }

    if (!hot_path_detected and counters.getDispatchOverheadRatio() <= 0.1 and
        counters.static_dispatches >= counters.dynamic_dispatches and
        counters.failed_dispatches == 0 and counters.ambiguous_dispatches == 0)
    {
        try writer.print("✨ Excellent performance! No optimization recommendations at this time.\n");
    }

    try writer.print("\nDemo completed successfully! 🎉\n");
}

test "Dispatch performance demo runs without errors" {
    const allocator = testing.allocator;

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try runDispatchPerformanceDemo(allocator, buffer.writer());

    // Verify demo produced comprehensive output
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Dispatch Performance Monitoring & Profiling Demo") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Performance Counter Demonstration") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Call Site Registration") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Function Family Registration") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Performance Analysis") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Regression Testing") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Demo completed successfully") != null);
}
