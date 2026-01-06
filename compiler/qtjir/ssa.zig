// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR SSA Transformation (High/Mid → SSA Form)

const std = @import("std");
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRNode = graph.IRNode;
const OpCode = graph.OpCode;

/// SSA Converter: Transforms High-level IR to SSA form (Mid-level)
pub const SSAConverter = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) SSAConverter {
        return SSAConverter{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *SSAConverter) void {
        _ = self;
    }
    
    /// Convert graph to SSA form
    /// Algorithm:
    /// 1. Detect control flow patterns (branches, loops)
    /// 2. Insert phi nodes at merge points
    /// 3. Update graph level to Mid
    pub fn convert(self: *SSAConverter, g: *QTJIRGraph) !void {
        // Step 1: Update all nodes to Mid-level (SSA is Mid-level IR)
        for (g.nodes.items) |*node| {
            node.level = .Mid;
        }
        
        // Step 2: Detect control flow and insert phi nodes
        try self.insertPhiNodes(g);
    }
    
    /// Insert phi nodes at control flow merge points
    /// Simplified algorithm:
    /// - Find Branch nodes (control flow splits)
    /// - Find Store nodes that follow branches (variable assignments)
    /// - Insert phi nodes to merge different definitions
    fn insertPhiNodes(self: *SSAConverter, g: *QTJIRGraph) !void {
        // Find all Branch nodes
        var branches = std.ArrayListUnmanaged(u32){};
        defer branches.deinit(self.allocator);
        
        for (g.nodes.items, 0..) |node, i| {
            if (node.op == .Branch) {
                try branches.append(self.allocator, @intCast(i));
            }
        }
        
        if (branches.items.len == 0) {
            // No control flow, straight-line code
            return;
        }
        
        // For each branch, find Store nodes that need phi nodes
        for (branches.items) |branch_id| {
            try self.insertPhiForBranch(g, branch_id);
        }
    }
    
    /// Insert phi node for a specific branch
    fn insertPhiForBranch(self: *SSAConverter, g: *QTJIRGraph, branch_id: u32) !void {
        // Detect if this is a loop (back-edge exists)
        const is_loop = self.detectLoop(g, branch_id);
        
        if (is_loop) {
            // For loops, insert phi nodes for loop-carried variables
            try self.insertLoopPhiNodes(g, branch_id);
        } else {
            // For if-else, insert phi nodes at merge point
            try self.insertBranchPhiNodes(g, branch_id);
        }
    }
    
    /// Detect if a branch is part of a loop (simplified heuristic)
    fn detectLoop(self: *SSAConverter, g: *const QTJIRGraph, branch_id: u32) bool {
        _ = self;
        
        // Heuristic: if there are Add nodes after the branch that use
        // values from before the branch, it's likely a loop
        for (g.nodes.items, 0..) |node, i| {
            if (i > branch_id and node.op == .Add) {
                // Check if this Add uses constants (loop initialization pattern)
                for (node.inputs.items) |input_id| {
                    const input_node = &g.nodes.items[input_id];
                    if (input_node.op == .Constant and input_id < branch_id) {
                        return true;
                    }
                }
            }
        }
        return false;
    }
    
    /// Insert phi nodes for loop-carried variables
    fn insertLoopPhiNodes(self: *SSAConverter, g: *QTJIRGraph, branch_id: u32) !void {
        // Find Add nodes after the branch (loop updates)
        var update_nodes = std.ArrayListUnmanaged(u32){};
        defer update_nodes.deinit(self.allocator);
        
        for (g.nodes.items, 0..) |node, i| {
            if (node.op == .Add and i > branch_id) {
                try update_nodes.append(self.allocator, @intCast(i));
            }
        }
        
        // For each update, create a phi node (initial value + back-edge)
        for (update_nodes.items) |update_id| {
            const update_node = &g.nodes.items[update_id];
            if (update_node.inputs.items.len >= 2) {
                const phi_id = @as(u32, @intCast(g.nodes.items.len));
                var phi_node = IRNode.init(phi_id, .Phi, .CPU_Serial);
                phi_node.level = .Mid;
                
                // Add initial value and back-edge value
                try phi_node.inputs.append(self.allocator, update_node.inputs.items[0]);
                try phi_node.inputs.append(self.allocator, update_id);
                
                try g.nodes.append(self.allocator, phi_node);
            }
        }
    }
    
    /// Insert phi nodes for if-else branches
    fn insertBranchPhiNodes(self: *SSAConverter, g: *QTJIRGraph, branch_id: u32) !void {
        // Find Store nodes after this branch
        var store_nodes = std.ArrayListUnmanaged(u32){};
        defer store_nodes.deinit(self.allocator);
        
        for (g.nodes.items, 0..) |node, i| {
            if (node.op == .Store and i > branch_id) {
                try store_nodes.append(self.allocator, @intCast(i));
            }
        }
        
        if (store_nodes.items.len < 2) {
            return;
        }
        
        // Create phi node to merge the stores
        const phi_id = @as(u32, @intCast(g.nodes.items.len));
        var phi_node = IRNode.init(phi_id, .Phi, .CPU_Serial);
        phi_node.level = .Mid;
        
        // Add inputs from each store
        for (store_nodes.items) |store_id| {
            const store_node = &g.nodes.items[store_id];
            if (store_node.inputs.items.len > 0) {
                try phi_node.inputs.append(self.allocator, store_node.inputs.items[0]);
            }
        }
        
        try g.nodes.append(self.allocator, phi_node);
    }
};

/// SSA Validator: Verifies SSA form correctness
pub const SSAValidator = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) SSAValidator {
        return SSAValidator{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *SSAValidator) void {
        _ = self;
        // Cleanup will be added as needed
    }
    
    /// Validate that graph is in valid SSA form
    /// Returns true if valid, false otherwise
    /// 
    /// Validation checks (Simplified for Phase 3.1.1):
    /// 1. Graph must be at Mid-level
    /// 2. Each node represents a unique definition (SSA property)
    /// 3. Phi nodes (if present) must have correct number of inputs
    pub fn validate(self: *SSAValidator, g: *const QTJIRGraph) !bool {
        _ = self;
        
        // Check 1: All nodes should be at Mid-level for SSA
        for (g.nodes.items) |node| {
            if (node.level != .Mid) {
                return false;
            }
        }
        
        // Check 2: Each node ID is unique (SSA single assignment property)
        // In our IR, node IDs are already unique by construction
        
        // Check 3: Validate phi nodes (if any)
        for (g.nodes.items) |node| {
            if (node.op == .Phi) {
                // Phi nodes must have at least 2 inputs (from different predecessors)
                if (node.inputs.items.len < 2) {
                    return false;
                }
            }
        }
        
        // TODO: Add more sophisticated validation
        // - Check dominance properties
        // - Verify use-def chains
        // - Validate phi node placement at merge points
        
        return true;
    }
};
