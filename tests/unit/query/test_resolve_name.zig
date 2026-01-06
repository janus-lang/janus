// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const query = @import("query");
const astdb = @import("query").astdb;

test "resolveName query" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try astdb.ASTDBSystem.init(allocator, true);
    defer db.deinit();

    // 1. Create a compilation unit
    const unit_id = try db.addUnit("test.jan", "func main() { let x = 42; }");
    const unit = db.getUnit(unit_id).?;

    // 2. Manually construct an AST and symbol table for the test
    // This is a simplified representation of what the parser would do
    const str_x = try db.internString("x");

    const scope_id: astdb.ScopeId = @enumFromInt(0);
    const decl_id: astdb.DeclId = @enumFromInt(0);

    unit.scopes = try unit.arenaAllocator().alloc(astdb.Scope, 1);
    unit.scopes[0] = .{
        .parent = null,
        .first_decl = decl_id,
        .kind = .function,
    };

    unit.decls = try unit.arenaAllocator().alloc(astdb.Decl, 1);
    unit.decls[0] = .{
        .node = @enumFromInt(0),
        .name = str_x,
        .scope = scope_id,
        .kind = .variable,
        .next_in_scope = null,
    };

    // 3. Set up the query context
    var query_ctx = try query.QueryCtx.init(allocator, &.{ .db = &db, .allocator = allocator });
    defer query_ctx.deinit();

    // 4. Create a fake scope CID
    // In a real scenario, this would be computed by the parser/semantic analysis
    var scope_cid: [32]u8 = undefined;
    @memset(&scope_cid, 0);
    const scope_node: astdb.AstNode = .{
        .kind = .func_decl,
        .first_token = @enumFromInt(0),
        .last_token = @enumFromInt(0),
        .child_lo = 0,
        .child_hi = 0,
    };
    unit.nodes = try unit.arenaAllocator().alloc(astdb.AstNode, 1);
    unit.nodes[0] = scope_node;
    unit.cids = try unit.arenaAllocator().alloc([32]u8, 1);
    unit.cids[0] = scope_cid;

    // 5. Execute the resolveName query
    var args = query.CanonicalArgs.init(allocator);
    defer args.deinit();
    try args.append(.{ .string = "x" });
    try args.append(.{ .cid = scope_cid });

    const result = try query_ctx.executeQuery(.ResolveName, args);

    // 6. Verify the result
    const symbol_info = result.data.symbol_info;
    try testing.expectEqualStrings("x", symbol_info.name);
    try testing.expect(symbol_info.definition_cid != undefined);
    try testing.expect(symbol_info.symbol_type == .variable);
}
