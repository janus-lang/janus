// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Comprehensive tests for Janus dispatch CLI tools

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;

const JanusDispatchCLI = @import("main.zig").JanusDispatchCLI;
const DispatchQueryCLI = @import("dispatch_query.zig").DispatchQueryCLI;
const DispatchTracer = @import("dispatch_tracer.zig").DispatchTracer;
const DispatchTracerCLI = @import("dispatch_tracer.zig").DispatchTracerCLI;
const mock_system = @import("mock_dispatch_system.zig");

// Test the main CLI interface
test "JanusDispatchCLI initialization and cleanup" {
    var cli = JanusDispatchCLI.init(testing.allocator);
    defer cli.deinit();

    // Should initialize without error
    try testing.expect(cli.query_cli == null);
    try testing.expect(cli.tracer_cli == null);
}

test "JanusDispatchCLI help command" {
    var cli = JanusDispatchCLI.init(testing.allocator);
    defer cli.deinit();

    // Test help command (should not error)
    const args = &[_][]const u8{ "janus", "help" };
    try cli.run(args);
}

test "JanusDispatchCLI version command" {
    var cli = JanusDispatchCLI.init(testing.allocator);
    defer cli.deinit();

    // Test version command (should not error)
    const args = &[_][]const u8{ "janus", "version" };
    try cli.run(args);
}

test "JanusDispatchCLI invalid command" {
    var cli = JanusDispatchCLI.init(testing.allocator);
    defer cli.deinit();

    // Test invalid command (should not crash)
    const args = &[_][]const u8{ "janus", "invalid_command" };
    try cli.run(args);
}

// Test the query CLI
test "DispatchQueryCLI initialization" {
    var query_cli = try DispatchQueryCLI.init(testing.allocator);
    defer query_cli.deinit();

    // Should initialize with empty dispatch families
    try testing.expect(query_cli.dispatch_families.count() == 0);
}

test "DispatchQueryCLI sample data loading" {
    var query_cli = try DispatchQueryCLI.init(testing.allocator);
    defer query_cli.deinit();

    // Load sample dispatch families
    const loader = @import("dispatch_query.zig").DispatchQueryCLIExt;
    try loader.loadDispatchFamilies(&query_cli);

    // Should have loaded sample families
    try testing.expect(query_cli.dispatch_families.count() > 0);

    // Should have "add" family
    const add_family = query_cli.dispatch_families.get("add");
    try testing.expect(add_family != null);
    try testing.expect(add_family.?.implementations.items.len >= 2);
}

test "DispatchQueryCLI query dispatch-ir command" {
    var query_cli = try DispatchQueryCLI.init(testing.allocator);
    defer query_cli.deinit();

    // Load sample data
    const loader = @import("dispatch_query.zig").DispatchQueryCLIExt;
    try loader.loadDispatchFamilies(&query_cli);

    // Test query dispatch-ir command
    const args = &[_][]const u8{ "janus", "query", "dispatch-ir", "add" };
    try query_cli.run(args);
}

test "DispatchQueryCLI query dispatch command" {
    var query_cli = try DispatchQueryCLI.init(testing.allocator);
    defer query_cli.deinit();

    // Load sample data
    const loader = @import("dispatch_query.zig").DispatchQueryCLIExt;
    try loader.loadDispatchFamilies(&query_cli);

    // Test query dispatch command
    const args = &[_][]const u8{ "janus", "query", "dispatch", "add", "--show-candidates" };
    try query_cli.run(args);
}

test "DispatchQueryCLI nonexistent symbol" {
    var query_cli = try DispatchQueryCLI.init(testing.allocator);
    defer query_cli.deinit();

    // Load sample data
    const loader = @import("dispatch_query.zig").DispatchQueryCLIExt;
    try loader.loadDispatchFamilies(&query_cli);

    // Test query for nonexistent symbol (should handle gracefully)
    const args = &[_][]const u8{ "janus", "query", "dispatch-ir", "nonexistent" };
    try query_cli.run(args);
}

// Test the tracer
test "DispatchTracer initialization" {
    const config = DispatchTracer.TracingConfig{};
    var tracer = try DispatchTracer.init(testing.allocator, config);
    defer tracer.deinit();

    // Should initialize with empty state
    try testing.expect(tracer.trace_buffer.items.len == 0);
    try testing.expect(tracer.active_traces.count() == 0);
    try testing.expect(tracer.performance_counters.total_dispatches == 0);
}

test "DispatchTracer basic tracing workflow" {
    const config = DispatchTracer.TracingConfig{
        .enable_detailed_tracing = true,
    };
    var tracer = try DispatchTracer.init(testing.allocator, config);
    defer tracer.deinit();

    const call_id: u64 = 1;
    const function_name = "test_function";
    const arg_types = &[_][]const u8{ "i32", "f64" };

    // Start trace
    try tracer.startTrace(call_id, function_name, arg_types);
    try testing.expect(tracer.active_traces.count() == 1);

    // Add resolution steps
    try tracer.addResolutionStep(call_id, "step1", "First step");
    try tracer.addResolutionStep(call_id, "step2", "Second step");

    const active_trace = tracer.active_traces.get(call_id).?;
    try testing.expect(active_trace.resolution_steps.items.len == 2);

    // Complete trace
    try tracer.completeTrace(
        call_id,
        .switch_table_lookup,
        "test_implementation",
        false,
    );

    // Should have moved to trace buffer
    try testing.expect(tracer.active_traces.count() == 0);
    try testing.expect(tracer.trace_buffer.items.len == 1);
    try testing.expect(tracer.performance_counters.total_dispatches == 1);
}

test "DispatchTracer performance counters" {
    const config = DispatchTracer.TracingConfig{};
    var tracer = try DispatchTracer.init(testing.allocator, config);
    defer tracer.deinit();

    // Simulate multiple dispatches
    for (0..5) |i| {
        const call_id = @as(u64, @intCast(i));
        try tracer.startTrace(call_id, "test_func", &[_][]const u8{"i32"});

        const strategy: DispatchTracer.TraceEntry.ResolutionStrategy = if (i % 2 == 0)
            .static_direct
        else
            .switch_table_lookup;

        try tracer.completeTrace(call_id, strategy, "impl", i % 3 == 0);
    }

    // Check counters
    try testing.expect(tracer.performance_counters.total_dispatches == 5);
    try testing.expect(tracer.performance_counters.static_dispatches == 3); // 0, 2, 4
    try testing.expect(tracer.performance_counters.dynamic_dispatches == 2); // 1, 3
    try testing.expect(tracer.performance_counters.cache_hits == 2); // 0, 3
    try testing.expect(tracer.performance_counters.cache_misses == 3); // 1, 2, 4
}

test "DispatchTracer hot path detection" {
    const config = DispatchTracer.TracingConfig{
        .hot_path_threshold = 2,
    };
    var tracer = try DispatchTracer.init(testing.allocator, config);
    defer tracer.deinit();

    // Call same function multiple times
    for (0..3) |i| {
        const call_id = @as(u64, @intCast(i));
        try tracer.startTrace(call_id, "hot_function", &[_][]const u8{"i32"});
        try tracer.completeTrace(call_id, .inline_cache_hit, "impl", true);
    }

    // Should detect hot path
    try testing.expect(tracer.performance_counters.hot_paths.count() == 1);

    const hot_path_stats = tracer.performance_counters.hot_paths.get("hot_function").?;
    try testing.expect(hot_path_stats.call_count == 3);
    try testing.expect(hot_path_stats.cache_hit_rate == 1.0); // 100% hit rate
}

test "DispatchTracer trace buffer trimming" {
    const config = DispatchTracer.TracingConfig{
        .max_trace_entries = 5,
    };
    var tracer = try DispatchTracer.init(testing.allocator, config);
    defer tracer.deinit();

    // Add more traces than the limit
    for (0..8) |i| {
        const call_id = @as(u64, @intCast(i));
        try tracer.startTrace(call_id, "test_func", &[_][]const u8{"i32"});
        try tracer.completeTrace(call_id, .switch_table_lookup, "impl", false);
    }

    // Should have trimmed to half the max size
    try testing.expect(tracer.trace_buffer.items.len <= config.max_trace_entries / 2 + 1);
}

test "DispatchTracer report generation" {
    const config = DispatchTracer.TracingConfig{};
    var tracer = try DispatchTracer.init(testing.allocator, config);
    defer tracer.deinit();

    // Add some sample traces
    for (0..3) |i| {
        const call_id = @as(u64, @intCast(i));
        try tracer.startTrace(call_id, "test_func", &[_][]const u8{"i32"});
        try tracer.completeTrace(call_id, .switch_table_lookup, "impl", i % 2 == 0);
    }

    // Test different report formats (should not crash)
    try tracer.generateReport(.console);
    try tracer.generateReport(.json);
    try tracer.generateReport(.csv);
    try tracer.generateReport(.flamegraph);
}

// Test the tracer CLI
test "DispatchTracerCLI initialization" {
    const config = DispatchTracer.TracingConfig{};
    var tracer_cli = try DispatchTracerCLI.init(testing.allocator, config);
    defer tracer_cli.deinit();

    // Should initialize successfully
    try testing.expect(tracer_cli.tracer.trace_buffer.items.len == 0);
}

// Integration tests
test "CLI integration - query workflow" {
    var cli = JanusDispatchCLI.init(testing.allocator);
    defer cli.deinit();

    // Test complete query workflow
    const query_args = &[_][]const u8{ "janus", "query", "dispatch-ir", "add", "--show-performance" };
    try cli.run(query_args);

    // Should have created query CLI
    try testing.expect(cli.query_cli != null);
}

test "CLI integration - trace workflow" {
    var cli = JanusDispatchCLI.init(testing.allocator);
    defer cli.deinit();

    // Test single call tracing
    const trace_args = &[_][]const u8{ "janus", "trace", "dispatch", "add(5, 10)", "--verbose" };
    try cli.run(trace_args);
}

// Performance tests
test "DispatchTracer performance - large trace buffer" {
    const config = DispatchTracer.TracingConfig{
        .max_trace_entries = 1000,
    };
    var tracer = try DispatchTracer.init(testing.allocator, config);
    defer tracer.deinit();

    const start_time = compat_time.nanoTimestamp();

    // Add many traces
    for (0..500) |i| {
        const call_id = @as(u64, @intCast(i));
        try tracer.startTrace(call_id, "perf_test", &[_][]const u8{"i32"});
        try tracer.completeTrace(call_id, .switch_table_lookup, "impl", i % 4 == 0);
    }

    const end_time = compat_time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000;

    // Should complete in reasonable time (less than 100ms)
    try testing.expect(duration_ms < 100.0);

    // Should have correct number of traces
    try testing.expect(tracer.performance_counters.total_dispatches == 500);
}

test "DispatchQueryCLI performance - large dispatch family" {
    var query_cli = try DispatchQueryCLI.init(testing.allocator);
    defer query_cli.deinit();

    // Create a large dispatch family for testing
    const large_family = try query_cli.allocator.create(mock_system.DispatchFamily);
    large_family.* = try mock_system.DispatchFamily.init(query_cli.allocator, "large_function");

    // Add many implementations
    for (0..100) |i| {
        const impl_name = try std.fmt.allocPrint(query_cli.allocator, "impl_{d}", .{i});
        defer query_cli.allocator.free(impl_name);

        try large_family.addImplementation(.{
            .name = try query_cli.allocator.dupe(u8, impl_name),
            .parameter_types = &[_][]const u8{"i32"},
            .return_type = "i32",
            .specificity_rank = @as(u32, @intCast(i)),
            .is_reachable = true,
            .source_file = "test.jan",
            .source_line = @as(u32, @intCast(i + 1)),
            .source_column = 1,
            .unreachable_reason = "",
        });
    }

    try query_cli.dispatch_families.put("large_function", large_family);

    const start_time = compat_time.nanoTimestamp();

    // Query the large family
    const args = &[_][]const u8{ "janus", "query", "dispatch", "large_function", "--show-candidates" };
    try query_cli.run(args);

    const end_time = compat_time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000;

    // Should complete in reasonable time (less than 50ms)
    try testing.expect(duration_ms < 50.0);
}

// Error handling tests
test "DispatchTracer error handling - invalid call ID" {
    const config = DispatchTracer.TracingConfig{};
    var tracer = try DispatchTracer.init(testing.allocator, config);
    defer tracer.deinit();

    // Try to add step to non-existent trace (should not crash)
    try tracer.addResolutionStep(999, "invalid_step", "Should be ignored");

    // Try to complete non-existent trace (should not crash)
    try tracer.completeTrace(999, .switch_table_lookup, "impl", false);

    // Should have no traces
    try testing.expect(tracer.trace_buffer.items.len == 0);
}

test "DispatchQueryCLI error handling - malformed arguments" {
    var query_cli = try DispatchQueryCLI.init(testing.allocator);
    defer query_cli.deinit();

    // Test various malformed argument combinations (should not crash)
    const test_cases = &[_][]const []const u8{
        &[_][]const u8{"janus"}, // No command
        &[_][]const u8{ "janus", "query" }, // No subcommand
        &[_][]const u8{ "janus", "query", "dispatch-ir" }, // No symbol
        &[_][]const u8{ "janus", "query", "invalid" }, // Invalid subcommand
        &[_][]const u8{ "janus", "trace" }, // No subcommand
        &[_][]const u8{ "janus", "trace", "invalid" }, // Invalid subcommand
    };

    for (test_cases) |args| {
        try query_cli.run(args);
    }
}

// Memory leak tests
test "DispatchTracer memory management" {
    const config = DispatchTracer.TracingConfig{};
    var tracer = try DispatchTracer.init(testing.allocator, config);
    defer tracer.deinit();

    // Add and complete many traces to test memory cleanup
    for (0..10) |i| {
        const call_id = @as(u64, @intCast(i));
        const function_name = try std.fmt.allocPrint(testing.allocator, "func_{d}", .{i});
        defer testing.allocator.free(function_name);

        try tracer.startTrace(call_id, function_name, &[_][]const u8{"i32"});
        try tracer.addResolutionStep(call_id, "step1", "Test step");
        try tracer.completeTrace(call_id, .switch_table_lookup, "impl", false);
    }

    // All memory should be properly managed by deinit()
}

test "DispatchQueryCLI memory management" {
    var query_cli = try DispatchQueryCLI.init(testing.allocator);
    defer query_cli.deinit();

    // Load sample data and perform queries
    const loader = @import("dispatch_query.zig").DispatchQueryCLIExt;
    try loader.loadDispatchFamilies(&query_cli);

    // Perform multiple queries
    for (0..5) |_| {
        const args = &[_][]const u8{ "janus", "query", "dispatch", "add" };
        try query_cli.run(args);
    }

    // All memory should be properly managed by deinit()
}
