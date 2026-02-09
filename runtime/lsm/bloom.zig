// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSM Bloom Filter: Probabilistic Set Membership

const std = @import("std");

pub const BloomFilter = struct {
    const Self = @This();

    bits: []u8,
    num_hashes: comptime_int = 7,
    bits_per_key: f64 = 10.0,

    pub fn init(allocator: std.mem.Allocator, expected_items: usize, bits_per_key: f64) !Self {
        const bits_needed = @as(usize, @intFromFloat(@as(f64, @floatFromInt(expected_items)) * bits_per_key));
        const bytes_needed = (bits_needed + 7) / 8;
        const bits = try allocator.alloc(u8, bytes_needed);
        @memset(bits, 0);

        return .{ 
            .bits = bits,
            .num_hashes = 7,
            .bits_per_key = bits_per_key,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.bits);
    }

    pub fn add(self: *Self, key: []const u8) void {
        inline for (0..self.num_hashes) |i| {
            const hash = std.hash.Wyhash.hash(i, key);
            const bit_idx = hash % (self.bits.len * 8);
            const byte_idx = bit_idx / 8;
            const bit_offset = @as(u3, @intCast(bit_idx % 8));
            self.bits[byte_idx] |= @as(u8, 1) << bit_offset;
        }
    }

    pub fn mightContain(self: Self, key: []const u8) bool {
        inline for (0..self.num_hashes) |i| {
            const hash = std.hash.Wyhash.hash(i, key);
            const bit_idx = hash % (self.bits.len * 8);
            const byte_idx = bit_idx / 8;
            const bit_offset = @as(u3, @intCast(bit_idx % 8));
            if ((self.bits[byte_idx] & (@as(u8, 1) << bit_offset)) == 0) {
                return false;
            }
        }
        return true;
    }

    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !Self {
        return .{ 
            .bits = try allocator.dupe(u8, bytes),
            .num_hashes = 7,
        };
    }
};

test "Bloom Filter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var bloom = try BloomFilter.init(allocator, 1000);
    defer bloom.deinit(allocator);

    bloom.add("testkey1");
    try std.testing.expect(bloom.mightContain("testkey1"));

    try std.testing.expect(!bloom.mightContain("testkey2"));
    bloom.add("testkey2");
    try std.testing.expect(bloom.mightContain("testkey2"));
}
