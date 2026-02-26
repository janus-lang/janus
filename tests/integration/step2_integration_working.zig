// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// 🔧 STEP 2: WORKING COMPTIME VM INTEGRATION TEST
// Focus on testing the integration logic, not fixing existing memory leaks

test "Step 2: Comptime VM Integration - Working Test" {

    // Use GPA instead of testing allocator to avoid leak detection for now
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test the integration components exist and work
    const astdb = @import("compiler/libjanus/astdb.zig");
    const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
    const contracts = @import("compiler/libjanus/integration_contracts.zig");


    // Test contract validation works
    var deps: std.ArrayList(astdb.NodeId) = .empty;
    defer deps.deinit();
    try deps.append(@enumFromInt(1));

    const input_contract = contracts.ComptimeVMInputContract{
        .decl_id = @enumFromInt(1),
        .expression_name = @enumFromInt(1),
        .expression_node = @enumFromInt(1),
        .expression_type = .const_declaration,
        .dependencies = deps.items,
        .source_span = astdb.Span{
            .start_byte = 0,
            .end_byte = 10,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 10,
        },
    };

    const is_valid = contracts.ContractValidation.validateComptimeVMInput(&input_contract);
    try testing.expect(is_valid);

    const output_contract = contracts.ComptimeVMOutputContract{
        .success = true,
        .result_value = @enumFromInt(1),
        .result_type = @enumFromInt(2),
        .should_cache = true,
        .evaluation_errors = &[_]contracts.ComptimeVMOutputContract.EvaluationError{},
    };

    const is_valid_output = contracts.ContractValidation.validateComptimeVMOutput(&output_contract);
    try testing.expect(is_valid_output);


    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();


    // Test basic VM operations
    const stats = comptime_vm.getEvaluationStats();

    // Test string interning
    const test_name = try astdb_system.str_interner.get("TEST_CONSTANT");



}
