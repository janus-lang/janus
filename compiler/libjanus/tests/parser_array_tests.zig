// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

const std = @import("std");
const janus_parser = @import("../janus_parser.zig");
const astdb_core = @import("../../astdb/core_astdb.zig");

test "parse array literal []T" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "[1, \"zig\"]";
    var astdb = try janus_parser.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try janus_parser.tokenizeIntoSnapshot(&astdb, source);
    try janus_parser.parseTokensIntoNodes(&astdb);

    const snapshot = try astdb.createSnapshot();
    defer snapshot.deinit();

    // Expect source_file > array_lit > integer_literal + string_literal
    const node_count = snapshot.nodeCount();
    try std.testing.expect(node_count >= 3); // source_file, array_lit, children

    const root = snapshot.getNode(.{ .index = 0 });
    try std.testing.expect(root != null);
    try std.testing.expect(root.?.kind == .source_file);

    // Find array_lit node
    var array_node: ?*const astdb_core.AstNode = null;
    for (0..node_count) |i| {
        if (snapshot.getNode(@enumFromInt(i))) |node| {
            if (node.kind == .array_lit) {
                array_node = node;
                break;
            }
        }
    }
    try std.testing.expect(array_node != null);

    // Check array_lit has children
    const children = snapshot.getChildren(@as(astdb_core.NodeId, @enumFromInt(array_node.?.child_lo)));
    try std.testing.expect(children.len == 2); // integer + string

    // First child integer_literal
    const first_child = snapshot.getNode(children[0]);
    try std.testing.expect(first_child != null);
    try std.testing.expect(first_child.?.kind == .integer_literal);

    // Second child string_literal
    const second_child = snapshot.getNode(children[1]);
    try std.testing.expect(second_child != null);
    try std.testing.expect(second_child.?.kind == .string_literal);
}
