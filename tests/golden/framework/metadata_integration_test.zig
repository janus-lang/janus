// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TestRunner = @import("test_runner.zig").TestRunner;
const TestMetadataSystem = @import("test_metadata.zig").TestMetadataSystem;

// Integration test demonstrating TestRunner with advanced metadata system
test "TestRunner with advanced metadata system integration" {
    const allocator = std.testing.allocator;

    // Initialize both systems
    var platforms = [_]TestRunner.TestConfig.Platform{.linux_x86_64};
    var optimization_levels = [_]TestRunner.TestConfig.OptimizationLevel{.release_fast};

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
    var metadata_system = TestMetadataSystem.init(allocator);

    // Verify runner is properly initialized with advanced configuration
    try std.testing.expect(runner.config.optimization_levels[0] == .release_fast);
    try std.testing.expect(runner.config.timeout_seconds == 30);

    // Test advanced metadata parsing
    const advanced_source =
        \\// @description: Advanced dispatch test showcasing comprehensive metadata system
        \\// @author: Golden Test Framework Team
        \\// @expected-strategy: hybrid_dispatch
        \\// @performance: dispatch_overhead_ns < 20
        \\// @performance: cache_miss_rate <= 0.05
        \\// @performance: memory_footprint < 1024
        \\// @performance: throughput_ops_per_sec >= 10000
        \\// @platforms: all
        \\// @optimization: release_fast
        \\// @timeout: 180
        \\
        \\func process(data: DataStream, processor: CPUProcessor) -> ProcessedResult {
        \\    processor.optimizeForCPU(data)
        \\}
        \\
        \\func process(data: DataStream, processor: GPUProcessor) -> ProcessedResult {
        \\    processor.optimizeForGPU(data)
        \\}
        \\
        \\func main() {
        \\    let cpu_data = DataStream.fromFile("input.dat")
        \\    let gpu_data = DataStream.fromFile("large_input.dat")
        \\
        \\    let cpu_processor = CPUProcessor.new()
        \\    let gpu_processor = GPUProcessor.new()
        \\
        \\    let result1 = process(cpu_data, cpu_processor)
        \\    let result2 = process(gpu_data, gpu_processor)
        \\}
    ;

    var metadata = try metadata_system.parseMetadata(advanced_source, "advanced_metadata_test");
    defer metadata.deinit(allocator);

    // Verify comprehensive metadata parsing
    try std.testing.expectEqualStrings(metadata.test_name, "advanced_metadata_test");
    try std.testing.expect(metadata.description != null);
    try std.testing.expectEqualStrings(metadata.description.?, "Advanced dispatch test showcasing comprehensive metadata system");
    try std.testing.expect(metadata.author != null);
    try std.testing.expectEqualStrings(metadata.author.?, "Golden Test Framework Team");

    // Verify dispatch strategy
    try std.testing.expect(metadata.expected_strategy != null);
    try std.testing.expect(metadata.expected_strategy.?.strategy_type == .hybrid_dispatch);

    // Verify strategy characteristics
    const characteristics = metadata.expected_strategy.?.expected_characteristics;
    try std.testing.expect(characteristics.expected_complexity == .constant);
    try std.testing.expect(characteristics.memory_usage.base_overhead == 64);
    try std.testing.expect(characteristics.cache_behavior.locality == .serviceod);
    try std.testing.expect(characteristics.cache_behavior.prefetch_friendly == true);
    try std.testing.expect(characteristics.scalability.implementation_count_sensitivity == 0.1);

    // Verify multiple performance expectations
    std.log.info("Number of performance expectations: {}", .{metadata.performance_expectations.len});
    for (metadata.performance_expectations, 0..) |expectation, i| {
        std.log.info("Expectation {}: {s} {} {d}", .{ i, expectation.metric_name, expectation.threshold.operator, expectation.threshold.value });
    }
    try std.testing.expect(metadata.performance_expectations.len == 4);

    // First expectation: dispatch_overhead_ns < 20
    try std.testing.expectEqualStrings(metadata.performance_expectations[0].metric_name, "dispatch_overhead_ns");
    try std.testing.expect(metadata.performance_expectations[0].threshold.operator == .less_than);
    try std.testing.expect(metadata.performance_expectations[0].threshold.value == 20.0);
    try std.testing.expect(metadata.performance_expectations[0].expectation_type == .absolute_bound);

    // Second expectation: cache_miss_rate <= 0.05
    try std.testing.expectEqualStrings(metadata.performance_expectations[1].metric_name, "cache_miss_rate");
    try std.testing.expect(metadata.performance_expectations[1].threshold.operator == .less_equal);
    try std.testing.expect(metadata.performance_expectations[1].threshold.value == 0.05);

    // Third expectation: memory_footprint < 1024
    try std.testing.expectEqualStrings(metadata.performance_expectations[2].metric_name, "memory_footprint");
    try std.testing.expect(metadata.performance_expectations[2].threshold.operator == .less_than);
    try std.testing.expect(metadata.performance_expectations[2].threshold.value == 1024.0);

    // Fourth expectation: throughput_ops_per_sec >= 10000
    try std.testing.expectEqualStrings(metadata.performance_expectations[3].metric_name, "throughput_ops_per_sec");
    try std.testing.expect(metadata.performance_expectations[3].threshold.operator == .greater_equal);

    // Debug the actual value
    std.log.info("Expected: 10000.0, Actual: {d}", .{metadata.performance_expectations[3].threshold.value});
    try std.testing.expect(metadata.performance_expectations[3].threshold.value == 10000.0);

    // Verify measurement configuration for all expectations
    for (metadata.performance_expectations) |expectation| {
        try std.testing.expect(expectation.measurement_config.warmup_iterations == 100);
        try std.testing.expect(expectation.measurement_config.measurement_iterations == 1000);
        try std.testing.expect(expectation.measurement_config.measurement_duration_ms == 1000);
        try std.testing.expect(expectation.measurement_config.measurement_method == .wall_clock_time);
        try std.testing.expect(expectation.measurement_config.environment_isolation == true);

        // Verify statistical requirements
        try std.testing.expect(expectation.statistical_requirements.confidence_level == 0.95);
        try std.testing.expect(expectation.statistical_requirements.coreimum_sample_size == 30);
        try std.testing.expect(expectation.statistical_requirements.outlier_detection == true);
        try std.testing.expect(expectation.statistical_requirements.normality_test == false);
        try std.testing.expect(expectation.statistical_requirements.variance_stability == true);
    }

    // Verify platform configuration
    try std.testing.expect(metadata.platform_config.target_platforms.len == 5); // All platforms
    try std.testing.expect(metadata.platform_config.cross_platform_validation.semantic_equivalence_required == true);
    try std.testing.expect(metadata.platform_config.cross_platform_validation.performance_consistency_required == true);
    try std.testing.expect(metadata.platform_config.cross_platform_validation.acceptable_variance_percentage == 5.0);

    // Verify optimization configuration
    try std.testing.expect(metadata.optimization_config.optimization_levels.len == 1);
    try std.testing.expect(metadata.optimization_config.optimization_levels[0] == .release_fast);
    try std.testing.expect(metadata.optimization_config.optimization_validation.validate_debug_info == true);
    try std.testing.expect(metadata.optimization_config.optimization_validation.validate_performance_improvement == true);
    try std.testing.expect(metadata.optimization_config.optimization_validation.validate_code_size == true);
    try std.testing.expect(metadata.optimization_config.optimization_validation.validate_compilation_time == true);

    // Verify execution configuration
    try std.testing.expect(metadata.execution_config.timeout_seconds == 180);
    try std.testing.expect(metadata.execution_config.retry_count == 0);
    try std.testing.expect(metadata.execution_config.parallel_execution == true);
    try std.testing.expect(metadata.execution_config.resource_limits.max_memory_mb == 1024);
    try std.testing.expect(metadata.execution_config.resource_limits.max_cpu_time_seconds == 60);
    try std.testing.expect(metadata.execution_config.resource_limits.max_wall_time_seconds == 120);
    try std.testing.expect(metadata.execution_config.isolation_requirements.process_isolation == true);
    try std.testing.expect(metadata.execution_config.isolation_requirements.network_isolation == true);

    // Verify validation configuration
    try std.testing.expect(metadata.validation_config.validation_strictness == .strict);

    // Verify metadata versioning
    try std.testing.expect(metadata.metadata_version == 1);
    try std.testing.expect(metadata.compatibility_version == 1);

    // Verify checksum is calculated
    var zero_checksum = std.mem.zeroes([32]u8);
    try std.testing.expect(!std.mem.eql(u8, &metadata.checksum, &zero_checksum));

    std.log.info("Advanced metadata system integration test completed successfully", .{});
}

// Test metadata validation with comprehensive validation rules
test "Advanced metadata validation" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    // Create comprehensive metadata for validation
    var metadata = try metadata_system.parseMetadata(
        \\// @description: Comprehensive validation test
        \\// @author: Test Engineer
        \\// @expected-strategy: perfect_hash
        \\// @performance: dispatch_overhead_ns < 30
        \\// @performance: memory_usage_bytes <= 256
        \\// @platforms: all
        \\// @optimization: release_safe
        \\// @timeout: 60
        \\
        \\func test_function() -> void {}
    , "validation_test");
    defer metadata.deinit(allocator);

    // Validate the metadata
    var validation_result = try metadata_system.validateMetadata(&metadata);
    defer validation_result.deinit();

    // Should be valid
    try std.testing.expect(validation_result.is_valid == true);
    try std.testing.expect(validation_result.errors.items.len == 0);

    // May have warnings about missing optional fields
    std.log.info("Validation completed with {} warnings", .{validation_result.warnings.items.len});

    for (validation_result.warnings.items) |warning| {
        std.log.info("Warning: {s} - {s}", .{ warning.field_name, warning.message });
    }
}

// Test platform-specific configuration parsing
test "Platform-specific configuration parsing" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    // Test all supported platforms
    const platform_names = [_][]const u8{
        "linux_x86_64",
        "linux_aarch64",
        "macos_x86_64",
        "macos_aarch64",
        "windows_x86_64",
    };

    for (platform_names) |platform_name| {
        const platform_enum = std.meta.stringToEnum(TestMetadataSystem.PlatformConfiguration.Platform, platform_name).?;
        try std.testing.expectEqualStrings(platform_enum.toString(), platform_name);
    }

    // Test "all" platforms configuration
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

    try metadata_system.parsePlatformConfiguration("all", &platform_config);
    defer platform_config.deinit(allocator);

    try std.testing.expect(platform_config.target_platforms.len == 5);

    // Verify all expected platforms are included
    const expected_platforms = [_]TestMetadataSystem.PlatformConfiguration.Platform{ .linux_x86_64, .linux_aarch64, .macos_x86_64, .macos_aarch64, .windows_x86_64 };

    for (expected_platforms, 0..) |expected_platform, i| {
        try std.testing.expect(platform_config.target_platforms[i] == expected_platform);
    }
}

// Test optimization level configuration
test "Optimization level configuration" {
    const allocator = std.testing.allocator;

    var metadata_system = TestMetadataSystem.init(allocator);

    const optimization_levels = [_][]const u8{
        "debug",
        "release_safe",
        "release_fast",
        "release_small",
    };

    for (optimization_levels) |level_name| {
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

        try metadata_system.parseOptimizationConfiguration(level_name, &opt_config);
        defer opt_config.deinit(allocator);

        try std.testing.expect(opt_config.optimization_levels.len == 1);

        const expected_level = std.meta.stringToEnum(TestMetadataSystem.OptimizationConfiguration.OptimizationLevel, level_name).?;
        try std.testing.expect(opt_config.optimization_levels[0] == expected_level);
        try std.testing.expectEqualStrings(opt_config.optimization_levels[0].toString(), level_name);
    }
}
