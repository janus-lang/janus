// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! NS-Msg: Core Types (Path and Pattern)
//! Uses Zig 0.15+ ArrayList API with .empty initialization

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Segment = union(enum) {
    literal: []const u8,
    single_wildcard,
    multi_wildcard,

    pub fn format(
        self: Segment,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .literal => |s| try writer.writeAll(s),
            .single_wildcard => try writer.writeByte('+'),
            .multi_wildcard => try writer.writeByte('*'),
        }
    }

    pub fn eql(self: Segment, other: Segment) bool {
        return switch (self) {
            .literal => |s| switch (other) {
                .literal => |o| std.mem.eql(u8, s, o),
                else => false,
            },
            .single_wildcard => other == .single_wildcard,
            .multi_wildcard => other == .multi_wildcard,
        };
    }

    pub fn isWildcard(self: Segment) bool {
        return self == .single_wildcard or self == .multi_wildcard;
    }
};

pub const Path = struct {
    const Self = @This();

    segments: []Segment,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return .{
            .segments = &.{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.segments) |seg| {
            if (seg == .literal) {
                self.allocator.free(seg.literal);
            }
        }
        self.allocator.free(self.segments);
        self.segments = &.{};
    }

    pub fn parse(allocator: Allocator, path_str: []const u8) !Self {
        var path = Self.init(allocator);

        var list: std.ArrayList(Segment) = .empty;
        defer list.deinit(allocator);

        var it = std.mem.splitScalar(u8, path_str, '/');
        while (it.next()) |segment| {
            if (segment.len == 0) continue;
            const seg = try allocator.dupe(u8, segment);
            try list.append(allocator, .{ .literal = seg });
        }

        path.segments = try list.toOwnedSlice(allocator);
        return path;
    }

    pub fn append(self: *Self, segment: []const u8) !void {
        const seg = try self.allocator.dupe(u8, segment);

        var list = std.ArrayList(Segment).fromOwnedSlice(self.segments);
        try list.append(self.allocator, Segment{ .literal = seg });
        self.segments = try list.toOwnedSlice(self.allocator);
    }

    pub fn toString(self: Self, allocator: Allocator) ![]const u8 {
        if (self.segments.len == 0) {
            return try allocator.dupe(u8, "");
        }

        var total_len: usize = 0;
        for (self.segments) |seg| {
            total_len += switch (seg) {
                .literal => |s| s.len,
                .single_wildcard => 1,
                .multi_wildcard => 1,
            };
        }
        total_len += self.segments.len - 1;

        var result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;

        for (self.segments, 0..) |seg, i| {
            if (i > 0) {
                result[pos] = '/';
                pos += 1;
            }
            const s = switch (seg) {
                .literal => |s| s,
                .single_wildcard => "+",
                .multi_wildcard => "*",
            };
            @memcpy(result[pos..pos + s.len], s);
            pos += s.len;
        }

        return result;
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        for (self.segments, 0..) |seg, i| {
            if (i > 0) try writer.writeByte('/');
            try writer.print("{}", .{seg});
        }
    }

    pub fn eql(self: Self, other: Self) bool {
        if (self.segments.len != other.segments.len) return false;
        for (self.segments, other.segments) |a, b| {
            if (!a.eql(b)) return false;
        }
        return true;
    }

    pub fn len(self: Self) usize {
        return self.segments.len;
    }

    pub fn get(self: Self, index: usize) ?Segment {
        if (index >= self.segments.len) return null;
        return self.segments[index];
    }
};

pub const Pattern = struct {
    const Self = @This();

    segments: []Segment,
    allocator: Allocator,
    needs_network: bool,

    pub fn init(allocator: Allocator) Self {
        return .{
            .segments = &.{},
            .allocator = allocator,
            .needs_network = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.segments) |seg| {
            if (seg == .literal) {
                self.allocator.free(seg.literal);
            }
        }
        self.allocator.free(self.segments);
        self.segments = &.{};
    }

    pub fn parse(allocator: Allocator, pattern_str: []const u8) !Self {
        var pattern = Self.init(allocator);

        var list: std.ArrayList(Segment) = .empty;
        defer list.deinit(allocator);

        var it = std.mem.splitScalar(u8, pattern_str, '/');
        while (it.next()) |segment| {
            if (segment.len == 0) continue;

            const seg: Segment = if (std.mem.eql(u8, segment, "+"))
                .single_wildcard
            else if (std.mem.eql(u8, segment, "*"))
                .multi_wildcard
            else
                .{ .literal = try allocator.dupe(u8, segment) };

            try list.append(allocator, seg);
            if (seg.isWildcard()) {
                pattern.needs_network = true;
            }
        }

        pattern.segments = try list.toOwnedSlice(allocator);
        return pattern;
    }

    pub fn appendLiteral(self: *Self, segment: []const u8) !void {
        const seg = try self.allocator.dupe(u8, segment);

        var list = std.ArrayList(Segment).fromOwnedSlice(self.segments);
        try list.append(self.allocator, Segment{ .literal = seg });
        self.segments = try list.toOwnedSlice(self.allocator);
    }

    pub fn appendSingleWildcard(self: *Self) !void {
        var list = std.ArrayList(Segment).fromOwnedSlice(self.segments);
        try list.append(self.allocator, .single_wildcard);
        self.segments = try list.toOwnedSlice(self.allocator);
        self.needs_network = true;
    }

    pub fn appendMultiWildcard(self: *Self) !void {
        var list = std.ArrayList(Segment).fromOwnedSlice(self.segments);
        try list.append(self.allocator, .multi_wildcard);
        self.segments = try list.toOwnedSlice(self.allocator);
        self.needs_network = true;
    }

    pub fn matchesPath(self: Self, path: Path) bool {
        var pattern_idx: usize = 0;
        var path_idx: usize = 0;

        while (pattern_idx < self.segments.len and path_idx < path.segments.len) {
            const pat_seg = self.segments[pattern_idx];
            const path_seg = path.segments[path_idx];

            switch (pat_seg) {
                .literal => |lit| {
                    if (path_seg != .literal) return false;
                    if (!std.mem.eql(u8, lit, path_seg.literal)) return false;
                    pattern_idx += 1;
                    path_idx += 1;
                },
                .single_wildcard => {
                    pattern_idx += 1;
                    path_idx += 1;
                },
                .multi_wildcard => {
                    if (pattern_idx + 1 >= self.segments.len) {
                        return true;
                    }
                    pattern_idx += 1;
                },
            }
        }

        const pattern_done = pattern_idx >= self.segments.len;
        const path_done = path_idx >= path.segments.len;

        if (pattern_done and path_done) return true;

        while (pattern_idx < self.segments.len) {
            if (self.segments[pattern_idx] != .multi_wildcard) return false;
            pattern_idx += 1;
        }

        return pattern_done == path_done;
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        for (self.segments, 0..) |seg, i| {
            if (i > 0) try writer.writeByte('/');
            try writer.print("{}", .{seg});
        }
    }

    pub fn eql(self: Self, other: Self) bool {
        if (self.segments.len != other.segments.len) return false;
        for (self.segments, other.segments) |a, b| {
            if (!a.eql(b)) return false;
        }
        return true;
    }

    pub fn hasWildcards(self: Self) bool {
        for (self.segments) |seg| {
            if (seg.isWildcard()) return true;
        }
        return false;
    }

    pub fn len(self: Self) usize {
        return self.segments.len;
    }
};

const testing = std.testing;

test "Path parsing and formatting" {
    const allocator = testing.allocator;

    var path = try Path.parse(allocator, "sensor/berlin/pm25");
    defer path.deinit();

    try testing.expectEqual(@as(usize, 3), path.len());
    try testing.expect(path.get(0).?.eql(.{ .literal = "sensor" }));
    try testing.expect(path.get(1).?.eql(.{ .literal = "berlin" }));
    try testing.expect(path.get(2).?.eql(.{ .literal = "pm25" }));

    const str = try path.toString(allocator);
    defer allocator.free(str);
    try testing.expectEqualStrings("sensor/berlin/pm25", str);
}

test "Pattern with wildcards" {
    const allocator = testing.allocator;

    var pattern = try Pattern.parse(allocator, "sensor/+/pm25");
    defer pattern.deinit();

    try testing.expectEqual(@as(usize, 3), pattern.len());
    try testing.expect(pattern.hasWildcards());

    var path1 = try Path.parse(allocator, "sensor/berlin/pm25");
    defer path1.deinit();
    try testing.expect(pattern.matchesPath(path1));

    var path2 = try Path.parse(allocator, "sensor/london/pm25");
    defer path2.deinit();
    try testing.expect(pattern.matchesPath(path2));

    var path3 = try Path.parse(allocator, "sensor/berlin/temperature");
    defer path3.deinit();
    try testing.expect(!pattern.matchesPath(path3));
}

test "Pattern with multi-wildcard" {
    const allocator = testing.allocator;

    var pattern = try Pattern.parse(allocator, "sensor/*");
    defer pattern.deinit();

    var path1 = try Path.parse(allocator, "sensor/berlin/pm25");
    defer path1.deinit();
    try testing.expect(pattern.matchesPath(path1));

    var path2 = try Path.parse(allocator, "sensor/london");
    defer path2.deinit();
    try testing.expect(pattern.matchesPath(path2));

    var path3 = try Path.parse(allocator, "feed/berlin/post1");
    defer path3.deinit();
    try testing.expect(!pattern.matchesPath(path3));
}
