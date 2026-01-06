// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Backend Abstraction — interface for emitting tensor graphs

const std = @import("std");
const jir = @import("tensor_jir.zig");
const fusion = @import("tensor_fusion.zig");
const quant = @import("tensor_quant.zig");
const tile = @import("tensor_tile.zig");

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;
pub const OpKind = jir.OpKind;
pub const FusionPlan = fusion.FusionPlan;
pub const BackendCaps = fusion.BackendCaps;
pub const QuantPlan = quant.QuantPlan;
pub const QuantPolicy = quant.QuantPolicy;
pub const TilePlan = tile.TilePlan;

/// Aggregate planning outputs used by backends
pub const PlanningBundle = struct {
    fusion: ?*const FusionPlan = null,
    quant: ?*const QuantPlan = null,
    tile: ?*const TilePlan = null,
    caps: BackendCaps = .{},
};

/// Backend vtable — function pointers implementing the interface
pub const BackendOps = struct {
    /// Human-readable backend name
    name: []const u8,
    /// Return true if this backend supports the given op kind
    supports: *const fn (*const Backend, OpKind) bool,
    /// Emit a backend-specific artifact (e.g., ONNX proto bytes, device binary, etc.)
    emit: *const fn (*const Backend, *const Graph, PlanningBundle, Allocator) anyerror![]u8,
    /// Optional deinit hook for backend-specific resources
    deinit: ?*const fn (*Backend, Allocator) void = null,
};

/// Backend instance holding a vtable and optional implementation context
pub const Backend = struct {
    ops: BackendOps,
    ctx: ?*anyopaque = null,

    pub fn supports(self: *const Backend, kind: OpKind) bool {
        return self.ops.supports(self, kind);
    }

    pub fn emit(self: *const Backend, g: *const Graph, plans: PlanningBundle, allocator: Allocator) ![]u8 {
        return self.ops.emit(self, g, plans, allocator);
    }

    pub fn deinit(self: *Backend, allocator: Allocator) void {
        if (self.ops.deinit) |f| f(self, allocator);
    }
};

// ------------------ Null/Dummy Backend ------------------

/// A simple backend that validates inputs and emits a textual summary.
pub const DummyBackend = struct {
    pub fn make() Backend {
        return Backend{
            .ops = BackendOps{
                .name = "dummy",
                .supports = &supports,
                .emit = &emit,
                .deinit = null,
            },
            .ctx = null,
        };
    }

    fn supports(_: *const Backend, _: OpKind) bool {
        // Accept all ops for summary purposes
        return true;
    }

    fn emit(_: *const Backend, g: *const Graph, plans: PlanningBundle, allocator: Allocator) ![]u8 {
        var bw = std.ArrayList(u8){};
        errdefer bw.deinit(allocator);
        var w = bw.writer(allocator);
        try w.print("JIR Graph: {d} nodes, {d} edges\n", .{ g.nodes.items.len, g.edges.items.len });
        if (plans.fusion) |fp| try w.print("Fusion groups: {d}\n", .{fp.groups.len});
        if (plans.quant) |qp| try w.print("Quant items: {d}\n", .{qp.items.len});
        if (plans.tile) |tp| try w.print("Tile items: {d}\n", .{tp.items.len});
        return bw.toOwnedSlice(allocator);
    }
};

// ------------------ Test ------------------
const testing = std.testing;
const builder = @import("tensor_builder.zig");

test "Backend: dummy emit summary" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 2, 2 }, null);
    const c = try b.add(a, a);
    _ = c;
    const g = b.getGraph();

    // Create minimal plans (empty) and run dummy backend
    var backend = DummyBackend.make();
    const out = try backend.emit(g, .{}, testing.allocator);
    defer testing.allocator.free(out);
    try testing.expect(out.len > 0);
}
