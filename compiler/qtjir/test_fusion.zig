// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Test suite for QTJIR tensor fusion passes (Phase 2)

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");
const transforms = @import("transforms.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const OpCode = graph.OpCode;
const Tenancy = graph.Tenancy;
const PassManager = transforms.PassManager;
const FuseMatmulRelu = transforms.FuseMatmulRelu;

// ============================================================================
// Test 1: Fuse Matmul + Relu
// ============================================================================

test "QTJIR Fusion: Fuse Matmul + Relu" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .NPU_Tensor;

    // Create graph: A @ B -> Relu
    const a = try builder.createNode(.Constant);
    const b = try builder.createNode(.Constant);

    const matmul = try builder.createNode(.Tensor_Matmul);
    try g.nodes.items[matmul].inputs.append(allocator, a);
    try g.nodes.items[matmul].inputs.append(allocator, b);

    // Add metadata to Matmul - shape must be heap-allocated!
    var matmul_shape = try allocator.alloc(usize, 2);
    matmul_shape[0] = 128;
    matmul_shape[1] = 512;
    // Ownership transfers to graph - do NOT manually free
    g.nodes.items[matmul].tensor_metadata = .{
        .shape = matmul_shape,
        .dtype = .f32,
        .layout = .RowMajor,
    };

    const relu = try builder.createNode(.Tensor_Relu);
    try g.nodes.items[relu].inputs.append(allocator, matmul);

    // Run Fusion Pass
    var pm = PassManager.init(allocator);
    defer pm.deinit();

    var fusion_pass = FuseMatmulRelu.init(allocator);
    try pm.addPass(fusion_pass.transform());

    try pm.run(&g);

    // Verify Fusion
    const fused_node = &g.nodes.items[relu];
    try testing.expectEqual(OpCode.Tensor_FusedMatmulRelu, fused_node.op);
    try testing.expectEqual(Tenancy.NPU_Tensor, fused_node.tenancy);

    // Inputs should be A and B (from Matmul)
    try testing.expectEqual(@as(usize, 2), fused_node.inputs.items.len);
    try testing.expectEqual(a, fused_node.inputs.items[0]);
    try testing.expectEqual(b, fused_node.inputs.items[1]);

    // Metadata should be preserved/propagated
    try testing.expect(fused_node.tensor_metadata != null);
    try testing.expectEqual(@as(usize, 128), fused_node.tensor_metadata.?.shape[0]);
    try testing.expectEqual(@as(usize, 512), fused_node.tensor_metadata.?.shape[1]);
}

// ============================================================================
// Test 2: Do not fuse if tenancy mismatch
// ============================================================================

test "QTJIR Fusion: Skip Tenancy Mismatch" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create graph: A @ B (CPU) -> Relu (NPU)
    builder.current_tenancy = .CPU_Serial;
    const a = try builder.createNode(.Constant);
    const b = try builder.createNode(.Constant);

    const matmul = try builder.createNode(.Tensor_Matmul);
    try g.nodes.items[matmul].inputs.append(allocator, a);
    try g.nodes.items[matmul].inputs.append(allocator, b);

    builder.current_tenancy = .NPU_Tensor;
    const relu = try builder.createNode(.Tensor_Relu);
    try g.nodes.items[relu].inputs.append(allocator, matmul);

    // Run Fusion Pass
    var pm = PassManager.init(allocator);
    defer pm.deinit();

    var fusion_pass = FuseMatmulRelu.init(allocator);
    try pm.addPass(fusion_pass.transform());

    try pm.run(&g);

    // Verify NO Fusion
    const relu_node = &g.nodes.items[relu];
    try testing.expectEqual(OpCode.Tensor_Relu, relu_node.op);
}
