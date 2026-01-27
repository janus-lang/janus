// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Parser Tests: Error Handling Syntax
//!
//! Tests that the parser correctly recognizes error handling syntax:
//! - error union types (T ! E)
//! - fail statements
//! - catch expressions
//! - try operator (?)

const std = @import("std");
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb_core");

const allocator = std.testing.allocator;

test "Parse error union type: i32 ! DivisionError" {
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\error DivisionError { DivisionByZero }
        \\
        \\func divide(a: i32, b: i32) -> i32 ! DivisionError {
        \\    a / b
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify parsing succeeded
    try std.testing.expect(snapshot.nodeCount() > 0);

    // Look for error_union_type node
    var found_error_union_type = false;
    for (0..snapshot.nodeCount()) |i| {
        const node_id: astdb_core.NodeId = @enumFromInt(i);
        if (snapshot.core_snapshot.getNode(node_id)) |node| {
            if (node.kind == .error_union_type) {
                found_error_union_type = true;
                break;
            }
        }
    }

    try std.testing.expect(found_error_union_type);
}

test "Parse fail statement: fail ErrorType.Variant" {
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

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

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try std.testing.expect(snapshot.nodeCount() > 0);

    // Look for fail_stmt node
    var found_fail_stmt = false;
    for (0..snapshot.nodeCount()) |i| {
        const node_id: astdb_core.NodeId = @enumFromInt(i);
        if (snapshot.core_snapshot.getNode(node_id)) |node| {
            if (node.kind == .fail_stmt) {
                found_fail_stmt = true;
                break;
            }
        }
    }

    try std.testing.expect(found_fail_stmt);
}

test "Parse catch expression: expr catch err { block }" {
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\func main() {
        \\    let x = divide(10, 2) catch err {
        \\        print(-1)
        \\        return
        \\    }
        \\    print(x)
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try std.testing.expect(snapshot.nodeCount() > 0);

    // Look for catch_expr node
    var found_catch_expr = false;
    for (0..snapshot.nodeCount()) |i| {
        const node_id: astdb_core.NodeId = @enumFromInt(i);
        if (snapshot.core_snapshot.getNode(node_id)) |node| {
            if (node.kind == .catch_expr) {
                found_catch_expr = true;
                break;
            }
        }
    }

    try std.testing.expect(found_catch_expr);
}

test "Parse try operator: expr?" {
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\func calculate(x: i32) -> i32 ! DivisionError {
        \\    let result = divide(x, 2)?
        \\    result * 2
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try std.testing.expect(snapshot.nodeCount() > 0);

    // Look for try_expr node
    var found_try_expr = false;
    for (0..snapshot.nodeCount()) |i| {
        const node_id: astdb_core.NodeId = @enumFromInt(i);
        if (snapshot.core_snapshot.getNode(node_id)) |node| {
            if (node.kind == .try_expr) {
                found_try_expr = true;
                break;
            }
        }
    }

    try std.testing.expect(found_try_expr);
}

test "Parse error declaration: error ErrorType { Variant1, Variant2 }" {
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\error FileError {
        \\    NotFound,
        \\    PermissionDenied,
        \\    AlreadyExists,
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try std.testing.expect(snapshot.nodeCount() > 0);

    // Look for error_decl node
    var found_error_decl = false;
    for (0..snapshot.nodeCount()) |i| {
        const node_id: astdb_core.NodeId = @enumFromInt(i);
        if (snapshot.core_snapshot.getNode(node_id)) |node| {
            if (node.kind == .error_decl) {
                found_error_decl = true;
                break;
            }
        }
    }

    try std.testing.expect(found_error_decl);
}

test "Parse complex error handling: nested catch and try" {
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\func complex() -> i32 ! MyError {
        \\    let a = foo()? catch err {
        \\        let b = bar()?
        \\        return b
        \\    }
        \\    a + 1
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try std.testing.expect(snapshot.nodeCount() > 0);

    // Verify both try_expr and catch_expr exist
    var found_try = false;
    var found_catch = false;
    for (0..snapshot.nodeCount()) |i| {
        const node_id: astdb_core.NodeId = @enumFromInt(i);
        if (snapshot.core_snapshot.getNode(node_id)) |node| {
            if (node.kind == .try_expr) found_try = true;
            if (node.kind == .catch_expr) found_catch = true;
        }
    }

    try std.testing.expect(found_try);
    try std.testing.expect(found_catch);
}
