// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const rsp1 = @import("rsp1");

test "RSP1: sign/verify with active epoch" {
    var v = rsp1.LeaseVerifier.init(.{ .key = [_]u8{0} ** 32, .id = 1 });
    var sig: [32]u8 = undefined;
    const ttl_ns: i128 = 5 * std.time.ns_per_s;
    v.sign("g", "n", ttl_ns, 0, &sig);
    try std.testing.expect(v.verify("g", "n", ttl_ns, 0, &sig));
    // heartbeat counter change should produce different signature
    var sig2: [32]u8 = undefined;
    v.sign("g", "n", ttl_ns, 1, &sig2);
    try std.testing.expect(!std.mem.eql(u8, &sig, &sig2));
}

test "RSP1: rotation accepts previous key, rejects older than previous" {
    var k1: [32]u8 = undefined; @memset(&k1, 0x11);
    var k2: [32]u8 = undefined; @memset(&k2, 0x22);
    var k3: [32]u8 = undefined; @memset(&k3, 0x33);

    var v = rsp1.LeaseVerifier.init(.{ .key = k1, .id = 1 });

    // Sign with k1
    var sig1: [32]u8 = undefined;
    v.sign("grp", "ent", 1_000, 0, &sig1);
    try std.testing.expect(v.verify("grp", "ent", 1_000, 0, &sig1));

    // Rotate to k2: both k1 and k2 should verify
    v.rotate(.{ .key = k2, .id = 2 });
    try std.testing.expect(v.verify("grp", "ent", 1_000, 0, &sig1));
    var sig2: [32]u8 = undefined;
    v.sign("grp", "ent", 1_000, 1, &sig2);
    try std.testing.expect(v.verify("grp", "ent", 1_000, 1, &sig2));

    // Rotate to k3: only k2 + k3 remain; k1 should be forgotten
    v.rotate(.{ .key = k3, .id = 3 });
    try std.testing.expect(!v.verify("grp", "ent", 1_000, 0, &sig1));
    try std.testing.expect(v.verify("grp", "ent", 1_000, 1, &sig2));
}
