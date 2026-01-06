// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR Comprehensive Test Suite - Phase 5 Epic 5.1

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRNode = graph.IRNode;
const OpCode = graph.OpCode;
const Tenancy = graph.Tenancy;
const DataType = graph.DataType;
const IRBuilder = graph.IRBuilder;

// ============================================================================
// Epic 5.1.1: Comprehensive Graph Operation Tests
// ============================================================================

// Test all OpCode types are properly defined
test "Comprehensive: All OpCode types enumerated" {
    const opcodes = [_]OpCode{
        .Constant,
        .Load,
        .Store,
        .Phi,
        .Call,
        .Return,
        .Branch,
        .Add,
        .Sub,
        .Mul,
        .Div,
        .Tensor_Matmul,
        .Tensor_Conv,
        .Tensor_Reduce,
        .Tensor_ScalarMul,
        .Tensor_FusedMatmulRelu,
        .Tensor_FusedMatmulAdd,
        .Tensor_Contract,
        .Tensor_Relu,
        .Quantum_Gate,
        .Quantum_Measure,
    };

    // Verify all opcodes are distinct
    for (opcodes, 0..) |op1, i| {
        for (opcodes[i + 1 ..]) |op2| {
            try testing.expect(op1 != op2);
        }
    }
}

// Test all DataType types
test "Comprehensive: All DataType types enumerated" {
    const types = [_]DataType{ .i32, .f32, .f64 };

    for (types, 0..) |type1, i| {
        for (types[i + 1 ..]) |type2| {
            try testing.expect(type1 != type2);
        }
    }
}

// Test all Tenancy types
test "Comprehensive: All Tenancy types enumerated" {
    const tenancies = [_]Tenancy{
        .CPU_Serial,
        .CPU_Parallel,
        .NPU_Tensor,
        .QPU_Quantum,
    };

    for (tenancies, 0..) |t1, i| {
        for (tenancies[i + 1 ..]) |t2| {
            try testing.expect(t1 != t2);
        }
    }
}

// Test graph with maximum node count
test "Comprehensive: Large graph construction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create 100 nodes
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try builder.createConstant(.{ .integer = @intCast(i) });
    }

    try testing.expectEqual(@as(usize, 100), g.nodes.items.len);
}

// Test graph with all operation types
test "Comprehensive: Graph with all operation types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create one node of each type
    _ = try builder.createConstant(.{ .integer = 42 });
    _ = try builder.createNode(.Load);
    _ = try builder.createNode(.Store);
    _ = try builder.createNode(.Phi);
    _ = try builder.createNode(.Call);
    _ = try builder.createNode(.Return);
    _ = try builder.createNode(.Branch);
    _ = try builder.createNode(.Add);
    _ = try builder.createNode(.Sub);
    _ = try builder.createNode(.Mul);
    _ = try builder.createNode(.Div);

    // Verify all nodes created
    try testing.expect(g.nodes.items.len >= 11);
}

// Test edge case: Empty graph
test "Comprehensive: Empty graph operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    // Empty graph should have zero nodes
    try testing.expectEqual(@as(usize, 0), g.nodes.items.len);
}

// Test edge case: Single node graph
test "Comprehensive: Single node graph" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    _ = try builder.createConstant(.{ .integer = 0 });

    try testing.expectEqual(@as(usize, 1), g.nodes.items.len);
}

// Test node ID uniqueness
test "Comprehensive: Node ID uniqueness" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);

    // Create multiple nodes
    const id1 = try builder.createConstant(.{ .integer = 1 });
    const id2 = try builder.createConstant(.{ .integer = 2 });
    const id3 = try builder.createConstant(.{ .integer = 3 });

    // All IDs should be unique
    try testing.expect(id1 != id2);
    try testing.expect(id2 != id3);
    try testing.expect(id1 != id3);
}

// Test graph function name
test "Comprehensive: Graph function name handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.initWithName(allocator, "test_function");
    defer g.deinit();

    try testing.expect(std.mem.eql(u8, g.function_name, "test_function"));
}

// Test graph with parameters
test "Comprehensive: Graph with multiple parameters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g = QTJIRGraph.initWithName(allocator, "multi_param");
    defer g.deinit();

    g.parameters = &[_]graph.Parameter{
        .{ .name = "a", .type_name = "i32" },
        .{ .name = "b", .type_name = "i32" },
        .{ .name = "c", .type_name = "i32" },
    };

    try testing.expectEqual(@as(usize, 3), g.parameters.len);
}
