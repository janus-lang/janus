// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb_core = @import("astdb_core");
const qtjir = @import("qtjir"); // Needs to match module name in build.zig
const parser = @import("janus_parser"); // Needs to match module name in build.zig

const AstDB = astdb_core.AstDB;
const UnitId = astdb_core.UnitId;
const OpCode = qtjir.OpCode;
const lower = qtjir.lower;

fn createTestEnv(allocator: std.mem.Allocator) !*AstDB {
    const db = try allocator.create(AstDB);
    db.* = try AstDB.init(allocator, true);
    return db;
}

test "lower: array literal" {
    const allocator = std.testing.allocator;
    const db = try createTestEnv(allocator);
    defer {
        db.deinit();
        allocator.destroy(db);
    }

    const source =
        \\func main() {
        \\    let arr = [1, 2, 3]
        \\    return 0
        \\}
    ;

    // 1. Setup DB and Parse
    const unit_id = try db.addUnit("test.jan", source);
    var p = parser.Parser.init(allocator);
    defer p.deinit();

    // Parse into the DB
    const parser_snapshot = try p.parseIntoAstDB(db, "test.jan", source);
    const core_snapshot = parser_snapshot.core_snapshot;
    // Note: parser_snapshot destructor handles memory, but here it doesn't own DB
    // so it's fine.

    // 2. Lower
    var ir_graphs = try lower.lowerUnit(allocator, &core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Get the first (and only) graph
    try std.testing.expect(ir_graphs.items.len == 1);
    const ir_graph = &ir_graphs.items[0];

    // 3. Verify Graph Topology
    // Expected:
    // 0: Constant(1)
    // 1: Constant(2)
    // 2: Constant(3)
    // 3: Array_Construct(0, 1, 2)
    // 4: Alloca("arr")
    // 5: Store(3, 4)
    // ... return logic ...

    // Find Array_Construct node
    var array_node_idx: ?usize = null;
    for (ir_graph.nodes.items, 0..) |node, i| {
        if (node.op == .Array_Construct) {
            array_node_idx = i;
            break;
        }
    }

    try std.testing.expect(array_node_idx != null);
    const array_node = &ir_graph.nodes.items[array_node_idx.?];

    // Check inputs (elements)
    try std.testing.expectEqual(@as(usize, 3), array_node.inputs.items.len);

    // Check element values (should be inputs pointing to Constants)
    const elem0_idx = array_node.inputs.items[0];
    const elem0 = &ir_graph.nodes.items[elem0_idx];
    try std.testing.expectEqual(OpCode.Constant, elem0.op);
    try std.testing.expectEqual(@as(i64, 1), elem0.data.integer);
}

test "lower: empty array literal" {
    const allocator = std.testing.allocator;
    const db = try createTestEnv(allocator);
    defer {
        db.deinit();
        allocator.destroy(db);
    }

    const source =
        \\func main() {
        \\    let empty = []
        \\    return 0
        \\}
    ;

    // 1. Setup DB and Parse
    const unit_id = try db.addUnit("test.jan", source);
    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const parser_snapshot = try p.parseIntoAstDB(db, "test.jan", source);
    const core_snapshot = parser_snapshot.core_snapshot;

    // 2. Lower
    var ir_graphs = try lower.lowerUnit(allocator, &core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Get the first (and only) graph
    try std.testing.expect(ir_graphs.items.len == 1);
    const ir_graph = &ir_graphs.items[0];

    // Find Array_Construct node
    var array_node_idx: ?usize = null;
    for (ir_graph.nodes.items, 0..) |node, i| {
        if (node.op == .Array_Construct) {
            array_node_idx = i;
            break;
        }
    }

    try std.testing.expect(array_node_idx != null);
    const array_node = &ir_graph.nodes.items[array_node_idx.?];

    // Check inputs (should be 0)
    try std.testing.expectEqual(@as(usize, 0), array_node.inputs.items.len);
}
