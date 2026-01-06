// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub const LogEntry = struct {
    term: u64,
    op: []const u8, // serialized UTCP op (register, heartbeat, etc.)
};

pub const RegistryNode = struct {
    allocator: std.mem.Allocator,
    id: usize,
    term: u64 = 0,
    log: std.ArrayList(LogEntry),

    pub fn init(alloc: std.mem.Allocator, id: usize) !RegistryNode {
        return .{
            .allocator = alloc,
            .id = id,
            .term = 0,
            .log = std.ArrayList(LogEntry){},
        };
    }

    pub fn deinit(self: *RegistryNode) void {
        // Free duplicated op buffers
        for (self.log.items) |le| self.allocator.free(le.op);
        self.log.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn append(self: *RegistryNode, term: u64, op: []const u8) !void {
        const dup = try self.allocator.dupe(u8, op);
        try self.log.append(self.allocator, .{ .term = term, .op = dup });
    }
};

/// Minimal in-memory quorum replication. Returns true if majority ack.
pub fn syncCluster(
    leader: *RegistryNode,
    followers: []*RegistryNode,
    op: []const u8,
) !bool {
    // Leader appends
    leader.term += 1;
    try leader.append(leader.term, op);

    var quorum: usize = 1; // leader always counts
    for (followers) |f| {
        try f.append(leader.term, op);
        quorum += 1;
    }

    return quorum >= (followers.len + 1) / 2 + 1;
}

/// Adapter hook to plug replication into registry without coupling.
pub const Replicator = struct {
    ctx: *anyopaque,
    call: *const fn (ctx: *anyopaque, op: []const u8) anyerror!bool,
};
