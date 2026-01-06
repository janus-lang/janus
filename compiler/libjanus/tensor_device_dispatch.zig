// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Device Dispatch — resolve device per J‑IR node

const std = @import("std");
const jir = @import("tensor_jir.zig");
const rt = @import("tensor_runtime.zig");
const regmod = @import("tensor_kernel_registry.zig");
const diag = @import("tensor_diagnostics.zig");
const fabric = @import("tensor_fabric_probe.zig");

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;
pub const DeviceKind = rt.DeviceKind;
pub const KernelRegistry = regmod.KernelRegistry;

pub const ResolveOptions = struct {
    has_apu: ?bool = null,
};

pub const DevicePlan = struct {
    devices: []DeviceKind, // indexed by node id
    pub fn deinit(self: *DevicePlan, allocator: Allocator) void { allocator.free(self.devices); }
};

pub fn resolveDevices(
    allocator: Allocator,
    g: *const Graph,
    registry: *const KernelRegistry,
    diagnostics: ?*diag.TensorDiagnostics,
) !DevicePlan {
    return resolveDevicesWithOptions(allocator, g, registry, diagnostics, .{});
}

pub fn resolveDevicesWithOptions(
    allocator: Allocator,
    g: *const Graph,
    registry: *const KernelRegistry,
    diagnostics: ?*diag.TensorDiagnostics,
    options: ResolveOptions,
) !DevicePlan {
    var devs = try allocator.alloc(DeviceKind, g.nodes.items.len);
    const has_apu = options.has_apu orelse detectUnifiedFabricAvailable(allocator);
    for (g.nodes.items, 0..) |node, i| {
        const node_id: jir.NodeId = @intCast(i);
        // Honor device hint if present
        if (node.device_hint) |hint| {
            const hinted: DeviceKind = switch (hint) {
                .cpu => .cpu,
                .gpu => .gpu,
                .npu => .npu,
                .apu => .apu,
                .auto => selectAutoDevice(node.kind, registry, has_apu),
            };
            if (hinted == .apu and !has_apu) {
                const fallback = selectAutoDevice(node.kind, registry, false);
                devs[i] = fallback;
                if (diagnostics) |d| {
                    _ = d.backendFallback(node_id, @tagName(node.kind), "apu", deviceName(fallback), "unified fabric not available") catch {};
                }
            } else if (registry.supports(node.kind, hinted)) {
                devs[i] = hinted;
            } else {
                const fallback = selectAutoDevice(node.kind, registry, has_apu and hinted != .apu);
                devs[i] = fallback;
                if (diagnostics) |d| {
                    _ = d.backendFallback(node_id, @tagName(node.kind), hintToStr(hint), deviceName(fallback), "hinted device lacks kernel") catch {};
                }
            }
            continue;
        }
        const auto_device = selectAutoDevice(node.kind, registry, has_apu);
        devs[i] = auto_device;
        if (diagnostics) |d| switch (auto_device) {
            .cpu => _ = d.backendFallback(node_id, @tagName(node.kind), "npu", "cpu", "no accelerator kernel available") catch {},
            .gpu => _ = d.backendFallback(node_id, @tagName(node.kind), "npu", "gpu", "kernel unavailable on npu") catch {},
            .npu => {},
            .apu => {},
        };
    }
    return DevicePlan{ .devices = devs };
}

fn deviceName(dev: DeviceKind) []const u8 {
    return switch (dev) {
        .cpu => "cpu",
        .gpu => "gpu",
        .npu => "npu",
        .apu => "apu",
    };
}

fn hintToStr(hint: jir.DeviceHint) []const u8 {
    return switch (hint) {
        .cpu => "cpu",
        .gpu => "gpu",
        .npu => "npu",
        .apu => "apu",
        .auto => "auto",
    };
}

fn detectUnifiedFabricAvailable(allocator: Allocator) bool {
    return fabric.detectUnifiedFabricAvailable(allocator);
}

fn selectAutoDevice(kind: jir.OpKind, registry: *const KernelRegistry, has_apu: bool) DeviceKind {
    if (has_apu and registry.supports(kind, .apu)) return .apu;
    if (registry.supports(kind, .npu)) return .npu;
    if (registry.supports(kind, .gpu)) return .gpu;
    return .cpu;
}

// Tests
const testing = std.testing;

test "device dispatch prefers apu when available" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();
    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const nid = try g.addNode(.Matmul, &[_]u32{ a, b }, &[_]u32{ o });
    _ = nid;

    var reg = KernelRegistry{};
    var plan = try resolveDevicesWithOptions(testing.allocator, &g, &reg, null, .{ .has_apu = true });
    defer plan.deinit(testing.allocator);
    try testing.expect(plan.devices.len == g.nodes.items.len);
    try testing.expect(plan.devices[0] == .apu);
}

test "device dispatch prefers npu when apu unavailable" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();
    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    _ = try g.addNode(.Matmul, &[_]u32{ a, b }, &[_]u32{ o });

    var reg = KernelRegistry{};
    var plan = try resolveDevicesWithOptions(testing.allocator, &g, &reg, null, .{ .has_apu = false });
    defer plan.deinit(testing.allocator);
    try testing.expect(plan.devices.len == g.nodes.items.len);
    try testing.expect(plan.devices[0] == .npu);
}

test "device dispatch records fallback diagnostic" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();
    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    _ = try g.addNode(.Transfer, &[_]u32{ a }, &[_]u32{ o });

    var reg = KernelRegistry{};
    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();

    var plan = try resolveDevicesWithOptions(testing.allocator, &g, &reg, &diags, .{ .has_apu = false });
    defer plan.deinit(testing.allocator);
    try testing.expect(plan.devices[0] == .cpu);
    try testing.expectEqual(@as(usize, 1), diags.all().len);
    try testing.expect(diags.all()[0].kind == .backend_fallback);
}

test "device dispatch falls back when apu hint unavailable" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();
    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const o = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = @constCast(&[_]u32{ 2, 2 }) }, .mem = null }, null);
    const node_id = try g.addNode(.Matmul, &[_]u32{ a, b }, &[_]u32{ o });
    g.nodes.items[node_id].device_hint = .apu;

    var reg = KernelRegistry{};
    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();

    var plan = try resolveDevicesWithOptions(testing.allocator, &g, &reg, &diags, .{ .has_apu = false });
    defer plan.deinit(testing.allocator);
    try testing.expect(plan.devices[0] == .npu);
    try testing.expect(diags.all().len >= 1);
}
