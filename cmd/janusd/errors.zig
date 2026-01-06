// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const json_helpers = @import("json_helpers.zig");

pub const ErrorKind = enum {
    ValidationError,
    AuthenticationError,
    AuthorizationError,
    ToolNotFoundError,
    ToolCallError,
};

pub fn kindName(kind: ErrorKind) []const u8 {
    return switch (kind) {
        .ValidationError => "ValidationError",
        .AuthenticationError => "AuthenticationError",
        .AuthorizationError => "AuthorizationError",
        .ToolNotFoundError => "ToolNotFoundError",
        .ToolCallError => "ToolCallError",
    };
}

pub const HttpStatus = struct { code: u16, text: []const u8 };

pub fn statusFor(kind: ErrorKind) HttpStatus {
    return switch (kind) {
        .ValidationError => .{ .code = 400, .text = "Bad Request" },
        .AuthenticationError => .{ .code = 401, .text = "Unauthorized" },
        .AuthorizationError => .{ .code = 403, .text = "Forbidden" },
        .ToolNotFoundError => .{ .code = 404, .text = "Not Found" },
        .ToolCallError => .{ .code = 500, .text = "Internal Server Error" },
    };
}

pub fn writeError(w: anytype, kind: ErrorKind, message: []const u8) !void {
    try json_helpers.writeMinified(w, .{ .type = kindName(kind), .message = message });
}

pub fn writeErrorWithDetails(w: anytype, kind: ErrorKind, message: []const u8, details: anytype) !void {
    try json_helpers.writeMinified(w, .{ .type = kindName(kind), .message = message, .details = details });
}

// --------------- Tests ---------------

test "statusFor maps kinds to HTTP status" {
    const s1 = statusFor(.ValidationError);
    try std.testing.expectEqual(@as(u16, 400), s1.code);
    try std.testing.expectEqualStrings("Bad Request", s1.text);
    const s2 = statusFor(.AuthenticationError);
    try std.testing.expectEqual(@as(u16, 401), s2.code);
    const s3 = statusFor(.AuthorizationError);
    try std.testing.expectEqual(@as(u16, 403), s3.code);
    const s4 = statusFor(.ToolNotFoundError);
    try std.testing.expectEqual(@as(u16, 404), s4.code);
    const s5 = statusFor(.ToolCallError);
    try std.testing.expectEqual(@as(u16, 500), s5.code);
}

test "writeError emits type and message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var buf = std.ArrayList(u8){}; defer buf.deinit(a);
    try writeError(buf.writer(a), .ValidationError, "bad");
    const s = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, s, "\"type\":\"ValidationError\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"message\":\"bad\"") != null);
}
