// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// NPU Simulator Tests - Validation of Tensor/SSM Operation Semantics
// Doctrine: Arrange-Act-Assert with explicit validation

const std = @import("std");
const testing = std.testing;
const qtjir = @import("../qtjir.zig");
const npu = @import("../npu_backend.zig");

const Graph = qtjir.graph.QTJIRGraph;
const IRBuilder = qtjir.graph.IRBuilder;
const OpCode = qtjir.graph.OpCode;
const Tenancy = qtjir.graph.Tenancy;

test "NPU Simulator: Validates correct NPU_Tensor tenancy" {
    const allocator = testing.allocator;

    // Arrange: Create graph with tensor operation
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .NPU_Tensor;

    const node_id = try builder.createNode(.Tensor_Matmul);
    var node = &graph.nodes.items[node_id];

    // Add dummy inputs (2 for matmul)
    try node.inputs.append(allocator, 0);
    try node.inputs.append(allocator, 1);

    // Act: Run simulator
    var simulator = try npu.Simulator.init(allocator);
    defer simulator.deinit();

    var result = try simulator.execute(&graph);
    defer result.deinit(allocator);

    // Assert: Validation passes
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 1), result.nodes_validated);
    try testing.expectEqual(@as(usize, 1), result.tensor_ops_count);
}

test "NPU Simulator: Detects incorrect tenancy" {
    const allocator = testing.allocator;

    // Arrange: Create graph with WRONG tenancy
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .CPU_Serial; // WRONG for tensor ops

    const node_id = try builder.createNode(.Tensor_Matmul);
    var node = &graph.nodes.items[node_id];

    // Add dummy inputs
    try node.inputs.append(allocator, 0);
    try node.inputs.append(allocator, 1);

    // Act: Run simulator
    var simulator = try npu.Simulator.init(allocator);
    defer simulator.deinit();

    var result = try simulator.execute(&graph);
    defer result.deinit(allocator);

    // Assert: Validation fails with tenancy error
    try testing.expect(!result.is_valid);
    try testing.expect(result.error_message != null);
}

test "NPU Simulator: Validates matmul input count" {
    const allocator = testing.allocator;

    // Arrange: Create matmul with wrong input count
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .NPU_Tensor;

    const node_id = try builder.createNode(.Tensor_Matmul);
    var node = &graph.nodes.items[node_id];

    // Add WRONG number of inputs (1 instead of 2)
    try node.inputs.append(allocator, 0);

    // Act: Run simulator
    var simulator = try npu.Simulator.init(allocator);
    defer simulator.deinit();

    var result = try simulator.execute(&graph);
    defer result.deinit(allocator);

    // Assert: Validation fails
    try testing.expect(!result.is_valid);
    try testing.expect(result.error_message != null);
}

test "NPU Simulator: Validates SSM scan input count" {
    const allocator = testing.allocator;

    // Arrange: Create SSM scan with correct inputs
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .NPU_Tensor;

    const node_id = try builder.createNode(.SSM_Scan);
    var node = &graph.nodes.items[node_id];

    // Add 3 inputs (A, B, C matrices)
    try node.inputs.append(allocator, 0);
    try node.inputs.append(allocator, 1);
    try node.inputs.append(allocator, 2);

    // Act: Run simulator
    var simulator = try npu.Simulator.init(allocator);
    defer simulator.deinit();

    var result = try simulator.execute(&graph);
    defer result.deinit(allocator);

    // Assert: Validation passes
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 1), result.ssm_ops_count);
}

test "NPU Simulator: Validates SSM selective_scan input count" {
    const allocator = testing.allocator;

    // Arrange: Create SSM selective_scan with correct inputs
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .NPU_Tensor;

    const node_id = try builder.createNode(.SSM_SelectiveScan);
    var node = &graph.nodes.items[node_id];

    // Add 4 inputs (A, B, C, delta)
    try node.inputs.append(allocator, 0);
    try node.inputs.append(allocator, 1);
    try node.inputs.append(allocator, 2);
    try node.inputs.append(allocator, 3);

    // Act: Run simulator
    var simulator = try npu.Simulator.init(allocator);
    defer simulator.deinit();

    var result = try simulator.execute(&graph);
    defer result.deinit(allocator);

    // Assert: Validation passes
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 1), result.ssm_ops_count);
}

test "NPU Simulator: Validates multiple tensor operations" {
    const allocator = testing.allocator;

    // Arrange: Create graph with multiple tensor ops
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .NPU_Tensor;

    // Create matmul
    const matmul_id = try builder.createNode(.Tensor_Matmul);
    var matmul = &graph.nodes.items[matmul_id];
    try matmul.inputs.append(allocator, 0);
    try matmul.inputs.append(allocator, 1);

    // Create relu
    const relu_id = try builder.createNode(.Tensor_Relu);
    var relu = &graph.nodes.items[relu_id];
    try relu.inputs.append(allocator, matmul_id);

    // Create softmax
    const softmax_id = try builder.createNode(.Tensor_Softmax);
    var softmax = &graph.nodes.items[softmax_id];
    try softmax.inputs.append(allocator, relu_id);

    // Act: Run simulator
    var simulator = try npu.Simulator.init(allocator);
    defer simulator.deinit();

    var result = try simulator.execute(&graph);
    defer result.deinit(allocator);

    // Assert: All operations validated
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 3), result.nodes_validated);
    try testing.expectEqual(@as(usize, 3), result.tensor_ops_count);
}
