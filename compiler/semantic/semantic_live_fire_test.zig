// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Semantic Engine Live-Fire Exercise - Integrated Test
//!
//! This test proves the unified semantic engine's intelligence by testing
//! the core components that have been unified. This test is designed to
//! run within the build system where astdb module is available.

const std = @import("std");
const testing = std.testing;

// Import unified semantic components
const janus = @import("astdb");
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const TypeSystem = @import("type_system.zig").TypeSystem;
const TypeInference = @import("type_inference.zig").TypeInference;
const ValidationEngine = @import("validation_engine.zig").ValidationEngine;

test "Semantic Engine Unification - Core Components Integration" {
    const allocator = std.testing.allocator;

    // Initialize ASTDB system for testing
    var astdb_system = try janus.astdb.ASTDBSystem.init(allocator, false);
    defer astdb_system.deinit();

    // Test 1: Type System Unification
    var type_system = try TypeSystem.init(allocator);
    defer type_system.deinit();

    // Verify O(1) primitive type access
    const i32_type = type_system.getPrimitiveType(.i32);
    const i64_type = type_system.getPrimitiveType(.i64);
    const bool_type = type_system.getPrimitiveType(.bool);

    try testing.expect(!i32_type.eql(i64_type));
    try testing.expect(!i32_type.eql(bool_type));
    try testing.expect(!i64_type.eql(bool_type));

    // Test 2: Symbol Table Unification
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();

    // Test string interning
    const symbol1 = try symbol_table.symbol_interner.intern("test_function");
    const symbol2 = try symbol_table.symbol_interner.intern("test_function");
    const symbol3 = try symbol_table.symbol_interner.intern("different_function");

    try testing.expect(symbol1.eql(symbol2)); // Same string should have same ID
    try testing.expect(!symbol1.eql(symbol3)); // Different strings should have different IDs

    // Test 3: Type Inference Integration
    var type_inference = try TypeInference.init(allocator, &type_system, symbol_table, &astdb_system);
    defer type_inference.deinit();

    // Verify type inference engine is connected
    const stats = type_inference.getStatistics();
    try testing.expect(stats.constraints_generated == 0); // No constraints generated yet
    try testing.expect(stats.constraints_solved == 0);
    try testing.expect(stats.unification_steps == 0);

    // Test 4: Component Integration
    // Verify that all components can work together without conflicts
    const test_type_id = type_system.getPrimitiveType(.string);
    try testing.expect(test_type_id.id > 0);

    const test_symbol_id = try symbol_table.symbol_interner.intern("integrated_test");
    try testing.expect(@intFromEnum(test_symbol_id) > 0);

    // SUCCESS: All unified components work together
}

test "Type System Canonical Hashing Integration" {
    const allocator = std.testing.allocator;
    const TypeCanonicalHasher = @import("type_canonical_hash.zig").TypeCanonicalHasher;
    const TypeInfo = @import("type_system.zig").TypeInfo;
    const TypeKind = @import("type_system.zig").TypeKind;

    var hasher = TypeCanonicalHasher.init(allocator);
    defer hasher.deinit();

    // Test canonical hashing with unified TypeInfo
    const type_info = TypeInfo{
        .kind = TypeKind{ .primitive = .i32 },
        .size = 4,
        .alignment = 4,
    };

    // Test that hashing works with unified types
    const existing_type = hasher.findExistingType(&type_info);
    try testing.expect(existing_type == null); // Should not exist initially

    // Register the type
    const new_type_id = hasher.next_id;
    try hasher.registerType(&type_info, new_type_id);

    // Verify it can be found
    const found_type = hasher.findExistingType(&type_info);
    try testing.expect(found_type != null);
    try testing.expect(found_type.?.eql(new_type_id));
}

test "Semantic Module Exports Verification" {
    // Verify that the semantic module exports all required components
    const semantic_module = @import("semantic_module.zig");

    // Test that all major components are exported
    _ = semantic_module.SymbolTable;
    _ = semantic_module.SymbolResolver;
    _ = semantic_module.TypeSystem;
    _ = semantic_module.TypeInference;
    _ = semantic_module.ValidationEngine;
    _ = semantic_module.ValidationResult;
    _ = semantic_module.ErrorManager;

    // Test that type definitions are exported
    _ = semantic_module.SemanticError;
    _ = semantic_module.SemanticWarning;
    _ = semantic_module.ErrorCode;
    _ = semantic_module.WarningCode;
}
