// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb_core = @import("astdb_core");
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const qtjir_lower = qtjir.lower;
const qtjir_graph = qtjir.graph;

test "QTJIR: Array literal lowering - basic" {
    const allocator = std.testing.allocator;

    // Source with array literal
    const source = "func main() { let arr = [1, 2, 3] }";

    // Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var graphs = try qtjir_lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (graphs.items) |*g| {
            g.deinit();
        }
        graphs.deinit(allocator);
    }

    // Verify Array_Construct node exists in any of the generated graphs
    var found_array_construct = false;
    for (graphs.items) |*graph| {
        for (graph.nodes.items) |node| {
            if (node.op == .Array_Construct) {
                found_array_construct = true;
                // Should have 3 inputs (elements)
                try std.testing.expectEqual(@as(usize, 3), node.inputs.items.len);
            }
        }
    }

    try std.testing.expect(found_array_construct);
}

test "QTJIR: Array literal lowering - empty array" {
    const allocator = std.testing.allocator;

    const source = "func main() { let arr = [] }";

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var graphs = try qtjir_lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (graphs.items) |*g| {
            g.deinit();
        }
        graphs.deinit(allocator);
    }

    // Verify Array_Construct node with no inputs
    var found_empty_array = false;
    for (graphs.items) |*graph| {
        for (graph.nodes.items) |node| {
            if (node.op == .Array_Construct and node.inputs.items.len == 0) {
                found_empty_array = true;
            }
        }
    }

    try std.testing.expect(found_empty_array);
}

test "QTJIR: Array literal lowering - nested elements" {
    const allocator = std.testing.allocator;

    const source = "func main() { let arr = [1 + 2, 3 * 4] }";

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var graphs = try qtjir_lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (graphs.items) |*g| {
            g.deinit();
        }
        graphs.deinit(allocator);
    }

    // Verify Array_Construct exists with computed elements
    var found_array_with_ops = false;
    var has_add_node = false;
    var has_mul_node = false;

    for (graphs.items) |*graph| {
        for (graph.nodes.items) |node| {
            if (node.op == .Array_Construct and node.inputs.items.len == 2) {
                found_array_with_ops = true;
            }
            if (node.op == .Add) has_add_node = true;
            if (node.op == .Mul) has_mul_node = true;
        }
    }

    try std.testing.expect(found_array_with_ops);
    try std.testing.expect(has_add_node);
    try std.testing.expect(has_mul_node);
}
