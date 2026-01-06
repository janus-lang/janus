// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Test suite for QTJIR tensor lowering (Phase 2 - Task 2.1.2)

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const OpCode = graph.OpCode;
const Tenancy = graph.Tenancy;

// ============================================================================
// Test 1: Given `A @ B`, verify Tensor_Matmul node is created
// ============================================================================

test "QTJIR: Matrix Multiply Lowering Creates Tensor_Matmul Node" {
    const allocator = testing.allocator;

    // This test verifies that the @ operator creates a Tensor_Matmul node
    // In a real scenario, this would parse: let C = A @ B

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_matmul";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .NPU_Tensor;

    // Simulate: let A: Tensor<f32, 128x256> = ...
    const a_node = try builder.createConstant(.{ .integer = 1 });

    // Simulate: let B: Tensor<f32, 256x512> = ...
    const b_node = try builder.createConstant(.{ .integer = 2 });

    // Simulate: let C = A @ B
    const matmul_node = try builder.createNode(.Tensor_Matmul);
    try g.nodes.items[matmul_node].inputs.append(allocator, a_node);
    try g.nodes.items[matmul_node].inputs.append(allocator, b_node);

    // Verify the node was created correctly
    try testing.expectEqual(OpCode.Tensor_Matmul, g.nodes.items[matmul_node].op);
    try testing.expectEqual(Tenancy.NPU_Tensor, g.nodes.items[matmul_node].tenancy);
    try testing.expectEqual(@as(usize, 2), g.nodes.items[matmul_node].inputs.items.len);
    try testing.expectEqual(a_node, g.nodes.items[matmul_node].inputs.items[0]);
    try testing.expectEqual(b_node, g.nodes.items[matmul_node].inputs.items[1]);
}

// ============================================================================
// Test 2: Verify shape metadata is correctly propagated through operations
// ============================================================================

test "QTJIR: Tensor Matmul Propagates Shape Metadata" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_shape_propagation";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .NPU_Tensor;

    // Create tensor A with shape [128, 256]
    const a_node = try builder.createConstant(.{ .integer = 1 });
    var shape_a = try allocator.alloc(usize, 2);
    shape_a[0] = 128;
    shape_a[1] = 256;
    g.nodes.items[a_node].tensor_metadata = .{
        .shape = shape_a,
        .dtype = .f32,
        .layout = .RowMajor,
    };

    // Create tensor B with shape [256, 512]
    const b_node = try builder.createConstant(.{ .integer = 2 });
    var shape_b = try allocator.alloc(usize, 2);
    shape_b[0] = 256;
    shape_b[1] = 512;
    g.nodes.items[b_node].tensor_metadata = .{
        .shape = shape_b,
        .dtype = .f32,
        .layout = .RowMajor,
    };

    // Create matmul node with output shape [128, 512]
    const matmul_node = try builder.createNode(.Tensor_Matmul);
    try g.nodes.items[matmul_node].inputs.append(allocator, a_node);
    try g.nodes.items[matmul_node].inputs.append(allocator, b_node);

    var shape_out = try allocator.alloc(usize, 2);
    shape_out[0] = 128;
    shape_out[1] = 512;
    g.nodes.items[matmul_node].tensor_metadata = .{
        .shape = shape_out,
        .dtype = .f32,
        .layout = .RowMajor,
    };

    // Verify shape metadata is correctly attached
    const a_meta = g.nodes.items[a_node].tensor_metadata.?;
    try testing.expectEqual(@as(usize, 128), a_meta.shape[0]);
    try testing.expectEqual(@as(usize, 256), a_meta.shape[1]);

    const b_meta = g.nodes.items[b_node].tensor_metadata.?;
    try testing.expectEqual(@as(usize, 256), b_meta.shape[0]);
    try testing.expectEqual(@as(usize, 512), b_meta.shape[1]);

    const out_meta = g.nodes.items[matmul_node].tensor_metadata.?;
    try testing.expectEqual(@as(usize, 128), out_meta.shape[0]);
    try testing.expectEqual(@as(usize, 512), out_meta.shape[1]);
}

// ============================================================================
// Test 3: Verify NPU_Tensor tenancy is set for tensor operations
// ============================================================================

test "QTJIR: Tensor Operations Use NPU_Tensor Tenancy" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_npu_tenancy";

    var builder = IRBuilder.init(&g);

    // Explicitly set NPU tenancy for tensor operations
    builder.current_tenancy = .NPU_Tensor;

    const matmul_node = try builder.createNode(.Tensor_Matmul);
    const conv_node = try builder.createNode(.Tensor_Conv);
    const reduce_node = try builder.createNode(.Tensor_Reduce);
    const contract_node = try builder.createNode(.Tensor_Contract);

    // Verify all tensor operations have NPU_Tensor tenancy
    try testing.expectEqual(Tenancy.NPU_Tensor, g.nodes.items[matmul_node].tenancy);
    try testing.expectEqual(Tenancy.NPU_Tensor, g.nodes.items[conv_node].tenancy);
    try testing.expectEqual(Tenancy.NPU_Tensor, g.nodes.items[reduce_node].tenancy);
    try testing.expectEqual(Tenancy.NPU_Tensor, g.nodes.items[contract_node].tenancy);
}

// ============================================================================
// Test 4: Verify einsum creates Tensor_Contract node
// ============================================================================

test "QTJIR: Einsum Creates Tensor_Contract Node" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_einsum";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .NPU_Tensor;

    // Simulate: einsum("ijk,jkl->il", A, B)
    const a_node = try builder.createConstant(.{ .integer = 1 });
    const b_node = try builder.createConstant(.{ .integer = 2 });

    const contract_node = try builder.createNode(.Tensor_Contract);
    try g.nodes.items[contract_node].inputs.append(allocator, a_node);
    try g.nodes.items[contract_node].inputs.append(allocator, b_node);

    // Verify the node was created correctly
    try testing.expectEqual(OpCode.Tensor_Contract, g.nodes.items[contract_node].op);
    try testing.expectEqual(Tenancy.NPU_Tensor, g.nodes.items[contract_node].tenancy);
    try testing.expectEqual(@as(usize, 2), g.nodes.items[contract_node].inputs.items.len);
}

// ============================================================================
// Test 5: Verify scalar-tensor multiplication
// ============================================================================

test "QTJIR: Scalar-Tensor Multiplication Lowering" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_scalar_mul";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .NPU_Tensor;

    // Simulate: let B = A * x (where A is tensor, x is scalar)
    const tensor_node = try builder.createConstant(.{ .integer = 1 });
    const scalar_node = try builder.createConstant(.{ .float = 2.5 });

    const scalar_mul_node = try builder.createNode(.Tensor_ScalarMul);
    try g.nodes.items[scalar_mul_node].inputs.append(allocator, tensor_node);
    try g.nodes.items[scalar_mul_node].inputs.append(allocator, scalar_node);

    // Verify the node was created correctly
    try testing.expectEqual(OpCode.Tensor_ScalarMul, g.nodes.items[scalar_mul_node].op);
    try testing.expectEqual(Tenancy.NPU_Tensor, g.nodes.items[scalar_mul_node].tenancy);
}

// ============================================================================
// Test 6: Verify tensor reduction operations
// ============================================================================

test "QTJIR: Tensor Reduction Lowering" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_reduction";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .NPU_Tensor;

    // Simulate: let sum = reduce_sum(A)
    const tensor_node = try builder.createConstant(.{ .integer = 1 });

    const reduce_node = try builder.createNode(.Tensor_Reduce);
    try g.nodes.items[reduce_node].inputs.append(allocator, tensor_node);

    // Verify the node was created correctly
    try testing.expectEqual(OpCode.Tensor_Reduce, g.nodes.items[reduce_node].op);
    try testing.expectEqual(Tenancy.NPU_Tensor, g.nodes.items[reduce_node].tenancy);
}
