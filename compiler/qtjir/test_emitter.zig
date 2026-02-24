// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR LLVM IR Emitter Tests

const std = @import("std");
const compat_fs = @import("compat_fs");
const testing = std.testing;
const graph = @import("graph.zig");
const emitter = @import("emitter.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRNode = graph.IRNode;
const OpCode = graph.OpCode;
const IRLevel = graph.IRLevel;
const Tenancy = graph.Tenancy;
const ConstantValue = graph.ConstantValue;
const LLVMEmitter = emitter.LLVMEmitter;

// BDD Scenario 17: Basic LLVM IR Emission
// Given: A QTJIR graph with print("Hello, World!")
// When: LLVM IR emitter processes the graph
// Then: Valid LLVM IR is generated with string constant and puts call
test "Scenario 17: Basic LLVM IR emission for print statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create graph with print statement
    var ir_graph = QTJIRGraph.initWithName(allocator, "main");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // Node 0: String constant "Hello, World!"
    const str_node = try builder.createConstant(.{ .string = "Hello, World!" });

    // Node 1: Call (print)
    const call_node = try builder.createNode(.Call);
    try ir_graph.nodes.items[call_node].inputs.append(allocator, str_node);

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify LLVM IR contains expected elements
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "target triple") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "declare i32 @puts") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@str0") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "Hello, World!") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @main") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "call i32 @puts") != null);
}

// BDD Scenario 18: Function Emission with Return
// Given: A QTJIR graph with return 42
// When: LLVM IR emitter processes the graph
// Then: Function signature and return statement are correctly emitted
test "Scenario 18: Function emission with return value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create graph with return statement
    var ir_graph = QTJIRGraph.initWithName(allocator, "test_func");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // Node 0: Integer constant 42
    const int_node = try builder.createConstant(.{ .integer = 42 });

    // Node 1: Return
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, int_node);

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify function signature and return
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @test_func") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 42") != null);
}

// BDD Scenario 19: Arithmetic Expression Emission
// Given: A QTJIR graph with arithmetic operations (a + b)
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains add instruction
test "Scenario 19: Arithmetic expression emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create graph with addition
    var ir_graph = QTJIRGraph.initWithName(allocator, "add_test");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // Node 0: Integer constant 10
    const a_node = try builder.createConstant(.{ .integer = 10 });

    // Node 1: Integer constant 20
    const b_node = try builder.createConstant(.{ .integer = 20 });

    // Node 2: Add operation
    const add_node = try builder.createNode(.Add);
    try ir_graph.nodes.items[add_node].inputs.append(allocator, a_node);
    try ir_graph.nodes.items[add_node].inputs.append(allocator, b_node);

    // Node 3: Return result
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, add_node);

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify arithmetic operation
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "add i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32") != null);
}

// BDD Scenario 20: Multiple String Constants
// Given: A QTJIR graph with multiple print statements
// When: LLVM IR emitter processes the graph
// Then: All string constants are emitted with unique IDs
test "Scenario 20: Multiple string constants emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create graph with multiple prints
    var ir_graph = QTJIRGraph.initWithName(allocator, "multi_print");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // First print
    const str1_node = try builder.createConstant(.{ .string = "First message" });
    const call1_node = try builder.createNode(.Call);
    try ir_graph.nodes.items[call1_node].inputs.append(allocator, str1_node);

    // Second print
    const str2_node = try builder.createConstant(.{ .string = "Second message" });
    const call2_node = try builder.createNode(.Call);
    try ir_graph.nodes.items[call2_node].inputs.append(allocator, str2_node);

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify both string constants
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@str0") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@str1") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "First message") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "Second message") != null);
}

// BDD Scenario 21: Control Flow Emission (Branch)
// Given: A QTJIR graph with branch node
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains function definition
test "Scenario 21: Control flow emission with branch" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create graph with branch (simplified - just structure test)
    var ir_graph = QTJIRGraph.initWithName(allocator, "branch_test");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // Create a simple branch node (condition will be added in future)
    const branch_node = try builder.createNode(.Branch);

    // Return 0 (simplified)
    const ret_val = try builder.createConstant(.{ .integer = 0 });
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, ret_val);

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify basic structure
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @branch_test") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 0") != null);
    // Note: Full branch emission will be implemented in task 4.1.2
    _ = branch_node; // Suppress unused warning
}

// ============================================================================
// Task 4.1.2: Function Emission Tests
// ============================================================================

// BDD Scenario 22: Function with Parameters
// Given: A QTJIR graph with function parameters
// When: LLVM IR emitter processes the graph
// Then: Function signature includes parameter declarations
test "Scenario 22: Function emission with parameters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create graph with parameters: func add(a: i32, b: i32) -> i32
    // Create graph with parameters: func add(a: i32, b: i32) -> i32
    var ir_graph = QTJIRGraph.initWithName(allocator, "add");
    defer {
        ir_graph.parameters = &.{};
        ir_graph.deinit();
    }

    // Set function parameters
    const params = [_]graph.Parameter{
        .{ .name = "a", .type_name = "i32" },
        .{ .name = "b", .type_name = "i32" },
    };
    ir_graph.parameters = &params;

    var builder = graph.IRBuilder.init(&ir_graph);

    // Return a + b (simplified - just return first param for now)
    const param_a = try builder.createNode(.Load); // Load parameter 'a'
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, param_a);

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify function signature with parameters
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @add(i32 %a, i32 %b)") != null);
}

// BDD Scenario 23: Function with No Parameters
// Given: A QTJIR graph with no parameters
// When: LLVM IR emitter processes the graph
// Then: Function signature has empty parameter list
test "Scenario 23: Function emission with no parameters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create graph: func get_value() -> i32
    var ir_graph = QTJIRGraph.initWithName(allocator, "get_value");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // Return constant
    const ret_val = try builder.createConstant(.{ .integer = 42 });
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, ret_val);

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify function signature with no parameters
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @get_value()") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 42") != null);
}

// BDD Scenario 24: Function with Multiple Return Paths
// Given: A QTJIR graph with multiple return statements
// When: LLVM IR emitter processes the graph
// Then: All return paths are correctly emitted
test "Scenario 24: Function with multiple return paths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create graph with two returns (simplified)
    var ir_graph = QTJIRGraph.initWithName(allocator, "multi_return");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // First return path
    const ret_val1 = try builder.createConstant(.{ .integer = 1 });
    const ret_node1 = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node1].inputs.append(allocator, ret_val1);

    // Second return path (in real code, would be in different basic block)
    const ret_val2 = try builder.createConstant(.{ .integer = 2 });
    const ret_node2 = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node2].inputs.append(allocator, ret_val2);

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify both returns are emitted
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 1") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 2") != null);
}

// BDD Scenario 25: Function Entry Block
// Given: A QTJIR graph with function body
// When: LLVM IR emitter processes the graph
// Then: Entry block is correctly labeled
test "Scenario 25: Function entry block emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create simple function
    var ir_graph = QTJIRGraph.initWithName(allocator, "test_entry");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // Simple return
    const ret_val = try builder.createConstant(.{ .integer = 0 });
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, ret_val);

    // Emit LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify entry block
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @test_entry() {") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "entry:") != null);
}

// ============================================================================
// Task 4.1.3: Expression Emission Tests
// ============================================================================

// BDD Scenario 26: Subtraction Operation
// Given: A QTJIR graph with subtraction (a - b)
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains sub instruction
test "Scenario 26: Subtraction operation emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "sub_test");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // 20 - 10
    const a_node = try builder.createConstant(.{ .integer = 20 });
    const b_node = try builder.createConstant(.{ .integer = 10 });

    const sub_node = try builder.createNode(.Sub);
    try ir_graph.nodes.items[sub_node].inputs.append(allocator, a_node);
    try ir_graph.nodes.items[sub_node].inputs.append(allocator, b_node);

    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, sub_node);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    try testing.expect(std.mem.indexOf(u8, llvm_ir, "sub i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32") != null);
}

// BDD Scenario 27: Multiplication Operation
// Given: A QTJIR graph with multiplication (a * b)
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains mul instruction
test "Scenario 27: Multiplication operation emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "mul_test");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // 5 * 6
    const a_node = try builder.createConstant(.{ .integer = 5 });
    const b_node = try builder.createConstant(.{ .integer = 6 });

    const mul_node = try builder.createNode(.Mul);
    try ir_graph.nodes.items[mul_node].inputs.append(allocator, a_node);
    try ir_graph.nodes.items[mul_node].inputs.append(allocator, b_node);

    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, mul_node);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    try testing.expect(std.mem.indexOf(u8, llvm_ir, "mul i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32") != null);
}

// BDD Scenario 28: Division Operation
// Given: A QTJIR graph with division (a / b)
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains sdiv instruction (signed division)
test "Scenario 28: Division operation emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "div_test");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // 100 / 5
    const a_node = try builder.createConstant(.{ .integer = 100 });
    const b_node = try builder.createConstant(.{ .integer = 5 });

    const div_node = try builder.createNode(.Div);
    try ir_graph.nodes.items[div_node].inputs.append(allocator, a_node);
    try ir_graph.nodes.items[div_node].inputs.append(allocator, b_node);

    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, div_node);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    try testing.expect(std.mem.indexOf(u8, llvm_ir, "sdiv i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32") != null);
}

// BDD Scenario 29: Complex Expression (a + b) * c
// Given: A QTJIR graph with nested arithmetic operations
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains both add and mul instructions in correct order
test "Scenario 29: Complex expression emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "complex_test");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // (10 + 20) * 3
    const a_node = try builder.createConstant(.{ .integer = 10 });
    const b_node = try builder.createConstant(.{ .integer = 20 });
    const c_node = try builder.createConstant(.{ .integer = 3 });

    // First: a + b
    const add_node = try builder.createNode(.Add);
    try ir_graph.nodes.items[add_node].inputs.append(allocator, a_node);
    try ir_graph.nodes.items[add_node].inputs.append(allocator, b_node);

    // Then: result * c
    const mul_node = try builder.createNode(.Mul);
    try ir_graph.nodes.items[mul_node].inputs.append(allocator, add_node);
    try ir_graph.nodes.items[mul_node].inputs.append(allocator, c_node);

    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, mul_node);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify both operations are present
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "add i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "mul i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32") != null);
}

// ============================================================================
// Task 4.1.4: Control Flow Emission Tests
// ============================================================================

// BDD Scenario 30: Basic Branch Instruction
// Given: A QTJIR graph with a branch node
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains br instruction
test "Scenario 30: Basic branch instruction emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "branch_simple");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // Create a simple conditional: if (true) return 1; else return 0;
    // For now, just test basic block structure
    const true_val = try builder.createConstant(.{ .integer = 1 });
    const false_val = try builder.createConstant(.{ .integer = 0 });

    // Branch node (condition will be added later)
    const branch_node = try builder.createNode(.Branch);

    // Two return paths (simplified - in real code would be in separate blocks)
    const ret_true = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_true].inputs.append(allocator, true_val);

    const ret_false = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_false].inputs.append(allocator, false_val);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify basic structure (branch emission is placeholder for now)
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @branch_simple") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "entry:") != null);
    // Note: Full branch emission with basic blocks will be implemented incrementally
    _ = branch_node; // Suppress unused warning
}

// BDD Scenario 31: Phi Node Emission
// Given: A QTJIR graph with a phi node (SSA merge point)
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains phi instruction
test "Scenario 31: Phi node emission for SSA" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "phi_test");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // Create phi node: %result = phi i32 [%val1, %block1], [%val2, %block2]
    const val1 = try builder.createConstant(.{ .integer = 10 });
    const val2 = try builder.createConstant(.{ .integer = 20 });

    const phi_node = try builder.createNode(.Phi);
    try ir_graph.nodes.items[phi_node].inputs.append(allocator, val1);
    try ir_graph.nodes.items[phi_node].inputs.append(allocator, val2);

    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, phi_node);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify phi instruction
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "phi i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32") != null);
}

// BDD Scenario 32: Load Operation
// Given: A QTJIR graph with a load node (parameter access)
// When: LLVM IR emitter processes the graph
// Then: LLVM IR references the parameter correctly
test "Scenario 32: Load operation for parameter access" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "load_test");
    defer {
        ir_graph.parameters = &.{};
        ir_graph.deinit();
    }

    // Function with parameter
    const params = [_]graph.Parameter{
        .{ .name = "x", .type_name = "i32" },
    };
    ir_graph.parameters = &params;

    var builder = graph.IRBuilder.init(&ir_graph);

    // Load parameter and return it
    const load_node = try builder.createNode(.Load);
    // Store parameter index in node metadata (simplified)
    ir_graph.nodes.items[load_node].data = .{ .integer = 0 }; // Parameter index

    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, load_node);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify parameter reference
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @load_test(i32 %x)") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 %x") != null);
}

// ============================================================================
// Epic 4.2: Tensor/Quantum Backend Integration Tests
// ============================================================================

// BDD Scenario 33: Tensor Matrix Multiplication Backend Call
// Given: A QTJIR graph with Tensor_Matmul operation
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains call to NPU runtime library
test "Scenario 33: Tensor matmul backend call emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "tensor_matmul");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);
    builder.current_tenancy = .NPU_Tensor;

    // Create tensor matmul: C = A @ B
    const a_node = try builder.createConstant(.{ .integer = 0 }); // Tensor handle A
    const b_node = try builder.createConstant(.{ .integer = 1 }); // Tensor handle B

    const matmul_node = try builder.createNode(.Tensor_Matmul);
    try ir_graph.nodes.items[matmul_node].inputs.append(allocator, a_node);
    try ir_graph.nodes.items[matmul_node].inputs.append(allocator, b_node);

    // Add tensor metadata - heap allocated
    var shape = try allocator.alloc(usize, 2);
    shape[0] = 128;
    shape[1] = 256;
    ir_graph.nodes.items[matmul_node].tensor_metadata = .{
        .shape = shape,
        .dtype = .f32,
        .layout = .RowMajor,
    };

    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, matmul_node);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify NPU runtime call
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@npu_tensor_matmul") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "call") != null);
}

// BDD Scenario 34: Quantum Gate Backend Call
// Given: A QTJIR graph with Quantum_Gate operation
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains call to QPU runtime library
test "Scenario 34: Quantum gate backend call emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "quantum_hadamard");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);
    builder.current_tenancy = .QPU_Quantum;

    // Create quantum gate: hadamard(q0)
    const gate_node = try builder.createNode(.Quantum_Gate);

    // Add quantum metadata
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0; // Qubit index 0

    ir_graph.nodes.items[gate_node].quantum_metadata = .{
        .gate_type = .Hadamard,
        .qubits = qubits,
        .parameters = &[_]f64{},
    };

    const ret_node = try builder.createNode(.Return);
    const ret_val = try builder.createConstant(.{ .integer = 0 });
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, ret_val);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify QPU runtime call
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@qpu_apply_gate") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "call") != null);
}

// BDD Scenario 35: Quantum Measurement Backend Call
// Given: A QTJIR graph with Quantum_Measure operation
// When: LLVM IR emitter processes the graph
// Then: LLVM IR contains call to QPU measurement function
test "Scenario 35: Quantum measurement backend call emission" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ir_graph = QTJIRGraph.initWithName(allocator, "quantum_measure");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);
    builder.current_tenancy = .QPU_Quantum;

    // Create quantum measurement: measure(q0)
    const measure_node = try builder.createNode(.Quantum_Measure);

    // Add quantum metadata
    var qubits = try allocator.alloc(usize, 1);
    qubits[0] = 0; // Qubit index 0

    ir_graph.nodes.items[measure_node].quantum_metadata = .{
        .gate_type = .Hadamard, // Unused for measurement
        .qubits = qubits,
        .parameters = &[_]f64{},
    };

    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, measure_node);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify QPU measurement call
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@qpu_measure") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "call") != null);
}

// ============================================================================
// Epic 4.3: JIT Compilation Support Tests
// ============================================================================

// BDD Scenario 36: LLVM IR to Executable Compilation
// Given: Valid LLVM IR code
// When: Emitter compiles to executable
// Then: Executable file is created successfully
test "Scenario 36: LLVM IR to executable compilation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create simple function that returns 42
    var ir_graph = QTJIRGraph.initWithName(allocator, "main");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    const ret_val = try builder.createConstant(.{ .integer = 42 });
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, ret_val);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // compileToExecutable removed in 0.16 — e2e tests use std.process.run pipeline
    // Verify IR was generated (functional test only)
    try testing.expect(llvm_ir.len > 0);
}

// BDD Scenario 37: JIT Execution Interface
// Given: A QTJIR graph with simple computation
// When: JIT executor runs the code
// Then: Result is computed correctly
test "Scenario 37: JIT execution interface" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create function: add(10, 20) = 30
    var ir_graph = QTJIRGraph.initWithName(allocator, "compute");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    const a_node = try builder.createConstant(.{ .integer = 10 });
    const b_node = try builder.createConstant(.{ .integer = 20 });

    const add_node = try builder.createNode(.Add);
    try ir_graph.nodes.items[add_node].inputs.append(allocator, a_node);
    try ir_graph.nodes.items[add_node].inputs.append(allocator, b_node);

    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, add_node);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify LLVM IR is valid
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "add i32 10, 20") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32") != null);

    // Note: Actual JIT execution would require LLVM ORC JIT integration
    // For now, we verify the IR is correct
}

// BDD Scenario 38: Module Caching for Hot-Reload
// Given: A compiled QTJIR module
// When: Module is cached for hot-reload
// Then: Cache entry is created with module metadata
test "Scenario 38: Module caching for hot-reload" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create simple module
    var ir_graph = QTJIRGraph.initWithName(allocator, "cached_module");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    const ret_val = try builder.createConstant(.{ .integer = 0 });
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, ret_val);

    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify module can be cached (IR is valid and complete)
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @cached_module") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "entry:") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 0") != null);

    // Note: Actual caching would require module management infrastructure
    // For now, we verify the module structure is cacheable
}

// ============================================================================
// Epic 4.4: End-to-End Pipeline Integration Tests
// ============================================================================

// BDD Scenario 39: Hello World End-to-End
// Given: A complete "Hello, World!" program in QTJIR
// When: Full pipeline processes the graph
// Then: Valid executable LLVM IR is generated
test "Scenario 39: Hello World end-to-end pipeline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create complete Hello World program
    var ir_graph = QTJIRGraph.initWithName(allocator, "main");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // print("Hello, World!")
    const str_node = try builder.createConstant(.{ .string = "Hello, World!" });
    const call_node = try builder.createNode(.Call);
    try ir_graph.nodes.items[call_node].inputs.append(allocator, str_node);

    // return 0
    const ret_val = try builder.createConstant(.{ .integer = 0 });
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, ret_val);

    // Full pipeline: Graph → LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify complete program structure
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "target triple") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@str0") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "Hello, World!") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @main()") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "call i32 @puts") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 0") != null);
}

// BDD Scenario 40: Arithmetic Computation End-to-End
// Given: A complete arithmetic program in QTJIR
// When: Full pipeline processes the graph
// Then: Valid LLVM IR with all operations is generated
test "Scenario 40: Arithmetic computation end-to-end pipeline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create program: (10 + 20) * 3 - 5 = 85
    var ir_graph = QTJIRGraph.initWithName(allocator, "compute");
    defer ir_graph.deinit();

    var builder = graph.IRBuilder.init(&ir_graph);

    // 10 + 20
    const a = try builder.createConstant(.{ .integer = 10 });
    const b = try builder.createConstant(.{ .integer = 20 });
    const add_node = try builder.createNode(.Add);
    try ir_graph.nodes.items[add_node].inputs.append(allocator, a);
    try ir_graph.nodes.items[add_node].inputs.append(allocator, b);

    // result * 3
    const c = try builder.createConstant(.{ .integer = 3 });
    const mul_node = try builder.createNode(.Mul);
    try ir_graph.nodes.items[mul_node].inputs.append(allocator, add_node);
    try ir_graph.nodes.items[mul_node].inputs.append(allocator, c);

    // result - 5
    const d = try builder.createConstant(.{ .integer = 5 });
    const sub_node = try builder.createNode(.Sub);
    try ir_graph.nodes.items[sub_node].inputs.append(allocator, mul_node);
    try ir_graph.nodes.items[sub_node].inputs.append(allocator, d);

    // return result
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, sub_node);

    // Full pipeline: Graph → LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify all operations present
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "add i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "mul i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "sub i32") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32") != null);
}

// BDD Scenario 41: Function with Parameters End-to-End
// Given: A complete function with parameters in QTJIR
// When: Full pipeline processes the graph
// Then: Valid LLVM IR with parameter handling is generated
test "Scenario 41: Function with parameters end-to-end pipeline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create function: add(a: i32, b: i32) -> i32 { return a + b; }
    // Create function: add(a: i32, b: i32) -> i32 { return a + b; }
    var ir_graph = QTJIRGraph.initWithName(allocator, "add");
    defer {
        // Clear parameters to prevent invalid free of static memory
        ir_graph.parameters = &.{};
        ir_graph.deinit();
    }

    const params = [_]graph.Parameter{
        .{ .name = "a", .type_name = "i32" },
        .{ .name = "b", .type_name = "i32" },
    };
    ir_graph.parameters = &params;

    var builder = graph.IRBuilder.init(&ir_graph);

    // Load parameters (simplified - using constants as placeholders)
    const a_load = try builder.createNode(.Load);
    ir_graph.nodes.items[a_load].data = .{ .integer = 0 };

    const b_load = try builder.createNode(.Load);
    ir_graph.nodes.items[b_load].data = .{ .integer = 1 };

    // For this test, just return first parameter
    const ret_node = try builder.createNode(.Return);
    try ir_graph.nodes.items[ret_node].inputs.append(allocator, a_load);

    // Full pipeline: Graph → LLVM IR
    var llvm_emitter = LLVMEmitter.init(allocator);
    defer llvm_emitter.deinit();

    const llvm_ir = try llvm_emitter.emit(&ir_graph);
    defer allocator.free(llvm_ir);

    // Verify function signature and parameter handling
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @add(i32 %a, i32 %b)") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 %a") != null);
}
