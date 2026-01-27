// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! QTJIR Error Handling Opcodes Tests
//!
//! Tests that error handling IR opcodes and builder functions work correctly:
//! - Error_Union_Construct opcode creates success error union
//! - Error_Fail_Construct opcode creates error error union
//! - Error_Union_Is_Error opcode checks error flag
//! - Error_Union_Unwrap opcode extracts payload
//! - Error_Union_Get_Error opcode extracts error value
//! - IRBuilder helper functions create correct nodes

const std = @import("std");
const testing = std.testing;
const qtjir = @import("qtjir");

test "QTJIR: Error_Union_Construct opcode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = qtjir.QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = qtjir.IRBuilder.init(&graph);

    // Create payload value
    const payload = try builder.createConstant(.{ .integer = 42 });

    // Create error union from payload
    const error_union = try builder.createErrorUnionConstruct(payload);

    // Verify node was created
    try testing.expectEqual(qtjir.OpCode.Error_Union_Construct, graph.nodes.items[error_union].op);

    // Verify input is payload
    try testing.expectEqual(@as(usize, 1), graph.nodes.items[error_union].inputs.items.len);
    try testing.expectEqual(payload, graph.nodes.items[error_union].inputs.items[0]);
}

test "QTJIR: Error_Fail_Construct opcode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = qtjir.QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = qtjir.IRBuilder.init(&graph);

    // Create error value
    const error_value = try builder.createConstant(.{ .integer = 1 }); // Error variant ID

    // Create error union from error
    const error_union = try builder.createErrorFailConstruct(error_value);

    // Verify node was created
    try testing.expectEqual(qtjir.OpCode.Error_Fail_Construct, graph.nodes.items[error_union].op);

    // Verify input is error value
    try testing.expectEqual(@as(usize, 1), graph.nodes.items[error_union].inputs.items.len);
    try testing.expectEqual(error_value, graph.nodes.items[error_union].inputs.items[0]);
}

test "QTJIR: Error_Union_Is_Error opcode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = qtjir.QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = qtjir.IRBuilder.init(&graph);

    // Create error union
    const payload = try builder.createConstant(.{ .integer = 42 });
    const error_union = try builder.createErrorUnionConstruct(payload);

    // Check if error
    const is_error = try builder.createErrorUnionIsError(error_union);

    // Verify node was created
    try testing.expectEqual(qtjir.OpCode.Error_Union_Is_Error, graph.nodes.items[is_error].op);

    // Verify input is error union
    try testing.expectEqual(@as(usize, 1), graph.nodes.items[is_error].inputs.items.len);
    try testing.expectEqual(error_union, graph.nodes.items[is_error].inputs.items[0]);
}

test "QTJIR: Error_Union_Unwrap opcode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = qtjir.QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = qtjir.IRBuilder.init(&graph);

    // Create error union
    const payload = try builder.createConstant(.{ .integer = 42 });
    const error_union = try builder.createErrorUnionConstruct(payload);

    // Unwrap payload
    const unwrapped = try builder.createErrorUnionUnwrap(error_union);

    // Verify node was created
    try testing.expectEqual(qtjir.OpCode.Error_Union_Unwrap, graph.nodes.items[unwrapped].op);

    // Verify input is error union
    try testing.expectEqual(@as(usize, 1), graph.nodes.items[unwrapped].inputs.items.len);
    try testing.expectEqual(error_union, graph.nodes.items[unwrapped].inputs.items[0]);
}

test "QTJIR: Error_Union_Get_Error opcode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = qtjir.QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = qtjir.IRBuilder.init(&graph);

    // Create error union from error
    const error_value = try builder.createConstant(.{ .integer = 1 });
    const error_union = try builder.createErrorFailConstruct(error_value);

    // Extract error
    const extracted_error = try builder.createErrorUnionGetError(error_union);

    // Verify node was created
    try testing.expectEqual(qtjir.OpCode.Error_Union_Get_Error, graph.nodes.items[extracted_error].op);

    // Verify input is error union
    try testing.expectEqual(@as(usize, 1), graph.nodes.items[extracted_error].inputs.items.len);
    try testing.expectEqual(error_union, graph.nodes.items[extracted_error].inputs.items[0]);
}

test "QTJIR: Error handling control flow pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = qtjir.QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = qtjir.IRBuilder.init(&graph);

    // Simulate: let x = divide(10, 2) catch err { return -1 }
    //
    // 1. Call divide function (returns error union)
    const arg1 = try builder.createConstant(.{ .integer = 10 });
    const arg2 = try builder.createConstant(.{ .integer = 2 });
    const result = try builder.createCallNamed("divide", &[_]u32{ arg1, arg2 });

    // 2. Check if result is error
    const is_error = try builder.createErrorUnionIsError(result);

    // 3. Create labels for branches
    const error_label = try builder.createLabel(1);
    const success_label = try builder.createLabel(2);

    // 4. Branch on error check
    const branch = try builder.createBranch(is_error, error_label, success_label);

    // 5. Error path: extract error and handle
    const error_value = try builder.createErrorUnionGetError(result);
    const error_return = try builder.createConstant(.{ .integer = -1 });
    _ = try builder.createReturn(error_return);

    // 6. Success path: unwrap payload
    const payload = try builder.createErrorUnionUnwrap(result);
    _ = try builder.createReturn(payload);

    // Verify graph structure
    try testing.expect(graph.nodes.items.len > 0);
    try testing.expectEqual(qtjir.OpCode.Error_Union_Is_Error, graph.nodes.items[is_error].op);
    try testing.expectEqual(qtjir.OpCode.Branch, graph.nodes.items[branch].op);
    try testing.expectEqual(qtjir.OpCode.Error_Union_Get_Error, graph.nodes.items[error_value].op);
    try testing.expectEqual(qtjir.OpCode.Error_Union_Unwrap, graph.nodes.items[payload].op);
}

test "QTJIR: Fail statement pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = qtjir.QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = qtjir.IRBuilder.init(&graph);

    // Simulate: if b == 0 { fail DivisionError.DivisionByZero }
    //
    // 1. Check condition
    const b = try builder.createConstant(.{ .integer = 0 });
    const zero = try builder.createConstant(.{ .integer = 0 });
    const cond = try builder.createBinaryOp(.Equal, b, zero);

    // 2. Create labels
    const fail_label = try builder.createLabel(1);
    const continue_label = try builder.createLabel(2);

    // 3. Branch
    _ = try builder.createBranch(cond, fail_label, continue_label);

    // 4. Fail path: construct error and return
    const error_variant = try builder.createConstant(.{ .integer = 0 }); // DivisionByZero = 0
    const error_union = try builder.createErrorFailConstruct(error_variant);
    _ = try builder.createReturn(error_union);

    // Verify graph structure
    try testing.expectEqual(qtjir.OpCode.Error_Fail_Construct, graph.nodes.items[error_union].op);
}
