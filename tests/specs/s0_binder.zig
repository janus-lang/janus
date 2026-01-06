// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const core = @import("astdb");
const binder = @import("astdb_binder_only");

test "binder: binds functions across multiple units and extracts names from tokens/source" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const A = gpa.allocator();

    var db = try core.AstDB.init(A, true);
    defer db.deinit();

    // Unit 0: with identifier token carrying StrId
    const uid0 = try db.addUnit("u0.jan", "func main(){}\n");
    var unit0 = db.getUnit(uid0).?;
    const a0 = unit0.arenaAllocator();
    // Tokens: func, identifier("main"), '(', ')', '{', '}'
    var toks0 = try a0.alloc(core.Token, 6);
    toks0[0] = .{ .kind = .func, .str = null, .span = .{ .start = 0, .end = 4, .line = 1, .column = 1 }, .trivia_lo = 0, .trivia_hi = 0 };
    const sid_main = try db.internString("main");
    toks0[1] = .{ .kind = .identifier, .str = sid_main, .span = .{ .start = 5, .end = 9, .line = 1, .column = 6 }, .trivia_lo = 0, .trivia_hi = 0 };
    toks0[2] = .{ .kind = .left_paren, .str = null, .span = .{ .start = 9, .end = 10, .line = 1, .column = 10 }, .trivia_lo = 0, .trivia_hi = 0 };
    toks0[3] = .{ .kind = .right_paren, .str = null, .span = .{ .start = 10, .end = 11, .line = 1, .column = 11 }, .trivia_lo = 0, .trivia_hi = 0 };
    toks0[4] = .{ .kind = .left_brace, .str = null, .span = .{ .start = 11, .end = 12, .line = 1, .column = 12 }, .trivia_lo = 0, .trivia_hi = 0 };
    toks0[5] = .{ .kind = .right_brace, .str = null, .span = .{ .start = 12, .end = 13, .line = 1, .column = 13 }, .trivia_lo = 0, .trivia_hi = 0 };
    unit0.tokens = toks0;
    // Nodes: func_decl, block
    var nodes0 = try a0.alloc(core.AstNode, 2);
    nodes0[0] = .{ .kind = .func_decl, .first_token = @enumFromInt(0), .last_token = @enumFromInt(5), .child_lo = 0, .child_hi = 1 };
    nodes0[1] = .{ .kind = .block_stmt, .first_token = @enumFromInt(4), .last_token = @enumFromInt(5), .child_lo = 1, .child_hi = 1 };
    unit0.nodes = nodes0;
    var edges0 = try a0.alloc(core.NodeId, 1);
    edges0[0] = @enumFromInt(1);
    unit0.edges = edges0;

    // Unit 1: identifier token with null str, extract from source
    const src1 = "func other(){}\n";
    const uid1 = try db.addUnit("u1.jan", src1);
    var unit1 = db.getUnit(uid1).?;
    const a1 = unit1.arenaAllocator();
    var toks1 = try a1.alloc(core.Token, 6);
    toks1[0] = .{ .kind = .func, .str = null, .span = .{ .start = 0, .end = 4, .line = 1, .column = 1 }, .trivia_lo = 0, .trivia_hi = 0 };
    toks1[1] = .{ .kind = .identifier, .str = null, .span = .{ .start = 5, .end = 10, .line = 1, .column = 6 }, .trivia_lo = 0, .trivia_hi = 0 }; // "other"
    toks1[2] = .{ .kind = .left_paren, .str = null, .span = .{ .start = 10, .end = 11, .line = 1, .column = 11 }, .trivia_lo = 0, .trivia_hi = 0 };
    toks1[3] = .{ .kind = .right_paren, .str = null, .span = .{ .start = 11, .end = 12, .line = 1, .column = 12 }, .trivia_lo = 0, .trivia_hi = 0 };
    toks1[4] = .{ .kind = .left_brace, .str = null, .span = .{ .start = 12, .end = 13, .line = 1, .column = 13 }, .trivia_lo = 0, .trivia_hi = 0 };
    toks1[5] = .{ .kind = .right_brace, .str = null, .span = .{ .start = 13, .end = 14, .line = 1, .column = 14 }, .trivia_lo = 0, .trivia_hi = 0 };
    unit1.tokens = toks1;
    var nodes1 = try a1.alloc(core.AstNode, 2);
    nodes1[0] = .{ .kind = .func_decl, .first_token = @enumFromInt(0), .last_token = @enumFromInt(5), .child_lo = 0, .child_hi = 1 };
    nodes1[1] = .{ .kind = .block_stmt, .first_token = @enumFromInt(4), .last_token = @enumFromInt(5), .child_lo = 1, .child_hi = 1 };
    unit1.nodes = nodes1;
    var edges1 = try a1.alloc(core.NodeId, 1);
    edges1[0] = @enumFromInt(1);
    unit1.edges = edges1;

    // Bind all
    try binder.bindAll(&db);

    // Assert unit 0 decls
    const uu0 = db.getUnit(uid0).?;
    try testing.expect(uu0.decls.len == 1);
    try testing.expectEqualStrings("main", db.getString(uu0.decls[0].name));

    // Assert unit 1 decls (from source extraction)
    const uu1 = db.getUnit(uid1).?;
    try testing.expect(uu1.decls.len == 1);
    try testing.expectEqualStrings("other", db.getString(uu1.decls[0].name));
}
