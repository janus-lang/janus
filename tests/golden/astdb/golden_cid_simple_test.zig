// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Simple CID test that can be run with the build system

const std = @import("std");
const testing = std.testing;

test "CID BLAKE3 basic validation" {
    // Test BLAKE3 hash properties
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update("test content");

    var result: [32]u8 = undefined;
    hasher.final(&result);

    // BLAKE3 should produce 32-byte hashes
    try testing.expectEqual(@as(usize, 32), result.len);

    // Same input should produce same hash
    var hasher2 = std.crypto.hash.Blake3.init(.{});
    hasher2.update("test content");

    var result2: [32]u8 = undefined;
    hasher2.final(&result2);

    try testing.expectEqualSlices(u8, &result, &result2);

    // Different input should produce different hash
    var hasher3 = std.crypto.hash.Blake3.init(.{});
    hasher3.update("different content");

    var result3: [32]u8 = undefined;
    hasher3.final(&result3);

    try testing.expect(!std.mem.eql(u8, &result, &result3));
}

test "CID deterministic field order" {
    // Test the documented field order for CID computation
    var hasher = std.crypto.hash.Blake3.init(.{});

    // Documented field order:
    // 1. toolchain_version (u32, little-endian)
    // 2. profile_mask (u32, little-endian)
    // 3. effect_mask (u64, little-endian)
    // 4. safety_level (u8)
    // 5. fastmath (u8: 1 if true, 0 if false)
    // 6. deterministic (u8: 1 if true, 0 if false)
    // 7. reserved (u8: always 0)
    // 8. target_triple (length-prefixed string)

    var knobs: [20]u8 = undefined;
    std.mem.writeInt(u32, knobs[0..4], 1, .little); // toolchain_version
    std.mem.writeInt(u32, knobs[4..8], 0, .little); // profile_mask
    std.mem.writeInt(u64, knobs[8..16], 0, .little); // effect_mask
    knobs[16] = 1; // safety_level
    knobs[17] = 0; // fastmath (false)
    knobs[18] = 1; // deterministic (true)
    knobs[19] = 0; // reserved

    hasher.update(&knobs);

    // Target triple as length-prefixed string
    const target_triple = "unknown-unknown-unknown";
    const target_len = @as(u32, @intCast(target_triple.len));
    hasher.update(std.mem.asBytes(&target_len));
    hasher.update(target_triple);

    var result: [32]u8 = undefined;
    hasher.final(&result);

    // Should produce deterministic 32-byte hash
    try testing.expectEqual(@as(usize, 32), result.len);

    // Same inputs should produce same result
    var hasher2 = std.crypto.hash.Blake3.init(.{});
    hasher2.update(&knobs);
    hasher2.update(std.mem.asBytes(&target_len));
    hasher2.update(target_triple);

    var result2: [32]u8 = undefined;
    hasher2.final(&result2);

    try testing.expectEqualSlices(u8, &result, &result2);
}
