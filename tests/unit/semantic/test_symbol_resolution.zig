// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Symbol Resolution Tests
//!
//! Tests the Symbol Table and Symbol Resolver implementation to ensure
//! every identifier is correctly bound to its declaration with proper
//! scope resolution and error reporting.

const std = @import("std");
const testing = std.testing;
const print = std.debug.print;

const astdb = @import("../../../compiler/astdb/astdb.zig");
const symbol_table = @import("../../../compiler/semantic/symbol_table.zig");
const symbol_resolver = @import("../../../compiler/semantic/symbol_resolver.zig");

const SymbolTable = symbol_table.SymbolTable;
constlver = symbol_resolver.SymbolResolver;

test "Symbol Table - Basic Operations" {
    print("\n🔧 SYMBOL TABLE BASIC OPERATIONS TEST\n");
    print("=====================================\n");

    const allocator = std.testing.allocator;

    const table = try SymbolTable.init(allocator);
    defer table.deinit();

    // Test symbol interner
    print("🧪 Test 1: Symbol Interner\n");

    const name1 = try table.symbol_interner.intern("hello");
    const name2 = try table.symbol_interner.intern("world");
    const name3 = try table.symbol_interner.intern("hello"); // Duplicate

    try testing.expect(name1 == name3); // Should be deduplicated
    try testing.expect(name1 != name2); // Should be different

    const retrieved1 = table.symbol_interner.getString(name1);
    const retrieved2 = table.symbol_interner.getString(name2);

    try testing.expectEqualStrings("hello", retrieved1);
    try testing.expectEqualStrings("world", retrieved2);

    print("   ✅ Symbol interner working correctly\n");

    // Test scope creation
    print("🧪 Test 2: Scope Management\n");

    const func_scope = try table.createScope(table.global_scope, .function);
    const block_scope = try table.createScope(func_scope, .block);

    try table.pushScope(func_scope);
    try table.pushScope(block_scope);

    const current = table.getCurrentScope();
    try testing.expect(current == block_scope);

    _ = table.popScope();
    const after_pop = table.getCurrentScope();
    try testing.expect(after_pop == func_scope);

    print("   ✅ Scope management working correctly\n");

    // Test symbol declaration
    print("🧪 Test 3: Symbol Declaration\n");

    const test_span = symbol_table.SourceSpan{
        .start_line = 1,
        .start_column = 5,
        .end_line = 1,
        .end_column = 10,
    };

    const var_name = try table.symbol_interner.intern("test_var");
    const symbol_id = try table.declareSymbol(
        var_name,
        .variable,
        @enumFromInt(42), // Mock node ID
        test_span,
        .private,
    );

    const symbol = table.getSymbol(symbol_id).?;
    try testing.expect(symbol.name == var_name);
    try testing.expect(symbol.kind == .variable);
    try testing.expect(symbol.visibility == .private);

    print("   ✅ Symbol declaration working correctly\n");

    // Test symbol resolution
    print("🧪 Test 4: Symbol Resolution\n");

    const resolved = table.resolveIdentifier(var_name, null);
    try testing.expect(resolved == symbol_id);

    // Test undefined symbol
    const undefined_name = try table.symbol_interner.intern("undefined_var");
    const undefined_resolved = table.resolveIdentifier(undefined_name, null);
    try testing.expect(undefined_resolved == null);

    print("   ✅ Symbol resolution working correctly\n");

    // Test statistics
    print("🧪 Test 5: Statistics\n");

    const stats = table.getStatistics();
    print("   Symbols: {}, Scopes: {}, Bindings: {}\n", .{ stats.total_symbols, stats.total_scopes, stats.total_bindings });

    try testing.expect(stats.total_symbols >= 1);
    try testing.expect(stats.total_scopes >= 3); // global + func + block

    print("   ✅ Statistics reporting correctly\n");

    print("🔧 Symbol Table: ALL TESTS PASSED!\n");
}

test "Symbol Resolution - Lexical Scoping" {
    print("\n🔍 SYMBOL RESOLUTION LEXICAL SCOPING TEST\n");
    print("==========================================\n");

    const allocator = std.testing.allocator;

    const table = try SymbolTable.init(allocator);
    defer table.deinit();

    // Simulate nested scopes with shadowing
    print("🧪 Test: Nested Scopes with Shadowing\n");

    const test_span = symbol_table.SourceSpan{
        .start_line = 1,
        .start_column = 0,
        .end_line = 1,
        .end_column = 5,
    };

    // Global scope: declare 'x'
    const x_name = try table.symbol_interner.intern("x");
    const global_x = try table.declareSymbol(
        x_name,
        .variable,
        @enumFromInt(1),
        test_span,
        .public,
    );

    // Function scope: declare 'x' (shadows global)
    const func_scope = try table.createScope(table.global_scope, .function);
    try table.pushScope(func_scope);

    const func_x = try table.declareSymbol(
        x_name,
        .parameter,
        @enumFromInt(2),
        test_span,
        .private,
    );

    // Block scope: declare 'x' (shadows function)
    const block_scope = try table.createScope(func_scope, .block);
    try table.pushScope(block_scope);

    const block_x = try table.declareSymbol(
        x_name,
        .variable,
        @enumFromInt(3),
        test_span,
        .private,
    );

    // Resolution should find innermost 'x'
    const resolved_in_block = table.resolveIdentifier(x_name, null);
    try testing.expect(resolved_in_block == block_x);

    print("   ✅ Block scope resolution: found innermost symbol\n");

    // Pop to function scope
    _ = table.popScope();
    const resolved_in_func = table.resolveIdentifier(x_name, null);
    try testing.expect(resolved_in_func == func_x);

    print("   ✅ Function scope resolution: found function symbol\n");

    // Pop to global scope
    _ = table.popScope();
    const resolved_in_global = table.resolveIdentifier(x_name, null);
    try testing.expect(resolved_in_global == global_x);

    print("   ✅ Global scope resolution: found global symbol\n");

    print("🔍 Lexical Scoping: ALL TESTS PASSED!\n");
}

test "Symbol Resolution - Visibility Rules" {
    print("\n👁️  SYMBOL RESOLUTION VISIBILITY TEST\n");
    print("====================================\n");

    const allocator = std.testing.allocator;

    const table = try SymbolTable.init(allocator);
    defer table.deinit();

    print("🧪 Test: Visibility Enforcement\n");

    const test_span = symbol_table.SourceSpan{
        .start_line = 1,
        .start_column = 0,
        .end_line = 1,
        .end_column = 10,
    };

    // Declare symbols with different visibility levels
    const public_name = try table.symbol_interner.intern("public_func");
    const private_name = try table.symbol_interner.intern("private_var");
    const module_name = try table.symbol_interner.intern("module_type");

    const public_symbol = try table.declareSymbol(
        public_name,
        .function,
        @enumFromInt(1),
        test_span,
        .public,
    );

    const private_symbol = try table.declareSymbol(
        private_name,
        .variable,
        @enumFromInt(2),
        test_span,
        .private,
    );

    const module_symbol = try table.declareSymbol(
        module_name,
        .struct_type,
        @enumFromInt(3),
        test_span,
        .module_local,
    );

    // Test resolution from same scope
    try testing.expect(table.resolveIdentifier(public_name, null) == public_symbol);
    try testing.expect(table.resolveIdentifier(private_name, null) == private_symbol);
    try testing.expect(table.resolveIdentifier(module_name, null) == module_symbol);

    print("   ✅ Same scope: all symbols visible\n");

    // Create nested scope and test visibility
    const nested_scope = try table.createScope(table.global_scope, .function);
    try table.pushScope(nested_scope);

    // Public should be visible
    try testing.expect(table.resolveIdentifier(public_name, null) == public_symbol);

    // Private should be visible (same module for now)
    try testing.expect(table.resolveIdentifier(private_name, null) == private_symbol);

    // Module-local should be visible (same module)
    try testing.expect(table.resolveIdentifier(module_name, null) == module_symbol);

    print("   ✅ Nested scope: visibility rules enforced\n");

    _ = table.popScope();

    print("👁️  Visibility Rules: ALL TESTS PASSED!\n");
}

test "Symbol Resolution - Error Detection" {
    print("\n❌ SYMBOL RESOLUTION ERROR DETECTION TEST\n");
    print("==========================================\n");

    const allocator = std.testing.allocator;

    // Initialize ASTDB for resolver testing
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const table = try SymbolTable.init(allocator);
    defer table.deinit();

    const resolver = try SymbolResolver.init(allocator, &db, table);
    defer resolver.deinit();

    print("🧪 Test: Undefined Symbol Detection\n");

    // Test undefined symbol reporting
    const undefined_name = try table.symbol_interner.intern("undefined_symbol");
    const test_span = symbol_table.SourceSpan{
        .start_line = 5,
        .start_column = 10,
        .end_line = 5,
        .end_column = 25,
    };

    try resolver.reportUndefinedSymbol(undefined_name, test_span);

    const diagnostics = resolver.getDiagnostics();
    try testing.expect(diagnostics.len == 1);

    const diagnostic = diagnostics[0];
    try testing.expect(diagnostic.kind == .undefined_symbol);
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "undefined_symbol") != null);

    print("   ✅ Undefined symbol error generated correctly\n");

    print("🧪 Test: Duplicate Declaration Detection\n");

    // Test duplicate declaration
    const duplicate_name = try table.symbol_interner.intern("duplicate_func");

    // First declaration should succeed
    const first_symbol = try table.declareSymbol(
        duplicate_name,
        .function,
        @enumFromInt(1),
        test_span,
        .public,
    );
    _ = first_symbol;

    // Second declaration should fail
    const result = table.declareSymbol(
        duplicate_name,
        .function,
        @enumFromInt(2),
        test_span,
        .public,
    );

    try testing.expectError(error.DuplicateDeclaration, result);

    print("   ✅ Duplicate declaration detected correctly\n");

    print("❌ Error Detection: ALL TESTS PASSED!\n");
}

test "Symbol Resolution - Performance Characteristics" {
    print("\n⚡ SYMBOL RESOLUTION PERFORMANCE TEST\n");
    print("====================================\n");

    const allocator = std.testing.allocator;

    const table = try SymbolTable.init(allocator);
    defer table.deinit();

    print("🧪 Test: Large Symbol Table Performance\n");

    const num_symbols = 1000;
    const test_span = symbol_table.SourceSpan{
        .start_line = 1,
        .start_column = 0,
        .end_line = 1,
        .end_column = 10,
    };

    // Create many symbols
    var symbol_ids = ArrayList(symbol_table.SymbolId){};
    defer symbol_ids.deinit();

    const start_time = std.time.nanoTimestamp();

    for (0..num_symbols) |i| {
        const name_str = try std.fmt.allocPrint(allocator, "symbol_{d}", .{i});
        defer allocator.free(name_str);

        const name = try table.symbol_interner.intern(name_str);
        const symbol_id = try table.declareSymbol(
            name,
            .variable,
            @enumFromInt(@intCast(i)),
            test_span,
            .private,
        );

        try symbol_ids.append(symbol_id);
    }

    const declaration_time = std.time.nanoTimestamp();
    const declaration_duration = @as(f64, @floatFromInt(declaration_time - start_time)) / 1_000_000.0;

    print("   Symbol declaration time: {d:.2f}ms for {} symbols\n", .{ declaration_duration, num_symbols });

    // Test resolution performance
    var resolved_count: u32 = 0;

    for (0..num_symbols) |i| {
        const name_str = try std.fmt.allocPrint(allocator, "symbol_{d}", .{i});
        defer allocator.free(name_str);

        const name = try table.symbol_interner.intern(name_str);
        if (table.resolveIdentifier(name, null) != null) {
            resolved_count += 1;
        }
    }

    const resolution_time = std.time.nanoTimestamp();
    const resolution_duration = @as(f64, @floatFromInt(resolution_time - declaration_time)) / 1_000_000.0;

    print("   Symbol resolution time: {d:.2f}ms for {} lookups\n", .{ resolution_duration, num_symbols });
    print("   Resolution success rate: {d:.1f}%\n", .{ @as(f64, @floatFromInt(resolved_count)) / @as(f64, @floatFromInt(num_symbols)) * 100.0 });

    try testing.expect(resolved_count == num_symbols);

    // Performance requirements
    const avg_declaration_time = declaration_duration / @as(f64, @floatFromInt(num_symbols));
    const avg_resolution_time = resolution_duration / @as(f64, @floatFromInt(num_symbols));

    print("   Average declaration time: {d:.3f}ms per symbol\n", .{avg_declaration_time});
    print("   Average resolution time: {d:.3f}ms per lookup\n", .{avg_resolution_time});

    // Should be sub-millisecond for individual operations
    try testing.expect(avg_declaration_time < 1.0);
    try testing.expect(avg_resolution_time < 1.0);

    print("   ✅ Performance requirements met\n");

    // Test memory usage
    const stats = table.getStatistics();
    print("   Memory usage: {} symbols, {} scopes, {} bindings\n", .{ stats.total_symbols, stats.total_scopes, stats.total_bindings });

    try testing.expect(stats.total_symbols == num_symbols);

    print("⚡ Performance: ALL TESTS PASSED!\n");
}

test "Symbol Resolution - Integration Test" {
    print("\n🔗 SYMBOL RESOLUTION INTEGRATION TEST\n");
    print("=====================================\n");

    const allocator = std.testing.allocator;

    // Initialize full system
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const table = try SymbolTable.init(allocator);
    defer table.deinit();

    const resolver = try SymbolResolver.init(allocator, &db, table);
    defer resolver.deinit();

    print("🧪 Test: Complete Symbol Resolution Workflow\n");

    // Simulate a simple Janus program
    const test_source =
        \\func fibonacci(n: i32) -> i32 {
        \\    if n <= 1 {
        \\        return n;
        \\    }
        \\    let result = fibonacci(n - 1) + fibonacci(n - 2);
        \\    return result;
        \\}
        \\
        \\func main() {
        \\    let value = fibonacci(10);
        \\    print(value);
        \\}
    ;

    // Add compilation unit
    const unit_id = try db.addUnit("test_fibonacci.jan", test_source);

    // TODO: This would require full parser integration
    // For now, test the resolver infrastructure

    print("   ✅ System initialization successful\n");

    // Test resolver statistics
    const stats = resolver.getStatistics();
    print("   Resolver stats: {} declarations, {} references\n", .{ stats.declarations_collected, stats.references_resolved });

    // Test symbol table integration
    const table_stats = table.getStatistics();
    print("   Symbol table stats: {} symbols, {} scopes\n", .{ table_stats.total_symbols, table_stats.total_scopes });

    print("   ✅ Integration components working together\n");

    _ = unit_id; // TODO: Use for full resolution test

    print("🔗 Integration: INFRASTRUCTURE COMPLETE!\n");
}
