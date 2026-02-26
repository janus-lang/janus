// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Actor runtime stub test (Channel-based)

const std = @import("std");
const actors = @import("../../runtime/actors/actor_runtime.zig");
const nursery_mod = @import("../../runtime/scheduler/nursery.zig");
const budget_mod = @import("../../runtime/scheduler/budget.zig");

const Nursery = nursery_mod.Nursery;
const Budget = budget_mod.Budget;

fn handler(actor: *actors.Actor, msg: actors.Message) callconv(.c) i64 {
    // Echo back by negating; stop on msg == 0
    if (msg == 0) return 1;
    _ = actor.send(-msg) catch return 2;
    return 0;
}

test "actor runtime: send/recv loop" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var nursery = Nursery.init(allocator, 1, Budget.clusterDefault(), null);
    defer nursery.deinit();

    var actor = try actors.Actor.init(allocator, 1);
    defer actor.deinit();

    const task = actors.spawn(&nursery, &actor, handler) orelse return error.TestExpectedNonNull;
    _ = task; // ensure spawn succeeded

    try actor.send(41);
    const reply = try actor.recv();
    try std.testing.expectEqual(@as(actors.Message, -41), reply);

    // stop loop
    try actor.send(0);
    actor.close();
}
