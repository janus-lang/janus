// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// JFind Hello World Compilation Test

const std = @import("std");
const testing = std.testing;
const graph_mod = @import("graph.zig");
const LLVMEmitter = @import("llvm_emitter.zig").LLVMEmitter;

const QTJIRGraph = graph_mod.QTJIRGraph;
const IRBuilder = graph_mod.IRBuilder;

test "JFind: Compile hello.jan" {
    const allocator = testing.allocator;

    // Manually construct the QTJIR that corresponds to hello.jan
    var ir_graph = QTJIRGraph.initWithName(allocator, "main");
    defer ir_graph.deinit();

    var builder = IRBuilder.init(&ir_graph);

    // 1. Create string constant (Sovereign Graph: heap-allocate)
    const owned_str = try allocator.dupeZ(u8, "Hello from Janus!");
    const str_node = try builder.createConstant(.{ .string = owned_str });

    // 2. Create call to print — set function name on the call node
    const call_id = try builder.createCall(&[_]u32{str_node});
    const owned_fn = try allocator.dupeZ(u8, "janus_print");
    ir_graph.nodes.items[call_id].data = .{ .string = owned_fn };

    // 3. Create return 0
    const zero = try builder.createConstant(.{ .integer = 0 });
    _ = try builder.createReturn(zero);

    // Emit to LLVM
    var emitter = try LLVMEmitter.init(allocator, "hello");
    defer emitter.deinit();

    try emitter.emit(&[_]QTJIRGraph{ir_graph});

    // Get LLVM IR
    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);

    // Verify IR contains expected elements
    try testing.expect(std.mem.indexOf(u8, ir_str, "janus_print") != null);
    try testing.expect(std.mem.indexOf(u8, ir_str, "Hello from Janus!") != null);
}
