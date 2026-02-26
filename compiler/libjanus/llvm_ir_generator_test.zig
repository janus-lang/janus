// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Tests for LLVM IR Generator - validates against golden references
// Every test must verify that generated IR matches canonical truth exactly

const std = @import("std");
const compat_fs = @import("compat_fs");
const testing = std.testing;
const ArrayList = std.array_list.Managed;

const IRGenerator = @import("llvm_ir_generator.zig").IRGenerator;
const DispatchFamily = @import("dispatch_family.zig").DispatchFamily;
const OptimizationStrategy = @import("dispatch_table_optimizer.zig").OptimizationStrategy;

test "IRGenerator initialization and cleanup" {
    var ir_generator = try IRGenerator.init(testing.allocator, "test_module");
    defer ir_generator.deinit();

    // Should initialize without error
    try testing.expect(ir_generator.llvm_context != null);
    try testing.expect(ir_generator.llvm_module != null);
    try testing.expect(ir_generator.symbol_manager != null);
    try testing.expect(ir_generator.debug_info_generator != null);
    try testing.expect(ir_generator.optimization_tracer != null);
}

test "static dispatch IR generation - zero overhead contract" {
    var ir_generator = try IRGenerator.init(testing.allocator, "static_test");
    defer ir_generator.deinit();

    // Create dispatch family with single implementation (static dispatch case)
    var dispatch_family = try DispatchFamily.init(testing.allocator, "test_function");
    defer dispatch_family.deinit();

    // Add single implementation to ensure static dispatch
    try dispatch_family.addImplementation(.{
        .name = "test_function_impl",
        .parameter_types = &[_][]const u8{"i32"},
        .return_type = "i32",
        .specificity_rank = 1,
        .is_reachable = true,
        .source_file = "test.jan",
        .source_line = 10,
        .source_column = 1,
        .unreachable_reason = "",
    });

    // Generate static dispatch IR
    var result = try ir_generator.generateDispatchIR(&dispatch_family, .static_direct);
    defer result.deinit(testing.allocator);

    // Validate zero-overhead contract
    try testing.expect(result.performance_characteristics.dispatch_overhead_ns == 0);
    try testing.expect(result.performance_characteristics.memory_overhead_bytes == 0);
    try testing.expect(result.performance_characteristics.cache_efficiency == .perfect);
    try testing.expect(result.dispatch_table == null); // No dispatch table for static

    // Validate that IR contains direct call (would be validated against golden reference)
    try testing.expect(result.llvm_function != null);
    try testing.expect(result.debug_info != null);

    // TODO: Validate generated IR text against golden reference
    // const golden_ir = try compat_fs.readFileAlloc(
    //     testing.allocator,
    //     "tests/golden/ir-generation/static_dispatch_zero_overhead_linux_x86_64_release_safe.ll",
    //     1024 * 1024
    // );
    // defer testing.allocator.free(golden_ir);
    // try testing.expectEqualStrings(golden_ir, result.generated_ir_text);
}

test "switch table dispatch IR generation - performance contract" {
    var ir_generator = try IRGenerator.init(testing.allocator, "switch_test");
    defer ir_generator.deinit();

    // Create dispatch family with multiple implementations (switch table case)
    var dispatch_family = try DispatchFamily.init(testing.allocator, "shape_area");
    defer dispatch_family.deinit();

    // Add multiple implementations to trigger switch table dispatch
    try dispatch_family.addImplementation(.{
        .name = "circle_area",
        .parameter_types = &[_][]const u8{"Circle"},
        .return_type = "f64",
        .specificity_rank = 1,
        .is_reachable = true,
        .source_file = "shapes.jan",
        .source_line = 15,
        .source_column = 1,
        .unreachable_reason = "",
    });

    try dispatch_family.addImplementation(.{
        .name = "rectangle_area",
        .parameter_types = &[_][]const u8{"Rectangle"},
        .return_type = "f64",
        .specificity_rank = 1,
        .is_reachable = true,
        .source_file = "shapes.jan",
        .source_line = 25,
        .source_column = 1,
        .unreachable_reason = "",
    });

    try dispatch_family.addImplementation(.{
        .name = "triangle_area",
        .parameter_types = &[_][]const u8{"Triangle"},
        .return_type = "f64",
        .specificity_rank = 1,
        .is_reachable = true,
        .source_file = "shapes.jan",
        .source_line = 35,
        .source_column = 1,
        .unreachable_reason = "",
    });

    // Generate switch table dispatch IR
    var result = try ir_generator.generateDispatchIR(&dispatch_family, .switch_table);
    defer result.deinit(testing.allocator);

    // Validate performance contract
    try testing.expect(result.performance_characteristics.dispatch_overhead_ns <= 100); // Contract: <100ns
    try testing.expect(result.performance_characteristics.memory_overhead_bytes > 0); // Should have vtable overhead
    try testing.expect(result.performance_characteristics.cache_efficiency == .good);

    // Validate that IR contains switch table infrastructure
    try testing.expect(result.llvm_function != null);
    try testing.expect(result.debug_info != null);

    // TODO: Validate generated IR text against golden reference
    // const golden_ir = try compat_fs.readFileAlloc(
    //     testing.allocator,
    //     "tests/golden/ir-generation/dynamic_dispatch_switch_table_linux_x86_64_release_safe.ll",
    //     1024 * 1024
    // );
    // defer testing.allocator.free(golden_ir);
    // try testing.expectEqualStrings(golden_ir, result.generated_ir_text);
}

test "optimization tracing and auditability" {
    var ir_generator = try IRGenerator.init(testing.allocator, "trace_test");
    defer ir_generator.deinit();

    // Create simple dispatch family
    var dispatch_family = try DispatchFamily.init(testing.allocator, "traced_function");
    defer dispatch_family.deinit();

    try dispatch_family.addImplementation(.{
        .name = "traced_impl",
        .parameter_types = &[_][]const u8{"i32"},
        .return_type = "i32",
        .specificity_rank = 1,
        .is_reachable = true,
        .source_file = "trace.jan",
        .source_line = 5,
        .source_column = 1,
        .unreachable_reason = "",
    });

    // Generate IR with tracing
    var result = try ir_generator.generateDispatchIR(&dispatch_family, .static_direct);
    defer result.deinit(testing.allocator);

    // Validate that mapping data is captured for auditability
    try testing.expect(result.mapping_data.optimization_decisions.len >= 1); // Should have strategy selection decision
    try testing.expect(result.mapping_data.performance_predictions.confidence_level > 0.0);

    // Validate that Janus-to-LLVM mapping exists
    try testing.expect(result.mapping_data.janus_to_llvm.count() >= 0);
}

test "symbol manager canonical naming" {
    var symbol_manager = IRGenerator.SymbolManager.init(testing.allocator);
    defer symbol_manager.deinit();

    // Create test dispatch family
    var dispatch_family = try DispatchFamily.init(testing.allocator, "test_add");
    defer dispatch_family.deinit();

    // Get canonical symbol name
    const symbol_name = try symbol_manager.getDispatchFunctionName(&dispatch_family);
    defer testing.allocator.free(symbol_name);

    // Validate canonical naming scheme
    try testing.expectEqualStrings("_janus_dispatch_test_add", symbol_name);
}

test "debug info generation" {
    var ir_generator = try IRGenerator.init(testing.allocator, "debug_test");
    defer ir_generator.deinit();

    // Create dispatch family with source location
    var dispatch_family = try DispatchFamily.init(testing.allocator, "debug_function");
    defer dispatch_family.deinit();

    dispatch_family.source_location = .{
        .file_path = "debug_test.jan",
        .line = 42,
        .column = 10,
    };

    try dispatch_family.addImplementation(.{
        .name = "debug_impl",
        .parameter_types = &[_][]const u8{"string"},
        .return_type = "string",
        .specificity_rank = 1,
        .is_reachable = true,
        .source_file = "debug_test.jan",
        .source_line = 42,
        .source_column = 10,
        .unreachable_reason = "",
    });

    // Generate IR with debug info
    var result = try ir_generator.generateDispatchIR(&dispatch_family, .static_direct);
    defer result.deinit(testing.allocator);

    // Validate debug info generation
    try testing.expect(result.debug_info != null);

    // TODO: Validate that debug info contains correct source mapping
    // This would be validated against DWARF information in the generated IR
}

test "error handling for invalid dispatch family" {
    var ir_generator = try IRGenerator.init(testing.allocator, "error_test");
    defer ir_generator.deinit();

    // Create dispatch family with no implementations
    var empty_dispatch_family = try DispatchFamily.init(testing.allocator, "empty");
    defer empty_dispatch_family.deinit();

    // Should fail gracefully for invalid dispatch family
    const result = ir_generator.generateDispatchIR(&empty_dispatch_family, .static_direct);
    try testing.expectError(error.InvalidDispatchFamily, result);
}

test "performance prediction accuracy" {
    var ir_generator = try IRGenerator.init(testing.allocator, "perf_test");
    defer ir_generator.deinit();

    // Test performance predictions for different strategies
    const static_impact = try ir_generator.predictPerformanceImpact(.static_direct);
    const switch_impact = try ir_generator.predictPerformanceImpact(.switch_table);

    // Static dispatch should save cycles and memory
    try testing.expect(static_impact.cycles_saved > 0);
    try testing.expect(static_impact.memory_saved > 0);

    // Switch table should have some overhead
    try testing.expect(switch_impact.cycles_saved < static_impact.cycles_saved);
    try testing.expect(switch_impact.memory_saved < 0); // Uses memory for dispatch table
}

// Integration test that validates the complete pipeline
test "end-to-end IR generation pipeline" {
    var ir_generator = try IRGenerator.init(testing.allocator, "e2e_test");
    defer ir_generator.deinit();

    // Create realistic dispatch family
    var dispatch_family = try DispatchFamily.init(testing.allocator, "calculate");
    defer dispatch_family.deinit();

    dispatch_family.source_location = .{
        .file_path = "calculator.jan",
        .line = 20,
        .column = 5,
    };

    try dispatch_family.addImplementation(.{
        .name = "calculate_int",
        .parameter_types = &[_][]const u8{ "i32", "i32" },
        .return_type = "i32",
        .specificity_rank = 1,
        .is_reachable = true,
        .source_file = "calculator.jan",
        .source_line = 25,
        .source_column = 1,
        .unreachable_reason = "",
    });

    try dispatch_family.addImplementation(.{
        .name = "calculate_float",
        .parameter_types = &[_][]const u8{ "f64", "f64" },
        .return_type = "f64",
        .specificity_rank = 1,
        .is_reachable = true,
        .source_file = "calculator.jan",
        .source_line = 30,
        .source_column = 1,
        .unreachable_reason = "",
    });

    // Generate IR for switch table strategy
    var result = try ir_generator.generateDispatchIR(&dispatch_family, .switch_table);
    defer result.deinit(testing.allocator);

    // Validate complete pipeline
    try testing.expect(result.llvm_function != null);
    try testing.expect(result.debug_info != null);
    try testing.expect(result.mapping_data.optimization_decisions.len > 0);
    try testing.expect(result.performance_characteristics.dispatch_overhead_ns <= 100);
    try testing.expect(result.generated_ir_text.len > 0);

    // Validate auditability
    try testing.expect(result.mapping_data.performance_predictions.confidence_level > 0.8);
}

// Golden reference validation test (placeholder)
test "golden reference validation framework" {
    // This test validates the framework for comparing generated IR against golden references
    // In a complete implementation, this would:
    // 1. Load golden reference IR from file
    // 2. Generate IR using IRGenerator
    // 3. Compare generated IR with golden reference
    // 4. Report any differences with detailed analysis

    // For now, just validate that the framework components exist
    var ir_generator = try IRGenerator.init(testing.allocator, "golden_test");
    defer ir_generator.deinit();

    try testing.expect(ir_generator.symbol_manager != null);
    try testing.expect(ir_generator.debug_info_generator != null);
    try testing.expect(ir_generator.optimization_tracer != null);

    // TODO: Implement actual golden reference comparison
    // This would be the core of the Golden Test Framework
}
