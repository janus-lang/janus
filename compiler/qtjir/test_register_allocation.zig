// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR Register Allocation Tests (Task 3.1.2)
// Doctrine: Test-Driven Development - Write failing tests first

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");
const ssa = @import("ssa.zig");
const regalloc = @import("register_allocation.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;

// Test Scenario 11: Register Allocation for Simple Function
// Given: SSA form of add_twice function
// When: Register allocation pass processes the SSA graph
// Then: Virtual registers are assigned with optimal reuse
test "Register allocation for simple function" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create SSA graph: x_0 = param; y_0 = x_0 + 1; z_0 = y_0 + 1; return z_0
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    const x = try builder.createNode(.Load);
    const const_1 = try builder.createConstant(.{ .integer = 1 });
    
    const y = try builder.createNode(.Add);
    try g.nodes.items[y].inputs.append(allocator, x);
    try g.nodes.items[y].inputs.append(allocator, const_1);
    
    const z = try builder.createNode(.Add);
    try g.nodes.items[z].inputs.append(allocator, y);
    try g.nodes.items[z].inputs.append(allocator, const_1);
    
    _ = try builder.createReturn(z);
    
    // Convert to SSA
    var ssa_converter = ssa.SSAConverter.init(allocator);
    defer ssa_converter.deinit();
    try ssa_converter.convert(&g);
    
    // Perform register allocation
    var reg_allocator = regalloc.RegisterAllocator.init(allocator);
    defer reg_allocator.deinit();
    
    try reg_allocator.allocate(&g);
    
    // Verify register assignment
    // x_0 should get a register (e.g., r0)
    // y_0 should get a register (e.g., r1)
    // z_0 can reuse x_0's register since x_0 is dead (e.g., r0)
    
    const x_reg = reg_allocator.getRegister(x);
    const y_reg = reg_allocator.getRegister(y);
    const z_reg = reg_allocator.getRegister(z);
    
    try testing.expect(x_reg != null);
    try testing.expect(y_reg != null);
    try testing.expect(z_reg != null);
    
    // z should reuse x's register (x is dead after y is computed)
    try testing.expectEqual(x_reg.?, z_reg.?);
}

// Test Scenario 12: Register Allocation with High Pressure
// Given: SSA form with many live variables
// When: Register allocation with limited registers
// Then: Spilling occurs for infrequently used variables
test "Register allocation with spilling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create SSA graph with high register pressure
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    // Create many live variables
    const v0 = try builder.createNode(.Load);
    const v1 = try builder.createNode(.Load);
    const v2 = try builder.createNode(.Load);
    const v3 = try builder.createNode(.Load);
    const v4 = try builder.createNode(.Load);
    
    // All variables used in final computation
    const sum1 = try builder.createNode(.Add);
    try g.nodes.items[sum1].inputs.append(allocator, v0);
    try g.nodes.items[sum1].inputs.append(allocator, v1);
    
    const sum2 = try builder.createNode(.Add);
    try g.nodes.items[sum2].inputs.append(allocator, v2);
    try g.nodes.items[sum2].inputs.append(allocator, v3);
    
    const sum3 = try builder.createNode(.Add);
    try g.nodes.items[sum3].inputs.append(allocator, sum1);
    try g.nodes.items[sum3].inputs.append(allocator, sum2);
    
    const final = try builder.createNode(.Add);
    try g.nodes.items[final].inputs.append(allocator, sum3);
    try g.nodes.items[final].inputs.append(allocator, v4);
    
    _ = try builder.createReturn(final);
    
    // Convert to SSA
    var ssa_converter = ssa.SSAConverter.init(allocator);
    defer ssa_converter.deinit();
    try ssa_converter.convert(&g);
    
    // Perform register allocation with limited registers (e.g., 3 registers)
    var reg_allocator = regalloc.RegisterAllocator.init(allocator);
    defer reg_allocator.deinit();
    reg_allocator.max_registers = 3;
    
    try reg_allocator.allocate(&g);
    
    // Verify that spilling occurred
    const spill_count = reg_allocator.getSpillCount();
    try testing.expect(spill_count > 0);
}

// Test: Liveness analysis computes correct live ranges
test "Liveness analysis for register allocation" {
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
    
    // Convert to SSA
    var ssa_converter = ssa.SSAConverter.init(allocator);
    defer ssa_converter.deinit();
    try ssa_converter.convert(&g);
    
    // Perform liveness analysis
    var reg_allocator = regalloc.RegisterAllocator.init(allocator);
    defer reg_allocator.deinit();
    
    try reg_allocator.computeLiveness(&g);
    
    // Verify liveness information
    // x is live from definition to use in y
    // y is live from definition onwards
    const x_live_range = reg_allocator.getLiveRange(x);
    const y_live_range = reg_allocator.getLiveRange(y);
    
    try testing.expect(x_live_range != null);
    try testing.expect(y_live_range != null);
    
    // x's live range should end before or at y's definition
    try testing.expect(x_live_range.?.end <= y_live_range.?.start);
}
