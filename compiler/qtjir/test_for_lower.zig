// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const lower = @import("lower.zig");
const graph = @import("graph.zig");

test "Lower: For Loop Range" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    for i in 0..10 {
        \\         print_int(i)
        \\    }
        \\}
    ;

    const snapshot = try p.parseIntoAstDB(&db, "test_for.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Verification Logic for Phi Loop Structure
    // Expect: Phi, LessEqual, Branch, Body..., Add, Jump(Header)

    var found_phi = false;
    var found_branch = false;
    var found_add = false;
    var found_jump = false;

    for (ir_graph.nodes.items) |node| {
        switch (node.op) {
            .Phi => found_phi = true,
            .Branch => found_branch = true,
            .Add => found_add = true,
            .Jump => found_jump = true,
            else => {},
        }
    }

    try testing.expect(found_phi);
    try testing.expect(found_branch);
    try testing.expect(found_add);
    try testing.expect(found_jump);
}

test "Lower: For Loop Exclusive Range" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    for i in 0..<10 {
        \\         print_int(i)
        \\    }
        \\}
    ;

    const snapshot = try p.parseIntoAstDB(&db, "test_for_ex.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    var found_less = false;

    for (ir_graph.nodes.items) |node| {
        switch (node.op) {
            .Less => found_less = true,
            else => {},
        }
    }
    // Exclusive range should use Less (< 10) instead of LessEqual
    try testing.expect(found_less);
}
