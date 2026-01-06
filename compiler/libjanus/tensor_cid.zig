// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Graph Canonicalization — content IDs with BLAKE3

const std = @import("std");
const jir = @import("tensor_jir.zig");

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;

const Blake3 = std.crypto.hash.Blake3;

/// Compute a deterministic BLAKE3 content ID for a J‑IR graph using a
/// canonical serialization independent of incidental IDs.
/// Strategy:
/// - Canonicalize edges by tensor properties and local connectivity (producer/consumer kinds)
/// - Reference edges by their canonical indices
/// - Canonicalize nodes by (kind, input edge indices sequence, output edge indices sequence)
/// - Exclude non-semantic hints (e.g., device_hint)
pub fn computeGraphCID(graph: *const Graph, allocator: Allocator) ![32]u8 {
    var hasher = Blake3.init(.{});

    // Precompute consumer kinds per edge (sorted)
    const edge_count = graph.edges.items.len;
    const consumer_kinds = try allocator.alloc([]const u16, edge_count);
    defer allocator.free(consumer_kinds);
    const tmp_bufs = try allocator.alloc([]u16, edge_count);
    defer {
        for (tmp_bufs) |b| if (b.len != 0) allocator.free(b);
        allocator.free(tmp_bufs);
    }
    var e: usize = 0;
    while (e < edge_count) : (e += 1) {
        const edge = graph.edges.items[e];
        const num = edge.consumers.len;
        var kinds = try allocator.alloc(u16, num);
        var i: usize = 0;
        while (i < num) : (i += 1) kinds[i] = @intFromEnum(graph.nodes.items[edge.consumers[i]].kind);
        std.sort.insertion(u16, kinds, {}, std.sort.asc(u16));
        consumer_kinds[e] = kinds;
        tmp_bufs[e] = kinds; // track for free
    }

    // Build canonical edge index mapping by sorting by tensor properties and connectivity
    const edge_indices = try allocator.alloc(usize, edge_count);
    defer allocator.free(edge_indices);
    for (edge_indices, 0..) |*idx, i| idx.* = i;

    const EdgeCtx = struct {
        g: *const Graph,
        ck: []const []const u16,
    };
    const edge_ctx = EdgeCtx{ .g = graph, .ck = consumer_kinds };
    const edgeLess = struct {
        fn less(ctx: EdgeCtx, a: usize, b: usize) bool {
            const ea = ctx.g.edges.items[a];
            const eb = ctx.g.edges.items[b];
            // dtype
            const da: u8 = @intFromEnum(ea.tensor.dtype);
            const db: u8 = @intFromEnum(eb.tensor.dtype);
            if (da != db) return da < db;
            // memspace (null => 255)
            const ma: u8 = if (ea.tensor.mem) |ms| @intFromEnum(ms) else 255;
            const mb: u8 = if (eb.tensor.mem) |ms| @intFromEnum(ms) else 255;
            if (ma != mb) return ma < mb;
            // rank
            const ra = ea.tensor.shape.dims.len;
            const rb = eb.tensor.shape.dims.len;
            if (ra != rb) return ra < rb;
            // dims lexicographically
            var i: usize = 0;
            while (i < ra) : (i += 1) {
                const xa = ea.tensor.shape.dims[i];
                const xb = eb.tensor.shape.dims[i];
                if (xa != xb) return xa < xb;
            }
            // producer kind (none => 0xffff)
            const pka: u16 = if (ea.producer) |nid| @intFromEnum(ctx.g.nodes.items[nid].kind) else 0xffff;
            const pkb: u16 = if (eb.producer) |nid| @intFromEnum(ctx.g.nodes.items[nid].kind) else 0xffff;
            if (pka != pkb) return pka < pkb;
            // consumer kinds (sorted)
            const cka = ctx.ck[a];
            const ckb = ctx.ck[b];
            if (cka.len != ckb.len) return cka.len < ckb.len;
            var j: usize = 0;
            while (j < cka.len) : (j += 1) {
                if (cka[j] != ckb[j]) return cka[j] < ckb[j];
            }
            // final tiebreaker: original index to ensure total order (stable)
            return a < b;
        }
    }.less;
    std.sort.pdq(usize, edge_indices, edge_ctx, edgeLess);

    // Build mapping from original edge id -> canonical index
    const edge_canon_index = try allocator.alloc(usize, edge_count);
    defer allocator.free(edge_canon_index);
    for (edge_indices, 0..) |orig, canon| edge_canon_index[orig] = canon;

    // Serialize edges in canonical order (without IDs)
    // E | dtype:u8 | mem:u8 | rank:u32 | dims*
    for (edge_indices) |eid| {
        const edge = graph.edges.items[eid];
        hasher.update("E");
        writeU8(&hasher, @intFromEnum(edge.tensor.dtype));
        if (edge.tensor.mem) |ms| writeU8(&hasher, @intFromEnum(ms)) else writeU8(&hasher, 255);
        writeU32(&hasher, @intCast(edge.tensor.shape.dims.len));
        for (edge.tensor.shape.dims) |d| writeU32(&hasher, d);
    }

    // Canonicalize nodes by structural keys using edge canonical indices
    const node_count = graph.nodes.items.len;
    const node_indices = try allocator.alloc(usize, node_count);
    defer allocator.free(node_indices);
    for (node_indices, 0..) |*idx, i| idx.* = i;

    const NodeCtx = struct { g: *const Graph, ecanon: []const usize };
    const node_ctx = NodeCtx{ .g = graph, .ecanon = edge_canon_index };
    const nodeLess = struct {
        fn less(ctx: NodeCtx, a: usize, b: usize) bool {
            const na = ctx.g.nodes.items[a];
            const nb = ctx.g.nodes.items[b];
            const ka: u16 = @intFromEnum(na.kind);
            const kb: u16 = @intFromEnum(nb.kind);
            if (ka != kb) return ka < kb;
            // inputs: compare by length then lex on canonical edge indices (preserve order)
            if (na.inputs.len != nb.inputs.len) return na.inputs.len < nb.inputs.len;
            var i: usize = 0;
            while (i < na.inputs.len) : (i += 1) {
                const ia = ctx.ecanon[na.inputs[i]];
                const ib = ctx.ecanon[nb.inputs[i]];
                if (ia != ib) return ia < ib;
            }
            // outputs
            if (na.outputs.len != nb.outputs.len) return na.outputs.len < nb.outputs.len;
            var j: usize = 0;
            while (j < na.outputs.len) : (j += 1) {
                const oa = ctx.ecanon[na.outputs[j]];
                const ob = ctx.ecanon[nb.outputs[j]];
                if (oa != ob) return oa < ob;
            }
            // final tiebreaker: original index to make total order stable
            return a < b;
        }
    }.less;
    std.sort.pdq(usize, node_indices, node_ctx, nodeLess);

    // Serialize nodes without ephemeral IDs
    // N | kind:u16 | in_count:u32 | inputs:canon_idx* | out_count:u32 | outputs:canon_idx*
    for (node_indices) |nid| {
        const node = graph.nodes.items[nid];
        hasher.update("N");
        writeU32(&hasher, @intFromEnum(node.kind));
        writeU32(&hasher, @intCast(node.inputs.len));
        for (node.inputs) |eid| writeU32(&hasher, @intCast(edge_canon_index[eid]));
        writeU32(&hasher, @intCast(node.outputs.len));
        for (node.outputs) |eid| writeU32(&hasher, @intCast(edge_canon_index[eid]));
    }

    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

pub fn cidHex(cid: *const [32]u8, allocator: Allocator) ![]u8 {
    const hex = try allocator.alloc(u8, 64);
    const encoded = std.fmt.bytesToHex(cid.*, .lower);
    @memcpy(hex, &encoded);
    return hex;
}

fn writeU8(hasher: *Blake3, v: u8) void { hasher.update(&[_]u8{v}); }
fn writeU32(hasher: *Blake3, v: u32) void {
    var buf: [4]u8 = .{ @intCast(v >> 24), @intCast((v >> 16) & 0xff), @intCast((v >> 8) & 0xff), @intCast(v & 0xff) };
    hasher.update(&buf);
}

// ------------------ Tests ------------------
const testing = std.testing;
const builder = @import("tensor_builder.zig");

test "computeGraphCID stable for identical graphs" {
    var b1 = builder.Builder.init(testing.allocator);
    defer b1.deinit();
    const a1 = try b1.input(.f32, &[_]u32{ 2, 2 }, null);
    const w1 = try b1.input(.f32, &[_]u32{ 2, 2 }, null);
    const m1 = try b1.matmul(a1, w1, null);
    _ = try b1.relu(m1);
    const g1 = b1.getGraph();

    var b2 = builder.Builder.init(testing.allocator);
    defer b2.deinit();
    const a2 = try b2.input(.f32, &[_]u32{ 2, 2 }, null);
    const w2 = try b2.input(.f32, &[_]u32{ 2, 2 }, null);
    const m2 = try b2.matmul(a2, w2, null);
    _ = try b2.relu(m2);
    const g2 = b2.getGraph();

    const cid1 = try computeGraphCID(g1, testing.allocator);
    const cid2 = try computeGraphCID(g2, testing.allocator);
    try testing.expect(std.mem.eql(u8, &cid1, &cid2));
}

test "computeGraphCID invariant to device_hint changes" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 2, 3 }, .dram);
    const w = try b.input(.f32, &[_]u32{ 3, 4 }, .dram);
    const m = try b.matmul(a, w, .dram);
    _ = try b.relu(m);
    const g = b.getGraph();

    const cid_before = try computeGraphCID(g, testing.allocator);
    // Toggle device hints on nodes; CID must not change
    g.nodes.items[0].device_hint = .npu;
    if (g.nodes.items.len > 1) g.nodes.items[1].device_hint = .cpu;
    const cid_after = try computeGraphCID(g, testing.allocator);
    try testing.expect(std.mem.eql(u8, &cid_before, &cid_after));
}

test "computeGraphCID changes with memspace changes" {
    var b1 = builder.Builder.init(testing.allocator);
    defer b1.deinit();
    const a1 = try b1.input(.f16, &[_]u32{ 4, 4 }, .dram);
    const w1 = try b1.input(.f16, &[_]u32{ 4, 4 }, .dram);
    const m1 = try b1.matmul(a1, w1, .dram);
    _ = try b1.relu(m1);
    const g1 = b1.getGraph();

    var b2 = builder.Builder.init(testing.allocator);
    defer b2.deinit();
    const a2 = try b2.input(.f16, &[_]u32{ 4, 4 }, .sram);
    const w2 = try b2.input(.f16, &[_]u32{ 4, 4 }, .sram);
    const m2 = try b2.matmul(a2, w2, .sram);
    _ = try b2.relu(m2);
    const g2 = b2.getGraph();

    const cid1 = try computeGraphCID(g1, testing.allocator);
    const cid2 = try computeGraphCID(g2, testing.allocator);
    try testing.expect(!std.mem.eql(u8, &cid1, &cid2));
}
