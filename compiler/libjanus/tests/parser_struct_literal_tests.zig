// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Parser test: struct literal Type{ field: value }

const std = @import("std");
const janus_parser = @import("../janus_parser.zig");
const astdb_core = @import("astdb_core");

test "parse struct literal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "let c = Config{ path: \".\" }";
    var astdb = try janus_parser.AstDB.init(allocator, true);
    defer astdb.deinit();

    _ = try janus_parser.tokenizeIntoSnapshot(&astdb, source);
    try janus_parser.parseTokensIntoNodes(&astdb);

    var snapshot = try astdb.createSnapshot();
    defer snapshot.deinit();

    var found = false;
    const node_count = snapshot.nodeCount();
    for (0..node_count) |i| {
        if (snapshot.getNode(@enumFromInt(i))) |n| {
            if (n.kind == .struct_literal) {
                found = true;
                break;
            }
        }
    }
    try std.testing.expect(found);
}
