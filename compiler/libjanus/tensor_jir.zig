// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor J‑IR — Core graph structures and verifier (v0.1.1-dev)

const std = @import("std");
const diag = @import("tensor_diagnostics.zig");

pub const Allocator = std.mem.Allocator;

// Element data types supported in J‑IR (subset; map to semantic PrimitiveType)
pub const DType = enum { i8, i16, i32, f16, f32, f64, bf16, bool };

// Memory spaces (aligns with semantic MemSpace). Optional on tensors.
pub const MemSpace = enum { sram, dram, vram, host, shared };

pub const EdgeId = u32;
pub const NodeId = u32;

pub const Shape = struct {
    dims: []u32,
};

pub const Tensor = struct {
    dtype: DType,
    shape: Shape,
    mem: ?MemSpace = null,
};

pub const OpKind = enum {
    Matmul,
    Conv2D,
    BatchNorm,
    Relu,
    Gelu,
    Add,
    Mul,
    ReduceSum,
    Reshape,
    Transpose,
    Concat,
    Split,
    Quantize,
    Dequantize,
    Copy,
    Transfer, // explicit memspace change
    Barrier,
};

pub const DeviceHint = enum { cpu, gpu, npu, apu, auto };

pub const OpNode = struct {
    kind: OpKind,
    inputs: []EdgeId,  // consumed tensors
    outputs: []EdgeId, // produced tensors
    device_hint: ?DeviceHint = null,
};

pub const TensorEdge = struct {
    tensor: Tensor,
    producer: ?NodeId, // node that produces this tensor
    consumers: []NodeId,
};

pub const Graph = struct {
    allocator: Allocator,
    nodes: std.ArrayListUnmanaged(OpNode),
    edges: std.ArrayListUnmanaged(TensorEdge),

    pub fn init(allocator: Allocator) Graph {
        return .{ .allocator = allocator, .nodes = .{}, .edges = .{} };
    }

    pub fn deinit(self: *Graph) void {
        for (self.nodes.items) |node| {
            self.allocator.free(node.inputs);
            self.allocator.free(node.outputs);
        }
        self.nodes.deinit(self.allocator);

        for (self.edges.items) |edge| {
            self.allocator.free(edge.tensor.shape.dims);
            self.allocator.free(edge.consumers);
        }
        self.edges.deinit(self.allocator);
    }

    pub fn addEdge(self: *Graph, t: Tensor, producer: ?NodeId) !EdgeId {
        // Own the shape dims to control lifetime
        const dims_owned = try self.allocator.alloc(u32, t.shape.dims.len);
        std.mem.copyForwards(u32, dims_owned, t.shape.dims);
        const edge = TensorEdge{
            .tensor = .{ .dtype = t.dtype, .shape = .{ .dims = dims_owned }, .mem = t.mem },
            .producer = producer,
            .consumers = &[_]NodeId{},
        };
        try self.edges.append(self.allocator, edge);
        return @intCast(self.edges.items.len - 1);
    }

    pub fn addNode(self: *Graph, kind: OpKind, inputs: []const EdgeId, outputs: []const EdgeId) !NodeId {
        // Copy input/output lists into graph-owned memory
        const in_copy = try self.allocator.alloc(EdgeId, inputs.len);
        std.mem.copyForwards(EdgeId, in_copy, inputs);
        const out_copy = try self.allocator.alloc(EdgeId, outputs.len);
        std.mem.copyForwards(EdgeId, out_copy, outputs);

        const node = OpNode{ .kind = kind, .inputs = in_copy, .outputs = out_copy, .device_hint = null };
        try self.nodes.append(self.allocator, node);
        const nid: NodeId = @intCast(self.nodes.items.len - 1);

        // Record producer/consumers
        for (inputs) |eid| {
            var e = &self.edges.items[eid];
            const newlen = e.consumers.len + 1;
            var grown = try self.allocator.alloc(NodeId, newlen);
            if (e.consumers.len > 0) std.mem.copyForwards(NodeId, grown, e.consumers);
            grown[newlen - 1] = nid;
            self.allocator.free(e.consumers);
            e.consumers = grown;
        }
        for (outputs) |eid| {
            self.edges.items[eid].producer = nid;
        }
        return nid;
    }

    // ------------------ Verifier ------------------
    pub fn verify(self: *Graph) !void {
        try self.verifyWithDiagnostics(null);
    }

    pub fn verifyWithDiagnostics(self: *Graph, diagnostics: ?*diag.TensorDiagnostics) !void {
        self.verifyAcyclic() catch |err| {
            if (diagnostics) |d| {
                _ = d.cycleDetected() catch {};
            }
            return err;
        };
        try self.verifyShapesAndMemspaces(diagnostics);
    }

    fn verifyAcyclic(self: *Graph) !void {
        const n = self.nodes.items.len;
        const temp_mark = try self.allocator.alloc(bool, n);
        defer self.allocator.free(temp_mark);
        const perm_mark = try self.allocator.alloc(bool, n);
        defer self.allocator.free(perm_mark);
        @memset(temp_mark, false);
        @memset(perm_mark, false);

        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (!perm_mark[i]) try self.visit(i, temp_mark, perm_mark);
        }
    }

    fn visit(self: *Graph, i: usize, temp_mark: []bool, perm_mark: []bool) !void {
        if (perm_mark[i]) return;
        if (temp_mark[i]) return error.CycleDetected;
        temp_mark[i] = true;
        const node = &self.nodes.items[i];
        // For each output, visit consumers
        for (node.outputs) |eid| {
            const edge = &self.edges.items[eid];
            for (edge.consumers) |cid| try self.visit(cid, temp_mark, perm_mark);
        }
        temp_mark[i] = false;
        perm_mark[i] = true;
    }

    fn verifyShapesAndMemspaces(self: *Graph, diagnostics: ?*diag.TensorDiagnostics) !void {
        for (self.nodes.items, 0..) |node, idx| {
            const node_id: NodeId = @intCast(idx);
            switch (node.kind) {
                .Matmul => try self.checkMatmul(node_id, node, diagnostics),
                .Relu, .Gelu => try self.checkUnaryShapePreserve(node_id, node, diagnostics),
                .Add, .Mul => try self.checkBinaryBroadcastable(node_id, node, diagnostics),
                .Transfer => try self.checkTransfer(node_id, node, diagnostics),
                else => {}, // TODO: extend with more ops
            }
        }
    }

    fn shapeOf(self: *Graph, eid: EdgeId) []const u32 {
        return self.edges.items[eid].tensor.shape.dims;
    }

    fn memOf(self: *Graph, eid: EdgeId) ?MemSpace {
        return self.edges.items[eid].tensor.mem;
    }

    fn checkMatmul(self: *Graph, node_id: NodeId, node: OpNode, diagnostics: ?*diag.TensorDiagnostics) !void {
        if (node.inputs.len != 2 or node.outputs.len != 1) {
            if (diagnostics) |d| {
                _ = d.invalidArity(node_id, "Matmul", 2, node.inputs.len, 1, node.outputs.len) catch {};
            }
            return error.InvalidArity;
        }
        const a = self.shapeOf(node.inputs[0]);
        const b = self.shapeOf(node.inputs[1]);
        const out = self.shapeOf(node.outputs[0]);
        if (a.len != 2 or b.len != 2 or out.len != 2) {
            if (diagnostics) |d| {
                const alloc = d.allocator;
                const a_shape = diag.formatShape(alloc, a) catch null;
                defer if (a_shape) |s| alloc.free(s);
                const b_shape = diag.formatShape(alloc, b) catch null;
                defer if (b_shape) |s| alloc.free(s);
                const out_shape = diag.formatShape(alloc, out) catch null;
                defer if (out_shape) |s| alloc.free(s);
                if (a_shape) |lhs| {
                    if (b_shape) |rhs| {
                const actual = std.fmt.allocPrint(alloc, "{s} × {s} -> {s}", .{ lhs, rhs, if (out_shape) |val| val else "?" }) catch null;
                defer if (actual) |act| alloc.free(act);
                const actual_slice: []const u8 = if (actual) |val| val else "unknown";
                _ = d.shapeMismatch(node_id, "Matmul", "rank-2 operands with rank-2 output", actual_slice) catch {};
                    }
                }
            }
            return error.ShapeMismatch;
        }
        const m = a[0];
        const k1 = a[1];
        const k2 = b[0];
        const n = b[1];
        if (k1 != k2) {
            if (diagnostics) |d| {
                const alloc = d.allocator;
                const a_shape = diag.formatShape(alloc, a) catch null;
                defer if (a_shape) |s| alloc.free(s);
                const b_shape = diag.formatShape(alloc, b) catch null;
                defer if (b_shape) |s| alloc.free(s);
                if (a_shape) |lhs| {
                    if (b_shape) |rhs| {
                        const actual = std.fmt.allocPrint(alloc, "inner dims {d} vs {d} ({s} × {s})", .{ k1, k2, lhs, rhs }) catch null;
                        defer if (actual) |act| alloc.free(act);
                        const actual_slice: []const u8 = if (actual) |val| val else "inner dimension mismatch";
                        _ = d.shapeMismatch(node_id, "Matmul", "matching inner dimensions", actual_slice) catch {};
                    }
                }
            }
            return error.ShapeMismatch;
        }
        if (!(out[0] == m and out[1] == n)) {
            if (diagnostics) |d| {
                const alloc = d.allocator;
                const out_shape = diag.formatShape(alloc, out) catch null;
                defer if (out_shape) |s| alloc.free(s);
                const expected = std.fmt.allocPrint(alloc, "output [{d} x {d}]", .{ m, n }) catch null;
                defer if (expected) |s| alloc.free(s);
                const exp_slice: []const u8 = if (expected) |val| val else "output shape [M x N]";
                const out_slice: []const u8 = if (out_shape) |val| val else "unknown output";
                _ = d.shapeMismatch(node_id, "Matmul", exp_slice, out_slice) catch {};
            }
            return error.ShapeMismatch;
        }
        // memspace: if set, inputs should be same unless op implies movement (not for Matmul)
        const ma = self.memOf(node.inputs[0]);
        const mb = self.memOf(node.inputs[1]);
        const mo = self.memOf(node.outputs[0]);
        if (ma != null and mb != null and ma.? != mb.?) {
            if (diagnostics) |d| {
                _ = d.memspaceMismatch(node_id, "Matmul inputs", @tagName(ma.?), @tagName(mb.?)) catch {};
            }
            return error.MemspaceMismatch;
        }
        if (ma != null and mo != null and ma.? != mo.?) {
            if (diagnostics) |d| {
                _ = d.memspaceMismatch(node_id, "Matmul output", @tagName(ma.?), @tagName(mo.?)) catch {};
            }
            return error.MemspaceMismatch;
        }
    }

    fn checkUnaryShapePreserve(self: *Graph, node_id: NodeId, node: OpNode, diagnostics: ?*diag.TensorDiagnostics) !void {
        if (node.inputs.len != 1 or node.outputs.len != 1) {
            if (diagnostics) |d| {
                _ = d.invalidArity(node_id, @tagName(node.kind), 1, node.inputs.len, 1, node.outputs.len) catch {};
            }
            return error.InvalidArity;
        }
        const in_s = self.shapeOf(node.inputs[0]);
        const out_s = self.shapeOf(node.outputs[0]);
        if (!shapesEqual(in_s, out_s)) {
            if (diagnostics) |d| {
                const alloc = d.allocator;
                const in_shape = diag.formatShape(alloc, in_s) catch null;
                defer if (in_shape) |s| alloc.free(s);
                const out_shape = diag.formatShape(alloc, out_s) catch null;
                defer if (out_shape) |s| alloc.free(s);
                const in_slice: []const u8 = if (in_shape) |val| val else "input shape";
                const out_slice: []const u8 = if (out_shape) |val| val else "output shape";
                _ = d.shapeMismatch(node_id, @tagName(node.kind), in_slice, out_slice) catch {};
            }
            return error.ShapeMismatch;
        }
    }

    fn checkBinaryBroadcastable(self: *Graph, node_id: NodeId, node: OpNode, diagnostics: ?*diag.TensorDiagnostics) !void {
        if (node.inputs.len != 2 or node.outputs.len != 1) {
            if (diagnostics) |d| {
                _ = d.invalidArity(node_id, @tagName(node.kind), 2, node.inputs.len, 1, node.outputs.len) catch {};
            }
            return error.InvalidArity;
        }
        const a = self.shapeOf(node.inputs[0]);
        const b = self.shapeOf(node.inputs[1]);
        const out = self.shapeOf(node.outputs[0]);
        if (!isBroadcastable(a, b)) {
            if (diagnostics) |d| {
                const alloc = d.allocator;
                const a_shape = diag.formatShape(alloc, a) catch null;
                defer if (a_shape) |s| alloc.free(s);
                const b_shape = diag.formatShape(alloc, b) catch null;
                defer if (b_shape) |s| alloc.free(s);
                if (a_shape) |lhs| {
                    if (b_shape) |rhs| {
                const actual = std.fmt.allocPrint(alloc, "lhs={s}, rhs={s}", .{ lhs, rhs }) catch null;
                defer if (actual) |act| alloc.free(act);
                const actual_slice: []const u8 = if (actual) |val| val else "non-broadcastable shapes";
                _ = d.shapeMismatch(node_id, @tagName(node.kind), "broadcastable shapes", actual_slice) catch {};
                    }
                }
            }
            return error.ShapeMismatch;
        }
        const exp = computeBroadcastShapeAlloc(self.allocator, a, b) catch |err| {
            if (diagnostics) |d| {
                const alloc = d.allocator;
                const a_shape = diag.formatShape(alloc, a) catch null;
                defer if (a_shape) |s| alloc.free(s);
                const b_shape = diag.formatShape(alloc, b) catch null;
                defer if (b_shape) |s| alloc.free(s);
                const lhs_slice: []const u8 = if (a_shape) |val| val else "?";
                const rhs_slice: []const u8 = if (b_shape) |val| val else "?";
                const msg = std.fmt.allocPrint(alloc, "lhs={s}, rhs={s}", .{ lhs_slice, rhs_slice }) catch null;
                defer if (msg) |m| alloc.free(m);
                const msg_slice: []const u8 = if (msg) |val| val else @errorName(err);
                _ = d.shapeMismatch(node_id, @tagName(node.kind), "broadcastable shapes", msg_slice) catch {};
            }
            return err;
        };
        defer self.allocator.free(exp);
        if (!shapesEqual(out, exp)) {
            if (diagnostics) |d| {
                const alloc = d.allocator;
                const exp_shape = diag.formatShape(alloc, exp) catch null;
                defer if (exp_shape) |s| alloc.free(s);
                const out_shape = diag.formatShape(alloc, out) catch null;
                defer if (out_shape) |s| alloc.free(s);
                const exp_slice: []const u8 = if (exp_shape) |val| val else "expected broadcast shape";
                const out_slice: []const u8 = if (out_shape) |val| val else "output shape";
                _ = d.shapeMismatch(node_id, @tagName(node.kind), exp_slice, out_slice) catch {};
            }
            return error.ShapeMismatch;
        }
    }

    fn checkTransfer(self: *Graph, node_id: NodeId, node: OpNode, diagnostics: ?*diag.TensorDiagnostics) !void {
        if (node.inputs.len != 1 or node.outputs.len != 1) {
            if (diagnostics) |d| {
                _ = d.invalidArity(node_id, "Transfer", 1, node.inputs.len, 1, node.outputs.len) catch {};
            }
            return error.InvalidArity;
        }
        const mi = self.memOf(node.inputs[0]);
        const mo = self.memOf(node.outputs[0]);
        if (mi == null or mo == null) {
            if (diagnostics) |d| {
                _ = d.memspaceMissing(node_id, "Transfer") catch {};
            }
            return error.MemspaceMissing;
        }
        if (mi.? == mo.?) {
            if (diagnostics) |d| {
                _ = d.memspaceNoChange(node_id, "Transfer", @tagName(mi.?)) catch {};
            }
            return error.MemspaceNoChange;
        }
    }
};

// -------- Shape helpers (duplicate of semantics version; kept local to avoid coupling) --------
pub fn shapesEqual(a: []const u32, b: []const u32) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) if (a[i] != b[i]) return false;
    return true;
}

pub fn isBroadcastable(a: []const u32, b: []const u32) bool {
    var ia: isize = @intCast(a.len);
    var ib: isize = @intCast(b.len);
    while (ia > 0 or ib > 0) {
        const da: u32 = if (ia > 0) a[@intCast(ia - 1)] else 1;
        const db: u32 = if (ib > 0) b[@intCast(ib - 1)] else 1;
        if (!(da == db or da == 1 or db == 1)) return false;
        ia -= 1;
        ib -= 1;
    }
    return true;
}

pub fn computeBroadcastShapeAlloc(allocator: Allocator, a: []const u32, b: []const u32) ![]u32 {
    if (!isBroadcastable(a, b)) return error.IncompatibleShapes;
    const out_len: usize = if (a.len > b.len) a.len else b.len;
    var out = try allocator.alloc(u32, out_len);
    var ia: isize = @intCast(a.len);
    var ib: isize = @intCast(b.len);
    var io: isize = @intCast(out_len);
    while (io > 0) : (io -= 1) {
        const da: u32 = if (ia > 0) a[@intCast(ia - 1)] else 1;
        const db: u32 = if (ib > 0) b[@intCast(ib - 1)] else 1;
        out[@intCast(io - 1)] = if (da == 1) db else da;
        ia -= 1;
        ib -= 1;
    }
    return out;
}

// ------------------ Tests ------------------
const testing = std.testing;

test "J-IR: matmul shape/memspace checks and acyclicity" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();

    const a_e = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = @constCast(&[_]u32{ 128, 64 }) }, .mem = .sram }, null);
    const b_e = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = @constCast(&[_]u32{ 64, 256 }) }, .mem = .sram }, null);
    const o_e = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = @constCast(&[_]u32{ 128, 256 }) }, .mem = .sram }, null);
    _ = try g.addNode(.Matmul, &[_]EdgeId{ a_e, b_e }, &[_]EdgeId{ o_e });

    try g.verify();
}

test "J-IR: add with broadcasting and transfer memspace" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();

    const x = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 1, 256 }) }, .mem = .dram }, null);
    const y = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 128, 256 }) }, .mem = .dram }, null);
    const z = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 128, 256 }) }, .mem = .dram }, null);
    _ = try g.addNode(.Add, &[_]EdgeId{ x, y }, &[_]EdgeId{ z });

    // Now transfer to sram
    const z2 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 128, 256 }) }, .mem = .sram }, null);
    _ = try g.addNode(.Transfer, &[_]EdgeId{ z }, &[_]EdgeId{ z2 });

    try g.verify();
}

test "J-IR: cycle detection" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();

    const e1 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 4, 4 }) }, .mem = .dram }, null);
    const e_aux = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 4, 4 }) }, .mem = .dram }, null);
    const e2 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 4, 4 }) }, .mem = .dram }, null);
    _ = try g.addNode(.Add, &[_]EdgeId{ e1, e_aux }, &[_]EdgeId{ e2 });
    // Create a cycle by feeding e2 back into a new node that outputs to e1
    const e_aux2 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 4, 4 }) }, .mem = .dram }, null);
    const e3 = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 4, 4 }) }, .mem = .dram }, null);
    _ = try g.addNode(.Add, &[_]EdgeId{ e2, e_aux2 }, &[_]EdgeId{ e3 });
    // overwrite e1 producer to emulate a cycle (not typical API usage but for test)
    g.edges.items[e1].producer = @intCast(g.nodes.items.len - 1);
    const last = &g.nodes.items[g.nodes.items.len - 1];
    const new_outputs = try g.allocator.alloc(EdgeId, last.outputs.len + 1);
    std.mem.copyForwards(EdgeId, new_outputs, last.outputs);
    new_outputs[last.outputs.len] = e1;
    g.allocator.free(last.outputs);
    last.outputs = new_outputs;

    const res = g.verify();
    try testing.expectError(error.CycleDetected, res);
}

test "Graph.verifyWithDiagnostics records shape mismatch" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 4, 3 }) }, .mem = null }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 5, 2 }) }, .mem = null }, null);
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 4, 2 }) }, .mem = null }, null);
    _ = try g.addNode(.Matmul, &[_]EdgeId{ a, b }, &[_]EdgeId{ o });

    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();

    const res = g.verifyWithDiagnostics(&diags);
    try testing.expectError(error.ShapeMismatch, res);
    try testing.expect(diags.all().len >= 1);
    try testing.expect(diags.all()[0].kind == .shape_mismatch);
}

test "Shape algebra: broadcast helper merges and rejects incompatible dims" {
    // Compatible broadcast
    const shape = try computeBroadcastShapeAlloc(testing.allocator, &[_]u32{ 1, 64 }, &[_]u32{ 32, 1, 64 });
    defer testing.allocator.free(shape);
    try testing.expectEqual(@as(usize, 3), shape.len);
    try testing.expect(shape[0] == 32 and shape[1] == 1 and shape[2] == 64);

    // Incompatible broadcast should error
    const incompatible = computeBroadcastShapeAlloc(testing.allocator, &[_]u32{ 2, 3 }, &[_]u32{ 4, 5 });
    try testing.expectError(error.IncompatibleShapes, incompatible);
}

test "Transfer verifier errors when memspace unchanged" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();

    const input = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 8, 8 }) }, .mem = .sram }, null);
    const output = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 8, 8 }) }, .mem = .sram }, null);
    _ = try g.addNode(.Transfer, &[_]EdgeId{ input }, &[_]EdgeId{ output });

    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();

    const res = g.verifyWithDiagnostics(&diags);
    try testing.expectError(error.MemspaceNoChange, res);
    try testing.expect(diags.all().len >= 1);
    try testing.expect(diags.all()[0].kind == .memspace_no_change);
}
