// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const EnhancedASTDBParser = @import("compiler/enhanced_astdb_parser.zig").EnhancedASTDBParser;
const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
const astdb = @import("compiler/libjanus/astdb.zig");
const ASTDBSystem = astdb.ASTDBSystem;
const contracts = @import("compiler/libjanus/integration_contracts.zig");

// 🔒 STEP 2: COMPTIME VM INTEGRATION CONTRACT - SIMPLE TEST
// Focus on const declarations only to validate the integration

test "Step 2: Comptime VM Integration - Simple Constants Only" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ASTDB system
    var astdb_system = try ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    // Initialize Comptime VM
    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();


    // Simple test program with only const declarations (no complex expressions)
    const test_source =
        \\const PI = 3.14159
        \\const BUFFER_SIZE = 1024
        \\const MESSAGE = "Hello"
    ;


    // Initialize parser with Comptime VM integration
    var parser = try EnhancedASTDBParser.initWithComptimeVM(allocator, test_source, &astdb_system, &comptime_vm);
    defer parser.deinit();

    // Parse the program - this should trigger comptime VM integration
    const root_node = try parser.parseProgram();
    const snapshot = parser.getSnapshot();


    // CONTRACT VALIDATION: Verify comptime expressions were registered

    // Test 1: Verify PI constant registration
    const pi_name = try astdb_system.str_interner.get("PI");
    const pi_result = comptime_vm.getConstantValue(pi_name);

    if (pi_result) |_| {
    } else {
        return error.IntegrationFailed;
    }

    // Test 2: Verify BUFFER_SIZE constant registration
    const buffer_size_name = try astdb_system.str_interner.get("BUFFER_SIZE");
    const buffer_size_result = comptime_vm.getConstantValue(buffer_size_name);

    if (buffer_size_result) |_| {
    } else {
        return error.IntegrationFailed;
    }

    // Test 3: Verify MESSAGE constant registration
    const message_name = try astdb_system.str_interner.get("MESSAGE");
    const message_result = comptime_vm.getConstantValue(message_name);

    if (message_result) |_| {
    } else {
        return error.IntegrationFailed;
    }

    // Test 4: Verify evaluation statistics
    const stats = comptime_vm.getEvaluationStats();

    // Should have evaluated at least 3 constants
    try testing.expect(stats.total_evaluations >= 3);
    try testing.expect(stats.cached_results >= 3);


    _ = root_node; // Suppress unused variable warning
}

// Test contract structure validation
test "Step 2: Comptime VM Contract Structure Validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    // Test ComptimeVMInputContract validation
    var dependencies = std.ArrayList(astdb.NodeId){};
    defer dependencies.deinit();
    try dependencies.append(@enumFromInt(1));

    const input_contract = contracts.ComptimeVMInputContract{
        .decl_id = @enumFromInt(1),
        .expression_name = @enumFromInt(1),
        .expression_node = @enumFromInt(1),
        .expression_type = .const_declaration,
        .dependencies = dependencies.items,
        .source_span = astdb.Span{
            .start_byte = 0,
            .end_byte = 10,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 10,
        },
    };

    try testing.expect(contracts.ContractValidation.validateComptimeVMInput(&input_contract));

    // Test ComptimeVMOutputContract validation
    const output_contract = contracts.ComptimeVMOutputContract{
        .success = true,
        .result_value = @enumFromInt(1),
        .result_type = @enumFromInt(2),
        .should_cache = true,
        .evaluation_errors = &[_]contracts.ComptimeVMOutputContract.EvaluationError{},
    };

    try testing.expect(contracts.ContractValidation.validateComptimeVMOutput(&output_contract));

}
