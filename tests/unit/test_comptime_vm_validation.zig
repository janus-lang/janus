// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;

// 🔧 COMPTIME VM VALIDATION
// Validates that ComptimeVM integrates correctly with the hardened ASTDB system

test "ComptimeVM Integration Validation" {

    const allocator = std.testing.allocator;
    const astdb = @import("compiler/libjanus/astdb.zig");
    const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
    const contracts = @import("compiler/libjanus/integration_contracts.zig");

    // Test 1: Basic ComptimeVM Initialization
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        const stats = comptime_vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, 0), stats.total_evaluations);
        try testing.expectEqual(@as(u32, 0), stats.cached_results);

    }

    // Test 2: Contract-Based Evaluation
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Create a test input contract
        var dependencies = std.ArrayList(astdb.NodeId){};
        defer dependencies.deinit();

        const pi_name = try astdb_system.str_interner.get("PI");
        const input_contract = contracts.ComptimeVMInputContract{
            .decl_id = @enumFromInt(1),
            .expression_name = pi_name,
            .expression_node = @enumFromInt(1),
            .expression_type = .const_declaration,
            .dependencies = dependencies.items,
            .source_span = astdb.Span{
                .start_byte = 0,
                .end_byte = 10,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 11,
            },
        };

        // Validate input contract
        try testing.expect(contracts.ContractValidation.validateComptimeVMInput(&input_contract));

        // Evaluate expression
        const output_contract = try comptime_vm.evaluateExpression(&input_contract);

        // Validate output contract
        try testing.expect(contracts.ContractValidation.validateComptimeVMOutput(&output_contract));
        try testing.expect(output_contract.success);
        try testing.expect(output_contract.result_value != null);

    }

    // Test 3: Constant Value Storage and Retrieval
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Store multiple constants
        const constants = [_][]const u8{ "PI", "BUFFER_SIZE", "MAX_CONNECTIONS" };
        var stored_ids: [3]astdb.StrId = undefined;

        for (constants, 0..) |constant_name, i| {
            const name_id = try astdb_system.str_interner.get(constant_name);
            stored_ids[i] = name_id;

            var dependencies = std.ArrayList(astdb.NodeId){};
            defer dependencies.deinit();

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = @enumFromInt(@as(u32, @intCast(i + 1))),
                .expression_name = name_id,
                .expression_node = @enumFromInt(@as(u32, @intCast(i + 1))),
                .expression_type = .const_declaration,
                .dependencies = dependencies.items,
                .source_span = astdb.Span{
                    .start_byte = 0,
                    .end_byte = 10,
                    .start_line = 1,
                    .start_col = 1,
                    .end_line = 1,
                    .end_col = 11,
                },
            };

            _ = try comptime_vm.evaluateExpression(&input_contract);
        }

        // Verify all constants are stored
        for (stored_ids) |name_id| {
            const result = comptime_vm.getConstantValue(name_id);
            try testing.expect(result != null);
        }

        const stats = comptime_vm.getEvaluationStats();
        try testing.expectEqual(@as(u32, 3), stats.total_evaluations);
        try testing.expectEqual(@as(u32, 3), stats.cached_results);

    }

    // Test 4: Memory Management Validation
    {
        for (0..10) |cycle| {
            var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
            defer astdb_system.deinit();

            var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
            defer comptime_vm.deinit();

            // Create many evaluations to test memory management
            var buffer: [64]u8 = undefined;
            for (0..20) |i| {
                const constant_name = std.fmt.bufPrint(&buffer, "CONST_{d}_{d}", .{ cycle, i }) catch unreachable;
                const name_id = try astdb_system.str_interner.get(constant_name);

                var dependencies = std.ArrayList(astdb.NodeId){};
                defer dependencies.deinit();

                const input_contract = contracts.ComptimeVMInputContract{
                    .decl_id = @enumFromInt(@as(u32, @intCast(i + 1))),
                    .expression_name = name_id,
                    .expression_node = @enumFromInt(@as(u32, @intCast(i + 1))),
                    .expression_type = .const_declaration,
                    .dependencies = dependencies.items,
                    .source_span = astdb.Span{
                        .start_byte = 0,
                        .end_byte = 10,
                        .start_line = 1,
                        .start_col = 1,
                        .end_line = 1,
                        .end_col = 11,
                    },
                };

                _ = try comptime_vm.evaluateExpression(&input_contract);
            }

            if (cycle % 3 == 0) {
            }
        }
    }

    // Test 5: Integration with String Interner
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Test that ComptimeVM properly uses string interner
        const test_strings = [_][]const u8{ "hello", "world", "test", "constant" };
        var string_ids: [4]astdb.StrId = undefined;

        // Intern strings through ASTDB
        for (test_strings, 0..) |str, i| {
            string_ids[i] = try astdb_system.str_interner.get(str);
        }

        // Use strings in ComptimeVM evaluations
        for (string_ids) |str_id| {
            var dependencies = std.ArrayList(astdb.NodeId){};
            defer dependencies.deinit();

            const input_contract = contracts.ComptimeVMInputContract{
                .decl_id = @enumFromInt(1),
                .expression_name = str_id,
                .expression_node = @enumFromInt(1),
                .expression_type = .const_declaration,
                .dependencies = dependencies.items,
                .source_span = astdb.Span{
                    .start_byte = 0,
                    .end_byte = 10,
                    .start_line = 1,
                    .start_col = 1,
                    .end_line = 1,
                    .end_col = 11,
                },
            };

            const output = try comptime_vm.evaluateExpression(&input_contract);
            try testing.expect(output.success);
        }

    }

    // Test 6: Error Handling Validation
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        // Create an invalid input contract (empty dependencies slice but large length)
        const invalid_dependencies = [_]astdb.NodeId{};
        var large_dependencies = std.ArrayList(astdb.NodeId){};
        defer large_dependencies.deinit();

        // Add too many dependencies to trigger validation failure
        for (0..100) |i| {
            try large_dependencies.append(@enumFromInt(@as(u32, @intCast(i))));
        }

        const invalid_contract = contracts.ComptimeVMInputContract{
            .decl_id = @enumFromInt(1),
            .expression_name = try astdb_system.str_interner.get("invalid"),
            .expression_node = @enumFromInt(1),
            .expression_type = .const_declaration,
            .dependencies = large_dependencies.items,
            .source_span = astdb.Span{
                .start_byte = 0,
                .end_byte = 10,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 11,
            },
        };

        // This should fail validation
        try testing.expect(!contracts.ContractValidation.validateComptimeVMInput(&invalid_contract));

        // Evaluation should handle invalid input gracefully
        const output = try comptime_vm.evaluateExpression(&invalid_contract);
        try testing.expect(!output.success);
        try testing.expect(output.evaluation_errors.len > 0);

    }

}

test "ComptimeVM Performance Validation" {

    const allocator = std.testing.allocator;
    const astdb = @import("compiler/libjanus/astdb.zig");
    const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
    const contracts = @import("compiler/libjanus/integration_contracts.zig");

    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();

    const start_time = compat_time.nanoTimestamp();

    // Perform 1000 evaluations
    var buffer: [64]u8 = undefined;
    for (0..1000) |i| {
        const constant_name = std.fmt.bufPrint(&buffer, "PERF_CONST_{d}", .{i}) catch unreachable;
        const name_id = try astdb_system.str_interner.get(constant_name);

        var dependencies = std.ArrayList(astdb.NodeId){};
        defer dependencies.deinit();

        const input_contract = contracts.ComptimeVMInputContract{
            .decl_id = @enumFromInt(@as(u32, @intCast(i + 1))),
            .expression_name = name_id,
            .expression_node = @enumFromInt(@as(u32, @intCast(i + 1))),
            .expression_type = .const_declaration,
            .dependencies = dependencies.items,
            .source_span = astdb.Span{
                .start_byte = 0,
                .end_byte = 10,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 11,
            },
        };

        const output = try comptime_vm.evaluateExpression(&input_contract);
        try testing.expect(output.success);
    }

    const end_time = compat_time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    const stats = comptime_vm.getEvaluationStats();


    // Performance assertions
    try testing.expect(duration_ms < 1000.0); // Should complete in under 1 second
    try testing.expectEqual(@as(u32, 1000), stats.total_evaluations);
    try testing.expectEqual(@as(u32, 1000), stats.cached_results);

}
