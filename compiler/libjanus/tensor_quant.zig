// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor J‑IR QuantizationPass — plan Q/DQ insertion per tolerance policy

const std = @import("std");
const jir = @import("tensor_jir.zig");
const diag = @import("tensor_diagnostics.zig");

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;
pub const NodeId = jir.NodeId;
pub const EdgeId = jir.EdgeId;
pub const OpKind = jir.OpKind;

pub const QuantMode = enum { int8_per_tensor, int8_per_channel };

pub const QuantPolicy = struct {
    enabled: bool = true,
    mode: QuantMode = .int8_per_tensor,
    max_relative_error: f32 = 0.02, // 2% default
};

pub const QuantOpSupport = struct {
    matmul: bool = true,
    conv2d: bool = true,
    relu: bool = true,
    add: bool = true,
    mul: bool = true,
};

pub const PlanItemKind = enum { InsertQuant, InsertDequant };

pub const PlanItem = struct {
    kind: PlanItemKind,
    edge: EdgeId, // edge where a Q/DQ node should be inserted (between producer and consumers)
};

pub const QuantPlan = struct {
    items: []PlanItem,

    pub fn deinit(self: *QuantPlan, allocator: Allocator) void {
        allocator.free(self.items);
    }
};

pub const QuantizationPass = struct {
    allocator: Allocator,
    policy: QuantPolicy,
    support: QuantOpSupport,

    pub fn init(allocator: Allocator, policy: QuantPolicy, support: QuantOpSupport) QuantizationPass {
        return .{ .allocator = allocator, .policy = policy, .support = support };
    }

    /// Produce a plan of Q/DQ insertions without mutating the graph.
    /// Strategy:
    /// - If policy disabled, return empty plan.
    /// - Mark nodes that support quantization.
    /// - For each supported node with float inputs, plan InsertQuant on incoming edges not already quantized.
    /// - For edges that flow from a supported node to a non-supported node, plan InsertDequant.
    pub fn plan(self: *QuantizationPass, g: *const Graph, diagnostics: ?*diag.TensorDiagnostics) !QuantPlan {
        var items = std.ArrayListUnmanaged(PlanItem){};
        defer items.deinit(self.allocator);

        if (!self.policy.enabled) {
            if (diagnostics) |d| {
                _ = d.quantizationPolicyDisabled(@tagName(self.policy.mode)) catch {};
            }
            return QuantPlan{ .items = try self.allocator.alloc(PlanItem, 0) };
        }

        const node_quant_ok = try self.allocator.alloc(bool, g.nodes.items.len);
        defer self.allocator.free(node_quant_ok);
        var i: usize = 0;
        while (i < g.nodes.items.len) : (i += 1) {
            node_quant_ok[i] = self.supports(g.nodes.items[i].kind);
            if (!node_quant_ok[i]) {
                if (diagnostics) |d| {
                    _ = d.quantizationUnsupported(@tagName(g.nodes.items[i].kind)) catch {};
                }
            }
        }

        // Track which edges we already plan to quantize so we don't duplicate
        const qmarked = try self.allocator.alloc(bool, g.edges.items.len);
        const dqmarked = try self.allocator.alloc(bool, g.edges.items.len);
        defer {
            self.allocator.free(qmarked);
            self.allocator.free(dqmarked);
        }
        @memset(qmarked, false);
        @memset(dqmarked, false);

        // For each node that supports quantization: ensure its inputs are quantized
        for (g.nodes.items, 0..) |node, nid| {
            if (!node_quant_ok[nid]) continue;
            for (node.inputs) |eid| {
                if (!qmarked[eid]) {
                    try items.append(self.allocator, .{ .kind = .InsertQuant, .edge = eid });
                    qmarked[eid] = true;
                }
            }
        }

        // For edges whose producer is a supported node, but a consumer is a non-supported node: insert DQ
        for (g.edges.items, 0..) |edge, eid| {
            if (edge.producer == null) continue;
            const prod_id = edge.producer.?;
            if (!node_quant_ok[prod_id]) continue;
            // If any consumer is non-quant, we must dequantize before entering it
            var needs_dq = false;
            for (edge.consumers) |cid| {
                if (!node_quant_ok[cid]) { needs_dq = true; break; }
            }
            if (needs_dq and !dqmarked[eid]) {
                try items.append(self.allocator, .{ .kind = .InsertDequant, .edge = @intCast(eid) });
                dqmarked[eid] = true;
            }
        }

        return QuantPlan{ .items = try items.toOwnedSlice(self.allocator) };
    }

    fn supports(self: *const QuantizationPass, kind: OpKind) bool {
        return switch (kind) {
            .Matmul => self.support.matmul,
            .Conv2D => self.support.conv2d,
            .Relu => self.support.relu,
            .Add => self.support.add,
            .Mul => self.support.mul,
            else => false,
        };
    }
};

// ------------------ Tests ------------------
const testing = std.testing;

test "QuantizationPass: plan Q on inputs and DQ when consumer not supported" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    // Build: Matmul -> Relu -> Transfer (non-quant)
    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 8, 4 }) }, .mem = null }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 4, 16 }) }, .mem = null }, null);
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 8, 16 }) }, .mem = null }, null);
    const n_mat = try g.addNode(.Matmul, &[_]EdgeId{ a, b }, &[_]EdgeId{ o });
    _ = n_mat;
    const o2 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 8, 16 }) }, .mem = null }, null);
    const n_relu = try g.addNode(.Relu, &[_]EdgeId{ o }, &[_]EdgeId{ o2 });
    _ = n_relu;
    const o3 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 8, 16 }) }, .mem = .sram }, null);
    _ = try g.addNode(.Transfer, &[_]EdgeId{ o2 }, &[_]EdgeId{ o3 });

    var pass = QuantizationPass.init(testing.allocator, .{}, .{});
    var plan = try pass.plan(&g, null);
    defer plan.deinit(testing.allocator);

    // Expect at least two InsertQuant (for inputs a,b) and one InsertDequant (before Transfer)
    var q: usize = 0;
    var dq: usize = 0;
    for (plan.items) |it| {
        switch (it.kind) {
            .InsertQuant => q += 1,
            .InsertDequant => dq += 1,
        }
    }
    try testing.expect(q >= 2);
    try testing.expect(dq >= 1);
}

test "QuantizationPass: disabled policy yields empty plan and diagnostic" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    _ = try g.addNode(.Matmul, &[_]EdgeId{ a, b }, &[_]EdgeId{ o });

    var pass = QuantizationPass.init(testing.allocator, .{ .enabled = false }, .{});
    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();
    var plan = try pass.plan(&g, &diags);
    defer plan.deinit(testing.allocator);
    try testing.expect(plan.items.len == 0);
    try testing.expectEqual(@as(usize, 1), diags.all().len);
    try testing.expect(diags.all()[0].kind == .quantization_policy_disabled);
}

test "QuantizationPass: unsupported op records diagnostic" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    _ = try g.addNode(.Transfer, &[_]EdgeId{ a }, &[_]EdgeId{ o });

    var pass = QuantizationPass.init(testing.allocator, .{}, .{ .matmul = false, .conv2d = false, .relu = false, .add = false, .mul = false });
    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();

    var plan = try pass.plan(&g, &diags);
    defer plan.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), plan.items.len);
    try testing.expect(diags.all().len >= 1);
    try testing.expect(diags.all()[0].kind == .quantization_not_supported);
}

test "QuantizationPass: shared input edge quantized only once" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const shared_input = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 16, 32 }) }, .mem = null }, null);
    const weights0 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 32, 64 }) }, .mem = null }, null);
    const out0 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 16, 64 }) }, .mem = null }, null);
    _ = try g.addNode(.Matmul, &[_]EdgeId{ shared_input, weights0 }, &[_]EdgeId{ out0 });

    const weights1 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 32, 32 }) }, .mem = null }, null);
    const out1 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 16, 32 }) }, .mem = null }, null);
    _ = try g.addNode(.Matmul, &[_]EdgeId{ shared_input, weights1 }, &[_]EdgeId{ out1 });

    var pass = QuantizationPass.init(testing.allocator, .{}, .{ .add = false });
    var plan = try pass.plan(&g, null);
    defer plan.deinit(testing.allocator);

    var quant_count: usize = 0;
    for (plan.items) |item| {
        if (item.kind == .InsertQuant and item.edge == shared_input) {
            quant_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 1), quant_count);
}

test "QuantizationPass: single dequant planned for multiple non-quant consumers" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const input = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 16, 16 }) }, .mem = null }, null);
    const weights = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 16, 16 }) }, .mem = null }, null);
    const prod = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 16, 16 }) }, .mem = null }, null);
    _ = try g.addNode(.Matmul, &[_]EdgeId{ input, weights }, &[_]EdgeId{ prod });

    const transfer_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 16, 16 }) }, .mem = .sram }, null);
    _ = try g.addNode(.Transfer, &[_]EdgeId{ prod }, &[_]EdgeId{ transfer_out });

    const add_rhs = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 16, 16 }) }, .mem = null }, null);
    const add_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 16, 16 }) }, .mem = null }, null);
    _ = try g.addNode(.Add, &[_]EdgeId{ prod, add_rhs }, &[_]EdgeId{ add_out });

    var pass = QuantizationPass.init(testing.allocator, .{}, .{});
    var plan = try pass.plan(&g, null);
    defer plan.deinit(testing.allocator);

    var dq_count: usize = 0;
    for (plan.items) |item| {
        if (item.kind == .InsertDequant and item.edge == prod) dq_count += 1;
    }
    try testing.expectEqual(@as(usize, 1), dq_count);
}
