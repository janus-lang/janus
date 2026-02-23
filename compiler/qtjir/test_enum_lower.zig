// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// IR-level tests for enum declaration lowering (SPEC-023 Phase A)
// Validates: enum variant access lowers to i32 constant via QTJIR pipeline

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");
const lower = qtjir.lower;

test "ENUM-001: simple enum variant lowers to i32 constant" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\enum Color { Red, Green, Blue }
        \\
        \\func main() -> i32 do
        \\    return Color.Green
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb.UnitId = @enumFromInt(0);
    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    try testing.expect(ir_graphs.items.len > 0);

    // Color.Green should produce a Constant with integer value 1 (0-indexed: Red=0, Green=1, Blue=2)
    const ir_graph = &ir_graphs.items[0];
    var found_constant_1 = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Constant) {
            switch (node.data) {
                .integer => |val| {
                    if (val == 1) found_constant_1 = true;
                },
                else => {},
            }
        }
    }

    try testing.expect(found_constant_1);
}

test "ENUM-002: enum with explicit values lowers correctly" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\enum HttpStatus { Ok = 200, NotFound = 404 }
        \\
        \\func main() -> i32 do
        \\    return HttpStatus.NotFound
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb.UnitId = @enumFromInt(0);
    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    try testing.expect(ir_graphs.items.len > 0);

    // HttpStatus.NotFound should produce a Constant with integer value 404
    const ir_graph = &ir_graphs.items[0];
    var found_constant_404 = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Constant) {
            switch (node.data) {
                .integer => |val| {
                    if (val == 404) found_constant_404 = true;
                },
                else => {},
            }
        }
    }

    try testing.expect(found_constant_404);
}

test "ENUM-003: enum first variant is zero" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\enum Direction { North, South, East, West }
        \\
        \\func main() -> i32 do
        \\    return Direction.North
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb.UnitId = @enumFromInt(0);
    var ir_graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    try testing.expect(ir_graphs.items.len > 0);

    // Direction.North should produce a Constant with integer value 0
    const ir_graph = &ir_graphs.items[0];
    var found_constant_0 = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Constant) {
            switch (node.data) {
                .integer => |val| {
                    if (val == 0) found_constant_0 = true;
                },
                else => {},
            }
        }
    }

    try testing.expect(found_constant_0);
}
