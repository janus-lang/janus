// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! LIVE-FIRE VALIDATION ENGINE TEST
//!
//! This is the one true proof. No mocks. No simulation. No lies.
//! Real ASTDB. Real parser. Real validation engine. Real assertions.
//!
//! The ValidationEngine does not work until it is proven against reality.

const std = @import("std");
const testing = std.testing;

// Real components - no mocks, no lies
const AstDB = @import("../../compiler/astdb/core_astdb.zig").AstDB;
const ValidationEngine = @import("../../compiler/semantic/validation_engine.zig").ValidationEngine;
const SymbolTable = @import("../../compiler/semantic/symbol_table.zig").SymbolTable;
const TypeSystem = @import("../../compiler/semantic/type_system.zig").TypeSystem;
const ProfileManager = @import("../../compiler/semantic/profile_manager.zig").ProfileManager;
const JanusParser = @import("../../compiler/libjanus/janus_parser.zig").Parser;

test "ValidationEngine - Live Fire: Real source, real validation, real proof" {

    const allocator = testing.allocator;

    // Real Janus source code - no simulation
    const source =
        \\func main() {
        \\    let x: i32 = 42;
        \\    let y: i32 = 21;
        \\    let sum: i32 = x + y;
        \\    if (sum > 50) {
        \\        print("Sum is greater than 50");
        \\    }
        \\}
    ;


    // Initialize real ASTDB system
    var astdb = AstDB.init(allocator);
    defer astdb.deinit();

    // Add real compilation unit
    const unit_id = try astdb.addUnit("live_fire_test.jan", source);

    // Initialize real parser
    var parser = JanusParser.init(allocator);
    defer parser.deinit();

    // Parse real source into real snapshot
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();


    // Initialize real semantic components

    var symbol_table = SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var type_system = TypeSystem.init(allocator);
    defer type_system.deinit();

    var profile_manager = ProfileManager.init(allocator, .core);
    defer profile_manager.deinit();

    // Initialize real ValidationEngine
    var validation_engine = ValidationEngine.init(allocator, &symbol_table, &type_system, &profile_manager);
    defer validation_engine.deinit();

    // THE MOMENT OF TRUTH: Real validation against real snapshot
    const validation_result = try validation_engine.validate(snapshot);
    defer validation_result.deinit();

    // EMPIRICAL PROOF: Assert the truth

    // The validation should succeed for valid :min profile code
    try testing.expect(validation_result.is_valid);

    // Should have no errors for this simple, correct code
    try testing.expect(validation_result.errors.len == 0);

    // Should detect the variables we declared
    const main_scope = validation_result.symbol_table.getScope("main") orelse return error.MainScopeNotFound;

    const x_symbol = main_scope.lookup("x") orelse return error.VariableXNotFound;
    try testing.expect(x_symbol.symbol_type == .variable);

    const y_symbol = main_scope.lookup("y") orelse return error.VariableYNotFound;
    try testing.expect(y_symbol.symbol_type == .variable);

    const sum_symbol = main_scope.lookup("sum") orelse return error.VariableSumNotFound;
    try testing.expect(sum_symbol.symbol_type == .variable);

    // Should validate types correctly
    try testing.expect(x_symbol.type_id == type_system.getBuiltinType(.i32));
    try testing.expect(y_symbol.type_id == type_system.getBuiltinType(.i32));
    try testing.expect(sum_symbol.type_id == type_system.getBuiltinType(.i32));

    // Should validate the arithmetic expression
    const arithmetic_nodes = validation_result.getNodesOfKind(.binary_expr);
    try testing.expect(arithmetic_nodes.len > 0);

    // Should validate the if statement
    const if_nodes = validation_result.getNodesOfKind(.if_stmt);
    try testing.expect(if_nodes.len > 0);

}

test "ValidationEngine - Live Fire: Invalid code should fail validation" {

    const allocator = testing.allocator;

    // Real invalid Janus source - should fail validation
    const invalid_source =
        \\func main() {
        \\    let x: i32 = "not a number";  // Type mismatch
        \\    let y: i32 = undefined_var;   // Undefined variable
        \\    print(z);                     // Undefined variable
        \\}
    ;


    // Initialize real components
    var astdb = AstDB.init(allocator);
    defer astdb.deinit();

    const unit_id = try astdb.addUnit("invalid_test.jan", invalid_source);
    _ = unit_id;

    var parser = JanusParser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(invalid_source);
    defer snapshot.deinit();

    var symbol_table = SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var type_system = TypeSystem.init(allocator);
    defer type_system.deinit();

    var profile_manager = ProfileManager.init(allocator, .core);
    defer profile_manager.deinit();

    var validation_engine = ValidationEngine.init(allocator, &symbol_table, &type_system, &profile_manager);
    defer validation_engine.deinit();

    // Validate invalid code
    const validation_result = try validation_engine.validate(snapshot);
    defer validation_result.deinit();

    // EMPIRICAL PROOF: Invalid code should fail
    try testing.expect(!validation_result.is_valid);

    // Should have errors
    try testing.expect(validation_result.errors.len > 0);

    // Print the errors for verification
    for (validation_result.errors, 0..) |error_info, i| {
    }

}

test "ValidationEngine - Live Fire: Profile boundary enforcement" {

    const allocator = testing.allocator;

    // Source that requires :go profile features
    const go_profile_source =
        \\func main() -> Result!void {
        \\    let result := try risky_operation();
        \\    match result {
        \\        .ok(value) => print("Success: {}", value),
        \\        .err(e) => print("Error: {}", e),
        \\    }
        \\}
    ;


    // Test with :min profile (should fail)
    {

        var astdb = AstDB.init(allocator);
        defer astdb.deinit();

        var parser = JanusParser.init(allocator);
        defer parser.deinit();

        const snapshot = try parser.parseWithSource(go_profile_source);
        defer snapshot.deinit();

        var symbol_table = SymbolTable.init(allocator);
        defer symbol_table.deinit();

        var type_system = TypeSystem.init(allocator);
        defer type_system.deinit();

        var profile_manager = ProfileManager.init(allocator, .core); // :min profile
        defer profile_manager.deinit();

        var validation_engine = ValidationEngine.init(allocator, &symbol_table, &type_system, &profile_manager);
        defer validation_engine.deinit();

        const validation_result = try validation_engine.validate(snapshot);
        defer validation_result.deinit();

        // Should fail due to profile restrictions
        try testing.expect(!validation_result.is_valid);

        // Should have profile violation errors
        var has_profile_error = false;
        for (validation_result.errors) |error_info| {
            if (error_info.kind == .profile_violation) {
                has_profile_error = true;
                break;
            }
        }
        try testing.expect(has_profile_error);
    }

    // Test with :go profile (should succeed)
    {

        var astdb = AstDB.init(allocator);
        defer astdb.deinit();

        var parser = JanusParser.init(allocator);
        defer parser.deinit();

        const snapshot = try parser.parseWithSource(go_profile_source);
        defer snapshot.deinit();

        var symbol_table = SymbolTable.init(allocator);
        defer symbol_table.deinit();

        var type_system = TypeSystem.init(allocator);
        defer type_system.deinit();

        var profile_manager = ProfileManager.init(allocator, .service); // :go profile
        defer profile_manager.deinit();

        var validation_engine = ValidationEngine.init(allocator, &symbol_table, &type_system, &profile_manager);
        defer validation_engine.deinit();

        const validation_result = try validation_engine.validate(snapshot);
        defer validation_result.deinit();

        // Should succeed with :go profile
        try testing.expect(validation_result.is_valid);
    }

}
