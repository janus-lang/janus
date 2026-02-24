// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Debug Test: Using Statement AST Structure

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb_core");

test "Debug: using statement AST structure" {
    const allocator = testing.allocator;

    const source =
        \\func open(path: String) -> i32 do
        \\    return 1
        \\end
        \\
        \\func process_file() do
        \\    using file = open("test.txt") do
        \\        return 0
        \\    end
        \\    return 0
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();


    // Find using_resource_stmt nodes
    for (snapshot.core_snapshot.nodes.items, 0..) |node, i| {
        if (node.kind == .using_resource_stmt or node.kind == .using_shared_stmt) {
            
            // Print children
            for (snapshot.core_snapshot.edges.items[node.child_lo..node.child_hi], 0..) |child_edge, j| {
                const child_node = snapshot.core_snapshot.nodes.items[child_edge];
            }
        }
    }

}
