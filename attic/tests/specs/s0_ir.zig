// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

const core = @import("astdb_core");
const IRGen = @import("libjanus_ir_generator");
const binder = @import("astdb_core");
const janus_parser = @import("janus_parser");

test "S0 IR: generate IR for minimal main()" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const A = gpa.allocator();

    // Build minimal ASTDB unit with func_decl → block_stmt
    var db = try core.AstDB.init(A, true);
    defer db.deinit();

    const unit_id = try db.addUnit("s0.jan", "");
    var unit = db.getUnit(unit_id).?;
    const arena = unit.arenaAllocator();

    // Nodes: [func_decl, block_stmt]
    var nodes = try arena.alloc(core.AstNode, 2);
    nodes[0] = core.AstNode{
        .kind = .func_decl,
        .first_token = @enumFromInt(0),
        .last_token = @enumFromInt(0),
        .child_lo = 0,
        .child_hi = 1,
    };
    nodes[1] = core.AstNode{
        .kind = .block_stmt,
        .first_token = @enumFromInt(0),
        .last_token = @enumFromInt(0),
        .child_lo = 1,
        .child_hi = 1,
    };
    unit.nodes = nodes;

    // Edges: func_decl → block_stmt (node id 1)
    var edges = try arena.alloc(core.NodeId, 1);
    edges[0] = @enumFromInt(1);
    unit.edges = edges;

    // Scopes: one global scope
    var scopes = try arena.alloc(core.Scope, 1);
    scopes[0] = core.Scope{ .parent = null, .first_decl = null, .kind = .global };
    unit.scopes = scopes;

    // Decls: one function decl for node 0 named "main"
    const name_sid = try db.internString("main");
    var decls = try arena.alloc(core.Decl, 1);
    decls[0] = core.Decl{
        .node = @enumFromInt(0),
        .name = name_sid,
        .scope = @enumFromInt(0),
        .kind = .function,
        .next_in_scope = null,
    };
    unit.decls = decls;
    unit.scopes[0].first_decl = @enumFromInt(0);

    // Bind decls automatically
    // try binder.bindUnit(&db, unit_id); // Removed: astdb_binder_only module removed
    // Snapshot
    const core_snap = try db.createSnapshot();
    var snap_ptr = try A.create(janus_parser.Snapshot);
    snap_ptr.* = janus_parser.Snapshot{
        .core_snapshot = core_snap,
        .astdb_system = &db,
        .allocator = A,
    };
    defer { snap_ptr.deinit(); A.destroy(snap_ptr); }

    // IR Generation
    var irg = try IRGen.IRGenerator.init(A, snap_ptr, &db);
    defer irg.deinit();
    var ir = try irg.generateIR(unit_id, @enumFromInt(0));
    defer ir.deinit(A);

    try testing.expect(ir.basic_blocks.len > 0);
    try testing.expectEqualStrings("main", ir.function_name);
    try testing.expect(ir.parameters.len == 0);
}
