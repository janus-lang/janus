// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Dilithium3 backend selector.
// Default: deterministic test backend to keep build green.
// For real Dilithium3 integration, see crypto_dilithium_pqclean.zig
// and pass -Dcrypto-backend=pqclean once vendor sources are linked.

const build_options = @import("build_options");
const Backend = enum { stub, pqclean };
const selected_backend: Backend = blk: {
    if (std.mem.eql(u8, build_options.crypto_backend, "pqclean")) break :blk .pqclean;
    break :blk .stub;
};

pub const Algorithm = enum { dilithium3_test, dilithium3 };

pub const Keypair = struct {
    public_key: []u8,
    private_key: []u8,
    allocator: std.mem.Allocator,
    pub fn deinit(self: *Keypair) void {
        self.allocator.free(self.public_key);
        self.allocator.free(self.private_key);
    }
};

pub fn generateKeypair(allocator: std.mem.Allocator) !Keypair {
    return switch (selected_backend) {
        .stub => test_generateKeypair(allocator),
        .pqclean => pq_generateKeypair(allocator),
    };
}

pub fn derivePublicKey(allocator: std.mem.Allocator, private_key: []const u8) ![]u8 {
    return switch (selected_backend) {
        .stub => test_derivePublicKey(allocator, private_key),
        .pqclean => pq_derivePublicKey(allocator, private_key),
    };
}

pub fn sign(private_key: []const u8, message: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return switch (selected_backend) {
        .stub => test_sign(private_key, message, allocator),
        .pqclean => pq_sign(private_key, message, allocator),
    };
}

pub fn verify(public_key: []const u8, message: []const u8, signature: []const u8) bool {
    return switch (selected_backend) {
        .stub => test_verify(public_key, message, signature),
        .pqclean => pq_verify(public_key, message, signature),
    };
}

pub fn parseThreshold(s: []const u8) ?struct { n: u32, m: u32 } {
    if (std.mem.indexOfScalar(u8, s, '/')) |p| {
        const a = std.mem.trim(u8, s[0..p], " \t");
        const b = std.mem.trim(u8, s[p+1..], " \t");
        const n = std.fmt.parseInt(u32, a, 10) catch return null;
        const m = std.fmt.parseInt(u32, b, 10) catch return null;
        if (n == 0 or m == 0 or n > m) return null;
        return .{ .n = n, .m = m };
    }
    return null;
}

// -----------------------
// Test backend (default)
// -----------------------
fn test_generateKeypair(allocator: std.mem.Allocator) !Keypair {
    const prk = try allocator.alloc(u8, 48);
    errdefer allocator.free(prk);
    try std.crypto.random.bytes(prk);
    const public = try test_derivePublicKey(allocator, prk);
    return .{ .public_key = public, .private_key = prk, .allocator = allocator };
}

fn test_derivePublicKey(allocator: std.mem.Allocator, private_key: []const u8) ![]u8 {
    var h = std.crypto.hash.Blake3.init(.{});
    h.update(private_key);
    var out: [32]u8 = undefined;
    h.final(&out);
    return try allocator.dupe(u8, &out);
}

fn test_sign(private_key: []const u8, message: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const pub_key = try test_derivePublicKey(allocator, private_key);
    defer allocator.free(pub_key);
    var h = std.crypto.hash.Blake3.init(.{});
    h.update(pub_key);
    h.update(message);
    var sig: [32]u8 = undefined;
    h.final(&sig);
    return try allocator.dupe(u8, &sig);
}

fn test_verify(public_key: []const u8, message: []const u8, signature: []const u8) bool {
    var h = std.crypto.hash.Blake3.init(.{});
    h.update(public_key);
    h.update(message);
    var sig: [32]u8 = undefined;
    h.final(&sig);
    return signature.len == sig.len and std.mem.eql(u8, signature, &sig);
}

// --------------------------------
// PQClean backend (scaffolding)
// --------------------------------
fn pq_generateKeypair(allocator: std.mem.Allocator) !Keypair {
    // TODO: wire to PQClean Dilithium3 keypair
    // Placeholder: fall back to test for now
    return test_generateKeypair(allocator);
}

fn pq_derivePublicKey(allocator: std.mem.Allocator, private_key: []const u8) ![]u8 {
    // TODO: if private contains seed, derive pub via PQClean; else unsupported
    return test_derivePublicKey(allocator, private_key);
}

fn pq_sign(private_key: []const u8, message: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // TODO: call PQClean sign
    return test_sign(private_key, message, allocator);
}

fn pq_verify(public_key: []const u8, message: []const u8, signature: []const u8) bool {
    // TODO: call PQClean verify
    return test_verify(public_key, message, signature);
}
