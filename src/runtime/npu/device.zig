// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus NPU-Native Runtime — device.zig
//!
//! Provides unified detection and capability descriptors for GPU/NPU/APU fabrics.
//! Integrates with Janus's capability system and allocator sovereignty principles.
//!
//! Doctrine Compliance:
//! - Capability Security: All devices advertise explicit capabilities
//! - Allocator Sovereignty: Memory spaces are explicit and traceable
//! - No Ambient Authority: Device access requires explicit capability grants

const std = @import("std");
const builtin = @import("builtin");
const ascii = std.ascii;

/// Hardware capability descriptor - aligns with Janus capability system
pub const Cap = enum {
    Cpu,
    Gpu,
    Npu,
    Apu, // unified CPU+GPU+NPU fabric (shared memory)
};

/// Options influencing device detection - allows explicit overrides for tests and tooling
pub const DetectionOptions = struct {
    /// Force advertising an APU device (used for tests and manual overrides)
    simulate_apu: bool = false,
    /// Override for the ROCm/HSA topology root (e.g., a temp directory in tests)
    sysfs_root_override: ?[]const u8 = null,
    /// Hint for Level Zero unified fabrics (allows deterministic simulation)
    level_zero_hint: ?[]const u8 = null,
};

const apu_capabilities = [_]Cap{ .Cpu, .Gpu, .Npu, .Apu };

/// Memory spaces for heterogeneous computing - explicit and traceable
pub const MemorySpace = enum {
    Host, // system memory
    Vram, // discrete GPU memory
    Sram, // discrete NPU memory
    Shared, // unified fabric (zero-copy UMA)
};

/// Represents a discovered compute device with Janus capability model
pub const Device = struct {
    id: u32,
    name: []const u8,
    kind: Cap,
    memory: MemorySpace,
    capabilities: []const Cap,

    /// Check if device supports a specific capability
    pub fn hasCapability(self: Device, cap: Cap) bool {
        for (self.capabilities) |c| {
            if (c == cap) return true;
        }
        return false;
    }
};

/// Detects available compute devices across CPU, GPU, NPU, and unified fabrics.
/// The returned slice always contains the host CPU; helper selection routines
/// (e.g. `getAutoDevice`) enforce priority (APU > GPU > NPU > CPU).
pub fn detectDevices(allocator: std.mem.Allocator) ![]Device {
    const simulate = std.process.hasEnvVar(allocator, "JANUS_FAKE_APU") catch false;
    const sysfs_override = try getEnvVarOwnedOptional(allocator, "JANUS_APU_SYSFS_ROOT");
    defer if (sysfs_override) |buf| allocator.free(buf);
    const level0_hint = try getEnvVarOwnedOptional(allocator, "JANUS_APU_LEVEL0_HINT");
    defer if (level0_hint) |buf| allocator.free(buf);

    const options = DetectionOptions{
        .simulate_apu = simulate,
        .sysfs_root_override = if (sysfs_override) |buf| @as([]const u8, buf) else null,
        .level_zero_hint = if (level0_hint) |buf| @as([]const u8, buf) else null,
    };

    return detectDevicesWithOptions(allocator, options);
}

/// Detect devices using explicit detection options (primarily for tests/tooling).
pub fn detectDevicesWithOptions(
    allocator: std.mem.Allocator,
    options: DetectionOptions,
) ![]Device {
    var list = std.ArrayList(Device){};
    errdefer list.deinit(allocator);

    // CPU baseline - always available
    try list.append(allocator, Device{
        .id = 0,
        .name = "Host CPU",
        .kind = .Cpu,
        .memory = .Host,
        .capabilities = &[_]Cap{.Cpu},
    });

    // Unified fabric detection (APU/AGPU) - highest priority
    if (try detectUnifiedFabric(allocator, options)) |apu_device| {
        try list.append(allocator, apu_device);
    }

    // Discrete GPU detection
    if (try detectDiscreteGpu(allocator)) |gpu_device| {
        try list.append(allocator, gpu_device);
    }

    // Discrete NPU detection
    if (try detectDiscreteNpu(allocator)) |npu_device| {
        try list.append(allocator, npu_device);
    }

    return try list.toOwnedSlice(allocator);
}

/// Returns the "best" compute device using Janus auto-selection logic
pub fn getAutoDevice(devices: []const Device) ?Device {
    // Priority: APU > GPU > NPU > CPU
    for (devices) |dev| {
        if (dev.kind == .Apu) return dev;
    }
    for (devices) |dev| {
        if (dev.kind == .Gpu) return dev;
    }
    for (devices) |dev| {
        if (dev.kind == .Npu) return dev;
    }
    return if (devices.len > 0) devices[0] else null;
}

/// Get appropriate allocator for memory space - respects allocator sovereignty
pub fn getAllocatorFor(space: MemorySpace) *std.mem.Allocator {
    return switch (space) {
        .Host, .Shared => &std.heap.page_allocator,
        .Vram, .Sram => &std.heap.c_allocator, // TODO: Replace with GPU/NPU allocators
    };
}

// -----------------------------------------------------------------------------
// Device Detection Implementations
// -----------------------------------------------------------------------------

fn detectUnifiedFabric(
    allocator: std.mem.Allocator,
    options: DetectionOptions,
) !?Device {
    if (options.simulate_apu) {
        return Device{
            .id = 3,
            .name = "Simulated APU (Unified Fabric)",
            .kind = .Apu,
            .memory = .Shared,
            .capabilities = &apu_capabilities,
        };
    }

    if (try detectRocmUnified(allocator, options.sysfs_root_override)) {
        return Device{
            .id = 1001,
            .name = "ROCm Unified Fabric",
            .kind = .Apu,
            .memory = .Shared,
            .capabilities = &apu_capabilities,
        };
    }

    if (try detectLevelZeroUnified(allocator, options.level_zero_hint)) {
        return Device{
            .id = 1100,
            .name = "Level Zero Unified Fabric",
            .kind = .Apu,
            .memory = .Shared,
            .capabilities = &apu_capabilities,
        };
    }

    return null;
}

fn detectDiscreteGpu(allocator: std.mem.Allocator) !?Device {
    // TODO: Implement real GPU detection:
    // - Vulkan physical device enumeration
    // - CUDA device count
    // - ROCm GPU agent discovery
    // - DirectX adapter enumeration

    _ = allocator; // Suppress unused parameter warning
    return null;
}

fn detectDiscreteNpu(allocator: std.mem.Allocator) !?Device {
    // TODO: Implement real NPU detection:
    // - PCIe enumeration for discrete NPUs
    // - Vendor-specific driver APIs
    // - USB enumeration for external accelerators

    _ = allocator; // Suppress unused parameter warning
    return null;
}

const PlatformType = enum {
    apu,
    discrete,
    unknown,
};

fn detectRocmUnified(
    allocator: std.mem.Allocator,
    sysfs_root_override: ?[]const u8,
) !bool {
    const root = sysfs_root_override orelse "/sys/class/kfd/kfd/topology";

    if (sysfs_root_override == null) {
        if (builtin.os.tag != .linux) return false;
        if (!fileExists("/dev/kfd")) return false;
    }

    const platform = try parseRocmPlatformType(allocator, root) orelse return false;
    return platform == .apu;
}

fn detectLevelZeroUnified(
    allocator: std.mem.Allocator,
    hint: ?[]const u8,
) !bool {
    if (hint) |value| {
        return value.len != 0;
    }

    const os_tag = builtin.os.tag;
    if (os_tag != .linux and os_tag != .windows) return false;

    const lib_names: []const []const u8 = if (os_tag == .windows)
        &[_][]const u8{"ze_loader.dll"}
    else
        &[_][]const u8{ "libze_loader.so", "libze_loader.so.1" };

    var lib_detected = false;
    for (lib_names) |lib_name| {
        if (try loadDynamicLibrary(lib_name)) {
            lib_detected = true;
            break;
        }
    }
    if (!lib_detected) return false;

    var score: u8 = 2; // base score for loader presence

    if (try envContains(allocator, "ONEAPI_DEVICE_FILTER", "gpu")) score += 1;
    if (try envContains(allocator, "SYCL_DEVICE_FILTER", "gpu")) score += 1;

    if (os_tag == .linux) {
        if (try readIntFromFile(allocator, "/sys/class/drm/card0/device/numa_node")) |numa| {
            if (numa == 0 or numa == -1) {
                score += 2;
            }
        }
    }

    return score >= 3;
}

fn parseRocmPlatformType(
    allocator: std.mem.Allocator,
    sysfs_root: []const u8,
) !?PlatformType {
    const path = try std.fs.path.join(allocator, &[_][]const u8{ sysfs_root, "system_properties" });
    defer allocator.free(path);

    const content = readFileAlloc(allocator, path, 16 * 1024) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return null,
        else => return err,
    };
    defer allocator.free(content);

    const needle = "platform_type";
    const idx = std.mem.indexOf(u8, content, needle) orelse return null;
    const line_end = std.mem.indexOfScalarPos(u8, content, idx, '\n') orelse content.len;
    const line = content[idx..line_end];

    if (std.mem.indexOf(u8, line, "APU") != null or std.mem.indexOf(u8, line, "apu") != null) {
        return .apu;
    }
    if (std.mem.indexOf(u8, line, "dGPU") != null or std.mem.indexOf(u8, line, "DGPU") != null or
        std.mem.indexOf(u8, line, "DISCRETE") != null)
    {
        return .discrete;
    }

    if (parseFirstDecimal(line)) |value| {
        return switch (value) {
            1 => .apu,
            2 => .discrete,
            else => .unknown,
        };
    }

    return null;
}

fn parseFirstDecimal(source: []const u8) ?u32 {
    var i: usize = 0;
    while (i < source.len and !ascii.isDigit(source[i])) : (i += 1) {}
    if (i == source.len) return null;
    var j = i;
    while (j < source.len and ascii.isDigit(source[j])) : (j += 1) {}
    return std.fmt.parseUnsigned(u32, source[i..j], 10) catch null;
}

fn envContains(
    allocator: std.mem.Allocator,
    name: []const u8,
    needle: []const u8,
) !bool {
    const value = try getEnvVarOwnedOptional(allocator, name) orelse return false;
    defer allocator.free(value);
    return std.mem.indexOf(u8, value, needle) != null;
}

fn loadDynamicLibrary(name: []const u8) !bool {
    const lib = std.DynLib.open(name) catch return false;
    defer lib.close();
    return true;
}

fn readIntFromFile(
    allocator: std.mem.Allocator,
    path: []const u8,
) !?i32 {
    const data = readFileAlloc(allocator, path, 128) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return null,
        else => return err,
    };
    defer allocator.free(data);

    if (data.len == 0) return null;

    var i: usize = 0;
    while (i < data.len and data[i] != '-' and !ascii.isDigit(data[i])) : (i += 1) {}
    if (i == data.len) return null;

    var j = i + 1;
    while (j < data.len and ascii.isDigit(data[j])) : (j += 1) {}

    return std.fmt.parseInt(i32, data[i..j], 10) catch null;
}

fn readFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) ![]u8 {
    const file = try openFile(path);
    defer file.close();
    return file.readToEndAlloc(allocator, max_bytes);
}

fn openFile(path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openFileAbsolute(path, .{});
    }
    return std.fs.cwd().openFile(path, .{});
}

fn fileExists(path: []const u8) bool {
    const file = openFile(path) catch return false;
    defer file.close();
    return true;
}

fn getEnvVarOwnedOptional(
    allocator: std.mem.Allocator,
    name: []const u8,
) !?[]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "device detection smoke test" {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const devices = try detectDevices(allocator);
    defer allocator.free(devices);

    // Should always have at least CPU
    try std.testing.expect(devices.len >= 1);
    try std.testing.expect(devices[0].kind == .Cpu);

    for (devices) |dev| {
        try std.testing.expect(dev.capabilities.len > 0);
        try std.testing.expect(dev.hasCapability(dev.kind));
    }

    if (getAutoDevice(devices)) |auto_dev| {
        // Auto device should be highest priority available
        try std.testing.expect(auto_dev.kind != .Cpu or devices.len == 1);
    }
}

test "detectDevicesWithOptions includes simulated unified fabric" {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const devices = try detectDevicesWithOptions(allocator, .{ .simulate_apu = true });
    defer allocator.free(devices);

    var has_apu = false;
    for (devices) |dev| {
        if (dev.kind == .Apu) {
            has_apu = true;
            try std.testing.expect(dev.memory == .Shared);
        }
    }
    try std.testing.expect(has_apu);

    const auto_dev = getAutoDevice(devices).?;
    try std.testing.expect(auto_dev.kind == .Apu);
}

test "ROCm sysfs override yields unified fabric" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile("system_properties", "platform_type: 1 (APU)\n");

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const maybe_device = try detectUnifiedFabric(std.testing.allocator, .{
        .sysfs_root_override = @as([]const u8, root),
    });
    try std.testing.expect(maybe_device != null);
    const dev = maybe_device.?;
    try std.testing.expect(dev.kind == .Apu);
    try std.testing.expect(dev.memory == .Shared);
}

test "ROCm sysfs discrete does not advertise unified fabric" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile("system_properties", "platform_type: 2 (dGPU)\n");

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const maybe_device = try detectUnifiedFabric(std.testing.allocator, .{
        .sysfs_root_override = @as([]const u8, root),
    });
    try std.testing.expect(maybe_device == null);
}

test "Level Zero hint advertises unified fabric" {
    const maybe_device = try detectUnifiedFabric(std.testing.allocator, .{
        .level_zero_hint = "simulate-level-zero",
    });
    try std.testing.expect(maybe_device != null);
    try std.testing.expect(maybe_device.?.kind == .Apu);
}

test "memory space allocator mapping" {
    // Test that each memory space maps to a valid allocator
    const spaces = [_]MemorySpace{ .Host, .Vram, .Sram, .Shared };

    for (spaces) |space| {
        const allocator = getAllocatorFor(space);
        try std.testing.expect(allocator != null);
        try std.testing.expect(allocator.?.vtable != null);
    }
}
