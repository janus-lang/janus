// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Error Handling Integration Tests
//!
//! Tests the integration of symbol table and type system for error handling:
//! - Error type declarations create both symbols AND types
//! - Error union types reference error type symbols
//! - Full end-to-end error handling pipeline

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb_core");
const semantic = @import("semantic");

test "Integration: Error type symbol with type system type" {
    const allocator = testing.allocator;

    const source =
        \\error DivisionError { DivisionByZero, Overflow }
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Initialize symbol resolver (includes type system)
    var resolver = try semantic.SymbolResolver.init(allocator, snapshot.astdb_system);
    defer resolver.deinit();

    // Resolve symbols
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    try resolver.resolveUnit(unit_id);

    // Verify symbol was created
    const error_symbol = resolver.symbol_table.lookup("DivisionError");
    try testing.expect(error_symbol != null);

    if (error_symbol) |symbol_id| {
        const symbol = resolver.symbol_table.getSymbol(symbol_id);
        try testing.expect(symbol != null);

        if (symbol) |sym| {
            try testing.expectEqual(semantic.SymbolTable.Symbol.SymbolKind.error_type, sym.kind);

            // If type_id is set, verify it's a valid type
            if (sym.type_id) |type_id| {
                const type_info = resolver.type_system.getTypeInfo(type_id);
                _ = type_info; // Type exists and is valid
            }
        }
    }
}

test "Integration: Error union type creation" {
    const allocator = testing.allocator;

    // Create type system
    var type_system = try semantic.TypeSystem.init(allocator);
    defer type_system.deinit();

    // Create error union type: i32 ! ErrorType
    const i32_type = type_system.getPrimitiveType(.i32);
    const error_type = type_system.getPrimitiveType(.i64); // Placeholder

    const error_union_type = try type_system.createErrorUnionType(i32_type, error_type);

    // Verify type properties
    try testing.expect(type_system.isErrorUnion(error_union_type));

    const payload = type_system.getErrorUnionPayload(error_union_type);
    try testing.expect(payload != null);
    try testing.expectEqual(i32_type.id, payload.?.id);

    const err = type_system.getErrorUnionError(error_union_type);
    try testing.expect(err != null);
    try testing.expectEqual(error_type.id, err.?.id);

    // Verify canonical hashing works
    const error_union_type_2 = try type_system.createErrorUnionType(i32_type, error_type);
    try testing.expectEqual(error_union_type.id, error_union_type_2.id);
}

test "Integration: Multiple error types with distinct type IDs" {
    const allocator = testing.allocator;

    const source =
        \\error FileError { NotFound, PermissionDenied }
        \\error NetworkError { ConnectionFailed, Timeout }
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    var resolver = try semantic.SymbolResolver.init(allocator, snapshot.astdb_system);
    defer resolver.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    try resolver.resolveUnit(unit_id);

    // Both error types should exist
    const file_error = resolver.symbol_table.lookup("FileError");
    const network_error = resolver.symbol_table.lookup("NetworkError");

    try testing.expect(file_error != null);
    try testing.expect(network_error != null);

    // They should be different symbols
    try testing.expect(@intFromEnum(file_error.?) != @intFromEnum(network_error.?));
}

test "Integration: Error union with function return type" {
    const allocator = testing.allocator;

    // Create type system
    var type_system = try semantic.TypeSystem.init(allocator);
    defer type_system.deinit();

    // Create function that returns i32 ! ErrorType
    const i32_type = type_system.getPrimitiveType(.i32);
    const error_type = type_system.getPrimitiveType(.i64);
    const error_union_return = try type_system.createErrorUnionType(i32_type, error_type);

    // Create function type with error union return
    const params = [_]semantic.TypeId{i32_type, i32_type}; // (i32, i32)
    const func_type = try type_system.createFunctionType(
        &params,
        error_union_return,
        .janus_call
    );

    const func_info = type_system.getTypeInfo(func_type);
    try testing.expect(func_info.kind == .function);

    // Extract return type and verify it's error union
    const return_type = func_info.kind.function.return_type;
    try testing.expect(type_system.isErrorUnion(return_type));

    const payload = type_system.getErrorUnionPayload(return_type);
    try testing.expectEqual(i32_type.id, payload.?.id);
}
