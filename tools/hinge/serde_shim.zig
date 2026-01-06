// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Minimal serde shim for Zig code integrating Janus serde intent.
// Bridges to std.json today; can be swapped for real SIMD serde later.

pub fn stringify(value: anytype, options: std.json.Stringify.Options, writer: anytype) !void {
    try std.json.Stringify.value(value, options, writer);
}

pub fn stringifyAlloc(allocator: std.mem.Allocator, value: anytype, options: std.json.Stringify.Options) ![]u8 {
    var buf = std.io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try std.json.Stringify.value(value, options, &buf.writer);
    return buf.toOwnedSlice();
}

pub fn deserializeFromJson(comptime T: type, reader: anytype, allocator: std.mem.Allocator) !T {
    // Read full JSON payload from reader, then parse into T.
    const chunk = try reader.readAllAlloc(allocator, 64 * 1024 * 1024);
    defer allocator.free(chunk);
    return try std.json.parseFromSlice(T, allocator, chunk, .{ .allocate = .alloc_always });
}
