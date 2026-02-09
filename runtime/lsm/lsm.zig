// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! GrainStore (LSM) Facade — minimal stdlib KV store

const std = @import("std");
const Allocator = std.mem.Allocator;
const MemTable = @import("memtable.zig").MemTable;
const WAL = @import("wal.zig").WAL;

pub const GrainStore = struct {
    const Self = @This();

    allocator: Allocator,
    memtable: MemTable,
    wal: WAL,
    ttl_default_ms: ?u64,
    wal_batch_ms: u64,

    pub const Options = struct {
        ttl_default_ms: ?u64 = null,
        wal_batch_ms: u64 = 0,
        memtable_max: usize = 1 * 1024 * 1024,
    };

    pub fn open(allocator: Allocator, path: []const u8, opts: Options) !Self {
        var memtable = try MemTable.init(allocator, opts.memtable_max);
        var wal = try WAL.init(allocator, path);
        return .{ 
            .allocator = allocator,
            .memtable = memtable,
            .wal = wal,
            .ttl_default_ms = opts.ttl_default_ms,
            .wal_batch_ms = opts.wal_batch_ms,
        };
    }

    pub fn close(self: *Self) void {
        self.memtable.deinit();
        self.wal.deinit();
    }

    pub fn put(self: *Self, key: []const u8, value: []const u8, ttl_ms: ?u64) !void {
        const now = std.time.milliTimestamp();
        const ttl = ttl_ms orelse self.ttl_default_ms;
        const expiry = if (ttl) |t| now + @as(i64, @intCast(t)) else 0;

        // Encode: [expiry (i64)][value]
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        try buf.writer().writeIntLittle(i64, expiry);
        try buf.writer().writeAll(value);

        try self.wal.append(key, buf.items, self.wal_batch_ms);
        try self.memtable.put(key, buf.items);
    }

    pub fn get(self: *Self, key: []const u8) ?[]const u8 {
        if (self.memtable.get(key)) |raw| {
            if (raw.len < 8) return null;
            const expiry = std.mem.readIntLittle(i64, raw[0..8]);
            if (expiry != 0 and expiry < std.time.milliTimestamp()) return null;
            return raw[8..];
        }
        return null;
    }

    pub fn sync(self: *Self) !void {
        try self.wal.flush();
    }
};
