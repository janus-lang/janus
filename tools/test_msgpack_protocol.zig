// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! MessagePack Protocol Test for Janus Core Daemon
//!
//! This test demonstrates that the current daemon implementation does NOT
//! properly implement MessagePack as specified in the Citadel Protocol.
//! It sends actual MessagePack data and shows the daemon fails to parse it.

const std = @import("std");
const protocol = @import("citadel_protocol");

// Simple MessagePack encoder for testing
const MessagePackEncoder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) MessagePackEncoder {
        return .{
            .allocator = allocator,
            .buffer = .empty,
        };
    }

    pub fn deinit(self: *MessagePackEncoder) void {
        self.buffer.deinit();
    }

    pub fn encodeMap(self: *MessagePackEncoder, size: u8) !void {
        if (size <= 15) {
            try self.buffer.append(0x80 | size); // fixmap
        } else {
            return error.MapTooLarge;
        }
    }

    pub fn encodeString(self: *MessagePackEncoder, str: []const u8) !void {
        if (str.len <= 31) {
            try self.buffer.append(0xa0 | @as(u8, @intCast(str.len))); // fixstr
        } else if (str.len <= 255) {
            try self.buffer.append(0xd9); // str 8
            try self.buffer.append(@as(u8, @intCast(str.len)));
        } else {
            return error.StringTooLong;
        }
        try self.buffer.appendSlice(str);
    }

    pub fn encodeUint32(self: *MessagePackEncoder, value: u32) !void {
        if (value <= 127) {
            try self.buffer.append(@as(u8, @intCast(value))); // positive fixint
        } else {
            try self.buffer.append(0xce); // uint 32
            try self.buffer.writer().writeInt(u32, value, .big);
        }
    }

    pub fn encodeUint64(self: *MessagePackEncoder, value: u64) !void {
        try self.buffer.append(0xcf); // uint 64
        try self.buffer.writer().writeInt(u64, value, .big);
    }

    pub fn getBytes(self: *MessagePackEncoder) []const u8 {
        return self.buffer.items;
    }
};

fn createMessagePackPingRequest(allocator: std.mem.Allocator) ![]u8 {
    var encoder = MessagePackEncoder.init(allocator);
    defer encoder.deinit();

    // Encode: {"id": 1, "type": "ping", "timestamp": 1725634800000000000, "payload": {"echo_data": "msgpack_test"}}

    // Root map with 4 keys
    try encoder.encodeMap(4);

    // "id": 1
    try encoder.encodeString("id");
    try encoder.encodeUint32(1);

    // "type": "ping"
    try encoder.encodeString("type");
    try encoder.encodeString("ping");

    // "timestamp": 1725634800000000000
    try encoder.encodeString("timestamp");
    try encoder.encodeUint64(1725634800000000000);

    // "payload": {"echo_data": "msgpack_test"}
    try encoder.encodeString("payload");
    try encoder.encodeMap(1); // payload map with 1 key
    try encoder.encodeString("echo_data");
    try encoder.encodeString("msgpack_test");

    return try allocator.dupe(u8, encoder.getBytes());
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🧪 Testing MessagePack Protocol Implementation\n", .{});

    // Create actual MessagePack data
    const msgpack_data = try createMessagePackPingRequest(allocator);
    defer allocator.free(msgpack_data);

    std.debug.print("📦 Created MessagePack payload ({} bytes): ", .{msgpack_data.len});
    for (msgpack_data) |byte| {
        std.debug.print("{X:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});

    // Start the core daemon
    var daemon_process = std.process.Child.init(&[_][]const u8{ "./zig-out/bin/janus-core-daemon", "--log-level", "debug" }, allocator);

    daemon_process.stdin_behavior = .Pipe;
    daemon_process.stdout_behavior = .Pipe;
    daemon_process.stderr_behavior = .Pipe;

    try daemon_process.spawn();
    defer {
        _ = daemon_process.kill() catch {};
    }

    // Set up communication
    const daemon_stdin = daemon_process.stdin.?.writer().any();
    const daemon_stdout = daemon_process.stdout.?.reader().any();

    var frame_writer = protocol.FrameWriter.init(daemon_stdin);
    var frame_reader = protocol.FrameReader.init(allocator, daemon_stdout);

    std.debug.print("📡 Sending MessagePack ping request to daemon...\n", .{});

    // Send the MessagePack data
    try frame_writer.writeFrame(msgpack_data);

    // Try to read response
    const response_data = frame_reader.readFrame() catch |err| {
        std.debug.print("❌ Failed to read response: {}\n", .{err});

        // Read stderr to see daemon error
        var stderr_buffer: [1024]u8 = undefined;
        if (daemon_process.stderr.?.readAll(&stderr_buffer)) |bytes_read| {
            if (bytes_read > 0) {
                std.debug.print("🔍 Daemon stderr: {s}\n", .{stderr_buffer[0..bytes_read]});
            }
        } else |_| {}

        std.debug.print("💥 PROOF: The daemon does NOT implement MessagePack!\n", .{});
        std.debug.print("💥 It fails to parse actual MessagePack data as required by the spec.\n", .{});
        return;
    };
    defer allocator.free(response_data);

    std.debug.print("📨 Received response: {s}\n", .{response_data});
    std.debug.print("✅ If you see this, the daemon somehow handled MessagePack (unexpected!)\n", .{});
}
