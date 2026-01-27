// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! QTJIR Error Handling Lowering Tests
//!
//! Tests that error handling AST nodes lower correctly to QTJIR:
//! - fail statement lowers to Error_Fail_Construct + Return
//! - catch expression lowers to branch with error handling
//! - try operator (?) lowers to propagation logic
//! - Error unions are tracked in lowering context

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb_core");
const qtjir = @import("qtjir");
const lower = qtjir.lower;

// Helper to lower source and return graphs
fn lowerSource(allocator: std.mem.Allocator, source: []const u8) !struct {
    snapshot: *janus_parser.Snapshot,
    graphs: std.ArrayListUnmanaged(qtjir.QTJIRGraph),

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        for (self.graphs.items) |*g| g.deinit();
        self.graphs.deinit(alloc);
        self.snapshot.deinit();
        // Note: snapshot.deinit() destroys itself
    }
} {
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    errdefer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const graphs = try lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);

    return .{
        .snapshot = snapshot,
        .graphs = graphs,
    };
}

test "QTJIR Lowering: fail statement" {
    const allocator = testing.allocator;

    const source =
        \\error DivisionError { DivisionByZero }
        \\
        \\func divide(a: i32, b: i32) -> i32 ! DivisionError {
        \\    if b == 0 {
        \\        fail DivisionError.DivisionByZero
        \\    }
        \\    a / b
        \\}
    ;

    var result = try lowerSource(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(result.graphs.items.len > 0);

    // Find Error_Fail_Construct node
    var found_fail_construct = false;
    var found_return_after_fail = false;

    for (result.graphs.items) |graph| {
        for (graph.nodes.items, 0..) |node, i| {
            if (node.op == .Error_Fail_Construct) {
                found_fail_construct = true;

                // Next node should be Return
                if (i + 1 < graph.nodes.items.len) {
                    const next_node = graph.nodes.items[i + 1];
                    if (next_node.op == .Return) {
                        found_return_after_fail = true;
                    }
                }
            }
        }
    }

    try testing.expect(found_fail_construct);
    try testing.expect(found_return_after_fail);
}

test "QTJIR Lowering: catch expression" {
    const allocator = testing.allocator;

    const source =
        \\error FileError { NotFound }
        \\
        \\func openFile(path: string) -> i32 ! FileError {
        \\    fail FileError.NotFound
        \\}
        \\
        \\func main() -> i32 {
        \\    let handle = openFile("test.txt") catch err {
        \\        -1
        \\    }
        \\    handle
        \\}
    ;

    var result = try lowerSource(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(result.graphs.items.len > 0);

    // Find key nodes for catch expression
    var found_is_error = false;
    var found_branch = false;
    var found_unwrap = false;
    var found_phi = false;

    for (result.graphs.items) |graph| {
        for (graph.nodes.items) |node| {
            switch (node.op) {
                .Error_Union_Is_Error => found_is_error = true,
                .Branch => found_branch = true,
                .Error_Union_Unwrap => found_unwrap = true,
                .Phi => found_phi = true,
                else => {},
            }
        }
    }

    try testing.expect(found_is_error);
    try testing.expect(found_branch);
    try testing.expect(found_unwrap);
    try testing.expect(found_phi);
}

test "QTJIR Lowering: try operator (?)" {
    const allocator = testing.allocator;

    const source =
        \\error NetworkError { Timeout }
        \\
        \\func connect(addr: string) -> i32 ! NetworkError {
        \\    fail NetworkError.Timeout
        \\}
        \\
        \\func wrapper() -> i32 ! NetworkError {
        \\    let conn = connect("127.0.0.1")?
        \\    conn
        \\}
    ;

    var result = try lowerSource(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(result.graphs.items.len > 0);

    // Find key nodes for try operator
    var found_is_error = false;
    var found_branch = false;
    var found_unwrap = false;
    var found_propagate_return = false;

    for (result.graphs.items) |graph| {
        for (graph.nodes.items) |node| {
            switch (node.op) {
                .Error_Union_Is_Error => found_is_error = true,
                .Branch => found_branch = true,
                .Error_Union_Unwrap => found_unwrap = true,
                .Return => {
                    if (node.inputs.items.len > 0) {
                        found_propagate_return = true;
                    }
                },
                else => {},
            }
        }
    }

    try testing.expect(found_is_error);
    try testing.expect(found_branch);
    try testing.expect(found_unwrap);
    try testing.expect(found_propagate_return);
}

test "QTJIR Lowering: error union tracking" {
    const allocator = testing.allocator;

    const source =
        \\error MyError { Fail }
        \\
        \\func mayFail() -> i32 ! MyError {
        \\    if true {
        \\        fail MyError.Fail
        \\    }
        \\    42
        \\}
    ;

    var result = try lowerSource(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(result.graphs.items.len > 0);

    // Verify error union nodes are created
    var found_error_union = false;
    for (result.graphs.items) |graph| {
        for (graph.nodes.items) |node| {
            if (node.op == .Error_Fail_Construct or node.op == .Error_Union_Construct) {
                found_error_union = true;
                break;
            }
        }
    }

    try testing.expect(found_error_union);
}

test "QTJIR Lowering: nested error handling" {
    const allocator = testing.allocator;

    const source =
        \\error Error1 { Fail1 }
        \\error Error2 { Fail2 }
        \\
        \\func inner() -> i32 ! Error1 {
        \\    fail Error1.Fail1
        \\}
        \\
        \\func outer() -> i32 ! Error2 {
        \\    let x = inner() catch err {
        \\        fail Error2.Fail2
        \\    }
        \\    x
        \\}
    ;

    var result = try lowerSource(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(result.graphs.items.len > 0);

    // Count error-related operations
    var fail_count: usize = 0;
    var is_error_count: usize = 0;

    for (result.graphs.items) |graph| {
        for (graph.nodes.items) |node| {
            switch (node.op) {
                .Error_Fail_Construct => fail_count += 1,
                .Error_Union_Is_Error => is_error_count += 1,
                else => {},
            }
        }
    }

    // Should have at least 2 fail constructs (one in inner, one in outer catch)
    try testing.expect(fail_count >= 2);
    // Should have at least 1 is_error check (for catch)
    try testing.expect(is_error_count >= 1);
}
