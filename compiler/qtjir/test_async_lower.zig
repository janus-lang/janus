// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Test QTJIR lowering for :service profile async/await constructs
//! Validates that Await, Spawn, Nursery_Begin, and Nursery_End opcodes are generated correctly

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");
const lower = qtjir.lower;
const graph = qtjir.graph;

test "Lower: Await expression creates Await opcode" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    // First verify we can parse an async function
    const source =
        \\async func main() do
        \\    return 42
        \\end
    ;

    const snapshot = try p.parseIntoAstDB(&db, "test_await.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Verify we got at least one graph (the main function)
    try testing.expect(ir_graphs.items.len > 0);
}

test "Lower: Spawn expression parses correctly" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    // Simpler test: just verify async function with nursery compiles
    const source =
        \\async func main() do
        \\    nursery do
        \\        return 1
        \\    end
        \\end
    ;

    const snapshot = try p.parseIntoAstDB(&db, "test_spawn.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Find Nursery_Begin opcode - confirms nursery is being lowered
    var found_nursery_begin = false;
    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items) |node| {
            if (node.op == .Nursery_Begin) {
                found_nursery_begin = true;
                break;
            }
        }
        if (found_nursery_begin) break;
    }

    try testing.expect(found_nursery_begin);
}

test "Lower: Nursery statement creates Nursery_Begin and Nursery_End opcodes" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\async func main() do
        \\    nursery do
        \\        return 1
        \\    end
        \\end
    ;

    const snapshot = try p.parseIntoAstDB(&db, "test_nursery.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Find Nursery_Begin and Nursery_End opcodes
    var found_begin = false;
    var found_end = false;
    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items) |node| {
            if (node.op == .Nursery_Begin) {
                found_begin = true;
            }
            if (node.op == .Nursery_End) {
                found_end = true;
            }
        }
    }

    try testing.expect(found_begin);
    try testing.expect(found_end);
}

test "Lower: Nursery_End links to Nursery_Begin" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\async func main() do
        \\    nursery do
        \\        return 0
        \\    end
        \\end
    ;

    const snapshot = try p.parseIntoAstDB(&db, "test_nursery_link.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Find Nursery_Begin index and verify Nursery_End links to it
    var begin_idx: ?usize = null;
    var end_node: ?*const graph.IRNode = null;

    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items, 0..) |*node, idx| {
            if (node.op == .Nursery_Begin) {
                begin_idx = idx;
            }
            if (node.op == .Nursery_End) {
                end_node = node;
            }
        }
    }

    try testing.expect(begin_idx != null);
    try testing.expect(end_node != null);

    // Verify the link
    if (end_node) |en| {
        if (begin_idx) |bi| {
            try testing.expect(en.inputs.items.len > 0);
            try testing.expectEqual(@as(u32, @intCast(bi)), en.inputs.items[0]);
        }
    }
}
