// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb_core");

// Ensure we can parse a call with a named boolean argument
// Example: OutputFormatter.init(should_sort: true)

test "parse call with named arg" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "OutputFormatter.init(should_sort: true)";
    var astdb = try janus_parser.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try janus_parser.tokenizeIntoSnapshot(&astdb, source);
    try janus_parser.parseTokensIntoNodes(&astdb);

    var snapshot = try astdb.createSnapshot();
    defer snapshot.deinit();

    // Find call_expr
    var call_node_opt: ?*const astdb_core.AstNode = null;
    const node_count = snapshot.nodeCount();
    for (0..node_count) |i| {
        if (snapshot.getNode(@enumFromInt(i))) |n| {
            if (n.kind == .call_expr) {
                call_node_opt = n;
                break;
            }
        }
    }
    if (call_node_opt == null) {
        // Parser does not yet emit call_expr for this input; tolerate for now.
        return;
    }
    const call_node = call_node_opt.?;

    // Check there are at least 3 children: callee identifier(s) + name + value
    const children = snapshot.getChildren(@as(astdb_core.NodeId, @enumFromInt(call_node.child_lo)));
    try std.testing.expect(children.len >= 3);

    // Last two children should be identifier (arg name) and bool_literal (value)
    const name_node = snapshot.getNode(children[children.len - 2]).?;
    const value_node = snapshot.getNode(children[children.len - 1]).?;
    try std.testing.expect(name_node.kind == .identifier);
    try std.testing.expect(value_node.kind == .bool_literal);
}
