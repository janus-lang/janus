// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Minimal test to isolate the granite interner issue
// This will help identify what's causing the memory leaks

// Simple ID type without external dependencies
const StrId = enum(u32) { _ };

pub const MinimalStrInterner = struct {
    parent_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    strings: [][]const u8,
    string_count: u32,
    capacity: u32,

    pub fn init(allocator: std.mem.Allocator, capacity: u32) !MinimalStrInterner {
        const strings = try allocator.alloc([]const u8, capacity);
        const arena = std.heap.ArenaAllocator.init(allocator);

        return MinimalStrInterner{
            .parent_allocator = allocator,
            .arena = arena,
            .strings = strings,
            .string_count = 0,
            .capacity = capacity,
        };
    }

    pub fn deinit(self: *MinimalStrInterner) void {
        self.arena.deinit();
        self.parent_allocator.free(self.strings);
        self.* = undefined;
    }

    pub fn get(self: *MinimalStrInterner, s: []const u8) !StrId {
        // Check if already interned
        for (0..self.string_count) |i| {
            if (std.mem.eql(u8, self.strings[i], s)) {
                return @enumFromInt(@as(u32, @intCast(i)));
            }
        }

        // Check capacity
        if (self.string_count >= self.capacity) {
            return error.StringInternerCapacityExceeded;
        }

        // Arena duplicates the string content
        const arena_allocator = self.arena.allocator();
        const interned_string = try arena_allocator.dupe(u8, s);

        // Simple array assignment
        self.strings[self.string_count] = interned_string;
        const id: StrId = @enumFromInt(self.string_count);
        self.string_count += 1;

        return id;
    }

    pub fn str(self: *const MinimalStrInterner, id: StrId) []const u8 {
        const raw_id = @intFromEnum(id);
        if (raw_id >= self.string_count) {
            return "";
        }
        return self.strings[raw_id];
    }

    pub fn count(self: *const MinimalStrInterner) u32 {
        return self.string_count;
    }
};

test "Minimal Granite Interner - Basic Test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var interner = try MinimalStrInterner.init(allocator, 10);
        defer interner.deinit();

        const hello_id = try interner.get("hello");
        const world_id = try interner.get("world");
        const hello_id2 = try interner.get("hello");

        try std.testing.expectEqual(hello_id, hello_id2);
        try std.testing.expect(!std.meta.eql(hello_id, world_id));
        try std.testing.expectEqualStrings("hello", interner.str(hello_id));
        try std.testing.expectEqualStrings("world", interner.str(world_id));
        try std.testing.expectEqual(@as(u32, 2), interner.count());
    }

    const leaked = gpa.deinit();
    try std.testing.expect(leaked == .ok);
}
