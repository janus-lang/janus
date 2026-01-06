// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! DocUpdate Integration Test
//!
//! This test verifies that the DocUpdate handler correctly integrates with
//! libjanus to parse Janus source code and create ASTDB snapshots.

const std = @import("std");
const protocol = @import("citadel_protocol");

fn createDocUpdateRequest(allocator: std.mem.Allocator, uri: []const u8, content: []const u8) ![]u8 {
    var encoder = protocol.MessagePackEncoder.init(allocator);
    defer encoder.deinit();

    // Create: {"id": 1, "type": "doc_update", "timestamp": 1000000000, "payload": {"uri": uri, "content": content}}

    try encoder.encodeMap(4); // id, type, timestamp, payload

    // "id": 1
    try encoder.encodeString("id");
    try encoder.encodeUint32(1);

    // "type": "doc_update"
    try encoder.encodeString("type");
    try encoder.encodeString("doc_update");

    // "timestamp": 1000000000
    try encoder.encodeString("timestamp");
    try encoder.encodeUint32(1000000000);

    // "payload": {"uri": uri, "content": content}
    try encoder.encodeString("payload");
    try encoder.encodeMap(2); // uri, content
    try encoder.encodeString("uri");
    try encoder.encodeString(uri);
    try encoder.encodeString("content");
    try encoder.encodeString(content);

    return try allocator.dupe(u8, encoder.getBytes());
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🧪 Testing DocUpdate Integration with libjanus\n", .{});

    // Test Janus source code
    const test_uri = "file:///test.jan";
    const test_content =
        \\func main() {
        \\    let x := 42;
        \\    print("Hello, Janus!");
        \\}
    ;

    std.debug.print("📄 Test document: {s}\n", .{test_uri});
    std.debug.print("📝 Content ({} bytes):\n{s}\n", .{ test_content.len, test_content });

    // Create MessagePack DocUpdate request
    const request_data = try createDocUpdateRequest(allocator, test_uri, test_content);
    defer allocator.free(request_data);

    std.debug.print("📦 Created DocUpdate request ({} bytes)\n", .{request_data.len});

    // Start the core daemon
    var daemon_process = std.process.Child.init(&[_][]const u8{ "./zig-out/bin/janus-core-daemon", "--log-level", "debug" }, allocator);

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

    std.debug.print("📡 Sending DocUpdate request to daemon...\n", .{});

    // Send the DocUpdate request
    try frame_writer.writeFrame(request_data);

    // Read response
    const response_data = try frame_reader.readFrame();
    defer allocator.free(response_data);

    std.debug.print("📨 Received {} bytes of response data\n", .{response_data.len});

    // Parse the response
    var parser = protocol.MessagePackParser.init(allocator, response_data);
    var response_value = try parser.parseValue();
    defer response_value.deinit(allocator);

    // Validate response structure
    const response_id = (response_value.getMapValue("id") orelse {
        std.debug.print("❌ Missing 'id' field in response\n", .{});
        return;
    }).getInteger() orelse {
        std.debug.print("❌ Invalid 'id' field type\n", .{});
        return;
    };

    const response_type = (response_value.getMapValue("type") orelse {
        std.debug.print("❌ Missing 'type' field in response\n", .{});
        return;
    }).getString() orelse {
        std.debug.print("❌ Invalid 'type' field type\n", .{});
        return;
    };

    const response_status = (response_value.getMapValue("status") orelse {
        std.debug.print("❌ Missing 'status' field in response\n", .{});
        return;
    }).getString() orelse {
        std.debug.print("❌ Invalid 'status' field type\n", .{});
        return;
    };

    std.debug.print("📋 Response: ID={}, Type={s}, Status={s}\n", .{ response_id, response_type, response_status });

    // Validate response values
    if (response_id != 1) {
        std.debug.print("❌ Wrong response ID: expected 1, got {}\n", .{response_id});
        return;
    }

    if (!std.mem.eql(u8, response_type, "doc_update_response")) {
        std.debug.print("❌ Wrong response type: expected 'doc_update_response', got '{s}'\n", .{response_type});
        return;
    }

    if (!std.mem.eql(u8, response_status, "success")) {
        std.debug.print("❌ DocUpdate failed: status = {s}\n", .{response_status});

        // Check for error details
        if (response_value.getMapValue("error_info")) |error_value| {
            if (error_value.getMapValue("message")) |msg_value| {
                if (msg_value.getString()) |error_msg| {
                    std.debug.print("💥 Error: {s}\n", .{error_msg});
                }
            }
            if (error_value.getMapValue("code")) |code_value| {
                if (code_value.getString()) |error_code| {
                    std.debug.print("🔢 Error Code: {s}\n", .{error_code});
                }
            }
        }
        return;
    }

    // Extract payload details
    const payload_value = response_value.getMapValue("payload") orelse {
        std.debug.print("❌ Missing payload in successful response\n", .{});
        return;
    };

    const success_value = payload_value.getMapValue("success") orelse {
        std.debug.print("❌ Missing 'success' field in payload\n", .{});
        return;
    };

    const success = success_value.getBoolean() orelse {
        std.debug.print("❌ Invalid 'success' field type\n", .{});
        return;
    };

    if (!success) {
        std.debug.print("❌ DocUpdate reported failure\n", .{});
        return;
    }

    // Extract parsing metrics
    var snapshot_id: ?[]const u8 = null;
    var parse_time_ns: ?u64 = null;
    var token_count: ?u32 = null;
    var node_count: ?u32 = null;

    if (payload_value.getMapValue("snapshot_id")) |sid_value| {
        snapshot_id = sid_value.getString();
    }

    if (payload_value.getMapValue("parse_time_ns")) |pt_value| {
        parse_time_ns = @as(u64, @intCast(pt_value.getInteger() orelse 0));
    }

    if (payload_value.getMapValue("token_count")) |tc_value| {
        token_count = @as(u32, @intCast(tc_value.getInteger() orelse 0));
    }

    if (payload_value.getMapValue("node_count")) |nc_value| {
        node_count = @as(u32, @intCast(nc_value.getInteger() orelse 0));
    }

    std.debug.print("✅ DocUpdate SUCCESS!\n", .{});
    std.debug.print("📊 Parsing Results:\n", .{});
    if (snapshot_id) |sid| {
        std.debug.print("  🔗 Snapshot ID: {s}\n", .{sid});
    }
    if (parse_time_ns) |pt| {
        std.debug.print("  ⏱️  Parse Time: {}ns ({:.2}ms)\n", .{ pt, @as(f64, @floatFromInt(pt)) / 1_000_000.0 });
    }
    if (token_count) |tc| {
        std.debug.print("  🔤 Tokens: {}\n", .{tc});
    }
    if (node_count) |nc| {
        std.debug.print("  🌳 AST Nodes: {}\n", .{nc});
    }

    // Validate that we got reasonable parsing results
    if (token_count == null or token_count.? == 0) {
        std.debug.print("⚠️  Warning: No tokens parsed - possible parsing issue\n", .{});
    }

    if (node_count == null or node_count.? == 0) {
        std.debug.print("⚠️  Warning: No AST nodes created - possible parsing issue\n", .{});
    }

    std.debug.print("🎉 The Citadel is Armed! libjanus integration successful!\n", .{});
}
