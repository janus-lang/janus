// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Test tool for the Janus Core Daemon
//!
//! This tool tests the basic functionality of the core daemon by sending
//! protocol messages and verifying responses.

const std = @import("std");
const protocol = @import("citadel_protocol");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🧪 Testing Janus Core Daemon\n", .{});

    // Start the core daemon as a subprocess
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

    // Test 1: Send a ping request
    std.debug.print("📡 Sending ping request...\n", .{});

    const ping_request =
        \\{"id":1,"type":"ping","timestamp":1725634800000000000,"payload":{"echo_data":"test_ping_123"}}
    ;

    try frame_writer.writeFrame(ping_request);

    // Read response
    const response_data = try frame_reader.readFrame();
    defer allocator.free(response_data);

    std.debug.print("📨 Received response: {s}\n", .{response_data});

    // Parse and validate response
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_data, .{});
    defer parsed.deinit();

    const response_obj = parsed.value.object;
    const response_id = @as(u32, @intCast(response_obj.get("id").?.integer));
    const response_type = response_obj.get("type").?.string;
    const response_status = response_obj.get("status").?.string;

    if (response_id != 1) {
        std.debug.print("❌ Wrong response ID: expected 1, got {}\n", .{response_id});
        return;
    }

    if (!std.mem.eql(u8, response_type, "ping_response")) {
        std.debug.print("❌ Wrong response type: expected 'ping_response', got '{s}'\n", .{response_type});
        return;
    }

    if (!std.mem.eql(u8, response_status, "success")) {
        std.debug.print("❌ Wrong response status: expected 'success', got '{s}'\n", .{response_status});
        return;
    }

    const payload = response_obj.get("payload").?.object;
    const echo_data = payload.get("echo_data").?.string;

    if (!std.mem.eql(u8, echo_data, "test_ping_123")) {
        std.debug.print("❌ Wrong echo data: expected 'test_ping_123', got '{s}'\n", .{echo_data});
        return;
    }

    std.debug.print("✅ Ping test passed!\n", .{});

    // Test 2: Send shutdown request
    std.debug.print("🛑 Sending shutdown request...\n", .{});

    const shutdown_request =
        \\{"id":2,"type":"shutdown","timestamp":1725634800000000000,"payload":{"reason":"test_complete","timeout_ms":1000}}
    ;

    try frame_writer.writeFrame(shutdown_request);

    // Read shutdown response
    const shutdown_response_data = try frame_reader.readFrame();
    defer allocator.free(shutdown_response_data);

    std.debug.print("📨 Received shutdown response: {s}\n", .{shutdown_response_data});

    // Wait for daemon to exit
    const exit_status = try daemon_process.wait();
    if (exit_status != .Exited or exit_status.Exited != 0) {
        std.debug.print("❌ Daemon exited with non-zero status\n", .{});
        return;
    }

    std.debug.print("✅ All tests passed! Core daemon is working correctly.\n", .{});
}
