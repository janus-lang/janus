const std = @import("std");
const actors = @import("../../actors/grain_runtime.zig");

test "LSM Phase 4 — Grain Integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var nursery = Nursery.init(allocator);
    defer nursery.deinit();

    var grain = try actors.Grain.init(allocator, &nursery, "testgrain");
    defer grain.deinit();

    const initial = .{ .balance = 100 };
    try grain.persistState(initial);

    // Restart simulation
    grain.deinit();
    grain = try actors.Grain.init(allocator, &nursery, "testgrain");

    const recovered = try grain.loadState(@TypeOf(initial));
    try std.testing.expectEqual(initial.balance, recovered.balance);
}
