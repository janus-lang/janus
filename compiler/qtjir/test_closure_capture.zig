// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// IR-level tests for closure capture analysis (SPEC-024 Phase B-a)
// Validates: Closure_Create, Closure_Env_Load, Closure_Call nodes,
// capture detection, and zero-capture regression

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");
const lower = qtjir.lower;
const graph = qtjir.graph;

/// Helper: count nodes with a given opcode in a graph
fn countOp(ir_graph: *const graph.QTJIRGraph, op: graph.OpCode) u32 {
    var count: u32 = 0;
    for (ir_graph.nodes.items) |node| {
        if (node.op == op) count += 1;
    }
    return count;
}

/// Helper: find first node with given opcode
fn findFirst(ir_graph: *const graph.QTJIRGraph, op: graph.OpCode) ?*const graph.IRNode {
    for (ir_graph.nodes.items) |*node| {
        if (node.op == op) return node;
    }
    return null;
}

/// Helper: find closure graph by name prefix
fn findClosureGraph(ir_graphs: []graph.QTJIRGraph) ?*graph.QTJIRGraph {
    for (ir_graphs) |*g| {
        if (std.mem.startsWith(u8, g.function_name, "__closure_")) return g;
    }
    return null;
}

test "CLO-B01: single immutable capture — Closure_Create with 1 input" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    // let x = 42; let f = fn(y: i32) -> i32 do x + y end
    const source =
        \\func main() -> i32 do
        \\    let x = 42
        \\    let f = func(y: i32) -> i32 do
        \\        return x + y
        \\    end
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

    // Should produce at least 2 graphs: main + closure
    try testing.expect(ir_graphs.items.len >= 2);

    const main_graph = &ir_graphs.items[0];

    // Assert: parent graph has Closure_Create (NOT Fn_Ref)
    const closure_create_count = countOp(main_graph, .Closure_Create);
    try testing.expectEqual(@as(u32, 1), closure_create_count);

    // Assert: NO Fn_Ref in parent (replaced by Closure_Create)
    const fn_ref_count = countOp(main_graph, .Fn_Ref);
    try testing.expectEqual(@as(u32, 0), fn_ref_count);

    // Assert: Closure_Create has exactly 1 input (the captured x value)
    const cc_node = findFirst(main_graph, .Closure_Create).?;
    try testing.expectEqual(@as(usize, 1), cc_node.inputs.items.len);

    // Assert: Closure_Create data.string starts with "__closure_"
    switch (cc_node.data) {
        .string => |s| try testing.expect(std.mem.startsWith(u8, s, "__closure_")),
        else => return error.InvalidNode,
    }

    // Assert: closure graph has Closure_Env_Load with index 0
    const closure_g = findClosureGraph(ir_graphs.items).?;
    const env_load_count = countOp(closure_g, .Closure_Env_Load);
    try testing.expectEqual(@as(u32, 1), env_load_count);

    const env_load_node = findFirst(closure_g, .Closure_Env_Load).?;
    try testing.expectEqual(@as(i64, 0), env_load_node.data.integer);

    // Assert: closure graph has captures metadata
    try testing.expectEqual(@as(usize, 1), closure_g.captures.len);
    try testing.expect(std.mem.eql(u8, closure_g.captures[0].name, "x"));
    try testing.expectEqual(@as(u32, 0), closure_g.captures[0].index);
}

test "CLO-B02: multiple captures — Closure_Create with 2 inputs" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    // let a = 1; let b = 2; let f = fn() -> i32 do a + b end
    const source =
        \\func main() -> i32 do
        \\    let a = 1
        \\    let b = 2
        \\    let f = func() -> i32 do
        \\        return a + b
        \\    end
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

    try testing.expect(ir_graphs.items.len >= 2);

    const main_graph = &ir_graphs.items[0];

    // Assert: Closure_Create with 2 inputs (a and b)
    const cc_node = findFirst(main_graph, .Closure_Create).?;
    try testing.expectEqual(@as(usize, 2), cc_node.inputs.items.len);

    // Assert: closure graph has 2 Closure_Env_Load nodes (index 0 and 1)
    const closure_g = findClosureGraph(ir_graphs.items).?;
    const env_load_count = countOp(closure_g, .Closure_Env_Load);
    try testing.expectEqual(@as(u32, 2), env_load_count);

    // Verify indices are 0 and 1
    var found_idx_0 = false;
    var found_idx_1 = false;
    for (closure_g.nodes.items) |node| {
        if (node.op == .Closure_Env_Load) {
            if (node.data.integer == 0) found_idx_0 = true;
            if (node.data.integer == 1) found_idx_1 = true;
        }
    }
    try testing.expect(found_idx_0);
    try testing.expect(found_idx_1);

    // Assert: captures metadata
    try testing.expectEqual(@as(usize, 2), closure_g.captures.len);
}

test "CLO-B03: mixed captured + param — Closure_Call in parent" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    // let x = 10; let f = fn(y: i32) -> i32 do x + y end; f(5)
    const source =
        \\func main() -> i32 do
        \\    let x = 10
        \\    let f = func(y: i32) -> i32 do
        \\        return x + y
        \\    end
        \\    let result = f(5)
        \\    return result
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

    try testing.expect(ir_graphs.items.len >= 2);

    const main_graph = &ir_graphs.items[0];

    // Assert: Closure_Call node in parent (not regular Call for the f(5) invocation)
    const closure_call_count = countOp(main_graph, .Closure_Call);
    try testing.expectEqual(@as(u32, 1), closure_call_count);

    // Assert: Closure_Call has inputs[0] = Closure_Create node + 1 arg
    const cc_call = findFirst(main_graph, .Closure_Call).?;
    try testing.expectEqual(@as(usize, 2), cc_call.inputs.items.len); // closure_id + 1 arg

    // Assert: inputs[0] is the Closure_Create node
    const closure_create_id = cc_call.inputs.items[0];
    const create_node = &main_graph.nodes.items[closure_create_id];
    try testing.expectEqual(graph.OpCode.Closure_Create, create_node.op);

    // Assert: closure graph has 1 Argument (for y, at index 1 since __env is 0)
    // and 1 Closure_Env_Load (for x)
    const closure_g = findClosureGraph(ir_graphs.items).?;

    var user_arg_count: u32 = 0;
    for (closure_g.nodes.items) |node| {
        if (node.op == .Argument) {
            // __env is Argument 0, y is Argument 1
            if (node.data.integer >= 1) user_arg_count += 1;
        }
    }
    try testing.expectEqual(@as(u32, 1), user_arg_count);

    const env_load_count = countOp(closure_g, .Closure_Env_Load);
    try testing.expectEqual(@as(u32, 1), env_load_count);

    // Assert: closure has __env as first parameter
    try testing.expect(closure_g.parameters.len >= 2);
    try testing.expect(std.mem.eql(u8, closure_g.parameters[0].name, "__env"));
}

test "CLO-B04: zero-capture regression — Fn_Ref path still works" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    // Same as CLO-A01: no captures, should produce Fn_Ref (not Closure_Create)
    const source =
        \\func main() -> i32 do
        \\    let double = func(x: i32) -> i32 do
        \\        return x * 2
        \\    end
        \\    let result = double(21)
        \\    return result
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

    try testing.expect(ir_graphs.items.len >= 2);

    const main_graph = &ir_graphs.items[0];

    // Assert: Fn_Ref present (zero-capture path)
    const fn_ref_count = countOp(main_graph, .Fn_Ref);
    try testing.expectEqual(@as(u32, 1), fn_ref_count);

    // Assert: NO Closure_Create (no captures)
    const closure_create_count = countOp(main_graph, .Closure_Create);
    try testing.expectEqual(@as(u32, 0), closure_create_count);

    // Assert: regular Call (not Closure_Call) for the invocation
    const closure_call_count = countOp(main_graph, .Closure_Call);
    try testing.expectEqual(@as(u32, 0), closure_call_count);

    // Assert: closure graph has no captures metadata
    const closure_g = findClosureGraph(ir_graphs.items).?;
    try testing.expectEqual(@as(usize, 0), closure_g.captures.len);

    // Assert: Call targets the closure name
    var found_closure_call = false;
    for (main_graph.nodes.items) |node| {
        if (node.op == .Call) {
            switch (node.data) {
                .string => |s| {
                    if (std.mem.startsWith(u8, s, "__closure_")) {
                        found_closure_call = true;
                    }
                },
                else => {},
            }
        }
    }
    try testing.expect(found_closure_call);
}
