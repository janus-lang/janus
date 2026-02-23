// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// LLVM-C Emitter Tests

const std = @import("std");
const testing = std.testing;
const graph_mod = @import("graph.zig");
const LLVMEmitter = @import("llvm_emitter.zig").LLVMEmitter;

const QTJIRGraph = graph_mod.QTJIRGraph;
const IRBuilder = graph_mod.IRBuilder;

test "LLVM Emitter: Hello World" {
    const allocator = testing.allocator;

    // Create QTJIR graph (main → returns i32 by default)
    var ir_graph = QTJIRGraph.initWithName(allocator, "main");
    defer ir_graph.deinit();

    var builder = IRBuilder.init(&ir_graph);

    // Create string constant — Sovereign Graph: dupe static literal
    const owned_str = try ir_graph.allocator.dupeZ(u8, "Hello, LLVM!");
    const str_node = try builder.createConstant(.{ .string = owned_str });

    // Create call to janus_println (must set data.string for emitCall dispatch)
    const call_node = try builder.createCall(&[_]u32{str_node});
    ir_graph.nodes.items[call_node].data = .{
        .string = try ir_graph.allocator.dupeZ(u8, "janus_println"),
    };

    // Create return (main returns i32, so return 0)
    const zero = try builder.createConstant(.{ .integer = 0 });
    _ = try builder.createReturn(zero);

    // Emit to LLVM
    var emitter = try LLVMEmitter.init(allocator, "test");
    defer emitter.deinit();

    try emitter.emit(&[_]QTJIRGraph{ir_graph});

    // Get IR as string
    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);

    // main returns i32 (default convention)
    try testing.expect(std.mem.indexOf(u8, ir_str, "define i32 @main()") != null);
    try testing.expect(std.mem.indexOf(u8, ir_str, "Hello, LLVM!") != null);
}

test "LLVM Emitter: Arithmetic" {
    const allocator = testing.allocator;

    // Create QTJIR graph for: 2 + 3
    var ir_graph = QTJIRGraph.initWithName(allocator, "add_test");
    defer ir_graph.deinit();

    var builder = IRBuilder.init(&ir_graph);

    // Create constants
    const lhs = try builder.createConstant(.{ .integer = 2 });
    const rhs = try builder.createConstant(.{ .integer = 3 });

    // Create add
    const add_node = try builder.createNode(.Add);
    var add_ir_node = &ir_graph.nodes.items[add_node];
    try add_ir_node.inputs.append(allocator, lhs);
    try add_ir_node.inputs.append(allocator, rhs);

    // Create return with add result
    const ret_node = try builder.createNode(.Return);
    var ret_ir_node = &ir_graph.nodes.items[ret_node];
    try ret_ir_node.inputs.append(allocator, add_node);

    // Emit to LLVM
    var emitter = try LLVMEmitter.init(allocator, "test");
    defer emitter.deinit();

    try emitter.emit(&[_]QTJIRGraph{ir_graph});

    // Get IR as string
    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);

    // Non-main functions with default return_type="i32" get i32 return
    try testing.expect(std.mem.indexOf(u8, ir_str, "define i32 @add_test()") != null);
}

test "LLVM Emitter: All Operations" {
    const allocator = testing.allocator;

    // Test Add, Sub, Mul, Div
    const ops = [_]graph_mod.OpCode{ .Add, .Sub, .Mul, .Div };

    for (ops) |op| {
        var ir_graph = QTJIRGraph.initWithName(allocator, "op_test");
        defer ir_graph.deinit();

        var builder = IRBuilder.init(&ir_graph);

        const lhs = try builder.createConstant(.{ .integer = 10 });
        const rhs = try builder.createConstant(.{ .integer = 5 });

        const op_node = try builder.createNode(op);
        var op_ir_node = &ir_graph.nodes.items[op_node];
        try op_ir_node.inputs.append(allocator, lhs);
        try op_ir_node.inputs.append(allocator, rhs);

        const ret_node = try builder.createNode(.Return);
        var ret_ir_node = &ir_graph.nodes.items[ret_node];
        try ret_ir_node.inputs.append(allocator, op_node);

        var emitter = try LLVMEmitter.init(allocator, "test");
        defer emitter.deinit();

        try emitter.emit(&[_]QTJIRGraph{ir_graph});

        const ir_str = try emitter.toString();
        defer allocator.free(ir_str);

        // Non-main functions get i32 return type by default
        try testing.expect(std.mem.indexOf(u8, ir_str, "define i32 @op_test()") != null);
    }
}
