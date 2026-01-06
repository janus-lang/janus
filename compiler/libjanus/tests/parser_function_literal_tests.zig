// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Parser test: function literals { |arg| ... } and do |arg| ... end

const std = @import("std");
const janus_parser = @import("../janus_parser.zig");
const astdb_core = @import("astdb_core");

test "parse block function literal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "let f = { |x| return x }";
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
            if (n.kind == .func_decl) {
                found = true;
                break;
            }
        }
    }
    try std.testing.expect(found);
}

test "parse do-end function literal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "let f = do |x| return x end";
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
            if (n.kind == .func_decl) {
                found = true;
                break;
            }
        }
    }
    try std.testing.expect(found);
}
