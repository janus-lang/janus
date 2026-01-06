// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const comptime_vm = @import("comptime_vm.zig");
const granite_astdb = @import("libjanus/astdb.zig");
const contracts = @import("libjanus/integration_contracts.zig");

// GRANITE-SOLID COMPTIME VM INTEGRATION TEST
// Comprehensive validation of Comptime VM with granite-solid foundation
// Zero leaks, maximum stress, architectural integrity

test "Granite-Solid Comptime VM - Basic Integration" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        // Initialize granite-solid ASTDB system
        var astdb_system = try granite_astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        // Initialize granite-solid Comptime VM
        var vm = try comptime_vm.ComptimeVM.init(allocator, &astdb_system);
        defer vm.deinit();

        // Create a test snapshot
        var snapshot = try astdb_system.createSnapshot();
        defer snapshot.deinit();

        // Add test content to snapshot
        const const_name = try astdb_system.str_interner.get("TEST_CONST");
        const token_id = try snapshot.addToken(.kw_const, const_name, granite_astdb.Span{
            .start_byte = 0,
            .end_byte = 10,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 11,
        });

        const node_id = try snapshot.addNode(.var_decl, token_id, token_id, &[_]granite_astdb.NodeId{});
        const decl_id = try snapshot.addDecl(node_id, const_name, @enumFromInt(0), .constant);

        // Create comptime VM input contract
        const input_contract = contracts.ComptimeVMInputContract{
            .decl_id = decl_id,
            .expression_name = const_name,
            .expression_node = node_id,
            .expression_type = .const_declaration,
            .dependencies = &[_]granite_astdb.NodeId{},
            .source_span = granite_astdb.Span{
                .start_byte = 0,
                .end_byte = 10,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 11,
            },
        };

        // Evaluate comptime expression
        const output_contract = try vm.evaluateExpression(&input_contract);

        // Verify successful evaluation
        try testing.expect(output_contract.success);
        try testing.expect(output_contract.result_value != null);
        try testing.expect(output_contract.result_type != null);
        try testing.expect(output_contract.should_cache);
        try testing.expectEqual(@as(usize, 0), output_contract.evaluation_errors.len);

        // Verify VM statistics
        const stats = vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, 1), stats.total_evaluations);
        try testing.expectEqual(@as(u32, 1), stats.cached_constants);

        // Verify constant retrieval
        const retrieved_value = vm.getConstantValue(const_name);
        try testing.expect(retrieved_value != null);
        try testing.expectEqual(output_contract.result_value.?, retrieved_value.?);
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite-Solid Comptime VM - Multiple Expression Types" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        // Initialize granite-solid components
        var astdb_system = try granite_astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var vm = try comptime_vm.ComptimeVM.init(allocator, &astdb_system);
        defer vm.deinit();

        var snapshot = try astdb_system.createSnapshot();
        defer snapshot.deinit();

        // Test different expression types
        const expression_types = [_]contracts.ComptimeVMInputContract.ExpressionType{
            .const_declaration,
            .type_expression,
            .comptime_function_call,
            .compile_time_constant,
        };

        for (expression_types, 0..) |expr_type, i| {
            const expr_name = try std.fmt.allocPrint(allocator, "test_expr_{d}", .{i});
            defer allocator.free(expr_name);

            const expr_str_id = try astdb_system.str_interner.get(expr_name);

            const token_id = try snapshot.addToken(.identifier, expr_str_id, granite_astdb.Span{
                .start_byte = @as(u32, @intCast(i * 10)),
                .end_byte = @as(u32, @intCast(i * 10 + 5)),
                .start_line = @as(u32, @intCast(i + 1)),
                .start_col = 1,
                .end_line = @as(u32, @intCast(i + 1)),
                .end_col = 6,
            });

            const node_id = try snapshot.addNode(.identifier, token_id, token_id, &[_]granite_astdb.NodeId{});
            const decl_id = try snapshot.addDecl(node_id, expr_str_id, @enumFromInt(0), .constant);

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = decl_id,
                .expression_name = expr_str_id,
                .expression_node = node_id,
                .expression_type = expr_type,
                .dependencies = &[_]granite_astdb.NodeId{},
                .source_span = granite_astdb.Span{
                    .start_byte = @as(u32, @intCast(i * 10)),
                    .end_byte = @as(u32, @intCast(i * 10 + 5)),
                    .start_line = @as(u32, @intCast(i + 1)),
                    .start_col = 1,
                    .end_line = @as(u32, @intCast(i + 1)),
                    .end_col = 6,
                },
            };

            const output_contract = try vm.evaluateExpression(&input_contract);

            // All expression types should evaluate successfully
            try testing.expect(output_contract.success);
            try testing.expect(output_contract.result_value != null);
            try testing.expect(output_contract.result_type != null);
        }

        // Verify final statistics
        const stats = vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, 4), stats.total_evaluations);
        try testing.expect(stats.cached_constants > 0); // At least const_declaration should be cached
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite-Solid Comptime VM - Stress Test" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        // Initialize granite-solid components
        var astdb_system = try granite_astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var vm = try comptime_vm.ComptimeVM.init(allocator, &astdb_system);
        defer vm.deinit();

        var snapshot = try astdb_system.createSnapshot();
        defer snapshot.deinit();

        // Stress test with many evaluations
        const evaluation_count = 100;

        for (0..evaluation_count) |i| {
            const expr_name = try std.fmt.allocPrint(allocator, "stress_const_{d}", .{i});
            defer allocator.free(expr_name);

            const expr_str_id = try astdb_system.str_interner.get(expr_name);

            const token_id = try snapshot.addToken(.kw_const, expr_str_id, granite_astdb.Span{
                .start_byte = @as(u32, @intCast(i * 10)),
                .end_byte = @as(u32, @intCast(i * 10 + 5)),
                .start_line = @as(u32, @intCast(i / 10 + 1)),
                .start_col = @as(u32, @intCast(i % 10 + 1)),
                .end_line = @as(u32, @intCast(i / 10 + 1)),
                .end_col = @as(u32, @intCast(i % 10 + 6)),
            });

            const node_id = try snapshot.addNode(.var_decl, token_id, token_id, &[_]granite_astdb.NodeId{});
            const decl_id = try snapshot.addDecl(node_id, expr_str_id, @enumFromInt(0), .constant);

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = decl_id,
                .expression_name = expr_str_id,
                .expression_node = node_id,
                .expression_type = .const_declaration,
                .dependencies = &[_]granite_astdb.NodeId{},
                .source_span = granite_astdb.Span{
                    .start_byte = @as(u32, @intCast(i * 10)),
                    .end_byte = @as(u32, @intCast(i * 10 + 5)),
                    .start_line = @as(u32, @intCast(i / 10 + 1)),
                    .start_col = @as(u32, @intCast(i % 10 + 1)),
                    .end_line = @as(u32, @intCast(i / 10 + 1)),
                    .end_col = @as(u32, @intCast(i % 10 + 6)),
                },
            };

            const output_contract = try vm.evaluateExpression(&input_contract);

            // Verify successful evaluation
            try testing.expect(output_contract.success);
            try testing.expect(output_contract.result_value != null);
            try testing.expect(output_contract.result_type != null);
        }

        // Verify final statistics
        const stats = vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, evaluation_count), stats.total_evaluations);
        try testing.expectEqual(@as(u32, evaluation_count), stats.cached_constants);

        // Test cache clearing
        vm.clearCache();
        const cleared_stats = vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, evaluation_count), cleared_stats.total_evaluations); // Evaluation count persists
        try testing.expectEqual(@as(u32, 0), cleared_stats.cached_constants); // Cache cleared

        // Test reset
        vm.reset();
        const reset_stats = vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, 0), reset_stats.total_evaluations); // Everything reset
        try testing.expectEqual(@as(u32, 0), reset_stats.cached_constants);
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite-Solid Comptime VM - Error Handling" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        // Initialize granite-solid components
        var astdb_system = try granite_astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var vm = try comptime_vm.ComptimeVM.init(allocator, &astdb_system);
        defer vm.deinit();

        // Test with invalid input contract (too many dependencies)
        const invalid_dependencies = try allocator.alloc(granite_astdb.NodeId, 100); // Exceeds validation limit
        defer allocator.free(invalid_dependencies);

        for (invalid_dependencies, 0..) |*dep, i| {
            dep.* = @enumFromInt(@as(u32, @intCast(i)));
        }

        const expr_name = try astdb_system.str_interner.get("invalid_expr");

        const invalid_contract = contracts.ComptimeVMInputContract{
            .decl_id = @enumFromInt(0),
            .expression_name = expr_name,
            .expression_node = @enumFromInt(0),
            .expression_type = .const_declaration,
            .dependencies = invalid_dependencies,
            .source_span = granite_astdb.Span{
                .start_byte = 0,
                .end_byte = 5,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 6,
            },
        };

        const output_contract = try vm.evaluateExpression(&invalid_contract);

        // Should fail validation and return error
        try testing.expect(!output_contract.success);
        try testing.expect(output_contract.result_value == null);
        try testing.expect(output_contract.result_type == null);
        try testing.expect(!output_contract.should_cache);
        try testing.expectEqual(@as(usize, 1), output_contract.evaluation_errors.len);
        try testing.expectEqual(contracts.ComptimeVMOutputContract.EvaluationError.ErrorType.unsupported_operation, output_contract.evaluation_errors[0].error_type);
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}
