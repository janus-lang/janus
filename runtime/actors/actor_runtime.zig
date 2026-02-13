// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Actor Runtime (STUB) — :cluster profile
//!
//! Minimal actor runtime to unblock :cluster compilation.
//! Provides mailbox + basic spawn integration with nursery scheduler.
//! Real implementation will add supervision, remote dispatch, and grains.

const std = @import("std");
const Allocator = std.mem.Allocator;

const rt = @import("../janus_rt.zig");
const Channel = rt.Channel;

const nursery_mod = @import("../scheduler/nursery.zig");
const Nursery = nursery_mod.Nursery;

const task_mod = @import("../scheduler/task.zig");
const Task = task_mod.Task;
const TaskFn = task_mod.TaskFn;

/// Actor message type (placeholder)
/// Real implementation will support typed messages + envelopes.
pub const Message = i64;

/// Actor identifier
pub const ActorId = u64;

/// Actor handler signature
/// Return 0 to continue, non-zero to stop the loop.
pub const ActorHandler = *const fn (*Actor, Message) callconv(.c) i64;

/// Actor handle
pub const Actor = struct {
    const Self = @This();

    id: ActorId,
    mailbox: *Channel(Message),
    allocator: Allocator,
    handler: ?ActorHandler,

    pub fn init(allocator: Allocator, id: ActorId) !Self {
        const mailbox = try Channel(Message).init(allocator);
        return .{ .id = id, .mailbox = mailbox, .allocator = allocator, .handler = null };
    }

    pub fn deinit(self: *Self) void {
        self.mailbox.deinit();
    }

    pub fn setHandler(self: *Self, handler: ActorHandler) void {
        self.handler = handler;
    }

    pub fn send(self: *Self, msg: Message) !void {
        try self.mailbox.send(msg);
    }

    pub fn recv(self: *Self) !Message {
        return try self.mailbox.recv();
    }

    pub fn close(self: *Self) void {
        self.mailbox.close();
    }
};

/// Internal actor loop entry point
fn actorLoopEntry(arg: ?*anyopaque) callconv(.c) i64 {
    if (arg == null) return 1;
    const actor: *Actor = @ptrCast(@alignCast(arg.?));
    const handler = actor.handler orelse return 1;

    while (true) {
        const msg = actor.recv() catch |err| switch (err) {
            error.ChannelClosed => return 0,
            else => return 1,
        };

        const rc = handler(actor, msg);
        if (rc != 0) return rc;
    }
}

/// Spawn an actor task using the nursery scheduler.
/// Installs the handler and runs the actor loop.
pub fn spawn(nursery: *Nursery, actor: *Actor, handler: ActorHandler) ?*Task {
    actor.setHandler(handler);
    return nursery.spawn(actorLoopEntry, actor);
}

/// Convenience: spawn a no-arg actor task (handler captures actor via global/closure)
pub fn spawnNoArg(nursery: *Nursery, handler: task_mod.NoArgTaskFn) ?*Task {
    return nursery.spawnNoArg(handler);
}

// --- Runtime hooks for lowering (minimal) ---

/// Blocking receive hook used by lowering stubs.
pub fn actor_receive(actor: *Actor) Message {
    return actor.recv() catch 0;
}

/// Send hook used by lowering stubs.
pub fn actor_send(actor: *Actor, msg: Message) void {
    _ = actor.send(msg) catch {};
}

/// Spawn stub hook used by lowering (returns actor ptr as i64 handle for now)
pub fn actor_spawn_stub() i64 {
    return 0;
}

// NOTE: Supervision, grains, message envelopes, and distributed
// transport will be implemented in the full :cluster runtime.
