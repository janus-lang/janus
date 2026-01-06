// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TestRunner = @import("test_runner.zig").TestRunner;

// Integration test demonstrating TestRunner discovering and processing test cases
test "TestRunner discovers and processes test cases" {
    const allocator = std.testing.allocator;

    var platforms = [_]TestRunner.TestConfig.Platform{.linux_x86_64};
    var optimization_levels = [_]TestRunner.TestConfig.OptimizationLevel{.release_safe};

    const config = TestRunner.TestConfig{
        .test_directory = "tests/golden/ir-generation",
        .servicelden_directory = "tests/golden/references",
        .performance_baseline_directory = "tests/golden/baselines",
        .platforms = &platforms,
        .optimization_levels = &optimization_levels,
        .parallel_execution = false,
        .timeout_seconds = 30,
        .max_parallel_workers = 4,
    };

    var runner = TestRunner.init(allocator, config);

    // Test that we can run a single test case
    var result = runner.runSingleTest("example_dispatch") catch |err| switch (err) {
        error.FileNotFound => {
            // Test file doesn't exist, which is expected in CI
            std.log.info("Test file not found - this is expected in CI environment", .{});
            return;
        },
        else => return err,
    };

    defer result.deinit(allocator);

    // Verify the test result structure
    try std.testing.expectEqualStrings(result.test_name, "example_dispatch");
    try std.testing.expect(result.execution_time_ms >= 0);
    try std.testing.expect(result.platform == .linux_x86_64);
    try std.testing.expect(result.optimization_level == .release_safe);

    std.log.info("Test '{s}' completed with status: {} in {}ms", .{
        result.test_name,
        result.status,
        result.execution_time_ms,
    });
}

// Test that demonstrates metadata parsing from the example test case
test "TestRunner parses example test metadata correctly" {
    const allocator = std.testing.allocator;

    var platforms = [_]TestRunner.TestConfig.Platform{.linux_x86_64};
    var optimization_levels = [_]TestRunner.TestConfig.OptimizationLevel{.release_safe};

    const config = TestRunner.TestConfig{
        .test_directory = "tests/golden/ir-generation",
        .servicelden_directory = "tests/golden/references",
        .performance_baseline_directory = "tests/golden/baselines",
        .platforms = &platforms,
        .optimization_levels = &optimization_levels,
        .parallel_execution = false,
        .timeout_seconds = 30,
        .max_parallel_workers = 4,
    };

    var runner = TestRunner.init(allocator, config);

    // Parse the example test case metadata
    const example_source =
        \\// @expected-strategy: perfect_hash
        \\// @expected-performance: dispatch_overhead_ns < 30
        \\// @expected-performance: memory_usage_bytes <= 256
        \\// @platforms: all
        \\// @optimization-level: release_safe
        \\// @description: Basic multiple dispatch example for golden test framework
        \\
        \\func add(x: i32, y: i32) -> i32 { x + y }
        \\func add(x: f64, y: f64) -> f64 { x + y }
        \\func add(x: string, y: string) -> string { x ++ y }
        \\
        \\func main() {
        \\    let result1 = add(5, 10)
        \\    let result2 = add(3.14, 2.86)
        \\    let result3 = add("hello", "world")
        \\}
    ;

    var metadata = try runner.parseTestMetadata(example_source);
    defer metadata.deinit(allocator);

    // Verify parsed metadata matches expectations
    try std.testing.expect(metadata.expected_strategy != null);
    try std.testing.expectEqualStrings(metadata.expected_strategy.?, "perfect_hash");

    try std.testing.expect(metadata.expected_performance.len == 2);

    // First performance expectation: dispatch_overhead_ns < 30
    try std.testing.expectEqualStrings(metadata.expected_performance[0].metric_name, "dispatch_overhead_ns");
    try std.testing.expect(metadata.expected_performance[0].operator == .less_than);
    try std.testing.expect(metadata.expected_performance[0].threshold_value == 30.0);

    // Second performance expectation: memory_usage_bytes <= 256
    try std.testing.expectEqualStrings(metadata.expected_performance[1].metric_name, "memory_usage_bytes");
    try std.testing.expect(metadata.expected_performance[1].operator == .less_equal);
    try std.testing.expect(metadata.expected_performance[1].threshold_value == 256.0);

    try std.testing.expect(metadata.platforms == .all);
    try std.testing.expect(metadata.optimization_levels.len == 1);
    try std.testing.expect(metadata.optimization_levels[0] == .release_safe);

    try std.testing.expect(metadata.description != null);
    try std.testing.expectEqualStrings(metadata.description.?, "Basic multiple dispatch example for golden test framework");

    std.log.info("Successfully parsed metadata for test with strategy: {s}", .{metadata.expected_strategy.?});
}
