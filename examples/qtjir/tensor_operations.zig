// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// QTJIR Example: Tensor Operations on NPU

const std = @import("std");
const graph = @import("../../compiler/qtjir/graph.zig");
const emitter = @import("../../compiler/qtjir/emitter.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const LLVMEmitter = emitter.LLVMEmitter;

/// Example: Tensor matrix multiplication on NPU
/// Demonstrates:
/// - NPU_Tensor tenancy
/// - Tensor metadata (shape, dtype, layout)
/// - Tensor operation lowering
/// - Backend function calls
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("QTJIR Example: Tensor Operations\n", .{});
    std.debug.print("=================================\n\n", .{});

    // Create graph for tensor matrix multiplication
    var graph_instance = QTJIRGraph.initWithName(allocator, "tensor_matmul");
    defer graph_instance.deinit();

    var builder = IRBuilder.init(&graph_instance);

    // Set tenancy to NPU for tensor operations
    std.debug.print("Setting execution target to NPU_Tensor...\n", .{});
    builder.current_tenancy = .NPU_Tensor;

    // Create tensor handles (in real code, these would be tensor objects)
    std.debug.print("Creating tensor handles...\n", .{});
    const tensor_a = try builder.createConstant(.{ .integer = 0 }); // Handle to tensor A
    const tensor_b = try builder.createConstant(.{ .integer = 1 }); // Handle to tensor B

    // Create matrix multiplication operation
    std.debug.print("Creating tensor matmul operation...\n", .{});
    const matmul_node = try builder.createNode(.Tensor_Matmul);
    try graph_instance.nodes.items[matmul_node].inputs.append(allocator, tensor_a);
    try graph_instance.nodes.items[matmul_node].inputs.append(allocator, tensor_b);

    // Add tensor metadata
    std.debug.print("Adding tensor metadata...\n", .{});
    var shape_a = try allocator.alloc(usize, 2);
    shape_a[0] = 128;
    shape_a[1] = 256;

    var shape_b = try allocator.alloc(usize, 2);
    shape_b[0] = 256;
    shape_b[1] = 512;

    graph_instance.nodes.items[matmul_node].tensor_metadata = .{
        .shape = shape_a, // Output shape will be [128, 512]
        .dtype = .f32,
        .layout = .RowMajor,
    };

    std.debug.print("  Input A shape: [128, 256]\n", .{});
    std.debug.print("  Input B shape: [256, 512]\n", .{});
    std.debug.print("  Output shape: [128, 512]\n", .{});
    std.debug.print("  Data type: f32\n", .{});
    std.debug.print("  Memory layout: RowMajor\n", .{});

    // Create return
    const ret_node = try builder.createNode(.Return);
    try graph_instance.nodes.items[ret_node].inputs.append(allocator, matmul_node);

    // Validate graph
    std.debug.print("\nValidating graph...\n", .{});
    _ = try graph_instance.validate();
    std.debug.print("✅ Graph validation passed\n", .{});

    // Emit LLVM IR
    std.debug.print("\nEmitting LLVM IR with NPU backend calls...\n", .{});
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&graph_instance);
    defer allocator.free(llvm_ir);

    std.debug.print("✅ LLVM IR emission successful\n\n", .{});

    // Print generated LLVM IR
    std.debug.print("Generated LLVM IR:\n", .{});
    std.debug.print("==================\n", .{});
    std.debug.print("{s}\n", .{llvm_ir});

    // Verify NPU backend calls
    if (std.mem.indexOf(u8, llvm_ir, "@npu_tensor_matmul") != null) {
        std.debug.print("✅ NPU tensor matmul backend call found\n", .{});
    } else {
        std.debug.print("❌ NPU tensor matmul backend call NOT found\n", .{});
    }
}
