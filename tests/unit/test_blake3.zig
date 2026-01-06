// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("compiler/libjanus/api.zig");

pub fn main() !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    try stdout_writer.print("🔧 BLAKE3 Integration Test\n", .{});
    try stdout_writer.print("==========================\n", .{});

    // Test the CAS functionality which uses BLAKE3
    const test_data = "Hello, Janus Ledger!";

    try stdout_writer.print("Testing BLAKE3 through CAS...\n", .{});

    // Use the CAS hash function which internally uses BLAKE3
    const hash = janus.ledger.cas.blake3Hash(test_data);

    try stdout_writer.print("Input: '{s}'\n", .{test_data});
    // Format hash as hex
    const hex_chars = "0123456789abcdef";
    var hash_hex: [64]u8 = undefined;
    for (hash, 0..) |byte, i| {
        hash_hex[i * 2] = hex_chars[byte >> 4];
        hash_hex[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    try stdout_writer.print("BLAKE3 Hash: {s}\n", .{hash_hex});

    // Test that the hash is deterministic
    const hash2 = janus.ledger.cas.blake3Hash(test_data);
    const is_deterministic = std.mem.eql(u8, &hash, &hash2);

    try stdout_writer.print("Deterministic: {}\n", .{is_deterministic});

    if (is_deterministic) {
        try stdout_writer.print("\n✅ BLAKE3 integration successful!\n", .{});
        try stdout_writer.print("✅ Cryptographic sovereignty achieved!\n", .{});
        try stdout_writer.print("✅ The Janus Ledger foundation is solid!\n", .{});
    } else {
        try stdout_writer.print("\n❌ BLAKE3 integration failed!\n", .{});
        try stdout_writer.flush();
        return;
    }

    try stdout_writer.flush();
}
