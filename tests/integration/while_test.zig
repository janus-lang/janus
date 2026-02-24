// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: While Loop (Iterative Factorial)
//

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "While Loop - Basic Parsing and Lowering" {
    // This test verifies that while loops parse and lower correctly
    // Comprehensive E2E tests are in while_loop_e2e_test.zig

    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var count = 0
        \\    while count < 5 {
        \\        count = count + 1
        \\    }
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify parsing succeeded
    try testing.expect(snapshot.nodeCount() > 0);

    // Lower to QTJIR
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Verify lowering produced IR nodes
    try testing.expect(ir_graphs.items[0].nodes.items.len > 0);

    // Verify we have control flow nodes (Branch, Label, Jump for while loop)
    var has_branch = false;
    var has_label = false;
    var has_jump = false;

    for (ir_graphs.items[0].nodes.items) |node| {
        if (node.op == .Branch) has_branch = true;
        if (node.op == .Label) has_label = true;
        if (node.op == .Jump) has_jump = true;
    }

    try testing.expect(has_branch);
    try testing.expect(has_label);
    try testing.expect(has_jump);

}
