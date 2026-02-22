// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("compiler/libjanus/astdb.zig");
const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
const contracts = @import("compiler/libjanus/integration_contracts.zig");

// GRANITE-SOLID ComptimeVM Validation Test
// Comprehensive zero-leak validation using the same patterns as StringInterner
test "Granite-Solid ComptimeVM - Zero Leak Validation" {
    std.debug.print("\n🔧 GRANITE-SOLID COMPTIME VM VALIDATION\n", .{});
    std.debug.print("==========================================\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Test 1: Basic initialization and cleanup
    std.debug.print("📋 Test 1: Basic Initialization\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        const stats = comptime_vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, 0), stats.total_evaluations);
        try testing.expectEqual(@as(u32, 0), stats.cached_constants);

        std.debug.print("✅ Basic initialization works\n", .{});
    }

    // Test 2: Single evaluation cycle
    std.debug.print("📋 Test 2: Single Evaluation Cycle\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Create test constant
        const const_name = try astdb_system.str_interner.get("test_const");

        var dependencies: std.ArrayList(astdb.NodeId) = .empty;
        defer dependencies.deinit();

        const input_contract = contracts.ComptimeVMInputContract{
            .decl_id = @enumFromInt(1),
            .expression_name = const_name,
            .expression_node = @enumFromInt(1),
            .expression_node = @enumFromInt(1),
            .expression_type = .const_declaration,
            .dependencies = dependencies.items,
            .source_span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 },
        };

        const output = try comptime_vm.evaluateExpression(&input_contract);
        try testing.expect(output.success);

        const stored_value = comptime_vm.getConstantValue(const_name);
        try testing.expect(stored_value != null);

        std.debug.print("✅ Single evaluation cycle works\n", .{});
    }

    // Test 3: Multiple evaluation cycles (stress test)
    std.debug.print("📋 Test 3: Multiple Evaluation Stress Test\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Stress test with 100 evaluations
        for (0..100) |i| {
            const const_name_str = try std.fmt.allocPrint(allocator, "stress_const_{d}", .{i});
            defer allocator.free(const_name_str);

            const const_name = try astdb_system.str_interner.get(const_name_str);

            var dependencies = std.ArrayList(astdb.NodeId){};
            defer dependencies.deinit();

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = @enumFromInt(@as(u32, @intCast(i + 1))),
                .expression_name = const_name,
                .expression_node = @enumFromInt(1),
                .expression_type = .const_declaration,
                .dependencies = dependencies.items,
                .source_span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 },
            };

            const output = try comptime_vm.evaluateExpression(&input_contract);
            try testing.expect(output.success);
        }

        const stats = comptime_vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, 100), stats.total_evaluations);
        try testing.expectEqual(@as(u32, 100), stats.cached_constants);

        std.debug.print("✅ Stress test with 100 evaluations works\n", .{});
    }

    // Test 4: BRUTAL stress test - creation/destruction cycles
    std.debug.print("📋 Test 4: BRUTAL Stress Test - Creation/Destruction Cycles\n", .{});
    {
        // This mimics the pattern that exposed leaks in the original ComptimeVM
        for (0..50) |cycle| {
            var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
            defer astdb_system.deinit();

            var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
            defer comptime_vm.deinit();

            // Intensive evaluation within each cycle
            for (0..20) |i| {
                const const_name_str = try std.fmt.allocPrint(allocator, "brutal_{d}_{d}", .{ cycle, i });
                defer allocator.free(const_name_str);

                const const_name = try astdb_system.str_interner.get(const_name_str);

                var dependencies = std.ArrayList(astdb.NodeId){};
                defer dependencies.deinit();

                const input_contract = contracts.ComptimeVMInputContract{
                    .decl_id = @enumFromInt(@as(u32, @intCast(i + 1))),
                    .expression_name = const_name,
                    .expression_node = @enumFromInt(1),
                    .expression_type = .const_declaration,
                    .dependencies = dependencies.items,
                    .source_span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 },
                };

                const output = try comptime_vm.evaluateExpression(&input_contract);
                try testing.expect(output.success);
            }

            // Test cache clearing
            comptime_vm.clearCache();
            const stats_after_clear = comptime_vm.getEvaluationStats();
            try testing.expectEqual(@as(u32, 0), stats_after_clear.cached_constants);
        }

        std.debug.print("✅ BRUTAL stress test (50 cycles × 20 evaluations) works\n", .{});
    }

    // Test 5: Different expression types
    std.debug.print("📋 Test 5: Different Expression Types\n", .{});
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Test const declaration
        {
            const const_name = try astdb_system.str_interner.get("test_const");
            var dependencies = std.ArrayList(astdb.NodeId){};
            defer dependencies.deinit();

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = @enumFromInt(1),
                .expression_name = const_name,
                .expression_node = @enumFromInt(1),
                .expression_type = .const_declaration,
                .dependencies = dependencies.items,
                .source_span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 },
            };

            const output = try comptime_vm.evaluateExpression(&input_contract);
            try testing.expect(output.success);
            try testing.expect(output.should_cache);
        }

        // Test arithmetic expression
        {
            const expr_name = try astdb_system.str_interner.get("2 + 3");
            var dependencies = std.ArrayList(astdb.NodeId){};
            defer dependencies.deinit();

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = @enumFromInt(2),
                .expression_name = expr_name,
                .expression_node = @enumFromInt(1),
                .expression_type = .type_expression,
                .dependencies = dependencies.items,
                .source_span = astdb.Span{ .start_byte = 0, .end_byte = 5, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 6 },
            };

            const output = try comptime_vm.evaluateExpression(&input_contract);
            try testing.expect(output.success);
        }

        // Test function call
        {
            const func_name = try astdb_system.str_interner.get("std.meta.get_function");
            var dependencies = std.ArrayList(astdb.NodeId){};
            defer dependencies.deinit();

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = @enumFromInt(3),
                .expression_name = func_name,
                .expression_node = @enumFromInt(1),
                .expression_type = .comptime_function_call,
                .dependencies = dependencies.items,
                .source_span = astdb.Span{ .start_byte = 0, .end_byte = 20, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 21 },
            };

            const output = try comptime_vm.evaluateExpression(&input_contract);
            try testing.expect(output.success);
            try testing.expect(!output.should_cache); // Function calls not cached
        }

        std.debug.print("✅ Different expression types work\n", .{});
    }

    // GRANITE-SOLID: Final memory leak check
    const leaked = gpa.deinit();
    if (leaked == .ok) {
        std.debug.print("🎉 GRANITE-SOLID VALIDATION PASSED: ZERO MEMORY LEAKS\n", .{});
    } else {
        std.debug.print("❌ MEMORY LEAKS DETECTED\n", .{});
        try testing.expect(false);
    }
}

// Test ComptimeVM integration with existing test patterns
test "Granite-Solid ComptimeVM - Integration Compatibility" {
    std.debug.print("\n🔧 INTEGRATION COMPATIBILITY TEST\n", .{});
    std.debug.print("==================================\n", .{});

    const allocator = std.testing.allocator;

    // Test compatibility with existing integration patterns
    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();

    // Test the same pattern used in step2_integration_working.zig
    var dependencies = std.ArrayList(astdb.NodeId){};
    defer dependencies.deinit();
    try dependencies.append(@enumFromInt(1));

    const test_name = try astdb_system.str_interner.get("test_integration");

    const input_contract = contracts.ComptimeVMInputContract{
        .decl_id = @enumFromInt(1),
        .expression_name = test_name,
        .expression_node = @enumFromInt(1),
        .expression_type = .const_declaration,
        .dependencies = dependencies.items,
        .source_span = astdb.Span{ .start_byte = 0, .end_byte = 15, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 16 },
    };

    // Validate input contract
    const is_valid = contracts.ContractValidation.validateComptimeVMInput(&input_contract);
    try testing.expect(is_valid);

    // Evaluate expression
    const output = try comptime_vm.evaluateExpression(&input_contract);
    try testing.expect(output.success);

    // Validate output contract
    const is_valid_output = contracts.ContractValidation.validateComptimeVMOutput(&output);
    try testing.expect(is_valid_output);

    std.debug.print("✅ Integration compatibility maintained\n", .{});
}

// Performance comparison test
test "Granite-Solid ComptimeVM - Performance Validation" {
    std.debug.print("\n🔧 PERFORMANCE VALIDATION\n", .{});
    std.debug.print("=========================\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();

    // Measure performance of 1000 evaluations
    const start_time = std.time.nanoTimestamp();

    for (0..1000) |i| {
        const const_name_str = try std.fmt.allocPrint(allocator, "perf_const_{d}", .{i});
        defer allocator.free(const_name_str);

        const const_name = try astdb_system.str_interner.get(const_name_str);

        var dependencies: std.ArrayList(astdb.NodeId) = .empty;
        defer dependencies.deinit();

        const input_contract = contracts.ComptimeVMInputContract{
            .decl_id = @enumFromInt(@as(u32, @intCast(i + 1))),
            .expression_name = const_name,
            .expression_node = @enumFromInt(1),
            .expression_type = .const_declaration,
            .dependencies = dependencies.items,
            .source_span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 },
        };

        const output = try comptime_vm.evaluateExpression(&input_contract);
        try testing.expect(output.success);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    std.debug.print("✅ 1000 evaluations completed in {d:.2} ms\n", .{duration_ms});
    std.debug.print("✅ Average: {d:.4} ms per evaluation\n", .{duration_ms / 1000.0});

    // Verify final state
    const stats = comptime_vm.getEvaluationStats();
    try testing.expectEqual(@as(u32, 1000), stats.total_evaluations);
    try testing.expectEqual(@as(u32, 1000), stats.cached_constants);

    // GRANITE-SOLID: Check for memory leaks
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}
