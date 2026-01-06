// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb_core = @import("astdb_core");
const qtjir = @import("qtjir");
const parser = @import("janus_parser");

const AstDB = astdb_core.AstDB;
const OpCode = qtjir.OpCode;
const lower = qtjir.lower;

fn createTestEnv(allocator: std.mem.Allocator) !*AstDB {
    const db = try allocator.create(AstDB);
    db.* = try AstDB.init(allocator, true);
    return db;
}

test "lower: std.array.create call" {
    const allocator = std.testing.allocator;
    const db = try createTestEnv(allocator);
    defer {
        db.deinit();
        allocator.destroy(db);
    }

    const source =
        \\func main() {
        \\    let heap_allocator = 0
        \\    let arr = std.array.create(10, heap_allocator)
        \\    return 0
        \\}
    ;

    const unit_id = try db.addUnit("std_array_create.jan", source);
    var p = parser.Parser.init(allocator);
    defer p.deinit();

    // Parse
    const parser_snapshot = try p.parseIntoAstDB(db, "std_array_create.jan", source);
    const core_snapshot = parser_snapshot.core_snapshot;

    // Lower
    var ir_graphs = try lower.lowerUnit(allocator, &core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Get the first (and only) graph
    try std.testing.expect(ir_graphs.items.len == 1);
    const ir_graph = &ir_graphs.items[0];

    // Verify Call node with "std_array_create" data
    var call_node_idx: ?usize = null;
    for (ir_graph.nodes.items, 0..) |node, i| {
        if (node.op == .Call) {
            // Check data string
            if (node.data == .string) {
                if (std.mem.eql(u8, node.data.string, "std_array_create")) {
                    call_node_idx = i;
                    break;
                }
            }
        }
    }

    try std.testing.expect(call_node_idx != null);
    const call_node = &ir_graph.nodes.items[call_node_idx.?];

    // Check inputs (2 args)
    try std.testing.expectEqual(@as(usize, 2), call_node.inputs.items.len);

    // Arg 0 should be 10 (Constant)
    const arg0_idx = call_node.inputs.items[0];
    const arg0 = &ir_graph.nodes.items[arg0_idx];
    try std.testing.expectEqual(OpCode.Constant, arg0.op);
    try std.testing.expectEqual(@as(i64, 10), arg0.data.integer);
}
