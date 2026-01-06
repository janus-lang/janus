// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub const Buffer = struct {
    bytes: std.ArrayList(u8),
    alloc: std.mem.Allocator,

    pub fn with(alloc: std.mem.Allocator) @This() {
        return .{ .bytes = .{}, .alloc = alloc };
    }

    pub fn write(self: *@This(), data: []const u8) !void {
        try self.bytes.appendSlice(self.alloc, data);
    }

    pub fn toOwned(self: *@This()) ![]u8 {
        return self.bytes.toOwnedSlice(self.alloc);
    }

    pub fn clear(self: *@This()) void {
        self.bytes.clearRetainingCapacity();
    }

    pub fn deinit(self: *@This()) void {
        self.bytes.deinit(self.alloc);
    }
};
