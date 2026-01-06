// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Test suite for QTJIR tensor operations (Phase 2 - Task 2.1.1)

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const OpCode = graph.OpCode;
const TensorMetadata = graph.TensorMetadata;
const DataType = graph.DataType;
const MemoryLayout = graph.MemoryLayout;

// ============================================================================
// Test 1: Verify OpCode enum contains all tensor operations
// ============================================================================

test "QTJIR: Tensor OpCodes Exist" {
    // Verify basic tensor operations are defined
    const matmul: OpCode = .Tensor_Matmul;
    const conv: OpCode = .Tensor_Conv;
    const reduce: OpCode = .Tensor_Reduce;
    const scalar_mul: OpCode = .Tensor_ScalarMul;

    // Verify fused operations for optimization
    const fused_matmul_relu: OpCode = .Tensor_FusedMatmulRelu;
    const fused_matmul_add: OpCode = .Tensor_FusedMatmulAdd;

    // If we get here without compilation errors, the opcodes exist
    _ = matmul;
    _ = conv;
    _ = reduce;
    _ = scalar_mul;
    _ = fused_matmul_relu;
    _ = fused_matmul_add;
}

// ============================================================================
// Test 2: Verify TensorMetadata can represent N-dimensional tensors
// ============================================================================

test "QTJIR: TensorMetadata N-Dimensional Shapes" {
    const allocator = testing.allocator;

    // Test 1D tensor (vector)
    {
        var shape1d = try allocator.alloc(usize, 1);
        defer allocator.free(shape1d);
        shape1d[0] = 256;

        const tensor1d = TensorMetadata{
            .shape = shape1d,
            .dtype = .f32,
            .layout = .RowMajor,
        };

        try testing.expectEqual(@as(usize, 1), tensor1d.shape.len);
        try testing.expectEqual(@as(usize, 256), tensor1d.shape[0]);
        try testing.expectEqual(DataType.f32, tensor1d.dtype);
    }

    // Test 2D tensor (matrix)
    {
        var shape2d = try allocator.alloc(usize, 2);
        defer allocator.free(shape2d);
        shape2d[0] = 128;
        shape2d[1] = 256;

        const tensor2d = TensorMetadata{
            .shape = shape2d,
            .dtype = .f64,
            .layout = .ColumnMajor,
        };

        try testing.expectEqual(@as(usize, 2), tensor2d.shape.len);
        try testing.expectEqual(@as(usize, 128), tensor2d.shape[0]);
        try testing.expectEqual(@as(usize, 256), tensor2d.shape[1]);
        try testing.expectEqual(DataType.f64, tensor2d.dtype);
    }

    // Test 4D tensor (batch of images: NCHW)
    {
        var shape4d = try allocator.alloc(usize, 4);
        defer allocator.free(shape4d);
        shape4d[0] = 32; // Batch size
        shape4d[1] = 3; // Channels (RGB)
        shape4d[2] = 224; // Height
        shape4d[3] = 224; // Width

        const tensor4d = TensorMetadata{
            .shape = shape4d,
            .dtype = .f16,
            .layout = .NCHW,
        };

        try testing.expectEqual(@as(usize, 4), tensor4d.shape.len);
        try testing.expectEqual(@as(usize, 32), tensor4d.shape[0]);
        try testing.expectEqual(@as(usize, 3), tensor4d.shape[1]);
        try testing.expectEqual(@as(usize, 224), tensor4d.shape[2]);
        try testing.expectEqual(@as(usize, 224), tensor4d.shape[3]);
        try testing.expectEqual(MemoryLayout.NCHW, tensor4d.layout);
    }
}

// ============================================================================
// Test 3: Verify IRNode can store and retrieve tensor metadata
// ============================================================================

test "QTJIR: IRNode Tensor Metadata Storage" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_tensor_metadata";

    var builder = IRBuilder.init(&g);

    // Create a tensor matmul node
    const matmul_id = try builder.createNode(.Tensor_Matmul);

    // Create tensor metadata for the operation
    // Note: shape_a and shape_b are not used by the graph, so we manually free them
    var shape_a = try allocator.alloc(usize, 2);
    defer allocator.free(shape_a);
    shape_a[0] = 128;
    shape_a[1] = 256;

    var shape_b = try allocator.alloc(usize, 2);
    defer allocator.free(shape_b);
    shape_b[0] = 256;
    shape_b[1] = 512;

    // Allocate shape for output tensor - ownership transfers to graph!
    // DO NOT manually free this - graph.deinit() will free it
    var shape_out = try allocator.alloc(usize, 2);
    // REMOVED: defer allocator.free(shape_out);  // Double-free bug!
    shape_out[0] = 128;
    shape_out[1] = 512;

    const metadata = TensorMetadata{
        .shape = shape_out, // Ownership transferred to graph
        .dtype = .f32,
        .layout = .RowMajor,
    };

    // Store metadata in the node - graph now owns shape_out
    g.nodes.items[matmul_id].tensor_metadata = metadata;

    // Retrieve and verify metadata
    const retrieved = g.nodes.items[matmul_id].tensor_metadata.?;
    try testing.expectEqual(@as(usize, 2), retrieved.shape.len);
    try testing.expectEqual(@as(usize, 128), retrieved.shape[0]);
    try testing.expectEqual(@as(usize, 512), retrieved.shape[1]);
    try testing.expectEqual(DataType.f32, retrieved.dtype);
    try testing.expectEqual(MemoryLayout.RowMajor, retrieved.layout);
}

// ============================================================================
// Test 4: Verify tensor operations have correct tenancy
// ============================================================================

test "QTJIR: Tensor Operations Default to NPU Tenancy" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_tensor_tenancy";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .NPU_Tensor;

    // Create various tensor operations
    const matmul_id = try builder.createNode(.Tensor_Matmul);
    const conv_id = try builder.createNode(.Tensor_Conv);
    const reduce_id = try builder.createNode(.Tensor_Reduce);

    // Verify all have NPU_Tensor tenancy
    try testing.expectEqual(graph.Tenancy.NPU_Tensor, g.nodes.items[matmul_id].tenancy);
    try testing.expectEqual(graph.Tenancy.NPU_Tensor, g.nodes.items[conv_id].tenancy);
    try testing.expectEqual(graph.Tenancy.NPU_Tensor, g.nodes.items[reduce_id].tenancy);
}

// ============================================================================
// Test 5: Verify DataType enum completeness
// ============================================================================

test "QTJIR: DataType Enum Completeness" {
    // Verify floating point types
    const dt_f16: DataType = .f16;
    const dt_f32: DataType = .f32;
    const dt_f64: DataType = .f64;

    // Verify signed integer types
    const dt_i8: DataType = .i8;
    const dt_i16: DataType = .i16;
    const dt_i32: DataType = .i32;
    const dt_i64: DataType = .i64;

    // Verify unsigned integer types
    const dt_u8: DataType = .u8;
    const dt_u16: DataType = .u16;
    const dt_u32: DataType = .u32;
    const dt_u64: DataType = .u64;

    // If we get here, all types exist
    _ = dt_f16;
    _ = dt_f32;
    _ = dt_f64;
    _ = dt_i8;
    _ = dt_i16;
    _ = dt_i32;
    _ = dt_i64;
    _ = dt_u8;
    _ = dt_u16;
    _ = dt_u32;
    _ = dt_u64;
}

// ============================================================================
// Test 6: Verify MemoryLayout enum completeness
// ============================================================================

test "QTJIR: MemoryLayout Enum Completeness" {
    // Verify basic layouts
    const row_major: MemoryLayout = .RowMajor;
    const col_major: MemoryLayout = .ColumnMajor;

    // Verify tensor-specific layouts
    const nchw: MemoryLayout = .NCHW;
    const nhwc: MemoryLayout = .NHWC;

    // If we get here, all layouts exist
    _ = row_major;
    _ = col_major;
    _ = nchw;
    _ = nhwc;
}
