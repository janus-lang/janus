// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Test suite for QTJIR quantum optimization passes (Phase 3)

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");
const transforms = @import("transforms.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const OpCode = graph.OpCode;
const Tenancy = graph.Tenancy;
const PassManager = transforms.PassManager;
const OptimizeQuantumGates = transforms.OptimizeQuantumGates;

// ============================================================================
// Test 1: Optimize H-H (Hadamard Cancellation)
// ============================================================================

test "QTJIR Quantum Opt: Cancel H-H Gates" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    // Create graph: Input -> H -> H -> Measure
    const input = try builder.createNode(.Constant); // Represents initial state
    
    // H1
    const h1 = try builder.createNode(.Quantum_Gate);
    try g.nodes.items[h1].inputs.append(allocator, input);
    var h1_qubits = try allocator.alloc(usize, 1);
    h1_qubits[0] = 0;
    g.nodes.items[h1].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = h1_qubits,
        .parameters = &.{},
    };
    
    // H2
    const h2 = try builder.createNode(.Quantum_Gate);
    try g.nodes.items[h2].inputs.append(allocator, h1);
    var h2_qubits = try allocator.alloc(usize, 1);
    h2_qubits[0] = 0;
    g.nodes.items[h2].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = h2_qubits,
        .parameters = &.{},
    };
    
    // Measure
    const measure = try builder.createNode(.Quantum_Measure);
    try g.nodes.items[measure].inputs.append(allocator, h2);
    var m_qubits = try allocator.alloc(usize, 1);
    m_qubits[0] = 0;
    g.nodes.items[measure].quantum_metadata = .{
        .gate_type = .Hadamard, // Placeholder
        .qubits = m_qubits,
        .parameters = &.{},
    };
    
    // Run Optimization Pass
    var pm = PassManager.init(allocator);
    defer pm.deinit();
    
    var opt_pass = OptimizeQuantumGates.init(allocator);
    try pm.addPass(opt_pass.transform());
    
    try pm.run(&g);
    
    // Verify Optimization
    const measure_node = &g.nodes.items[measure];
    
    // Measure should now depend on Input, bypassing H1 and H2
    try testing.expectEqual(@as(usize, 1), measure_node.inputs.items.len);
    try testing.expectEqual(input, measure_node.inputs.items[0]);
}

// ============================================================================
// Test 2: Do NOT cancel different gates (H-X)
// ============================================================================

test "QTJIR Quantum Opt: Do Not Cancel H-X" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    const input = try builder.createNode(.Constant);
    
    // H
    const h = try builder.createNode(.Quantum_Gate);
    try g.nodes.items[h].inputs.append(allocator, input);
    var h_qubits = try allocator.alloc(usize, 1);
    h_qubits[0] = 0;
    g.nodes.items[h].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = h_qubits,
        .parameters = &.{},
    };
    
    // X
    const x = try builder.createNode(.Quantum_Gate);
    try g.nodes.items[x].inputs.append(allocator, h);
    var x_qubits = try allocator.alloc(usize, 1);
    x_qubits[0] = 0;
    g.nodes.items[x].quantum_metadata = .{
        .gate_type = .PauliX,
        .qubits = x_qubits,
        .parameters = &.{},
    };
    
    // Measure
    const measure = try builder.createNode(.Quantum_Measure);
    try g.nodes.items[measure].inputs.append(allocator, x);
    
    // Run Optimization Pass
    var pm = PassManager.init(allocator);
    defer pm.deinit();
    
    var opt_pass = OptimizeQuantumGates.init(allocator);
    try pm.addPass(opt_pass.transform());
    
    try pm.run(&g);
    
    // Verify NO Optimization
    const measure_node = &g.nodes.items[measure];
    try testing.expectEqual(x, measure_node.inputs.items[0]);
}
