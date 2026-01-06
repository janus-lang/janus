// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Test suite for QTJIR quantum validation (Phase 2 - Task 2.2.3)

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const OpCode = graph.OpCode;
const GateType = graph.GateType;
const QuantumMetadata = graph.QuantumMetadata;

// ============================================================================
// Test 1: Valid quantum circuit should pass validation
// ============================================================================

test "QTJIR: Valid Quantum Circuit Passes Validation" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_valid_quantum";
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create H → CNOT → Measure circuit with valid qubit indices
    const h_node = try builder.createNode(.Quantum_Gate);
    var h_qubits = try allocator.alloc(usize, 1);
    h_qubits[0] = 0;
    g.nodes.items[h_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = h_qubits,
        .parameters = &.{},
    };
    
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
    
    const measure_node = try builder.createNode(.Quantum_Measure);
    var measure_qubits = try allocator.alloc(usize, 1);
    measure_qubits[0] = 1;
    g.nodes.items[measure_node].quantum_metadata = .{
        .gate_type = .Hadamard,  // Placeholder
        .qubits = measure_qubits,
        .parameters = &.{},
    };
    try g.nodes.items[measure_node].inputs.append(allocator, cnot_node);
    
    // Should validate successfully
    var result = try g.validate();
    defer result.deinit();
    
    try testing.expect(!result.has_errors);
}

// ============================================================================
// Test 2: Quantum operation without metadata should fail validation
// ============================================================================

test "QTJIR: Quantum Operation Without Metadata Fails Validation" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_missing_metadata";
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create quantum gate without metadata
    _ = try builder.createNode(.Quantum_Gate);
    
    // Should fail validation
    var result = try g.validate();
    defer result.deinit();
    
    try testing.expect(result.has_errors);
    
    // Verify error mentions missing metadata
    var found_metadata_error = false;
    for (result.diagnostics.items) |diag| {
        if (std.mem.indexOf(u8, diag.message, "metadata") != null) {
            found_metadata_error = true;
            break;
        }
    }
    try testing.expect(found_metadata_error);
}

// ============================================================================
// Test 3: Qubit index out of range should fail validation
// ============================================================================

test "QTJIR: Qubit Index Out of Range Generates Warning" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_qubit_out_of_range";
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create gate with qubit index 100 (out of reasonable range)
    const gate_node = try builder.createNode(.Quantum_Gate);
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 100;  // Unreasonably high qubit index
    
    g.nodes.items[gate_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = qubits,
        .parameters = &.{},
    };
    
    // Should generate warning about high qubit index
    var result = try g.validate();
    defer result.deinit();
    
    // Should have at least one diagnostic (warning about qubit count)
    try testing.expect(result.diagnostics.items.len > 0);
    
    // Verify warning mentions qubit index
    var found_qubit_warning = false;
    for (result.diagnostics.items) |diag| {
        if (std.mem.indexOf(u8, diag.message, "qubit") != null and
            std.mem.indexOf(u8, diag.message, "100") != null) {
            found_qubit_warning = true;
            break;
        }
    }
    try testing.expect(found_qubit_warning);
}

// ============================================================================
// Test 4: CNOT gate with same control and target should fail validation
// ============================================================================

test "QTJIR: CNOT Same Control and Target Fails Validation" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_cnot_same_qubits";
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create CNOT with same qubit as control and target
    const cnot_node = try builder.createNode(.Quantum_Gate);
    var qubits = try allocator.alloc(usize, 2);
    qubits[0] = 0;  // Control
    qubits[1] = 0;  // Target (same as control - invalid!)
    
    g.nodes.items[cnot_node].quantum_metadata = .{
        .gate_type = .CNOT,
        .qubits = qubits,
        .parameters = &.{},
    };
    
    // Should fail validation
    var result = try g.validate();
    defer result.deinit();
    
    try testing.expect(result.has_errors);
}

// ============================================================================
// Test 5: Rotation gate with invalid angle should fail validation
// ============================================================================

test "QTJIR: Rotation Gate Invalid Angle Fails Validation" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_invalid_rotation";
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create RX gate with NaN parameter
    const rx_node = try builder.createNode(.Quantum_Gate);
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;
    
    var params = try allocator.alloc(f64, 1);
    params[0] = std.math.nan(f64);  // Invalid parameter
    
    g.nodes.items[rx_node].quantum_metadata = .{
        .gate_type = .RX,
        .qubits = qubits,
        .parameters = params,
    };
    
    // Should fail validation
    var result = try g.validate();
    defer result.deinit();
    
    try testing.expect(result.has_errors);
}

// ============================================================================
// Test 6: Rotation gate without parameter should fail validation
// ============================================================================

test "QTJIR: Rotation Gate Missing Parameter Fails Validation" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_missing_parameter";
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create RX gate without parameter
    const rx_node = try builder.createNode(.Quantum_Gate);
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;
    
    g.nodes.items[rx_node].quantum_metadata = .{
        .gate_type = .RX,
        .qubits = qubits,
        .parameters = &.{},  // Missing parameter!
    };
    
    // Should fail validation
    var result = try g.validate();
    defer result.deinit();
    
    try testing.expect(result.has_errors);
}

// ============================================================================
// Test 7: QPU_Quantum tenancy consistency validation
// ============================================================================

test "QTJIR: QPU_Quantum Tenancy Consistency" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_tenancy_consistency";
    
    var builder = IRBuilder.init(&g);
    
    // Create quantum gate with wrong tenancy
    builder.current_tenancy = .CPU_Serial;  // Wrong tenancy!
    const gate_node = try builder.createNode(.Quantum_Gate);
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;
    
    g.nodes.items[gate_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = qubits,
        .parameters = &.{},
    };
    
    // Should generate warning about tenancy mismatch
    var result = try g.validate();
    defer result.deinit();
    
    // Should have at least a warning
    try testing.expect(result.diagnostics.items.len > 0);
}

// ============================================================================
// Test 8: Toffoli gate with insufficient qubits should fail validation
// ============================================================================

test "QTJIR: Toffoli Gate Insufficient Qubits Fails Validation" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_toffoli_insufficient";
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create Toffoli gate with only 2 qubits (needs 3)
    const toffoli_node = try builder.createNode(.Quantum_Gate);
    var qubits = try allocator.alloc(usize, 2);
    qubits[0] = 0;
    qubits[1] = 1;
    
    g.nodes.items[toffoli_node].quantum_metadata = .{
        .gate_type = .Toffoli,
        .qubits = qubits,
        .parameters = &.{},
    };
    
    // Should fail validation
    var result = try g.validate();
    defer result.deinit();
    
    try testing.expect(result.has_errors);
}

// ============================================================================
// Test 9: Valid rotation gate with valid angle passes validation
// ============================================================================

test "QTJIR: Valid Rotation Gate Passes Validation" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_valid_rotation";
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create RX gate with valid parameter
    const rx_node = try builder.createNode(.Quantum_Gate);
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;
    
    var params = try allocator.alloc(f64, 1);
    params[0] = std.math.pi / 2.0;  // Valid angle
    
    g.nodes.items[rx_node].quantum_metadata = .{
        .gate_type = .RX,
        .qubits = qubits,
        .parameters = params,
    };
    
    // Should validate successfully
    var result = try g.validate();
    defer result.deinit();
    
    try testing.expect(!result.has_errors);
}

// ============================================================================
// Test 10: Measurement without metadata should fail validation
// ============================================================================

test "QTJIR: Measurement Without Metadata Fails Validation" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    g.function_name = "test_measure_no_metadata";
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create measurement without metadata
    _ = try builder.createNode(.Quantum_Measure);
    
    // Should fail validation
    var result = try g.validate();
    defer result.deinit();
    
    try testing.expect(result.has_errors);
}
