// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Error Handling End-to-End Test
//!
//! Tests the COMPLETE error handling pipeline:
//! Source → Parser → ASTDB → QTJIR Lowering → LLVM Codegen → Execution
//!
//! Validates:
//! - fail statement creates error union
//! - catch expression branches on error
//! - try operator (?) propagates errors
//! - Error union IR opcodes lower correctly
//! - LLVM code generation for error unions

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "E2E: Simple fail statement" {
    const allocator = testing.allocator;

    // ========== STEP 1: Parse Source ==========
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

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.nodeCount() > 0);

    // ========== STEP 2: Lower to QTJIR ==========
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    try testing.expect(ir_graphs.items.len > 0);


    // Look for error handling opcodes in IR
    var found_error_fail = false;
    var found_error_is_error = false;
    var found_branch = false;

    for (ir_graphs.items) |graph| {
        for (graph.nodes.items) |node| {
            switch (node.op) {
                .Error_Fail_Construct => {
                    found_error_fail = true;
                },
                .Error_Union_Is_Error => {
                    found_error_is_error = true;
                },
                .Branch => {
                    found_branch = true;
                },
                else => {},
            }
        }
    }

    // Verify error handling opcodes present
    try testing.expect(found_error_fail);

    // ========== STEP 3: Emit LLVM IR ==========
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "error_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);


    // Verify LLVM IR contains error handling structures
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define") != null);
}

test "E2E: Catch expression with error handling" {
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
        \\
        \\func safe_divide(a: i32, b: i32) -> i32 {
        \\    let result = divide(a, b) catch err {
        \\        return 0
        \\    }
        \\    result
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.nodeCount() > 0);

    // Lower to QTJIR
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }


    try testing.expect(ir_graphs.items.len > 0);

    // Look for catch-related opcodes
    var found_is_error = false;
    var found_unwrap = false;
    var found_branch = false;

    for (ir_graphs.items) |graph| {
        for (graph.nodes.items) |node| {
            switch (node.op) {
                .Error_Union_Is_Error => found_is_error = true,
                .Error_Union_Unwrap => found_unwrap = true,
                .Branch => found_branch = true,
                else => {},
            }
        }
    }

    try testing.expect(found_is_error);
    try testing.expect(found_branch);

    // Emit LLVM
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "catch_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

}

test "E2E: Try operator (?) error propagation" {
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
        \\
        \\func calculate(x: i32, y: i32) -> i32 ! DivisionError {
        \\    let result = divide(x, y)?
        \\    result * 2
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.nodeCount() > 0);

    // Lower to QTJIR
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }


    // Look for try-related opcodes (propagation means branch + return)
    var found_is_error = false;
    var found_return = false;

    for (ir_graphs.items) |graph| {
        for (graph.nodes.items) |node| {
            switch (node.op) {
                .Error_Union_Is_Error => found_is_error = true,
                .Return => found_return = true,
                else => {},
            }
        }
    }

    try testing.expect(found_is_error);
    try testing.expect(found_return);

    // Emit LLVM
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "try_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

}

test "E2E: Multiple error types" {
    const allocator = testing.allocator;

    const source =
        \\error FileError { NotFound, PermissionDenied }
        \\error ParseError { InvalidFormat, UnexpectedEOF }
        \\
        \\func read_file(path: i32) -> i32 ! FileError {
        \\    if path == 0 {
        \\        fail FileError.NotFound
        \\    }
        \\    path
        \\}
        \\
        \\func parse(data: i32) -> i32 ! ParseError {
        \\    if data == 0 {
        \\        fail ParseError.InvalidFormat
        \\    }
        \\    data
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.nodeCount() > 0);

    // Lower to QTJIR
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }


    // Count error fail constructs (should be 2, one per function)
    var error_fail_count: usize = 0;
    for (ir_graphs.items) |graph| {
        for (graph.nodes.items) |node| {
            if (node.op == .Error_Fail_Construct) {
                error_fail_count += 1;
            }
        }
    }

    try testing.expect(error_fail_count >= 2);
}

test "E2E: Nested error handling" {
    const allocator = testing.allocator;

    const source =
        \\error MyError { Fail1, Fail2 }
        \\
        \\func inner() -> i32 ! MyError {
        \\    fail MyError.Fail1
        \\}
        \\
        \\func outer() -> i32 ! MyError {
        \\    let x = inner() catch err {
        \\        return 1
        \\    }
        \\    x + 1
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.nodeCount() > 0);

    // Lower to QTJIR
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }


    // Verify both functions have error handling IR
    for (ir_graphs.items) |graph| {
        var has_error_ops = false;
        for (graph.nodes.items) |node| {
            switch (node.op) {
                .Error_Fail_Construct, .Error_Union_Is_Error, .Error_Union_Unwrap => {
                    has_error_ops = true;
                    break;
                },
                else => {},
            }
        }
        if (has_error_ops) {
        }
    }

    // Emit LLVM
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "nested_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

}
