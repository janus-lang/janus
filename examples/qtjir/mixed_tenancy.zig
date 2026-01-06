// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// QTJIR Example: Mixed Tenancy Program (CPU + NPU + QPU)

const std = @import("std");
const graph = @import("../../compiler/qtjir/graph.zig");
const emitter = @import("../../compiler/qtjir/emitter.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const LLVMEmitter = emitter.LLVMEmitter;

/// Example: Mixed tenancy program combining CPU, NPU, and QPU operations
/// Demonstrates:
/// - Multiple execution targets in one program
/// - Tenancy switching
/// - Cross-tenancy data flow
/// - Heterogeneous acceleration
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("QTJIR Example: Mixed Tenancy Program\n", .{});
    std.debug.print("=====================================\n\n", .{});

    // Create graph for mixed tenancy computation
    var graph_instance = QTJIRGraph.initWithName(allocator, "mixed_tenancy");
    defer graph_instance.deinit();

    var builder = IRBuilder.init(&graph_instance);

    // Phase 1: CPU computation
    std.debug.print("Phase 1: CPU Serial Computation\n", .{});
    std.debug.print("--------------------------------\n", .{});
    builder.current_tenancy = .CPU_Serial;

    const cpu_a = try builder.createConstant(.{ .integer = 100 });
    const cpu_b = try builder.createConstant(.{ .integer = 50 });

    std.debug.print("Creating CPU addition: 100 + 50\n", .{});
    const cpu_add = try builder.createNode(.Add);
    try graph_instance.nodes.items[cpu_add].inputs.append(allocator, cpu_a);
    try graph_instance.nodes.items[cpu_add].inputs.append(allocator, cpu_b);

    // Phase 2: NPU tensor computation
    std.debug.print("\nPhase 2: NPU Tensor Computation\n", .{});
    std.debug.print("-------------------------------\n", .{});
    builder.current_tenancy = .NPU_Tensor;

    const tensor_a = try builder.createConstant(.{ .integer = 0 });
    const tensor_b = try builder.createConstant(.{ .integer = 1 });

    std.debug.print("Creating tensor matmul operation\n", .{});
    const matmul_node = try builder.createNode(.Tensor_Matmul);
    try graph_instance.nodes.items[matmul_node].inputs.append(allocator, tensor_a);
    try graph_instance.nodes.items[matmul_node].inputs.append(allocator, tensor_b);

    var shape = try allocator.alloc(usize, 2);
    shape[0] = 64;
    shape[1] = 128;

    graph_instance.nodes.items[matmul_node].tensor_metadata = .{
        .shape = shape,
        .dtype = .f32,
        .layout = .RowMajor,
    };

    std.debug.print("Tensor shape: [64, 128]\n", .{});
    std.debug.print("Data type: f32\n", .{});

    // Phase 3: QPU quantum computation
    std.debug.print("\nPhase 3: QPU Quantum Computation\n", .{});
    std.debug.print("--------------------------------\n", .{});
    builder.current_tenancy = .QPU_Quantum;

    std.debug.print("Creating quantum gate operation\n", .{});
    const quantum_gate = try builder.createNode(.Quantum_Gate);
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;

    graph_instance.nodes.items[quantum_gate].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = qubits,
        .parameters = &[_]f64{},
    };

    std.debug.print("Gate: Hadamard on qubit 0\n", .{});

    // Phase 4: Measurement
    std.debug.print("\nPhase 4: Quantum Measurement\n", .{});
    std.debug.print("----------------------------\n", .{});

    const measure = try builder.createNode(.Quantum_Measure);
    var measure_qubits = try allocator.alloc(usize, 1);
    measure_qubits[0] = 0;

    graph_instance.nodes.items[measure].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = measure_qubits,
        .parameters = &[_]f64{},
    };

    std.debug.print("Measuring qubit 0\n", .{});

    // Create return
    const ret_node = try builder.createNode(.Return);
    try graph_instance.nodes.items[ret_node].inputs.append(allocator, measure);

    // Validate graph
    std.debug.print("\nValidating mixed tenancy graph...\n", .{});
    _ = try graph_instance.validate();
    std.debug.print("✅ Graph validation passed\n", .{});

    // Emit LLVM IR
    std.debug.print("\nEmitting LLVM IR with mixed backend calls...\n", .{});
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&graph_instance);
    defer allocator.free(llvm_ir);

    std.debug.print("✅ LLVM IR emission successful\n\n", .{});

    // Print generated LLVM IR
    std.debug.print("Generated LLVM IR:\n", .{});
    std.debug.print("==================\n", .{});
    std.debug.print("{s}\n", .{llvm_ir});

    // Verify all backend calls
    std.debug.print("\nBackend verification:\n", .{});
    var backend_count: u32 = 0;

    if (std.mem.indexOf(u8, llvm_ir, "add i32") != null) {
        std.debug.print("✅ CPU arithmetic operation found\n", .{});
        backend_count += 1;
    }

    if (std.mem.indexOf(u8, llvm_ir, "@npu_tensor_matmul") != null) {
        std.debug.print("✅ NPU tensor operation found\n", .{});
        backend_count += 1;
    }

    if (std.mem.indexOf(u8, llvm_ir, "@qpu_apply_gate") != null) {
        std.debug.print("✅ QPU gate operation found\n", .{});
        backend_count += 1;
    }

    if (std.mem.indexOf(u8, llvm_ir, "@qpu_measure") != null) {
        std.debug.print("✅ QPU measurement found\n", .{});
        backend_count += 1;
    }

    std.debug.print("\nTotal backends utilized: {d}/4\n", .{backend_count});

    std.debug.print("\nMixed tenancy explanation:\n", .{});
    std.debug.print("This program demonstrates heterogeneous acceleration:\n", .{});
    std.debug.print("1. CPU handles scalar arithmetic (fast for small ops)\n", .{});
    std.debug.print("2. NPU accelerates tensor operations (matrix multiply)\n", .{});
    std.debug.print("3. QPU executes quantum algorithms (quantum gates)\n", .{});
    std.debug.print("4. Results are measured and returned\n", .{});
}
