// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const builder = @import("../tensor_builder.zig");
const diag = @import("../tensor_diagnostics.zig");
const fusion = @import("../tensor_fusion.zig");
const quant = @import("../tensor_quant.zig");
const tile = @import("../tensor_tile.zig");
const onnx_backend = @import("../tensor_backend_onnx.zig");
const runtime = @import("../tensor_runtime.zig");
const device_dispatch = @import("../tensor_device_dispatch.zig");
const kernel_registry = @import("../tensor_kernel_registry.zig");
const graph_cid = @import("../tensor_cid.zig");
const debug = @import("../tensor_debug.zig");

test "tensor integration: pipeline end to end scheduling" {
    const allocator = testing.allocator;

    var diags = diag.TensorDiagnostics.init(allocator);
    defer diags.deinit();

    var b = builder.Builder.init(allocator);
    defer b.deinit();

    const input = try b.input(.f16, &[_]u32{ 512, 256 }, .dram);
    const weights = try b.input(.f16, &[_]u32{ 256, 512 }, .dram);
    const matmul = try b.matmul(input, weights, .dram);
    const relu = try b.relu(matmul);
    const staged = try b.transfer(relu, .sram);
    const bias = try b.input(.f16, &[_]u32{ 512, 512 }, .sram);
    const summed = try b.add(staged, bias);
    _ = summed;

    const graph = b.getGraph();
    try graph.verifyWithDiagnostics(&diags);
    try testing.expectEqual(@as(usize, 0), diags.all().len);

    var fusion_pass = fusion.FusionPass.init(allocator, .{});
    var fusion_plan = try fusion_pass.plan(graph);
    defer fusion_plan.deinit(allocator);
    try testing.expect(fusion_plan.groups.len >= 1);

    var quant_pass = quant.QuantizationPass.init(allocator, .{}, .{});
    var quant_plan = try quant_pass.plan(graph, null);
    defer quant_plan.deinit(allocator);
    try testing.expect(quant_plan.items.len >= 2);

    var tile_pass = tile.TilePass.init(allocator, .{ .capacity_bytes = 64 * 1024 });
    var tile_plan = try tile_pass.plan(graph);
    defer tile_plan.deinit(allocator);
    try testing.expect(tile_plan.items.len >= 1);

    const backend = onnx_backend.OnnxBackend.make();
    const artifact = try backend.emit(
        graph,
        .{ .fusion = &fusion_plan, .quant = &quant_plan, .tile = &tile_plan },
        allocator,
    );
    defer allocator.free(artifact);
    try testing.expect(std.mem.containsAtLeast(u8, artifact, 1, "\"nodes\""));

    var registry = kernel_registry.KernelRegistry{};
    var device_plan = try device_dispatch.resolveDevicesWithOptions(allocator, graph, &registry, null, .{ .has_apu = false });
    defer device_plan.deinit(allocator);
    try testing.expect(device_plan.devices.len == graph.nodes.items.len);

    var has_cpu = false;
    var has_npu = false;
    for (device_plan.devices) |dev| {
        switch (dev) {
            .cpu => has_cpu = true,
            .npu => has_npu = true,
            else => {},
        }
    }
    try testing.expect(has_cpu);
    try testing.expect(has_npu);

    var runtime_ctx = runtime.Runtime.init(allocator, null);
    defer runtime_ctx.deinit();

    var scheduler = runtime.Scheduler.init(allocator, &runtime_ctx);
    var exec_plan = try scheduler.buildPlanWithDevices(graph, device_plan.devices);
    defer exec_plan.deinit(allocator);
    try testing.expect(exec_plan.entries.len == graph.nodes.items.len);

    var cross_stream_wait = false;
    for (exec_plan.entries) |entry| {
        if (entry.waits.len > 0) {
            cross_stream_wait = true;
            break;
        }
    }
    try testing.expect(cross_stream_wait);

    const cid1 = try graph_cid.computeGraphCID(graph, allocator);
    const cid2 = try graph_cid.computeGraphCID(graph, allocator);
    try testing.expect(std.mem.eql(u8, &cid1, &cid2));

    const debug_run_1 = try debug.runCpu(graph, allocator);
    defer debug_run_1.deinit(allocator);
    const debug_run_2 = try debug.runCpu(graph, allocator);
    defer debug_run_2.deinit(allocator);
    const drifts = try debug.compare(&debug_run_1, &debug_run_2, graph, .{}, allocator);
    defer allocator.free(drifts);
    try testing.expect(drifts.len == 0);
}
