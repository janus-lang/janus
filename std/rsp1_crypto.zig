// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

/// Maximum number of simultaneous keys (active + previous + staged).
pub const MAX_KEYS = 3;

/// Secret epoch key
pub const EpochKey = struct {
    key: [32]u8,
    id: u64, // monotonic epoch id
};

/// Multi-secret verifier for lease signatures
pub const LeaseVerifier = struct {
    keys: [MAX_KEYS]?EpochKey = .{ null, null, null },
    active_idx: usize = 0,

    pub fn init(active: EpochKey) LeaseVerifier {
        var v = LeaseVerifier{};
        v.keys[0] = active;
        return v;
    }

    /// Demote active to previous, install new as active
    pub fn rotate(self: *LeaseVerifier, new_key: EpochKey) void {
        self.keys[1] = self.keys[self.active_idx];
        self.keys[0] = new_key;
        self.active_idx = 0;
    }

    /// Sign a lease state using active key
    /// RSP-1: MAC over (group, name, ttl_ns, heartbeat_counter)
    pub fn sign(
        self: *LeaseVerifier,
        group: []const u8,
        name: []const u8,
        ttl_ns: i128,
        heartbeat_counter: u64,
        out: *[32]u8,
    ) void {
        const key = self.keys[self.active_idx].?;
        // Concatenate inputs into a fixed buffer then compute keyed BLAKE3
        var buf: [1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        var list = std.ArrayListUnmanaged(u8){};
        const allocator = fba.allocator();
        _ = list.appendSlice(allocator, group) catch {};
        _ = list.appendSlice(allocator, name) catch {};
        _ = list.appendSlice(allocator, std.mem.asBytes(&ttl_ns)) catch {};
        _ = list.appendSlice(allocator, std.mem.asBytes(&heartbeat_counter)) catch {};
        std.crypto.hash.Blake3.hash(list.items, out, .{ .key = key.key });
    }

    /// Verify a lease signature against any known epoch key
    pub fn verify(
        self: *const LeaseVerifier,
        group: []const u8,
        name: []const u8,
        ttl_ns: i128,
        heartbeat_counter: u64,
        sig: []const u8,
    ) bool {
        for (self.keys) |maybe_key| {
            if (maybe_key) |key| {
                var buf: [1024]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&buf);
                var list = std.ArrayListUnmanaged(u8){};
                const allocator = fba.allocator();
                _ = list.appendSlice(allocator, group) catch {};
                _ = list.appendSlice(allocator, name) catch {};
                _ = list.appendSlice(allocator, std.mem.asBytes(&ttl_ns)) catch {};
                _ = list.appendSlice(allocator, std.mem.asBytes(&heartbeat_counter)) catch {};
                var expected: [32]u8 = undefined;
                std.crypto.hash.Blake3.hash(list.items, &expected, .{ .key = key.key });
                if (std.mem.eql(u8, &expected, sig)) return true;
            }
        }
        return false;
    }
};
