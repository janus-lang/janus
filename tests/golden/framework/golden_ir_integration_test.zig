// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const IRIntegration = @import("ir_integration.zig").IRIntegration;
const GoldenDiff = @import("golden_diff.zig").GoldenDiff;
const TestMetadata = @import("test_metadata.zig").TestMetadata;
const MetadataParser = @import("metadata_parser.zig").MetadataParser;
const ErrorRegistry = @import("error_registry.zig").ErrorRegistry;

test "Error Registry - Basic functionality" {
    const allocator = testing.allocator;

    var error_registry = try ErrorRegistry.init(allocator);
    defer error_registry.deinit();

    // Test error registry functionality
    const error_info = error_registry.getErrorInfo(.G1001_IR_GENERATION_FAILED);
    try testing.expect(error_info != null);
    try testing.expectEqualStrings(error_info.?.title, "IR Generation Failed");
    try testing.expect(error_info.?.severity == .critical);
}

test "Error Registry - Failure Report Creation" {
    const allocator = testing.allocator;

    var error_registry = try ErrorRegistry.init(allocator);
    defer error_registry.deinit();

    // Create a failure report
    var failure_report = try error_registry.createFailureReport(.G1103_DISPATCH_TABLE_MISSING, "test_case", "linux_x86_64", "release_safe", "Dispatch table not found in generated IR", .{
        .servicelden_reference_path = "tests/golden/references/test_case_linux_x86_64_release_safe.ll",
        .generated_ir_path = "/tmp/generated.ll",
        .metadata_source = "test_case.jan",
        .compiler_version = "janus-0.1.0",
        .environment_info = "CI Environment",
    }, .{
        .ir_diff_summary = "Missing dispatch table structure",
        .performance_metrics = "instruction_count: 25, expected: < 20",
        .contract_violations = "Expected switch_table dispatch strategy",
        .stack_trace = null,
        .debug_artifacts = null,
    });
    defer failure_report.deinit(allocator);

    // Verify failure report
    try testing.expect(failure_report.error_code == .G1103_DISPATCH_TABLE_MISSING);
    try testing.expectEqualStrings(failure_report.test_case, "test_case");
    try testing.expectEqualStrings(failure_report.platform, "linux_x86_64");

    // Format the failure report
    const formatted_report = try error_registry.formatFailureReport(failure_report);
    defer allocator.free(formatted_report);

    // Verify formatted report contains key information
    try testing.expect(std.mem.indexOf(u8, formatted_report, "G1103") != null);
    try testing.expect(std.mem.indexOf(u8, formatted_report, "Dispatch Table Missing") != null);
    try testing.expect(std.mem.indexOf(u8, formatted_report, "test_case") != null);
}

test "Metadata Integration - Performance Contract Validation" {
    const allocator = testing.allocator;

    var metadata_parser = MetadataParser.init(allocator);

    const test_source =
        \\// @description: Test case with performance contracts
        \\// @expected-strategy: static_dispatch
        \\// @performance: dispatch_overhead_ns < 5 ±1% @99%
        \\// @performance: instruction_count <= 10
        \\// @platforms: all
        \\// @optimization-levels: release_safe
        \\
        \\func add(x: i32, y: i32) -> i32 {
        \\    x + y
        \\}
        \\
        \\func main() {
        \\    let result = add(5, 10)
        \\}
    ;

    var metadata = try metadata_parser.parseFromSource("test_case", test_source);
    defer metadata.deinit(allocator);

    // Verify metadata parsing
    try testing.expect(metadata.expected_strategy != null);
    try testing.expect(metadata.expected_strategy.? == .static_dispatch);

    try testing.expect(metadata.performance_expectations.len == 2);

    // Check first performance expectation
    const perf1 = metadata.performance_expectations[0];
    try testing.expect(perf1.metric == .dispatch_overhead_ns);
    try testing.expect(perf1.operator == .less_than);
    try testing.expect(perf1.threshold == 5.0);
    try testing.expect(perf1.tolerance != null);
    try testing.expect(perf1.tolerance.? == 1.0);
    try testing.expect(perf1.confidence_level == 99.0);

    // Check second performance expectation
    const perf2 = metadata.performance_expectations[1];
    try testing.expect(perf2.metric == .instruction_count);
    try testing.expect(perf2.operator == .less_equal);
    try testing.expect(perf2.threshold == 10.0);
}

test "Golden Diff - Basic initialization" {
    const allocator = testing.allocator;

    var golden_diff = GoldenDiff.init(allocator);
    _ = golden_diff; // Suppress unused variable warning

    // Test basic initialization
    try testing.expect(true); // Placeholder test
}

test "IR Integration - Basic initialization" {
    const allocator = testing.allocator;

    var ir_integration = IRIntegration.init(allocator);
    _ = ir_integration; // Suppress unused variable warning

    // Test basic initialization
    try testing.expect(true); // Placeholder test
}

test "Mock Golden Test Workflow" {
    const allocator = testing.allocator;

    // This test simulates the complete golden test workflow
    // without actually invoking the compiler or file system

    var error_registry = try ErrorRegistry.init(allocator);
    defer error_registry.deinit();

    // Mock metadata for static dispatch test
    const mock_metadata = TestMetadata{
        .expected_strategy = .static_dispatch,
        .fallback_strategies = &.{},
        .performance_expectations = &.{
            .{
                .metric = .instruction_count,
                .operator = .less_than,
                .threshold = 15.0,
                .tolerance = null,
                .confidence_level = 95.0,
                .unit = "count",
            },
        },
        .platform_requirements = &.{},
        .execution_config = .{
            .timeout_seconds = 30,
            .memory_limit_mb = 256,
            .cpu_limit_percent = 80,
        },
        .dependencies = &.{},
        .validation_rules = &.{},
        .quality_gates = &.{},
    };

    // Verify mock metadata structure
    try testing.expect(mock_metadata.expected_strategy.? == .static_dispatch);
    try testing.expect(mock_metadata.performance_expectations.len == 1);
    try testing.expect(mock_metadata.performance_expectations[0].threshold == 15.0);
}

test "Performance Contract Structure" {
    const allocator = testing.allocator;

    // Test performance expectation structure
    const perf_expectation = TestMetadata.PerformanceExpectation{
        .metric = .dispatch_overhead_ns,
        .operator = .less_than,
        .threshold = 30.0,
        .tolerance = 5.0,
        .confidence_level = 95.0,
        .unit = "nanoseconds",
    };

    try testing.expect(perf_expectation.metric == .dispatch_overhead_ns);
    try testing.expect(perf_expectation.operator == .less_than);
    try testing.expect(perf_expectation.threshold == 30.0);
    try testing.expect(perf_expectation.tolerance.? == 5.0);
    try testing.expect(perf_expectation.confidence_level == 95.0);

    _ = allocator; // Suppress unused variable warning
}

test "Validation Rule Structure" {
    const allocator = testing.allocator;

    // Test validation rule structure
    const validation_rule = TestMetadata.ValidationRule{
        .rule_type = .ir_structure,
        .validation_function = "validate_static_dispatch",
        .description = "Must contain direct function calls, no dispatch tables",
    };

    try testing.expect(validation_rule.rule_type == .ir_structure);
    try testing.expectEqualStrings(validation_rule.validation_function, "validate_static_dispatch");
    try testing.expectEqualStrings(validation_rule.description, "Must contain direct function calls, no dispatch tables");

    _ = allocator; // Suppress unused variable warning
}

test "Quality Gate Structure" {
    const allocator = testing.allocator;

    // Test quality gate structure
    const quality_gate = TestMetadata.QualityGate{
        .gate_name = "static_stability",
        .gate_type = .performance_stability,
        .threshold = 0.01,
        .sample_size = 100,
    };

    try testing.expectEqualStrings(quality_gate.gate_name, "static_stability");
    try testing.expect(quality_gate.gate_type == .performance_stability);
    try testing.expect(quality_gate.threshold == 0.01);
    try testing.expect(quality_gate.sample_size == 100);

    _ = allocator; // Suppress unused variable warning
}
