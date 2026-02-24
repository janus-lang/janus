// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Validation Engine LSP Integration Tests
//!
//! This test suite validates the integration between the Semantic Validation Engine
//! and the LSP server, ensuring real-time validation and semantic information delivery.

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const time = std.time;

const astdb_mod = @import("astdb");
const semantic_mod = @import("semantic");

const ValidationEngine = semantic_mod.ValidationEngine;
const AstDB = astdb_mod.AstDB;
const QueryEngine = astdb_mod.QueryEngine;

/// Mock LSP request/response for testing
const LSPRequest = struct {
    method: []const u8,
    params: std.json.Value,
    id: i32,
};

const LSPResponse = struct {
    result: ?std.json.Value,
    err: ?LSPError,
    id: i32,
};

const LSPError = struct {
    code: i32,
    message: []const u8,
};

/// LSP integration test context
const LSPValidationContext = struct {
    allocator: Allocator,
    astdb: AstDB.AstDB,
    query_engine: QueryEngine,
    validation_engine: ValidationEngine,
    document_uri: []const u8,
    document_version: i32,

    pub fn init(allocator: Allocator) !LSPValidationContext {
        var astdb = AstDB.initWithMode(allocator, true);
        const query_engine = try QueryEngine.init(allocator, &astdb);
        const validation_engine = try ValidationEngine.init(allocator);

        return LSPValidationContext{
            .allocator = allocator,
            .astdb = astdb,
            .query_engine = query_engine,
            .validation_engine = validation_engine,
            .document_uri = "file:///test.jan",
            .document_version = 1,
        };
    }

    pub fn deinit(self: *LSPValidationContext) void {
        self.validation_engine.deinit();
        self.query_engine.deinit();
        self.astdb.deinit();
    }

    /// Simulate LSP textDocument/didOpen notification
    pub fn didOpenDocument(self: *LSPValidationContext, content: []const u8) !AstDB.UnitId {
        const unit_id = try self.astdb.addUnit(self.document_uri, content);

        // Trigger validation as LSP would
        const validation_result = try self.validation_engine.validateUnit(unit_id, &self.astdb);

        // Store validation results for LSP queries
        _ = validation_result; // Would be stored in LSP server state

        return unit_id;
    }

    /// Simulate LSP textDocument/didChange notification
    pub fn didChangeDocument(self: *LSPValidationContext, unit_id: AstDB.UnitId, new_content: []const u8) !void {
        try self.astdb.updateUnit(unit_id, new_content);
        self.document_version += 1;

        // Re-validate after change
        const validation_result = try self.validation_engine.validateUnit(unit_id, &self.astdb);
        _ = validation_result; // Would trigger diagnostics publication
    }

    /// Simulate LSP textDocument/hover request
    pub fn handleHoverRequest(self: *LSPValidationContext, unit_id: AstDB.UnitId, line: u32, character: u32) !?[]const u8 {
        // Find node at position
        const node_id = try self.query_engine.getNodeAtPosition(unit_id, line, character);
        if (node_id == null) return null;

        // Get type information for hover
        const type_info = try self.query_engine.getTypeAnnotation(unit_id, node_id.?);
        if (type_info == null) return null;

        // Format hover response (simplified)
        return try std.fmt.allocPrint(self.allocator, "Type: {s}", .{type_info.?.name});
    }

    /// Simulate LSP textDocument/definition request
    pub fn handleDefinitionRequest(self: *LSPValidationContext, unit_id: AstDB.UnitId, line: u32, character: u32) !?AstDB.NodeId {
        // Find symbol at position
        const symbol_node = try self.query_engine.getNodeAtPosition(unit_id, line, character);
        if (symbol_node == null) return null;

        // Find definition through symbol resolution
        const definition = try self.query_engine.getSymbolDefinition(unit_id, symbol_node.?);
        return definition;
    }
};

test "LSP document lifecycle with validation" {
    const allocator = testing.allocator;
    var context = try LSPValidationContext.init(allocator);
    defer context.deinit();

    // Simulate opening a document
    const initial_content =
        \\func greet(name: string) -> string {
        \\    return "Hello, " + name;
        \\}
    ;

    const unit_id = try context.didOpenDocument(initial_content);

    // Verify document was added and validated
    const unit = context.astdb.getUnit(unit_id).?;
    try testing.expectEqualStrings(initial_content, unit.source);

    // Simulate document change
    const updated_content =
        \\func greet(name: string) -> string {
        \\    return "Hi, " + name + "!";
        \\}
    ;

    try context.didChangeDocument(unit_id, updated_content);

    // Verify document was updated
    const updated_unit = context.astdb.getUnit(unit_id).?;
    try testing.expectEqualStrings(updated_content, updated_unit.source);

}

test "LSP hover with validation engine integration" {
    const allocator = testing.allocator;
    var context = try LSPValidationContext.init(allocator);
    defer context.deinit();

    const content =
        \\func calculate(x: i32, y: i32) -> i32 {
        \\    let result = x + y;
        \\    return result;
        \\}
    ;

    const unit_id = try context.didOpenDocument(content);

    // Test hover on variable 'result' (line 1, approximate character position)
    const hover_response = try context.handleHoverRequest(unit_id, 1, 8);

    // Should get type information from validation engine
    if (hover_response) |response| {
        try testing.expect(std.mem.indexOf(u8, response, "i32") != null);
        allocator.free(response);
    }

}

test "LSP go-to-definition with symbol resolution" {
    const allocator = testing.allocator;
    var context = try LSPValidationContext.init(allocator);
    defer context.deinit();

    const content =
        \\func helper() -> i32 {
        \\    return 42;
        \\}
        \\
        \\func main() {
        \\    let value = helper();
        \\    return value;
        \\}
    ;

    const unit_id = try context.didOpenDocument(content);

    // Test go-to-definition on 'helper' call (line 4, approximate position)
    const definition_node = try context.handleDefinitionRequest(unit_id, 4, 16);

    // Should find the function definition
    try testing.expect(definition_node != null);

}

test "LSP real-time diagnostics with validation errors" {
    const allocator = testing.allocator;
    var context = try LSPValidationContext.init(allocator);
    defer context.deinit();

    // Start with valid content
    const valid_content =
        \\func test() -> i32 {
        \\    return 42;
        \\}
    ;

    const unit_id = try context.didOpenDocument(valid_content);

    // Verify no errors initially
    var validation_result = try context.validation_engine.validateUnit(unit_id, &context.astdb);
    try testing.expect(validation_result.success);
    try testing.expect(validation_result.errors.len == 0);

    // Introduce error through document change
    const invalid_content =
        \\func test() -> i32 {
        \\    return "not a number";  // Type error
        \\}
    ;

    try context.didChangeDocument(unit_id, invalid_content);

    // Verify errors are detected
    validation_result = try context.validation_engine.validateUnit(unit_id, &context.astdb);
    try testing.expect(!validation_result.success);
    try testing.expect(validation_result.errors.len > 0);

    // Verify error has proper location for LSP diagnostics
    const err = validation_result.errors[0];
    try testing.expect(err.location.line > 0);
    try testing.expect(err.location.column > 0);

}

test "LSP performance with concurrent validation requests" {
    const allocator = testing.allocator;
    var context = try LSPValidationContext.init(allocator);
    defer context.deinit();

    const content =
        \\func fibonacci(n: i32) -> i32 {
        \\    if n <= 1 {
        \\        return n;
        \\    }
        \\    return fibonacci(n - 1) + fibonacci(n - 2);
        \\}
    ;

    const unit_id = try context.didOpenDocument(content);

    const start_time = compat_time.nanoTimestamp();

    // Simulate multiple concurrent LSP requests
    var hover_results: [10]?[]const u8 = undefined;
    for (0..10) |i| {
        hover_results[i] = try context.handleHoverRequest(unit_id, 0, @intCast(i + 5));
    }

    const end_time = compat_time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Performance requirement: < 50ms for 10 concurrent requests
    try testing.expect(duration_ms < 50.0);

    // Clean up allocated responses
    for (hover_results) |result| {
        if (result) |response| {
            allocator.free(response);
        }
    }

}
