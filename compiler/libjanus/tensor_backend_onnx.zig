// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

// Janus Tensor Backend — ONNX exporter (scaffolding JSON form)

const std = @import("std");
const tensor_backend = @import("tensor_backend.zig");
const jir = @import("tensor_jir.zig");
const List = @import("mem/ctx/List.zig").List;
const region = @import("mem/region.zig");

pub const Allocator = std.mem.Allocator;
pub const Backend = tensor_backend.Backend;
pub const BackendOps = tensor_backend.BackendOps;
pub const PlanningBundle = tensor_backend.PlanningBundle;
pub const OpKind = jir.OpKind;
pub const DType = jir.DType;

pub const OnnxBackend = struct {
    pub fn make() Backend {
        return Backend{
            .ops = BackendOps{
                .name = "onnx",
                .supports = &supports,
                .emit = &emit,
                .deinit = null,
            },
            .ctx = null,
        };
    }

    fn supports(_: *const Backend, kind: OpKind) bool {
        return switch (kind) {
            .Matmul, .Relu, .Add, .Mul, .Transpose, .Reshape, .Concat, .Split, .ReduceSum, .Conv2D, .BatchNorm => true,
            .Transfer, .Copy, .Barrier, .Quantize, .Dequantize => true, // represent via attributes or identity
            .Gelu => true, // as custom op if needed
        };
    }

    fn dtypeToOnnx(dt: DType) []const u8 {
        return switch (dt) {
            .f32 => "FLOAT",
            .f16 => "FLOAT16",
            .bf16 => "BFLOAT16",
            .f64 => "DOUBLE",
            .i8 => "INT8",
            .i16 => "INT16",
            .i32 => "INT32",
            .bool => "BOOL",
        };
    }

    fn emit(self: *const Backend, g: *const jir.Graph, plans: PlanningBundle, allocator: Allocator) ![]u8 {
        _ = self;
        _ = plans;
        var out = List(u8).with(allocator);
        errdefer out.deinit();
        const w = out.writer();

        try w.print("{{\n  \"ir_version\": 8,\n  \"producer_name\": \"janus\",\n  \"graph\": {{\n    \"name\": \"janus_graph\",\n    \"tensors\": [\n", .{});

        // Tensors
        for (g.edges.items, 0..) |edge, eid| {
            const dt = dtypeToOnnx(edge.tensor.dtype);
            try w.print("      {{ \"name\": \"e{d}\", \"dtype\": \"{s}\", \"shape\": [", .{ eid, dt });
            for (edge.tensor.shape.dims, 0..) |d, i| {
                try w.print("{d}{s}", .{ d, if (i + 1 < edge.tensor.shape.dims.len) "," else "" });
            }
            try w.print("]", .{});
            if (edge.tensor.mem) |ms| {
                try w.print(", \"memspace\": \"{s}\"", .{@tagName(ms)});
            }
            try w.print(" }}{s}\n", .{if (eid + 1 < g.edges.items.len) "," else ""});
        }

        try w.print("    ],\n    \"nodes\": [\n", .{});

        // Nodes
        for (g.nodes.items, 0..) |node, nid| {
            const op = opToOnnx(node.kind);
            try w.print("      {{ \"name\": \"n{d}\", \"op_type\": \"{s}\", \"inputs\": [", .{ nid, op });
            for (node.inputs, 0..) |eid, i| {
                try w.print("\"e{d}\"{s}", .{ eid, if (i + 1 < node.inputs.len) "," else "" });
            }
            try w.print("], \"outputs\": [", .{});
            for (node.outputs, 0..) |eid, i| {
                try w.print("\"e{d}\"{s}", .{ eid, if (i + 1 < node.outputs.len) "," else "" });
            }
            // Represent Transfer/Quantize/Dequantize with attributes
            if (node.kind == .Transfer or node.kind == .Quantize or node.kind == .Dequantize) {
                try w.print("], \"attributes\": {{ \"janus_tag\": \"{s}\" }} }}{s}\n", .{ @tagName(node.kind), if (nid + 1 < g.nodes.items.len) "," else "" });
            } else {
                try w.print("] }}{s}\n", .{if (nid + 1 < g.nodes.items.len) "," else ""});
            }
        }

        try w.print("    ]\n  }}\n}}\n", .{});
        return out.toOwnedSlice();
    }

    fn opToOnnx(kind: OpKind) []const u8 {
        return switch (kind) {
            .Matmul => "MatMul",
            .Relu => "Relu",
            .Add => "Add",
            .Mul => "Mul",
            .Transpose => "Transpose",
            .Reshape => "Reshape",
            .Concat => "Concat",
            .Split => "Split",
            .ReduceSum => "ReduceSum",
            .Conv2D => "Conv",
            .BatchNorm => "BatchNormalization",
            .Transfer => "Identity", // with attribute
            .Copy => "Identity",
            .Barrier => "NoOp",
            .Quantize => "QuantizeLinear",
            .Dequantize => "DequantizeLinear",
            .Gelu => "Gelu", // ONNX domain op exists in newer opsets
        };
    }
};

// ------------------ Test ------------------
const testing = std.testing;
const builder = @import("tensor_builder.zig");

test "ONNX backend: emits JSON scaffold" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 2, 2 }, null);
    const w = try b.input(.f32, &[_]u32{ 2, 4 }, null);
    const m = try b.matmul(a, w, null);
    const r = try b.relu(m);
    _ = r;
    const g = b.getGraph();

    const be = OnnxBackend.make();
    const bytes = try be.emit(g, .{}, testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expect(std.mem.indexOf(u8, bytes, "\"graph\"") != null);
}
