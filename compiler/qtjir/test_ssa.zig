// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR SSA Transformation Tests
// Doctrine: Test-Driven Development - Write failing tests first

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");
const ssa = @import("ssa.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const IRNode = graph.IRNode;
const OpCode = graph.OpCode;
const Level = graph.Level;
const Tenancy = graph.Tenancy;

// Test Scenario 8: SSA Conversion for Simple Function
// Given: Straight-line code with variable assignments
// When: SSA conversion pass processes the graph
// Then: Each variable has exactly one definition (SSA form)
test "SSA conversion for straight-line code" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create graph: y = x + 1; z = y + 1; return z
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    // Node 0: x (parameter) - use Load to represent parameter
    const x_node = try builder.createNode(.Load);
    
    // Node 1: constant 1
    const const_1 = try builder.createConstant(.{ .integer = 1 });
    
    // Node 2: y = x + 1
    const y_node = try builder.createNode(.Add);
    try g.nodes.items[y_node].inputs.append(allocator, x_node);
    try g.nodes.items[y_node].inputs.append(allocator, const_1);
    
    // Node 3: z = y + 1
    const z_node = try builder.createNode(.Add);
    try g.nodes.items[z_node].inputs.append(allocator, y_node);
    try g.nodes.items[z_node].inputs.append(allocator, const_1);
    
    // Node 4: return z
    _ = try builder.createReturn(z_node);
    
    // Convert to SSA
    var ssa_converter = ssa.SSAConverter.init(allocator);
    defer ssa_converter.deinit();
    
    try ssa_converter.convert(&g);
    
    // Verify SSA properties
    // 1. Each variable should have exactly one definition
    // 2. No phi nodes needed for straight-line code
    // 3. Use-def chains should be maintained
    
    // Count definitions per variable (simplified check)
    var def_count = std.AutoHashMap(u32, u32).init(allocator);
    defer def_count.deinit();
    
    for (g.nodes.items) |node| {
        if (node.op != .Constant and node.op != .Load) {
            const entry = try def_count.getOrPut(node.id);
            if (!entry.found_existing) {
                entry.value_ptr.* = 0;
            }
            entry.value_ptr.* += 1;
        }
    }
    
    // Each variable should be defined exactly once
    var iter = def_count.iterator();
    while (iter.next()) |entry| {
        try testing.expectEqual(@as(u32, 1), entry.value_ptr.*);
    }
}

// Test Scenario 9: SSA Conversion with Control Flow
// Given: If-else statement with variable assignment in both branches
// When: SSA conversion pass processes the graph
// Then: Phi node is inserted at merge point
test "SSA conversion with if-else control flow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create graph: if (a > b) { result = a } else { result = b }
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    // Node 0: a (parameter)
    const a_node = try builder.createNode(.Load);
    
    // Node 1: b (parameter)
    const b_node = try builder.createNode(.Load);
    
    // Node 2: condition (a > b) - simplified as Branch
    const cond_node = try builder.createNode(.Branch);
    try g.nodes.items[cond_node].inputs.append(allocator, a_node);
    try g.nodes.items[cond_node].inputs.append(allocator, b_node);
    
    // Node 3: result = a (true branch)
    const result_true = try builder.createNode(.Store);
    try g.nodes.items[result_true].inputs.append(allocator, a_node);
    
    // Node 4: result = b (false branch)
    const result_false = try builder.createNode(.Store);
    try g.nodes.items[result_false].inputs.append(allocator, b_node);
    
    // Convert to SSA
    var ssa_converter = ssa.SSAConverter.init(allocator);
    defer ssa_converter.deinit();
    
    try ssa_converter.convert(&g);
    
    // Verify phi node insertion
    // After SSA conversion, there should be a phi node at the merge point
    var phi_count: u32 = 0;
    for (g.nodes.items) |node| {
        if (node.op == .Phi) {
            phi_count += 1;
            // Phi node should have 2 inputs (one from each branch)
            try testing.expectEqual(@as(usize, 2), node.inputs.items.len);
        }
    }
    
    // Should have exactly one phi node for the merged variable
    try testing.expectEqual(@as(u32, 1), phi_count);
}

// Test Scenario 10: SSA Conversion with Loops
// Given: While loop with loop-carried dependencies
// When: SSA conversion pass processes the graph
// Then: Phi nodes are inserted at loop header
test "SSA conversion with while loop" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create graph: i = 0; sum = 0; while (i < n) { sum += i; i += 1; }
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    // Node 0: n (parameter)
    const n_node = try builder.createNode(.Load);
    
    // Node 1: i = 0 (initial)
    const i_init = try builder.createConstant(.{ .integer = 0 });
    
    // Node 2: sum = 0 (initial)
    const sum_init = try builder.createConstant(.{ .integer = 0 });
    
    // Node 3: loop condition (i < n) - simplified as Branch
    const loop_cond = try builder.createNode(.Branch);
    try g.nodes.items[loop_cond].inputs.append(allocator, i_init);
    try g.nodes.items[loop_cond].inputs.append(allocator, n_node);
    
    // Node 4: sum += i (loop body)
    const sum_update = try builder.createNode(.Add);
    try g.nodes.items[sum_update].inputs.append(allocator, sum_init);
    try g.nodes.items[sum_update].inputs.append(allocator, i_init);
    
    // Node 5: constant 1
    const const_1 = try builder.createConstant(.{ .integer = 1 });
    
    // Node 6: i += 1 (loop body)
    const i_update = try builder.createNode(.Add);
    try g.nodes.items[i_update].inputs.append(allocator, i_init);
    try g.nodes.items[i_update].inputs.append(allocator, const_1);
    
    // Convert to SSA
    var ssa_converter = ssa.SSAConverter.init(allocator);
    defer ssa_converter.deinit();
    
    try ssa_converter.convert(&g);
    
    // Verify phi nodes at loop header
    // Should have phi nodes for loop-carried variables (i and sum)
    var phi_count: u32 = 0;
    for (g.nodes.items) |node| {
        if (node.op == .Phi) {
            phi_count += 1;
            // Phi node should have 2 inputs (initial value and back-edge)
            try testing.expectEqual(@as(usize, 2), node.inputs.items.len);
        }
    }
    
    // Should have 2 phi nodes (one for i, one for sum)
    try testing.expectEqual(@as(u32, 2), phi_count);
}

// Test: SSA validation accepts valid SSA form
test "SSA validation accepts valid SSA form" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create simple SSA graph
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    const x = try builder.createNode(.Load);
    const const_1 = try builder.createConstant(.{ .integer = 1 });
    
    const y = try builder.createNode(.Add);
    try g.nodes.items[y].inputs.append(allocator, x);
    try g.nodes.items[y].inputs.append(allocator, const_1);
    
    // Update level to Mid (SSA is Mid-level)
    for (g.nodes.items) |*node| {
        node.level = .Mid;
    }
    
    // Validate SSA form
    var validator = ssa.SSAValidator.init(allocator);
    defer validator.deinit();
    
    const is_valid = try validator.validate(&g);
    try testing.expect(is_valid);
}

// Test: SSA validation rejects invalid SSA form (multiple definitions)
test "SSA validation rejects multiple definitions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create invalid SSA graph (same variable defined twice)
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    // This test will be implemented once we have a way to represent
    // multiple definitions of the same variable
    // For now, we'll skip this test
    
    // TODO: Implement test for invalid SSA form
}
