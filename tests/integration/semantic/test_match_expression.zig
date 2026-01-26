// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const libjanus = @import("libjanus");
const astdb_mod = @import("astdb");
// We can access NodeKind via astdb_mod or libjanus re-export
const NodeKind = astdb_mod.AstNode.NodeKind;

test "parser - match expression basic" {
    const allocator = testing.allocator;

    // Initialize Parser
    var parser = libjanus.parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\func test_match() {
        \\    let x = match 42 {
        \\        0 => "zero",
        \\        _ => "other"
        \\    };
        \\}
    ;

    // Parse
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify AST structure
    var found_match = false;
    const count = snapshot.nodeCount();

    var match_node: *const astdb_mod.AstNode = undefined;

    for (0..count) |i| {
        const id: astdb_mod.NodeId = @enumFromInt(i);
        if (snapshot.getNode(id)) |node| {
            if (node.kind == .match_stmt) {
                found_match = true;
                match_node = node;
                break;
            }
        }
    }

    try testing.expect(found_match);

    // Check children count: Value(1) + Arms(2) = 3 children
    const child_count = match_node.child_hi - match_node.child_lo;
    try testing.expectEqual(@as(u32, 3), child_count);
}

test "parser - match expression with do-end" {
    const allocator = testing.allocator;

    var parser = libjanus.parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\func test_match_do() {
        \\    match x do
        \\       1 => true,
        \\       2 => false
        \\    end
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    var found_match = false;
    const count = snapshot.nodeCount();

    for (0..count) |i| {
        const id: astdb_mod.NodeId = @enumFromInt(i);
        if (snapshot.getNode(id)) |node| {
            if (node.kind == .match_stmt) {
                found_match = true;
                break;
            }
        }
    }

    try testing.expect(found_match);
}

test "parser - match expression with guards" {
    const allocator = testing.allocator;

    var parser = libjanus.parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\func test_match_guard() {
        \\    match x {
        \\       n when n > 0 => "pos",
        \\       _ => "zero"
        \\    }
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    var found_match = false;
    const count = snapshot.nodeCount();

    for (0..count) |i| {
        const id: astdb_mod.NodeId = @enumFromInt(i);
        if (snapshot.getNode(id)) |node| {
            if (node.kind == .match_stmt) {
                found_match = true;
                break;
            }
        }
    }

    try testing.expect(found_match);
}
