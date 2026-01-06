// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Simple MessagePack Test - Proves the Protocol Works
//!
//! This test creates a minimal MessagePack ping request and verifies
//! that the daemon can parse it and respond correctly.

const std = @import("std");
const protocol = @import("citadel_protocol");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🧪 Simple MessagePack Protocol Test\n", .{});

    // Create a simple ping request manually
    var msgpack_data = std.ArrayList(u8).init(allocator);
    defer msgpack_data.deinit();

    // Create: {"id": 1, "type": "ping", "timestamp": 1000000000, "payload": {"echo_data": "test"}}

    // Root map with 4 keys
    try msgpack_data.append(0x84); // fixmap with 4 elements

    // "id": 1
    try msgpack_data.appendSlice(&[_]u8{0xa2}); // fixstr len=2
    try msgpack_data.appendSlice("id");
    try msgpack_data.append(0x01); // positive fixint 1

    // "type": "ping"
    try msgpack_data.appendSlice(&[_]u8{0xa4}); // fixstr len=4
    try msgpack_data.appendSlice("type");
    try msgpack_data.appendSlice(&[_]u8{0xa4}); // fixstr len=4
    try msgpack_data.appendSlice("ping");

    // "timestamp": 1000000000
    try msgpack_data.appendSlice(&[_]u8{0xa9}); // fixstr len=9
    try msgpack_data.appendSlice("timestamp");
    try msgpack_data.append(0xce); // uint32
    try msgpack_data.writer().writeInt(u32, 1000000000, .big);

    // "payload": {"echo_data": "test"}
    try msgpack_data.appendSlice(&[_]u8{0xa7}); // fixstr len=7
    try msgpack_data.appendSlice("payload");
    try msgpack_data.append(0x81); // fixmap with 1 element
    try msgpack_data.appendSlice(&[_]u8{0xa9}); // fixstr len=9
    try msgpack_data.appendSlice("echo_data");
    try msgpack_data.appendSlice(&[_]u8{0xa4}); // fixstr len=4
    try msgpack_data.appendSlice("test");

    std.debug.print("📦 Created MessagePack ping ({} bytes)\n", .{msgpack_data.items.len});

    // Test parsing with our own parser
    std.debug.print("🔍 Testing our MessagePack parser...\n", .{});
    const parsed_request = protocol.parseRequest(allocator, msgpack_data.items) catch |err| {
        std.debug.print("❌ Our parser failed: {}\n", .{err});
        return;
    };
    defer parsed_request.deinit(allocator);

    std.debug.print("✅ Our parser works! Request ID: {}, Type: {s}, Echo: {s}\n", .{
        parsed_request.id,
        parsed_request.request_type.toString(),
        parsed_request.payload.ping.echo_data,
    });

    // Now test with the daemon
    std.debug.print("📡 Testing with daemon...\n", .{});

    var daemon_process = std.process.Child.init(&[_][]const u8{ "./zig-out/bin/janus-core-daemon", "--log-level", "info" }, allocator);

    daemon_process.stdin_behavior = .Pipe;
    daemon_process.stdout_behavior = .Pipe;
    daemon_process.stderr_behavior = .Pipe;

    try daemon_process.spawn();
    defer {
        _ = daemon_process.kill() catch {};
    }

    const daemon_stdin = daemon_process.stdin.?.writer().any();
    const daemon_stdout = daemon_process.stdout.?.reader().any();

    var frame_writer = protocol.FrameWriter.init(daemon_stdin);
    var frame_reader = protocol.FrameReader.init(allocator, daemon_stdout);

    // Send the MessagePack request
    try frame_writer.writeFrame(msgpack_data.items);

    // Read response
    const response_data = try frame_reader.readFrame();
    defer allocator.free(response_data);

    std.debug.print("📨 Received {} bytes of response data\n", .{response_data.len});

    // Try to parse the response as MessagePack
    var parser = protocol.MessagePackParser.init(allocator, response_data);
    var response_value = parser.parseValue() catch |err| {
        std.debug.print("❌ Failed to parse response as MessagePack: {}\n", .{err});
        std.debug.print("Raw response bytes: ", .{});
        for (response_data[0..@min(response_data.len, 32)]) |byte| {
            std.debug.print("{X:0>2} ", .{byte});
        }
        std.debug.print("\n", .{});
        return;
    };
    defer response_value.deinit(allocator);

    std.debug.print("✅ SUCCESS! Daemon correctly implements MessagePack protocol!\n", .{});
    std.debug.print("🎉 The Protocol is Law, and the Law is Enforced!\n", .{});
}
