// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TestMetadataSystem = @import("test_metadata.zig").TestMetadataSystem;

// Test the comprehensive metadata system
test "TestMetadataSystem initialization" {
    const allocator = std.testing.allocator;

    const metadata_system = TestMetadataSystem.init(allocator);

    // Test basic initialization
    try std.testing.expect(metadata_system.allocator.ptr == allocator.ptr);
}

// Test basic metadata parsing
test "TestMetadataSystem basic metadata parsing" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    const source_content =
        \\// @description: Basic dispatch test with comprehensive metadata
        \\// @author: Test Developer
        \\// @expected-strategy: perfect_hash
        \\// @performance: dispatch_overhead_ns < 25
        \\// @performance: memory_usage_bytes <= 512
        \\// @platforms: all
        \\// @optimization: release_safe
        \\// @timeout: 60
        \\
        \\func add(x: i32, y: i32) -> i32 { x + y }
        \\func add(x: f64, y: f64) -> f64 { x + y }
        \\
        \\func main() {
        \\    let result1 = add(5, 10)
        \\    let result2 = add(3.14, 2.86)
        \\}
    ;

    var metadata = try metadata_system.parseMetadata(source_content, "basic_dispatch_test");
    defer metadata.deinit(allocator);

    // Verify basic metadata
    try std.testing.expectEqualStrings(metadata.test_name, "basic_dispatch_test");
    try std.testing.expect(metadata.description != null);
    try std.testing.expectEqualStrings(metadata.description.?, "Basic dispatch test with comprehensive metadata");
    try std.testing.expect(metadata.author != null);
    try std.testing.expectEqualStrings(metadata.author.?, "Test Developer");

    // Verify dispatch strategy
    try std.testing.expect(metadata.expected_strategy != null);
    try std.testing.expect(metadata.expected_strategy.?.strategy_type == .perfect_hash);

    // Verify performance expectations
    try std.testing.expect(metadata.performance_expectations.len == 2);

    // First expectation: dispatch_overhead_ns < 25
    try std.testing.expectEqualStrings(metadata.performance_expectations[0].metric_name, "dispatch_overhead_ns");
    try std.testing.expect(metadata.performance_expectations[0].threshold.operator == .less_than);
    try std.testing.expect(metadata.performance_expectations[0].threshold.value == 25.0);

    // Second expectation: memory_usage_bytes <= 512
    try std.testing.expectEqualStrings(metadata.performance_expectations[1].metric_name, "memory_usage_bytes");
    try std.testing.expect(metadata.performance_expectations[1].threshold.operator == .less_equal);
    try std.testing.expect(metadata.performance_expectations[1].threshold.value == 512.0);

    // Verify platform configuration
    try std.testing.expect(metadata.platform_config.target_platforms.len > 0);

    // Verify optimization configuration
    try std.testing.expect(metadata.optimization_config.optimization_levels.len == 1);
    try std.testing.expect(metadata.optimization_config.optimization_levels[0] == .release_safe);

    // Verify execution configuration
    try std.testing.expect(metadata.execution_config.timeout_seconds == 60);
}

// Test advanced metadata features
test "TestMetadataSystem advanced metadata features" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    const advanced_source =
        \\// @description: Advanced dispatch test with complex metadata
        \\// @author: Senior Test Engineer
        \\// @expected-strategy: hybrid_dispatch
        \\// @performance: dispatch_overhead_ns < 20
        \\// @performance: cache_miss_rate <= 0.05
        \\// @performance: memory_footprint < 1024
        \\// @platforms: all
        \\// @optimization: release_fast
        \\// @timeout: 120
        \\
        \\func complex_dispatch(a: ComplexType, b: AnotherType) -> ResultType {
        \\    // Complex dispatch logic here
        \\}
    ;

    var metadata = try metadata_system.parseMetadata(advanced_source, "advanced_dispatch_test");
    defer metadata.deinit(allocator);

    // Verify advanced metadata
    try std.testing.expectEqualStrings(metadata.test_name, "advanced_dispatch_test");
    try std.testing.expect(metadata.description != null);
    try std.testing.expectEqualStrings(metadata.description.?, "Advanced dispatch test with complex metadata");

    // Verify strategy
    try std.testing.expect(metadata.expected_strategy != null);
    try std.testing.expect(metadata.expected_strategy.?.strategy_type == .hybrid_dispatch);

    // Verify multiple performance expectations
    try std.testing.expect(metadata.performance_expectations.len == 3);

    // Verify strategy characteristics
    const characteristics = metadata.expected_strategy.?.expected_characteristics;
    try std.testing.expect(characteristics.expected_complexity == .constant);
    try std.testing.expect(characteristics.cache_behavior.locality == .serviceod);
    try std.testing.expect(characteristics.cache_behavior.prefetch_friendly == true);

    // Verify measurement configuration
    const measurement_config = metadata.performance_expectations[0].measurement_config;
    try std.testing.expect(measurement_config.warmup_iterations == 100);
    try std.testing.expect(measurement_config.measurement_iterations == 1000);
    try std.testing.expect(measurement_config.environment_isolation == true);

    // Verify statistical requirements
    const stats_req = metadata.performance_expectations[0].statistical_requirements;
    try std.testing.expect(stats_req.confidence_level == 0.95);
    try std.testing.expect(stats_req.coreimum_sample_size == 30);
    try std.testing.expect(stats_req.outlier_detection == true);
}

// Test metadata validation
test "TestMetadataSystem metadata validation" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    // Create valid metadata
    var valid_metadata = try metadata_system.parseMetadata("// @description: Valid test\n// @expected-strategy: perfect_hash\n", "valid_test");
    defer valid_metadata.deinit(allocator);

    var validation_result = try metadata_system.validateMetadata(&valid_metadata);
    defer validation_result.deinit();

    try std.testing.expect(validation_result.is_valid == true);
    try std.testing.expect(validation_result.errors.items.len == 0);

    // Create invalid metadata (empty test name)
    var invalid_metadata = TestMetadataSystem.TestMetadata{
        .test_name = "",
        .description = null,
        .author = null,
        .created_date = null,
        .last_modified = null,
        .expected_strategy = null,
        .fallback_strategies = &.{},
        .strategy_constraints = &.{},
        .performance_expectations = &.{},
        .performance_baselines = &.{},
        .regression_thresholds = &.{},
        .platform_config = TestMetadataSystem.PlatformConfiguration{
            .target_platforms = &.{},
            .excluded_platforms = &.{},
            .platform_specific_config = &.{},
            .cross_platform_validation = TestMetadataSystem.PlatformConfiguration.CrossPlatformValidation{
                .semantic_equivalence_required = true,
                .performance_consistency_required = true,
                .acceptable_variance_percentage = 5.0,
                .platform_comparison_matrix = &.{},
            },
        },
        .optimization_config = TestMetadataSystem.OptimizationConfiguration{
            .optimization_levels = &.{},
            .optimization_constraints = &.{},
            .optimization_validation = TestMetadataSystem.OptimizationConfiguration.OptimizationValidation{
                .validate_debug_info = true,
                .validate_performance_improvement = true,
                .validate_code_size = true,
                .validate_compilation_time = true,
            },
        },
        .environment_requirements = &.{},
        .execution_config = TestMetadataSystem.ExecutionConfiguration{
            .timeout_seconds = 30,
            .retry_count = 0,
            .parallel_execution = true,
            .resource_limits = TestMetadataSystem.ExecutionConfiguration.ResourceLimits{
                .max_memory_mb = 1024,
                .max_cpu_time_seconds = 60,
                .max_wall_time_seconds = 120,
                .max_file_descriptors = 1024,
                .max_processes = 10,
            },
            .isolation_requirements = TestMetadataSystem.ExecutionConfiguration.IsolationRequirements{
                .process_isolation = true,
                .filesystem_isolation = false,
                .network_isolation = true,
                .environment_isolation = false,
            },
        },
        .validation_config = TestMetadataSystem.ValidationConfiguration{
            .validation_phases = &.{},
            .validation_strictness = .strict,
            .custom_validators = &.{},
        },
        .dependencies = &.{},
        .conflicts = &.{},
        .prerequisites = &.{},
        .metadata_version = 1,
        .compatibility_version = 1,
        .checksum = std.mem.zeroes([32]u8),
    };

    var invalid_validation_result = try metadata_system.validateMetadata(&invalid_metadata);
    defer invalid_validation_result.deinit();

    try std.testing.expect(invalid_validation_result.is_valid == false);
    try std.testing.expect(invalid_validation_result.errors.items.len > 0);
    try std.testing.expect(invalid_validation_result.errors.items[0].error_type == .missing_required_field);
}

// Test dispatch strategy parsing
test "TestMetadataSystem dispatch strategy parsing" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    // Test various dispatch strategies
    const strategies = [_][]const u8{
        "perfect_hash",
        "switch_table",
        "binary_search",
        "linear_search",
        "inline_cache",
        "static_dispatch",
        "dynamic_dispatch",
        "hybrid_dispatch",
    };

    for (strategies) |strategy_name| {
        const strategy = try metadata_system.parseDispatchStrategy(strategy_name);
        try std.testing.expect(strategy != null);

        const expected_type = std.meta.stringToEnum(TestMetadataSystem.DispatchStrategy.StrategyType, strategy_name).?;
        try std.testing.expect(strategy.?.strategy_type == expected_type);

        // Verify default characteristics
        try std.testing.expect(strategy.?.expected_characteristics.expected_complexity == .constant);
        try std.testing.expect(strategy.?.expected_characteristics.memory_usage.base_overhead == 64);
        try std.testing.expect(strategy.?.expected_characteristics.cache_behavior.locality == .serviceod);
    }

    // Test invalid strategy
    const invalid_strategy = try metadata_system.parseDispatchStrategy("invalid_strategy");
    try std.testing.expect(invalid_strategy == null);
}

// Test performance expectation parsing
test "TestMetadataSystem performance expectation parsing" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    // Test various operators
    const test_cases = [_]struct {
        input: []const u8,
        expected_operator: TestMetadataSystem.PerformanceExpectation.ThresholdSpecification.ComparisonOperator,
        expected_value: f64,
        expected_metric: []const u8,
    }{
        .{ .input = "dispatch_overhead_ns < 30", .expected_operator = .less_than, .expected_value = 30.0, .expected_metric = "dispatch_overhead_ns" },
        .{ .input = "memory_usage_bytes <= 256", .expected_operator = .less_equal, .expected_value = 256.0, .expected_metric = "memory_usage_bytes" },
        .{ .input = "throughput_ops_per_sec >= 1000", .expected_operator = .greater_equal, .expected_value = 1000.0, .expected_metric = "throughput_ops_per_sec" },
        .{ .input = "latency_ms ~= 5.5", .expected_operator = .approximately_equal, .expected_value = 5.5, .expected_metric = "latency_ms" },
    };

    for (test_cases) |test_case| {
        var expectation = try metadata_system.parsePerformanceExpectation(test_case.input);
        defer expectation.deinit(allocator);

        try std.testing.expectEqualStrings(expectation.metric_name, test_case.expected_metric);
        try std.testing.expect(expectation.threshold.operator == test_case.expected_operator);
        try std.testing.expect(expectation.threshold.value == test_case.expected_value);
        try std.testing.expect(expectation.expectation_type == .absolute_bound);

        // Verify measurement configuration defaults
        try std.testing.expect(expectation.measurement_config.warmup_iterations == 100);
        try std.testing.expect(expectation.measurement_config.measurement_iterations == 1000);
        try std.testing.expect(expectation.measurement_config.environment_isolation == true);

        // Verify statistical requirements defaults
        try std.testing.expect(expectation.statistical_requirements.confidence_level == 0.95);
        try std.testing.expect(expectation.statistical_requirements.coreimum_sample_size == 30);
        try std.testing.expect(expectation.statistical_requirements.outlier_detection == true);
    }
}

// Test error handling in parsing
test "TestMetadataSystem error handling" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    // Test invalid performance expectation format
    try std.testing.expectError(error.InvalidPerformanceExpectation, metadata_system.parsePerformanceExpectation("invalid_format_no_operator"));

    // Test invalid threshold value
    try std.testing.expectError(error.InvalidThresholdValue, metadata_system.parsePerformanceExpectation("metric_name < invalid_number"));
}

// Test platform configuration parsing
test "TestMetadataSystem platform configuration" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    var platform_config = TestMetadataSystem.PlatformConfiguration{
        .target_platforms = &.{},
        .excluded_platforms = &.{},
        .platform_specific_config = &.{},
        .cross_platform_validation = TestMetadataSystem.PlatformConfiguration.CrossPlatformValidation{
            .semantic_equivalence_required = true,
            .performance_consistency_required = true,
            .acceptable_variance_percentage = 5.0,
            .platform_comparison_matrix = &.{},
        },
    };

    // Test "all" platforms
    try metadata_system.parsePlatformConfiguration("all", &platform_config);
    defer platform_config.deinit(allocator);

    try std.testing.expect(platform_config.target_platforms.len == 5); // All supported platforms
    try std.testing.expect(platform_config.target_platforms[0] == .linux_x86_64);
    try std.testing.expect(platform_config.target_platforms[1] == .linux_aarch64);
    try std.testing.expect(platform_config.target_platforms[2] == .macos_x86_64);
    try std.testing.expect(platform_config.target_platforms[3] == .macos_aarch64);
    try std.testing.expect(platform_config.target_platforms[4] == .windows_x86_64);
}

// Test optimization configuration parsing
test "TestMetadataSystem optimization configuration" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    var opt_config = TestMetadataSystem.OptimizationConfiguration{
        .optimization_levels = &.{},
        .optimization_constraints = &.{},
        .optimization_validation = TestMetadataSystem.OptimizationConfiguration.OptimizationValidation{
            .validate_debug_info = true,
            .validate_performance_improvement = true,
            .validate_code_size = true,
            .validate_compilation_time = true,
        },
    };

    const optimization_levels = [_][]const u8{
        "debug",
        "release_safe",
        "release_fast",
        "release_small",
    };

    for (optimization_levels) |level_name| {
        try metadata_system.parseOptimizationConfiguration(level_name, &opt_config);
        defer opt_config.deinit(allocator);

        try std.testing.expect(opt_config.optimization_levels.len == 1);

        const expected_level = std.meta.stringToEnum(TestMetadataSystem.OptimizationConfiguration.OptimizationLevel, level_name).?;
        try std.testing.expect(opt_config.optimization_levels[0] == expected_level);

        // Reset for next iteration
        allocator.free(opt_config.optimization_levels);
        opt_config.optimization_levels = &.{};
    }
}

// Test metadata checksum calculation
test "TestMetadataSystem checksum calculation" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    var metadata1 = try metadata_system.parseMetadata("// @description: Test 1\n// @expected-strategy: perfect_hash\n", "test1");
    defer metadata1.deinit(allocator);

    var metadata2 = try metadata_system.parseMetadata("// @description: Test 2\n// @expected-strategy: perfect_hash\n", "test2");
    defer metadata2.deinit(allocator);

    // Different metadata should have different checksums
    try std.testing.expect(!std.mem.eql(u8, &metadata1.checksum, &metadata2.checksum));

    // Same metadata should have same checksum
    var metadata1_copy = try metadata_system.parseMetadata("// @description: Test 1\n// @expected-strategy: perfect_hash\n", "test1");
    defer metadata1_copy.deinit(allocator);

    try std.testing.expect(std.mem.eql(u8, &metadata1.checksum, &metadata1_copy.checksum));
}
