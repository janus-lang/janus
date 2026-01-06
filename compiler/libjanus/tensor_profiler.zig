// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Profiler — timing (synthetic), fusion summary, stream occupancy

const std = @import("std");
const jir = @import("tensor_jir.zig");
const rt = @import("tensor_runtime.zig");
const fusion = @import("tensor_fusion.zig");
const tile = @import("tensor_tile.zig");
const registry_mod = @import("tensor_kernel_registry.zig");

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;
pub const ExecutionPlan = rt.ExecutionPlan;
pub const MemoryPlan = rt.MemoryPlan;
pub const FusionPlan = fusion.FusionPlan;
pub const TilePlan = tile.TilePlan;
pub const DeviceKind = rt.DeviceKind;
pub const KernelRegistry = registry_mod.KernelRegistry;

pub const NodeTiming = struct { node: jir.NodeId, stream: rt.StreamId, duration_ns: u64 };
pub const TransferTiming = struct { edge: jir.EdgeId, src: jir.MemSpace, dst: jir.MemSpace, duration_ns: u64 };

pub const StreamStat = struct { stream: rt.StreamId, busy_ns: u64, occupancy: f64 };

pub const ProfileReport = struct {
    node_timings: []NodeTiming,
    transfer_timings: []TransferTiming,
    streams: []StreamStat,
    fusion_groups: usize,
    tile_items: usize,

    pub fn deinit(self: *ProfileReport, allocator: Allocator) void {
        allocator.free(self.node_timings);
        allocator.free(self.transfer_timings);
        allocator.free(self.streams);
    }
};

pub const Profiler = struct {
    allocator: Allocator,
    registry: KernelRegistry,

    pub fn init(allocator: Allocator) Profiler { return .{ .allocator = allocator, .registry = .{} }; }

    /// Produce a synthetic profile report using a simple cost model and tensor sizes.
    pub fn profile(self: *Profiler, g: *const Graph, exec: *const ExecutionPlan, mem: ?*const MemoryPlan, f: ?*const FusionPlan, t: ?*const TilePlan) !ProfileReport {
        var node_timings = std.ArrayListUnmanaged(NodeTiming){};
        defer node_timings.deinit(self.allocator);
        var transfer_timings = std.ArrayListUnmanaged(TransferTiming){};
        defer transfer_timings.deinit(self.allocator);

        // Synthetic durations
        for (exec.entries) |e| {
            const kind = g.nodes.items[e.node].kind;
            const dev = e.device;
            const base_cost = self.registry.estimateCost(kind, dev);
            // Scale by approximate tensor size of first output (ns units)
            const out_edge = if (g.nodes.items[e.node].outputs.len > 0) g.nodes.items[e.node].outputs[0] else 0;
            const bytes = tensorBytes(g.edges.items[out_edge].tensor);
            const duration_ns: u64 = @as(u64, base_cost) * (bytes / 1024 + 1) * 100; // 100ns per KiB * cost
            try node_timings.append(self.allocator, .{ .node = e.node, .stream = e.stream, .duration_ns = duration_ns });
        }

        if (mem) |m| {
            for (m.actions) |act| {
                const bytes = tensorBytes(g.edges.items[act.edge].tensor);
                // Assume transfer cost ~ 500ns per KiB
                const dur: u64 = (bytes / 1024 + 1) * 500;
                try transfer_timings.append(self.allocator, .{ .edge = act.edge, .src = act.src, .dst = act.dst, .duration_ns = dur });
            }
        }

        // Compute stream occupancy: busy_ns per stream / total busy_ns
        var busy = std.AutoHashMap(rt.StreamId, u64).init(self.allocator);
        defer busy.deinit();
        var total_busy: u64 = 0;
        for (node_timings.items) |nt| {
            total_busy += nt.duration_ns;
            const cur = busy.get(nt.stream) orelse 0;
            try busy.put(nt.stream, cur + nt.duration_ns);
        }
        var streams_list = std.ArrayListUnmanaged(StreamStat){};
        defer streams_list.deinit(self.allocator);
        var it = busy.iterator();
        while (it.next()) |entry| {
            const occ = if (total_busy == 0) 0.0 else @as(f64, @floatFromInt(entry.value_ptr.*)) / @as(f64, @floatFromInt(total_busy));
            try streams_list.append(self.allocator, .{ .stream = entry.key_ptr.*, .busy_ns = entry.value_ptr.*, .occupancy = occ });
        }

        return ProfileReport{
            .node_timings = try node_timings.toOwnedSlice(self.allocator),
            .transfer_timings = try transfer_timings.toOwnedSlice(self.allocator),
            .streams = try streams_list.toOwnedSlice(self.allocator),
            .fusion_groups = if (f) |fp| fp.groups.len else 0,
            .tile_items = if (t) |tp| tp.items.len else 0,
        };
    }
};

fn tensorBytes(t: jir.Tensor) u64 {
    return @as(u64, tensorLen(t)) * @as(u64, bytesPerDType(t.dtype));
}

fn tensorLen(t: jir.Tensor) usize { var total: usize = 1; for (t.shape.dims) |d| total *= d; return total; }

fn bytesPerDType(dt: jir.DType) u32 {
    return switch (dt) { .i8 => 1, .i16 => 2, .i32 => 4, .f16 => 2, .bf16 => 2, .f32 => 4, .f64 => 8, .bool => 1 };
}

// ------------------ Tests ------------------
const testing = std.testing;
const builder = @import("tensor_builder.zig");
const fusionpass = @import("tensor_fusion.zig");

test "Profiler: produces stream occupancy and counts plans" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 128, 64 }, null);
    const w = try b.input(.f32, &[_]u32{ 64, 256 }, null);
    const m = try b.matmul(a, w, null);
    const r = try b.relu(m);
    _ = r;
    const g = b.getGraph();

    var rt_state = rt.Runtime.init(testing.allocator, null);
    defer rt_state.deinit();
    var sched = rt.Scheduler.init(testing.allocator, &rt_state);
    var exec = try sched.buildPlan(g);
    defer exec.deinit(testing.allocator);

    var fpass = fusionpass.FusionPass.init(testing.allocator, .{});
    var fplan = try fpass.plan(g);
    defer fplan.deinit(testing.allocator);

    var prof = Profiler.init(testing.allocator);
    var report = try prof.profile(g, &exec, null, &fplan, null);
    defer report.deinit(testing.allocator);

    try testing.expect(report.node_timings.len == g.nodes.items.len);
    try testing.expect(report.fusion_groups >= 0);
    var occ_sum: f64 = 0.0;
    for (report.streams) |st| occ_sum += st.occupancy;
    try testing.expect(occ_sum > 0.0);
}
