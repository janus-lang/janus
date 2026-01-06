// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Zig wrapper for the BLAKE3 C library
// This provides a clean, safe interface to the official BLAKE3 implementation
// while maintaining our sovereignty principles through vendored dependencies.

// BLAKE3 C library bindings
const c = @cImport({
    @cInclude("blake3.h");
});

pub const BLAKE3_OUT_LEN = 32; // 256 bits
pub const BLAKE3_KEY_LEN = 32; // 256 bits
pub const BLAKE3_CONTEXT_LEN = 16; // 128 bits

// BLAKE3 hasher context
pub const Hasher = struct {
    ctx: c.blake3_hasher,

    // Initialize a new hasher
    pub fn init() Hasher {
        var hasher = Hasher{
            .ctx = undefined,
        };
        c.blake3_hasher_init(&hasher.ctx);
        return hasher;
    }

    // Initialize a hasher with a key for keyed hashing
    pub fn initKeyed(key: *const [BLAKE3_KEY_LEN]u8) Hasher {
        var hasher = Hasher{
            .ctx = undefined,
        };
        c.blake3_hasher_init_keyed(&hasher.ctx, key);
        return hasher;
    }

    // Initialize a hasher for key derivation
    pub fn initDerive(context: []const u8) Hasher {
        var hasher = Hasher{
            .ctx = undefined,
        };
        c.blake3_hasher_init_derive_key(&hasher.ctx, context.ptr);
        return hasher;
    }

    // Update the hasher with input data
    pub fn update(self: *Hasher, input: []const u8) void {
        c.blake3_hasher_update(&self.ctx, input.ptr, input.len);
    }

    // Finalize the hash and write the result to output
    pub fn final(self: *Hasher, output: []u8) void {
        c.blake3_hasher_finalize(&self.ctx, output.ptr, output.len);
    }

    // Finalize the hash and return a fixed-size result
    pub fn finalFixed(self: *Hasher) [BLAKE3_OUT_LEN]u8 {
        var result: [BLAKE3_OUT_LEN]u8 = undefined;
        c.blake3_hasher_finalize(&self.ctx, &result, BLAKE3_OUT_LEN);
        return result;
    }

    // Reset the hasher to its initial state
    pub fn reset(self: *Hasher) void {
        c.blake3_hasher_init(&self.ctx);
    }
};

// Convenience function to hash data in one call
pub fn hash(input: []const u8) [BLAKE3_OUT_LEN]u8 {
    var hasher = Hasher.init();
    hasher.update(input);
    return hasher.finalFixed();
}

// Convenience function for keyed hashing
pub fn hashKeyed(key: *const [BLAKE3_KEY_LEN]u8, input: []const u8) [BLAKE3_OUT_LEN]u8 {
    var hasher = Hasher.initKeyed(key);
    hasher.update(input);
    return hasher.finalFixed();
}

// Convenience function for key derivation
pub fn deriveKey(context: []const u8, input: []const u8) [BLAKE3_OUT_LEN]u8 {
    var hasher = Hasher.initDerive(context);
    hasher.update(input);
    return hasher.finalFixed();
}

// Test that the BLAKE3 library is working correctly
pub fn selfTest() bool {
    // Test vector from the BLAKE3 specification
    const test_input = "";
    const expected = [_]u8{
        0xaf, 0x13, 0x49, 0xb9, 0xf5, 0xf9, 0xa1, 0xa6,
        0xa0, 0x40, 0x4d, 0xea, 0x36, 0xdc, 0xc9, 0x49,
        0x9b, 0xcb, 0x25, 0xc9, 0xad, 0xc1, 0x12, 0xb7,
        0xcc, 0x9a, 0x93, 0xca, 0xe4, 0x1f, 0x32, 0x62,
    };

    const result = hash(test_input);
    return std.mem.eql(u8, &result, &expected);
}
