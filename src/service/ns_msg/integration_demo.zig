// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Demo: Pub/Sub over MemoryTransport
//! zig build-exe integration_demo.zig && ./integration_demo

const std = @import("std");

const ns_msg = @import("ns_msg.zig");
const transport = @import("transport.zig");
const envelope = @import("envelope.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mem_transport = try transport.MemoryTransport.init(allocator);
    defer mem_transport.deinit();
    var trans: transport.Transport = .{ .memory = &mem_transport };

    var nsm = try ns_msg.NsMsg.init(allocator);
    defer nsm.deinit();

    try nsm.addLocalRoute("demo/sensor/*", &trans);

    // Publish example sensor reading
    const reading = envelope.SensorReading{
        .value = 52.3,
        .unit = "µg/m³",
        .timestamp = @intCast(std.time.timestamp()),
        .geohash = "u33dc0",
    };

    const meta: ns_msg.NsMsg.FrameMeta = .{};
    try nsm.publishSensor("demo/sensor/berlin/pm25", 0xFF00, meta, reading, null);
    std.debug.print("Published sensor reading to demo/sensor/berlin/pm25\n", .{});

    // Receive and print
    const received_opt = try nsm.recvSensor(&trans, null);
    if (received_opt) |received| {
        std.debug.print(
            "Received: {d:.1} {s} (geohash: {s}, ts: {d})\n",
            .{ received.value, received.unit, received.geohash, received.timestamp }
        );
        allocator.free(received.unit);
        allocator.free(received.geohash);
    } else {
        std.debug.print("No message received\n", .{});
    }
}
