// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! NS-Msg: Effect Definitions (Zig 0.15+ compatible)

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const envelope = @import("envelope.zig");
const Path = types.Path;
const Pattern = types.Pattern;
const Envelope = envelope.Envelope;

pub const NetworkError = error{
    ConnectionFailed,
    Timeout,
    InvalidPath,
    SerializationFailed,
    TransportError,
    NotConnected,
    SubscriptionClosed,
    QueryCancelled,
};

pub const NsEffect = enum {
    publish,
    subscribe,
    query,
    respond,
    cancel,

    pub fn toString(self: NsEffect) []const u8 {
        return switch (self) {
            .publish => "NS.publish",
            .subscribe => "NS.subscribe",
            .query => "NS.query",
            .respond => "NS.respond",
            .cancel => "NS.cancel",
        };
    }
};

pub fn Subscription(comptime T: type) type {
    _ = T;
    return struct {
        const Self = @This();

        pattern: Pattern,
        is_active: bool,

        pub fn init(allocator: Allocator, pattern: Pattern) Self {
            _ = allocator;
            return .{
                .pattern = pattern,
                .is_active = true,
            };
        }

        pub fn deinit(self: *Self) void {
            self.is_active = false;
            self.pattern.deinit();
        }

        pub fn matches(self: Self, path: Path) bool {
            return self.pattern.matchesPath(path);
        }
    };
}

pub fn QueryHandle(comptime R: type) type {
    return struct {
        const Self = @This();

        responses: std.ArrayList(R),
        allocator: Allocator,
        timeout_ms: u32,
        query_id: u128,
        is_active: bool,
        start_time: i64,

        pub fn init(allocator: Allocator, timeout_ms: u32, query_id: u128) Self {
            return .{
                .responses = .empty,
                .allocator = allocator,
                .timeout_ms = timeout_ms,
                .query_id = query_id,
                .is_active = true,
                .start_time = std.time.milliTimestamp(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.is_active = false;
            self.responses.deinit(self.allocator);
        }

        pub fn addResponse(self: *Self, response: R) !void {
            if (!self.is_active) return;
            try self.responses.append(self.allocator, response);
        }
    };
}

pub const NsContext = struct {
    allocator: Allocator,
};

pub fn generateQueryId() u128 {
    const timestamp = @as(u128, @intCast(std.time.nanoTimestamp())) << 64;
    const random = std.crypto.random.int(u64);
    return timestamp | random;
}

const testing = std.testing;

test "Subscription matching" {
    const allocator = testing.allocator;

    const pattern = try Pattern.parse(allocator, "sensor/+/pm25");
    // Note: pattern ownership moves to subscription, no defer needed here

    var sub = Subscription(envelope.SensorReading).init(allocator, pattern);
    defer sub.deinit(); // This will deinit the pattern

    var path = try types.Path.parse(allocator, "sensor/berlin/pm25");
    defer path.deinit();

    try testing.expect(sub.matches(path));
}

test "QueryHandle operations" {
    const allocator = testing.allocator;

    const query_id = generateQueryId();
    var handle = QueryHandle(i32).init(allocator, 1000, query_id);
    defer handle.deinit();

    try handle.addResponse(42);
    try handle.addResponse(43);

    try testing.expectEqual(@as(usize, 2), handle.responses.items.len);
}

test "NsEffect strings" {
    try testing.expectEqualStrings("NS.publish", NsEffect.publish.toString());
    try testing.expectEqualStrings("NS.subscribe", NsEffect.subscribe.toString());
    try testing.expectEqualStrings("NS.query", NsEffect.query.toString());
    try testing.expectEqualStrings("NS.respond", NsEffect.respond.toString());
}
