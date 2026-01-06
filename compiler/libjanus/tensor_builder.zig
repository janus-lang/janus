// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor J‑IR Builder — scaffolding to construct graphs from tensor ops

const std = @import("std");
const jir = @import("tensor_jir.zig");

pub const Allocator = std.mem.Allocator;
pub const DType = jir.DType;
pub const MemSpace = jir.MemSpace;
pub const Graph = jir.Graph;
pub const EdgeId = jir.EdgeId;
pub const NodeId = jir.NodeId;

pub const Builder = struct {
    allocator: Allocator,
    graph: Graph,

    pub fn init(allocator: Allocator) Builder {
        return .{ .allocator = allocator, .graph = Graph.init(allocator) };
    }

    pub fn deinit(self: *Builder) void {
        self.graph.deinit();
    }

    /// Create an input (source) tensor edge with no producer
    pub fn input(self: *Builder, dtype: DType, dims: []const u32, mem: ?MemSpace) !EdgeId {
        return self.graph.addEdge(.{ .dtype = dtype, .shape = .{ .dims = @constCast(dims) }, .mem = mem }, null);
    }

    /// Matmul: [M,K] x [K,N] -> [M,N]
    pub fn matmul(self: *Builder, a: EdgeId, b: EdgeId, out_mem: ?MemSpace) !EdgeId {
        const ashape = self.graph.edges.items[a].tensor.shape.dims;
        const bshape = self.graph.edges.items[b].tensor.shape.dims;
        if (ashape.len != 2 or bshape.len != 2) return error.ShapeMismatch;
        const M = ashape[0];
        const K1 = ashape[1];
        const K2 = bshape[0];
        const N = bshape[1];
        if (K1 != K2) return error.ShapeMismatch;

        const dtype = self.graph.edges.items[a].tensor.dtype; // assume same dtype for now
        const out_e = try self.graph.addEdge(.{ .dtype = dtype, .shape = .{ .dims = @constCast(&[_]u32{ M, N }) }, .mem = out_mem }, null);
        _ = try self.graph.addNode(.Matmul, &[_]EdgeId{ a, b }, &[_]EdgeId{ out_e });
        return out_e;
    }

    /// Unary activation (shape-preserving)
    pub fn relu(self: *Builder, x: EdgeId) !EdgeId {
        const t = self.graph.edges.items[x].tensor;
        const out = try self.graph.addEdge(.{ .dtype = t.dtype, .shape = .{ .dims = t.shape.dims }, .mem = t.mem }, null);
        _ = try self.graph.addNode(.Relu, &[_]EdgeId{ x }, &[_]EdgeId{ out });
        return out;
    }

    /// Binary add with broadcasting rules; output dtype = left dtype
    pub fn add(self: *Builder, a: EdgeId, b: EdgeId) !EdgeId {
        const at = self.graph.edges.items[a].tensor;
        const bt = self.graph.edges.items[b].tensor;
        const out_shape = try jir.computeBroadcastShapeAlloc(self.allocator, at.shape.dims, bt.shape.dims);
        defer self.allocator.free(out_shape);
        const out = try self.graph.addEdge(.{ .dtype = at.dtype, .shape = .{ .dims = out_shape }, .mem = at.mem }, null);
        _ = try self.graph.addNode(.Add, &[_]EdgeId{ a, b }, &[_]EdgeId{ out });
        return out;
    }

    /// Transfer a tensor to a different memory space
    pub fn transfer(self: *Builder, x: EdgeId, dst: MemSpace) !EdgeId {
        const t = self.graph.edges.items[x].tensor;
        const out = try self.graph.addEdge(.{ .dtype = t.dtype, .shape = .{ .dims = t.shape.dims }, .mem = dst }, null);
        _ = try self.graph.addNode(.Transfer, &[_]EdgeId{ x }, &[_]EdgeId{ out });
        return out;
    }

    pub fn getGraph(self: *Builder) *Graph {
        return &self.graph;
    }
};

// ------------------ Tests ------------------
const testing = std.testing;

test "builder: matmul -> relu -> transfer" {
    var b = Builder.init(testing.allocator);
    defer b.deinit();

    const a = try b.input(.f16, &[_]u32{ 128, 64 }, .dram);
    const w = try b.input(.f16, &[_]u32{ 64, 256 }, .dram);
    const m = try b.matmul(a, w, .dram);
    const r = try b.relu(m);
    const s = try b.transfer(r, .sram);
    _ = s;

    const g = b.getGraph();
    try g.verify();
}
