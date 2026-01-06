// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// MLIR Emitter Tests - Validation of QTJIR → MLIR Transformation
// Doctrine: Arrange-Act-Assert with explicit MLIR output validation

const std = @import("std");
const testing = std.testing;
const qtjir = @import("../qtjir.zig");
const npu = @import("../npu_backend.zig");

const Graph = qtjir.graph.QTJIRGraph;
const IRBuilder = qtjir.graph.IRBuilder;
const OpCode = qtjir.graph.OpCode;
const Tenancy = qtjir.graph.Tenancy;

test "MLIR Emitter: Emits valid MLIR module structure" {
    const allocator = testing.allocator;

    // Arrange: Create empty graph
    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Act: Emit MLIR
    var emitter = try npu.MLIREmitter.init(allocator);
    defer emitter.deinit();

    var mlir_module = try emitter.emit(&graph);
    defer mlir_module.deinit();

    // Assert: Contains module wrapper
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "module {") != null);
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "func.func @janus_main()") != null);
}

test "MLIR Emitter: Emits tensor.matmul as linalg.matmul" {
    const allocator = testing.allocator;

    // Arrange: Create graph with matmul
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .NPU_Tensor;

    const node_id = try builder.createNode(.Tensor_Matmul);
    var node = &graph.nodes.items[node_id];

    // Add dummy inputs
    try node.inputs.append(allocator, 0);
    try node.inputs.append(allocator, 1);

    // Act: Emit MLIR
    var emitter = try npu.MLIREmitter.init(allocator);
    defer emitter.deinit();

    var mlir_module = try emitter.emit(&graph);
    defer mlir_module.deinit();

    // Assert: Contains linalg.matmul
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "linalg.matmul") != null);
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "tensor<?x?xf32>") != null);
}

test "MLIR Emitter: Emits tensor.relu as linalg.generic" {
    const allocator = testing.allocator;

    // Arrange: Create graph with relu
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .NPU_Tensor;

    const node_id = try builder.createNode(.Tensor_Relu);
    var node = &graph.nodes.items[node_id];
    try node.inputs.append(allocator, 0);

    // Act: Emit MLIR
    var emitter = try npu.MLIREmitter.init(allocator);
    defer emitter.deinit();

    var mlir_module = try emitter.emit(&graph);
    defer mlir_module.deinit();

    // Assert: Contains linalg.generic with ReLU logic
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "linalg.generic") != null);
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "arith.maximumf") != null);
}

test "MLIR Emitter: Emits SSM operations to custom dialect" {
    const allocator = testing.allocator;

    // Arrange: Create graph with SSM scan
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .NPU_Tensor;

    const node_id = try builder.createNode(.SSM_Scan);
    var node = &graph.nodes.items[node_id];

    // Add 3 inputs (A, B, C)
    try node.inputs.append(allocator, 0);
    try node.inputs.append(allocator, 1);
    try node.inputs.append(allocator, 2);

    // Act: Emit MLIR
    var emitter = try npu.MLIREmitter.init(allocator);
    defer emitter.deinit();

    var mlir_module = try emitter.emit(&graph);
    defer mlir_module.deinit();

    // Assert: Contains custom janus.ssm.scan operation
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "janus.ssm.scan") != null);
}

test "MLIR Emitter: Emits SSM selective_scan with 4 inputs" {
    const allocator = testing.allocator;

    // Arrange: Create graph with SSM selective_scan
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

    // Act: Emit MLIR
    var emitter = try npu.MLIREmitter.init(allocator);
    defer emitter.deinit();

    var mlir_module = try emitter.emit(&graph);
    defer mlir_module.deinit();

    // Assert: Contains custom janus.ssm.selective_scan operation
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "janus.ssm.selective_scan") != null);
}

test "MLIR Emitter: Emits quantum operations to custom dialect" {
    const allocator = testing.allocator;

    // Arrange: Create graph with quantum gate
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);
    builder.current_tenancy = .QPU_Quantum;

    const node_id = try builder.createNode(.Quantum_Gate);
    var node = &graph.nodes.items[node_id];

    // Add quantum metadata
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;

    node.quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = qubits,
        .parameters = &.{},
    };

    // Act: Emit MLIR
    var emitter = try npu.MLIREmitter.init(allocator);
    defer emitter.deinit();

    var mlir_module = try emitter.emit(&graph);
    defer mlir_module.deinit();

    // Assert: Contains custom janus.quantum.gate operation
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "janus.quantum.gate") != null);
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "Hadamard") != null);
}

test "MLIR Emitter: Emits constants correctly" {
    const allocator = testing.allocator;

    // Arrange: Create graph with constant
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    const node_id = try builder.createNode(.Constant);
    var node = &graph.nodes.items[node_id];
    node.data = .{ .integer = 42 };

    // Act: Emit MLIR
    var emitter = try npu.MLIREmitter.init(allocator);
    defer emitter.deinit();

    var mlir_module = try emitter.emit(&graph);
    defer mlir_module.deinit();

    // Assert: Contains arith.constant
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "arith.constant") != null);
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "42") != null);
}

test "MLIR Emitter: Handles multiple operations in sequence" {
    const allocator = testing.allocator;

    // Arrange: Create graph with matmul → relu pipeline
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

    // Act: Emit MLIR
    var emitter = try npu.MLIREmitter.init(allocator);
    defer emitter.deinit();

    var mlir_module = try emitter.emit(&graph);
    defer mlir_module.deinit();

    // Assert: Contains both operations
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "linalg.matmul") != null);
    try testing.expect(std.mem.indexOf(u8, mlir_module.text, "linalg.generic") != null);
}
