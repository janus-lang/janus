// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSM Grain Runtime: Persistent Actors

const std = @import("std");
const Allocator = std.mem.Allocator;
const lsm = @import("../lsm/lsm.zig");
const Nursery = @import("../../scheduler/nursery.zig").Nursery;

pub const Grain = struct {
    const Self = @This();

    id: []const u8,
    db: lsm.LSMDB,
    nursery: *Nursery,
    allocator: Allocator,

    pub fn init(allocator: Allocator, nursery: *Nursery, id: []const u8) !Self {
        const db_path = try std.fmt.allocPrint(allocator, "grain_{s}.db", .{id});
        errdefer allocator.free(db_path);

        const db = try lsm.LSMDB.open(allocator, db_path);
        return .{ 
            .id = try allocator.dupe(u8, id),
            .db = db,
            .nursery = nursery,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.db.close();
        self.allocator.free(self.id);
    }

    pub fn loadState(self: *Self, comptime T: type) !T {
        const state_bytes = self.db.get("state") orelse return T{};
        return std.json.parseFromSlice(T, self.allocator, state_bytes, .{});
    }

    pub fn persistState(self: *Self, state: anytype) !void {
        const state_bytes = try std.json.stringifyAlloc(self.allocator, state, .{});
        defer self.allocator.free(state_bytes);
        try self.db.put("state", state_bytes);
        try self.db.sync();
    }

    pub fn spawnGrain(comptime GrainType: type, nursery: *Nursery, allocator: Allocator, id: []const u8) !GrainType {
        var grain = try GrainType.init(allocator, nursery, id);
        errdefer grain.deinit();

        // Spawn grain message loop
        const grain_pid = try nursery.spawn(grain.messageLoop());
        return grain;
    }
};

test "Grain persistence" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var nursery = Nursery.init(allocator);
    defer nursery.deinit();

    var grain = try Grain.init(allocator, &nursery, "testgrain");
    defer grain.deinit();

    const initial_state = .{ .balance = 100 };
    try grain.persistState(initial_state);

    // Simulate restart
    grain.deinit();
    grain = try Grain.init(allocator, &nursery, "testgrain");

    const recovered = try grain.loadState(@TypeOf(initial_state));
    try std.testing.expectEqual(initial_state.balance, recovered.balance);
}
