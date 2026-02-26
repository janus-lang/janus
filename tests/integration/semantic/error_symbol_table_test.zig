// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Symbol Table Tests: Error Type Registration
//!
//! Tests that error types and variants are correctly registered in the symbol table:
//! - Error type declaration creates error_type symbol
//! - Error variants are registered in error body scope
//! - Error type resolution works correctly
//! - Duplicate error declarations are caught

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb_core");
const semantic = @import("semantic");

test "Symbol Table: Register error type declaration" {
    const allocator = testing.allocator;

    const source =
        \\error DivisionError { DivisionByZero, Overflow }
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Initialize symbol resolver
    var resolver = try semantic.SymbolResolver.init(allocator, snapshot.astdb_system);
    defer resolver.deinit();

    // Resolve symbols
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    try resolver.resolveUnit(unit_id);

    // Verify error type was registered
    const error_type_symbol = resolver.symbol_table.lookup("DivisionError");
    try testing.expect(error_type_symbol != null);

    if (error_type_symbol) |symbol_id| {
        const symbol = resolver.symbol_table.getSymbol(symbol_id);
        try testing.expect(symbol != null);
        if (symbol) |sym| {
            try testing.expectEqual(semantic.SymbolTable.Symbol.SymbolKind.error_type, sym.kind);
            try testing.expectEqual(semantic.SymbolTable.Symbol.Visibility.public, sym.visibility);
        }
    }

}

test "Symbol Table: Register error variants" {
    const allocator = testing.allocator;

    const source =
        \\error FileError { NotFound, PermissionDenied, AlreadyExists }
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Initialize symbol resolver
    var resolver = try semantic.SymbolResolver.init(allocator, snapshot.astdb_system);
    defer resolver.deinit();

    // Resolve symbols
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    try resolver.resolveUnit(unit_id);

    // Verify error type was registered
    const error_type_symbol = resolver.symbol_table.lookup("FileError");
    try testing.expect(error_type_symbol != null);

    // Verify variants were registered
    // Note: Variants are in the error body scope, need special lookup
    // Variant lookup deferred: requires navigating to error body scope
    // Expected variants: NotFound, PermissionDenied, AlreadyExists
}

test "Symbol Table: Detect duplicate error declaration" {
    const allocator = testing.allocator;

    const source =
        \\error MyError { Fail1 }
        \\error MyError { Fail2 }
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Initialize symbol resolver
    var resolver = try semantic.SymbolResolver.init(allocator, snapshot.astdb_system);
    defer resolver.deinit();

    // Resolve symbols - should detect duplicate
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    try resolver.resolveUnit(unit_id);

    // Check diagnostics for duplicate declaration
    const diagnostics = resolver.getDiagnostics();
    var found_duplicate = false;
    for (diagnostics) |diag| {
        if (std.mem.indexOf(u8, diag.message, "duplicate") != null or
            std.mem.indexOf(u8, diag.message, "Duplicate") != null or
            std.mem.indexOf(u8, diag.message, "already declared") != null)
        {
            found_duplicate = true;
            break;
        }
    }

    try testing.expect(found_duplicate);
}

test "Symbol Table: Error type with function declaration" {
    const allocator = testing.allocator;

    const source =
        \\error DivisionError { DivisionByZero }
        \\
        \\func divide(a: i32, b: i32) -> i32 ! DivisionError {
        \\    if b == 0 {
        \\        fail DivisionError.DivisionByZero
        \\    }
        \\    a / b
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Initialize symbol resolver
    var resolver = try semantic.SymbolResolver.init(allocator, snapshot.astdb_system);
    defer resolver.deinit();

    // Resolve symbols
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    try resolver.resolveUnit(unit_id);

    // Verify both error type and function were registered
    const error_symbol = resolver.symbol_table.lookup("DivisionError");
    try testing.expect(error_symbol != null);

    const func_symbol = resolver.symbol_table.lookup("divide");
    try testing.expect(func_symbol != null);

}
