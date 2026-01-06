// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn Map(comptime K: type, comptime V: type) type {
    return struct {
        inner: std.AutoHashMap(K, V),

        pub fn with(alloc: std.mem.Allocator) @This() {
            return .{ .inner = std.AutoHashMap(K, V).init(alloc) };
        }

        pub fn get(self: *@This(), key: K) ?*V {
            return self.inner.getPtr(key);
        }

        pub fn put(self: *@This(), key: K, value: V) !void {
            try self.inner.put(key, value);
        }

        pub fn remove(self: *@This(), key: K) bool {
            return self.inner.remove(key);
        }

        pub fn deinit(self: *@This()) void {
            self.inner.deinit();
        }
    };
}
