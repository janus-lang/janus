// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR Register Allocation (Linear Scan)
// Doctrine: Mechanism over Policy - Provide register allocation, let users control strategy

const std = @import("std");
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;

/// Live range for a variable
pub const LiveRange = struct {
    start: u32,  // First instruction where variable is defined
    end: u32,    // Last instruction where variable is used
};

/// Register Allocator: Assigns virtual registers to SSA values
pub const RegisterAllocator = struct {
    allocator: std.mem.Allocator,
    max_registers: u32 = 16,  // Default: 16 virtual registers
    
    // Register assignment map: node_id -> register_id
    register_map: std.AutoHashMap(u32, u32),
    
    // Liveness information: node_id -> live_range
    liveness: std.AutoHashMap(u32, LiveRange),
    
    // Spill tracking
    spill_count: u32 = 0,
    
    pub fn init(allocator: std.mem.Allocator) RegisterAllocator {
        return RegisterAllocator{
            .allocator = allocator,
            .register_map = std.AutoHashMap(u32, u32).init(allocator),
            .liveness = std.AutoHashMap(u32, LiveRange).init(allocator),
        };
    }
    
    pub fn deinit(self: *RegisterAllocator) void {
        self.register_map.deinit();
        self.liveness.deinit();
    }
    
    /// Perform register allocation on SSA graph
    /// Algorithm:
    /// 1. Compute liveness information
    /// 2. Build interference graph
    /// 3. Assign registers (linear scan or graph coloring)
    /// 4. Handle spilling if needed
    pub fn allocate(self: *RegisterAllocator, g: *QTJIRGraph) !void {
        // Step 1: Compute liveness
        try self.computeLiveness(g);
        
        // Step 2: Assign registers using linear scan
        try self.linearScanAllocation(g);
    }
    
    /// Compute liveness information for all variables
    /// Liveness: A variable is live from its definition to its last use
    pub fn computeLiveness(self: *RegisterAllocator, g: *const QTJIRGraph) !void {
        // For each node, compute its live range
        for (g.nodes.items, 0..) |node, i| {
            const node_id = @as(u32, @intCast(i));
            
            // Skip constants and phi nodes for now
            if (node.op == .Constant or node.op == .Phi) {
                continue;
            }
            
            // Find last use of this node
            var last_use: u32 = node_id;
            for (g.nodes.items, 0..) |other_node, j| {
                for (other_node.inputs.items) |input_id| {
                    if (input_id == node_id) {
                        last_use = @max(last_use, @as(u32, @intCast(j)));
                    }
                }
            }
            
            // Store live range
            try self.liveness.put(node_id, LiveRange{
                .start = node_id,
                .end = last_use,
            });
        }
    }
    
    /// Linear scan register allocation with register reuse
    /// Optimized algorithm that reuses registers from dead variables
    fn linearScanAllocation(self: *RegisterAllocator, g: *const QTJIRGraph) !void {
        // Track which registers are free
        var free_registers = std.ArrayListUnmanaged(u32){};
        defer free_registers.deinit(self.allocator);
        
        // Track active intervals: node_id -> register
        var active_map = std.AutoHashMap(u32, u32).init(self.allocator);
        defer active_map.deinit();
        
        var next_register: u32 = 0;
        
        // Process nodes in order
        for (g.nodes.items, 0..) |node, i| {
            const node_id = @as(u32, @intCast(i));
            
            // Skip constants
            if (node.op == .Constant) {
                continue;
            }
            
            // Expire old intervals and free their registers
            var iter = active_map.iterator();
            var to_remove = std.ArrayListUnmanaged(u32){};
            defer to_remove.deinit(self.allocator);
            
            while (iter.next()) |entry| {
                const active_id = entry.key_ptr.*;
                const active_range = self.liveness.get(active_id) orelse continue;
                
                if (active_range.end < node_id) {
                    // This range is no longer active, free its register
                    const freed_reg = entry.value_ptr.*;
                    try free_registers.append(self.allocator, freed_reg);
                    try to_remove.append(self.allocator, active_id);
                }
            }
            
            // Remove expired intervals
            for (to_remove.items) |expired_id| {
                _ = active_map.remove(expired_id);
            }
            
            // Assign register to current node
            var assigned_reg: u32 = undefined;
            
            if (free_registers.items.len > 0) {
                // Reuse a free register
                assigned_reg = free_registers.items[free_registers.items.len - 1];
                _ = free_registers.pop();
            } else if (active_map.count() < self.max_registers) {
                // Allocate a new register
                assigned_reg = next_register;
                next_register += 1;
            } else {
                // Need to spill
                self.spill_count += 1;
                assigned_reg = 0xFFFFFFFF;
            }
            
            try self.register_map.put(node_id, assigned_reg);
            if (assigned_reg != 0xFFFFFFFF) {
                try active_map.put(node_id, assigned_reg);
            }
        }
    }
    
    /// Get assigned register for a node
    pub fn getRegister(self: *const RegisterAllocator, node_id: u32) ?u32 {
        return self.register_map.get(node_id);
    }
    
    /// Get live range for a node
    pub fn getLiveRange(self: *const RegisterAllocator, node_id: u32) ?LiveRange {
        return self.liveness.get(node_id);
    }
    
    /// Get number of spills that occurred
    pub fn getSpillCount(self: *const RegisterAllocator) u32 {
        return self.spill_count;
    }
};
