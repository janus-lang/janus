// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Tensor Capsule — model weights with BLAKE3 integrity

const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub const ModelCapsule = struct {
    name: []const u8,
    weights: []u8, // owned copy
    digest: [32]u8, // BLAKE3 digest bytes

    pub fn deinit(self: *ModelCapsule, allocator: Allocator) void {
        allocator.free(self.weights);
        allocator.free(self.name);
        self.* = undefined;
    }

    pub fn fromBytes(allocator: Allocator, name: []const u8, bytes: []const u8) !ModelCapsule {
        const wcopy = try allocator.alloc(u8, bytes.len);
        @memcpy(wcopy, bytes);
        const ncopy = try allocator.alloc(u8, name.len);
        @memcpy(ncopy, name);
        var dig: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(bytes, &dig, .{});
        return .{ .name = ncopy, .weights = wcopy, .digest = dig };
    }

    pub fn digestHex(self: *const ModelCapsule, allocator: Allocator) ![]u8 {
        const hex_value = std.fmt.bytesToHex(self.digest, .lower);
        return try allocator.dupe(u8, &hex_value);
    }

    pub fn verifyDigest(self: *const ModelCapsule, expected_hex: []const u8) bool {
        const hex_value = std.fmt.bytesToHex(self.digest, .lower);
        return std.mem.eql(u8, &hex_value, expected_hex);
    }
};

// ------------------ Tests ------------------
const testing = std.testing;

test "ModelCapsule computes BLAKE3 digest" {
    const data = "hello-weights";
    var cap = try ModelCapsule.fromBytes(testing.allocator, "toy", data);
    defer cap.deinit(testing.allocator);
    const hex = try cap.digestHex(testing.allocator);
    defer testing.allocator.free(hex);
    try testing.expect(hex.len == 64);
}
