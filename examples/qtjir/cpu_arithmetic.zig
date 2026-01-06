// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// QTJIR Example: CPU-Only Arithmetic Operations

const std = @import("std");
const graph = @import("../../compiler/qtjir/graph.zig");
const emitter = @import("../../compiler/qtjir/emitter.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const LLVMEmitter = emitter.LLVMEmitter;

/// Example: Simple arithmetic operations on CPU
/// Demonstrates:
/// - Graph construction
/// - Arithmetic operations (Add, Sub, Mul, Div)
/// - LLVM IR emission
/// - Executable compilation
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("QTJIR Example: CPU Arithmetic\n", .{});
    std.debug.print("==============================\n\n", .{});

    // Create graph for: (a + b) * (c - d)
    var graph_instance = QTJIRGraph.initWithName(allocator, "arithmetic");
    defer graph_instance.deinit();

    var builder = IRBuilder.init(&graph_instance);

    // Create constants
    std.debug.print("Creating constants...\n", .{});
    const a = try builder.createConstant(.{ .integer = 10 });
    const b = try builder.createConstant(.{ .integer = 20 });
    const c = try builder.createConstant(.{ .integer = 30 });
    const d = try builder.createConstant(.{ .integer = 5 });

    // Create addition: a + b
    std.debug.print("Creating addition: 10 + 20...\n", .{});
    const add_node = try builder.createNode(.Add);
    try graph_instance.nodes.items[add_node].inputs.append(allocator, a);
    try graph_instance.nodes.items[add_node].inputs.append(allocator, b);

    // Create subtraction: c - d
    std.debug.print("Creating subtraction: 30 - 5...\n", .{});
    const sub_node = try builder.createNode(.Sub);
    try graph_instance.nodes.items[sub_node].inputs.append(allocator, c);
    try graph_instance.nodes.items[sub_node].inputs.append(allocator, d);

    // Create multiplication: (a + b) * (c - d)
    std.debug.print("Creating multiplication: (a + b) * (c - d)...\n", .{});
    const mul_node = try builder.createNode(.Mul);
    try graph_instance.nodes.items[mul_node].inputs.append(allocator, add_node);
    try graph_instance.nodes.items[mul_node].inputs.append(allocator, sub_node);

    // Create return
    const ret_node = try builder.createNode(.Return);
    try graph_instance.nodes.items[ret_node].inputs.append(allocator, mul_node);

    // Validate graph
    std.debug.print("\nValidating graph...\n", .{});
    _ = try graph_instance.validate();
    std.debug.print("✅ Graph validation passed\n", .{});

    // Emit LLVM IR
    std.debug.print("\nEmitting LLVM IR...\n", .{});
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&graph_instance);
    defer allocator.free(llvm_ir);

    std.debug.print("✅ LLVM IR emission successful\n\n", .{});

    // Print generated LLVM IR
    std.debug.print("Generated LLVM IR:\n", .{});
    std.debug.print("==================\n", .{});
    std.debug.print("{s}\n", .{llvm_ir});

    // Calculate expected result
    const result = (10 + 20) * (30 - 5);
    std.debug.print("Expected result: (10 + 20) * (30 - 5) = {d}\n", .{result});
}
