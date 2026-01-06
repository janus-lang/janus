// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR Platform Lowering Tests (Epic 3.2)
// Doctrine: Test-Driven Development - Write failing tests first

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");
const ssa = @import("ssa.zig");
const platform = @import("platform_lowering.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const Level = graph.Level;

// Test Scenario 13: CPU_Serial Platform Lowering
// Given: Mid-level QTJIR with arithmetic operations
// When: CPU_Serial lowering pass processes the graph
// Then: Low-level QTJIR contains CPU-specific instructions
test "CPU_Serial lowering for arithmetic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create Mid-level SSA graph: r0 = r1 + r2; r3 = r0 * r4
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    const r1 = try builder.createNode(.Load);
    const r2 = try builder.createNode(.Load);
    const r4 = try builder.createNode(.Load);
    
    const r0 = try builder.createNode(.Add);
    try g.nodes.items[r0].inputs.append(allocator, r1);
    try g.nodes.items[r0].inputs.append(allocator, r2);
    
    const r3 = try builder.createNode(.Mul);
    try g.nodes.items[r3].inputs.append(allocator, r0);
    try g.nodes.items[r3].inputs.append(allocator, r4);
    
    // Set to Mid-level (SSA)
    for (g.nodes.items) |*node| {
        node.level = .Mid;
    }
    
    // Perform CPU_Serial lowering
    var lowerer = platform.PlatformLowering.init(allocator);
    defer lowerer.deinit();
    
    try lowerer.lowerCPUSerial(&g);
    
    // Verify all nodes are now at Low-level
    for (g.nodes.items) |node| {
        try testing.expectEqual(Level.Low, node.level);
    }
    
    // Verify operations are still correct (Add, Mul preserved)
    var add_count: u32 = 0;
    var mul_count: u32 = 0;
    for (g.nodes.items) |node| {
        if (node.op == .Add) add_count += 1;
        if (node.op == .Mul) mul_count += 1;
    }
    try testing.expectEqual(@as(u32, 1), add_count);
    try testing.expectEqual(@as(u32, 1), mul_count);
}

// Test: CPU_Serial lowering preserves tenancy
test "CPU_Serial lowering preserves CPU_Serial tenancy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    const x = try builder.createNode(.Load);
    const const_1 = try builder.createConstant(.{ .integer = 1 });
    const y = try builder.createNode(.Add);
    try g.nodes.items[y].inputs.append(allocator, x);
    try g.nodes.items[y].inputs.append(allocator, const_1);
    
    // Set to Mid-level
    for (g.nodes.items) |*node| {
        node.level = .Mid;
    }
    
    // Perform lowering
    var lowerer = platform.PlatformLowering.init(allocator);
    defer lowerer.deinit();
    try lowerer.lowerCPUSerial(&g);
    
    // Verify tenancy is preserved
    for (g.nodes.items) |node| {
        try testing.expectEqual(graph.Tenancy.CPU_Serial, node.tenancy);
    }
}

// Test Scenario 14: CPU_Parallel lowering (stub for now)
test "CPU_Parallel lowering placeholder" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .CPU_Parallel;
    
    const x = try builder.createNode(.Load);
    _ = x;
    
    // Set to Mid-level
    for (g.nodes.items) |*node| {
        node.level = .Mid;
    }
    
    // Perform lowering
    var lowerer = platform.PlatformLowering.init(allocator);
    defer lowerer.deinit();
    try lowerer.lowerCPUParallel(&g);
    
    // Verify level changed to Low
    for (g.nodes.items) |node| {
        try testing.expectEqual(Level.Low, node.level);
    }
}

// Test Scenario 15: NPU_Tensor lowering (stub for now)
test "NPU_Tensor lowering placeholder" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .NPU_Tensor;
    
    const t1 = try builder.createNode(.Tensor_Matmul);
    _ = t1;
    
    // Set to Mid-level
    for (g.nodes.items) |*node| {
        node.level = .Mid;
    }
    
    // Perform lowering
    var lowerer = platform.PlatformLowering.init(allocator);
    defer lowerer.deinit();
    try lowerer.lowerNPUTensor(&g);
    
    // Verify level changed to Low
    for (g.nodes.items) |node| {
        try testing.expectEqual(Level.Low, node.level);
    }
}

// Test Scenario 16: QPU_Quantum lowering (stub for now)
test "QPU_Quantum lowering placeholder" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .QPU_Quantum;
    
    const q1 = try builder.createNode(.Quantum_Gate);
    _ = q1;
    
    // Set to Mid-level
    for (g.nodes.items) |*node| {
        node.level = .Mid;
    }
    
    // Perform lowering
    var lowerer = platform.PlatformLowering.init(allocator);
    defer lowerer.deinit();
    try lowerer.lowerQPUQuantum(&g);
    
    // Verify level changed to Low
    for (g.nodes.items) |node| {
        try testing.expectEqual(Level.Low, node.level);
    }
}
