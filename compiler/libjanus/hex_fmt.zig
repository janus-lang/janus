// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Hex formatting utilities for Zig 0.15.2+
//! Replacement for deprecated std.fmt.fmtSliceHexLower

const std = @import("std");

/// Format a byte slice as lowercase hexadecimal string
/// Caller owns returned memory and must free it
pub fn hexSlice(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const hex_chars = "0123456789abcdef";
    var result = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, i| {
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return result;
}

/// Format a fixed-size hash as lowercase hexadecimal string
/// Caller owns returned memory and must free it
pub fn hexHash(allocator: std.mem.Allocator, hash: *const [32]u8) ![]u8 {
    return hexSlice(allocator, hash);
}

test "hexSlice basic" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const bytes = [_]u8{ 0xde, 0xad, 0xbe, 0xef };
    const hex = try hexSlice(allocator, &bytes);
    defer allocator.free(hex);

    try testing.expectEqualStrings("deadbeef", hex);
}

test "hexHash 32-byte" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const hash = [_]u8{0x42} ** 32;
    const hex = try hexHash(allocator, &hash);
    defer allocator.free(hex);

    try testing.expectEqual(@as(usize, 64), hex.len);
    try testing.expect(std.mem.allEqual(u8, hex, '4') or std.mem.allEqual(u8, hex, '2'));
}
