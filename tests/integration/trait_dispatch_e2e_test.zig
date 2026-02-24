// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Trait Static Dispatch (SPEC-025 Phase C Sprint 1)
//
// Validates static dispatch through the lowering pipeline:
// Source -> Parser -> ASTDB -> Lowerer -> QTJIR IR
// Checks: qualified name resolution, Trait_Method_Call emission, default method lowering
//
// NOTE: Parser/snapshot must remain alive while inspecting graph function_name
// because non-impl graphs borrow their name from the string interner.

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const lower = qtjir.lower;
const graph_mod = qtjir.graph;

/// Check if any node in a graph has a given opcode and string data
fn hasNodeWithOp(g: *const graph_mod.QTJIRGraph, op: graph_mod.OpCode, data_str: ?[]const u8) bool {
    for (g.nodes.items) |node| {
        if (node.op == op) {
            if (data_str) |expected| {
                switch (node.data) {
                    .string => |s| {
                        if (std.mem.eql(u8, s, expected)) return true;
                    },
                    else => {},
                }
            } else {
                return true;
            }
        }
    }
    return false;
}

test "TRAIT-001: Impl method lowered with qualified name" {
    const allocator = testing.allocator;

    var p = janus_parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\trait Printable {
        \\    func describe(self) -> i32
        \\}
        \\impl Printable for Point {
        \\    func describe(self) -> i32 do
        \\        return 42
        \\    end
        \\}
        \\func main() -> i32 do
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

    // Graph named Point_Printable_describe must exist
    var found = false;
    for (ir_graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Point_Printable_describe")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "TRAIT-004: Static dispatch via method call emits Trait_Method_Call" {
    const allocator = testing.allocator;

    var p = janus_parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\struct Calc {
        \\    val: i32,
        \\}
        \\trait Adder {
        \\    func add_ten(self, x: i32) -> i32
        \\}
        \\impl Adder for Calc {
        \\    func add_ten(self, x: i32) -> i32 do
        \\        return x + 10
        \\    end
        \\}
        \\func main() -> i32 do
        \\    let c = Calc{ val: 0 }
        \\    let r = c.add_ten(5)
        \\    return r
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

    // The impl graph must exist
    var found_impl = false;
    for (ir_graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Calc_Adder_add_ten")) {
            found_impl = true;
            break;
        }
    }
    try testing.expect(found_impl);

    // The main graph must contain a Trait_Method_Call with "Calc_Adder_add_ten"
    var main_graph: ?*const graph_mod.QTJIRGraph = null;
    for (ir_graphs.items) |*g| {
        if (std.mem.eql(u8, g.function_name, "main")) {
            main_graph = g;
            break;
        }
    }
    const mg = main_graph orelse return error.TestUnexpectedResult;
    try testing.expect(hasNodeWithOp(mg, .Trait_Method_Call, "Calc_Adder_add_ten"));
}

test "TRAIT-008: Default method used when not overridden" {
    const allocator = testing.allocator;

    var p = janus_parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\trait Describable {
        \\    func label(self) -> i32 do
        \\        return 99
        \\    end
        \\}
        \\impl Describable for Thing {
        \\}
        \\func main() -> i32 do
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

    // Default method must be lowered as Thing_Describable_label
    var found = false;
    for (ir_graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Thing_Describable_label")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "TRAIT-009: Default method NOT emitted when impl overrides" {
    const allocator = testing.allocator;

    var p = janus_parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\trait Describable {
        \\    func label(self) -> i32 do
        \\        return 99
        \\    end
        \\}
        \\impl Describable for Thing {
        \\    func label(self) -> i32 do
        \\        return 42
        \\    end
        \\}
        \\func main() -> i32 do
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

    // Should have exactly one Thing_Describable_label graph (from the impl, not default)
    var count: usize = 0;
    for (ir_graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Thing_Describable_label")) count += 1;
    }
    try testing.expectEqual(@as(usize, 1), count);
}

test "TRAIT-010: Disambiguated dispatch with known receiver type" {
    const allocator = testing.allocator;

    var p = janus_parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\struct Point { x: i32 }
        \\struct Circle { r: i32 }
        \\trait Drawable { func draw(self) -> i32 }
        \\impl Drawable for Point {
        \\    func draw(self) -> i32 do
        \\        return 1
        \\    end
        \\}
        \\impl Drawable for Circle {
        \\    func draw(self) -> i32 do
        \\        return 2
        \\    end
        \\}
        \\func main() -> i32 do
        \\    let p = Point{ x: 10 }
        \\    let c = Circle{ r: 5 }
        \\    let a = p.draw()
        \\    let b = c.draw()
        \\    return a + b
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

    // Both impl graphs must exist
    var found_point = false;
    var found_circle = false;
    for (ir_graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Point_Drawable_draw")) found_point = true;
        if (std.mem.eql(u8, g.function_name, "Circle_Drawable_draw")) found_circle = true;
    }
    try testing.expect(found_point);
    try testing.expect(found_circle);

    // Main graph must have BOTH Trait_Method_Call nodes with correct qualified names
    var main_graph: ?*const graph_mod.QTJIRGraph = null;
    for (ir_graphs.items) |*g| {
        if (std.mem.eql(u8, g.function_name, "main")) {
            main_graph = g;
            break;
        }
    }
    const mg = main_graph orelse return error.TestUnexpectedResult;
    try testing.expect(hasNodeWithOp(mg, .Trait_Method_Call, "Point_Drawable_draw"));
    try testing.expect(hasNodeWithOp(mg, .Trait_Method_Call, "Circle_Drawable_draw"));
}

test "TRAIT-011: Sprint 1 behavior preserved for single-impl case" {
    const allocator = testing.allocator;

    var p = janus_parser.Parser.init(allocator);
    defer p.deinit();

    // Single impl — type_map not strictly needed, Sprint 1 heuristic suffices
    const source =
        \\struct Widget {
        \\    id: i32,
        \\}
        \\trait Renderable {
        \\    func render(self) -> i32
        \\}
        \\impl Renderable for Widget {
        \\    func render(self) -> i32 do
        \\        return 7
        \\    end
        \\}
        \\func main() -> i32 do
        \\    let w = Widget{ id: 1 }
        \\    return w.render()
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

    // Impl graph must exist
    var found_impl = false;
    for (ir_graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Widget_Renderable_render")) {
            found_impl = true;
            break;
        }
    }
    try testing.expect(found_impl);

    // Main graph must have Trait_Method_Call
    var main_graph: ?*const graph_mod.QTJIRGraph = null;
    for (ir_graphs.items) |*g| {
        if (std.mem.eql(u8, g.function_name, "main")) {
            main_graph = g;
            break;
        }
    }
    const mg = main_graph orelse return error.TestUnexpectedResult;
    try testing.expect(hasNodeWithOp(mg, .Trait_Method_Call, "Widget_Renderable_render"));
}

test "TRAIT-020: LoweringResult carries trait_meta for vtable construction" {
    const allocator = testing.allocator;

    var p = janus_parser.Parser.init(allocator);
    defer p.deinit();

    // Two impls of the same trait — verifies trait_meta survives in LoweringResult
    // and contains correct data for vtable spec construction.
    const source =
        \\struct Point { x: i32 }
        \\struct Circle { r: i32 }
        \\trait Drawable { func draw(self) -> i32 }
        \\impl Drawable for Point {
        \\    func draw(self) -> i32 do
        \\        return 1
        \\    end
        \\}
        \\impl Drawable for Circle {
        \\    func draw(self) -> i32 do
        \\        return 2
        \\    end
        \\}
        \\func main() -> i32 do
        \\    let p = Point{ x: 10 }
        \\    return p.draw()
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var result = try lower.lowerUnitWithExterns(allocator, &snapshot.core_snapshot, unit_id, null);
    defer result.deinit(allocator);

    // Verify trait_meta is populated (Sprint 3D: meta transfers to LoweringResult)
    try testing.expect(result.trait_meta != null);
    const meta = &result.trait_meta.?;

    // Verify trait definition exists
    try testing.expect(meta.traits.get("Drawable") != null);
    const trait_def = meta.traits.get("Drawable").?;
    try testing.expectEqual(@as(usize, 1), trait_def.methods.items.len);
    try testing.expect(std.mem.eql(u8, trait_def.methods.items[0].name, "draw"));

    // Verify two impls exist
    try testing.expectEqual(@as(usize, 2), meta.impls.items.len);

    // Verify impl entries have correct qualified names for vtable construction
    var found_point = false;
    var found_circle = false;
    for (meta.impls.items) |impl_entry| {
        if (std.mem.eql(u8, impl_entry.type_name, "Point")) {
            try testing.expect(impl_entry.trait_name != null);
            try testing.expect(std.mem.eql(u8, impl_entry.trait_name.?, "Drawable"));
            try testing.expectEqual(@as(usize, 1), impl_entry.methods.items.len);
            try testing.expect(std.mem.eql(u8, impl_entry.methods.items[0].qualified_name, "Point_Drawable_draw"));
            found_point = true;
        } else if (std.mem.eql(u8, impl_entry.type_name, "Circle")) {
            try testing.expect(impl_entry.trait_name != null);
            try testing.expect(std.mem.eql(u8, impl_entry.trait_name.?, "Drawable"));
            try testing.expectEqual(@as(usize, 1), impl_entry.methods.items.len);
            try testing.expect(std.mem.eql(u8, impl_entry.methods.items[0].qualified_name, "Circle_Drawable_draw"));
            found_circle = true;
        }
    }
    try testing.expect(found_point);
    try testing.expect(found_circle);

    // Verify impl function graphs were emitted
    var found_point_graph = false;
    var found_circle_graph = false;
    for (result.graphs.items) |g| {
        if (std.mem.eql(u8, g.function_name, "Point_Drawable_draw")) found_point_graph = true;
        if (std.mem.eql(u8, g.function_name, "Circle_Drawable_draw")) found_circle_graph = true;
    }
    try testing.expect(found_point_graph);
    try testing.expect(found_circle_graph);
}

test "TRAIT-030: &dyn Trait binding emits Vtable_Construct and dynamic dispatch" {
    const allocator = testing.allocator;

    var p = janus_parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\struct Point { x: i32 }
        \\trait Drawable { func draw(self) -> i32 }
        \\impl Drawable for Point {
        \\    func draw(self) -> i32 do
        \\        return 1
        \\    end
        \\}
        \\func main() -> i32 do
        \\    let p: &dyn Drawable = Point{ x: 10 }
        \\    return p.draw()
        \\end
    ;

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit_id: astdb.UnitId = @enumFromInt(0);

    var result = try lower.lowerUnitWithExterns(allocator, &snapshot.core_snapshot, unit_id, null);
    defer result.deinit(allocator);

    // Find the main graph
    var main_graph: ?*const graph_mod.QTJIRGraph = null;
    for (result.graphs.items) |*g| {
        if (std.mem.eql(u8, g.function_name, "main")) {
            main_graph = g;
            break;
        }
    }
    const mg = main_graph orelse return error.TestUnexpectedResult;

    // Vtable_Construct must exist with key "Point_Drawable"
    try testing.expect(hasNodeWithOp(mg, .Vtable_Construct, "Point_Drawable"));

    // Vtable_Lookup must exist with slot index 0
    var found_lookup = false;
    for (mg.nodes.items) |node| {
        if (node.op == .Vtable_Lookup) {
            switch (node.data) {
                .integer => |i| {
                    if (i == 0) found_lookup = true;
                },
                else => {},
            }
        }
    }
    try testing.expect(found_lookup);

    // Vtable_Lookup's first input must be the Vtable_Construct node
    for (mg.nodes.items) |node| {
        if (node.op == .Vtable_Lookup and node.inputs.items.len >= 1) {
            const construct_ref = node.inputs.items[0];
            const construct_node = mg.nodes.items[construct_ref];
            try testing.expectEqual(graph_mod.OpCode.Vtable_Construct, construct_node.op);
            break;
        }
    }
}
