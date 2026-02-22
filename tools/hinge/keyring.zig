// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const packer = @import("packer.zig");

pub fn defaultDir(allocator: std.mem.Allocator) ![]u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return try std.fs.path.join(allocator, &.{ home, ".hinge", "keyring" });
}

pub fn keyIdHex(allocator: std.mem.Allocator, pub_bytes: []const u8) ![]u8 {
    var h = std.crypto.hash.Blake3.init(.{});
    h.update(pub_bytes);
    var out: [32]u8 = undefined;
    h.final(&out);
    const hex = try packer.hexSlice(allocator, &out);
    // return first 16
    if (hex.len <= 16) return hex;
    const slice = try allocator.alloc(u8, 16);
    @memcpy(slice, hex[0..16]);
    allocator.free(hex);
    return slice;
}

pub fn isTrusted(allocator: std.mem.Allocator, pub_bytes: []const u8) !bool {
    const dir = try defaultDir(allocator);
    defer allocator.free(dir);
    const keyid = try keyIdHex(allocator, pub_bytes);
    defer allocator.free(keyid);
    const fname = try std.fmt.allocPrint(allocator, "{s}.pub", .{keyid});
    defer allocator.free(fname);
    const path = try std.fs.path.join(allocator, &.{ dir, fname });
    defer allocator.free(path);
    const fh = std.fs.cwd().openFile(path, .{}) catch return false;
    fh.close();
    return true;
}

pub fn addPublicKey(allocator: std.mem.Allocator, pub_path: []const u8) ![]u8 {
    const pub_bytes = try compat_fs.readFileAlloc(allocator, pub_path, 1 << 24);
    defer allocator.free(pub_bytes);
    const dir = try defaultDir(allocator);
    defer allocator.free(dir);
    try compat_fs.makeDir(dir);
    const keyid = try keyIdHex(allocator, pub_bytes);
    errdefer allocator.free(keyid);
    const fname = try std.fmt.allocPrint(allocator, "{s}.pub", .{keyid});
    defer allocator.free(fname);
    const path = try std.fs.path.join(allocator, &.{ dir, fname });
    defer allocator.free(path);
    // Write if absent
    const f = compat_fs.createFile(path, .{ .exclusive = true }) catch |e| switch (e) {
        error.PathAlreadyExists => {
            // already trusted, return keyid
            return keyid;
        },
        else => return e,
    };
    defer f.close();
    try f.writeAll(pub_bytes);
    return keyid;
}

pub fn listKeyIds(allocator: std.mem.Allocator) ![][]u8 {
    const dir = try defaultDir(allocator);
    defer allocator.free(dir);
    var out: std.ArrayList([]u8) = .empty;
    errdefer {
        for (out.items) |s| allocator.free(s);
        out.deinit(allocator);
    }
    var d = compat_fs.openDir(dir, .{ .iterate = true }) catch |e| switch (e) {
        error.FileNotFound => return try out.toOwnedSlice(allocator),
        else => return e,
    };
    defer d.close();
    var it = d.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".pub")) continue;
        const base = entry.name[0 .. entry.name.len - 4];
        const dup = try allocator.dupe(u8, base);
        try out.append(allocator, dup);
    }
    return try out.toOwnedSlice(allocator);
}

pub fn removeByKeyId(allocator: std.mem.Allocator, keyid: []const u8) !void {
    const dir = try defaultDir(allocator);
    defer allocator.free(dir);
    const fname = try std.fmt.allocPrint(allocator, "{s}.pub", .{keyid});
    defer allocator.free(fname);
    const path = try std.fs.path.join(allocator, &.{ dir, fname });
    defer allocator.free(path);
    try compat_fs.deleteFile(path);
}
