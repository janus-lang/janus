// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn List(comptime T: type) type {
    return struct {
        inner: std.ArrayList(T),
        alloc: std.mem.Allocator,

        pub fn with(alloc: std.mem.Allocator) @This() {
            return .{ .inner = .{}, .alloc = alloc };
        }

        pub fn append(self: *@This(), value: T) !void {
            try self.inner.append(self.alloc, value);
        }

        pub fn appendSlice(self: *@This(), values: []const T) !void {
            try self.inner.appendSlice(self.alloc, values);
        }

        pub fn writer(self: *@This()) @TypeOf(self.inner.writer(self.alloc)) {
            return self.inner.writer(self.alloc);
        }

        pub fn items(self: *const @This()) []const T {
            return self.inner.items;
        }

        pub fn toOwnedSlice(self: *@This()) ![]T {
            return self.inner.toOwnedSlice(self.alloc);
        }

        pub fn clearRetainingCapacity(self: *@This()) void {
            self.inner.clearRetainingCapacity();
        }

        pub fn orderedRemove(self: *@This(), index: usize) T {
            return self.inner.orderedRemove(index);
        }

        pub fn deinit(self: *@This()) void {
            self.inner.deinit(self.alloc);
        }
    };
}
