// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor J‑IR TilePass — memory-aware tiling plan for fast mem (e.g., SRAM)

const std = @import("std");
const jir = @import("tensor_jir.zig");

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;
pub const NodeId = jir.NodeId;
pub const EdgeId = jir.EdgeId;
pub const OpKind = jir.OpKind;
pub const DType = jir.DType;
pub const MemSpace = jir.MemSpace;

pub const TilePolicy = struct {
    fast_mem: MemSpace = .sram,
    capacity_bytes: u64 = 256 * 1024, // default 256KB
};

pub const TileKind = enum { Matmul2D };

pub const TileItem = struct {
    node: NodeId,
    kind: TileKind,
    tile_m: u32,
    tile_n: u32,
};

pub const TilePlan = struct {
    items: []TileItem,
    pub fn deinit(self: *TilePlan, allocator: Allocator) void {
        allocator.free(self.items);
    }
};

pub const TilePass = struct {
    allocator: Allocator,
    policy: TilePolicy,

    pub fn init(allocator: Allocator, policy: TilePolicy) TilePass {
        return .{ .allocator = allocator, .policy = policy };
    }

    /// Produce a tiling plan for nodes whose working set exceeds fast memory.
    /// Planning only; graph mutation is delegated to a later lowering pass.
    pub fn plan(self: *TilePass, g: *const Graph) !TilePlan {
        var items = try std.ArrayList(TileItem).initCapacity(self.allocator, 0);
        defer items.deinit(self.allocator);

        for (g.nodes.items, 0..) |node, nid| {
            switch (node.kind) {
                .Matmul => {
                    if (node.inputs.len != 2 or node.outputs.len != 1) continue;
                    const a = g.edges.items[node.inputs[0]].tensor;
                    const b = g.edges.items[node.inputs[1]].tensor;
                    const o = g.edges.items[node.outputs[0]].tensor;
                    if (a.shape.dims.len != 2 or b.shape.dims.len != 2 or o.shape.dims.len != 2) continue;
                    const M: u32 = a.shape.dims[0];
                    const K: u32 = a.shape.dims[1];
                    const N: u32 = b.shape.dims[1];
                    const bytes = bytesPerDType(a.dtype);
                    // Working set model for one tile: A_tile (M_t*K) + B_tile (K*N_t) + O_tile (M_t*N_t)
                    // Choose initial full N, reduce M_t until fits; if needed, also reduce N_t.
                    var Mt: u32 = M;
                    var Nt: u32 = N;
                    const cap = self.policy.capacity_bytes;
                    var ok = self.fitsMatmul(bytes, Mt, K, Nt, cap);
                    while (!ok and (Mt > 1 or Nt > 1)) {
                        if (Mt >= Nt and Mt > 1) {
                            Mt = @max(1, Mt / 2);
                        } else if (Nt > 1) {
                            Nt = @max(1, Nt / 2);
                        }
                        ok = self.fitsMatmul(bytes, Mt, K, Nt, cap);
                    }
                    if (!ok) continue; // give up; backend will handle spilling
                    if (Mt < M or Nt < N) {
                        _ = try items.append(self.allocator, .{ .node = @intCast(nid), .kind = .Matmul2D, .tile_m = Mt, .tile_n = Nt });
                    }
                },
                else => {},
            }
        }

        return TilePlan{ .items = try items.toOwnedSlice(self.allocator) };
    }

    fn fitsMatmul(self: *const TilePass, elem_bytes: u32, Mt: u32, K: u32, Nt: u32, cap: u64) bool {
        _ = self;
        const a_bytes: u64 = @as(u64, Mt) * @as(u64, K) * elem_bytes;
        const b_bytes: u64 = @as(u64, K) * @as(u64, Nt) * elem_bytes;
        const o_bytes: u64 = @as(u64, Mt) * @as(u64, Nt) * elem_bytes;
        const total = a_bytes + b_bytes + o_bytes;
        return total <= cap;
    }
};

pub fn bytesPerDType(dt: DType) u32 {
    return switch (dt) {
        .i8 => 1,
        .i16 => 2,
        .i32 => 4,
        .f16 => 2,
        .bf16 => 2,
        .f32 => 4,
        .f64 => 8,
        .bool => 1,
    };
}

// ------------------ Tests ------------------
const testing = std.testing;

test "TilePass: plans tiling for large matmul under small SRAM" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    // 1024x1024 matmul in f16 with 64KB capacity will require tiling
    var dims_a: [2]u32 = [_]u32{ 1024, 1024 };
    var dims_b: [2]u32 = [_]u32{ 1024, 1024 };
    var dims_o: [2]u32 = [_]u32{ 1024, 1024 };
    const a = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = &dims_a }, .mem = .dram }, null);
    const b = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = &dims_b }, .mem = .dram }, null);
    const o = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = &dims_o }, .mem = .dram }, null);
    _ = try g.addNode(.Matmul, &[_]EdgeId{ a, b }, &[_]EdgeId{ o });

    var pass = TilePass.init(testing.allocator, .{ .capacity_bytes = 64 * 1024 });
    var plan = try pass.plan(&g);
    defer plan.deinit(testing.allocator);
    try testing.expect(plan.items.len >= 1);
    try testing.expect(plan.items[0].tile_m < 1024 or plan.items[0].tile_n < 1024);
}
