// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub const Region = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(parent: std.mem.Allocator) Region {
        return .{ .arena = std.heap.ArenaAllocator.init(parent) };
    }

    pub fn allocator(self: *Region) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *Region) void {
        self.arena.reset(.retain_capacity);
    }

    pub fn deinit(self: *Region) void {
        self.arena.deinit();
    }
};

pub fn withScratch(parent: std.mem.Allocator, body: fn (std.mem.Allocator) anyerror!void) !void {
    var region = Region.init(parent);
    defer region.deinit();
    try body(region.allocator());
}
