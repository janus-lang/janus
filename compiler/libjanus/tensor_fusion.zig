// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor J‑IR FusionPass — rule-driven fusion planning

const std = @import("std");
const jir = @import("tensor_jir.zig");

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;
pub const NodeId = jir.NodeId;
pub const EdgeId = jir.EdgeId;
pub const OpKind = jir.OpKind;

pub const BackendCaps = struct {
    matmul_relu: bool = true,
    conv_bn_relu: bool = true,
};

pub const FusionRule = enum { MatmulRelu, ConvBnRelu };

pub const FusedGroup = struct {
    nodes: []NodeId,
    fused_kind: OpKind,
};

pub const FusionPlan = struct {
    groups: []FusedGroup,

    pub fn deinit(self: *FusionPlan, allocator: Allocator) void {
        for (self.groups) |g| allocator.free(g.nodes);
        allocator.free(self.groups);
    }
};

pub const FusionPass = struct {
    allocator: Allocator,
    caps: BackendCaps,

    pub fn init(allocator: Allocator, caps: BackendCaps) FusionPass {
        return .{ .allocator = allocator, .caps = caps };
    }

    pub fn plan(self: *FusionPass, g: *const Graph) !FusionPlan {
        var groups = std.ArrayList(FusedGroup).initCapacity(self.allocator, 0) catch unreachable;
        defer groups.deinit(self.allocator);

        if (self.caps.matmul_relu) try self.detectMatmulRelu(g, &groups);
        if (self.caps.conv_bn_relu) try self.detectConvBnRelu(g, &groups);

        return FusionPlan{ .groups = try groups.toOwnedSlice(self.allocator) };
    }

    fn detectMatmulRelu(self: *FusionPass, g: *const Graph, out: *std.ArrayList(FusedGroup)) !void {
        // Pattern: Matmul -> Relu
        for (g.nodes.items, 0..) |node, i| {
            if (node.kind != .Matmul) continue;
            if (node.outputs.len != 1) continue;
            const out_edge = g.edges.items[node.outputs[0]];
            if (out_edge.consumers.len != 1) continue;
            const consumer_id = out_edge.consumers[0];
            const consumer = g.nodes.items[consumer_id];
            if (consumer.kind != .Relu) continue;
            // Found a pair
            const nodes = try self.allocator.alloc(NodeId, 2);
            nodes[0] = @intCast(i);
            nodes[1] = consumer_id;
            try out.append(self.allocator, .{ .nodes = nodes, .fused_kind = .Matmul }); // fused matmul+relu (activation fused)
        }
    }

    fn detectConvBnRelu(self: *FusionPass, g: *const Graph, out: *std.ArrayList(FusedGroup)) !void {
        // Pattern: Conv2D -> BatchNorm -> Relu (single-consumer chain)
        for (g.nodes.items, 0..) |node, i| {
            if (node.kind != .Conv2D) continue;
            if (node.outputs.len != 1) continue;
            const e1 = g.edges.items[node.outputs[0]];
            if (e1.consumers.len != 1) continue;
            const bn_id = e1.consumers[0];
            const bn = g.nodes.items[bn_id];
            if (bn.kind != .BatchNorm or bn.outputs.len != 1) continue;
            const e2 = g.edges.items[bn.outputs[0]];
            if (e2.consumers.len != 1) continue;
            const relu_id = e2.consumers[0];
            const relu = g.nodes.items[relu_id];
            if (relu.kind != .Relu) continue;
            const nodes = try self.allocator.alloc(NodeId, 3);
            nodes[0] = @intCast(i);
            nodes[1] = bn_id;
            nodes[2] = relu_id;
            try out.append(self.allocator, .{ .nodes = nodes, .fused_kind = .Conv2D }); // fused conv+bn+relu
        }
    }
};

// ------------------ Tests ------------------
const testing = std.testing;

test "FusionPass: Matmul->Relu plan when enabled" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    var dims_a: [2]u32 = [_]u32{ 8, 4 };
    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = dims_a[0..] }, .mem = null }, null);
    const dims_b = [_]u32{ 4, 16 };
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_b[0..]) }, .mem = null }, null);
    const dims_o = [_]u32{ 8, 16 };
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_o[0..]) }, .mem = null }, null);
    _ = try g.addNode(.Matmul, &[_]EdgeId{ a, b }, &[_]EdgeId{ o });
    const o2 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_o[0..]) }, .mem = null }, null);
    _ = try g.addNode(.Relu, &[_]EdgeId{ o }, &[_]EdgeId{ o2 });

    var pass = FusionPass.init(testing.allocator, .{ .matmul_relu = true, .conv_bn_relu = false });
    var plan = try pass.plan(&g);
    defer plan.deinit(testing.allocator);
    try testing.expect(plan.groups.len == 1);
    try testing.expect(plan.groups[0].nodes.len == 2);
}

test "FusionPass: disabled capability yields empty plan" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const dims_a = [_]u32{ 8, 4 };
    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_a[0..]) }, .mem = null }, null);
    const dims_b = [_]u32{ 4, 16 };
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_b[0..]) }, .mem = null }, null);
    const dims_o = [_]u32{ 8, 16 };
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_o[0..]) }, .mem = null }, null);
    _ = try g.addNode(.Matmul, &[_]EdgeId{ a, b }, &[_]EdgeId{ o });
    const o2 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_o[0..]) }, .mem = null }, null);
    _ = try g.addNode(.Relu, &[_]EdgeId{ o }, &[_]EdgeId{ o2 });

    var pass = FusionPass.init(testing.allocator, .{ .matmul_relu = false, .conv_bn_relu = false });
    var plan = try pass.plan(&g);
    defer plan.deinit(testing.allocator);
    try testing.expect(plan.groups.len == 0);
}

test "FusionPass: Conv->BatchNorm->Relu chain fused when capability enabled" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const dims_input = [_]u32{ 1, 64, 56, 56 };
    const input = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_input[0..]) }, .mem = null }, null);
    const dims_weight = [_]u32{ 64, 64, 3, 3 };
    const weight = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_weight[0..]) }, .mem = null }, null);
    const dims_conv = [_]u32{ 1, 64, 54, 54 };
    const conv_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_conv[0..]) }, .mem = null }, null);
    _ = try g.addNode(.Conv2D, &[_]EdgeId{ input, weight }, &[_]EdgeId{ conv_out });

    const bn_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_conv[0..]) }, .mem = null }, null);
    _ = try g.addNode(.BatchNorm, &[_]EdgeId{ conv_out }, &[_]EdgeId{ bn_out });

    const relu_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_conv[0..]) }, .mem = null }, null);
    _ = try g.addNode(.Relu, &[_]EdgeId{ bn_out }, &[_]EdgeId{ relu_out });

    var pass = FusionPass.init(testing.allocator, .{ .matmul_relu = false, .conv_bn_relu = true });
    var plan = try pass.plan(&g);
    defer plan.deinit(testing.allocator);
    try testing.expect(plan.groups.len == 1);
    try testing.expect(plan.groups[0].fused_kind == .Conv2D);
    try testing.expect(plan.groups[0].nodes.len == 3);
}

test "FusionPass: Conv chain not fused when outputs have multiple consumers" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const dims_input = [_]u32{ 1, 32, 28, 28 };
    const input = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_input[0..]) }, .mem = null }, null);
    const dims_weight = [_]u32{ 32, 32, 3, 3 };
    const weight = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_weight[0..]) }, .mem = null }, null);
    const dims_conv = [_]u32{ 1, 32, 26, 26 };
    const conv_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_conv[0..]) }, .mem = null }, null);
    _ = try g.addNode(.Conv2D, &[_]EdgeId{ input, weight }, &[_]EdgeId{ conv_out });

    const extra_weight = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_conv[0..]) }, .mem = null }, null);
    const extra_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_conv[0..]) }, .mem = null }, null);
    _ = try g.addNode(.Add, &[_]EdgeId{ conv_out, extra_weight }, &[_]EdgeId{ extra_out });

    const bn_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_conv[0..]) }, .mem = null }, null);
    _ = try g.addNode(.BatchNorm, &[_]EdgeId{ conv_out }, &[_]EdgeId{ bn_out });
    const relu_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(dims_conv[0..]) }, .mem = null }, null);
    _ = try g.addNode(.Relu, &[_]EdgeId{ bn_out }, &[_]EdgeId{ relu_out });

    var pass = FusionPass.init(testing.allocator, .{});
    var plan = try pass.plan(&g);
    defer plan.deinit(testing.allocator);

    try testing.expect(plan.groups.len == 0);
}
