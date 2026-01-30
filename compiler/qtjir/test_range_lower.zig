// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");
const lower = qtjir.lower;
const graph = qtjir.graph;

test "Lower: Inclusive Range" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    return 1..10
        \\}
    ;

    const snapshot = try p.parseIntoAstDB(&db, "test_range.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Verify Range node
    var found_range = false;
    var is_inclusive = false;

    for (ir_graph.nodes.items) |node| {
        if (node.op == .Range) {
            found_range = true;
            if (node.data == .boolean and node.data.boolean == true) {
                is_inclusive = true;
            }
        }
    }

    try testing.expect(found_range);
    try testing.expect(is_inclusive);
}

test "Lower: Exclusive Range" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    return 1..<10
        \\}
    ;

    const snapshot = try p.parseIntoAstDB(&db, "test_range_ex.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Verify Range node
    var found_range = false;
    var is_exclusive = false;

    // Check strict exclusive
    var found_inclusive = false;

    for (ir_graph.nodes.items) |node| {
        if (node.op == .Range) {
            found_range = true;
            if (node.data == .boolean) {
                if (node.data.boolean == false) {
                    is_exclusive = true;
                } else {
                    found_inclusive = true;
                }
            }
        }
    }

    try testing.expect(found_range);
    try testing.expect(is_exclusive);
    try testing.expect(!found_inclusive);
}
