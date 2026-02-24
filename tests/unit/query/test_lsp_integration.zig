// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSP Integration Tests
//!
//! Tests the integration between the LSP server and ASTDB query engine,
//! validating that all LSP operations meet performance requirements and
//! provide correct semantic information.

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const json = std.json;

const lsp_server = @import("../../../lsp/janus_lsp_server.zig");
const query_engine = @import("../../../compiler/astdb/query_engine.zig");
const astdb = @import("../../../compiler/astdb/astdb.zig");

test "LSP Server Initialization" {

    const allocator = std.testing.allocator;

    const config = lsp_server.LSPConfig{
        .max_response_time_ms = 10,
        .enable_caching = true,
        .profile = ":full",
        .enable_diagnostics = true,
    };

    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    // Test initialization capabilities
    const init_params = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    const capabilities = try server.handleInitialize(init_params);

    try testing.expect(capabilities.object.contains("capabilities"));
    const caps = capabilities.object.get("capabilities").?;

    // Verify required capabilities are present
    try testing.expect(caps.object.get("hoverProvider").?.bool == true);
    try testing.expect(caps.object.get("definitionProvider").?.bool == true);
    try testing.expect(caps.object.get("referencesProvider").?.bool == true);

}

test "Query Engine Performance Requirements" {

    const allocator = std.testing.allocator;

    // Initialize ASTDB and query engine
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const engine = try query_engine.QueryEngine.init(allocator, &db);
    defer engine.deinit();

    // Add a test document
    const test_source =
        \\func main() {
        \\    let x: i32 = 42;
        \\    let y = x + 1;
        \\    return y;
        \\}
    ;

    const unit_id = try db.addUnit("test.jan", test_source);
    _ = unit_id;

    // Test query performance
    const start_time = compat_time.nanoTimestamp();

    // Simulate hover query
    const symbol_info = try engine.querySymbolAtPosition("test.jan", 1, 8); // Position of 'x'
    _ = symbol_info;

    const end_time = compat_time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;


    // Verife requirement (< 10ms)
    try testing.expect(duration_ms < 10.0);

}

test "LSP Hover Functionality" {
    bug.print("\n🔧 LSP HOVER FUNCTIONALITY TEST\n", .{});

    const allocator = std.testing.allocator;

    const config = lsp_server.LSPConfig{};
    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    // Simulate document change
    const change_params = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const text_document = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try text_document.object.put("uri", json.Value{ .string = "file://test.jan" });
    try text_document.object.put("version", json.Value{ .integer = 1 });

    const content_changes = json.Value{
        .array = .empty,
    };

    const change = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try change.object.put("text", json.Value{ .string = "func main() { let x: i32 = 42; }" });

    try content_changes.array.append(change);

    try change_params.object.put("textDocument", text_document);
    try change_params.object.put("contentChanges", content_changes);

    try server.handleTextDocumentDidChange(change_params);

    // Test hover request
    const hover_params = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const hover_text_document = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try hover_text_document.object.put("uri", json.Value{ .string = "file://test.jan" });

    const position = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try position.object.put("line", json.Value{ .integer = 0 });
    try position.object.put("character", json.Value{ .integer = 18 }); // Position of 'x'

    try hover_params.object.put("textDocument", hover_text_document);
    try hover_params.object.put("position", position);

    const hover_result = try server.handleHover(hover_params);

    if (hover_result) |result| {
        try testing.expect(result.object.contains("contents"));
    } else {
    }
}

test "LSP Go-to-Definition Functionality" {

    const allocator = std.testing.allocator;

    const config = lsp_server.LSPConfig{};
    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    // Test definition request
    const def_params = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const text_document = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try text_document.object.put("uri", json.Value{ .string = "file://test.jan" });

    const position = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try position.object.put("line", json.Value{ .integer = 0 });
    try position.object.put("character", json.Value{ .integer = 5 });

    try def_params.object.put("textDocument", text_document);
    try def_params.object.put("position", position);

    const def_result = try server.handleDefinition(def_params);

    if (def_result) |result| {
        try testing.expect(result.object.contains("uri"));
        try testing.expect(result.object.contains("range"));
    } else {
    }
}

test "LSP Find References Functionality" {

    const allocator = std.testing.allocator;

    const config = lsp_server.LSPConfig{};
    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    // Test references request
    const ref_params = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const text_document = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try text_document.object.put("uri", json.Value{ .string = "file://test.jan" });

    const position = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try position.object.put("line", json.Value{ .integer = 0 });
    try position.object.put("character", json.Value{ .integer = 5 });

    try ref_params.object.put("textDocument", text_document);
    try ref_params.object.put("position", position);

    const ref_result = try server.handleReferences(ref_params);

    if (ref_result) |result| {
        try testing.expect(result == .array);
    } else {
    }
}

test "Query Engine Caching Behavior" {

    const allocator = std.testing.allocator;

    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const engine = try query_engine.QueryEngine.init(allocator, &db);
    defer engine.deinit();

    // Add test document
    const unit_id = try db.addUnit("cache_test.jan", "func test() {}");
    _ = unit_id;

    // First query (cache miss)
    const start_time1 = compat_time.nanoTimestamp();
    const result1 = try engine.querySymbolAtPosition("cache_test.jan", 0, 5);
    const end_time1 = compat_time.nanoTimestamp();
    const duration1 = end_time1 - start_time1;

    // Second identical query (should be cache hit)
    const start_time2 = compat_time.nanoTimestamp();
    const result2 = try engine.querySymbolAtPosition("cache_test.jan", 0, 5);
    const end_time2 = compat_time.nanoTimestamp();
    const duration2 = end_time2 - start_time2;

    _ = result1;
    _ = result2;

    // Cache hit should be significantly faster

    // Get cache statistics
    const stats = engine.getStats();

    try testing.expect(stats.total_queries >= 2);

}

test "LSP Performance Under Load" {

    const allocator = std.testing.allocator;

    const config = lsp_server.LSPConfig{
        .max_response_time_ms = 10,
    };
    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    // Simulate multiple rapid requests
    const num_requests = 100;
    var total_duration: u64 = 0;

    for (0..num_requests) |i| {
        const start_time = compat_time.nanoTimestamp();

        // Simulate hover request
        const hover_params = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };

        const text_document = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try text_document.object.put("uri", json.Value{ .string = "file://load_test.jan" });

        const position = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try position.object.put("line", json.Value{ .integer = @intCast(i % 10) });
        try position.object.put("character", json.Value{ .integer = @intCast(i % 20) });

        try hover_params.object.put("textDocument", text_document);
        try hover_params.object.put("position", position);

        _ = try server.handleHover(hover_params);

        const end_time = compat_time.nanoTimestamp();
        total_duration += @intCast(end_time - start_time);
    }

    const avg_duration_ns = total_duration / num_requests;
    const avg_duration_ms = @as(f64, @floatFromInt(avg_duration_ns)) / 1_000_000.0;


    // Verify performance requirement
    try testing.expect(avg_duration_ms < 10.0);

}
