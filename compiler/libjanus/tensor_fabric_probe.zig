// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Fabric Probe — lightweight detection for unified fabrics (APU/AGPU)

const std = @import("std");
const builtin = @import("builtin");
const ascii = std.ascii;

pub const FabricCaps = struct {
    has_gpu: bool = true,
    has_npu: bool = true,
    has_apu: bool = false,
};

pub fn detectCaps(allocator: std.mem.Allocator) !FabricCaps {
    var caps = FabricCaps{};

    // Environment override for deterministic tests and tooling
    if (std.process.hasEnvVar(allocator, "JANUS_DISABLE_ACCEL") catch false) {
        caps.has_gpu = false;
        caps.has_npu = false;
        caps.has_apu = false;
        return caps;
    }

    if (try detectUnifiedFabric(allocator)) {
        caps.has_apu = true;
        caps.has_gpu = true;
        caps.has_npu = true;
    }

    return caps;
}

pub fn detectUnifiedFabricAvailable(allocator: std.mem.Allocator) bool {
    return detectUnifiedFabric(allocator) catch false;
}

fn detectUnifiedFabric(allocator: std.mem.Allocator) !bool {
    const simulate = std.process.hasEnvVar(allocator, "JANUS_FAKE_APU") catch false;
    if (simulate) return true;

    const sysfs_override = try getEnvVarOwnedOptional(allocator, "JANUS_APU_SYSFS_ROOT");
    defer if (sysfs_override) |buf| allocator.free(buf);
    const level0_hint = try getEnvVarOwnedOptional(allocator, "JANUS_APU_LEVEL0_HINT");
    defer if (level0_hint) |buf| allocator.free(buf);

    if (try detectRocmUnified(allocator, if (sysfs_override) |buf| @as([]const u8, buf) else null)) return true;
    if (try detectLevelZeroUnified(allocator, if (level0_hint) |buf| @as([]const u8, buf) else null)) return true;

    return false;
}

fn detectRocmUnified(allocator: std.mem.Allocator, sysfs_root_override: ?[]const u8) !bool {
    const root = sysfs_root_override orelse "/sys/class/kfd/kfd/topology";

    if (sysfs_root_override == null) {
        if (builtin.os.tag != .linux) return false;
        if (!fileExists("/dev/kfd")) return false;
    }

    const platform = try parseRocmPlatformType(allocator, root) orelse return false;
    return platform == .apu;
}

fn detectLevelZeroUnified(allocator: std.mem.Allocator, hint: ?[]const u8) !bool {
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

const PlatformType = enum { apu, discrete, unknown };

fn parseRocmPlatformType(allocator: std.mem.Allocator, sysfs_root: []const u8) !?PlatformType {
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

fn envContains(allocator: std.mem.Allocator, name: []const u8, needle: []const u8) !bool {
    const value = try getEnvVarOwnedOptional(allocator, name) orelse return false;
    defer allocator.free(value);
    return std.mem.indexOf(u8, value, needle) != null;
}

fn loadDynamicLibrary(name: []const u8) !bool {
    var lib = std.DynLib.open(name) catch return false;
    defer lib.close();
    return true;
}

fn readIntFromFile(allocator: std.mem.Allocator, path: []const u8) !?i32 {
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

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
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

fn getEnvVarOwnedOptional(allocator: std.mem.Allocator, name: []const u8) !?[]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
}
