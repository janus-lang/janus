// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus NPU-native Unit Tests - Comprehensive coverage for tensor operations

const std = @import("std");
const testing = std.testing;
const jir = @import("../tensor_jir.zig");
const fusion = @import("../tensor_fusion.zig");
const quant = @import("../tensor_quant.zig");
const tile = @import("../tensor_tile.zig");
const runtime = @import("../tensor_runtime.zig");
const builder = @import("../tensor_builder.zig");
const diag = @import("../tensor_diagnostics.zig");

// TensorType and shape algebra unit tests
test "TensorType creation and canonicalization" {
    const allocator = testing.allocator;
    var system = try @import("../semantic/type_system.zig").TypeSystem.init(allocator);
    defer system.deinit();

    const f32_type = system.getPrimitiveType(.f32);
    const dims = [_]u32{ 128, 256 };

    // Create identical tensor types - should canonicalize to same ID
    const t1 = try system.createTensorType(f32, &dims, .sram);
    const t2 = try system.createTensorType(f32, &dims, .sram);
    try testing.expect(t1.id == t2.id);

    // Different memspace should create different type
    const t3 = try system.createTensorType(f32, &dims, .dram);
    try testing.expect(t1.id != t3.id);

    // Different shape should create different type
    const dims2 = [_]u32{ 256, 256 };
    const t4 = try system.createTensorType(f32, &dims2, .sram);
    try testing.expect(t1.id != t4.id);
}

test "Shape algebra: broadcasting rules" {
    const allocator = testing.allocator;
    var system = try @import("../semantic/type_system.zig").TypeSystem.init(allocator);
    defer system.deinit();

    // Test broadcast compatibility
    const s1 = [_]u32{ 8, 1, 32 };
    const s2 = [_]u32{ 1, 16, 32 };
    const s3 = [_]u32{ 8, 16, 32 };

    try testing.expect(system.isBroadcastable(&s1, &s2));
    try testing.expect(!system.isBroadcastable(&s3, &s1));

    // Test broadcast shape computation
    const result = try system.computeBroadcastShape(&s1, &s2, allocator);
    defer allocator.free(result);
    try testing.expect(result.len == 3);
    try testing.expect(result[0] == 8 and result[1] == 16 and result[2] == 32);
}

test "Shape algebra: divisibility checks" {
    const allocator = testing.allocator;
    var system = try @import("../semantic/type_system.zig").TypeSystem.init(allocator);
    defer system.deinit();

    const shape = [_]u32{ 8, 16, 32 };
    const tile1 = [_]u32{ 2, 4, 8 };
    const tile2 = [_]u32{ 3, 4, 8 };

    try testing.expect(system.isShapeDivisibleBy(&shape, &tile1));
    try testing.expect(!system.isShapeDivisibleBy(&shape, &tile2));
}

// J-IR graph construction and verification unit tests
test "J-IR: basic graph construction" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    const c = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);

    _ = try g.addNode(.Add, &[_]jir.EdgeId{ a, b }, &[_]jir.EdgeId{ c });

    try g.verify();
}

test "J-IR: matmul verification" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = &[_]u32{ 128, 64 } }, .mem = .sram }, null);
    const b = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = &[_]u32{ 64, 256 } }, .mem = .sram }, null);
    const c = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = &[_]u32{ 128, 256 } }, .mem = .sram }, null);

    _ = try g.addNode(.Matmul, &[_]jir.EdgeId{ a, b }, &[_]jir.EdgeId{ c });

    try g.verify();
}

test "J-IR: memspace mismatch detection" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .sram }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    const c = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .sram }, null);

    _ = try g.addNode(.Add, &[_]jir.EdgeId{ a, b }, &[_]jir.EdgeId{ c });

    try testing.expectError(error.MemspaceMismatch, g.verify());
}

// Optimization passes unit tests
test "FusionPass: matmul-relu fusion" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const input = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 8, 8 } }, .mem = .dram }, null);
    const weights = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 8, 8 } }, .mem = .dram }, null);
    const matmul_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 8, 8 } }, .mem = .dram }, null);
    const relu_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 8, 8 } }, .mem = .dram }, null);

    _ = try g.addNode(.Matmul, &[_]jir.EdgeId{ input, weights }, &[_]jir.EdgeId{ matmul_out });
    _ = try g.addNode(.Relu, &[_]jir.EdgeId{ matmul_out }, &[_]jir.EdgeId{ relu_out });

    var pass = fusion.FusionPass.init(testing.allocator, .{ .matmul_relu = true, .conv_bn_relu = false });
    var plan = try pass.plan(&g);
    defer plan.deinit(testing.allocator);

    try testing.expect(plan.groups.len >= 1);
}

test "QuantizationPass: insert Q/DQ nodes" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const input = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = null }, null);
    const matmul_out = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = null }, null);

    _ = try g.addNode(.Matmul, &[_]jir.EdgeId{ input }, &[_]jir.EdgeId{ matmul_out });

    var pass = quant.QuantizationPass.init(testing.allocator, .{}, .{ .matmul = true });
    var plan = try pass.plan(&g, null);
    defer plan.deinit(testing.allocator);

    try testing.expect(plan.items.len >= 2); // Q and DQ nodes
}

test "TilePass: memory-aware tiling" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = &[_]u32{ 512, 512 } }, .mem = .dram }, null);
    const b = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = &[_]u32{ 512, 512 } }, .mem = .dram }, null);
    const c = try g.addEdge(.{ .dtype = .f16, .shape = .{ .dims = &[_]u32{ 512, 512 } }, .mem = .dram }, null);

    _ = try g.addNode(.Matmul, &[_]jir.EdgeId{ a, b }, &[_]jir.EdgeId{ c });

    var pass = tile.TilePass.init(testing.allocator, .{ .capacity_bytes = 64 * 1024 });
    var plan = try pass.plan(&g);
    defer plan.deinit(testing.allocator);

    try testing.expect(plan.items.len >= 1);
}

// Runtime streams and events unit tests
test "Runtime: stream and event management" {
    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();

    var rt = runtime.Runtime.init(testing.allocator, &diags);
    defer rt.deinit();

    const stream_id = try rt.createStream(.npu);
    try testing.expect(stream_id == 0);

    const event_id = try rt.createEvent();
    try testing.expect(event_id == 0);

    rt.record(event_id, stream_id);
    try testing.expect(rt.events.items[event_id].signaled == true);
}

test "Runtime: cross-stream dependencies" {
    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();

    var rt = runtime.Runtime.init(testing.allocator, &diags);
    defer rt.deinit();

    const npu_stream = try rt.createStream(.npu);
    const cpu_stream = try rt.createStream(.cpu);
    const event1 = try rt.createEvent();
    const event2 = try rt.createEvent();

    // Simulate cross-stream dependency
    rt.record(event1, npu_stream);
    rt.record(event2, cpu_stream);

    try testing.expect(rt.events.items[event1].signaled == true);
    try testing.expect(rt.events.items[event2].signaled == true);
}

// Backend emission unit tests
test "ONNX backend: basic graph emission" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 2, 3 } }, .mem = .dram }, null);
    const b = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 3, 4 } }, .mem = .dram }, null);
    const c = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 2, 4 } }, .mem = .dram }, null);

    _ = try g.addNode(.Matmul, &[_]jir.EdgeId{ a, b }, &[_]jir.EdgeId{ c });

    const backend = @import("../tensor_backend_onnx.zig").OnnxBackend.make();
    const artifact = try backend.emit(&g, .{}, testing.allocator);
    defer testing.allocator.free(artifact);

    try testing.expect(std.mem.containsAtLeast(u8, artifact, 1, "ir_version"));
    try testing.expect(std.mem.containsAtLeast(u8, artifact, 1, "producer"));
}

test "Device dispatch: kernel resolution" {
    var g = jir.Graph.init(testing.allocator);
    defer g.deinit();

    const input = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    const output = try g.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);

    _ = try g.addNode(.Relu, &[_]jir.EdgeId{ input }, &[_]jir.EdgeId{ output });

    const device_dispatch = @import("../tensor_device_dispatch.zig");
    var registry = device_dispatch.KernelRegistry{};
    const plan = try device_dispatch.resolveDevicesWithOptions(testing.allocator, &g, &registry, null, .{ .has_apu = false });
    defer plan.deinit(testing.allocator);

    try testing.expect(plan.devices.len == g.nodes.items.len);
}

// Content addressing and determinism tests
test "Graph CID: deterministic computation" {
    var g1 = jir.Graph.init(testing.allocator);
    defer g1.deinit();
    var g2 = jir.Graph.init(testing.allocator);
    defer g2.deinit();

    // Create identical graphs
    const a1 = try g1.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    const b1 = try g1.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    const c1 = try g1.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    _ = try g1.addNode(.Add, &[_]jir.EdgeId{ a1, b1 }, &[_]jir.EdgeId{ c1 });

    const a2 = try g2.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    const b2 = try g2.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    const c2 = try g2.addEdge(.{ .dtype = .f32, .shape = .{ .dims = &[_]u32{ 4, 4 } }, .mem = .dram }, null);
    _ = try g2.addNode(.Add, &[_]jir.EdgeId{ a2, b2 }, &[_]jir.EdgeId{ c2 });

    const cid = @import("../tensor_cid.zig");
    const id1 = try cid.computeGraphCID(&g1, testing.allocator);
    defer testing.allocator.free(id1);
    const id2 = try cid.computeGraphCID(&g2, testing.allocator);
    defer testing.allocator.free(id2);

    try testing.expect(std.mem.eql(u8, &id1, &id2));
}

// Profile gating unit tests
test "Profile gating: NPU features require :npu" {
    const pm = @import("../semantic/profile_manager.zig");

    // Test that NPU features are properly gated
    var manager = try pm.ProfileManager.init(testing.allocator, .min);
    defer manager.deinit();

    // Tensor features should be rejected in :min profile
    const test_span = pm.SourceSpan{ .start = 0, .end = 10 };
    const npu_ok = try manager.validateNpuFeature("tensor", test_span);
    try testing.expect(!npu_ok);

    // Switch to NPU profile
    try manager.setProfile(.npu);
    const npu_ok_after = try manager.validateNpuFeature("tensor", test_span);
    try testing.expect(npu_ok_after);
}
