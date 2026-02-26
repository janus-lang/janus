// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const EnhancedASTDBParser = @import("compiler/enhanced_astdb_parser.zig").EnhancedASTDBParser;
const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
const astdb = @import("compiler/libjanus/astdb.zig");
const ASTDBSystem = astdb.ASTDBSystem;
const contracts = @import("compiler/libjanus/integration_contracts.zig");

// Golden Test: Comptime VM Integration Contract
// This test validates that the parser correctly integrates with the Comptime VM
// using the defined ComptimeVMInputContract.
//
// EXPECTED BEHAVIOR:
// 1. Parse a program with comptime expressions
// 2. Extract comptime expression information and create ComptimeVMInputContract
// 3. Register expressions with the Comptime VM for evaluation
// 4. Validate that const declarations are evaluated at compile time
// 5. Validate that comptime function calls are properly handled
//
// THIS TEST MUST FAIL INITIALLY because the integration does not exist yet.
test "Comptime VM Integration Contract - North Star MVP" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var astdb_system = try ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();


    // North Star MVP program with comptime expressions
    const demo_jan_source =
        \\const PI = 3.14159
        \\const BUFFER_SIZE = 1024
        \\
        \\func compute_area(radius: f64) -> f64 {
        \\    return PI * radius * radius
        \\}
        \\
        \\func main() {
        \\    const area = compute_area(5.0)
        \\    return
        \\}
    ;


    var parser = try EnhancedASTDBParser.initWithComptimeVM(allocator, demo_jan_source, &astdb_system, &comptime_vm);
    defer parser.deinit();

    const root_node = try parser.parseProgram();
    const snapshot = parser.getSnapshot();


    // INTEGRATION CONTRACT TEST: Extract comptime expressions and register with Comptime VM

    // This is where the integration should happen but doesn't exist yet
    // The parser should extract comptime expressions and create ComptimeVMInputContract
    // then register expressions with the Comptime VM for evaluation

    // TEST 1: Verify PI constant is registered and evaluated
    const pi_name = try astdb_system.str_interner.get("PI");
    const pi_result = comptime_vm.getConstantValue(pi_name);

    if (pi_result) |result| {
        // Integration working - constant registered
        try testing.expect(result != null);
    } else {
        try testing.expect(false); // Integration should work now
    }

    // TEST 2: Verify BUFFER_SIZE constant is registered and evaluated
    const buffer_size_name = try astdb_system.str_interner.get("BUFFER_SIZE");
    const buffer_size_result = comptime_vm.getConstantValue(buffer_size_name);

    if (buffer_size_result) |result| {
        // Should be evaluated to "1024"
        const expected_size = try astdb_system.str_interner.get("1024");
        try testing.expect(std.meta.eql(result, expected_size));
    } else {
        // This will fail because integration doesn't exist yet
        try testing.expect(false); // EXPECTED FAILURE
    }

    // TEST 3: Verify comptime evaluation capabilities
    const evaluation_stats = comptime_vm.getEvaluationStats();

    try testing.expect(evaluation_stats.total_evaluations >= 2); // Should have evaluated PI and BUFFER_SIZE


    _ = root_node; // Suppress unused variable warning
}

// Test the Comptime VM integration contract structures themselves
test "Comptime VM Integration Contract Structures" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    // Test creating a valid ComptimeVMInputContract
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

    // Validate the contract
    try testing.expect(contracts.ContractValidation.validateComptimeVMInput(&input_contract));

    // Test creating a valid ComptimeVMOutputContract
    const output_contract = contracts.ComptimeVMOutputContract{
        .success = true,
        .result_value = @enumFromInt(1),
        .result_type = @enumFromInt(2),
        .should_cache = true,
        .evaluation_errors = &[_]contracts.ComptimeVMOutputContract.EvaluationError{},
    };

    // Validate the contract
    try testing.expect(contracts.ContractValidation.validateComptimeVMOutput(&output_contract));

}
