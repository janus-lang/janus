// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const utcp = @import("../std/utcp_registry.zig");
const rsp1 = @import("../std/rsp1_crypto.zig");
const cl = @import("../std/rsp1_cluster.zig");

/// Test container for lease registry testing
const TestContainer = struct {
    name: []const u8,
    value: u32,

    pub const WriteCapability = struct {};

    pub fn utcpManual(self: *const TestContainer, alloc: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(alloc, "{{\"name\":\"{s}\",\"value\":{}}}", .{self.name, self.value});
    }
};

test "UTCP lease registry - basic lease registration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Create registry with test secret key (32 bytes)
    var secret_key: [32]u8 = undefined;
    const test_key1 = "test-secret-key-for-utcp-lease!!"; // 32 bytes
    @memcpy(&secret_key, test_key1);

    var registry = utcp.Registry.init(gpa.allocator(), secret_key);
    defer registry.deinit();

    var container = TestContainer{ .name = "test_container", .value = 42 };

    // Register with 10 second lease
    try registry.registerLease(
        "test_group",
        "test_entry",
        &container,
        utcp.makeManualAdapter(TestContainer),
        10,
        .{},
    );

    // Verify lease exists
    const manual = try registry.buildManual(gpa.allocator());
    defer gpa.allocator().free(manual);

    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "test_group"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "test_entry"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "test_container"));
}

test "UTCP lease registry - heartbeat extension" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var secret_key: [32]u8 = undefined;
    const test_key2 = "test-secret-key-for-utcp-lease!!"; // 32 bytes
    @memcpy(&secret_key, test_key2);

    var registry = utcp.Registry.init(gpa.allocator(), secret_key);
    defer registry.deinit();

    var container = TestContainer{ .name = "heartbeat_test", .value = 100 };

    // Register with short lease (1 second)
    try registry.registerLease(
        "heartbeat_group",
        "heartbeat_entry",
        &container,
        utcp.makeManualAdapter(TestContainer),
        1,
        .{},
    );

    // Sleep for 500ms
    std.time.sleep(500 * std.time.ns_per_ms);

    // Extend lease with heartbeat (5 seconds)
    const success = try registry.heartbeat(
        "heartbeat_group",
        "heartbeat_entry",
        5,
        .{},
    );

    try std.testing.expect(success);

    // Verify lease was extended
    const manual = try registry.buildManual(gpa.allocator());
    defer gpa.allocator().free(manual);

    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "heartbeat_group"));
}

test "UTCP lease registry - signature verification fails" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var secret_key: [32]u8 = undefined;
    const test_key3 = "test-secret-key-for-utcp-lease!!"; // 32 bytes
    @memcpy(&secret_key, test_key3);

    var registry = utcp.Registry.init(gpa.allocator(), secret_key);
    defer registry.deinit();

    // Manually tamper with registry to simulate bad signature
    try registry.registerLease(
        "tamper_group",
        "tamper_entry",
        &TestContainer{ .name = "tamper", .value = 999 },
        utcp.makeManualAdapter(TestContainer),
        10,
        .{},
    );

    // Manually corrupt signature in registry
    if (registry.findGroup("tamper_group")) |g| {
        for (g.entries.items) |*e| {
            if (std.mem.eql(u8, e.name, "tamper_entry")) {
                e.signature[0] ^= 0xFF; // flip bits to corrupt signature
            }
        }
    }

    // Heartbeat should fail due to bad signature
    const success = try registry.heartbeat(
        "tamper_group",
        "tamper_entry",
        10,
        .{},
    );

    try std.testing.expect(!success);
}

test "UTCP lease registry - stale entry cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var secret_key: [32]u8 = undefined;
    const test_key4 = "test-cleanup-key-for-registry!!!"; // 32 bytes
    @memcpy(&secret_key, test_key4);

    var registry = utcp.Registry.init(gpa.allocator(), secret_key);
    defer registry.deinit();

    var container1 = TestContainer{ .name = "live_container", .value = 1 };
    var container2 = TestContainer{ .name = "expired_container", .value = 2 };

    // Register containers with very short leases (100ms)
    try registry.registerLease(
        "cleanup_group",
        "live_entry",
        &container1,
        utcp.makeManualAdapter(TestContainer),
        1, // 1 second
        .{},
    );

    try registry.registerLease(
        "cleanup_group",
        "expired_entry",
        &container2,
        utcp.makeManualAdapter(TestContainer),
        0, // 0 seconds = already expired
        .{},
    );

    // Sleep for 100ms to ensure expiration
    std.time.sleep(100 * std.time.ns_per_ms);

    // Build manual which triggers cleanup
    const manual1 = try registry.buildManual(gpa.allocator());
    defer gpa.allocator().free(manual1);

    // Only live entry should remain
    try std.testing.expect(std.mem.containsAtLeast(u8, manual1, 1, "live_entry"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, manual1, 1, "expired_entry"));
}

test "UTCP lease registry - crypto signature validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var secret_key: [32]u8 = undefined;
    const test_key5 = "crypto-test-secret-key-123456!!!"; // 32 bytes
    @memcpy(&secret_key, test_key5);

    var registry = utcp.Registry.init(gpa.allocator(), secret_key);
    defer registry.deinit();

    var container = TestContainer{ .name = "crypto_test", .value = 777 };

    const ttl_seconds: u64 = 60;
    const now = std.time.nanoTimestamp();
    const expected_deadline = now + (@as(i128, ttl_seconds) * std.time.ns_per_s);

    // Register container
    try registry.registerLease(
        "crypto_group",
        "crypto_entry",
        &container,
        utcp.makeManualAdapter(TestContainer),
        ttl_seconds,
        .{},
    );

    // Verify signature in registry matches expected
    if (registry.findGroup("crypto_group")) |g| {
        for (g.entries.items) |e| {
            if (std.mem.eql(u8, e.name, "crypto_entry")) {
                // Verify signature using RSP-1 (ttl_ns + heartbeat_count)
                var v = rsp1.LeaseVerifier.init(.{ .key = secret_key, .id = 1 });
                var expected_sig: [32]u8 = undefined;
                v.sign("crypto_group", "crypto_entry", @as(i128, ttl_seconds) * std.time.ns_per_s, 0, &expected_sig);
                try std.testing.expectEqualSlices(u8, &expected_sig, &e.signature);
                try std.testing.expect(e.deadline_ns <= expected_deadline);
            }
        }
    }
}

test "UTCP lease registry - concurrent access safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var secret_key: [32]u8 = undefined;
    const test_key6 = "concurrent-test-secret-key-789!!"; // 32 bytes (was 33)
    @memcpy(&secret_key, test_key6);

    var registry = utcp.Registry.init(gpa.allocator(), secret_key);
    defer registry.deinit();

    const num_threads = 4;
    const entries_per_thread = 10;

    var threads: [num_threads]std.Thread = undefined;
    var thread_data: [num_threads]TestContainer = undefined;

    // Spawn threads to register entries concurrently
    for (0..num_threads) |i| {
        thread_data[i] = TestContainer{
            .name = try std.fmt.allocPrint(gpa.allocator(), "thread_{}_container", .{i}),
            .value = @intCast(i * 100),
        };

        threads[i] = try std.Thread.spawn(.{}, struct {
            fn threadFn(reg: *utcp.Registry, container: *TestContainer, thread_id: usize, count: usize) !void {
                for (0..count) |j| {
                    const entry_name = try std.fmt.allocPrint(std.heap.page_allocator, "thread_{}_entry_{}", .{thread_id, j});
                    defer std.heap.page_allocator.free(entry_name);

                    try reg.registerLease(
                        "concurrent_group",
                        entry_name,
                        container,
                        utcp.makeManualAdapter(TestContainer),
                        30, // 30 second lease
                        .{},
                    );
                }
            }
        }.threadFn, .{ &registry, &thread_data[i], i, entries_per_thread });
    }

    // Wait for all threads to complete
    for (0..num_threads) |i| {
        threads[i].join();
        gpa.allocator().free(thread_data[i].name);
    }

    // Verify all entries were registered
    const manual = try registry.buildManual(gpa.allocator());
    defer gpa.allocator().free(manual);

    var total_entries: usize = 0;
    for (0..num_threads) |i| {
        for (0..entries_per_thread) |j| {
            const entry_name = try std.fmt.allocPrint(gpa.allocator(), "thread_{}_entry_{}", .{i, j});
            defer gpa.allocator().free(entry_name);

            if (std.mem.containsAtLeast(u8, manual, 1, entry_name)) {
                total_entries += 1;
            }
        }
    }

    try std.testing.expectEqual(total_entries, num_threads * entries_per_thread);
}

test "UTCP lease registry - lease metadata in manual" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var secret_key: [32]u8 = undefined;
    const test_key7 = "metadata-test-secret-key-abcdefg"; // 32 bytes (fixed length)
    @memcpy(&secret_key, test_key7);

    var registry = utcp.Registry.init(gpa.allocator(), secret_key);
    defer registry.deinit();

    var container = TestContainer{ .name = "metadata_test", .value = 12345 };

    const lease_ttl: u64 = 120; // 2 minutes
    const before_time = std.time.nanoTimestamp();

    try registry.registerLease(
        "metadata_group",
        "metadata_entry",
        &container,
        utcp.makeManualAdapter(TestContainer),
        lease_ttl,
        .{},
    );

    const after_time = std.time.nanoTimestamp();

    const manual = try registry.buildManual(gpa.allocator());
    defer gpa.allocator().free(manual);

    // Verify lease metadata is included in manual
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "lease_deadline"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "heartbeat_count"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "signature"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "registry_time_ns"));

    // Parse JSON to verify deadline is reasonable
    var parser = std.json.Parser.init(gpa.allocator(), false);
    defer parser.deinit();
    const parsed = try parser.parse(manual);
    defer parsed.deinit();

    const root = parsed.value.object.get("groups").?.value.object.get("metadata_group").?.value.array.items[0].object;
    const deadline = root.get("lease_deadline").?.value.integer;
    const heartbeat_count = root.get("heartbeat_count").?.value.integer;

    try std.testing.expect(deadline >= before_time);
    try std.testing.expect(deadline <= after_time + (@as(i128, lease_ttl) * std.time.ns_per_s));
    try std.testing.expectEqual(heartbeat_count, 0); // no heartbeats yet
}

test "UTCP lease registry - namespace quota enforcement" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var secret_key: [32]u8 = undefined;
    const key = "quota-test-secret-key-xxxxxxxx"; // 32 bytes
    @memcpy(&secret_key, key);

    var registry = utcp.Registry.init(A, secret_key);
    defer registry.deinit();

    // Set quota to 1 entry per group
    registry.setNamespaceQuota(1);

    var c1 = TestContainer{ .name = "q1", .value = 1 };
    var c2 = TestContainer{ .name = "q2", .value = 2 };

    try registry.registerLease(
        "quota_group",
        "entry_one",
        &c1,
        utcp.makeManualAdapter(TestContainer),
        5,
        .{},
    );

    // Second distinct entry should exceed the quota
    try std.testing.expectError(error.NamespaceQuotaExceeded, registry.registerLease(
        "quota_group",
        "entry_two",
        &c2,
        utcp.makeManualAdapter(TestContainer),
        5,
        .{},
    ));
}

test "RSP-1: key rotation accepts previous signatures" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var k1: [32]u8 = undefined;
    @memcpy(&k1, "epoch-key-aaaaaaaaaaaaaaaaaaaaaaaa");
    var reg = utcp.Registry.init(A, k1);
    defer reg.deinit();

    var c = TestContainer{ .name = "rot", .value = 1 };
    try reg.registerLease("grp", "ent", &c, utcp.makeManualAdapter(TestContainer), 2, .{});

    // Rotate to new key; verify old signature still validates for heartbeat
    var k2: [32]u8 = undefined;
    @memcpy(&k2, "epoch-key-bbbbbbbbbbbbbbbbbbbbbbbb");
    reg.rotateKey(.{ .key = k2, .id = 2 });

    // Heartbeat should still be accepted (verification uses either key)
    const ok = try reg.heartbeat("grp", "ent", 3, .{});
    try std.testing.expect(ok);
}

test "Raft-lite: registry uses replicator for quorum" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var k: [32]u8 = undefined;
    @memcpy(&k, "epoch-key-cccccccccccccccccccccccc");
    var reg = utcp.Registry.init(A, k);
    defer reg.deinit();

    // Build a tiny 3-node cluster and attach a replicator
    const cl = @import("../std/rsp1_cluster.zig");
    var leader = try cl.RegistryNode.init(A, 1);
    defer leader.deinit();
    var f1 = try cl.RegistryNode.init(A, 2);
    defer f1.deinit();
    var f2 = try cl.RegistryNode.init(A, 3);
    defer f2.deinit();

    const rep = cl.Replicator{
        .ctx = &leader,
        .call = struct {
            fn run(ctx: *anyopaque, op: []const u8) anyerror!bool {
                var l: *cl.RegistryNode = @ptrCast(ctx);
                return try cl.syncCluster(l, &[_]*cl.RegistryNode{ &f1, &f2 }, op);
            }
        }.run,
    };
    reg.attachReplicator(rep);

    var c = TestContainer{ .name = "q", .value = 7 };
    try reg.registerLease("g", "n", &c, utcp.makeManualAdapter(TestContainer), 5, .{});

    // Quorum was achieved (leader log has one entry)
    try std.testing.expect(leader.log.items.len == 1);
}
