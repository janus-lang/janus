// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR Integration Test Suite - Phase 5 Epic 5.2

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const graph = @import("graph.zig");
const emitter = @import("emitter.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const LLVMEmitter = emitter.LLVMEmitter;

// ============================================================================
// Epic 5.2.1: Comprehensive Integration Tests
// ============================================================================

// Integration test: Full pipeline for simple arithmetic
test "Integration: Simple arithmetic (1 + 2)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create graph
    var g = QTJIRGraph.initWithName(allocator, "add_test");
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create constants
    const const1 = try builder.createConstant(.{ .integer = 1 });
    const const2 = try builder.createConstant(.{ .integer = 2 });

    // Create addition
    const add_node = try builder.createNode(.Add);
    try g.nodes.items[add_node].inputs.append(allocator, const1);
    try g.nodes.items[add_node].inputs.append(allocator, const2);

    // Create return
    const ret_node = try builder.createNode(.Return);
    try g.nodes.items[ret_node].inputs.append(allocator, add_node);

    // Validate graph
    _ = try g.validate();

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&g);
    defer allocator.free(llvm_ir);

    // Verify LLVM IR contains expected elements
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @add_test") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "add i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32") != null);
}

// Integration test: Mixed tenancy program (CPU + NPU)
test "Integration: Mixed tenancy (CPU + NPU)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.initWithName(allocator, "mixed_tenancy");
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // CPU operation
    builder.current_tenancy = .CPU_Serial;
    const cpu_const = try builder.createConstant(.{ .integer = 10 });

    // NPU operation
    builder.current_tenancy = .NPU_Tensor;
    const npu_const = try builder.createConstant(.{ .integer = 20 });
    const matmul_node = try builder.createNode(.Tensor_Matmul);
    try g.nodes.items[matmul_node].inputs.append(allocator, cpu_const);
    try g.nodes.items[matmul_node].inputs.append(allocator, npu_const);

    // Return
    const ret_node = try builder.createNode(.Return);
    try g.nodes.items[ret_node].inputs.append(allocator, matmul_node);

    // Validate
    _ = try g.validate();

    // Emit
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&g);
    defer allocator.free(llvm_ir);

    // Verify mixed tenancy
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@npu_tensor_matmul") != null);
}

// Integration test: Error propagation through pipeline
test "Integration: Error handling in pipeline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create invalid tensor operation (no inputs)
    _ = try builder.createNode(.Tensor_Matmul);

    // Validation should catch missing inputs
    _ = g.validate() catch |err| {
        try testing.expect(err == error.InvalidNodeInputs or err == error.MissingTensorMetadata);
    };
}

// Integration test: Complex expression evaluation
test "Integration: Complex expression (a + b) * (c - d)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.initWithName(allocator, "complex_expr");
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create constants
    const a = try builder.createConstant(.{ .integer = 10 });
    const b = try builder.createConstant(.{ .integer = 20 });
    const c = try builder.createConstant(.{ .integer = 30 });
    const d = try builder.createConstant(.{ .integer = 5 });

    // a + b
    const add_node = try builder.createNode(.Add);
    try g.nodes.items[add_node].inputs.append(allocator, a);
    try g.nodes.items[add_node].inputs.append(allocator, b);

    // c - d
    const sub_node = try builder.createNode(.Sub);
    try g.nodes.items[sub_node].inputs.append(allocator, c);
    try g.nodes.items[sub_node].inputs.append(allocator, d);

    // (a + b) * (c - d)
    const mul_node = try builder.createNode(.Mul);
    try g.nodes.items[mul_node].inputs.append(allocator, add_node);
    try g.nodes.items[mul_node].inputs.append(allocator, sub_node);

    // Return
    const ret_node = try builder.createNode(.Return);
    try g.nodes.items[ret_node].inputs.append(allocator, mul_node);

    // Validate
    _ = try g.validate();

    // Emit
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&g);
    defer allocator.free(llvm_ir);

    // Verify all operations present
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "add i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "sub i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "mul i32") != null);
}

// ============================================================================
// Epic 5.2.2: Golden Tests (Output Stability)
// ============================================================================

// Golden test: Verify consistent LLVM IR output
test "Golden: Hello World LLVM IR stability" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.initWithName(allocator, "hello_world");
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create string constant
    const str_node = try builder.createConstant(.{ .string = "Hello, World!" });

    // Create call to puts
    const call_node = try builder.createNode(.Call);
    try g.nodes.items[call_node].inputs.append(allocator, str_node);

    // Return 0
    const ret_val = try builder.createConstant(.{ .integer = 0 });
    const ret_node = try builder.createNode(.Return);
    try g.nodes.items[ret_node].inputs.append(allocator, ret_val);

    // Emit
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&g);
    defer allocator.free(llvm_ir);

    // Golden output checks
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @hello_world") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "Hello, World!") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@puts") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 0") != null);
}

// Golden test: Verify tensor operation output
test "Golden: Tensor matmul LLVM IR stability" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.initWithName(allocator, "tensor_matmul");
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .NPU_Tensor;

    // Create tensor constants
    const a = try builder.createConstant(.{ .integer = 0 });
    const b = try builder.createConstant(.{ .integer = 1 });

    // Create matmul
    const matmul_node = try builder.createNode(.Tensor_Matmul);
    try g.nodes.items[matmul_node].inputs.append(allocator, a);
    try g.nodes.items[matmul_node].inputs.append(allocator, b);

    // Add metadata - shape must be heap-allocated!
    var shape = try allocator.alloc(usize, 2);
    shape[0] = 128;
    shape[1] = 256;
    g.nodes.items[matmul_node].tensor_metadata = .{
        .shape = shape,
        .dtype = .f32,
        .layout = .RowMajor,
    };

    // Return
    const ret_node = try builder.createNode(.Return);
    try g.nodes.items[ret_node].inputs.append(allocator, matmul_node);

    // Emit
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&g);
    defer allocator.free(llvm_ir);

    // Golden output checks
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @tensor_matmul") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@npu_tensor_matmul") != null);
}

// Golden test: Verify quantum operation output
test "Golden: Quantum circuit LLVM IR stability" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.initWithName(allocator, "quantum_circuit");
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;

    // Create Hadamard gate
    const h_node = try builder.createNode(.Quantum_Gate);
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0;
    g.nodes.items[h_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = qubits,
        .parameters = &[_]f64{},
    };

    // Create measurement
    const measure_node = try builder.createNode(.Quantum_Measure);
    var measure_qubits = try allocator.alloc(usize, 1);
    measure_qubits[0] = 0;
    g.nodes.items[measure_node].quantum_metadata = .{
        .gate_type = .Hadamard, // Gate type not used for measurement
        .qubits = measure_qubits,
        .parameters = &[_]f64{},
    };

    // Return measurement result
    const ret_node = try builder.createNode(.Return);
    try g.nodes.items[ret_node].inputs.append(allocator, measure_node);

    // Validate
    _ = try g.validate();

    // Emit
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&g);
    defer allocator.free(llvm_ir);

    // Golden output checks
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @quantum_circuit") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@qpu_apply_gate") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@qpu_measure") != null);
}

// ============================================================================
// Epic 5.2.3: Performance Characteristics
// ============================================================================

// Performance test: End-to-end pipeline timing
test "Performance: Full pipeline (1000 nodes)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const start_time = compat_time.nanoTimestamp();

    // Create large graph
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create 1000 nodes
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = try builder.createConstant(.{ .integer = @intCast(i) });
    }

    // Validate
    _ = try g.validate();

    // Emit
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&g);
    defer allocator.free(llvm_ir);

    const end_time = compat_time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    std.debug.print("Full pipeline (1000 nodes): {d:.2} ms\n", .{duration_ms});

    // Performance assertion: should complete in reasonable time
    try testing.expect(duration_ms < 500.0);
}

// Performance test: Validation performance
test "Performance: Validation (5000 nodes)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create 5000 nodes
    var i: usize = 0;
    while (i < 5000) : (i += 1) {
        _ = try builder.createConstant(.{ .integer = @intCast(i) });
    }

    const start_time = compat_time.nanoTimestamp();
    _ = try g.validate();
    const end_time = compat_time.nanoTimestamp();

    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    std.debug.print("Validation (5000 nodes): {d:.2} ms\n", .{duration_ms});

    // Performance assertion
    try testing.expect(duration_ms < 100.0);
}

// Performance test: Emission performance
test "Performance: Emission (500 nodes)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create 500 nodes
    var i: usize = 0;
    while (i < 500) : (i += 1) {
        _ = try builder.createConstant(.{ .integer = @intCast(i) });
    }

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const start_time = compat_time.nanoTimestamp();
    const llvm_ir = try llvm_emitter.emit(&g);
    defer allocator.free(llvm_ir);
    const end_time = compat_time.nanoTimestamp();

    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    std.debug.print("Emission (500 nodes): {d:.2} ms\n", .{duration_ms});

    // Performance assertion
    try testing.expect(duration_ms < 200.0);
}
