// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Test suite for QTJIR graph validation (Phase 1 - Task 1.1.3)

const std = @import("std");
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const ConstantValue = graph.ConstantValue;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== QTJIR Validation Tests ===\n\n", .{});

    try testValidGraph(allocator);
    try testDanglingEdge(allocator);
    try testCycleDetection(allocator);
    try testSelfCycle(allocator);
    try testComplexAcyclicGraph(allocator);
    try testTenancyWarning(allocator);

    std.debug.print("\n✅ All validation tests passed!\n", .{});
}

fn testValidGraph(allocator: std.mem.Allocator) !void {
    std.debug.print("Test: Valid Graph... ", .{});
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    const const_node = try builder.createConstant(.{ .integer = 42 });
    const args = [_]u32{const_node};
    _ = try builder.createCall(&args);

    var result = try g.validate();
    defer result.deinit();
    
    if (result.has_errors) {
        std.debug.print("✗ Validation failed with errors:\n", .{});
        result.dump();
        return error.TestFailed;
    }
    std.debug.print("✓\n", .{});
}

fn testDanglingEdge(allocator: std.mem.Allocator) !void {
    std.debug.print("Test: Dangling Edge Detection... ", .{});
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    const node_id = try builder.createNode(.Call);
    try g.nodes.items[node_id].inputs.append(allocator, 999);

    var result = try g.validate();
    defer result.deinit();

    if (!result.has_errors) {
        std.debug.print("✗ Expected error but validation passed\n", .{});
        return error.TestFailed;
    }

    // Check for specific error message
    var found = false;
    for (result.diagnostics.items) |diag| {
        if (diag.level == .Error and diag.node_id == node_id and diag.related_node_id == 999) {
            found = true;
            break;
        }
    }

    if (found) {
        std.debug.print("✓\n", .{});
    } else {
        std.debug.print("✗ Wrong error or missing diagnostic\n", .{});
        result.dump();
        return error.TestFailed;
    }
}

fn testCycleDetection(allocator: std.mem.Allocator) !void {
    std.debug.print("Test: Cycle Detection... ", .{});
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    const node0 = try builder.createNode(.Add);
    const node1 = try builder.createNode(.Add);
    
    try g.nodes.items[node1].inputs.append(allocator, node0);
    try g.nodes.items[node0].inputs.append(allocator, node1);

    var result = try g.validate();
    defer result.deinit();

    if (!result.has_errors) {
        std.debug.print("✗ Expected cycle error but validation passed\n", .{});
        return error.TestFailed;
    }

    var found = false;
    for (result.diagnostics.items) |diag| {
        if (std.mem.indexOf(u8, diag.message, "Cycle detected") != null) {
            found = true;
            break;
        }
    }

    if (found) {
        std.debug.print("✓\n", .{});
    } else {
        std.debug.print("✗ Wrong error: expected cycle detection\n", .{});
        result.dump();
        return error.TestFailed;
    }
}

fn testSelfCycle(allocator: std.mem.Allocator) !void {
    std.debug.print("Test: Self-Referencing Cycle... ", .{});
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    const node_id = try builder.createNode(.Add);
    try g.nodes.items[node_id].inputs.append(allocator, node_id);

    var result = try g.validate();
    defer result.deinit();

    if (!result.has_errors) {
        std.debug.print("✗ Expected cycle error but validation passed\n", .{});
        return error.TestFailed;
    }

    var found = false;
    for (result.diagnostics.items) |diag| {
        if (std.mem.indexOf(u8, diag.message, "Cycle detected") != null) {
            found = true;
            break;
        }
    }

    if (found) {
        std.debug.print("✓\n", .{});
    } else {
        std.debug.print("✗ Wrong error: expected cycle detection\n", .{});
        result.dump();
        return error.TestFailed;
    }
}

fn testComplexAcyclicGraph(allocator: std.mem.Allocator) !void {
    std.debug.print("Test: Complex Acyclic Graph (Diamond)... ", .{});
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    const node0 = try builder.createConstant(.{ .integer = 1 });
    const node1 = try builder.createNode(.Add);
    const node2 = try builder.createNode(.Mul);
    const node3 = try builder.createNode(.Add);

    try g.nodes.items[node1].inputs.append(allocator, node0);
    try g.nodes.items[node2].inputs.append(allocator, node0);
    try g.nodes.items[node3].inputs.append(allocator, node1);
    try g.nodes.items[node3].inputs.append(allocator, node2);

    var result = try g.validate();
    defer result.deinit();

    if (result.has_errors) {
        std.debug.print("✗ Validation failed with errors:\n", .{});
        result.dump();
        return error.TestFailed;
    }
    std.debug.print("✓\n", .{});
}

fn testTenancyWarning(allocator: std.mem.Allocator) !void {
    std.debug.print("Test: Tenancy Consistency Warning... ", .{});
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();

    var builder = IRBuilder.init(&g);
    builder.current_tenancy = .CPU_Serial;
    const cpu_node = try builder.createConstant(.{ .integer = 42 });

    builder.current_tenancy = .NPU_Tensor;
    const npu_node = try builder.createNode(.Tensor_Contract);
    try g.nodes.items[npu_node].inputs.append(allocator, cpu_node);

    var result = try g.validate();
    defer result.deinit();

    // Should have warnings but no errors (Phase 1/2 policy)
    if (result.has_errors) {
        std.debug.print("✗ Validation failed with errors (expected warnings only):\n", .{});
        result.dump();
        return error.TestFailed;
    }

    var found = false;
    for (result.diagnostics.items) |diag| {
        if (diag.level == .Warning and std.mem.indexOf(u8, diag.message, "Tenancy mismatch") != null) {
            found = true;
            break;
        }
    }

    if (found) {
        std.debug.print("✓ (warning expected)\n", .{});
    } else {
        std.debug.print("✗ Expected tenancy warning not found\n", .{});
        result.dump();
        return error.TestFailed;
    }
}
