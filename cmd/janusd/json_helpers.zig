// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn writeMinified(writer: anytype, value: anytype) !void {
    const payload = try std.json.Stringify.valueAlloc(std.heap.page_allocator, value, .{ .whitespace = .minified });
    defer std.heap.page_allocator.free(payload);
    try writer.writeAll(payload);
}

/// Writer adapter for ArrayList(u8) — replaces buf.writer(allocator) removed in Zig 0.16.
/// Provides writeAll, print, and writeByte over an ArrayList(u8) + allocator pair.
pub const ArrayListWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn writeAll(self: ArrayListWriter, data: []const u8) !void {
        try self.list.appendSlice(self.allocator, data);
    }

    pub fn print(self: ArrayListWriter, comptime fmt: []const u8, args: anytype) !void {
        const formatted = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(formatted);
        try self.list.appendSlice(self.allocator, formatted);
    }

    pub fn writeByte(self: ArrayListWriter, byte: u8) !void {
        try self.list.append(self.allocator, byte);
    }
};

/// Construct an ArrayListWriter from an ArrayList(u8) pointer and allocator.
pub fn arrayListWriter(list: *std.ArrayList(u8), allocator: std.mem.Allocator) ArrayListWriter {
    return .{ .list = list, .allocator = allocator };
}
