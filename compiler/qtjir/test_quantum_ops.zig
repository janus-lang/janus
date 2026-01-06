// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Test suite for QTJIR quantum operations (Phase 2 - Task 2.2.1)

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const OpCode = graph.OpCode;
const GateType = graph.GateType;
const QuantumMetadata = graph.QuantumMetadata;

// ============================================================================
// Test 1: Verify OpCode enum contains quantum operations
// ============================================================================

test "QTJIR: OpCode Enum Contains Quantum Operations" {
    // Verify that Quantum_Gate and Quantum_Measure opcodes exist
    const gate_op: OpCode = .Quantum_Gate;
    const measure_op: OpCode = .Quantum_Measure;

    try testing.expect(gate_op == .Quantum_Gate);
    try testing.expect(measure_op == .Quantum_Measure);
}

// ============================================================================
// Test 2: Verify GateType enum contains all standard quantum gates
// ============================================================================

test "QTJIR: GateType Enum Contains Standard Quantum Gates" {
    // Single-qubit gates
    const hadamard: GateType = .Hadamard;
    const pauli_x: GateType = .PauliX;
    const pauli_y: GateType = .PauliY;
    const pauli_z: GateType = .PauliZ;
    const phase: GateType = .Phase;
    const t_gate: GateType = .T;

    // Two-qubit gates
    const cnot: GateType = .CNOT;
    const cz: GateType = .CZ;
    const swap: GateType = .SWAP;

    // Three-qubit gates
    const toffoli: GateType = .Toffoli;
    const fredkin: GateType = .Fredkin;

    // Rotation gates
    const rx: GateType = .RX;
    const ry: GateType = .RY;
    const rz: GateType = .RZ;

    // Mark unused variables (intentional - we're testing enum completeness)
    _ = pauli_y;
    _ = pauli_z;
    _ = phase;
    _ = t_gate;
    _ = cz;
    _ = swap;
    _ = fredkin;
    _ = ry;
    _ = rz;

    // Verify all gate types are distinct
    try testing.expect(hadamard == .Hadamard);
    try testing.expect(pauli_x == .PauliX);
    try testing.expect(cnot == .CNOT);
    try testing.expect(toffoli == .Toffoli);
    try testing.expect(rx == .RX);
}

// ============================================================================
// Test 3: Verify QuantumMetadata can track qubit indices
// ============================================================================

test "QTJIR: QuantumMetadata Tracks Qubit Indices" {
    const allocator = testing.allocator;

    // Single-qubit gate metadata
    var qubits_single = try allocator.alloc(usize, 1);
    defer allocator.free(qubits_single);
    qubits_single[0] = 0;

    const single_qubit_meta = QuantumMetadata{
        .gate_type = .Hadamard,
        .qubits = qubits_single,
        .parameters = &.{},
    };

    try testing.expectEqual(GateType.Hadamard, single_qubit_meta.gate_type);
    try testing.expectEqual(@as(usize, 1), single_qubit_meta.qubits.len);
    try testing.expectEqual(@as(usize, 0), single_qubit_meta.qubits[0]);

    // Two-qubit gate metadata (CNOT)
    var qubits_two = try allocator.alloc(usize, 2);
    defer allocator.free(qubits_two);
    qubits_two[0] = 0; // Control qubit
    qubits_two[1] = 1; // Target qubit

    const two_qubit_meta = QuantumMetadata{
        .gate_type = .CNOT,
        .qubits = qubits_two,
        .parameters = &.{},
    };

    try testing.expectEqual(GateType.CNOT, two_qubit_meta.gate_type);
    try testing.expectEqual(@as(usize, 2), two_qubit_meta.qubits.len);
    try testing.expectEqual(@as(usize, 0), two_qubit_meta.qubits[0]);
    try testing.expectEqual(@as(usize, 1), two_qubit_meta.qubits[1]);
}

// ============================================================================
// Test 4: Verify QuantumMetadata can track gate parameters
// ============================================================================

test "QTJIR: QuantumMetadata Tracks Gate Parameters" {
    const allocator = testing.allocator;

    // Rotation gate with angle parameter
    var qubits = try allocator.alloc(usize, 1);
    defer allocator.free(qubits);
    qubits[0] = 0;

    var params = try allocator.alloc(f64, 1);
    defer allocator.free(params);
    params[0] = 1.5707963267948966; // π/2 radians

    const rotation_meta = QuantumMetadata{
        .gate_type = .RX,
        .qubits = qubits,
        .parameters = params,
    };

    try testing.expectEqual(GateType.RX, rotation_meta.gate_type);
    try testing.expectEqual(@as(usize, 1), rotation_meta.parameters.len);
    try testing.expectApproxEqAbs(1.5707963267948966, rotation_meta.parameters[0], 1e-10);
}

// ============================================================================
// Test 5: Verify IRNode can store quantum metadata
// ============================================================================

test "QTJIR: IRNode Stores Quantum Metadata" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_quantum_metadata";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Create a Hadamard gate node
    const gate_node = try builder.createNode(.Quantum_Gate);

    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;

    g.nodes.items[gate_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = qubits,
        .parameters = &.{},
    };

    // Verify metadata is stored correctly
    const stored_meta = g.nodes.items[gate_node].quantum_metadata.?;
    try testing.expectEqual(GateType.Hadamard, stored_meta.gate_type);
    try testing.expectEqual(@as(usize, 1), stored_meta.qubits.len);
    try testing.expectEqual(@as(usize, 0), stored_meta.qubits[0]);
}

// ============================================================================
// Test 6: Verify quantum nodes have QPU_Quantum tenancy
// ============================================================================

test "QTJIR: Quantum Nodes Have QPU_Quantum Tenancy" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_quantum_tenancy";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Create quantum gate node
    const gate_node = try builder.createNode(.Quantum_Gate);
    try testing.expectEqual(graph.Tenancy.QPU_Quantum, g.nodes.items[gate_node].tenancy);

    // Create quantum measurement node
    const measure_node = try builder.createNode(.Quantum_Measure);
    try testing.expectEqual(graph.Tenancy.QPU_Quantum, g.nodes.items[measure_node].tenancy);
}

// ============================================================================
// Test 7: Verify three-qubit gate metadata (Toffoli)
// ============================================================================

test "QTJIR: Three-Qubit Gate Metadata (Toffoli)" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_toffoli";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Create Toffoli gate node (3 qubits: 2 controls, 1 target)
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

    const stored_meta = g.nodes.items[toffoli_node].quantum_metadata.?;
    try testing.expectEqual(GateType.Toffoli, stored_meta.gate_type);
    try testing.expectEqual(@as(usize, 3), stored_meta.qubits.len);
    try testing.expectEqual(@as(usize, 0), stored_meta.qubits[0]);
    try testing.expectEqual(@as(usize, 1), stored_meta.qubits[1]);
    try testing.expectEqual(@as(usize, 2), stored_meta.qubits[2]);
}

// ============================================================================
// Test 8: Verify measurement metadata
// ============================================================================

test "QTJIR: Quantum Measurement Metadata" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_measurement";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Create measurement node
    const measure_node = try builder.createNode(.Quantum_Measure);

    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 1; // Measure qubit 1

    g.nodes.items[measure_node].quantum_metadata = .{
        .gate_type = .Hadamard, // Not used for measurements, but required by struct
        .qubits = qubits,
        .parameters = &.{},
    };

    const stored_meta = g.nodes.items[measure_node].quantum_metadata.?;
    try testing.expectEqual(@as(usize, 1), stored_meta.qubits.len);
    try testing.expectEqual(@as(usize, 1), stored_meta.qubits[0]);
}

// ============================================================================
// Test 9: Verify quantum circuit with multiple gates
// ============================================================================

test "QTJIR: Quantum Circuit With Multiple Gates" {
    const allocator = testing.allocator;

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_quantum_circuit";

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Gate 1: Hadamard on qubit 0
    const h_node = try builder.createNode(.Quantum_Gate);
    var h_qubits = try allocator.alloc(usize, 1);
    h_qubits[0] = 0;
    g.nodes.items[h_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = h_qubits,
        .parameters = &.{},
    };

    // Gate 2: CNOT with control=0, target=1
    const cnot_node = try builder.createNode(.Quantum_Gate);
    var cnot_qubits = try allocator.alloc(usize, 2);
    cnot_qubits[0] = 0;
    cnot_qubits[1] = 1;
    g.nodes.items[cnot_node].quantum_metadata = .{
        .gate_type = .CNOT,
        .qubits = cnot_qubits,
        .parameters = &.{},
    };
    try g.nodes.items[cnot_node].inputs.append(allocator, h_node);

    // Gate 3: Measure qubit 1
    const measure_node = try builder.createNode(.Quantum_Measure);
    var measure_qubits = try allocator.alloc(usize, 1);
    measure_qubits[0] = 1;
    g.nodes.items[measure_node].quantum_metadata = .{
        .gate_type = .Hadamard, // Placeholder
        .qubits = measure_qubits,
        .parameters = &.{},
    };
    try g.nodes.items[measure_node].inputs.append(allocator, cnot_node);

    // Verify circuit structure
    try testing.expectEqual(@as(usize, 3), g.nodes.items.len);
    try testing.expectEqual(OpCode.Quantum_Gate, g.nodes.items[h_node].op);
    try testing.expectEqual(OpCode.Quantum_Gate, g.nodes.items[cnot_node].op);
    try testing.expectEqual(OpCode.Quantum_Measure, g.nodes.items[measure_node].op);
}
