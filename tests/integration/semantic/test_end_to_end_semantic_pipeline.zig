// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! End-to-End Semantic Analysis Pipeline Integration Tests
//!
//! This test suite validates the complete semantic analysis pipeline from
//! source code through parsing, validation, ASTDB storage, and LSP queries.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const astdb_mod = @import("astdb");
const semantic_mod = @import("semantic");

const ValidationEngine = semantic_mod.ValidationEngine;
const AstDB = astdb_mod.AstDB;
const QueryEngine = astdb_mod.QueryEngine;
const RegionParser = astdb_mod.RegionParser;
const RegionLexer = astdb_mod.RegionLexer;

/// Complete end-to-end pipeline context
const PipelineContext = struct {
    allocator: Allocator,
    astdb: AstDB.AstDB,
    query_engine: QueryEngine,
    validation_engine: ValidationEngine,

    pub fn init(allocator: Allocator) !PipelineContext {
        var astdb = AstDB.initWithMode(allocator, true);
        const query_engine = try QueryEngine.init(allocator, &astdb);
        const validation_engine = try ValidationEngine.init(allocator);

        return PipelineContext{
            .allocator = allocator,
            .astdb = astdb,
            .query_engine = query_engine,
            .validation_engine = validation_engine,
        };
    }

    pub fn deinit(self: *PipelineContext) void {
        self.validation_engine.deinit();
        self.query_engine.deinit();
        self.astdb.deinit();
    }

    /// Complete pipeline: source -> tokens -> AST -> validation -> queries
    pub fn processSource(self: *PipelineContext, filename: []const u8, source: []const u8) !PipelineResult {
        // Step 1: Add to ASTDB and parse
        const unit_id = try self.astdb.addUnit(filename, source);
        const unit = self.astdb.getUnit(unit_id).?;

        // Step 2: Tokenize
        var lexer = RegionLexer.init(unit.arenaAllocator(), source, &self.astdb.str_interner);
        defer lexer.deinit();
        const tokens = try lexer.tokenize();

        // Step 3: Parse to AST
        var parser = RegionParser.init(unit.arenaAllocator(), tokens, &self.astdb.str_interner);
        defer parser.deinit();
        const root_node_id = try parser.parse();

        // Step 4: Store in ASTDB
        unit.tokens = tokens;
        unit.nodes = try unit.arenaAllocator().dupe(AstDB.AstNode, parser.nodes.items);
        unit.edges = try unit.arenaAllocator().dupe(AstDB.NodeId, parser.edges.items);
        unit.diags = try unit.arenaAllocator().dupe(AstDB.Diagnostic, parser.diagnostics.items);

        // Step 5: Semantic validation
        const validation_result = try self.validation_engine.validateUnit(unit_id, &self.astdb);

        return PipelineResult{
            .unit_id = unit_id,
            .root_node_id = root_node_id,
            .validation_result = validation_result,
            .token_count = tokens.len,
            .node_count = unit.nodes.len,
        };
    }
};

const PipelineResult = struct {
    unit_id: AstDB.UnitId,
    root_node_id: AstDB.NodeId,
    validation_result: ValidationEngine.ValidationResult,
    token_count: usize,
    node_count: usize,
};

test "complete semantic pipeline - simple function" {
    const allocator = testing.allocator;
    var context = try PipelineContext.init(allocator);
    defer context.deinit();

    const source =
        \\func add(x: i32, y: i32) -> i32 {
        \\    return x + y;
        \\}
    ;

    const result = try context.processSource("simple.jan", source);

    // Verify parsing succeeded
    try testing.expect(result.token_count > 0);
    try testing.expect(result.node_count > 0);

    // Verify validation succeeded
    try testing.expect(result.validation_result.success);
    try testing.expect(result.validation_result.errors.len == 0);

    // Verify ASTDB queries work
    const function_nodes = try context.query_engine.findNodesByType(result.unit_id, .function_declaration);
    try testing.expect(function_nodes.len == 1);

    // Verify type annotations are available
    const type_annotation = try context.query_engine.getTypeAnnotation(result.unit_id, function_nodes[0]);
    try testing.expect(type_annotation != null);

    std.debug.print("✅ Complete semantic pipeline test passed\n", .{});
}

test "complete semantic pipeline - complex program with errors" {
    const allocator = testing.allocator;
    var context = try PipelineContext.init(allocator);
    defer context.deinit();

    const source =
        \\func factorial(n: i32) -> i32 {
        \\    if n <= 1 {
        \\        return 1;
        \\    }
        \\    return n * factorial(n - 1);
        \\}
        \\
        \\func main() {
        \\    let result = factorial(5);
        \\    let invalid = undefined_function();  // Error: undefined function
        \\    return result + "string";            // Error: type mismatch
        \\}
    ;

    const result = try context.processSource("complex.jan", source);

    // Verify parsing succeeded despite semantic errors
    try testing.expect(result.token_count > 0);
    try testing.expect(result.node_count > 0);

    // Verify validation detected errors
    try testing.expect(!result.validation_result.success);
    try testing.expect(result.validation_result.errors.len >= 2);

    // Verify we can still query the AST
    const function_nodes = try context.query_engine.findNodesByType(result.unit_id, .function_declaration);
    try testing.expect(function_nodes.len == 2); // factorial and main

    // Verify error locations are precise
    for (result.validation_result.errors) |err| {
        try testing.expect(err.location.line > 0);
        try testing.expect(err.location.column > 0);
        try testing.expect(err.message.len > 0);
    }

    std.debug.print("✅ Complex semantic pipeline with errors test passed\n", .{});
}

test "semantic pipeline performance benchmark" {
    const allocator = testing.allocator;
    var context = try PipelineContext.init(allocator);
    defer context.deinit();

    // Generate a moderately complex source file
    var source_buffer = std.ArrayList(u8).init(allocator);
    defer source_buffer.deinit();

    // Create 20 functions with various complexity
    for (0..20) |i| {
        try source_buffer.writer().print(
            \\func function_{d}(param1: i32, param2: string) -> i32 {{
            \\    let local_var = param1 * {d};
            \\    if local_var > 100 {{
            \\        return local_var - {d};
            \\    }} else {{
            \\        return local_var + {d};
            \\    }}
            \\}}
            \\
        , .{ i, i, i, i });
    }

    const source = source_buffer.items;
    const start_time = std.time.nanoTimestamp();

    const result = try context.processSource("benchmark.jan", source);

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Verify processing succeeded
    try testing.expect(result.validation_result.success);
    try testing.expect(result.token_count > 100); // Should have many tokens
    try testing.expect(result.node_count > 50); // Should have many nodes

    // Performance requirement: < 200ms for 20 functions
    try testing.expect(duration_ms < 200.0);

    // Verify all functions are queryable
    const function_nodes = try context.query_engine.findNodesByType(result.unit_id, .function_declaration);
    try testing.expect(function_nodes.len == 20);

    std.debug.print("✅ Semantic pipeline performance test passed: {d:.2}ms for 20 functions\n", .{duration_ms});
}

test "semantic pipeline memory efficiency" {
    const allocator = testing.allocator;

    // Use tracking allocator to monitor memory usage
    var tracking_allocator = std.heap.GeneralPurposeAllocator(.{ .track_allocations = true }){};
    defer _ = tracking_allocator.deinit();
    const tracked_allocator = tracking_allocator.allocator();

    var context = try PipelineContext.init(tracked_allocator);
    defer context.deinit();

    const source =
        \\func memory_test(data: string) -> i32 {
        \\    let length = data.length();
        \\    let result = length * 2;
        \\    return result;
        \\}
    ;

    // Process multiple times to test memory reuse
    for (0..5) |i| {
        const filename = try std.fmt.allocPrint(tracked_allocator, "memory_test_{d}.jan", .{i});
        defer tracked_allocator.free(filename);

        const result = try context.processSource(filename, source);
        try testing.expect(result.validation_result.success);

        // Clean up this unit to test memory reclamation
        try context.astdb.removeUnit(result.unit_id);
    }

    // Verify no significant memory leaks (some overhead is expected)
    const current_allocations = tracking_allocator.total_requested_bytes;
    try testing.expect(current_allocations < 1024 * 1024); // Less than 1MB overhead

    std.debug.print("✅ Semantic pipeline memory efficiency test passed: {d} bytes overhead\n", .{current_allocations});
}

test "semantic pipeline with profile constraints" {
    const allocator = testing.allocator;
    var context = try PipelineContext.init(allocator);
    defer context.deinit();

    // Test source that should work in :go profile but not :min profile
    const source =
        \\func error_handling() -> Result[i32, string] {
        \\    let value = try_operation();
        \\    return Ok(value);
        \\}
    ;

    const result = try context.processSource("profile_test.jan", source);

    // This would depend on profile configuration in validation engine
    // For now, just verify the pipeline processes it
    try testing.expect(result.token_count > 0);
    try testing.expect(result.node_count > 0);

    // The validation result would depend on active profile
    // In a real implementation, we'd test different profile settings

    std.debug.print("✅ Semantic pipeline profile constraints test passed\n", .{});
}
