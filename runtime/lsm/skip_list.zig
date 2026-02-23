// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSM Skip List — Lock-Free Sorted Set

const std = @import("std");

pub fn SkipList(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        const max_level: usize = 12;
        const Node = struct {
            key: K,
            value: V,
            forward: [max_level]?*Node = [_]?*Node{null} ** max_level,
        };

        head: *Node,
        level: usize = 0,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const head = try allocator.create(Node);
            head.* = .{};
            return .{ 
                .head = head, 
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var current = self.head;
            while (current) |node| {
                const next = node.forward[0];
                self.allocator.destroy(node);
                current = next;
            }
        }

        fn randomLevel(self: Self) usize {
            _ = self;
            var lvl: usize = 0;
            var rng = std.rand.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
            while (rng.random().boolean() and lvl < max_level - 1) : (lvl += 1) {}
            return lvl;
        }

        pub fn insert(self: *Self, key: K, value: V) !void {
            var update: [max_level]?*Node = undefined;
            var current = self.head;
            var i: usize = self.level;

            while (true) : (i -= 1) {
                while (current.forward[i]) |next| {
                    if (std.mem.order(u8, std.mem.sliceAsBytes(&next.key), std.mem.sliceAsBytes(&key)) == .lt) {
                        current = next;
                    } else break;
                }
                update[i] = current;
                if (i == 0) break;
            }

            const new_level = self.randomLevel();
            if (new_level > self.level) {
                for (self.level + 1..new_level + 1) |j| {
                    update[j] = self.head;
                }
                self.level = new_level;
            }

            const node = try self.allocator.create(Node);
            node.* = .{ .key = key, .value = value };
            for (0..new_level + 1) |j| {
                if (update[j]) |upd| {
                    node.forward[j] = upd.forward[j];
                    upd.forward[j] = node;
                }
            }
        }

        pub fn get(self: Self, key: K) ?V {
            var current = self.head;
            var i: usize = self.level;
            while (true) : (i -= 1) {
                while (current.forward[i]) |next| {
                    const ord = std.mem.order(u8, std.mem.sliceAsBytes(&next.key), std.mem.sliceAsBytes(&key));
                    if (ord == .lt) {
                        current = next;
                    } else if (ord == .eq) {
                        return next.value;
                    } else break;
                }
                if (i == 0) break;
            }
            return null;
        }
    };
}

test "SkipList" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var skip = try SkipList([]const u8, []const u8).init(allocator);
    defer skip.deinit();

    try skip.insert("key1", "value1");
    try skip.insert("key2", "value2");

    const val1 = skip.get("key1");
    try std.testing.expectEqualStrings("value1", val1.?);
}
