// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Extended tests for ASTDB → QTJIR Lowering (Phase 5 - Task 5.1.2)

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");
const lower = qtjir.lower;
const graph = qtjir.graph;

// TODO: Fix AST structure expectations - binary_expr nodes are flat in function body
// The lowerer works but the test expectations don't match current parser output
// Skipped until AST structure investigation is complete
test "Lower: Basic Arithmetic" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    return 1 + 2;
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "basic.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    // Get root node (last node in unit)
    const unit = db.getUnit(unit_id).?;
    const root_node_id: astdb.NodeId = @enumFromInt(unit.nodes.len - 1);
    const root_node = db.getNode(unit_id, root_node_id).?;

    // Find main function
    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();
    const children = root_node.children(&snapshot);
    var func_node: ?*const astdb.AstNode = null;
    for (children) |child_id| {
        const child = db.getNode(unit_id, child_id).?;
        if (child.kind == .func_decl) {
            func_node = child;
            break;
        }
    }

    try testing.expect(func_node != null);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);

    defer {
        for (ir_graphs.items) |*g| g.deinit();

        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Count Add nodes
    var add_count: usize = 0;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Add) add_count += 1;
    }

    try testing.expectEqual(add_count, 1);
}

// TODO: Fix AST structure expectations - nested expressions need proper child resolution
test "Lower: Nested Expressions" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    // Test (1 + 2) * 3
    const source =
        \\func main() {
        \\    return (1 + 2) * 3;
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "nested.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    // Get root node (last node in unit)
    const unit = db.getUnit(unit_id).?;
    const root_node_id: astdb.NodeId = @enumFromInt(unit.nodes.len - 1);
    const root_node = db.getNode(unit_id, root_node_id).?;

    // Find main function
    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();
    const children = root_node.children(&snapshot);
    var func_node: ?*const astdb.AstNode = null;
    for (children) |child_id| {
        const child = db.getNode(unit_id, child_id).?;
        if (child.kind == .func_decl) {
            func_node = child;
            break;
        }
    }

    try testing.expect(func_node != null);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);

    defer {
        for (ir_graphs.items) |*g| g.deinit();

        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Should have 1 Add and 1 Mul
    var add_count: usize = 0;
    var mul_count: usize = 0;

    for (ir_graph.nodes.items) |node| {
        switch (node.op) {
            .Add => add_count += 1,
            .Mul => mul_count += 1,
            else => {},
        }
    }

    try testing.expectEqual(add_count, 1);
    try testing.expectEqual(mul_count, 1);

    // Verify structure: Mul depends on Add
    // Find Mul node
    var mul_node_idx: ?usize = null;
    for (ir_graph.nodes.items, 0..) |node, i| {
        if (node.op == .Mul) {
            mul_node_idx = i;
            break;
        }
    }

    try testing.expect(mul_node_idx != null);
    const mul_node = ir_graph.nodes.items[mul_node_idx.?];

    // Check inputs of Mul
    var found_add_input = false;
    for (mul_node.inputs.items) |input_id| {
        if (ir_graph.nodes.items[input_id].op == .Add) {
            found_add_input = true;
        }
    }

    try testing.expect(found_add_input);
}

test "Lower: Function Calls" {
    const allocator = testing.allocator;

    var db = try astdb.AstDB.init(allocator, true);
    defer db.deinit();

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() {
        \\    print("Hello", 42)
        \\}
    ;

    _ = try p.parseIntoAstDB(&db, "calls.jan", source);
    const unit_id: astdb.UnitId = @enumFromInt(0);

    // Get root node (last node in unit)
    const unit = db.getUnit(unit_id).?;
    const root_node_id: astdb.NodeId = @enumFromInt(unit.nodes.len - 1);
    const root_node = db.getNode(unit_id, root_node_id).?;

    // Find main function
    var snapshot = db.createSnapshot() catch unreachable;
    defer snapshot.deinit();
    const children = root_node.children(&snapshot);
    var func_node: ?*const astdb.AstNode = null;
    for (children) |child_id| {
        const child = db.getNode(unit_id, child_id).?;
        if (child.kind == .func_decl) {
            func_node = child;
            break;
        }
    }

    try testing.expect(func_node != null);

    var ir_graphs = try lower.lowerUnit(allocator, &snapshot, unit_id);

    defer {
        for (ir_graphs.items) |*g| g.deinit();

        ir_graphs.deinit(allocator);
    }

    const ir_graph = &ir_graphs.items[0];

    // Find Call node
    var call_node_idx: ?usize = null;
    for (ir_graph.nodes.items, 0..) |node, i| {
        if (node.op == .Call) {
            call_node_idx = i;
            break;
        }
    }

    try testing.expect(call_node_idx != null);
    const call_node = ir_graph.nodes.items[call_node_idx.?];

    // Should have 2 inputs (arguments)
    try testing.expectEqual(call_node.inputs.items.len, 2);

    const arg1 = ir_graph.nodes.items[call_node.inputs.items[0]];
    const arg2 = ir_graph.nodes.items[call_node.inputs.items[1]];

    try testing.expectEqual(arg1.op, .Constant); // "Hello"
    try testing.expectEqual(arg2.op, .Constant); // 42
}
