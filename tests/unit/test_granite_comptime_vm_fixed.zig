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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Test 1: Basic initialization and cleanup
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        const stats = comptime_vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, 0), stats.total_evaluations);
        try testing.expectEqual(@as(u32, 0), stats.cached_constants);

    }

    // Test 2: Single evaluation cycle
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Create test constant
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

        const stored_value = comptime_vm.getConstantValue(const_name);
        try testing.expect(stored_value != null);

    }

    // Test 3: Multiple evaluation cycles (stress test)
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

            var dependencies: std.ArrayList(astdb.NodeId) = .empty;
            defer dependencies.deinit();

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = @enumFromInt(@as(u32, @intCast(i + 1))),
                .expression_name = const_name,
                .expression_node = @enumFromInt(@as(u32, @intCast(i + 1))),
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

    }

    // GRANITE-SOLID: Final memory leak check
    const leaked = gpa.deinit();
    if (leaked == .ok) {
    } else {
        try testing.expect(false);
    }
}

// Test ComptimeVM integration with existing test patterns
test "Granite-Solid ComptimeVM - Integration Compatibility" {

    const allocator = std.testing.allocator;

    // Test compatibility with existing integration patterns
    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();

    // Test the same pattern used in step2_integration_working.zig
    var dependencies: std.ArrayList(astdb.NodeId) = .empty;
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

}
