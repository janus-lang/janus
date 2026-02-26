// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("compiler/libjanus/astdb.zig");
const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
const contracts = @import("compiler/libjanus/integration_contracts.zig");

// FINAL GRANITE-SOLID INFRASTRUCTURE VALIDATION
// This test validates our complete revolutionary architecture
test "Granite-Solid Infrastructure - Complete Zero-Leak Validation" {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Test 1: ASTDB System with Granite-Solid String Interner
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        // Test granite-solid string interner
        const hello_id = try astdb_system.str_interner.get("hello");
        const world_id = try astdb_system.str_interner.get("world");
        const hello_id2 = try astdb_system.str_interner.get("hello");

        // Verify deduplication
        try testing.expectEqual(hello_id, hello_id2);
        try testing.expect(!std.meta.eql(hello_id, world_id));

        // Verify retrieval
        try testing.expectEqualStrings("hello", astdb_system.str_interner.str(hello_id));
        try testing.expectEqualStrings("world", astdb_system.str_interner.str(world_id));

    }

    // Test 2: ComptimeVM with Granite-Solid Architecture
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Test const declaration evaluation
        const const_name = try astdb_system.str_interner.get("test_const");

        var dependencies: std.ArrayList(astdb.NodeId) = .empty;
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

    // Test 3: Integrated System Stress Test
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Stress test with 50 evaluations
        for (0..50) |i| {
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
        try testing.expectEqual(@as(u32, 50), stats.total_evaluations);
        try testing.expectEqual(@as(u32, 50), stats.cached_constants);

    }

    // FINAL VALIDATION: Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .ok) {
    } else {
        try testing.expect(false);
    }
}

// Test individual components for detailed analysis
test "Granite-Solid Components - Individual Validation" {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Test granite-solid string interner in isolation
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        // Test multiple string operations
        for (0..100) |i| {
            const test_str = try std.fmt.allocPrint(allocator, "test_string_{d}", .{i});
            defer allocator.free(test_str);

            const str_id = try astdb_system.str_interner.get(test_str);
            const retrieved = astdb_system.str_interner.str(str_id);
            try testing.expectEqualStrings(test_str, retrieved);
        }

    }

    // Test ComptimeVM in isolation
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Test different expression types
        const test_cases = [_]contracts.ComptimeVMInputContract.ExpressionType{
            .const_declaration,
            .type_expression,
            .comptime_function_call,
            .compile_time_constant,
        };

        for (test_cases, 0..) |expr_type, i| {
            const expr_name = try astdb_system.str_interner.get("test_expr");

            var dependencies: std.ArrayList(astdb.NodeId) = .empty;
            defer dependencies.deinit();

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = @enumFromInt(@as(u32, @intCast(i + 1))),
                .expression_name = expr_name,
                .expression_node = @enumFromInt(@as(u32, @intCast(i + 1))),
                .expression_type = expr_type,
                .dependencies = dependencies.items,
                .source_span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 },
            };

            const output = try comptime_vm.evaluateExpression(&input_contract);
            try testing.expect(output.success);
        }

    }

    // Final component validation
    const leaked = gpa.deinit();
    if (leaked == .ok) {
    } else {
        try testing.expect(false);
    }
}
