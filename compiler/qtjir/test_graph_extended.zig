// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Extended test suite for QTJIR graph operations (Phase 5 - Task 5.1.1)

const std = @import("std");
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const IRNode = graph.IRNode;
const OpCode = graph.OpCode;
const Tenancy = graph.Tenancy;
const ValidationResult = graph.ValidationResult;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    try testNodeCreation(allocator);
    try testAllOpCodes(allocator);
    try testGraphTopology(allocator);
    try testValidationResultAPI(allocator);
    try testComplexCycles(allocator);

}

fn testNodeCreation(allocator: std.mem.Allocator) !void {
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    
    // Test 1: Create simple node
    const id1 = try builder.createNode(.Add);
    try std.testing.expectEqual(id1, 0);
    try std.testing.expectEqual(g.nodes.items[0].op, .Add);
    
    // Test 2: Create node with inputs
    const id2 = try builder.createNode(.Constant);
    const args = [_]u32{id2};
    const id3 = try builder.createNodeWithInputs(.Return, &args);
    
    try std.testing.expectEqual(id3, 2);
    try std.testing.expectEqual(g.nodes.items[2].inputs.items.len, 1);
    try std.testing.expectEqual(g.nodes.items[2].inputs.items[0], id2);

}

fn testAllOpCodes(allocator: std.mem.Allocator) !void {
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    var builder = IRBuilder.init(&g);

    // Data Flow
    _ = try builder.createNode(.Constant);
    _ = try builder.createNode(.Load);
    _ = try builder.createNode(.Store);
    _ = try builder.createNode(.Phi);

    // Control Flow
    _ = try builder.createNode(.Call);
    _ = try builder.createNode(.Return);
    _ = try builder.createNode(.Branch);

    // Arithmetic
    _ = try builder.createNode(.Add);
    _ = try builder.createNode(.Sub);
    _ = try builder.createNode(.Mul);
    _ = try builder.createNode(.Div);

    // Tensor
    _ = try builder.createNode(.Tensor_Matmul);
    _ = try builder.createNode(.Tensor_Conv);
    _ = try builder.createNode(.Tensor_Reduce);
    _ = try builder.createNode(.Tensor_ScalarMul);
    _ = try builder.createNode(.Tensor_FusedMatmulRelu);
    _ = try builder.createNode(.Tensor_FusedMatmulAdd);
    _ = try builder.createNode(.Tensor_Contract);
    _ = try builder.createNode(.Tensor_Relu);

    // Quantum
    _ = try builder.createNode(.Quantum_Gate);
    _ = try builder.createNode(.Quantum_Measure);

    // Verify count
    try std.testing.expectEqual(g.nodes.items.len, 19);
    
}

fn testGraphTopology(allocator: std.mem.Allocator) !void {
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    var builder = IRBuilder.init(&g);

    // Create a diamond shape
    //   0
    //  / \
    // 1   2
    //  \ /
    //   3
    
    const n0 = try builder.createNode(.Constant);
    const n1 = try builder.createNode(.Add);
    const n2 = try builder.createNode(.Sub);
    const n3 = try builder.createNode(.Mul);

    try g.nodes.items[n1].inputs.append(allocator, n0);
    try g.nodes.items[n2].inputs.append(allocator, n0);
    try g.nodes.items[n3].inputs.append(allocator, n1);
    try g.nodes.items[n3].inputs.append(allocator, n2);

    // Verify structure
    try std.testing.expectEqual(g.nodes.items[n1].inputs.items[0], n0);
    try std.testing.expectEqual(g.nodes.items[n2].inputs.items[0], n0);
    try std.testing.expectEqual(g.nodes.items[n3].inputs.items[0], n1);
    try std.testing.expectEqual(g.nodes.items[n3].inputs.items[1], n2);

}

fn testValidationResultAPI(allocator: std.mem.Allocator) !void {
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    var builder = IRBuilder.init(&g);

    // Create invalid graph (dangling edge)
    const n0 = try builder.createNode(.Call);
    try g.nodes.items[n0].inputs.append(allocator, 999);

    var result = try g.validate();
    defer result.deinit();

    try std.testing.expect(result.has_errors);
    try std.testing.expect(result.diagnostics.items.len > 0);
    
    const diag = result.diagnostics.items[0];
    try std.testing.expectEqual(diag.level, .Error);
    try std.testing.expectEqual(diag.node_id, n0);
    try std.testing.expectEqual(diag.related_node_id, 999);

}

fn testComplexCycles(allocator: std.mem.Allocator) !void {
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    var builder = IRBuilder.init(&g);

    // Create 3-node cycle: 0 -> 1 -> 2 -> 0
    const n0 = try builder.createNode(.Add);
    const n1 = try builder.createNode(.Add);
    const n2 = try builder.createNode(.Add);

    try g.nodes.items[n1].inputs.append(allocator, n0);
    try g.nodes.items[n2].inputs.append(allocator, n1);
    try g.nodes.items[n0].inputs.append(allocator, n2);

    var result = try g.validate();
    defer result.deinit();

    try std.testing.expect(result.has_errors);
    
    // Find the cycle error
    var found_cycle = false;
    for (result.diagnostics.items) |diag| {
        if (std.mem.indexOf(u8, diag.message, "Cycle detected") != null) {
            found_cycle = true;
            break;
        }
    }
    try std.testing.expect(found_cycle);

}
