// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub const ParseError = error{ InvalidFormat };

pub const Token = struct {
    action: []const u8,   // namespace.verb
    resource: []const u8, // part after ':'
};

/// Parse canonical token: "namespace.verb:<resource>"
pub fn parseToken(tok: []const u8) ParseError!Token {
    const idx = std.mem.indexOfScalar(u8, tok, ':') orelse return error.InvalidFormat;
    const action = std.mem.trim(u8, tok[0..idx], " \t");
    const resource = std.mem.trim(u8, tok[idx + 1 ..], " \t");
    if (action.len == 0 or resource.len == 0) return error.InvalidFormat;
    if (std.mem.indexOfScalar(u8, action, '.') == null) return error.InvalidFormat; // require namespace.verb
    return .{ .action = action, .resource = resource };
}

/// Compute which required tokens are missing from presented.
pub fn computeMissing(
    allocator: std.mem.Allocator,
    presented: []const []const u8,
    required: []const []const u8,
) ![]const []const u8 {
    var set = std.StringHashMap(void).init(allocator);
    defer set.deinit();
    for (presented) |p| {
        _ = try set.put(p, {});
    }
    var missing = std.ArrayList([]const u8){};
    errdefer missing.deinit(allocator);
    for (required) |r| {
        if (!set.contains(r)) {
            try missing.append(allocator, r);
        }
    }
    return try missing.toOwnedSlice(allocator);
}

test "parseToken accepts canonical tokens" {
    const t = try parseToken("fs.read:${WORKSPACE}");
    try std.testing.expectEqualStrings("fs.read", t.action);
    try std.testing.expectEqualStrings("${WORKSPACE}", t.resource);
}

test "parseToken rejects invalid formats" {
    try std.testing.expectError(error.InvalidFormat, parseToken("read"));
    try std.testing.expectError(error.InvalidFormat, parseToken("fs.read:"));
    try std.testing.expectError(error.InvalidFormat, parseToken(":/etc"));
    try std.testing.expectError(error.InvalidFormat, parseToken("fs:/etc"));
}
