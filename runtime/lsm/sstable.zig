// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSM SSTable: Immutable Sorted Key-Value File

const std = @import("std");
const Allocator = std.mem.Allocator;
const BloomFilter = @import("bloom.zig").BloomFilter;

const MAGIC: u64 = 0x4C534D5353544142; // "LSMSSTAB"

pub const SSTable = struct {
    const Self = @This();

    file: std.fs.File,
    index: []IndexEntry,
    bloom: BloomFilter,
    footer: Footer,

    pub const IndexEntry = struct {
        key_prefix: []const u8,
        offset: u64,
        size: u32,
    };

    pub const Footer = packed struct {
        magic: u64,
        index_offset: u64,
        bloom_offset: u64,
        bloom_size: u64,
    };

    pub fn open(allocator: Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        const stat = try file.stat();

        if (stat.size < @sizeOf(Footer)) return error.InvalidSSTable;

        var reader = file.reader();
        try reader.context.stream_position = stat.size - @sizeOf(Footer);
        const footer = try reader.readStruct(Footer);

        if (footer.magic != MAGIC) return error.InvalidMagic;

        const index_slice = try allocator.alloc(u8, @intCast(footer.index_offset - footer.bloom_offset + footer.bloom_size));
        errdefer allocator.free(index_slice);

        try reader.context.stream_position = footer.bloom_offset;
        _ = try reader.readAll(index_slice);

        const bloom = try BloomFilter.fromBytes(allocator, index_slice[0..footer.bloom_size]);
        const index_bytes = index_slice[@intCast(footer.bloom_size)..];
        const index = try parseIndex(allocator, index_bytes);

        return .{
            .file = file,
            .index = index,
            .bloom = bloom,
            .footer = footer,
        };
    }

    pub fn get(self: Self, key: []const u8) !?[]const u8 {
        if (!self.bloom.mightContain(key)) return null;

        const index_entry = for (self.index) |entry| {
            if (std.mem.startsWith(u8, key, entry.key_prefix)) {
                break entry;
            }
        } else return null;

        var reader = self.file.reader();
        try reader.context.stream_position = index_entry.offset;
        const block_header = try reader.readStruct(BlockHeader);
        const block_data = try allocator.alloc(u8, @intCast(block_header.size));
        errdefer allocator.free(block_data);

        _ = try reader.readAll(block_data);
        return scanBlock(block_data, key);
    }
};

fn parseIndex(allocator: Allocator, bytes: []const u8) ![]IndexEntry {
    // Parse sparse index from bytes
    var list: std.ArrayList(IndexEntry) = .empty;
    errdefer list.deinit();

    var reader = std.io.fixedBufferStream(bytes).reader();
    while (reader.context.pos < bytes.len) {
        const entry_size = try reader.readIntLittle(u32);
        const key_prefix_len = try reader.readIntLittle(u32);
        const key_prefix = try allocator.alloc(u8, key_prefix_len);
        _ = try reader.readAll(key_prefix);
        const offset = try reader.readIntLittle(u64);
        const size = try reader.readIntLittle(u32);

        try list.append(.{
            .key_prefix = key_prefix,
            .offset = offset,
            .size = size,
        });
    }

    return try list.toOwnedSlice();
}

test "SSTable open and get" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Write test SSTable
    var test_file = try std.fs.cwd().createFile("test.sstable", .{});
    defer test_file.delete();

    // ... write test data

    var sstable = try SSTable.open(allocator, "test.sstable");
    defer sstable.deinit();

    const val = try sstable.get("testkey");
    try std.testing.expectEqualStrings("testvalue", val.?);
}
