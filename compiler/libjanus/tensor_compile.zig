// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Compile Diagnostics — centralized compile-time checks for :npu graphs

const std = @import("std");
const jir = @import("tensor_jir.zig");
const diag = @import("tensor_diagnostics.zig");
const quant = @import("tensor_quant.zig");
const device_dispatch = @import("tensor_device_dispatch.zig");
const kernel_registry = @import("tensor_kernel_registry.zig");

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;
pub const TensorDiagnostics = diag.TensorDiagnostics;

/// Compile-time options for diagnostic runs.
pub const CompileOptions = struct {
    quant_policy: quant.QuantPolicy = .{},
    quant_support: quant.QuantOpSupport = .{},
};

/// Centralized compile-time diagnostic runner for tensor graphs.
pub const CompileDiagnostics = struct {
    allocator: Allocator,
    options: CompileOptions,
    diagnostics: TensorDiagnostics,

    pub fn init(allocator: Allocator, options: CompileOptions) CompileDiagnostics {
        return .{
            .allocator = allocator,
            .options = options,
            .diagnostics = TensorDiagnostics.init(allocator),
        };
    }

    pub fn deinit(self: *CompileDiagnostics) void {
        self.diagnostics.deinit();
    }

    /// Access collected diagnostics.
    pub fn diagnosticsSlice(self: *CompileDiagnostics) []const diag.Diagnostic {
        return self.diagnostics.all();
    }

    /// Transfer ownership of collected diagnostics to the caller. The caller must
    /// eventually call `diag.TensorDiagnostics.deinit` on the returned value.
    pub fn releaseDiagnostics(self: *CompileDiagnostics) TensorDiagnostics {
        const owned = self.diagnostics;
        self.diagnostics = TensorDiagnostics.init(self.allocator);
        return owned;
    }

    /// Run the compile-time checks for the provided graph, emitting diagnostics for
    /// shape verification, quantization planning, and backend device selection.
    pub fn analyzeGraph(self: *CompileDiagnostics, graph: *Graph) !void {
        try self.verifyGraph(graph);
        try self.planQuantization(graph);
        try self.planDevices(graph);
    }

    /// Record a profile-gating diagnostic for a feature that requires :npu.
    pub fn requireProfile(self: *CompileDiagnostics, feature: []const u8, profile: []const u8, span: ?diag.SourceSpan) void {
        _ = self.diagnostics.profileRequired(feature, profile, span) catch {};
    }

    fn verifyGraph(self: *CompileDiagnostics, graph: *Graph) !void {
        try graph.verifyWithDiagnostics(&self.diagnostics);
    }

    fn planQuantization(self: *CompileDiagnostics, graph: *const Graph) !void {
        var pass = quant.QuantizationPass.init(self.allocator, self.options.quant_policy, self.options.quant_support);
        var plan = try pass.plan(graph, &self.diagnostics);
        defer plan.deinit(self.allocator);
    }

    fn planDevices(self: *CompileDiagnostics, graph: *const Graph) !void {
        var registry = kernel_registry.KernelRegistry{};
        var plan = try device_dispatch.resolveDevices(self.allocator, graph, &registry, &self.diagnostics);
        defer plan.deinit(self.allocator);
    }
};

// ------------------ Tests ------------------
const testing = std.testing;
const builder = @import("tensor_builder.zig");

test "compile diagnostics capture matmul shape mismatch" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 3 } }, .mem = null }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 5, 2 } }, .mem = null }, null);
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 2 } }, .mem = null }, null);
    _ = try g.addNode(.Matmul, &[_]jir.EdgeId{ a, b }, &[_]jir.EdgeId{ o });

    var ctx = CompileDiagnostics.init(testing.allocator, .{});
    defer ctx.deinit();

    const err = ctx.analyzeGraph(&g);
    try testing.expectError(error.ShapeMismatch, err);

    const diags = ctx.diagnosticsSlice();
    try testing.expect(diags.len >= 1);
    try testing.expect(diags[0].kind == .shape_mismatch);
}

test "compile diagnostics capture backend fallback" {
    var bld = builder.Builder.init(testing.allocator);
    defer bld.deinit();

    const x = try bld.input(.f32, &[_]u32{ 1, 256 }, .dram);
    const y = try bld.input(.f32, &[_]u32{ 128, 256 }, .dram);
    const sum = try bld.add(x, y);
    const moved = try bld.transfer(sum, .sram);
    _ = moved;

    var ctx = CompileDiagnostics.init(testing.allocator, .{});
    defer ctx.deinit();

    try ctx.analyzeGraph(bld.getGraph());

    const diags = ctx.diagnosticsSlice();
    var saw_fallback = false;
    for (diags) |d| saw_fallback = saw_fallback or d.kind == .backend_fallback;
    try testing.expect(saw_fallback);
}

test "compile diagnostics record quantization disabled and unsupported" {
    var bld = builder.Builder.init(testing.allocator);
    defer bld.deinit();

    const a = try bld.input(.f32, &[_]u32{ 8, 8 }, null);
    const b = try bld.input(.f32, &[_]u32{ 8, 8 }, null);
    const m = try bld.matmul(a, b, null);
    const t = try bld.transfer(m, .sram);
    _ = t;

    var ctx = CompileDiagnostics.init(testing.allocator, .{ .quant_policy = .{ .enabled = false } });
    defer ctx.deinit();

    try ctx.analyzeGraph(bld.getGraph());

    const diags = ctx.diagnosticsSlice();
    var saw_policy = false;
    var saw_unsupported = false;
    for (diags) |d| {
        if (d.kind == .quantization_policy_disabled) saw_policy = true;
        if (d.kind == .quantization_not_supported) saw_unsupported = true;
    }
    try testing.expect(saw_policy);
    try testing.expect(saw_unsupported);
}

test "compile diagnostics record profile gating" {
    var ctx = CompileDiagnostics.init(testing.allocator, .{});
    defer ctx.deinit();

    ctx.requireProfile("tensor type", ":npu", null);
    const diags = ctx.diagnosticsSlice();
    try testing.expect(diags.len == 1);
    try testing.expect(diags[0].kind == .profile_required);
}
