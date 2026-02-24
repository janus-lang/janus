// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// 🔧 COMPTIME VM MEMORY LEAK FIX VALIDATION
// Test the memory leak fixes applied to ComptimeVM

test "ComptimeVM Memory Leak Fix Validation" {

    const allocator = std.testing.allocator;
    const astdb = @import("compiler/libjanus/astdb.zig");
    const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
    const contracts = @import("compiler/libjanus/integration_contracts.zig");

    // Test 1: Basic functionality still works
    {
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
        defer comptime_vm.deinit();

        const test_name = try astdb_system.str_interner.get("TEST_CONSTANT");

        var dependencies: std.ArrayList(astdb.NodeId) = .empty;
        defer dependencies.deinit();

        const input_contract = contracts.ComptimeVMInputContract{
            .decl_id = @enumFromInt(1),
            .expression_name = test_name,
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

    // Test 2: Reduced Memory Pressure Test
    {
        // Use single ASTDB system for efficiency
        var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
        defer astdb_system.deinit();

        // Test fewer cycles with proper cleanup
        for (0..5) |cycle| {
            var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
            defer comptime_vm.deinit();

            // Fewer evaluations per cycle
            var buffer: [64]u8 = undefined;
            for (0..5) |i| {
                const constant_name = std.fmt.bufPrint(&buffer, "fix_test_{d}_{d}", .{ cycle, i }) catch unreachable;
                const name_id = try astdb_system.str_interner.get(constant_name);

                // Use arena for temporary allocations
                var temp_arena = std.heap.ArenaAllocator.init(allocator);
                defer temp_arena.deinit();

                var dependencies: std.ArrayList(astdb.NodeId) = .empty);

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

            if (cycle % 2 == 0) {
            }
        }

    }

}
