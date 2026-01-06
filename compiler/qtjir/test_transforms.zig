// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Test suite for QTJIR transformation infrastructure (Phase 1)

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");
const transforms = @import("transforms.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const OpCode = graph.OpCode;
const Pattern = transforms.Pattern;

// ============================================================================
// Test 1: Pattern matching basic OpCode
// ============================================================================

test "QTJIR Transforms: Match OpCode" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    const node_id = try builder.createNode(.Tensor_Matmul);
    
    const pattern = Pattern{ .op = .Tensor_Matmul };
    try testing.expect(pattern.matches(&g, node_id));
    
    const mismatch_pattern = Pattern{ .op = .Tensor_Relu };
    try testing.expect(!mismatch_pattern.matches(&g, node_id));
}

// ============================================================================
// Test 2: Pattern matching with inputs (recursive)
// ============================================================================

test "QTJIR Transforms: Match Structure (Matmul -> Relu)" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    // Create graph: A @ B -> Relu
    const a = try builder.createNode(.Constant);
    const b = try builder.createNode(.Constant);
    
    const matmul = try builder.createNode(.Tensor_Matmul);
    try g.nodes.items[matmul].inputs.append(allocator, a);
    try g.nodes.items[matmul].inputs.append(allocator, b);
    
    const relu = try builder.createNode(.Tensor_Relu);
    try g.nodes.items[relu].inputs.append(allocator, matmul);
    
    // Define pattern: Relu(Matmul(Constant, Constant))
    const const_pat = Pattern{ .op = .Constant };
    const matmul_pat = Pattern{ 
        .op = .Tensor_Matmul,
        .inputs = &[_]Pattern{ const_pat, const_pat }
    };
    const relu_pat = Pattern{
        .op = .Tensor_Relu,
        .inputs = &[_]Pattern{ matmul_pat }
    };
    
    try testing.expect(relu_pat.matches(&g, relu));
    
    // Test mismatch (wrong input count)
    const wrong_matmul_pat = Pattern{
        .op = .Tensor_Matmul,
        .inputs = &[_]Pattern{ const_pat } // Missing one input
    };
    const wrong_relu_pat = Pattern{
        .op = .Tensor_Relu,
        .inputs = &[_]Pattern{ wrong_matmul_pat }
    };
    
    try testing.expect(!wrong_relu_pat.matches(&g, relu));
}

// ============================================================================
// Test 3: Find all matches
// ============================================================================

test "QTJIR Transforms: Find All Matches" {
    const allocator = testing.allocator;
    
    var g = QTJIRGraph.init(allocator);
    defer g.deinit();
    
    var builder = IRBuilder.init(&g);
    
    // Create 3 Constant nodes
    _ = try builder.createNode(.Constant);
    _ = try builder.createNode(.Constant);
    _ = try builder.createNode(.Tensor_Matmul);
    _ = try builder.createNode(.Constant);
    
    const pattern = Pattern{ .op = .Constant };
    var matches = try transforms.findAllMatches(allocator, &g, pattern);
    defer matches.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 3), matches.items.len);
}
