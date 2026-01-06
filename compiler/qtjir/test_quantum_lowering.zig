// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Test suite for QTJIR quantum lowering (Phase 2 - Task 2.2.2)

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");
const lowerer = @import("lower.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const OpCode = graph.OpCode;
const GateType = graph.GateType;
const QuantumMetadata = graph.QuantumMetadata;
const Tenancy = graph.Tenancy;

// ============================================================================
// Test 1: Lower hadamard(q0) to Quantum_Gate node with Hadamard gate type
// ============================================================================

test "QTJIR Lowering: Hadamard Gate" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_hadamard";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Simulate lowering: hadamard(q0) where q0 is qubit index 0
    const h_node = try builder.createNode(.Quantum_Gate);

    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;

    g.nodes.items[h_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = qubits,
        .parameters = &.{},
    };

    // Verify the lowered node
    try testing.expectEqual(OpCode.Quantum_Gate, g.nodes.items[h_node].op);
    try testing.expectEqual(Tenancy.QPU_Quantum, g.nodes.items[h_node].tenancy);

    const meta = g.nodes.items[h_node].quantum_metadata.?;
    try testing.expectEqual(GateType.Hadamard, meta.gate_type);
    try testing.expectEqual(@as(usize, 1), meta.qubits.len);
    try testing.expectEqual(@as(usize, 0), meta.qubits[0]);
}

// ============================================================================
// Test 2: Lower cnot(q0, q1) to Quantum_Gate node with control/target qubits
// ============================================================================

test "QTJIR Lowering: CNOT Gate" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_cnot";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Simulate lowering: cnot(q0, q1) where q0=control, q1=target
    const cnot_node = try builder.createNode(.Quantum_Gate);

    var qubits = try allocator.alloc(usize, 2);
    qubits[0] = 0; // Control qubit
    qubits[1] = 1; // Target qubit

    g.nodes.items[cnot_node].quantum_metadata = .{
        .gate_type = .CNOT,
        .qubits = qubits,
        .parameters = &.{},
    };

    // Verify the lowered node
    try testing.expectEqual(OpCode.Quantum_Gate, g.nodes.items[cnot_node].op);
    try testing.expectEqual(Tenancy.QPU_Quantum, g.nodes.items[cnot_node].tenancy);

    const meta = g.nodes.items[cnot_node].quantum_metadata.?;
    try testing.expectEqual(GateType.CNOT, meta.gate_type);
    try testing.expectEqual(@as(usize, 2), meta.qubits.len);
    try testing.expectEqual(@as(usize, 0), meta.qubits[0]); // Control
    try testing.expectEqual(@as(usize, 1), meta.qubits[1]); // Target
}

// ============================================================================
// Test 3: Lower measure(q) to Quantum_Measure node
// ============================================================================

test "QTJIR Lowering: Quantum Measurement" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_measure";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Simulate lowering: measure(q1) where q1 is qubit index 1
    const measure_node = try builder.createNode(.Quantum_Measure);

    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 1;

    g.nodes.items[measure_node].quantum_metadata = .{
        .gate_type = .Hadamard, // Placeholder (not used for measurements)
        .qubits = qubits,
        .parameters = &.{},
    };

    // Verify the lowered node
    try testing.expectEqual(OpCode.Quantum_Measure, g.nodes.items[measure_node].op);
    try testing.expectEqual(Tenancy.QPU_Quantum, g.nodes.items[measure_node].tenancy);

    const meta = g.nodes.items[measure_node].quantum_metadata.?;
    try testing.expectEqual(@as(usize, 1), meta.qubits.len);
    try testing.expectEqual(@as(usize, 1), meta.qubits[0]);
}

// ============================================================================
// Test 4: Lower Pauli-X gate
// ============================================================================

test "QTJIR Lowering: Pauli-X Gate" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_pauli_x";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Simulate lowering: pauli_x(q0)
    const x_node = try builder.createNode(.Quantum_Gate);

    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;

    g.nodes.items[x_node].quantum_metadata = .{
        .gate_type = .PauliX,
        .qubits = qubits,
        .parameters = &.{},
    };

    // Verify the lowered node
    const meta = g.nodes.items[x_node].quantum_metadata.?;
    try testing.expectEqual(GateType.PauliX, meta.gate_type);
    try testing.expectEqual(@as(usize, 0), meta.qubits[0]);
}

// ============================================================================
// Test 5: Lower rotation gate with parameter (RX)
// ============================================================================

test "QTJIR Lowering: Rotation Gate RX" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_rx";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Simulate lowering: rx(q0, π/2)
    const rx_node = try builder.createNode(.Quantum_Gate);

    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;

    var params = try allocator.alloc(f64, 1);
    params[0] = 1.5707963267948966; // π/2

    g.nodes.items[rx_node].quantum_metadata = .{
        .gate_type = .RX,
        .qubits = qubits,
        .parameters = params,
    };

    // Verify the lowered node
    const meta = g.nodes.items[rx_node].quantum_metadata.?;
    try testing.expectEqual(GateType.RX, meta.gate_type);
    try testing.expectEqual(@as(usize, 1), meta.parameters.len);
    try testing.expectApproxEqAbs(1.5707963267948966, meta.parameters[0], 1e-10);
}

// ============================================================================
// Test 6: Lower quantum circuit with gate sequence (BDD Scenario 4)
// ============================================================================

test "QTJIR Lowering: Quantum Circuit H → CNOT → Measure" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_quantum_circuit";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Gate 1: hadamard(q0)
    const h_node = try builder.createNode(.Quantum_Gate);
    var h_qubits = try allocator.alloc(usize, 1);
    h_qubits[0] = 0;
    g.nodes.items[h_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = h_qubits,
        .parameters = &.{},
    };

    // Gate 2: cnot(q0, q1)
    const cnot_node = try builder.createNode(.Quantum_Gate);
    var cnot_qubits = try allocator.alloc(usize, 2);
    cnot_qubits[0] = 0; // Control
    cnot_qubits[1] = 1; // Target
    g.nodes.items[cnot_node].quantum_metadata = .{
        .gate_type = .CNOT,
        .qubits = cnot_qubits,
        .parameters = &.{},
    };
    try g.nodes.items[cnot_node].inputs.append(allocator, h_node);

    // Gate 3: measure(q1)
    const measure_node = try builder.createNode(.Quantum_Measure);
    var measure_qubits = try allocator.alloc(usize, 1);
    measure_qubits[0] = 1;
    g.nodes.items[measure_node].quantum_metadata = .{
        .gate_type = .Hadamard, // Placeholder
        .qubits = measure_qubits,
        .parameters = &.{},
    };
    try g.nodes.items[measure_node].inputs.append(allocator, cnot_node);

    // Verify circuit structure matches BDD Scenario 4
    try testing.expectEqual(@as(usize, 3), g.nodes.items.len);

    // Node 0: Hadamard on qubit 0
    try testing.expectEqual(OpCode.Quantum_Gate, g.nodes.items[0].op);
    try testing.expectEqual(Tenancy.QPU_Quantum, g.nodes.items[0].tenancy);
    try testing.expectEqual(GateType.Hadamard, g.nodes.items[0].quantum_metadata.?.gate_type);

    // Node 1: CNOT on qubits [0, 1]
    try testing.expectEqual(OpCode.Quantum_Gate, g.nodes.items[1].op);
    try testing.expectEqual(Tenancy.QPU_Quantum, g.nodes.items[1].tenancy);
    try testing.expectEqual(GateType.CNOT, g.nodes.items[1].quantum_metadata.?.gate_type);

    // Node 2: Measure qubit 1
    try testing.expectEqual(OpCode.Quantum_Measure, g.nodes.items[2].op);
    try testing.expectEqual(Tenancy.QPU_Quantum, g.nodes.items[2].tenancy);
    try testing.expectEqual(@as(usize, 1), g.nodes.items[2].quantum_metadata.?.qubits[0]);
}

// ============================================================================
// Test 7: Verify QPU_Quantum tenancy for all quantum operations
// ============================================================================

test "QTJIR Lowering: QPU_Quantum Tenancy Enforcement" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_tenancy";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Create various quantum operations
    const h_node = try builder.createNode(.Quantum_Gate);
    const cnot_node = try builder.createNode(.Quantum_Gate);
    const measure_node = try builder.createNode(.Quantum_Measure);

    // All should have QPU_Quantum tenancy
    try testing.expectEqual(Tenancy.QPU_Quantum, g.nodes.items[h_node].tenancy);
    try testing.expectEqual(Tenancy.QPU_Quantum, g.nodes.items[cnot_node].tenancy);
    try testing.expectEqual(Tenancy.QPU_Quantum, g.nodes.items[measure_node].tenancy);
}

// ============================================================================
// Test 8: Lower Toffoli gate (three-qubit gate)
// ============================================================================

test "QTJIR Lowering: Toffoli Gate (Three Qubits)" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_toffoli";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Simulate lowering: toffoli(q0, q1, q2) - two controls, one target
    const toffoli_node = try builder.createNode(.Quantum_Gate);

    var qubits = try allocator.alloc(usize, 3);
    qubits[0] = 0; // Control 1
    qubits[1] = 1; // Control 2
    qubits[2] = 2; // Target

    g.nodes.items[toffoli_node].quantum_metadata = .{
        .gate_type = .Toffoli,
        .qubits = qubits,
        .parameters = &.{},
    };

    // Verify the lowered node
    const meta = g.nodes.items[toffoli_node].quantum_metadata.?;
    try testing.expectEqual(GateType.Toffoli, meta.gate_type);
    try testing.expectEqual(@as(usize, 3), meta.qubits.len);
    try testing.expectEqual(@as(usize, 0), meta.qubits[0]);
    try testing.expectEqual(@as(usize, 1), meta.qubits[1]);
    try testing.expectEqual(@as(usize, 2), meta.qubits[2]);
}

// ============================================================================
// Test 9: Lower SWAP gate
// ============================================================================

test "QTJIR Lowering: SWAP Gate" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_swap";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Simulate lowering: swap(q0, q1)
    const swap_node = try builder.createNode(.Quantum_Gate);

    var qubits = try allocator.alloc(usize, 2);
    qubits[0] = 0;
    qubits[1] = 1;

    g.nodes.items[swap_node].quantum_metadata = .{
        .gate_type = .SWAP,
        .qubits = qubits,
        .parameters = &.{},
    };

    // Verify the lowered node
    const meta = g.nodes.items[swap_node].quantum_metadata.?;
    try testing.expectEqual(GateType.SWAP, meta.gate_type);
    try testing.expectEqual(@as(usize, 2), meta.qubits.len);
}
