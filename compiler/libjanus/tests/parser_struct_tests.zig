// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

const std = @import("std");
const testing = std.testing;
const libjanus = @import("../libjanus.zig");
const astdb_core = @import("astdb_core");

test "parse struct Config { path: string, max_depth: i32 }" {
    const allocator = testing.allocator;
    const source = "struct Config { path: string, max_depth: i32 }";

    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);
    try libjanus.parseTokensIntoNodes(&astdb);

    const snapshot = try astdb.createSnapshot();

    const root_id: astdb_core.NodeId = @enumFromInt(0);
    if (snapshot.getNode(root_id)) |root| {
        try testing.expectEqual(root.kind, astdb_core.AstNode.NodeKind.source_file);

        // Expect one child: struct declaration
        const child_count = root.child_hi - root.child_lo;
        try testing.expectEqual(@as(u32, 1), child_count);

        const struct_id: astdb_core.NodeId = @enumFromInt(root.child_lo);
        if (snapshot.getNode(struct_id)) |struct_node| {
            try testing.expectEqual(struct_node.kind, astdb_core.AstNode.NodeKind.struct_decl);

            // Expect struct has children: Config, left_brace, path, colon, string, comma, max_depth, colon, i32, right_brace
            const struct_child_count = struct_node.child_hi - struct_node.child_lo;
            try testing.expect(struct_child_count >= 9);

            // Check first child is identifier "struct"
            const struct_kw_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo);
            if (snapshot.getNode(struct_kw_id)) |kw_node| {
                try testing.expectEqual(kw_node.kind, astdb_core.AstNode.NodeKind.keyword); // or .struct_kw
            }

            // Check next is identifier "Config"
            const config_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo + 1);
            if (snapshot.getNode(config_id)) |config_node| {
                try testing.expectEqual(config_node.kind, astdb_core.AstNode.NodeKind.identifier);
                // TODO: Verify token text is "Config"
            }

            // Check left_brace
            const lbrace_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo + 2);
            if (snapshot.getNode(lbrace_id)) |lbrace_node| {
                try testing.expectEqual(lbrace_node.kind, astdb_core.AstNode.NodeKind.punctuator); // left_brace
            }

            // Check field "path"
            const path_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo + 3);
            if (snapshot.getNode(path_id)) |path_node| {
                try testing.expectEqual(path_node.kind, astdb_core.AstNode.NodeKind.identifier);
            }

            // Check colon after path
            const colon1_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo + 4);
            if (snapshot.getNode(colon1_id)) |colon1_node| {
                try testing.expectEqual(colon1_node.kind, astdb_core.AstNode.NodeKind.punctuator); // colon
            }

            // Check type "string"
            const string_type_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo + 5);
            if (snapshot.getNode(string_type_id)) |string_type_node| {
                try testing.expectEqual(string_type_node.kind, astdb_core.AstNode.NodeKind.identifier); // or .primitive_type
            }

            // Check comma
            const comma_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo + 6);
            if (snapshot.getNode(comma_id)) |comma_node| {
                try testing.expectEqual(comma_node.kind, astdb_core.AstNode.NodeKind.punctuator); // comma
            }

            // Check field "max_depth"
            const max_depth_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo + 7);
            if (snapshot.getNode(max_depth_id)) |max_depth_node| {
                try testing.expectEqual(max_depth_node.kind, astdb_core.AstNode.NodeKind.identifier);
            }

            // Check colon after max_depth
            const colon2_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo + 8);
            if (snapshot.getNode(colon2_id)) |colon2_node| {
                try testing.expectEqual(colon2_node.kind, astdb_core.AstNode.NodeKind.punctuator); // colon
            }

            // Check type "i32"
            const i32_type_id: astdb_core.NodeId = @enumFromInt(struct_node.child_lo + 9);
            if (snapshot.getNode(i32_type_id)) |i32_type_node| {
                try testing.expectEqual(i32_type_node.kind, astdb_core.AstNode.NodeKind.identifier); // or .primitive_type
            }

            // Check right_brace
            const rbrace_id: astdb_core.NodeId = @enumFromInt(struct_node.child_hi - 1);
            if (snapshot.getNode(rbrace_id)) |rbrace_node| {
                try testing.expectEqual(rbrace_node.kind, astdb_core.AstNode.NodeKind.punctuator); // right_brace
            }
        } else {
            try testing.expect(false); // Should have found struct_decl
        }
    } else {
        try testing.expect(false); // Should have root node
    }
}

test "parse nested struct" {
    const allocator = testing.allocator;
    const source = "struct Inner { value: i32 } struct Outer { inner: Inner }";

    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);
    try libjanus.parseTokensIntoNodes(&astdb);

    const snapshot = try astdb.createSnapshot();

    const root_id: astdb_core.NodeId = @enumFromInt(0);
    if (snapshot.getNode(root_id)) |root| {
        try testing.expectEqual(root.kind, astdb_core.AstNode.NodeKind.source_file);

        // Expect two struct declarations
        const child_count = root.child_hi - root.child_lo;
        try testing.expectEqual(@as(u32, 2), child_count);

        // Check first child is struct Inner
        const inner_struct_id: astdb_core.NodeId = @as(astdb_core.NodeId, @enumFromInt(root.child_lo));
        if (snapshot.getNode(inner_struct_id)) |inner_struct| {
            try testing.expectEqual(inner_struct.kind, astdb_core.AstNode.NodeKind.struct_decl);
        }

        // Check second child is struct Outer with nested field
        const outer_struct_id: astdb_core.NodeId = @enumFromInt(root.child_hi - 1);
        if (snapshot.getNode(outer_struct_id)) |outer_struct| {
            try testing.expectEqual(outer_struct.kind, astdb_core.AstNode.NodeKind.struct_decl);

            // Expect nested struct type for inner field
            // TODO: Verify nested type reference
            const field_count = outer_struct.child_hi - outer_struct.child_lo;
            try testing.expect(field_count >= 3); // inner : Inner , right_brace etc.
        }
    }
}

test "error on invalid struct syntax" {
    const allocator = testing.allocator;
    const invalid_sources = [_][]const u8{
        "struct", // Missing name
        "struct Config {", // Missing right brace
        "struct Config { path: }", // Missing type after colon
        "struct Config { path: string", // Missing comma or right brace
        "struct Config { path: string invalid }", // Invalid token after type
    };

    for (invalid_sources) |source| {
        var astdb = try libjanus.AstDB.init(allocator, true);
        defer astdb.deinit();

        _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);

        // This should fail parsing due to invalid syntax
        const parse_result = libjanus.parseTokensIntoNodes(&astdb);
        try testing.expectError(libjanus.ParseError.UnexpectedToken, parse_result);
    }
}
