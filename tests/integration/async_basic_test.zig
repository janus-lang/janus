// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Test async/await syntax parsing for :service profile
//! Phase 1: Week 1 - Basic async function and await expression recognition

const std = @import("std");
const testing = std.testing;
const astdb_core = @import("astdb_core");
const janus_parser = @import("janus_parser");

test "async function declaration parses" {
    const allocator = testing.allocator;

    const source =
        \\async func fetch_data() do
        \\    return 42
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify we got nodes
    try testing.expect(snapshot.core_snapshot.nodeCount() > 0);

    // Find async function declaration node
    var found_async_func = false;
    for (0..snapshot.core_snapshot.nodeCount()) |i| {
        const node_id: astdb_core.NodeId = @enumFromInt(i);
        if (snapshot.core_snapshot.getNode(node_id)) |node| {
            if (node.kind == .async_func_decl) {
                found_async_func = true;
                break;
            }
        }
    }

    try testing.expect(found_async_func);
}

test "await expression parses" {
    const allocator = testing.allocator;

    const source =
        \\async func main() do
        \\    let data = await fetch_data()
        \\    return data
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify we got nodes
    try testing.expect(snapshot.core_snapshot.nodeCount() > 0);

    // Find await expression node
    var found_await = false;
    for (0..snapshot.core_snapshot.nodeCount()) |i| {
        const node_id: astdb_core.NodeId = @enumFromInt(i);
        if (snapshot.core_snapshot.getNode(node_id)) |node| {
            if (node.kind == .await_expr) {
                found_await = true;
                break;
            }
        }
    }

    try testing.expect(found_await);
}

test "regular function still works" {
    const allocator = testing.allocator;

    const source =
        \\func add(a: i64, b: i64) -> i64 do
        \\    return a + b
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify we got nodes
    try testing.expect(snapshot.core_snapshot.nodeCount() > 0);

    // Find regular function declaration node (not async)
    var found_regular_func = false;
    var found_async_func = false;
    for (0..snapshot.core_snapshot.nodeCount()) |i| {
        const node_id: astdb_core.NodeId = @enumFromInt(i);
        if (snapshot.core_snapshot.getNode(node_id)) |node| {
            if (node.kind == .func_decl) {
                found_regular_func = true;
            }
            if (node.kind == .async_func_decl) {
                found_async_func = true;
            }
        }
    }

    try testing.expect(found_regular_func);
    try testing.expect(!found_async_func); // Should NOT find async func
}
