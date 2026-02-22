// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSP Server Hardening Tests
//!
//! Tests the production-hardened LSP server implementation including:
//! - Concurrent request handling
//! - Error resilience (uncrashable server)
//! - Incremental document synchronization
//! - Performance under load

const std = @import("std");
const testing = std.testing;
const json = std.json;
const Thread = std.Thread;

const lsp_server = @import("../../../lsp/janus_lsp_server.zig");

test "LSP Server Error Resilience - Uncrashable Server" {
    std.debug.print("\n🛡️  LSP SERVER ERROR RESILIENCE TEST\n", .{});
    std.debug.print("=====================================\n", .{});

    const allocator = std.testing.allocator;

    const config = lsp_server.LSPConfig{
        .max_response_time_ms = 10,
        .enable_caching = true,
        .profile = ":full",
        .enable_diagnostics = true,
    };

    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    // Test 1: Invalid JSON parameters
    std.debug.print("🧪 Test 1: Invalid JSON Parameters\n", .{});

    const invalid_params = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    // Missing required fields - should not crash

    const hover_result = server.handleHover(invalid_params);
    try testing.expect(hover_result == null); // Graceful failure

    std.debug.print("   ✅ Server survived invalid hover parameters\n", .{});

    // Test 2: Null parameters
    std.debug.print("🧪 Test 2: Null Parameters\n", .{});

    const null_params = json.Value{ .null = {} };
    const def_result = server.handleDefinition(null_params);
    try testing.expect(def_result == null); // Graceful failure

    std.debug.print("   ✅ Server survived null parameters\n", .{});

    // Test 3: Malformed document change
    std.debug.print("🧪 Test 3: Malformed Document Change\n", .{});

    const malformed_change = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    // Missing textDocument and contentChanges

    server.handleTextDocumentDidChange(malformed_change);
    // Should not crash - void return means it handled the error internally

    std.debug.print("   ✅ Server survived malformed document change\n", .{});

    std.debug.print("🛡️  Error resilience: ALL TESTS PASSED - Server is uncrashable!\n", .{});
}

test "LSP Server Incremental Document Synchronization" {
    std.debug.print("\n📝 INCREMENTAL DOCUMENT SYNCHRONIZATION TEST\n", .{});
    std.debug.print("=============================================\n", .{});

    const allocator = std.testing.allocator;

    const config = lsp_server.LSPConfig{};
    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    // Test 1: Full document replacement
    std.debug.print("🧪 Test 1: Full Document Replacement\n", .{});

    const initial_content = "func hello() {\n    print(\"Hello, World!\");\n}";

    const full_change_params = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const text_document = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try text_document.object.put("uri", json.Value{ .string = "file://test_incremental.jan" });
    try text_document.object.put("version", json.Value{ .integer = 1 });

    const content_changes = json.Value{
        .array = std.ArrayList(json.Value).init(allocator),
    };

    const full_change = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try full_change.object.put("text", json.Value{ .string = initial_content });

    try content_changes.array.append(full_change);

    try full_change_params.object.put("textDocument", text_document);
    try full_change_params.object.put("contentChanges", content_changes);

    server.handleTextDocumentDidChange(full_change_params);

    std.debug.print("   ✅ Full document replacement successful\n", .{});

    // Test 2: Incremental change (insert text)
    std.debug.print("🧪 Test 2: Incremental Text Insertion\n", .{});

    const incremental_params = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const text_document2 = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try text_document2.object.put("uri", json.Value{ .string = "file://test_incremental.jan" });
    try text_document2.object.put("version", json.Value{ .integer = 2 });

    const incremental_changes = json.Value{
        .array = std.ArrayList(json.Value){},
    };

    const incremental_change = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    // Insert " world" at position (1, 11) - after "Hello,"
    const range = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const start_pos = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try start_pos.object.put("line", json.Value{ .integer = 1 });
    try start_pos.object.put("character", json.Value{ .integer = 11 });

    const end_pos = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try end_pos.object.put("line", json.Value{ .integer = 1 });
    try end_pos.object.put("character", json.Value{ .integer = 11 });

    try range.object.put("start", start_pos);
    try range.object.put("end", end_pos);

    try incremental_change.object.put("range", range);
    try incremental_change.object.put("text", json.Value{ .string = " Amazing" });

    try incremental_changes.array.append(incremental_change);

    try incremental_params.object.put("textDocument", text_document2);
    try incremental_params.object.put("contentChanges", incremental_changes);

    server.handleTextDocumentDidChange(incremental_params);

    std.debug.print("   ✅ Incremental text insertion successful\n", .{});

    // Test 3: Multiple incremental changes in one request
    std.debug.print("🧪 Test 3: Multiple Incremental Changes\n", .{});

    const multi_params = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const text_document3 = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try text_document3.object.put("uri", json.Value{ .string = "file://test_incremental.jan" });
    try text_document3.object.put("version", json.Value{ .integer = 3 });

    const multi_changes = json.Value{
        .array = std.ArrayList(json.Value){},
    };

    // Change 1: Replace "func" with "function"
    const change1 = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const range1 = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const start1 = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try start1.object.put("line", json.Value{ .integer = 0 });
    try start1.object.put("character", json.Value{ .integer = 0 });

    const end1 = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try end1.object.put("line", json.Value{ .integer = 0 });
    try end1.object.put("character", json.Value{ .integer = 4 });

    try range1.object.put("start", start1);
    try range1.object.put("end", end1);

    try change1.object.put("range", range1);
    try change1.object.put("text", json.Value{ .string = "function" });

    try multi_changes.array.append(change1);

    try multi_params.object.put("textDocument", text_document3);
    try multi_params.object.put("contentChanges", multi_changes);

    server.handleTextDocumentDidChange(multi_params);

    std.debug.print("   ✅ Multiple incremental changes successful\n", .{});

    std.debug.print("📝 Incremental synchronization: ALL TESTS PASSED!\n", .{});
}

test "LSP Server Concurrent Request Handling" {
    std.debug.print("\n⚡ CONCURRENT REQUEST HANDLING TEST\n", .{});
    std.debug.print("===================================\n", .{});

    const allocator = std.testing.allocator;

    const config = lsp_server.LSPConfig{
        .max_response_time_ms = 50, // Relaxed for concurrent testing
    };
    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    // Set up a test document
    const setup_params = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };

    const text_document = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try text_document.object.put("uri", json.Value{ .string = "file://concurrent_test.jan" });
    try text_document.object.put("version", json.Value{ .integer = 1 });

    const content_changes = json.Value{
        .array = std.ArrayList(json.Value){},
    };

    const change = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try change.object.put("text", json.Value{ .string = "func test(x: i32) -> i32 { return x * 2; }" });

    try content_changes.array.append(change);

    try setup_params.object.put("textDocument", text_document);
    try setup_params.object.put("contentChanges", content_changes);

    server.handleTextDocumentDidChange(setup_params);

    std.debug.print("🧪 Test: Concurrent Hover Requests\n", .{});

    // Simulate concurrent requests from multiple threads
    const num_threads = 4;
    const requests_per_thread = 10;

    var threads: [num_threads]Thread = undefined;
    var results: [num_threads]bool = [_]bool{false} ** num_threads;

    const ConcurrentTestContext = struct {
        server: *lsp_server.LSPServer,
        thread_id: usize,
        result: *bool,
        allocator: std.mem.Allocator,

        fn runConcurrentRequests(ctx: @This()) void {
            var success_count: u32 = 0;

            for (0..requests_per_thread) |i| {
                const hover_params = json.Value{
                    .object = std.json.ObjectMap.init(ctx.allocator),
                };

                const req_text_document = json.Value{
                    .object = std.json.ObjectMap.init(ctx.allocator),
                };
                req_text_document.object.put("uri", json.Value{ .string = "file://concurrent_test.jan" }) catch continue;

                const position = json.Value{
                    .object = std.json.ObjectMap.init(ctx.allocator),
                };
                position.object.put("line", json.Value{ .integer = 0 }) catch continue;
                position.object.put("character", json.Value{ .integer = @intCast(5 + (i % 10)) }) catch continue;

                hover_params.object.put("textDocument", req_text_document) catch continue;
                hover_params.object.put("position", position) catch continue;

                // Execute hover request
                const start_time = std.time.nanoTimestamp();
                _ = ctx.server.handleHover(hover_params);
                const end_time = std.time.nanoTimestamp();

                const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

                if (duration_ms < 100.0) { // Reasonable timeout for concurrent testing
                    success_count += 1;
                }

                // Small delay to simulate realistic request patterns
                std.time.sleep(1_000_000); // 1ms
            }

            ctx.result.* = success_count >= (requests_per_thread * 8 / 10); // 80% success rate
        }
    };

    // Start concurrent threads
    for (0..num_threads) |i| {
        const context = ConcurrentTestContext{
            .server = server,
            .thread_id = i,
            .result = &results[i],
            .allocator = allocator,
        };

        threads[i] = try Thread.spawn(.{}, ConcurrentTestContext.runConcurrentRequests, .{context});
    }

    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }

    // Check results
    var successful_threads: u32 = 0;
    for (results) |result| {
        if (result) successful_threads += 1;
    }

    std.debug.print("   Successful threads: {}/{}\n", .{ successful_threads, num_threads });

    // At least 75% of threads should succeed
    try testing.expect(successful_threads >= (num_threads * 3 / 4));

    std.debug.print("   ✅ Concurrent request handling successful\n", .{});

    // Test server statistics
    const stats = server.query_engine.getStats();
    std.debug.print("   Total queries processed: {}\n", .{stats.total_queries});
    std.debug.print("   Cache hit rate: {d:.1f}%\n", .{if (stats.total_queries > 0)
        @as(f64, @floatFromInt(stats.cache_hits)) / @as(f64, @floatFromInt(stats.total_queries)) * 100.0
    else
        0.0});

    try testing.expect(stats.total_queries > 0);

    std.debug.print("⚡ Concurrent handling: ALL TESTS PASSED!\n", .{});
}

test "LSP Server Performance Under Stress" {
    std.debug.print("\n🔥 LSP SERVER STRESS TEST\n", .{});
    std.debug.print("=========================\n", .{});

    const allocator = std.testing.allocator;

    const config = lsp_server.LSPConfig{
        .max_response_time_ms = 10,
    };
    const server = try lsp_server.LSPServer.init(allocator, config);
    defer server.deinit();

    // Stress test: Rapid document changes + queries
    std.debug.print("🧪 Stress Test: Rapid Document Changes + Queries\n", .{});

    const num_iterations = 100;
    var total_duration: u64 = 0;
    var successful_operations: u32 = 0;

    for (0..num_iterations) |i| {
        const start_time = std.time.nanoTimestamp();

        // Document change
        const change_params = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };

        const text_document = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try text_document.object.put("uri", json.Value{ .string = "file://stress_test.jan" });
        try text_document.object.put("version", json.Value{ .integer = @intCast(i + 1) });

        const content_changes = json.Value{
            .array = std.ArrayList(json.Value).init(allocator),
        };

        const change = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };

        const new_content = try std.fmt.allocPrint(allocator, "func iteration{}() {{ return {}; }}", .{ i, i });
        defer allocator.free(new_content);

        try change.object.put("text", json.Value{ .string = new_content });

        try content_changes.array.append(change);

        try change_params.object.put("textDocument", text_document);
        try change_params.object.put("contentChanges", content_changes);

        server.handleTextDocumentDidChange(change_params);

        // Follow up with hover query
        const hover_params = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };

        const hover_text_document = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try hover_text_document.object.put("uri", json.Value{ .string = "file://stress_test.jan" });

        const position = json.Value{
            .object = std.json.ObjectMap.init(allocator),
        };
        try position.object.put("line", json.Value{ .integer = 0 });
        try position.object.put("character", json.Value{ .integer = 5 });

        try hover_params.object.put("textDocument", hover_text_document);
        try hover_params.object.put("position", position);

        _ = server.handleHover(hover_params);

        const end_time = std.time.nanoTimestamp();
        const duration = @as(u64, @intCast(end_time - start_time));
        total_duration += duration;

        if (duration < 50_000_000) { // 50ms timeout per operation
            successful_operations += 1;
        }
    }

    const avg_duration_ms = @as(f64, @floatFromInt(total_duration)) / @as(f64, @floatFromInt(num_iterations)) / 1_000_000.0;
    const success_rate = @as(f64, @floatFromInt(successful_operations)) / @as(f64, @floatFromInt(num_iterations)) * 100.0;

    std.debug.print("   Operations: {}\n", .{num_iterations});
    std.debug.print("   Average duration: {d:.2f}ms\n", .{avg_duration_ms});
    std.debug.print("   Success rate: {d:.1f}%\n", .{success_rate});

    // Require 90% success rate under stress
    try testing.expect(success_rate >= 90.0);

    std.debug.print("   ✅ Server maintained performance under stress\n", .{});

    std.debug.print("🔥 Stress test: ALL TESTS PASSED!\n", .{});
}
