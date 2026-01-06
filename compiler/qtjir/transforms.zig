// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR Transformation Infrastructure
// Doctrine: Mechanism over Policy - Generic pattern matching engine

const std = @import("std");
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRNode = graph.IRNode;
const OpCode = graph.OpCode;
const Tenancy = graph.Tenancy;

/// Interface for graph transformations
pub const Transform = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        name: []const u8,
        run: *const fn (ctx: *anyopaque, graph: *QTJIRGraph) anyerror!bool,
    };

    pub fn name(self: Transform) []const u8 {
        return self.vtable.name;
    }

    pub fn run(self: Transform, g: *QTJIRGraph) !bool {
        return self.vtable.run(self.ptr, g);
    }
};

/// Pattern matching engine for graph nodes
pub const Pattern = struct {
    op: ?OpCode = null,
    tenancy: ?Tenancy = null,
    inputs: ?[]const Pattern = null,

    /// Check if a node matches the pattern
    pub fn matches(self: Pattern, g: *const QTJIRGraph, node_id: u32) bool {
        if (node_id >= g.nodes.items.len) return false;
        const node = &g.nodes.items[node_id];

        // Check OpCode
        if (self.op) |op| {
            if (node.op != op) return false;
        }

        // Check Tenancy
        if (self.tenancy) |ten| {
            if (node.tenancy != ten) return false;
        }

        // Check Inputs (recursive)
        if (self.inputs) |input_patterns| {
            if (node.inputs.items.len != input_patterns.len) return false;

            for (input_patterns, 0..) |pat, i| {
                const input_id = node.inputs.items[i];
                if (!pat.matches(g, input_id)) return false;
            }
        }

        return true;
    }
};

/// Match result containing captured nodes
pub const MatchResult = struct {
    root: u32,
    captures: std.AutoHashMap(u32, u32), // pattern_id -> node_id (future enhancement)

    pub fn init(allocator: std.mem.Allocator, root: u32) MatchResult {
        return MatchResult{
            .root = root,
            .captures = std.AutoHashMap(u32, u32).init(allocator),
        };
    }

    pub fn deinit(self: *MatchResult) void {
        self.captures.deinit();
    }
};

/// Helper to find all matches of a pattern in the graph
pub fn findAllMatches(allocator: std.mem.Allocator, g: *const QTJIRGraph, pattern: Pattern) !std.ArrayListUnmanaged(u32) {
    var matches = std.ArrayListUnmanaged(u32){};
    errdefer matches.deinit(allocator);

    for (g.nodes.items) |node| {
        if (pattern.matches(g, node.id)) {
            try matches.append(allocator, node.id);
        }
    }

    return matches;
}

/// Pass Manager to orchestrate transformations
pub const PassManager = struct {
    passes: std.ArrayListUnmanaged(Transform),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PassManager {
        return PassManager{
            .passes = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PassManager) void {
        self.passes.deinit(self.allocator);
    }

    pub fn addPass(self: *PassManager, pass: Transform) !void {
        try self.passes.append(self.allocator, pass);
    }

    /// Run all passes until convergence or max iterations
    pub fn run(self: *PassManager, g: *QTJIRGraph) !void {
        const max_iterations = 10;
        var changed = true;
        var iter: usize = 0;

        while (changed and iter < max_iterations) : (iter += 1) {
            changed = false;
            for (self.passes.items) |pass| {
                if (try pass.run(g)) {
                    changed = true;
                }
            }
        }
    }
};

//==============================================================================
// Standard Optimization Passes
//==============================================================================

/// Transformation: Constant Folding - Evaluate constant expressions at compile time
pub const ConstantFolding = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConstantFolding {
        return ConstantFolding{ .allocator = allocator };
    }

    pub fn run(ctx: *anyopaque, g: *QTJIRGraph) anyerror!bool {
        const self: *ConstantFolding = @ptrCast(@alignCast(ctx));

        var changed = false;

        for (g.nodes.items) |*node| {
            // Skip if already a constant
            if (node.op == .Constant) continue;

            // Check if this is a foldable operation with all constant inputs
            const can_fold = switch (node.op) {
                .Add, .Sub, .Mul, .Div => blk: {
                    if (node.inputs.items.len != 2) break :blk false;
                    const lhs = &g.nodes.items[node.inputs.items[0]];
                    const rhs = &g.nodes.items[node.inputs.items[1]];
                    break :blk lhs.op == .Constant and rhs.op == .Constant;
                },
                else => false,
            };

            if (!can_fold) continue;

            // Get constant values
            const lhs = &g.nodes.items[node.inputs.items[0]];
            const rhs = &g.nodes.items[node.inputs.items[1]];

            const lhs_val = switch (lhs.data) {
                .integer => |v| v,
                else => continue,
            };

            const rhs_val = switch (rhs.data) {
                .integer => |v| v,
                else => continue,
            };

            // Compute result
            const result: i64 = switch (node.op) {
                .Add => lhs_val + rhs_val,
                .Sub => lhs_val - rhs_val,
                .Mul => lhs_val * rhs_val,
                .Div => if (rhs_val != 0) @divTrunc(lhs_val, rhs_val) else continue,
                else => unreachable,
            };

            // Replace node with constant
            node.op = .Constant;
            node.data = .{ .integer = result };
            node.inputs.deinit(self.allocator);
            node.inputs = .{};

            changed = true;
        }

        return changed;
    }

    pub const vtable = Transform.VTable{
        .name = "ConstantFolding",
        .run = run,
    };

    pub fn transform(self: *ConstantFolding) Transform {
        return Transform{
            .ptr = self,
            .vtable = &vtable,
        };
    }
};

/// Transformation: Dead Code Elimination - Remove unused nodes
pub const DeadCodeElimination = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DeadCodeElimination {
        return DeadCodeElimination{ .allocator = allocator };
    }

    pub fn run(ctx: *anyopaque, g: *QTJIRGraph) anyerror!bool {
        const self: *DeadCodeElimination = @ptrCast(@alignCast(ctx));

        // Mark all live nodes (nodes that are used)
        var live = try std.DynamicBitSet.initEmpty(self.allocator, g.nodes.items.len);
        defer live.deinit();

        // Start with Return nodes (always live)
        for (g.nodes.items) |node| {
            if (node.op == .Return) {
                try markLive(g, &live, node.id);
            }
        }

        // Also mark Call nodes as live (side effects)
        for (g.nodes.items) |node| {
            if (node.op == .Call) {
                live.set(node.id);
            }
        }

        // Count dead nodes
        var dead_count: usize = 0;
        for (0..g.nodes.items.len) |i| {
            if (!live.isSet(i)) {
                dead_count += 1;
            }
        }

        if (dead_count == 0) return false;

        // Remove dead nodes (in reverse to maintain indices)
        var i: usize = g.nodes.items.len;
        while (i > 0) {
            i -= 1;
            if (!live.isSet(i)) {
                var removed = g.nodes.orderedRemove(i);
                removed.inputs.deinit(self.allocator);
            }
        }

        return dead_count > 0;
    }

    fn markLive(g: *QTJIRGraph, live: *std.DynamicBitSet, node_id: u32) !void {
        if (node_id >= g.nodes.items.len) return;
        if (live.isSet(node_id)) return; // Already marked

        live.set(node_id);

        // Recursively mark inputs
        const node = &g.nodes.items[node_id];
        for (node.inputs.items) |input_id| {
            try markLive(g, live, input_id);
        }
    }

    pub const vtable = Transform.VTable{
        .name = "DeadCodeElimination",
        .run = run,
    };

    pub fn transform(self: *DeadCodeElimination) Transform {
        return Transform{
            .ptr = self,
            .vtable = &vtable,
        };
    }
};

/// Transformation: Common Subexpression Elimination - Deduplicate identical computations
pub const CommonSubexpressionElimination = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommonSubexpressionElimination {
        return CommonSubexpressionElimination{ .allocator = allocator };
    }

    pub fn run(ctx: *anyopaque, g: *QTJIRGraph) anyerror!bool {
        const self: *CommonSubexpressionElimination = @ptrCast(@alignCast(ctx));
        _ = self; // Used for allocator in future enhancements

        var changed = false;
        var i: usize = 0;

        while (i < g.nodes.items.len) : (i += 1) {
            const node_a = &g.nodes.items[i];

            // Skip Constants and side-effect nodes
            if (node_a.op == .Constant or node_a.op == .Call or node_a.op == .Return) continue;

            // Look for duplicate
            var j: usize = i + 1;
            while (j < g.nodes.items.len) : (j += 1) {
                const node_b = &g.nodes.items[j];

                // Check if nodes are equivalent
                if (!nodesEquivalent(node_a, node_b)) continue;

                // Replace all uses of node_b with node_a
                const node_b_id = node_b.id;
                const node_a_id = node_a.id;

                for (g.nodes.items) |*user| {
                    for (user.inputs.items) |*input_id| {
                        if (input_id.* == node_b_id) {
                            input_id.* = node_a_id;
                            changed = true;
                        }
                    }
                }
            }
        }

        return changed;
    }

    fn nodesEquivalent(a: *const IRNode, b: *const IRNode) bool {
        // Must have same operation
        if (a.op != b.op) return false;

        // Must have same number of inputs
        if (a.inputs.items.len != b.inputs.items.len) return false;

        // Must have same inputs (order matters for non-commutative ops)
        for (a.inputs.items, b.inputs.items) |a_input, b_input| {
            if (a_input != b_input) return false;
        }

        // For Constants, must have same value
        if (a.op == .Constant) {
            return switch (a.data) {
                .integer => |a_val| switch (b.data) {
                    .integer => |b_val| a_val == b_val,
                    else => false,
                },
                .string => |a_str| switch (b.data) {
                    .string => |b_str| std.mem.eql(u8, a_str, b_str),
                    else => false,
                },
                else => false,
            };
        }

        return true;
    }

    pub const vtable = Transform.VTable{
        .name = "CommonSubexpressionElimination",
        .run = run,
    };

    pub fn transform(self: *CommonSubexpressionElimination) Transform {
        return Transform{
            .ptr = self,
            .vtable = &vtable,
        };
    }
};

//==============================================================================
// Domain-Specific Optimization Passes (Tensor/Quantum)
//==============================================================================

/// Transformation: Fuse Matmul + Relu into Tensor_FusedMatmulRelu
pub const FuseMatmulRelu = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FuseMatmulRelu {
        return FuseMatmulRelu{ .allocator = allocator };
    }

    pub fn run(ctx: *anyopaque, g: *QTJIRGraph) anyerror!bool {
        const self: *FuseMatmulRelu = @ptrCast(@alignCast(ctx));

        // Pattern: Relu(Matmul(A, B))
        const matmul_pat = Pattern{ .op = .Tensor_Matmul };
        const relu_pat = Pattern{ .op = .Tensor_Relu, .inputs = &[_]Pattern{matmul_pat} };

        var matches = try findAllMatches(self.allocator, g, relu_pat);
        defer matches.deinit(self.allocator);

        if (matches.items.len == 0) return false;

        var changed = false;

        for (matches.items) |relu_id| {
            var relu_node = &g.nodes.items[relu_id];

            // Skip if already fused (though pattern matching should prevent this)
            if (relu_node.op != .Tensor_Relu) continue;

            const matmul_id = relu_node.inputs.items[0];
            const matmul_node = &g.nodes.items[matmul_id];

            // Verify tenancy (must be NPU)
            if (relu_node.tenancy != .NPU_Tensor or matmul_node.tenancy != .NPU_Tensor) continue;

            // Perform Fusion:
            // 1. Clone inputs from Matmul (A, B)
            const new_inputs = try matmul_node.inputs.clone(self.allocator);

            // 2. Update Relu node to be FusedMatmulRelu
            relu_node.op = .Tensor_FusedMatmulRelu;
            relu_node.inputs.deinit(self.allocator);
            relu_node.inputs = new_inputs;

            // 3. Preserve metadata (deep copy shape to avoid double-free)
            if (relu_node.tensor_metadata == null) {
                if (matmul_node.tensor_metadata) |tm| {
                    const new_shape = try self.allocator.dupe(usize, tm.shape);
                    relu_node.tensor_metadata = .{
                        .shape = new_shape,
                        .dtype = tm.dtype,
                        .layout = tm.layout,
                    };
                }
            }

            changed = true;
        }

        return changed;
    }

    pub const vtable = Transform.VTable{
        .name = "FuseMatmulRelu",
        .run = run,
    };

    pub fn transform(self: *FuseMatmulRelu) Transform {
        return Transform{
            .ptr = self,
            .vtable = &vtable,
        };
    }
};

/// Transformation: Optimize Quantum Gates (Cancellation)
pub const OptimizeQuantumGates = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) OptimizeQuantumGates {
        return OptimizeQuantumGates{ .allocator = allocator };
    }

    pub fn run(ctx: *anyopaque, g: *QTJIRGraph) anyerror!bool {
        const self: *OptimizeQuantumGates = @ptrCast(@alignCast(ctx));

        // Pattern: Gate2(Gate1)
        const gate1_pat = Pattern{ .op = .Quantum_Gate };
        const gate2_pat = Pattern{ .op = .Quantum_Gate, .inputs = &[_]Pattern{gate1_pat} };

        var matches = try findAllMatches(self.allocator, g, gate2_pat);
        defer matches.deinit(self.allocator);

        if (matches.items.len == 0) return false;

        var changed = false;

        for (matches.items) |gate2_id| {
            const gate2_node = &g.nodes.items[gate2_id];

            const gate1_id = gate2_node.inputs.items[0];
            const gate1_node = &g.nodes.items[gate1_id];

            // Check metadata
            const meta1 = gate1_node.quantum_metadata orelse continue;
            const meta2 = gate2_node.quantum_metadata orelse continue;

            // Must be same gate type and self-inverse
            if (meta1.gate_type != meta2.gate_type) continue;
            if (!isSelfInverse(meta1.gate_type)) continue;

            // Must operate on same qubits
            if (!std.mem.eql(usize, meta1.qubits, meta2.qubits)) continue;

            // Optimization: Bypass Gate1 and Gate2
            if (gate1_node.inputs.items.len == 0) continue;
            const original_input = gate1_node.inputs.items[0];

            // Rewire users of Gate2 to use original_input
            var rewired = false;
            for (g.nodes.items) |*node| {
                for (node.inputs.items) |*input_id| {
                    if (input_id.* == gate2_id) {
                        input_id.* = original_input;
                        rewired = true;
                    }
                }
            }

            if (rewired) changed = true;
        }

        return changed;
    }

    fn isSelfInverse(gate: graph.GateType) bool {
        return switch (gate) {
            .Hadamard, .PauliX, .PauliY, .PauliZ, .CNOT, .CZ, .SWAP, .Toffoli, .Fredkin => true,
            else => false,
        };
    }

    pub const vtable = Transform.VTable{
        .name = "OptimizeQuantumGates",
        .run = run,
    };

    pub fn transform(self: *OptimizeQuantumGates) Transform {
        return Transform{
            .ptr = self,
            .vtable = &vtable,
        };
    }
};
