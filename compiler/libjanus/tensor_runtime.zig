// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Runtime — streams, events and scheduler (scaffolding)

const std = @import("std");
const jir = @import("tensor_jir.zig");
const diag = @import("tensor_diagnostics.zig");

const fabric = @import("tensor_fabric_probe.zig");

const log = std.log.scoped(.tensor_runtime);

pub const Allocator = std.mem.Allocator;
pub const Graph = jir.Graph;
pub const NodeId = jir.NodeId;
pub const EdgeId = jir.EdgeId;
pub const OpKind = jir.OpKind;
pub const MemSpace = jir.MemSpace;

pub const DeviceKind = enum { cpu, gpu, npu, apu };

const CapabilityFlags = struct {
    has_gpu: bool = false,
    has_npu: bool = false,
    has_apu: bool = false,

    fn has(self: CapabilityFlags, device: DeviceKind) bool {
        return switch (device) {
            .cpu => true,
            .gpu => self.has_gpu or self.has_apu,
            .npu => self.has_npu or self.has_apu,
            .apu => self.has_apu,
        };
    }
};

/// Public descriptor for advertised tensor capabilities.
/// Requirement: `.codex/specs/janus-npu-native/requirements.md` §2.4
pub const CapabilityDescriptor = struct {
    capability: []const u8,
    device: DeviceKind,
    default_residency: MemSpace,
    zero_copy: bool,
};

pub const StreamId = u32;
pub const EventId = u32;

pub const Stream = struct {
    id: StreamId,
    device: DeviceKind,
};

pub const Event = struct {
    id: EventId,
    signaled: bool = false,
};

pub const Runtime = struct {
    allocator: Allocator,
    streams: std.ArrayListUnmanaged(Stream),
    events: std.ArrayListUnmanaged(Event),
    diagnostics: ?*diag.TensorDiagnostics,
    capabilities: CapabilityFlags = .{},

    pub fn init(allocator: Allocator, diagnostics: ?*diag.TensorDiagnostics) Runtime {
        var runtime = Runtime{
            .allocator = allocator,
            .streams = .{},
            .events = .{},
            .diagnostics = diagnostics,
            .capabilities = .{},
        };
        runtime.refreshCapabilities() catch |err| {
            log.warn("device detection failed: {}", .{err});
        };
        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        self.streams.deinit(self.allocator);
        self.events.deinit(self.allocator);
    }

    pub fn hasCapability(self: *const Runtime, device: DeviceKind) bool {
        return self.capabilities.has(device);
    }

    /// Emit a manifest describing available tensor fabrics/capabilities.
    /// Consumers (e.g. UTCP manuals, daemon introspection) can use this to surface
    /// `CapApu` when unified fabrics are detected, satisfying janus-npu-native §2.4.
    pub fn capabilityManifest(self: *const Runtime, allocator: Allocator) ![]CapabilityDescriptor {
        var entries = std.ArrayListUnmanaged(CapabilityDescriptor){};
        errdefer entries.deinit(allocator);

        try entries.append(allocator, capabilityDescriptor(.cpu));
        if (self.capabilities.has_gpu) try entries.append(allocator, capabilityDescriptor(.gpu));
        if (self.capabilities.has_npu) try entries.append(allocator, capabilityDescriptor(.npu));
        if (self.capabilities.has_apu) try entries.append(allocator, capabilityDescriptor(.apu));

        return entries.toOwnedSlice(allocator);
    }

    fn refreshCapabilities(self: *Runtime) !void {
        const caps = try fabric.detectCaps(self.allocator);
        self.capabilities = .{
            .has_gpu = caps.has_gpu,
            .has_npu = caps.has_npu,
            .has_apu = caps.has_apu,
        };
    }

    pub fn createStream(self: *Runtime, device: DeviceKind) !StreamId {
        const id: StreamId = @intCast(self.streams.items.len);
        self.streams.append(self.allocator, .{ .id = id, .device = device }) catch |err| {
            if (self.diagnostics) |d| {
                _ = d.runtimeOutOfMemory("stream", deviceName(device)) catch {};
            }
            log.warn("failed to create stream for {s}: {}", .{ deviceName(device), err });
            return err;
        };
        return id;
    }

    pub fn createEvent(self: *Runtime) !EventId {
        const id: EventId = @intCast(self.events.items.len);
        self.events.append(self.allocator, .{ .id = id, .signaled = false }) catch |err| {
            if (self.diagnostics) |d| {
                _ = d.runtimeOutOfMemory("event", "runtime") catch {};
            }
            log.warn("failed to create event: {}", .{err});
            return err;
        };
        return id;
    }

    pub fn record(self: *Runtime, ev: EventId, stream: StreamId) void {
        _ = stream; // scaffolding: would associate with stream timeline
        self.events.items[ev].signaled = true;
    }

    pub fn waitEvent(self: *Runtime, ev: EventId) void {
        _ = self;
        _ = ev; // scaffolding: no-op; in real runtime this would block/sync
    }
};

pub const RuntimeError = error{CapabilityDenied};

pub fn deviceName(device: DeviceKind) []const u8 {
    return switch (device) {
        .cpu => "cpu",
        .gpu => "gpu",
        .npu => "npu",
        .apu => "apu",
    };
}

fn capabilityName(device: DeviceKind) []const u8 {
    return switch (device) {
        .cpu => "CapCpu",
        .gpu => "CapGpu",
        .npu => "CapNpu",
        .apu => "CapApu",
    };
}

fn capabilityDescriptor(device: DeviceKind) CapabilityDescriptor {
    return switch (device) {
        .cpu => .{
            .capability = capabilityName(.cpu),
            .device = .cpu,
            .default_residency = .host,
            .zero_copy = true,
        },
        .gpu => .{
            .capability = capabilityName(.gpu),
            .device = .gpu,
            .default_residency = .vram,
            .zero_copy = false,
        },
        .npu => .{
            .capability = capabilityName(.npu),
            .device = .npu,
            .default_residency = .sram,
            .zero_copy = false,
        },
        .apu => .{
            .capability = capabilityName(.apu),
            .device = .apu,
            .default_residency = .shared,
            .zero_copy = true,
        },
    };
}

pub fn requireCapability(
    runtime: *Runtime,
    has_capability: bool,
    capability: []const u8,
    context: []const u8,
) RuntimeError!void {
    if (has_capability) return;
    if (runtime.diagnostics) |d| {
        _ = d.runtimeCapabilityDenied(capability, context) catch {};
    }
    log.warn("capability '{s}' denied in context '{s}'", .{ capability, context });
    return error.CapabilityDenied;
}

pub fn reportDeviceFailure(
    runtime: *Runtime,
    node: jir.NodeId,
    device: DeviceKind,
    err: anyerror,
) void {
    const name = deviceName(device);
    if (runtime.diagnostics) |d| {
        _ = d.runtimeDeviceError(node, name, @errorName(err)) catch {};
    }
    log.warn("device {s} failure on node {d}: {}", .{ name, node, err });
}

pub const PlanEntry = struct {
    node: NodeId,
    stream: StreamId,
    waits: []EventId,
    signal: ?EventId,
    device: DeviceKind,
};

pub const ExecutionPlan = struct {
    entries: []PlanEntry,
    pub fn deinit(self: *ExecutionPlan, allocator: Allocator) void {
        for (self.entries) |e| allocator.free(e.waits);
        allocator.free(self.entries);
    }
};

pub const Scheduler = struct {
    allocator: Allocator,
    runtime: *Runtime,

    pub fn init(allocator: Allocator, runtime: *Runtime) Scheduler {
        return .{ .allocator = allocator, .runtime = runtime };
    }

    pub fn buildPlan(self: *Scheduler, g: *const Graph) !ExecutionPlan {
        const n = g.nodes.items.len;
        var devices = try self.allocator.alloc(DeviceKind, n);
        defer self.allocator.free(devices);

        for (g.nodes.items, 0..) |node, idx| {
            devices[idx] = self.defaultDeviceFor(node.kind);
        }

        return try self.buildPlanWithDevices(g, devices);
    }

    /// Build a plan using an externally resolved device per node
    pub fn buildPlanWithDevices(self: *Scheduler, g: *const Graph, devices: []const DeviceKind) !ExecutionPlan {
        const n = g.nodes.items.len;
        var indeg = try self.allocator.alloc(u32, n);
        defer self.allocator.free(indeg);
        @memset(indeg, 0);
        for (g.nodes.items, 0..) |node, i| {
            for (node.inputs) |eid| {
                if (g.edges.items[eid].producer) |_| {
                    indeg[i] += 1;
                }
            }
        }

        var queue = std.ArrayListUnmanaged(NodeId){};
        defer queue.deinit(self.allocator);
        for (indeg, 0..) |d, i| if (d == 0) try queue.append(self.allocator, @intCast(i));

        var node_event = try self.allocator.alloc(EventId, n);
        defer self.allocator.free(node_event);
        for (node_event, 0..) |_, i| node_event[i] = try self.runtime.createEvent();

        var stream_map = std.AutoHashMap(DeviceKind, StreamId).init(self.allocator);
        defer stream_map.deinit();

        var entries = std.ArrayListUnmanaged(PlanEntry){};
        defer entries.deinit(self.allocator);

        while (queue.items.len > 0) {
            const nid = queue.orderedRemove(0);
            const node = g.nodes.items[nid];
            const dev = devices[nid];
            const stream = try self.ensureStream(&stream_map, dev);

            var waits = std.ArrayListUnmanaged(EventId){};
            defer waits.deinit(self.allocator);
            for (node.inputs) |eid| {
                if (g.edges.items[eid].producer) |pid| {
                    const prod_dev = devices[pid];
                    if (prod_dev != dev) try waits.append(self.allocator, node_event[pid]);
                }
            }

            const signal = node_event[nid];
            const waits_owned = try waits.toOwnedSlice(self.allocator);
            try entries.append(self.allocator, .{ .node = nid, .stream = stream, .waits = waits_owned, .signal = signal, .device = dev });

            for (node.outputs) |eid| {
                for (g.edges.items[eid].consumers) |cid| {
                    if (indeg[cid] > 0) {
                        indeg[cid] -= 1;
                        if (indeg[cid] == 0) try queue.append(self.allocator, @intCast(cid));
                    }
                }
            }
        }

        return ExecutionPlan{ .entries = try entries.toOwnedSlice(self.allocator) };
    }

    fn ensureStream(self: *Scheduler, map: *std.AutoHashMap(DeviceKind, StreamId), device: DeviceKind) !StreamId {
        if (map.get(device)) |existing| return existing;
        if (device != .cpu) {
            try requireCapability(self.runtime, self.runtime.hasCapability(device), capabilityName(device), "create stream");
        }
        const stream = try self.runtime.createStream(device);
        try map.put(device, stream);
        return stream;
    }

    fn defaultDeviceFor(self: *Scheduler, kind: OpKind) DeviceKind {
        return switch (kind) {
            .Matmul, .Conv2D, .Relu, .Gelu, .Add, .Mul, .ReduceSum, .Transpose, .Reshape, .Concat, .Split, .BatchNorm => blk: {
                if (self.runtime.hasCapability(.apu)) break :blk .apu;
                if (self.runtime.hasCapability(.npu)) break :blk .npu;
                if (self.runtime.hasCapability(.gpu)) break :blk .gpu;
                break :blk .cpu;
            },
            .Transfer, .Copy, .Barrier, .Quantize, .Dequantize => .cpu,
        };
    }
};

// ------------------ Memory Residency Planning ------------------

pub const Buffer = struct { edge: EdgeId, mem: jir.MemSpace };

pub const MemoryActionKind = enum { Transfer };
pub const MemoryAction = struct {
    kind: MemoryActionKind,
    edge: EdgeId,
    src: jir.MemSpace,
    dst: jir.MemSpace,
};

pub const MemoryPlan = struct {
    actions: []MemoryAction,
    pub fn deinit(self: *MemoryPlan, allocator: Allocator) void {
        allocator.free(self.actions);
    }
};

/// Planner that determines additional transfers needed to satisfy device preferences,
/// avoiding moves when a matching Transfer node already provides residency, or when
/// memory is already accessible by the target device (zero-copy semantics where possible).
pub const MemoryPlanner = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) MemoryPlanner {
        return .{ .allocator = allocator };
    }

    pub fn plan(self: *MemoryPlanner, g: *const Graph, exec: *const ExecutionPlan) !MemoryPlan {
        var actions = std.ArrayListUnmanaged(MemoryAction){};
        defer actions.deinit(self.allocator);

        // Track discovered residency: start with declared tensor.mem when present
        const resid = try self.allocator.alloc(?jir.MemSpace, g.edges.items.len);
        defer self.allocator.free(resid);
        for (g.edges.items, 0..) |e, i| resid[i] = e.tensor.mem;

        // For each execution entry, ensure inputs are resident in preferred mem for the device
        for (exec.entries) |entry| {
            const dev = entry.device;
            const pref = preferredMem(dev);
            const node = g.nodes.items[entry.node];
            for (node.inputs) |eid| {
                const cur = resid[eid] orelse inferDefaultResidency(dev);
                if (isAccessible(dev, cur)) continue; // zero-copy path is acceptable

                // If the producing node is an explicit Transfer to the preferred mem, skip
                if (g.edges.items[eid].producer) |pid| {
                    const prod = g.nodes.items[pid];
                    if (prod.kind == .Transfer) {
                        const out_mem = g.edges.items[eid].tensor.mem;
                        if (out_mem != null and out_mem.? == pref) {
                            resid[eid] = out_mem; // already transferred
                            continue;
                        }
                    }
                }

                // Plan an explicit transfer action
                try actions.append(self.allocator, .{ .kind = .Transfer, .edge = eid, .src = cur, .dst = pref });
                resid[eid] = pref;
            }

            // Mark outputs as resident where their mem is declared, else in preferred mem
            for (node.outputs) |oeid| {
                const decl = g.edges.items[oeid].tensor.mem;
                resid[oeid] = decl orelse pref;
            }
        }

        return MemoryPlan{ .actions = try actions.toOwnedSlice(self.allocator) };
    }
};

fn preferredMem(dev: DeviceKind) jir.MemSpace {
    return switch (dev) {
        .cpu => .host,
        .gpu => .vram,
        .npu => .sram,
        .apu => .shared,
    };
}

fn inferDefaultResidency(dev: DeviceKind) jir.MemSpace {
    return preferredMem(dev);
}

fn isAccessible(dev: DeviceKind, mem: jir.MemSpace) bool {
    return switch (dev) {
        .cpu => (mem == .host or mem == .dram or mem == .shared),
        .gpu => (mem == .vram),
        .npu => (mem == .sram),
        .apu => (mem == .shared or mem == .host or mem == .dram),
    };
}

// ------------------ Tests ------------------
const testing = std.testing;
const builder = @import("tensor_builder.zig");

test "Scheduler: builds entries and inserts waits for cross-stream" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 2, 2 }, .dram);
    const w = try b.input(.f32, &[_]u32{ 2, 2 }, .dram);
    const m = try b.matmul(a, w, .dram); // NPU
    const t = try b.transfer(m, .sram); // CPU
    _ = t;
    const g = b.getGraph();

    var rt = Runtime.init(testing.allocator, null);
    defer rt.deinit();
    var sched = Scheduler.init(testing.allocator, &rt);
    var plan = try sched.buildPlan(g);
    defer plan.deinit(testing.allocator);

    try testing.expect(plan.entries.len == g.nodes.items.len);
    // The second entry (Transfer) should have at least one wait event
    var has_wait = false;
    for (plan.entries) |e| {
        if (e.waits.len > 0) {
            has_wait = true;
            break;
        }
    }
    try testing.expect(has_wait);
}

test "Scheduler.buildPlanWithDevices honors external device mapping" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 2, 2 }, .dram);
    const b2 = try b.input(.f32, &[_]u32{ 2, 2 }, .dram);
    const o = try b.matmul(a, b2, .dram);
    _ = o;
    const g = b.getGraph();

    var rt = Runtime.init(testing.allocator, null);
    defer rt.deinit();
    var sched = Scheduler.init(testing.allocator, &rt);

    // Force CPU for node 0
    var devs = try testing.allocator.alloc(DeviceKind, g.nodes.items.len);
    defer testing.allocator.free(devs);
    devs[0] = .cpu;
    var plan = try sched.buildPlanWithDevices(g, devs);
    defer plan.deinit(testing.allocator);

    try testing.expect(plan.entries.len >= 1);
    try testing.expect(plan.entries[0].device == .cpu);
}

test "MemoryPlanner: plans transfers when residency mismatches device pref" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 2, 2 }, .dram);
    const w = try b.input(.f32, &[_]u32{ 2, 2 }, .dram);
    const m = try b.matmul(a, w, .dram); // produced in DRAM
    _ = m;
    const g = b.getGraph();

    var rt = Runtime.init(testing.allocator, null);
    defer rt.deinit();
    var sched = Scheduler.init(testing.allocator, &rt);
    var plan = try sched.buildPlan(g);
    defer plan.deinit(testing.allocator);

    var mp = MemoryPlanner.init(testing.allocator);
    var mplan = try mp.plan(g, &plan);
    defer mplan.deinit(testing.allocator);

    // Expect at least one transfer into NPU preferred mem (SRAM) for inputs
    var has = false;
    for (mplan.actions) |act| {
        if (act.kind == .Transfer and act.dst == .sram) {
            has = true;
            break;
        }
    }
    try testing.expect(has);
}

test "Runtime surfaces out-of-memory diagnostics" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });

    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();

    var rt = Runtime.init(failing.allocator(), &diags);
    defer rt.deinit();

    const res = rt.createStream(.npu);
    try testing.expectError(error.OutOfMemory, res);
    try testing.expectEqual(@as(usize, 1), diags.all().len);
    try testing.expect(diags.all()[0].kind == .runtime_out_of_memory);
}

test "Runtime capability denial recorded" {
    var diags = diag.TensorDiagnostics.init(testing.allocator);
    defer diags.deinit();
    var rt = Runtime.init(testing.allocator, &diags);
    defer rt.deinit();

    const result = requireCapability(&rt, false, "npu.execute", "dispatch tensor graph");
    try testing.expectError(error.CapabilityDenied, result);
    try testing.expect(diags.all().len >= 1);
    try testing.expect(diags.all()[diags.all().len - 1].kind == .runtime_capability_denied);
}

test "Scheduler prefers apu when capability available" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 4, 4 }, .shared);
    const w = try b.input(.f32, &[_]u32{ 4, 4 }, .shared);
    _ = try b.matmul(a, w, .shared);

    var rt = Runtime.init(testing.allocator, null);
    defer rt.deinit();
    rt.capabilities.has_apu = true;
    rt.capabilities.has_gpu = true;
    rt.capabilities.has_npu = true;

    var sched = Scheduler.init(testing.allocator, &rt);
    var plan = try sched.buildPlan(b.getGraph());
    defer plan.deinit(testing.allocator);

    try testing.expect(plan.entries.len >= 1);
    try testing.expect(plan.entries[0].device == .apu);
}

test "MemoryPlanner avoids transfers for shared memory on apu" {
    var b = builder.Builder.init(testing.allocator);
    defer b.deinit();
    const a = try b.input(.f32, &[_]u32{ 2, 2 }, .shared);
    const w = try b.input(.f32, &[_]u32{ 2, 2 }, .shared);
    const m = try b.matmul(a, w, .shared);
    _ = m;

    var rt = Runtime.init(testing.allocator, null);
    defer rt.deinit();
    rt.capabilities.has_apu = true;
    rt.capabilities.has_gpu = true;
    rt.capabilities.has_npu = true;

    var sched = Scheduler.init(testing.allocator, &rt);
    var plan = try sched.buildPlan(b.getGraph());
    defer plan.deinit(testing.allocator);

    var mp = MemoryPlanner.init(testing.allocator);
    var mplan = try mp.plan(b.getGraph(), &plan);
    defer mplan.deinit(testing.allocator);

    try testing.expect(mplan.actions.len == 0);
}

test "capability manifest advertises CapApu shared residency" {
    var rt = Runtime.init(testing.allocator, null);
    defer rt.deinit();
    rt.capabilities.has_apu = true;
    rt.capabilities.has_gpu = true;
    rt.capabilities.has_npu = true;

    const manifest = try rt.capabilityManifest(testing.allocator);
    defer testing.allocator.free(manifest);

    var seen_apu = false;
    for (manifest) |entry| {
        if (entry.device == .apu) {
            seen_apu = true;
            try testing.expect(std.mem.eql(u8, entry.capability, "CapApu"));
            try testing.expect(entry.default_residency == .shared);
            try testing.expect(entry.zero_copy);
        }
    }
    try testing.expect(seen_apu);
}
