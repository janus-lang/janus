// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! NS-Msg: Message Envelope and Serialization

const std = @import("std");
const compat_time = @import("compat_time");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const Path = types.Path;
const Pattern = types.Pattern;

/// Message envelope containing payload and metadata
pub fn Envelope(comptime T: type) type {
    return struct {
        const Self = @This();

        path: Path,
        payload: T,
        timestamp: u64,
        sequence: u64,
        query_id: ?u128,
        reply_path: ?Path,
        expect_multiple: bool,

        pub fn init(allocator: Allocator, path: Path, payload: T) !Self {
            _ = allocator;
            return .{
                .path = path,
                .payload = payload,
                .timestamp = @intCast(compat_time.nanoTimestamp()),
                .sequence = 0,
                .query_id = null,
                .reply_path = null,
                .expect_multiple = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.path.deinit();
            if (self.reply_path) |*rp| {
                rp.deinit();
            }
        }
    };
}

/// Payload type for sensor readings
pub const SensorReading = struct {
    value: f64,
    unit: []const u8,
    timestamp: u64,
    geohash: []const u8,
};

/// Payload type for feed posts
pub const FeedPost = struct {
    author: []const u8,
    content: []const u8,
    entropy: u64,
};

/// Payload type for query requests
pub const QueryRequest = struct {
    operation: []const u8,
    params: std.json.Value,
};

/// Payload type for query responses
pub const QueryResponse = struct {
    success: bool,
    data: std.json.Value,
    error_message: ?[]const u8,
};

// Test suite
const testing = std.testing;

test "Envelope creation" {
    const allocator = testing.allocator;

    // Build path - ownership moves to envelope
    var path = types.Path.init(allocator);
    try path.append("sensor");
    try path.append("berlin");
    try path.append("pm25");

    const reading = SensorReading{
        .value = 42.5,
        .unit = "µg/m³",
        .timestamp = 1234567890,
        .geohash = "u33dc0",
    };

    var envelope = try Envelope(SensorReading).init(allocator, path, reading);
    defer envelope.deinit(); // This deinits the path

    try testing.expectEqual(@as(u64, 1234567890), envelope.payload.timestamp);
    try testing.expect(envelope.query_id == null);
}
