// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const packer = @import("packer.zig");

pub const Entry = struct {
    op: []const u8,
    package_name: []const u8,
    version: []const u8,
    package_path: []const u8,
    hash_b3: []const u8,
    sigs_valid: ?u32 = null,
    sigs_total: ?u32 = null,
    timestamp: i64,
    prev_hash: []const u8,
    entry_hash: []const u8,
};

pub fn defaultPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    const dir = try std.fs.path.join(allocator, &.{ home, ".hinge" });
    defer allocator.free(dir);
    const path = try std.fs.path.join(allocator, &.{ home, ".hinge", "ledger.jsonl" });
    return path; // caller frees
}

pub fn append(op: []const u8, pkg_name: []const u8, version: []const u8, pkg_path: []const u8, hash_hex: []const u8, sigs_valid: ?u32, sigs_total: ?u32, allocator: std.mem.Allocator) !void {
    const path = try defaultPath(allocator);
    defer allocator.free(path);
    // Ensure directory exists
    if (std.fs.path.dirname(path)) |dirp| {
        try std.fs.cwd().makePath(dirp);
    }

    var prev_hash_hex: []u8 = &[_]u8{};
    // Read last line if exists to get prev entry hash
    if (std.fs.cwd().openFile(path, .{})) |file| {
        defer file.close();
        const content = try file.readToEndAlloc(allocator, 1024 * 1024 * 16);
        defer allocator.free(content);
        var it = std.mem.splitScalar(u8, content, '\n');
        var last: []const u8 = &[_]u8{};
        while (it.next()) |line| {
            if (line.len > 0) last = line;
        }
        if (last.len > 0) {
            const key = "\"entry_hash\":\"";
            if (std.mem.indexOf(u8, last, key)) |pos| {
                const start = pos + key.len;
                if (std.mem.indexOfScalarPos(u8, last, start, '"')) |endq| {
                    const val = last[start..endq];
                    prev_hash_hex = try allocator.dupe(u8, val);
                    defer allocator.free(prev_hash_hex);
                }
            }
        }
    } else |_| {}

    // Build canonical buffer for hashing
    var data = std.io.Writer.Allocating.init(allocator);
    defer data.deinit();
    try data.writer.print("{s}|{s}|{s}|{s}|{s}|{?d}|{?d}|{d}|{s}", .{ op, pkg_name, version, pkg_path, hash_hex, sigs_valid, sigs_total, std.time.timestamp(), prev_hash_hex });

    var h = std.crypto.hash.Blake3.init(.{});
    h.update(data.written());
    var out: [32]u8 = undefined;
    h.final(&out);
    const entry_hash_hex = try packer.hexSlice(allocator, &out);
    defer allocator.free(entry_hash_hex);

    // Serialize entry JSON
    var obj = std.json.ObjectMap.init(allocator);
    defer obj.deinit();
    try obj.put("op", .{ .string = op });
    try obj.put("package_name", .{ .string = pkg_name });
    try obj.put("version", .{ .string = version });
    try obj.put("package_path", .{ .string = pkg_path });
    try obj.put("hash_b3", .{ .string = hash_hex });
    if (sigs_valid) |v| try obj.put("sigs_valid", .{ .integer = @intCast(v) });
    if (sigs_total) |v| try obj.put("sigs_total", .{ .integer = @intCast(v) });
    try obj.put("timestamp", .{ .integer = @intCast(std.time.timestamp()) });
    try obj.put("prev_hash", .{ .string = prev_hash_hex });
    try obj.put("entry_hash", .{ .string = entry_hash_hex });

    var buf = std.io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    const root = std.json.Value{ .object = obj };
    try std.json.Stringify.value(root, .{ .whitespace = .minified }, &buf.writer);

    // Append line
    var file = std.fs.cwd().createFile(path, .{ .truncate = false, .read = true }) catch |e| switch (e) {
        error.PathAlreadyExists => try std.fs.cwd().openFile(path, .{ .mode = .read_write }),
        else => return e,
    };
    defer file.close();
    try file.seekFromEnd(0);
    try file.writeAll(buf.written());
    try file.writeAll("\n");
}
