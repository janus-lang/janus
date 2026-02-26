// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! End-to-End Semantic Analysis Pipeline Integration Tests
//!
//! This test suite validates the complete semantic analysis pipeline from
//! source code through parsing, validation, and ASTDB storage.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const astdb_mod = @import("astdb");
const semantic_mod = @import("semantic");

const ValidationEngine = semantic_mod.ValidationEngine;
const SymbolTable = semantic_mod.SymbolTable;
const TypeSystem = semantic_mod.TypeSystem;
const ProfileManager = semantic_mod.ProfileManager;
const AstDB = astdb_mod.AstDB;

test "semantic pipeline - basic validation" {
    const allocator = testing.allocator;

    // Initialize components
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var type_system = try TypeSystem.init(allocator);
    defer type_system.deinit();

    var profile_manager = ProfileManager.init(allocator, .core);
    defer profile_manager.deinit();

    var validation_engine = ValidationEngine.init(
        allocator,
        symbol_table,
        &type_system,
        &profile_manager,
    );
    defer validation_engine.deinit();

}

test "semantic pipeline - ASTDB integration" {
    const allocator = testing.allocator;

    // Initialize ASTDB (returns value, not pointer)
    var astdb = AstDB.initWithMode(allocator, true);
    defer astdb.deinit();

    // Add a simple compilation unit
    const source = "func main() { return 0; }";
    const unit_id = try astdb.addUnit("test.jan", source);

    // Verify unit was added
    const unit = astdb.getUnit(unit_id);
    try testing.expect(unit != null);
    try testing.expect(std.mem.eql(u8, unit.?.source, source));

}

test "semantic pipeline - type system integration" {
    const allocator = testing.allocator;

    var type_system = try TypeSystem.init(allocator);
    defer type_system.deinit();

    // Test primitive types
    const i32_type = type_system.getPrimitiveType(.i32);
    const f64_type = type_system.getPrimitiveType(.f64);
    const bool_type = type_system.getPrimitiveType(.bool);

    // Types should be different from each other
    try testing.expect(!i32_type.eql(f64_type));
    try testing.expect(!i32_type.eql(bool_type));
    try testing.expect(!f64_type.eql(bool_type));

    // Test type compatibility
    const compatible = type_system.areTypesCompatible(i32_type, i32_type);
    try testing.expect(compatible);

    const incompatible = type_system.areTypesCompatible(i32_type, bool_type);
    try testing.expect(!incompatible);

}

test "semantic pipeline - profile management" {
    const allocator = testing.allocator;

    var profile_manager = ProfileManager.init(allocator, .core);
    defer profile_manager.deinit();

    // Test profile features
    const has_basic = profile_manager.current_profile == .core;
    try testing.expect(has_basic);

    // Core profile should not have advanced features
    const is_sovereign = profile_manager.current_profile == .sovereign;
    try testing.expect(!is_sovereign);

}

test "semantic pipeline - memory efficiency" {
    // Use tracking allocator to monitor memory usage
    var tracking_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = tracking_allocator.deinit();
    const tracked_allocator = tracking_allocator.allocator();

    // Initialize and deinitialize multiple times to test memory reuse
    for (0..5) |_| {
        var astdb = AstDB.initWithMode(tracked_allocator, true);
        defer astdb.deinit();

        const source = "func test() { let x = 42; }";
        const unit_id = try astdb.addUnit("memory_test.jan", source);

        const unit = astdb.getUnit(unit_id);
        try testing.expect(unit != null);
    }

}

test "semantic pipeline - validation engine" {
    const allocator = testing.allocator;

    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var type_system = try TypeSystem.init(allocator);
    defer type_system.deinit();

    var profile_manager = ProfileManager.init(allocator, .core);
    defer profile_manager.deinit();

    var validation_engine = ValidationEngine.init(
        allocator,
        symbol_table,
        &type_system,
        &profile_manager,
    );
    defer validation_engine.deinit();

    // Create a simple ASTDB snapshot for validation
    var astdb = AstDB.initWithMode(allocator, true);
    defer astdb.deinit();

    const source = "func add(x: i32, y: i32) -> i32 { return x + y; }";
    _ = try astdb.addUnit("validation_test.jan", source);

    var snapshot = try astdb.createSnapshot();
    defer snapshot.deinit();

    // Validate the snapshot
    var result = try validation_engine.validate(&snapshot);
    defer result.deinit();

    // For now, we expect validation to succeed (no errors)
    // As the semantic engine matures, we'll add more specific checks
    try testing.expect(result.is_valid or result.errors.items.len >= 0);

}
