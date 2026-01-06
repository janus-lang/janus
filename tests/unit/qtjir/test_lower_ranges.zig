// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb_core = @import("astdb_core");
const qtjir = @import("qtjir");
const parser = @import("janus_parser");

const AstDB = astdb_core.AstDB;
const UnitId = astdb_core.UnitId;
const OpCode = qtjir.OpCode;
const lower = qtjir.lower;

fn createTestEnv(allocator: std.mem.Allocator) !*AstDB {
    const db = try allocator.create(AstDB);
    db.* = try AstDB.init(allocator, true);
    return db;
}

test "lower: range expression" {
    const allocator = std.testing.allocator;
    const db = try createTestEnv(allocator);
    defer {
        db.deinit();
        allocator.destroy(db);
    }

    const source =
        \\func main() {
        \\    let r = 1..10
        \\    return 0
        \\}
    ;

    const unit_id = try db.addUnit("range.jan", source);
    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const parser_snapshot = try p.parseIntoAstDB(db, "range.jan", source);
    const core_snapshot = parser_snapshot.core_snapshot;

    var ir_graphs = try lower.lowerUnit(allocator, &core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Get the first (and only) graph
    try std.testing.expect(ir_graphs.items.len == 1);
    const ir_graph = &ir_graphs.items[0];

    // Verify Graph Topology
    // Expected:
    // Constant(1)
    // Constant(10)
    // Range(1, 10)
    // Alloca("r")
    // Store(range, alloca)

    var range_node_idx: ?usize = null;
    for (ir_graph.nodes.items, 0..) |node, i| {
        if (node.op == .Range) {
            range_node_idx = i;
            break;
        }
    }

    try std.testing.expect(range_node_idx != null);
    const range_node = &ir_graph.nodes.items[range_node_idx.?];

    try std.testing.expectEqual(@as(usize, 2), range_node.inputs.items.len);

    const start_idx = range_node.inputs.items[0];
    const end_idx = range_node.inputs.items[1];

    const start_node = &ir_graph.nodes.items[start_idx];
    const end_node = &ir_graph.nodes.items[end_idx];

    try std.testing.expectEqual(OpCode.Constant, start_node.op);
    try std.testing.expectEqual(@as(i64, 1), start_node.data.integer);

    try std.testing.expectEqual(OpCode.Constant, end_node.op);
    try std.testing.expectEqual(@as(i64, 10), end_node.data.integer);
}
