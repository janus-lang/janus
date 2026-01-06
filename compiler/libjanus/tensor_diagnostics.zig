// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Diagnostics — centralised compile-time/runtime reporting

const std = @import("std");
const jir = @import("tensor_jir.zig");

const log = std.log.scoped(.tensor_diag);

pub const Allocator = std.mem.Allocator;
pub const NodeId = jir.NodeId;
pub const EdgeId = jir.EdgeId;

pub const Severity = enum { @"error", warning, info };

pub const Kind = enum {
    shape_mismatch,
    invalid_arity,
    memspace_mismatch,
    memspace_missing,
    memspace_no_change,
    cycle_detected,
    profile_required,
    backend_fallback,
    quantization_policy_disabled,
    quantization_not_supported,
    runtime_capability_denied,
    runtime_device_error,
    runtime_out_of_memory,
};

pub const SourceSpan = struct {
    file: []const u8 = "",
    start_line: u32 = 0,
    start_col: u32 = 0,
    end_line: u32 = 0,
    end_col: u32 = 0,
};

pub const Diagnostic = struct {
    kind: Kind,
    severity: Severity,
    code: []const u8,
    message: []u8,
    node: ?NodeId = null,
    edge: ?EdgeId = null,
    span: ?SourceSpan = null,

    pub fn deinit(self: *Diagnostic, allocator: Allocator) void {
        allocator.free(self.message);
    }
};

pub const TensorDiagnostics = struct {
    allocator: Allocator,
    items: std.ArrayListUnmanaged(Diagnostic),

    pub fn init(allocator: Allocator) TensorDiagnostics {
        return .{ .allocator = allocator, .items = .{} };
    }

    pub fn deinit(self: *TensorDiagnostics) void {
        for (self.items.items) |*item| item.deinit(self.allocator);
        self.items.deinit(self.allocator);
    }

    pub fn all(self: *const TensorDiagnostics) []const Diagnostic {
        return self.items.items;
    }

    pub fn shapeString(self: *TensorDiagnostics, dims: []const u32) ![]u8 {
        return formatShape(self.allocator, dims);
    }

    fn recordFmt(
        self: *TensorDiagnostics,
        code: []const u8,
        kind: Kind,
        severity: Severity,
        node: ?NodeId,
        edge: ?EdgeId,
        span: ?SourceSpan,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const msg = try std.fmt.allocPrint(self.allocator, fmt, args);
        errdefer self.allocator.free(msg);
        try self.items.append(self.allocator, .{
            .kind = kind,
            .severity = severity,
            .code = code,
            .message = msg,
            .node = node,
            .edge = edge,
            .span = span,
        });
    }

    pub fn shapeMismatch(
        self: *TensorDiagnostics,
        node: ?NodeId,
        op_name: []const u8,
        expected: []const u8,
        actual: []const u8,
    ) !void {
        try self.recordFmt(codes.shape_mismatch, .shape_mismatch, .@"error", node, null, null, "{s}: expected {s}, got {s}", .{ op_name, expected, actual });
    }

    pub fn invalidArity(
        self: *TensorDiagnostics,
        node: ?NodeId,
        op_name: []const u8,
        expected_inputs: usize,
        got_inputs: usize,
        expected_outputs: usize,
        got_outputs: usize,
    ) !void {
        try self.recordFmt(
            codes.invalid_arity,
            .invalid_arity,
            .@"error",
            node,
            null,
            null,
            "{s}: expected {d} inputs/{d} outputs but received {d} inputs/{d} outputs",
            .{ op_name, expected_inputs, expected_outputs, got_inputs, got_outputs },
        );
    }

    pub fn memspaceMismatch(
        self: *TensorDiagnostics,
        node: ?NodeId,
        op_name: []const u8,
        lhs: []const u8,
        rhs: []const u8,
    ) !void {
        try self.recordFmt(codes.memspace_mismatch, .memspace_mismatch, .@"error", node, null, null, "{s}: memory spaces must match (lhs={s}, rhs={s})", .{ op_name, lhs, rhs });
    }

    pub fn memspaceMissing(
        self: *TensorDiagnostics,
        node: ?NodeId,
        op_name: []const u8,
    ) !void {
        try self.recordFmt(codes.memspace_missing, .memspace_missing, .@"error", node, null, null, "{s}: memory space annotation is required", .{op_name});
    }

    pub fn memspaceNoChange(
        self: *TensorDiagnostics,
        node: ?NodeId,
        op_name: []const u8,
        mem: []const u8,
    ) !void {
        try self.recordFmt(codes.memspace_no_change, .memspace_no_change, .warning, node, null, null, "{s}: transfer does not change memory space (still {s})", .{ op_name, mem });
    }

    pub fn cycleDetected(self: *TensorDiagnostics) !void {
        try self.recordFmt(codes.cycle_detected, .cycle_detected, .@"error", null, null, null, "Tensor graph contains a cycle", .{});
    }

    pub fn profileRequired(
        self: *TensorDiagnostics,
        feature: []const u8,
        profile: []const u8,
        span: ?SourceSpan,
    ) !void {
        try self.recordFmt(codes.profile_required, .profile_required, .@"error", null, null, span, "Feature '{s}' requires profile {s}", .{ feature, profile });
    }

    pub fn backendFallback(
        self: *TensorDiagnostics,
        node: ?NodeId,
        op_name: []const u8,
        requested: []const u8,
        fallback: []const u8,
        reason: []const u8,
    ) !void {
        try self.recordFmt(
            codes.backend_fallback,
            .backend_fallback,
            .warning,
            node,
            null,
            null,
            "{s}: falling back from {s} to {s} ({s})",
            .{ op_name, requested, fallback, reason },
        );
    }

    pub fn quantizationPolicyDisabled(self: *TensorDiagnostics, mode: []const u8) !void {
        try self.recordFmt(codes.quant_policy_disabled, .quantization_policy_disabled, .info, null, null, null, "Quantization policy disabled (mode={s})", .{mode});
    }

    pub fn quantizationUnsupported(self: *TensorDiagnostics, op_name: []const u8) !void {
        try self.recordFmt(codes.quant_not_supported, .quantization_not_supported, .warning, null, null, null, "Quantization not supported for op {s}", .{op_name});
    }

    pub fn runtimeCapabilityDenied(self: *TensorDiagnostics, capability: []const u8, context: []const u8) !void {
        try self.recordFmt(codes.runtime_capability_denied, .runtime_capability_denied, .@"error", null, null, null, "Capability '{s}' denied while {s}", .{ capability, context });
        log.warn("Capability '{s}' denied in context '{s}'", .{ capability, context });
    }

    pub fn runtimeDeviceError(
        self: *TensorDiagnostics,
        node: ?NodeId,
        device: []const u8,
        message: []const u8,
    ) !void {
        try self.recordFmt(codes.runtime_device_error, .runtime_device_error, .@"error", node, null, null, "Device {s} error: {s}", .{ device, message });
        log.warn("Device {s} error: {s}", .{ device, message });
    }

    pub fn runtimeOutOfMemory(self: *TensorDiagnostics, resource: []const u8, device: []const u8) !void {
        try self.recordFmt(codes.runtime_out_of_memory, .runtime_out_of_memory, .@"error", null, null, null, "Out of memory while allocating {s} for {s}", .{ resource, device });
        log.warn("Out of memory allocating {s} for {s}", .{ resource, device });
    }
};

pub fn formatShape(allocator: Allocator, dims: []const u32) ![]u8 {
    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);
    var w = builder.writer(allocator);
    try w.writeByte('[');
    for (dims, 0..) |d, i| {
        try w.print("{d}", .{d});
        if (i + 1 < dims.len) try w.print(" x ", .{});
    }
    try w.writeByte(']');
    return builder.toOwnedSlice(allocator);
}

const codes = struct {
    const shape_mismatch = "NPU001";
    const invalid_arity = "NPU002";
    const memspace_mismatch = "NPU003";
    const memspace_missing = "NPU004";
    const memspace_no_change = "NPU005";
    const cycle_detected = "NPU006";
    const profile_required = "NPU010";
    const backend_fallback = "NPU020";
    const quant_policy_disabled = "NPU030";
    const quant_not_supported = "NPU031";
    const runtime_capability_denied = "NPU100";
    const runtime_device_error = "NPU101";
    const runtime_out_of_memory = "NPU102";
};

const testing = std.testing;

test "TensorDiagnostics records shape mismatch" {
    var diags = TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();
    try diags.shapeMismatch(null, "Matmul", "rank-2 operands", "[2 x 4] × [8 x 16]");
    try testing.expectEqual(@as(usize, 1), diags.all().len);
    try testing.expect(std.mem.eql(u8, diags.all()[0].code, codes.shape_mismatch));
}
