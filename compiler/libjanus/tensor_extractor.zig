// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Minimal Tensor Extractor — builds a plausible J‑IR subgraph as a starting point

const std = @import("std");
const jir = @import("tensor_jir.zig");

pub const Allocator = std.mem.Allocator;
pub const Snapshot = @import("libjanus_astdb").Snapshot;
pub const SemanticGraph = @import("libjanus_semantic.zig").SemanticGraph;

/// Build a tiny graph: two inputs -> Matmul -> Relu
pub fn extractMinimalGraph(snapshot: *const Snapshot, _: *const SemanticGraph, allocator: Allocator) !*jir.Graph {
    // Conservative pattern: look for an identifier named "matmul_relu_demo" in first unit tokens
    const astdb = snapshot.astdb;
    if (astdb.units.items.len == 0) return error.NotFound;
    const unit = astdb.units.items[0];
    var found = false;
    const name = "matmul_relu_demo";
    var i: usize = 0;
    while (i < unit.tokens.len) : (i += 1) {
        const tok = unit.tokens[i];
        // identifier token with str
        if (tok.str) |sid| {
            const s = astdb.getString(sid);
            if (std.mem.eql(u8, s, name)) { found = true; break; }
        }
    }
    if (!found) return error.NotFound;

    // Build tiny demo graph as a starting point
    var g_ptr = try allocator.create(jir.Graph);
    g_ptr.* = jir.Graph.init(allocator);
    errdefer { g_ptr.deinit(); allocator.destroy(g_ptr); }

    const a = try g_ptr.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 128, 64 }) }, .mem = .dram }, null);
    const b = try g_ptr.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 64, 256 }) }, .mem = .dram }, null);
    const o = try g_ptr.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 128, 256 }) }, .mem = .dram }, null);
    _ = try g_ptr.addNode(.Matmul, &[_]u32{ a, b }, &[_]u32{ o });
    const o2 = try g_ptr.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 128, 256 }) }, .mem = .dram }, null);
    _ = try g_ptr.addNode(.Relu, &[_]u32{ o }, &[_]u32{ o2 });

    try g_ptr.verify();
    return g_ptr;
}
