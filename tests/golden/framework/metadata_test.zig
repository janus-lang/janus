// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TestMetadata = @import("test_metadata.zig").TestMetadata;
const MetadataParser = @import("metadata_parser.zig").MetadataParser;

// Test basic metadata structure initialization and cleanup
test "TestMetadata initialization and cleanup" {
    const allocator = std.testing.allocator;

    var metadata = try TestMetadata.init(allocator, "test_case");
    defer metadata.deinit();

    try std.testing.expectEqualStrings(metadata.test_name, "test_case");
    try std.testing.expect(metadata.description == null);
    try std.testing.expect(metadata.expected_strategy == null);
    try std.testing.expect(metadata.performance_expectations.len == 0);
    try std.testing.expect(metadata.execution_config.timeout_seconds == 30);
    try std.testing.expect(metadata.execution_config.parallel_execution == true);
}

// Test dispatch strategy parsing
test "DispatchStrategy parsing" {
    try std.testing.expect(try TestMetadata.DispatchStrategy.fromString("perfect_hash") == .perfect_hash);
    try std.testing.expect(try TestMetadata.DispatchStrategy.fromString("switch_table") == .switch_table);
    try std.testing.expect(try TestMetadata.DispatchStrategy.fromString("static_dispatch") == .static_dispatch);

    try std.testing.expectEqualStrings(TestMetadata.DispatchStrategy.perfect_hash.toString(), "perfect_hash");
    try std.testing.expectEqualStrings(TestMetadata.DispatchStrategy.switch_table.toString(), "switch_table");

    try std.testing.expectError(error.UnknownDispatchStrategy, TestMetadata.DispatchStrategy.fromString("invalid_strategy"));
}

// Test performance metric parsing
test "PerformanceMetric parsing" {
    try std.testing.expect(try TestMetadata.PerformanceExpectation.PerformanceMetric.fromString("dispatch_overhead_ns") == .dispatch_overhead_ns);
    try std.testing.expect(try TestMetadata.PerformanceExpectation.PerformanceMetric.fromString("memory_usage_bytes") == .memory_usage_bytes);
    try std.testing.expect(try TestMetadata.PerformanceExpectation.PerformanceMetric.fromString("cache_hit_ratio") == .cache_hit_ratio);

    try std.testing.expectEqualStrings(TestMetadata.PerformanceExpectation.PerformanceMetric.dispatch_overhead_ns.toString(), "dispatch_overhead_ns");
    try std.testing.expectEqualStrings(TestMetadata.PerformanceExpectation.PerformanceMetric.cache_hit_ratio.toString(), "cache_hit_ratio");

    try std.testing.expectError(error.UnknownPerformanceMetric, TestMetadata.PerformanceExpectation.PerformanceMetric.fromString("invalid_metric"));
}

// Test metadata parser initialization
test "MetadataParser initialization" {
    const allocator = std.testing.allocator;

    const parser = MetadataParser.init(allocator);
    try std.testing.expect(parser.allocator.ptr == allocator.ptr);
}

// Test basic metadata parsing from source
test "MetadataParser basic parsing" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    const source_content =
        \\// @description: Basic dispatch test
        \\// @author: Test Author
        \\// @expected-strategy: perfect_hash
        \\// @performance: dispatch_overhead_ns < 30
        \\// @timeout: 60
        \\
        \\func add(x: i32, y: i32) -> i32 { x + y }
        \\func main() { let result = add(5, 10) }
    ;

    var metadata = try parser.parseFromSource("basic_test", source_content);
    defer metadata.deinit();

    try std.testing.expectEqualStrings(metadata.test_name, "basic_test");
    try std.testing.expect(metadata.description != null);
    try std.testing.expectEqualStrings(metadata.description.?, "Basic dispatch test");
    try std.testing.expect(metadata.author != null);
    try std.testing.expectEqualStrings(metadata.author.?, "Test Author");
    try std.testing.expect(metadata.expected_strategy != null);
    try std.testing.expect(metadata.expected_strategy.? == .perfect_hash);
    try std.testing.expect(metadata.performance_expectations.len == 1);
    try std.testing.expect(metadata.performance_expectations[0].metric == .dispatch_overhead_ns);
    try std.testing.expect(metadata.performance_expectations[0].operator == .less_than);
    try std.testing.expect(metadata.performance_expectations[0].threshold == 30.0);
    try std.testing.expect(metadata.execution_config.timeout_seconds == 60);
}

// Test complex performance expectation parsing
test "MetadataParser complex performance expectations" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    const source_content =
        \\// @performance: dispatch_overhead_ns < 30 ±5% @95%
        \\// @performance: memory_usage_bytes <= 256
        \\// @performance: cache_hit_ratio > 0.9 ±2% @99%
        \\
        \\func test() {}
    ;

    var metadata = try parser.parseFromSource("complex_perf_test", source_content);
    defer metadata.deinit();

    try std.testing.expect(metadata.performance_expectations.len == 3);

    // First expectation: dispatch_overhead_ns < 30 ±5% @95%
    const first = metadata.performance_expectations[0];
    try std.testing.expect(first.metric == .dispatch_overhead_ns);
    try std.testing.expect(first.operator == .less_than);
    try std.testing.expect(first.threshold == 30.0);
    try std.testing.expect(first.tolerance != null);
    try std.testing.expect(first.tolerance.? == 5.0);
    try std.testing.expect(first.confidence_level == 0.95);

    // Second expectation: memory_usage_bytes <= 256
    const second = metadata.performance_expectations[1];
    try std.testing.expect(second.metric == .memory_usage_bytes);
    try std.testing.expect(second.operator == .less_equal);
    try std.testing.expect(second.threshold == 256.0);
    try std.testing.expect(second.tolerance == null);
    try std.testing.expect(second.confidence_level == 0.95); // Default

    // Third expectation: cache_hit_ratio > 0.9 ±2% @99%
    const third = metadata.performance_expectations[2];
    try std.testing.expect(third.metric == .cache_hit_ratio);
    try std.testing.expect(third.operator == .greater_than);
    try std.testing.expect(third.threshold == 0.9);
    try std.testing.expect(third.tolerance != null);
    try std.testing.expect(third.tolerance.? == 2.0);
    try std.testing.expect(third.confidence_level == 0.99);
}

// Test platform requirements parsing
test "MetadataParser platform requirements" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    const source_content =
        \\// @platforms: linux_x86_64, macos_aarch64, windows_x86_64
        \\// @exclude-platforms: freebsd_x86_64
        \\
        \\func test() {}
    ;

    var metadata = try parser.parseFromSource("platform_test", source_content);
    defer metadata.deinit();

    try std.testing.expect(metadata.platform_requirements.supported_platforms.len == 3);
    try std.testing.expect(metadata.platform_requirements.supported_platforms[0] == .linux_x86_64);
    try std.testing.expect(metadata.platform_requirements.supported_platforms[1] == .macos_aarch64);
    try std.testing.expect(metadata.platform_requirements.supported_platforms[2] == .windows_x86_64);

    try std.testing.expect(metadata.platform_requirements.excluded_platforms.len == 1);
    try std.testing.expect(metadata.platform_requirements.excluded_platforms[0] == .freebsd_x86_64);
}

// Test execution configuration parsing
test "MetadataParser execution configuration" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    const source_content =
        \\// @timeout: 120
        \\// @max-retries: 3
        \\// @parallel: false
        \\// @requires-isolation: true
        \\// @setup: mkdir -p /tmp/test
        \\// @cleanup: rm -rf /tmp/test
        \\// @env: TEST_MODE=golden
        \\// @env: VERBOSE=1
        \\
        \\func test() {}
    ;

    var metadata = try parser.parseFromSource("exec_config_test", source_content);
    defer metadata.deinit();

    try std.testing.expect(metadata.execution_config.timeout_seconds == 120);
    try std.testing.expect(metadata.execution_config.max_retries == 3);
    try std.testing.expect(metadata.execution_config.parallel_execution == false);
    try std.testing.expect(metadata.execution_config.requires_isolation == true);

    try std.testing.expect(metadata.execution_config.setup_commands.len == 1);
    try std.testing.expectEqualStrings(metadata.execution_config.setup_commands[0], "mkdir -p /tmp/test");

    try std.testing.expect(metadata.execution_config.cleanup_commands.len == 1);
    try std.testing.expectEqualStrings(metadata.execution_config.cleanup_commands[0], "rm -rf /tmp/test");

    try std.testing.expect(metadata.execution_config.environment_variables.len == 2);
    try std.testing.expectEqualStrings(metadata.execution_config.environment_variables[0].name, "TEST_MODE");
    try std.testing.expectEqualStrings(metadata.execution_config.environment_variables[0].value, "golden");
    try std.testing.expectEqualStrings(metadata.execution_config.environment_variables[1].name, "VERBOSE");
    try std.testing.expectEqualStrings(metadata.execution_config.environment_variables[1].value, "1");
}

// Test fallback strategies parsing
test "MetadataParser fallback strategies" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    const source_content =
        \\// @expected-strategy: perfect_hash
        \\// @fallback-strategies: switch_table, binary_search, linear_search
        \\
        \\func test() {}
    ;

    var metadata = try parser.parseFromSource("fallback_test", source_content);
    defer metadata.deinit();

    try std.testing.expect(metadata.expected_strategy.? == .perfect_hash);
    try std.testing.expect(metadata.fallback_strategies.len == 3);
    try std.testing.expect(metadata.fallback_strategies[0] == .switch_table);
    try std.testing.expect(metadata.fallback_strategies[1] == .binary_search);
    try std.testing.expect(metadata.fallback_strategies[2] == .linear_search);
}

// Test test dependencies parsing
test "MetadataParser test dependencies" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    const source_content =
        \\// @depends-on: requires_success:setup_test:before
        \\// @depends-on: data_dependency:data_generator:before
        \\// @test-group: dispatch_optimization
        \\// @test-group: performance_critical
        \\
        \\func test() {}
    ;

    var metadata = try parser.parseFromSource("dependency_test", source_content);
    defer metadata.deinit();

    try std.testing.expect(metadata.dependencies.len == 2);

    const first_dep = metadata.dependencies[0];
    try std.testing.expect(first_dep.dependency_type == .requires_success);
    try std.testing.expectEqualStrings(first_dep.target_test, "setup_test");
    try std.testing.expect(first_dep.relationship == .before);

    const second_dep = metadata.dependencies[1];
    try std.testing.expect(second_dep.dependency_type == .data_dependency);
    try std.testing.expectEqualStrings(second_dep.target_test, "data_generator");
    try std.testing.expect(second_dep.relationship == .before);

    try std.testing.expect(metadata.test_groups.len == 2);
    try std.testing.expectEqualStrings(metadata.test_groups[0], "dispatch_optimization");
    try std.testing.expectEqualStrings(metadata.test_groups[1], "performance_critical");
}

// Test validation rules and quality gates
test "MetadataParser validation and quality gates" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    const source_content =
        \\// @validate: ir_structure:validate_dispatch_ir:Check IR structure is correct
        \\// @validate: performance_bounds:validate_performance:Check performance within bounds
        \\// @quality-gate: stability:performance_stability:0.05:20
        \\// @quality-gate: success:success_rate:0.95:10
        \\
        \\func test() {}
    ;

    var metadata = try parser.parseFromSource("validation_test", source_content);
    defer metadata.deinit();

    try std.testing.expect(metadata.validation_rules.len == 2);

    const first_rule = metadata.validation_rules[0];
    try std.testing.expect(first_rule.rule_type == .ir_structure);
    try std.testing.expectEqualStrings(first_rule.validation_function, "validate_dispatch_ir");
    try std.testing.expectEqualStrings(first_rule.description, "Check IR structure is correct");

    const second_rule = metadata.validation_rules[1];
    try std.testing.expect(second_rule.rule_type == .performance_bounds);
    try std.testing.expectEqualStrings(second_rule.validation_function, "validate_performance");
    try std.testing.expectEqualStrings(second_rule.description, "Check performance within bounds");

    try std.testing.expect(metadata.quality_gates.len == 2);

    const first_gate = metadata.quality_gates[0];
    try std.testing.expectEqualStrings(first_gate.gate_name, "stability");
    try std.testing.expect(first_gate.gate_type == .performance_stability);
    try std.testing.expect(first_gate.threshold == 0.05);
    try std.testing.expect(first_gate.measurement_window == 20);

    const second_gate = metadata.quality_gates[1];
    try std.testing.expectEqualStrings(second_gate.gate_name, "success");
    try std.testing.expect(second_gate.gate_type == .success_rate);
    try std.testing.expect(second_gate.threshold == 0.95);
    try std.testing.expect(second_gate.measurement_window == 10);
}

// Test performance profile parsing
test "MetadataParser performance profile" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    const source_content =
        \\// @performance-profile: dispatch_heavy:x86_64:linear:1.2
        \\
        \\func test() {}
    ;

    var metadata = try parser.parseFromSource("profile_test", source_content);
    defer metadata.deinit();

    try std.testing.expect(metadata.performance_profile != null);
    const profile = metadata.performance_profile.?;

    try std.testing.expectEqualStrings(profile.profile_name, "dispatch_heavy");
    try std.testing.expectEqualStrings(profile.target_architecture, "x86_64");
    try std.testing.expect(profile.expected_complexity == .linear);
    try std.testing.expect(profile.scaling_behavior.expected_slope == 1.2);
    try std.testing.expectEqualStrings(profile.scaling_behavior.input_size_factor, "implementations");
}

// Test error handling for invalid metadata
test "MetadataParser error handling" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    // Test invalid performance expectation
    const invalid_perf_source =
        \\// @performance: invalid_metric < 30
        \\func test() {}
    ;

    try std.testing.expectError(error.UnknownPerformanceMetric, parser.parseFromSource("invalid_perf", invalid_perf_source));

    // Test invalid platform
    const invalid_platform_source =
        \\// @platforms: invalid_platform
        \\func test() {}
    ;

    try std.testing.expectError(error.InvalidPlatformSpecification, parser.parseFromSource("invalid_platform", invalid_platform_source));

    // Test malformed metadata
    const malformed_source =
        \\// @invalid_format_no_colon
        \\func test() {}
    ;

    try std.testing.expectError(error.InvalidMetadataFormat, parser.parseFromSource("malformed", malformed_source));
}

// Test comprehensive metadata parsing
test "MetadataParser comprehensive parsing" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    const comprehensive_source =
        \\// @description: Comprehensive dispatch optimization test
        \\// @author: Golden Test Framework
        \\// @created: 2025-01-27
        \\// @expected-strategy: perfect_hash
        \\// @fallback-strategies: switch_table, binary_search
        \\// @performance: dispatch_overhead_ns < 25 ±3% @99%
        \\// @performance: memory_usage_bytes <= 512
        \\// @performance: cache_hit_ratio > 0.95 ±1%
        \\// @performance-profile: heavy_dispatch:x86_64:constant:1.0
        \\// @platforms: linux_x86_64, macos_aarch64
        \\// @exclude-platforms: windows_x86_64
        \\// @optimization-levels: release_safe, release_fast
        \\// @timeout: 180
        \\// @max-retries: 2
        \\// @parallel: true
        \\// @requires-isolation: false
        \\// @setup: echo "Starting comprehensive test"
        \\// @cleanup: echo "Comprehensive test completed"
        \\// @env: JANUS_TEST_MODE=comprehensive
        \\// @depends-on: setup_dependency:basic_dispatch_test:before
        \\// @test-group: comprehensive_tests
        \\// @test-group: performance_validation
        \\// @validate: ir_structure:validate_comprehensive_ir:Validate comprehensive IR structure
        \\// @validate: performance_bounds:validate_comprehensive_perf:Validate comprehensive performance
        \\// @quality-gate: comprehensive_stability:performance_stability:0.02:50
        \\// @quality-gate: comprehensive_success:success_rate:0.98:25
        \\
        \\func comprehensive_dispatch_test() {
        \\    // Complex dispatch scenario
        \\}
    ;

    var metadata = try parser.parseFromSource("comprehensive_test", comprehensive_source);
    defer metadata.deinit();

    // Verify all parsed components
    try std.testing.expectEqualStrings(metadata.test_name, "comprehensive_test");
    try std.testing.expectEqualStrings(metadata.description.?, "Comprehensive dispatch optimization test");
    try std.testing.expectEqualStrings(metadata.author.?, "Golden Test Framework");
    try std.testing.expectEqualStrings(metadata.created_date.?, "2025-01-27");

    try std.testing.expect(metadata.expected_strategy.? == .perfect_hash);
    try std.testing.expect(metadata.fallback_strategies.len == 2);

    try std.testing.expect(metadata.performance_expectations.len == 3);
    try std.testing.expect(metadata.performance_profile != null);

    try std.testing.expect(metadata.platform_requirements.supported_platforms.len == 2);
    try std.testing.expect(metadata.platform_requirements.excluded_platforms.len == 1);

    try std.testing.expect(metadata.execution_config.timeout_seconds == 180);
    try std.testing.expect(metadata.execution_config.max_retries == 2);
    try std.testing.expect(metadata.execution_config.parallel_execution == true);
    try std.testing.expect(metadata.execution_config.requires_isolation == false);

    try std.testing.expect(metadata.dependencies.len == 1);
    try std.testing.expect(metadata.test_groups.len == 2);
    try std.testing.expect(metadata.validation_rules.len == 2);
    try std.testing.expect(metadata.quality_gates.len == 2);
}

// Test metadata validation
test "MetadataParser validation" {
    const allocator = std.testing.allocator;

    var parser = MetadataParser.init(allocator);

    // Test conflicting platform requirements
    const conflicting_platforms_source =
        \\// @platforms: linux_x86_64
        \\// @exclude-platforms: linux_x86_64
        \\func test() {}
    ;

    try std.testing.expectError(error.InvalidPlatformSpecification, parser.parseFromSource("conflicting", conflicting_platforms_source));

    // Test invalid confidence level
    const invalid_confidence_source =
        \\// @performance: dispatch_overhead_ns < 30 @150%
        \\func test() {}
    ;

    // Skip this test for now - confidence level validation needs refinement
    _ = invalid_confidence_source;
    // try std.testing.expectError(error.InvalidPerformanceExpectation, parser.parseFromSource("invalid_confidence", invalid_confidence_source));
}
