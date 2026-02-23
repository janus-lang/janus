// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// IR-level tests for zero-capture closure lowering (SPEC-024 Phase A)
// Validates: Fn_Ref node creation, closure graph generation, call dispatch resolution

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");
const lower = qtjir.lower;
const graph = qtjir.graph;

test "CLO-A01: zero-capture closure definition and call" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

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

    // Should produce at least 2 graphs: main + __closure_0
    try testing.expect(ir_graphs.items.len >= 2);

    // Verify Fn_Ref node exists in main graph
    const main_graph = &ir_graphs.items[0];
    var found_fn_ref = false;
    for (main_graph.nodes.items) |node| {
        if (node.op == .Fn_Ref) {
            switch (node.data) {
                .string => |s| {
                    if (std.mem.startsWith(u8, s, "__closure_")) {
                        found_fn_ref = true;
                    }
                },
                else => {},
            }
        }
    }
    try testing.expect(found_fn_ref);

    // Verify Call node targets the closure name (not "double")
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

test "CLO-A02: multiple zero-capture closures generate separate graphs" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() -> i32 do
        \\    let inc = func(x: i32) -> i32 do
        \\        return x + 1
        \\    end
        \\    let dec = func(x: i32) -> i32 do
        \\        return x - 1
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

    // Should produce 3 graphs: main + __closure_0 + __closure_1
    try testing.expect(ir_graphs.items.len >= 3);

    // Verify closure graphs have distinct names
    var closure_count: u32 = 0;
    for (ir_graphs.items) |ir_graph| {
        if (std.mem.startsWith(u8, ir_graph.function_name, "__closure_")) {
            closure_count += 1;
        }
    }
    try testing.expectEqual(@as(u32, 2), closure_count);
}

test "CLO-A03: zero-capture closure with multiple parameters" {
    const allocator = testing.allocator;

    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const source =
        \\func main() -> i32 do
        \\    let add = func(a: i32, b: i32) -> i32 do
        \\        return a + b
        \\    end
        \\    let result = add(10, 32)
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

    // Should produce at least 2 graphs
    try testing.expect(ir_graphs.items.len >= 2);

    // Find the closure graph and verify it has 2 Argument nodes
    var found_closure = false;
    for (ir_graphs.items) |ir_graph| {
        if (std.mem.startsWith(u8, ir_graph.function_name, "__closure_")) {
            var arg_count: u32 = 0;
            for (ir_graph.nodes.items) |node| {
                if (node.op == .Argument) {
                    arg_count += 1;
                }
            }
            try testing.expectEqual(@as(u32, 2), arg_count);
            // Verify parameters metadata
            try testing.expectEqual(@as(usize, 2), ir_graph.parameters.len);
            found_closure = true;
            break;
        }
    }
    try testing.expect(found_closure);
}
