// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSP Test Client
//!
//! A simple command-line tool to test the Janus LSP server functionality.
//! This tool can be used to validate LSP operations without requiring
//! a full IDE integration.

const std = @import("std");
const json = std.json;
const print = std.debug.print;

const lsp_server = @import("lsp_server");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 Janus LSP Test Client\n", .{});
    print("========================\n\n", .{});

    // Initialize LSP server
    const config = lsp_server.LSPConfig{
        .max_response_time_ms = 10,
        .enable_caching = true,
        .profile = ":full",
        .enable_diagnostics = true,
    };

    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    print("✅ LSP Server initialized\n", .{});

    // Test 1: Initialize capabilities
    print("\n📋 Test 1: Initialize Capabilities\n", .{});
    print("-----------------------------------\n", .{});

    var init_map = std.json.ObjectMap.init(allocator);
    const init_params = json.Value{ .object = init_map };
    const capabilities = server.handleInitialize(init_params);

    print("Server capabilities:\n", .{});
    if (capabilities.object.get("capabilities")) |caps| {
        if (caps.object.get("hoverProvider")) |hover| {
            print("  - Hover: {}\n", .{hover.bool});
        }
        if (caps.object.get("definitionProvider")) |def| {
            print("  - Go-to-Definition: {}\n", .{def.bool});
        }
        if (caps.object.get("referencesProvider")) |refs| {
            print("  - Find References: {}\n", .{refs.bool});
        }
    }

    // Test 2: Document synchronization
    print("\n📋 Test 2: Document Synchronization\n", .{});
    print("------------------------------------\n", .{});

    const test_source =
        \\func fibonacci(n: i32) -> i32 {
        \\    if n <= 1 {
        \\        return n;
        \\    }
        \\    return fibonacci(n - 1) + fibonacci(n - 2);
        \\}
        \\
        \\func main() {
        \\    let result = fibonacci(10);
        \\    print("Fibonacci(10) = {}", result);
        \\}
    ;

    var change_params_map = std.json.ObjectMap.init(allocator);

    const text_document = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try text_document.object.put("uri", json.Value{ .string = "file://test_fibonacci.jan" });
    try text_document.object.put("version", json.Value{ .integer = 1 });

    var content_changes_arr: std.ArrayList(json.Value) = .empty;
    const content_changes = json.Value{ .array = content_changes_arr };

    var change_map = std.json.ObjectMap.init(allocator);
    try change_map.put("text", json.Value{ .string = test_source });
    try content_changes_arr.append(json.Value{ .object = change_map });

    try change_params_map.put("textDocument", text_document);
    try change_params_map.put("contentChanges", content_changes);
    const change_params = json.Value{ .object = change_params_map };

    try server.handleTextDocumentDidChange(change_params);
    print("✅ Document synchronized: test_fibonacci.jan\n");

    // Test 3: Hover requests
    print("\n📋 Test 3: Hover Requests\n");
    print("--------------------------\n");

    const hover_tests = [_]struct { line: u32, character: u32, description: []const u8 }{
        .{ .line = 0, .character = 5, .description = "function name 'fibonacci'" },
        .{ .line = 0, .character = 15, .description = "parameter 'n'" },
        .{ .line = 8, .character = 8, .description = "variable 'result'" },
        .{ .line = 8, .character = 17, .description = "function call 'fibonacci'" },
    };

    for (hover_tests) |test_case| {
        const hover_params = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };

        const hover_text_document = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try hover_text_document.object.put("uri", json.Value{ .string = "file://test_fibonacci.jan" });

        const position = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try position.object.put("line", json.Value{ .integer = test_case.line });
        try position.object.put("character", json.Value{ .integer = test_case.character });

        try hover_params.object.put("textDocument", hover_text_document);
        try hover_params.object.put("position", position);

        const start_time = std.time.nanoTimestamp();
        const hover_result = try server.handleHover(hover_params);
        const end_time = std.time.nanoTimestamp();

        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        if (hover_result) |result| {
            print("  ✅ Hover at {}:{} ({}): {d:.2f}ms\n", .{ test_case.line, test_case.character, test_case.description, duration_ms });
            if (result.object.get("contents")) |contents| {
                if (contents.object.get("value")) |value| {
                    print("     Content: {s}\n", .{value.string[0..@min(50, value.string.len)]});
                }
            }
        } else {
            print("  ⚠️  Hover at {}:{} ({}): No result ({d:.2f}ms)\n", .{ test_case.line, test_case.character, test_case.description, duration_ms });
        }
    }

    // Test 4: Go-to-Definition requests
    print("\n📋 Test 4: Go-to-Definition Requests\n");
    print("-------------------------------------\n");

    const definition_tests = [_]struct { line: u32, character: u32, description: []const u8 }{
        .{ .line = 4, .character = 15, .description = "recursive call to 'fibonacci'" },
        .{ .line = 8, .character = 17, .description = "call to 'fibonacci'" },
    };

    for (definition_tests) |test_case| {
        const def_params = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };

        const def_text_document = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try def_text_document.object.put("uri", json.Value{ .string = "file://test_fibonacci.jan" });

        const position = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try position.object.put("line", json.Value{ .integer = test_case.line });
        try position.object.put("character", json.Value{ .integer = test_case.character });

        try def_params.object.put("textDocument", def_text_document);
        try def_params.object.put("position", position);

        const start_time = std.time.nanoTimestamp();
        const def_result = try server.handleDefinition(def_params);
        const end_time = std.time.nanoTimestamp();

        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        if (def_result) |result| {
            print("  ✅ Definition at {}:{} ({}): {d:.2f}ms\n", .{ test_case.line, test_case.character, test_case.description, duration_ms });
            if (result.object.get("uri")) |uri| {
                print("     Location: {s}\n", .{uri.string});
            }
        } else {
            print("  ⚠️  Definition at {}:{} ({}): No result ({d:.2f}ms)\n", .{ test_case.line, test_case.character, test_case.description, duration_ms });
        }
    }

    // Test 5: Find References requests
    print("\n📋 Test 5: Find References Requests\n");
    print("------------------------------------\n");

    const references_tests = [_]struct { line: u32, character: u32, description: []const u8 }{
        .{ .line = 0, .character = 5, .description = "all references to 'fibonacci'" },
        .{ .line = 0, .character = 15, .description = "all references to parameter 'n'" },
    };

    for (references_tests) |test_case| {
        const ref_params = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };

        const ref_text_document = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try ref_text_document.object.put("uri", json.Value{ .string = "file://test_fibonacci.jan" });

        const position = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try position.object.put("line", json.Value{ .integer = test_case.line });
        try position.object.put("character", json.Value{ .integer = test_case.character });

        try ref_params.object.put("textDocument", ref_text_document);
        try ref_params.object.put("position", position);

        const start_time = std.time.nanoTimestamp();
        const ref_result = try server.handleReferences(ref_params);
        const end_time = std.time.nanoTimestamp();

        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        if (ref_result) |result| {
            const ref_count = result.array.items.len;
            print("  ✅ References at {}:{} ({}): {} found ({d:.2f}ms)\n", .{ test_case.line, test_case.character, test_case.description, ref_count, duration_ms });
        } else {
            print("  ⚠️  References at {}:{} ({}): No result ({d:.2f}ms)\n", .{ test_case.line, test_case.character, test_case.description, duration_ms });
        }
    }

    // Test 6: Performance summary
    print("\n📊 Performance Summary\n");
    print("----------------------\n");

    const stats = server.query_engine.getStats();
    print("Total queries executed: {}\n", .{stats.total_queries});
    print("Cache hits: {} ({d:.1f}%)\n", .{ stats.cache_hits, @as(f64, @floatFromInt(stats.cache_hits)) / @as(f64, @floatFromInt(stats.total_queries)) * 100.0 });
    print("Cache misses: {} ({d:.1f}%)\n", .{ stats.cache_misses, @as(f64, @floatFromInt(stats.cache_misses)) / @as(f64, @floatFromInt(stats.total_queries)) * 100.0 });
    print("Average response time: {d:.2f}ms\n", .{@as(f64, @floatFromInt(stats.avg_response_time_ns)) / 1_000_000.0});

    if (stats.avg_response_time_ns / 1_000_000 < 10) {
        print("✅ Performance requirement met (<10ms average)\n");
    } else {
        print("⚠️  Performance requirement not met (≥10ms average)\n");
    }

    print("\n🎉 LSP Test Client completed successfully!\n");
}
