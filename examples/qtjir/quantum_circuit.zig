// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// QTJIR Example: Quantum Circuit Operations on QPU

const std = @import("std");
const graph = @import("../../compiler/qtjir/graph.zig");
const emitter = @import("../../compiler/qtjir/emitter.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const LLVMEmitter = emitter.LLVMEmitter;

/// Example: Simple quantum circuit (Bell state preparation)
/// Demonstrates:
/// - QPU_Quantum tenancy
/// - Quantum gate operations (Hadamard, CNOT)
/// - Quantum measurement
/// - Quantum metadata (gate type, qubits, parameters)
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("QTJIR Example: Quantum Circuit\n", .{});
    std.debug.print("===============================\n\n", .{});

    // Create graph for Bell state preparation
    var graph_instance = QTJIRGraph.initWithName(allocator, "bell_state");
    defer graph_instance.deinit();

    var builder = IRBuilder.init(&graph_instance);

    // Set tenancy to QPU for quantum operations
    std.debug.print("Setting execution target to QPU_Quantum...\n", .{});
    builder.current_tenancy = .QPU_Quantum;

    // Step 1: Apply Hadamard gate to qubit 0
    std.debug.print("\nStep 1: Apply Hadamard gate to qubit 0\n", .{});
    const h_node = try builder.createNode(.Quantum_Gate);
    var h_qubits = try allocator.alloc(usize, 1);
    h_qubits[0] = 0;
    graph_instance.nodes.items[h_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = h_qubits,
        .parameters = &[_]f64{},
    };
    std.debug.print("  Gate: Hadamard\n", .{});
    std.debug.print("  Qubit: 0\n", .{});

    // Step 2: Apply CNOT gate (control=0, target=1)
    std.debug.print("\nStep 2: Apply CNOT gate (control=0, target=1)\n", .{});
    const cnot_node = try builder.createNode(.Quantum_Gate);
    var cnot_qubits = try allocator.alloc(usize, 2);
    cnot_qubits[0] = 0; // Control qubit
    cnot_qubits[1] = 1; // Target qubit
    graph_instance.nodes.items[cnot_node].quantum_metadata = .{
        .gate_type = .CNOT,
        .qubits = cnot_qubits,
        .parameters = &[_]f64{},
    };
    std.debug.print("  Gate: CNOT\n", .{});
    std.debug.print("  Control qubit: 0\n", .{});
    std.debug.print("  Target qubit: 1\n", .{});

    // Step 3: Measure qubit 0
    std.debug.print("\nStep 3: Measure qubit 0\n", .{});
    const measure_node = try builder.createNode(.Quantum_Measure);
    var measure_qubits = try allocator.alloc(usize, 1);
    measure_qubits[0] = 0;
    graph_instance.nodes.items[measure_node].quantum_metadata = .{
        .gate_type = .Hadamard, // Gate type not used for measurement
        .qubits = measure_qubits,
        .parameters = &[_]f64{},
    };
    std.debug.print("  Measuring qubit: 0\n", .{});

    // Create return
    const ret_node = try builder.createNode(.Return);
    try graph_instance.nodes.items[ret_node].inputs.append(allocator, measure_node);

    // Validate graph
    std.debug.print("\nValidating quantum circuit...\n", .{});
    _ = try graph_instance.validate();
    std.debug.print("✅ Graph validation passed\n", .{});

    // Emit LLVM IR
    std.debug.print("\nEmitting LLVM IR with QPU backend calls...\n", .{});
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&graph_instance);
    defer allocator.free(llvm_ir);

    std.debug.print("✅ LLVM IR emission successful\n\n", .{});

    // Print generated LLVM IR
    std.debug.print("Generated LLVM IR:\n", .{});
    std.debug.print("==================\n", .{});
    std.debug.print("{s}\n", .{llvm_ir});

    // Verify QPU backend calls
    std.debug.print("\nBackend verification:\n", .{});
    if (std.mem.indexOf(u8, llvm_ir, "@qpu_apply_gate") != null) {
        std.debug.print("✅ QPU apply gate backend call found\n", .{});
    } else {
        std.debug.print("❌ QPU apply gate backend call NOT found\n", .{});
    }

    if (std.mem.indexOf(u8, llvm_ir, "@qpu_measure") != null) {
        std.debug.print("✅ QPU measure backend call found\n", .{});
    } else {
        std.debug.print("❌ QPU measure backend call NOT found\n", .{});
    }

    std.debug.print("\nQuantum circuit explanation:\n", .{});
    std.debug.print("This circuit prepares a Bell state (entangled state):\n", .{});
    std.debug.print("1. Hadamard on q0 creates superposition: (|0⟩ + |1⟩)/√2\n", .{});
    std.debug.print("2. CNOT entangles q0 and q1: (|00⟩ + |11⟩)/√2\n", .{});
    std.debug.print("3. Measurement collapses the state\n", .{});
}
