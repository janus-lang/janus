// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Debug Backend — CPU execution + drift diagnostics

const std = @import("std");
const jir = @import("tensor_jir.zig");

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;
pub const EdgeId = jir.EdgeId;
pub const NodeId = jir.NodeId;
pub const DType = jir.DType;

pub const Tolerance = struct { rel: f32 = 1e-3, abs: f32 = 1e-6 };

pub const DebugResult = struct {
    // For simplicity store only f32 buffers; other types can be extended later
    buffers: []?[]f32, // indexed by edge id

    pub fn deinit(self: *const DebugResult, allocator: Allocator) void {
        for (self.buffers) |mbuf| if (mbuf) |buf| allocator.free(buf);
        allocator.free(self.buffers);
    }
};

pub const Drift = struct { edge: EdgeId, node: ?NodeId, max_rel: f32, max_abs: f32 };

pub fn runCpu(graph: *const Graph, allocator: Allocator) !DebugResult {
    // Allocate buffers for all edges
    var buffers = try allocator.alloc(?[]f32, graph.edges.items.len);
    for (buffers) |*slot| slot.* = null;

    // Materialize initial values for edges without producer (inputs)
    for (graph.edges.items, 0..) |edge, eid| {
        if (edge.producer == null) {
            const len = tensorLen(edge.tensor);
            buffers[eid] = try allocZeros(allocator, len);
        }
    }

    // Execute nodes in insertion order (graph is assumed verified DAG)
    for (graph.nodes.items, 0..) |node, idx| {
        const nid: NodeId = @as(NodeId, @intCast(idx));
        switch (node.kind) {
            .Relu => try execRelu(graph, nid, &buffers, allocator),
            .Add => try execBinary(graph, nid, &buffers, allocator, .add),
            .Mul => try execBinary(graph, nid, &buffers, allocator, .mul),
            .Matmul => try execMatmul(graph, nid, &buffers, allocator),
            .Transfer, .Copy => try execIdentity(graph, nid, &buffers, allocator),
            else => try execPassthrough(graph, nid, &buffers, allocator),
        }
    }

    return DebugResult{ .buffers = buffers };
}

pub fn compare(a: *const DebugResult, b: *const DebugResult, graph: *const Graph, tol: Tolerance, allocator: Allocator) ![]Drift {
    if (a.buffers.len != b.buffers.len) return error.MismatchedResults;
    var drifts = std.ArrayList(Drift){};
    defer drifts.deinit();

    for (a.buffers, 0..) |ambuf, eid| {
        const bmbuf = b.buffers[eid];
        if (ambuf == null or bmbuf == null) continue;
        const av = ambuf.?;
        const bv = bmbuf.?;
        if (av.len != bv.len) return error.MismatchedBuffers;
        var max_rel: f32 = 0;
        var max_abs: f32 = 0;
        var i: usize = 0;
        while (i < av.len) : (i += 1) {
            const diff: f32 = @abs(av[i] - bv[i]);
            const rel: f32 = if (@abs(bv[i]) > tol.abs) diff / @abs(bv[i]) else 0;
            if (diff > max_abs) max_abs = diff;
            if (rel > max_rel) max_rel = rel;
        }
        if (max_rel > tol.rel and max_abs > tol.abs) {
            // Find a node that produces or consumes this edge (first consumer preferred)
            var node_id: ?NodeId = null;
            if (graph.edges.items[eid].consumers.len > 0) node_id = graph.edges.items[eid].consumers[0] else node_id = graph.edges.items[eid].producer;
            try drifts.append(allocator, .{ .edge = @as(EdgeId, @intCast(eid)), .node = node_id, .max_rel = max_rel, .max_abs = max_abs });
        }
    }

    return try drifts.toOwnedSlice(allocator);
}

fn tensorLen(t: jir.Tensor) usize {
    var total: usize = 1;
    for (t.shape.dims) |d| total *= d;
    return total;
}

fn allocZeros(allocator: Allocator, n: usize) ![]f32 {
    const buf = try allocator.alloc(f32, n);
    @memset(buf, 0.0);
    return buf;
}

fn execIdentity(graph: *const Graph, nid: NodeId, buffers: *[]?[]f32, allocator: Allocator) !void {
    const node = graph.nodes.items[nid];
    if (node.inputs.len != 1 or node.outputs.len != 1) return error.InvalidArity;
    const inp = buffers.*[node.inputs[0]] orelse return error.MissingInput;
    buffers.*[node.outputs[0]] = try dupBuf(allocator, inp);
}

fn execPassthrough(graph: *const Graph, nid: NodeId, buffers: *[]?[]f32, allocator: Allocator) !void {
    // For unsupported ops, copy first input to outputs to keep shape continuity in debug mode
    if (graph.nodes.items[nid].inputs.len == 0 or graph.nodes.items[nid].outputs.len == 0) return;
    const inp = buffers.*[graph.nodes.items[nid].inputs[0]] orelse return error.MissingInput;
    for (graph.nodes.items[nid].outputs) |eid| buffers.*[eid] = try dupBuf(allocator, inp);
}

fn execRelu(graph: *const Graph, nid: NodeId, buffers: *[]?[]f32, allocator: Allocator) !void {
    const node = graph.nodes.items[nid];
    if (node.inputs.len != 1 or node.outputs.len != 1) return error.InvalidArity;
    const inp = buffers.*[node.inputs[0]] orelse return error.MissingInput;
    const out = try dupBuf(allocator, inp);
    for (out) |*v| {
        if (v.* < 0) v.* = 0;
    }
    buffers.*[node.outputs[0]] = out;
}

const BinKind = enum { add, mul };

fn execBinary(graph: *const Graph, nid: NodeId, buffers: *[]?[]f32, allocator: Allocator, kind: BinKind) !void {
    const node = graph.nodes.items[nid];
    if (node.inputs.len != 2 or node.outputs.len != 1) return error.InvalidArity;
    const a = buffers.*[node.inputs[0]] orelse return error.MissingInput;
    const b = buffers.*[node.inputs[1]] orelse return error.MissingInput;
    if (a.len != b.len) return error.UnsupportedBroadcastInDebug;
    var out = try allocZeros(allocator, a.len);
    var i: usize = 0;
    while (i < a.len) : (i += 1) out[i] = switch (kind) {
        .add => a[i] + b[i],
        .mul => a[i] * b[i],
    };
    buffers.*[node.outputs[0]] = out;
}

fn execMatmul(graph: *const Graph, nid: NodeId, buffers: *[]?[]f32, allocator: Allocator) !void {
    const node = graph.nodes.items[nid];
    if (node.inputs.len != 2 or node.outputs.len != 1) return error.InvalidArity;
    const a = buffers.*[node.inputs[0]] orelse return error.MissingInput;
    const b = buffers.*[node.inputs[1]] orelse return error.MissingInput;
    // Shapes are verified earlier; for debug assume dims present in edge.tensor.shape
    const ashape = graph.edges.items[node.inputs[0]].tensor.shape.dims;
    const bshape = graph.edges.items[node.inputs[1]].tensor.shape.dims;
    const oshape = graph.edges.items[node.outputs[0]].tensor.shape.dims;
    const M = ashape[0];
    const K = ashape[1];
    const N = bshape[1];
    if (oshape[0] != M or oshape[1] != N) return error.ShapeMismatch;

    var out = try allocZeros(allocator, @as(usize, M) * @as(usize, N));
    var m: usize = 0;
    while (m < M) : (m += 1) {
        var n: usize = 0;
        while (n < N) : (n += 1) {
            var acc: f32 = 0.0;
            var k: usize = 0;
            while (k < K) : (k += 1) {
                acc += a[m * K + k] * b[k * N + n];
            }
            out[m * N + n] = acc;
        }
    }
    buffers.*[node.outputs[0]] = out;
}

fn dupBuf(allocator: Allocator, src: []const f32) ![]f32 {
    const out = try allocator.alloc(f32, src.len);
    @memcpy(out, src);
    return out;
}

// ------------------ Tests ------------------
const testing = std.testing;
const builder = @import("tensor_builder.zig");

test "CPU debug run + compare produces zero drift for same graph" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 2, 2 }, null);
    const w = try b.input(.f32, &[_]u32{ 2, 2 }, null);
    const m = try b.matmul(a, w, null);
    const r = try b.relu(m);
    _ = r;
    const g = b.getGraph();
    const res1 = try runCpu(g, testing.allocator);
    defer res1.deinit(testing.allocator);
    const res2 = try runCpu(g, testing.allocator);
    defer res2.deinit(testing.allocator);
    const drifts = try compare(&res1, &res2, g, .{}, testing.allocator);
    defer testing.allocator.free(drifts);
    try testing.expect(drifts.len == 0);
}

test "Drift compare detects differences" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 1, 2 }, null);
    const a2 = try b.add(a, a);
    _ = a2;
    const g = b.getGraph();
    var res1 = try runCpu(g, testing.allocator);
    defer res1.deinit(testing.allocator);
    var res2 = try runCpu(g, testing.allocator);
    defer res2.deinit(testing.allocator);
    // Perturb one buffer to trigger drift
    const eid: usize = 0;
    if (res2.buffers[eid]) |buf| {
        if (buf.len > 0) buf[0] += 1.0;
    }
    const drifts = try compare(&res1, &res2, g, .{ .rel = 1e-5, .abs = 1e-5 }, testing.allocator);
    defer testing.allocator.free(drifts);
    try testing.expect(drifts.len >= 1);
}
