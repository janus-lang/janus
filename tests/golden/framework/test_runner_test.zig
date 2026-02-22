// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const TestRunner = @import("test_runner.zig").TestRunner;

// Integration test for TestRunner functionality
test "TestRunner integration test" {
    const allocator = std.testing.allocator;

    // Create test configuration
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

    const runner = TestRunner.init(allocator, config);

    // Test that runner initializes correctly
    try std.testing.expect(!runner.config.parallel_execution);
    try std.testing.expect(runner.config.timeout_seconds == 30);
    try std.testing.expectEqualStrings(runner.config.test_directory, "tests/golden/ir-generation");
}

// Test metadata parsing with various formats
test "TestRunner metadata parsing comprehensive" {
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

    const complex_source =
        \\// @expected-strategy: switch_table
        \\// @expected-performance: dispatch_overhead_ns < 25
        \\// @expected-performance: memory_usage_bytes <= 512
        \\// @expected-performance: code_size_bytes < 1024
        \\// @platforms: all
        \\// @optimization-level: release_fast
        \\// @skip-platforms: windows_x86_64
        \\// @timeout: 60
        \\// @description: Complex dispatch test with multiple performance constraints
        \\
        \\func process(x: i32) -> i32 { x * 2 }
        \\func process(x: f64) -> f64 { x * 2.0 }
        \\func process(x: string) -> string { x ++ x }
        \\
        \\func main() {
        \\    let result1 = process(42)
        \\    let result2 = process(3.14)
        \\    let result3 = process("test")
        \\}
    ;

    var metadata = try runner.parseTestMetadata(complex_source);
    defer metadata.deinit(allocator);

    // Verify all parsed metadata
    try std.testing.expect(metadata.expected_strategy != null);
    try std.testing.expectEqualStrings(metadata.expected_strategy.?, "switch_table");

    // Check multiple performance expectations
    try std.testing.expect(metadata.expected_performance.len == 3);

    // First expectation: dispatch_overhead_ns < 25
    try std.testing.expectEqualStrings(metadata.expected_performance[0].metric_name, "dispatch_overhead_ns");
    try std.testing.expect(metadata.expected_performance[0].operator == .less_than);
    try std.testing.expect(metadata.expected_performance[0].threshold_value == 25.0);

    // Second expectation: memory_usage_bytes <= 512
    try std.testing.expectEqualStrings(metadata.expected_performance[1].metric_name, "memory_usage_bytes");
    try std.testing.expect(metadata.expected_performance[1].operator == .less_equal);
    try std.testing.expect(metadata.expected_performance[1].threshold_value == 512.0);

    // Third expectation: code_size_bytes < 1024
    try std.testing.expectEqualStrings(metadata.expected_performance[2].metric_name, "code_size_bytes");
    try std.testing.expect(metadata.expected_performance[2].operator == .less_than);
    try std.testing.expect(metadata.expected_performance[2].threshold_value == 1024.0);

    // Check platform settings
    try std.testing.expect(metadata.platforms == .all);
    try std.testing.expect(metadata.skip_platforms.len == 1);
    try std.testing.expect(metadata.skip_platforms[0] == .windows_x86_64);

    // Check optimization level
    try std.testing.expect(metadata.optimization_levels.len == 1);
    try std.testing.expect(metadata.optimization_levels[0] == .release_fast);

    // Check timeout override
    try std.testing.expect(metadata.timeout_override != null);
    try std.testing.expect(metadata.timeout_override.? == 60);

    // Check description
    try std.testing.expect(metadata.description != null);
    try std.testing.expectEqualStrings(metadata.description.?, "Complex dispatch test with multiple performance constraints");
}

// Test error handling in metadata parsing
test "TestRunner metadata parsing error handling" {
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

    // Test invalid performance expectation
    try std.testing.expectError(error.InvalidPerformanceExpectation, runner.parsePerformanceExpectation("invalid_format"));

    // Test invalid threshold value
    try std.testing.expectError(error.InvalidThresholdValue, runner.parsePerformanceExpectation("metric_name < invalid_number"));

    // Test invalid optimization level
    try std.testing.expectError(error.UnknownOptimizationLevel, runner.parseOptimizationLevel("invalid_level"));

    // Test invalid platform
    try std.testing.expectError(error.UnknownPlatform, runner.parsePlatform("invalid_platform"));
}

// Test TestResult creation and cleanup
test "TestResult lifecycle" {
    const allocator = std.testing.allocator;

    // Create a test result with diagnostic messages
    var diagnostic_messages: std.ArrayList(TestRunner.DiagnosticMessage) = .empty;
    defer diagnostic_messages.deinit();

    try diagnostic_messages.append(.{
        .level = .info,
        .phase = .loading,
        .message = try allocator.dupe(u8, "Test message"),
        .context = try allocator.dupe(u8, "Test context"),
        .timestamp = compat_time.timestamp(),
    });

    var result = TestRunner.TestResult{
        .test_name = try allocator.dupe(u8, "test_case"),
        .status = .passed,
        .execution_time_ms = 100,
        .platform = .linux_x86_64,
        .optimization_level = .release_safe,
        .diagnostic_messages = try diagnostic_messages.toOwnedSlice(),
    };

    // Verify result properties
    try std.testing.expectEqualStrings(result.test_name, "test_case");
    try std.testing.expect(result.status == .passed);
    try std.testing.expect(result.execution_time_ms == 100);
    try std.testing.expect(result.platform == .linux_x86_64);
    try std.testing.expect(result.optimization_level == .release_safe);
    try std.testing.expect(result.diagnostic_messages.len == 1);

    // Clean up
    result.deinit(allocator);
}
