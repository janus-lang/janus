// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Validation Engine ASTDB Integration Tests
//!
//! This test suite validates the complete integration between the Semantic Validation Engine
//! and the ASTDB query system, ensuring validated AST nodes are properly stored and queryable.

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const astdb_mod = @import("astdb");
const semantic_mod = @import("semantic");

const ValidationEngine = semantic_mod.ValidationEngine;
const AstDB = astdb_mod.AstDB;
const QueryEngine = astdb_mod.QueryEngine;
const SymbolTable = semantic_mod.SymbolTable;
const TypeSystem = semantic_mod.TypeSystem;

/// Integration test context combining validation engine with ASTDB
const ValidationAstDBContext = struct {
    allocator: Allocator,
    astdb: AstDB.AstDB,
    query_engine: QueryEngine,
    validation_engine: ValidationEngine,

    pub fn init(allocator: Allocator) !ValidationAstDBContext {
        var astdb = AstDB.initWithMode(allocator, true);
        const query_engine = try QueryEngine.init(allocator, &astdb);
        const validation_engine = try ValidationEngine.init(allocator);

        return ValidationAstDBContext{
            .allocator = allocator,
            .astdb = astdb,
            .query_engine = query_engine,
            .validation_engine = validation_engine,
        };
    }

    pub fn deinit(self: *ValidationAstDBContext) void {
        self.validation_engine.deinit();
        self.query_engine.deinit();
        self.astdb.deinit();
    }
};

test "validation engine ASTDB query integration" {
    const allocator = testing.allocator;
    var context = try ValidationAstDBContext.init(allocator);
    defer context.deinit();

    // Test source with semantic content
    const source =
        \\func add(x: i32, y: i32) -> i32 {
        \\    return x + y;
        \\}
        \\
        \\func main() {
        \\    let result = add(10, 20);
        \\    return result;
        \\}
    ;

    // Add source to ASTDB
    const unit_id = try context.astdb.addUnit("test.jan", source);
    _ = context.astdb.getUnit(unit_id).?;

    // Parse and validate through validation engine
    const validation_result = try context.validation_engine.validateUnit(unit_id, &context.astdb);
    try testing.expect(validation_result.success);
    try testing.expect(validation_result.errors.len == 0);

    // Query validated AST through query engine
    const function_nodes = try context.query_engine.findNodesByType(unit_id, .function_declaration);
    try testing.expect(function_nodes.len == 2); // add and main functions

    // Verify type annotations are available through queries
    const add_function = function_nodes[0];
    const type_annotation = try context.query_engine.getTypeAnnotation(unit_id, add_function);
    try testing.expect(type_annotation != null);

    // Verify symbol resolution through queries
    const symbols = try context.query_engine.getSymbolsInScope(unit_id, add_function);
    try testing.expect(symbols.len >= 2); // x and y parameters

}

test "validation engine error reporting through ASTDB" {
    const allocator = testing.allocator;
    var context = try ValidationAstDBContext.init(allocator);
    defer context.deinit();

    // Test source with semantic errors
    const source =
        \\func broken(x: i32) -> i32 {
        \\    let y = undefined_variable;  // Error: undefined symbol
        \\    return y + "string";         // Error: type mismatch
        \\}
    ;

    const unit_id = try context.astdb.addUnit("broken.jan", source);

    // Validate and expect errors
    const validation_result = try context.validation_engine.validateUnit(unit_id, &context.astdb);
    try testing.expect(!validation_result.success);
    try testing.expect(validation_result.errors.len >= 2);

    // Verify errors are queryable through ASTDB
    const error_diagnostics = try context.query_engine.getDiagnostics(unit_id);
    try testing.expect(error_diagnostics.len >= 2);

    // Verify error locations are precise
    for (validation_result.errors) |err| {
        try testing.expect(err.location.line > 0);
        try testing.expect(err.location.column > 0);
    }

}

test "incremental validation with ASTDB updates" {
    const allocator = testing.allocator;
    var context = try ValidationAstDBContext.init(allocator);
    defer context.deinit();

    // Initial valid source
    const initial_source =
        \\func test() -> i32 {
        \\    return 42;
        \\}
    ;

    const unit_id = try context.astdb.addUnit("incremental.jan", initial_source);

    // Initial validation
    var validation_result = try context.validation_engine.validateUnit(unit_id, &context.astdb);
    try testing.expect(validation_result.success);

    // Update source with error
    const updated_source =
        \\func test() -> i32 {
        \\    return "not an integer";  // Type error
        \\}
    ;

    try context.astdb.updateUnit(unit_id, updated_source);

    // Re-validate after update
    validation_result = try context.validation_engine.validateUnit(unit_id, &context.astdb);
    try testing.expect(!validation_result.success);
    try testing.expect(validation_result.errors.len > 0);

    // Verify incremental update worked
    const current_unit = context.astdb.getUnit(unit_id).?;
    try testing.expectEqualStrings(updated_source, current_unit.source);

}

test "validation engine performance with large ASTDB" {
    const allocator = testing.allocator;
    var context = try ValidationAstDBContext.init(allocator);
    defer context.deinit();

    const start_time = compat_time.nanoTimestamp();

    // Create multiple compilation units
    var unit_ids: std.ArrayList(AstDB.UnitId) = .empty;
    defer unit_ids.deinit();

    for (0..10) |i| {
        const source = try std.fmt.allocPrint(allocator,
            \\func test_{d}(x: i32) -> i32 {{
            \\    let y = x * {d};
            \\    return y + {d};
            \\}}
        , .{ i, i, i });
        defer allocator.free(source);

        const filename = try std.fmt.allocPrint(allocator, "test_{d}.jan", .{i});
        defer allocator.free(filename);

        const unit_id = try context.astdb.addUnit(filename, source);
        try unit_ids.append(unit_id);
    }

    // Validate all units
    for (unit_ids.items) |unit_id| {
        const validation_result = try context.validation_engine.validateUnit(unit_id, &context.astdb);
        try testing.expect(validation_result.success);
    }

    const end_time = compat_time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Performance requirement: < 100ms for 10 units
    try testing.expect(duration_ms < 100.0);

}
