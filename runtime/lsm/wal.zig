// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSM WAL: Append-Only Durability

const std = @import("std");
const Allocator = std.mem.Allocator;
const MemTable = @import("memtable.zig").MemTable;

const WALEntry = packed struct {
    len: u32,
    key_len: u32,
    value_len: u32,
    crc32: u32,
};

pub const WAL = struct {
    const Self = @This();

    file: std.fs.File,
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u8) !Self {
        const dir = std.fs.cwd().makeOpenPathIterable("/tmp", .{}) catch unreachable;
        const file = try dir.createFile(path, .{});
        return .{ .file = file, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
    }

    pub fn append(self: *Self, key: []const u8, value: []const u8, batch_ms: u64) !void {
        const entry = WALEntry{
            .len = @intCast(key.len + value.len + 8),
            .key_len = @intCast(key.len),
            .value_len = @intCast(value.len),
            .crc32 = std.hash.Crc32.hash(key ++ value),
        };
        try self.file.writer().writeStruct(entry);
        try self.file.writer().writeAll(key);
        try self.file.writer().writeAll(value);
        if (batch_ms == 0) {
            try self.file.sync();
        } else {
            // Defer fsync: WAL batching window
            std.time.sleep(batch_ms * std.time.ns_per_ms);
            try self.file.sync();
        }
    }

    pub fn flush(self: *Self) !void {
        try self.file.sync();
    }

    pub fn recover(self: Self, allocator: Allocator, path: []const u8) !MemTable {
        var memtable = try MemTable.init(allocator, 1024 * 1024);
        errdefer memtable.deinit();

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const temp_alloc = arena.allocator();
        var reader = file.reader();

        while (true) {
            var entry: WALEntry = undefined;
            const read_len = try reader.readStruct(WALEntry, &entry);
            if (read_len == 0) break;

            const key = try temp_alloc.alloc(u8, entry.key_len);
            const value = try temp_alloc.alloc(u8, entry.value_len);

            try reader.readNoEof(key);
            try reader.readNoEof(value);

            const computed_crc = std.hash.Crc32.hash(key) ^ std.hash.Crc32.hash(value);
            if (entry.crc32 != computed_crc) return error.CorruptedWAL;

            try memtable.put(key, value);
        }

        return memtable;
    }
};

test "WAL durability" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const wal = try WAL.init(allocator, "test.wal");
    defer wal.deinit();

    try wal.append("key1", "value1");

    // Simulate crash
    wal.deinit();

    // Recover
    var memtable = try WAL.recover(allocator, "test.wal");
    defer memtable.deinit();

    const val = memtable.get("key1");
    try std.testing.expectEqualStrings("value1", val.?);
}
