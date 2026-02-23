// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSM MemTable: Skip List + Arena Allocator

const std = @import("std");
const Allocator = std.mem.Allocator;

const SkipList = @import("skip_list.zig").SkipList;
const KeyType = []const u8;
const ValueType = []const u8;

pub const MemTable = struct {
    const Self = @This();

    skiplist: SkipList(KeyType, ValueType),
    arena: std.heap.ArenaAllocator,
    size_bytes: usize = 0,
    max_size: usize,

    pub fn init(allocator: Allocator, max_size: usize) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        return .{
            .skiplist = SkipList(KeyType, ValueType).init(arena.allocator()),
            .arena = arena,
            .max_size = max_size,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn put(self: *Self, key: KeyType, value: ValueType) !void {
        const key_copy = try self.arena.allocator().dupe(u8, key);
        const value_copy = try self.arena.allocator().dupe(u8, value);
        try self.skiplist.insert(key_copy, value_copy);
        self.size_bytes += key.len + value.len;
    }

    pub fn get(self: Self, key: KeyType) ?ValueType {
        return self.skiplist.get(key);
    }

    pub fn shouldFlush(self: Self) bool {
        return self.size_bytes >= self.max_size;
    }
};

test "MemTable basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memtable = try MemTable.init(allocator, 1024);
    defer memtable.deinit();

    try memtable.put("key1", "value1");
    try memtable.put("key2", "value2");

    const val1 = memtable.get("key1");
    try std.testing.expectEqualStrings("value1", val1.?);

    const val2 = memtable.get("key2");
    try std.testing.expectEqualStrings("value2", val2.?);

    try std.testing.expect(memtable.shouldFlush() == false);
}
