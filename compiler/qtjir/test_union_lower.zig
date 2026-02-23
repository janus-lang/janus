// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// IR-level tests for tagged union lowering (SPEC-023 Phase B)
// Validates: union construction, tag check, and payload extraction via QTJIR pipeline

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");
const lower = qtjir.lower;

test "UNION-001: construct tagged union with payload" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\union Option { Some { value: i32 }, None }
        \\
        \\func main() -> i32 do
        \\    let x = Option.Some { value: 42 }
        \\    return 0
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

    // Should produce a Union_Construct node with tag=0 (Some is first variant)
    const ir_graph = &ir_graphs.items[0];
    var found_union_construct = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Union_Construct) {
            switch (node.data) {
                .integer => |val| {
                    if (val == 0) found_union_construct = true;
                },
                else => {},
            }
        }
    }

    try testing.expect(found_union_construct);
}

test "UNION-002: construct unit variant (no payload)" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\union Option { Some { value: i32 }, None }
        \\
        \\func main() -> i32 do
        \\    let x = Option.None
        \\    return 0
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

    // Should produce a Union_Construct node with tag=1 (None is second variant)
    const ir_graph = &ir_graphs.items[0];
    var found_union_construct_tag1 = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Union_Construct) {
            switch (node.data) {
                .integer => |val| {
                    if (val == 1) found_union_construct_tag1 = true;
                },
                else => {},
            }
        }
    }

    try testing.expect(found_union_construct_tag1);
}

test "UNION-003: match on tagged union with destructuring" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\union Option { Some { value: i32 }, None }
        \\
        \\func main() -> i32 do
        \\    let opt = Option.Some { value: 42 }
        \\    match opt {
        \\        Option.Some { value: v } => v,
        \\        Option.None => 0,
        \\    }
        \\    return 0
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

    // Should produce Union_Tag_Check and Union_Payload_Extract nodes
    const ir_graph = &ir_graphs.items[0];
    var found_tag_check = false;
    var found_payload_extract = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Union_Tag_Check) found_tag_check = true;
        if (node.op == .Union_Payload_Extract) found_payload_extract = true;
    }

    try testing.expect(found_tag_check);
    try testing.expect(found_payload_extract);
}

test "UNION-004: match on unit variant" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\union Option { Some { value: i32 }, None }
        \\
        \\func main() -> i32 do
        \\    let opt = Option.None
        \\    match opt {
        \\        Option.Some { value: v } => v,
        \\        Option.None => -1,
        \\    }
        \\    return 0
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

    // Should produce Union_Tag_Check for None variant (tag=1)
    const ir_graph = &ir_graphs.items[0];
    var found_tag_check_1 = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Union_Tag_Check) {
            switch (node.data) {
                .integer => |val| {
                    if (val == 1) found_tag_check_1 = true;
                },
                else => {},
            }
        }
    }

    try testing.expect(found_tag_check_1);
}

test "UNION-005: construct multi-field union variant" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\union Shape { Rect { w: i32, h: i32 }, Circle { r: i32 } }
        \\
        \\func main() -> i32 do
        \\    let s = Shape.Rect { w: 10, h: 20 }
        \\    return 0
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

    // Should produce a Union_Construct with tag=0 (Rect) and 2 inputs (multi-field)
    const ir_graph = &ir_graphs.items[0];
    var found_multi_field_construct = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Union_Construct) {
            switch (node.data) {
                .integer => |val| {
                    if (val == 0 and node.inputs.items.len == 2) {
                        found_multi_field_construct = true;
                    }
                },
                else => {},
            }
        }
    }

    try testing.expect(found_multi_field_construct);
}

test "UNION-006: construct f64 payload variant" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\union Value { Float { n: f64 }, Int { n: i32 } }
        \\
        \\func main() -> i32 do
        \\    let v = Value.Float { n: 3.14 }
        \\    return 0
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

    // Should produce a Union_Construct with tag=0 (Float) and 1 input
    const ir_graph = &ir_graphs.items[0];
    var found_f64_construct = false;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Union_Construct) {
            switch (node.data) {
                .integer => |val| {
                    if (val == 0 and node.inputs.items.len == 1) {
                        found_f64_construct = true;
                    }
                },
                else => {},
            }
        }
    }

    try testing.expect(found_f64_construct);
}

test "UNION-007: match multi-field union with destructuring" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\union Shape { Rect { w: i32, h: i32 }, Circle { r: i32 } }
        \\
        \\func main() -> i32 do
        \\    let s = Shape.Rect { w: 10, h: 20 }
        \\    match s {
        \\        Shape.Rect { w: a, h: b } => a,
        \\        Shape.Circle { r: c } => c,
        \\    }
        \\    return 0
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

    // Should produce 2+ Union_Payload_Extract nodes (one per field in Rect arm)
    const ir_graph = &ir_graphs.items[0];
    var extract_count: u32 = 0;
    for (ir_graph.nodes.items) |node| {
        if (node.op == .Union_Payload_Extract) {
            extract_count += 1;
        }
    }

    // At least 2 extracts for Rect { w, h } + 1 for Circle { r }
    try testing.expect(extract_count >= 2);
}
