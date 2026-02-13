// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

const ns_msg = @import("ns_msg.zig");
const transport = @import("transport.zig");
const envelope = @import("envelope.zig");

test "integration: publish -> route -> transport -> receive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup transport
    var mem_transport = try transport.MemoryTransport.init(allocator);
    defer mem_transport.deinit();
    var trans: transport.Transport = .{ .memory = &mem_transport };

    // Setup router via NsMsg
    var nsm = try ns_msg.NsMsg.init(allocator);
    defer nsm.deinit();

    try nsm.addLocalRoute("app/service/*", &trans);

    // Verify route exists
    const routed = try nsm.route("app/service/backend");
    try testing.expect(routed != null);

    // Prepare payload
    const expected = envelope.SensorReading{
        .value = 42.5,
        .unit = "µg/m³",
        .timestamp = 1234567890,
        .geohash = "u33dc0",
    };

    // Publish
    const meta: ns_msg.NsMsg.FrameMeta = .{};
    try nsm.publishSensor("app/service/backend", 0xFF00, meta, expected, null);

    // Receive
    const received_opt = try nsm.recvSensor(&trans, null);
    try testing.expect(received_opt != null);
    const received = received_opt.?;

    // Verify (arena frees strings)
    try testing.expectApproxEqAbs(received.value, expected.value, 1e-6);
    try testing.expectEqualStrings(expected.unit, received.unit);
    try testing.expectEqual(expected.timestamp, received.timestamp);
    try testing.expectEqualStrings(expected.geohash, received.geohash);
}

test "integration: no route" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nsm = try ns_msg.NsMsg.init(allocator);
    defer nsm.deinit();

    const reading = envelope.SensorReading{
        .value = 1.0,
        .unit = "test",
        .timestamp = 0,
        .geohash = "test",
    };

    const meta: ns_msg.NsMsg.FrameMeta = .{};
    try testing.expectError(ns_msg.NoRoute.NoRoute, nsm.publishSensor("unrouted/path", 0xFF00, meta, reading, null));
}
