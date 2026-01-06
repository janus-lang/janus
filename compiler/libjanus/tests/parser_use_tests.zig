// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

const std = @import("std");
const testing = std.testing;
const libjanus = @import("../libjanus.zig");
const astdb_core = @import("astdb_core");

test "parse use std.io import statement" {
    const allocator = testing.allocator;
    const source = "use std.io";

    // Create ASTDB system
    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    // Tokenize source into ASTDB
    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);

    // Parse tokens into nodes
    try libjanus.parseTokensIntoNodes(&astdb);

    // Create snapshot
    const snapshot = try astdb.createSnapshot();

    // Get root node (source_file)
    const root_id: astdb_core.NodeId = @enumFromInt(0);
    if (snapshot.getNode(root_id)) |root| {
        try testing.expectEqual(root.kind, astdb_core.AstNode.NodeKind.source_file);

        // Expect one child: use statement
        const child_count = root.child_hi - root.child_lo;
        try testing.expectEqual(@as(u32, 1), child_count);

        const use_stmt_id = @enumFromInt(root.child_lo);
        if (snapshot.getNode(use_stmt_id)) |use_stmt| {
            try testing.expectEqual(use_stmt.kind, astdb_core.AstNode.NodeKind.use_stmt);

            // Expect use_stmt has child path nodes (std . io)
            const path_child_count = use_stmt.child_hi - use_stmt.child_lo;
            try testing.expect(path_child_count >= 2); // std, dot, io at minimum

            // Check first child is identifier "std"
            const std_id = @enumFromInt(use_stmt.child_lo);
            if (snapshot.getNode(std_id)) |std_node| {
                try testing.expectEqual(std_node.kind, astdb_core.AstNode.NodeKind.identifier);
                // TODO: Verify token text is "std" once tokenizer supports 'use'
            }

            // Check next is dot
            const dot_id = @enumFromInt(use_stmt.child_lo + 1);
            if (snapshot.getNode(dot_id)) |dot_node| {
                try testing.expectEqual(dot_node.kind, astdb_core.AstNode.NodeKind.punctuator); // or specific dot kind
            }

            // Check next is identifier "io"
            const io_id = @enumFromInt(use_stmt.child_lo + 2);
            if (snapshot.getNode(io_id)) |io_node| {
                try testing.expectEqual(io_node.kind, astdb_core.AstNode.NodeKind.identifier);
                // TODO: Verify token text is "io"
            }
        } else {
            try testing.expect(false); // Should have found use_stmt
        }
    } else {
        try testing.expect(false); // Should have root node
    }
}

test "parse use jfind.walker import" {
    const allocator = testing.allocator;
    const source = "use jfind.walker";

    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);
    try libjanus.parseTokensIntoNodes(&astdb);

    const snapshot = try astdb.createSnapshot();

    const root_id: astdb_core.NodeId = @enumFromInt(0);
    if (snapshot.getNode(root_id)) |root| {
        try testing.expectEqual(root.kind, astdb_core.AstNode.NodeKind.source_file);

        const child_count = root.child_hi - root.child_lo;
        try testing.expectEqual(@as(u32, 1), child_count);

        const use_stmt_id = @enumFromInt(root.child_lo);
        if (snapshot.getNode(use_stmt_id)) |use_stmt| {
            try testing.expectEqual(use_stmt.kind, astdb_core.AstNode.NodeKind.use_stmt);

            const path_child_count = use_stmt.child_hi - use_stmt.child_lo;
            try testing.expect(path_child_count >= 2); // jfind . walker

            // Check first child "jfind"
            const jfind_id = @enumFromInt(use_stmt.child_lo);
            if (snapshot.getNode(jfind_id)) |jfind_node| {
                try testing.expectEqual(jfind_node.kind, astdb_core.AstNode.NodeKind.identifier);
            }

            // Check dot
            const dot_id = @enumFromInt(use_stmt.child_lo + 1);
            if (snapshot.getNode(dot_id)) |dot_node| {
                try testing.expectEqual(dot_node.kind, astdb_core.AstNode.NodeKind.punctuator);
            }

            // Check "walker"
            const walker_id = @enumFromInt(use_stmt.child_lo + 2);
            if (snapshot.getNode(walker_id)) |walker_node| {
                try testing.expectEqual(walker_node.kind, astdb_core.AstNode.NodeKind.identifier);
            }
        }
    }
}

test "parse use with as alias" {
    const allocator = testing.allocator;
    const source = "use std.io as io";

    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);
    try libjanus.parseTokensIntoNodes(&astdb);

    const snapshot = try astdb.createSnapshot();

    const root_id: astdb_core.NodeId = @enumFromInt(0);
    if (snapshot.getNode(root_id)) |root| {
        try testing.expectEqual(root.kind, astdb_core.AstNode.NodeKind.source_file);

        const child_count = root.child_hi - root.child_lo;
        try testing.expectEqual(@as(u32, 1), child_count);

        const use_stmt_id = @enumFromInt(root.child_lo);
        if (snapshot.getNode(use_stmt_id)) |use_stmt| {
            try testing.expectEqual(use_stmt.kind, astdb_core.AstNode.NodeKind.use_stmt);

            // Expect path + as + alias
            const path_child_count = use_stmt.child_hi - use_stmt.child_lo;
            try testing.expect(path_child_count >= 4); // std . io as io

            // Check last child is identifier "io" (alias)
            const alias_id = @enumFromInt(use_stmt.child_hi - 1);
            if (snapshot.getNode(alias_id)) |alias_node| {
                try testing.expectEqual(alias_node.kind, astdb_core.AstNode.NodeKind.identifier);
                // TODO: Verify token text is "io"
            }

            // Check before alias is 'as' keyword
            const as_id = @enumFromInt(use_stmt.child_hi - 2);
            if (snapshot.getNode(as_id)) |as_node| {
                try testing.expectEqual(as_node.kind, astdb_core.AstNode.NodeKind.keyword); // or specific as kind
            }
        }
    }
}

test "parse multiple use statements" {
    const allocator = testing.allocator;
    const source =
        \\use std.io
        \\use jfind.walker
        \\use jfind.filter;
        \\func main() {}
    ;

    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);
    try libjanus.parseTokensIntoNodes(&astdb);

    const snapshot = try astdb.createSnapshot();

    const root_id: astdb_core.NodeId = @enumFromInt(0);
    if (snapshot.getNode(root_id)) |root| {
        try testing.expectEqual(root.kind, astdb_core.AstNode.NodeKind.source_file);

        const child_count = root.child_hi - root.child_lo;
        try testing.expect(child_count >= 4); // 3 use + func main

        // Check first 3 children are use statements
        for (0..3) |i| {
            const use_id = @enumFromInt(root.child_lo + i);
            if (snapshot.getNode(use_id)) |use_node| {
                try testing.expectEqual(use_node.kind, astdb_core.AstNode.NodeKind.use_stmt);
            }
        }

        // Check last child is function declaration
        const func_id = @enumFromInt(root.child_hi - 1);
        if (snapshot.getNode(func_id)) |func_node| {
            try testing.expectEqual(func_node.kind, astdb_core.AstNode.NodeKind.func_decl);
        }
    }
}

test "parse use zig with module string" {
    const allocator = testing.allocator;
    const source = "use zig \"dvui\";";

    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);
    try libjanus.parseTokensIntoNodes(&astdb);

    const snapshot = try astdb.createSnapshot();
    const root_id: astdb_core.NodeId = @enumFromInt(0);
    if (snapshot.getNode(root_id)) |root| {
        try testing.expectEqual(root.kind, astdb_core.AstNode.NodeKind.source_file);

        const child_count = root.child_hi - root.child_lo;
        try testing.expectEqual(@as(u32, 1), child_count);

        const use_stmt_id = @enumFromInt(root.child_lo);
        if (snapshot.getNode(use_stmt_id)) |use_stmt| {
            try testing.expectEqual(use_stmt.kind, astdb_core.AstNode.NodeKind.use_stmt);
            // Expect origin identifier and module string children
            try testing.expect(use_stmt.child_hi - use_stmt.child_lo >= 2);
        } else {
            try testing.expect(false);
        }
    } else {
        try testing.expect(false);
    }
}

test "parse graft alias equals zig module" {
    const allocator = testing.allocator;
    const source = "graft gui = zig \"dvui\";";

    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);
    try libjanus.parseTokensIntoNodes(&astdb);

    const snapshot = try astdb.createSnapshot();
    const root_id: astdb_core.NodeId = @enumFromInt(0);
    if (snapshot.getNode(root_id)) |root| {
        try testing.expectEqual(root.kind, astdb_core.AstNode.NodeKind.source_file);

        const child_count = root.child_hi - root.child_lo;
        try testing.expectEqual(@as(u32, 1), child_count);

        const use_stmt_id = @enumFromInt(root.child_lo);
        if (snapshot.getNode(use_stmt_id)) |use_stmt| {
            try testing.expectEqual(use_stmt.kind, astdb_core.AstNode.NodeKind.use_stmt);
            // Expect alias identifier, origin identifier, and module string as children
            try testing.expect(use_stmt.child_hi - use_stmt.child_lo >= 3);
        } else {
            try testing.expect(false);
        }
    } else {
        try testing.expect(false);
    }
}

test "error on invalid use syntax" {
    const allocator = testing.allocator;
    const invalid_sources = [_][]const u8{
        "use", // Missing path
        "use 123", // Number instead of identifier
        "use std . io", // Extra space around dot
        "use std.io as", // Missing alias
        "use std.io invalid", // Invalid keyword after as
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
