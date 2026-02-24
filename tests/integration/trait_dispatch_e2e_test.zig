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
