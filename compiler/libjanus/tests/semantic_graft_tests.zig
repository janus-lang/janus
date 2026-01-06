// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const libjanus = @import("../libjanus.zig");
const semantic = @import("../libjanus_semantic.zig");

test "semantic collects graft alias = zig \"module\"" {
    const allocator = testing.allocator;
    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    const source = "graft gui = zig \"dvui\";";
    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);
    try libjanus.parseTokensIntoNodes(&astdb);

    var graph = try semantic.analyzeWithASTDB(&astdb, allocator);
    defer graph.deinit();

    try testing.expect(graph.foreign_grafts.items.len >= 1);
    const g = graph.foreign_grafts.items[0];
    try testing.expect(g.alias != null);
    if (g.alias) |sid| {
        const alias = graph.astdb_system.str_interner.getString(sid);
        try testing.expectEqualStrings("gui", alias);
    }
    const origin = graph.astdb_system.str_interner.getString(g.origin);
    try testing.expectEqualStrings("zig", origin);
    try testing.expectEqualStrings("dvui", g.module);
}

test "semantic collects use zig \"module\"" {
    const allocator = testing.allocator;
    var astdb = try libjanus.AstDB.init(allocator, true);
    defer astdb.deinit();

    const source = "use zig \"capy\";";
    _ = try libjanus.tokenizeIntoSnapshot(&astdb, source);
    try libjanus.parseTokensIntoNodes(&astdb);

    var graph = try semantic.analyzeWithASTDB(&astdb, allocator);
    defer graph.deinit();

    try testing.expect(graph.foreign_grafts.items.len >= 1);
    const g = graph.foreign_grafts.items[0];
    try testing.expect(g.alias == null);
    const origin = graph.astdb_system.str_interner.getString(g.origin);
    try testing.expectEqualStrings("zig", origin);
    try testing.expectEqualStrings("capy", g.module);
}
