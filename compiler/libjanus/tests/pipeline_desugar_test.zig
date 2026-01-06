// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const libjanus = @import("libjanus");
const astdb = @import("astdb_core");

test "pipeline operator: basic desugaring" {
    const allocator = testing.allocator;
    libjanus.parser.setS0Gate(false);
    const source = "func main() { \"Hello\" |> print() }";

    var p = libjanus.parser.Parser.init(allocator);
    defer p.deinit();

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit = snapshot.astdb_system.units.items[0];

    // Find the call_expr in the AST
    // We expect main -> block -> print("Hello")
    var found_print = false;
    for (unit.nodes) |node| {
        if (node.kind == .call_expr) {
            const edges = unit.edges[node.child_lo..node.child_hi];
            if (edges.len >= 2) {
                const callee = unit.nodes[@intFromEnum(edges[0])];
                if (callee.kind == .identifier) {
                    const sid = unit.tokens[@intFromEnum(callee.first_token)].str.?;
                    const name = snapshot.astdb_system.str_interner.getString(sid);
                    if (std.mem.eql(u8, name, "print")) {
                        // Check if "Hello" is the first argument
                        const arg0 = unit.nodes[@intFromEnum(edges[1])];
                        if (arg0.kind == .string_literal) {
                            const arg_sid = unit.tokens[@intFromEnum(arg0.first_token)].str.?;
                            const arg_val = snapshot.astdb_system.str_interner.getString(arg_sid);
                            if (std.mem.eql(u8, arg_val, "\"Hello\"")) {
                                found_print = true;
                            }
                        }
                    }
                }
            }
        }
    }

    try testing.expect(found_print);
}

test "pipeline operator: chained desugaring" {
    const allocator = testing.allocator;
    libjanus.parser.setS0Gate(false);
    const source = "func main() { 1 |> inc() |> print() }";

    var p = libjanus.parser.Parser.init(allocator);
    defer p.deinit();

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit = snapshot.astdb_system.units.items[0];

    // 1 |> inc() |> print() should become print(inc(1))
    // CallExpr(print, CallExpr(inc, 1))

    var found_print_inc = false;
    for (unit.nodes) |node| {
        if (node.kind == .call_expr) {
            const edges = unit.edges[node.child_lo..node.child_hi];
            if (edges.len < 2) continue;

            const callee = unit.nodes[@intFromEnum(edges[0])];
            const sid = unit.tokens[@intFromEnum(callee.first_token)].str.?;
            const name = snapshot.astdb_system.str_interner.getString(sid);

            if (std.mem.eql(u8, name, "print")) {
                const arg0 = unit.nodes[@intFromEnum(edges[1])];
                if (arg0.kind == .call_expr) {
                    const inner_edges = unit.edges[arg0.child_lo..arg0.child_hi];
                    if (inner_edges.len >= 2) {
                        const inner_callee = unit.nodes[@intFromEnum(inner_edges[0])];
                        const inner_sid = unit.tokens[@intFromEnum(inner_callee.first_token)].str.?;
                        const inner_name = snapshot.astdb_system.str_interner.getString(inner_sid);

                        if (std.mem.eql(u8, inner_name, "inc")) {
                            const inner_arg0 = unit.nodes[@intFromEnum(inner_edges[1])];
                            if (inner_arg0.kind == .integer_literal) {
                                found_print_inc = true;
                            }
                        }
                    }
                }
            }
        }
    }

    try testing.expect(found_print_inc);
}

test "semantic: UFCS argument normalization" {
    const allocator = testing.allocator;
    libjanus.parser.setS0Gate(false);
    const source =
        \\struct Viewer { name: string }
        \\func action(v: Viewer, x: i32) { print(v.name) }
        \\func main() {
        \\    let v = Viewer { name: "Markus" }
        \\    v.action(42)
        \\}
    ;

    var p = libjanus.parser.Parser.init(allocator);
    defer p.deinit();

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();
    const unit = snapshot.astdb_system.units.items[0];

    var graph = try libjanus.semantic.analyzeWithASTDB(snapshot.astdb_system, allocator, .min);
    defer graph.deinit();

    // Find v.action(42) call_expr
    var found_ufcs_call = false;
    for (unit.nodes, 0..) |node, i| {
        if (node.kind == .call_expr) {
            const node_id: libjanus.astdb.NodeId = @enumFromInt(i);
            const edges = unit.edges[node.child_lo..node.child_hi];
            const callee = unit.nodes[@intFromEnum(edges[0])];

            if (callee.kind == .field_expr) {
                // This is the v.action(42) call
                const args = graph.getCallArgs(node_id);
                if (args) |a| {
                    // Expected normalized args: [v, 42]
                    try testing.expect(a.len == 2);

                    // arg0 should be 'v' (the receiver)
                    const receiver_node = unit.nodes[@intFromEnum(a[0])];
                    try testing.expect(receiver_node.kind == .identifier);

                    // arg1 should be 42
                    const lit_node = unit.nodes[@intFromEnum(a[1])];
                    try testing.expect(lit_node.kind == .integer_literal);

                    found_ufcs_call = true;
                }
            }
        }
    }

    try testing.expect(found_ufcs_call);
}
