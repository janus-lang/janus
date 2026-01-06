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
    std.debug.print("\n🔥 LIVE-FIRE VALIDATION ENGINE TEST\n", .{});
    std.debug.print("===================================\n", .{});

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

    std.debug.print("📝 Source code:\n{s}\n\n", .{source});

    // Initialize real ASTDB system
    std.debug.print("🔧 Initializing real ASTDB system...\n", .{});
    var astdb = AstDB.init(allocator);
    defer astdb.deinit();

    // Add real compilation unit
    const unit_id = try astdb.addUnit("live_fire_test.jan", source);
    std.debug.print("✅ Added compilation unit: {}\n", .{unit_id});

    // Initialize real parser
    std.debug.print("🔧 Initializing real parser...\n", .{});
    var parser = JanusParser.init(allocator);
    defer parser.deinit();

    // Parse real source into real snapshot
    std.debug.print("🔧 Parsing real source...\n", .{});
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    std.debug.print("✅ Parsed {} nodes\n", .{snapshot.nodes.len});

    // Initialize real semantic components
    std.debug.print("🔧 Initializing real semantic components...\n", .{});

    var symbol_table = SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var type_system = TypeSystem.init(allocator);
    defer type_system.deinit();

    var profile_manager = ProfileManager.init(allocator, .core);
    defer profile_manager.deinit();

    // Initialize real ValidationEngine
    std.debug.print("🔧 Initializing real ValidationEngine...\n", .{});
    var validation_engine = ValidationEngine.init(allocator, &symbol_table, &type_system, &profile_manager);
    defer validation_engine.deinit();

    // THE MOMENT OF TRUTH: Real validation against real snapshot
    std.debug.print("🔥 EXECUTING LIVE-FIRE VALIDATION...\n", .{});
    const validation_result = try validation_engine.validate(snapshot);
    defer validation_result.deinit();

    // EMPIRICAL PROOF: Assert the truth
    std.debug.print("🔍 Validating results...\n", .{});

    // The validation should succeed for valid :min profile code
    try testing.expect(validation_result.is_valid);
    std.debug.print("✅ Validation result: VALID\n", .{});

    // Should have no errors for this simple, correct code
    try testing.expect(validation_result.errors.len == 0);
    std.debug.print("✅ Error count: {} (expected: 0)\n", .{validation_result.errors.len});

    // Should detect the variables we declared
    const main_scope = validation_result.symbol_table.getScope("main") orelse return error.MainScopeNotFound;

    const x_symbol = main_scope.lookup("x") orelse return error.VariableXNotFound;
    try testing.expect(x_symbol.symbol_type == .variable);
    std.debug.print("✅ Variable 'x' found and validated\n", .{});

    const y_symbol = main_scope.lookup("y") orelse return error.VariableYNotFound;
    try testing.expect(y_symbol.symbol_type == .variable);
    std.debug.print("✅ Variable 'y' found and validated\n", .{});

    const sum_symbol = main_scope.lookup("sum") orelse return error.VariableSumNotFound;
    try testing.expect(sum_symbol.symbol_type == .variable);
    std.debug.print("✅ Variable 'sum' found and validated\n", .{});

    // Should validate types correctly
    try testing.expect(x_symbol.type_id == type_system.getBuiltinType(.i32));
    try testing.expect(y_symbol.type_id == type_system.getBuiltinType(.i32));
    try testing.expect(sum_symbol.type_id == type_system.getBuiltinType(.i32));
    std.debug.print("✅ All variable types validated as i32\n", .{});

    // Should validate the arithmetic expression
    const arithmetic_nodes = validation_result.getNodesOfKind(.binary_expr);
    try testing.expect(arithmetic_nodes.len > 0);
    std.debug.print("✅ Arithmetic expression validated\n", .{});

    // Should validate the if statement
    const if_nodes = validation_result.getNodesOfKind(.if_stmt);
    try testing.expect(if_nodes.len > 0);
    std.debug.print("✅ If statement validated\n", .{});

    std.debug.print("\n🎉 LIVE-FIRE TEST COMPLETE: ValidationEngine PROVEN!\n", .{});
    std.debug.print("🎉 Real source → Real parser → Real validation → Real proof\n", .{});
    std.debug.print("🎉 The ValidationEngine works against reality!\n\n", .{});
}

test "ValidationEngine - Live Fire: Invalid code should fail validation" {
    std.debug.print("\n🔥 LIVE-FIRE NEGATIVE TEST: Invalid code\n", .{});
    std.debug.print("========================================\n", .{});

    const allocator = testing.allocator;

    // Real invalid Janus source - should fail validation
    const invalid_source =
        \\func main() {
        \\    let x: i32 = "not a number";  // Type mismatch
        \\    let y: i32 = undefined_var;   // Undefined variable
        \\    print(z);                     // Undefined variable
        \\}
    ;

    std.debug.print("📝 Invalid source code:\n{s}\n\n", .{invalid_source});

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
    std.debug.print("🔥 VALIDATING INVALID CODE...\n", .{});
    const validation_result = try validation_engine.validate(snapshot);
    defer validation_result.deinit();

    // EMPIRICAL PROOF: Invalid code should fail
    try testing.expect(!validation_result.is_valid);
    std.debug.print("✅ Validation result: INVALID (as expected)\n", .{});

    // Should have errors
    try testing.expect(validation_result.errors.len > 0);
    std.debug.print("✅ Error count: {} (expected: > 0)\n", .{validation_result.errors.len});

    // Print the errors for verification
    for (validation_result.errors, 0..) |error_info, i| {
        std.debug.print("  Error {}: {} - {s}\n", .{ i + 1, error_info.kind, error_info.message });
    }

    std.debug.print("\n🎉 NEGATIVE TEST COMPLETE: ValidationEngine correctly rejects invalid code!\n\n", .{});
}

test "ValidationEngine - Live Fire: Profile boundary enforcement" {
    std.debug.print("\n🔥 LIVE-FIRE PROFILE TEST: Profile boundary enforcement\n", .{});
    std.debug.print("====================================================\n", .{});

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

    std.debug.print("📝 Go-profile source code:\n{s}\n\n", .{go_profile_source});

    // Test with :min profile (should fail)
    {
        std.debug.print("🔧 Testing with :min profile (should fail)...\n", .{});

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
        std.debug.print("✅ :min profile correctly rejected :go features\n", .{});

        // Should have profile violation errors
        var has_profile_error = false;
        for (validation_result.errors) |error_info| {
            if (error_info.kind == .profile_violation) {
                has_profile_error = true;
                break;
            }
        }
        try testing.expect(has_profile_error);
        std.debug.print("✅ Profile violation error detected\n", .{});
    }

    // Test with :go profile (should succeed)
    {
        std.debug.print("🔧 Testing with :go profile (should succeed)...\n", .{});

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
        std.debug.print("✅ :go profile correctly accepted :go features\n", .{});
    }

    std.debug.print("\n🎉 PROFILE TEST COMPLETE: Profile boundaries enforced!\n\n", .{});
}
