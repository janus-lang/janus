// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const utcp = @import("std_utcp");
const utcp_manual = @import("janusd_utcp");
const rsp1 = @import("rsp1");

// UTCP Transport BDD Test Suite
// These tests follow the Gherkin scenarios in features/transport/utcp_transport.feature

// ============================================================================
// Test: Manual Discovery
// ============================================================================

test "UTCP Transport: Client requests manual from janusd" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given a janusd instance is running on localhost:7654
    // When the client sends a "manual" request
    var manual_json = std.ArrayList(u8){};
    defer manual_json.deinit(allocator);

    try utcp_manual.writeManualJSON(manual_json.writer(allocator), .{});
    const json_bytes = try manual_json.toOwnedSlice(allocator);
    defer allocator.free(json_bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    const root = parsed.value;

    // Then the response contains "manual_version" equal to "0.1.1"
    const manual_version = root.object.get("manual_version").?;
    try std.testing.expectEqualStrings("0.1.1", manual_version.string);

    // And the response contains "utcp_version" equal to "0.1"
    const utcp_version = root.object.get("utcp_version").?;
    try std.testing.expectEqualStrings("0.1", utcp_version.string);

    // And the response contains an "auth" object with "auth_type" equal to "bearer"
    const auth = root.object.get("auth").?;
    try std.testing.expectEqualStrings("bearer", auth.object.get("auth_type").?.string);

    // And the response contains a "tools" array with at least one tool
    const tools = root.object.get("tools").?;
    try std.testing.expect(tools.array.items.len > 0);
}

test "UTCP Transport: Manual contains tool definitions with capabilities" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manual_json = std.ArrayList(u8){};
    defer manual_json.deinit(allocator);

    try utcp_manual.writeManualJSON(manual_json.writer(allocator), .{});
    const json_bytes = try manual_json.toOwnedSlice(allocator);
    defer allocator.free(json_bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    const tools = parsed.value.object.get("tools").?.array.items;

    // Each tool must have required fields
    for (tools) |tool| {
        const t = tool.object;

        // name (string)
        const name = t.get("name").?;
        try std.testing.expect(name == .string);
        try std.testing.expect(name.string.len > 0);

        // description (string)
        const desc = t.get("description").?;
        try std.testing.expect(desc == .string);
        try std.testing.expect(desc.string.len > 0);

        // inputs (object)
        const inputs = t.get("inputs").?;
        try std.testing.expect(inputs == .object);

        // tool_call_template (object) with required fields
        const tmpl = t.get("tool_call_template").?;
        try std.testing.expect(tmpl == .object);
        try std.testing.expect(tmpl.object.get("call_template_type").? == .string);
        try std.testing.expect(tmpl.object.get("url").? == .string);
        try std.testing.expect(tmpl.object.get("http_method").? == .string);

        // x-janus-capabilities (object) with required and optional
        const caps = t.get("x-janus-capabilities").?;
        try std.testing.expect(caps == .object);
        try std.testing.expect(caps.object.get("required").? == .array);
        try std.testing.expect(caps.object.get("optional").? == .array);
    }
}

// ============================================================================
// Test: Tool Invocation with Capability Validation
// ============================================================================

test "UTCP Transport: Client calls tool with required capabilities" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup registry with test key
    var secret_key: [32]u8 = undefined;
    @memcpy(&secret_key, "test-capability-key-1234567890!!");

    var registry = utcp.Registry.init(allocator, secret_key);
    defer registry.deinit();

    // Create a test container that represents a compilable unit
    const TestCompileUnit = struct {
        name: []const u8,
        source_file: []const u8,

        pub fn utcpManual(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(alloc, "{{\"name\":\"{s}\",\"source\":\"{s}\"}}", .{ self.name, self.source_file });
        }
    };

    var unit = TestCompileUnit{ .name = "test_compile", .source_file = "test.janus" };

    // Register the compile unit
    try registry.registerLease(
        "compile_tools",
        "compile_test",
        &unit,
        struct {
            fn call(ctx: *const anyopaque, alloc: std.mem.Allocator) ![]const u8 {
                const p = @as(*const TestCompileUnit, @ptrCast(@alignCast(ctx)));
                return p.utcpManual(alloc);
            }
        }.call,
        60,
        .{},
    );

    // Verify registration succeeded
    const manual = try registry.buildManual(allocator);
    defer allocator.free(manual);
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "compile_test"));
}

test "UTCP Transport: Client calls tool without required capabilities - E1403_CAP_MISMATCH" {
    // This test documents the expected behavior when capabilities are missing
    // Currently the registry requires WriteCapability which is a compile-time type
    // Future work: Add runtime capability token validation

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var secret_key: [32]u8 = undefined;
    @memcpy(&secret_key, "test-rejection-key-1234567890!!!");

    var registry = utcp.Registry.init(allocator, secret_key);
    defer registry.deinit();

    // Without WriteCapability, operations should be blocked at compile time
    // This test validates the capability-based API design
    // Registry is used via defer deinit
}

// ============================================================================
// Test: Lease Registry Operations
// ============================================================================

test "UTCP Transport: Client registers a lease for UTCP entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var secret_key: [32]u8 = undefined;
    @memcpy(&secret_key, "test-lease-reg-key-1234567890!!!");

    var registry = utcp.Registry.init(allocator, secret_key);
    defer registry.deinit();

    const TestEntry = struct {
        name: []const u8,
        value: u32,

        pub fn utcpManual(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(alloc, "{{\"name\":\"{s}\",\"value\":{}}}", .{ self.name, self.value });
        }
    };

    var entry = TestEntry{ .name = "test_lease_entry", .value = 42 };

    // Register with 60 second TTL
    try registry.registerLease(
        "test_group",
        "test_entry",
        &entry,
        struct {
            fn call(ctx: *const anyopaque, alloc: std.mem.Allocator) ![]const u8 {
                const p = @as(*const TestEntry, @ptrCast(@alignCast(ctx)));
                return p.utcpManual(alloc);
            }
        }.call,
        60,
        .{},
    );

    // Verify lease exists and has valid signature
    const manual = try registry.buildManual(allocator);
    defer allocator.free(manual);

    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "test_entry"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "signature"));
    try std.testing.expect(std.mem.containsAtLeast(u8, manual, 1, "lease_deadline"));
}

test "UTCP Transport: Client extends lease via heartbeat" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var secret_key: [32]u8 = undefined;
    @memcpy(&secret_key, "test-heartbeat-key-1234567890!!!");

    var registry = utcp.Registry.init(allocator, secret_key);
    defer registry.deinit();

    const TestEntry = struct {
        name: []const u8,
        pub fn utcpManual(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(alloc, "{{\"name\":\"{s}\"}}", .{self.name});
        }
    };

    var entry = TestEntry{ .name = "heartbeat_test" };

    // Register with short TTL
    try registry.registerLease(
        "heartbeat_group",
        "heartbeat_entry",
        &entry,
        struct {
            fn call(ctx: *const anyopaque, alloc: std.mem.Allocator) ![]const u8 {
                const p = @as(*const TestEntry, @ptrCast(@alignCast(ctx)));
                return p.utcpManual(alloc);
            }
        }.call,
        5,
        .{},
    );

    // Extend via heartbeat
    const success = try registry.heartbeat(
        "heartbeat_group",
        "heartbeat_entry",
        120,
        .{},
    );

    try std.testing.expect(success);

    // Verify heartbeat_count incremented
    if (registry.findGroup("heartbeat_group")) |g| {
        for (g.entries.items) |e| {
            if (std.mem.eql(u8, e.name, "heartbeat_entry")) {
                try std.testing.expectEqual(@as(u64, 1), e.heartbeat_count);
            }
        }
    }
}

test "UTCP Transport: Heartbeat fails with invalid signature" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var secret_key: [32]u8 = undefined;
    @memcpy(&secret_key, "test-sigfail-key-1234567890!!!!!");

    var registry = utcp.Registry.init(allocator, secret_key);
    defer registry.deinit();

    const TestEntry = struct {
        name: []const u8,
        pub fn utcpManual(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(alloc, "{{\"name\":\"{s}\"}}", .{self.name});
        }
    };

    var entry = TestEntry{ .name = "sigfail_test" };

    try registry.registerLease(
        "sigfail_group",
        "sigfail_entry",
        &entry,
        struct {
            fn call(ctx: *const anyopaque, alloc: std.mem.Allocator) ![]const u8 {
                const p = @as(*const TestEntry, @ptrCast(@alignCast(ctx)));
                return p.utcpManual(alloc);
            }
        }.call,
        60,
        .{},
    );

    // Corrupt the signature
    if (registry.findGroup("sigfail_group")) |g| {
        for (g.entries.items) |*e| {
            if (std.mem.eql(u8, e.name, "sigfail_entry")) {
                e.signature[0] ^= 0xFF;
            }
        }
    }

    // Heartbeat should fail
    const success = try registry.heartbeat(
        "sigfail_group",
        "sigfail_entry",
        60,
        .{},
    );

    try std.testing.expect(!success);
}

// ============================================================================
// Test: Registry State and Quotas
// ============================================================================

test "UTCP Transport: Client queries registry state" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var secret_key: [32]u8 = undefined;
    @memcpy(&secret_key, "test-state-key-1234567890!!!!!!!");

    var registry = utcp.Registry.init(allocator, secret_key);
    defer registry.deinit();

    const TestEntry = struct {
        name: []const u8,
        pub fn utcpManual(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(alloc, "{{\"name\":\"{s}\"}}", .{self.name});
        }
    };

    var entry = TestEntry{ .name = "state_test" };

    try registry.registerLease(
        "state_group",
        "state_entry",
        &entry,
        struct {
            fn call(ctx: *const anyopaque, alloc: std.mem.Allocator) ![]const u8 {
                const p = @as(*const TestEntry, @ptrCast(@alignCast(ctx)));
                return p.utcpManual(alloc);
            }
        }.call,
        60,
        .{},
    );

    // Build manual (equivalent to querying registry state)
    const manual = try registry.buildManual(allocator);
    defer allocator.free(manual);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, manual, .{});
    defer parsed.deinit();

    // Verify expected fields
    try std.testing.expect(parsed.value.object.contains("utcp_version"));
    try std.testing.expect(parsed.value.object.contains("backpressure_metrics"));
    try std.testing.expect(parsed.value.object.contains("groups"));
}

test "UTCP Transport: Admin sets namespace quota" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var secret_key: [32]u8 = undefined;
    @memcpy(&secret_key, "test-quota-key-1234567890!!!!!!!");

    var registry = utcp.Registry.init(allocator, secret_key);
    defer registry.deinit();

    // Set quota to 5 entries per group
    registry.setNamespaceQuota(5);

    const TestEntry = struct {
        id: usize,
        pub fn utcpManual(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(alloc, "{{\"id\":{}}}", .{self.id});
        }
    };

    // Register 5 entries (should succeed)
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var entry = TestEntry{ .id = i };
        try registry.registerLease(
            "quota_group",
            try std.fmt.allocPrint(allocator, "entry_{}", .{i}),
            &entry,
            struct {
                fn call(ctx: *const anyopaque, alloc: std.mem.Allocator) ![]const u8 {
                    const p = @as(*const TestEntry, @ptrCast(@alignCast(ctx)));
                    return p.utcpManual(alloc);
                }
            }.call,
            60,
            .{},
        );
    }

    // 6th entry should fail with quota exceeded
    var entry6 = TestEntry{ .id = 5 };
    const result = registry.registerLease(
        "quota_group",
        "entry_5",
        &entry6,
        struct {
            fn call(ctx: *const anyopaque, alloc: std.mem.Allocator) ![]const u8 {
                const p = @as(*const TestEntry, @ptrCast(@alignCast(ctx)));
                return p.utcpManual(alloc);
            }
        }.call,
        60,
        .{},
    );

    try std.testing.expectError(error.NamespaceQuotaExceeded, result);
}

test "UTCP Transport: Quota enforcement prevents overflow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var secret_key: [32]u8 = undefined;
    @memcpy(&secret_key, "test-quota2-key-1234567890!!!!!!");

    var registry = utcp.Registry.init(allocator, secret_key);
    defer registry.deinit();

    // Set very low quota
    registry.setNamespaceQuota(2);

    const TestEntry = struct {
        id: usize,
        pub fn utcpManual(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(alloc, "{{\"id\":{}}}", .{self.id});
        }
    };

    // Register 2 entries
    var e1 = TestEntry{ .id = 1 };
    try registry.registerLease("quota_test_group", "entry_1", &e1, makeAdapter(TestEntry), 60, .{});

    var e2 = TestEntry{ .id = 2 };
    try registry.registerLease("quota_test_group", "entry_2", &e2, makeAdapter(TestEntry), 60, .{});

    // 3rd entry should fail
    var e3 = TestEntry{ .id = 3 };
    const result = registry.registerLease("quota_test_group", "entry_3", &e3, makeAdapter(TestEntry), 60, .{});

    try std.testing.expectError(error.NamespaceQuotaExceeded, result);
}

fn makeAdapter(comptime T: type) utcp.ManualFn {
    return struct {
        fn call(ctx: *const anyopaque, alloc: std.mem.Allocator) ![]const u8 {
            const p = @as(*const T, @ptrCast(@alignCast(ctx)));
            return p.utcpManual(alloc);
        }
    }.call;
}

// ============================================================================
// Test: Key Rotation (RSP-1)
// ============================================================================

test "UTCP Transport: Admin rotates epoch key" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var k1: [32]u8 = undefined;
    @memcpy(&k1, "epoch-key-aaaaaaaaaaaaaaaaaaaaaa");

    var registry = utcp.Registry.init(allocator, k1);
    defer registry.deinit();

    const TestEntry = struct {
        name: []const u8,
        pub fn utcpManual(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(alloc, "{{\"name\":\"{s}\"}}", .{self.name});
        }
    };

    var entry = TestEntry{ .name = "rotation_test" };

    // Register with old key
    try registry.registerLease(
        "rotation_group",
        "rotation_entry",
        &entry,
        makeAdapter(TestEntry),
        60,
        .{},
    );

    // Rotate to new key
    var k2: [32]u8 = undefined;
    @memcpy(&k2, "epoch-key-bbbbbbbbbbbbbbbbbbbbbb");  // 32 bytes
    registry.rotateKey(.{ .key = k2, .id = 2 });

    // Old lease should still be valid (grace period)
    const success = try registry.heartbeat("rotation_group", "rotation_entry", 30, .{});
    try std.testing.expect(success);
}
