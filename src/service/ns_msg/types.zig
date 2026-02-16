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

    pub fn clone(self: Self, allocator: Allocator) !Self {
        var new_path = Self.init(allocator);

        var list: std.ArrayList(Segment) = .empty;
        defer list.deinit(allocator);

        for (self.segments) |seg| {
            const new_seg: Segment = switch (seg) {
                .literal => |s| .{ .literal = try allocator.dupe(u8, s) },
                .single_wildcard => .single_wildcard,
                .multi_wildcard => .multi_wildcard,
            };
            try list.append(allocator, new_seg);
        }

        new_path.segments = try list.toOwnedSlice(allocator);
        return new_path;
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

/// Retained value entry for MQTT-style last-known-value delivery
/// RFC-0500 §3.5 compliant
pub const RetainedValue = struct {
    const Self = @This();

    path: Path,
    envelope_data: []const u8, // Serialized envelope bytes
    lamport_clock: u64,
    expires_at: ?u64, // Optional TTL (null = no expiration)
    delivery_count: u32,
    last_accessed: u64, // For LRU eviction

    pub fn init(
        allocator: Allocator,
        path: Path,
        envelope_data: []const u8,
        lamport_clock: u64,
        ttl_seconds: ?u64,
    ) !Self {
        const data_copy = try allocator.dupe(u8, envelope_data);
        errdefer allocator.free(data_copy);

        // Clone the path so caller retains ownership
        const path_clone = try path.clone(allocator);
        errdefer path_clone.deinit(allocator);

        const now = @as(u64, @intCast(std.time.timestamp()));
        const expires = if (ttl_seconds) |ttl| now + ttl else null;

        return .{
            .path = path_clone,
            .envelope_data = data_copy,
            .lamport_clock = lamport_clock,
            .expires_at = expires,
            .delivery_count = 0,
            .last_accessed = now,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.path.deinit();
        allocator.free(self.envelope_data);
    }

    /// Check if this retained value has expired
    pub fn isExpired(self: Self) bool {
        if (self.expires_at) |exp| {
            const now = @as(u64, @intCast(std.time.timestamp()));
            return now > exp;
        }
        return false;
    }

    /// Update access time and increment delivery count
    pub fn markDelivered(self: *Self) void {
        self.last_accessed = @as(u64, @intCast(std.time.timestamp()));
        self.delivery_count += 1;
    }
};

/// Options for publishing with retained value support
pub const PublishOptions = struct {
    retain: bool = false,
    lamport_clock: u64 = 0,
    ttl_seconds: ?u64 = null,
};

/// Callback for delivering retained values to new subscribers
pub const RetainedValueCallback = *const fn (
    ctx: *anyopaque,
    path: Path,
    envelope_data: []const u8,
    lamport_clock: u64,
) void;

/// Retained value cache with LRU eviction
/// RFC-0500 §3.5 compliant
pub const RetainedValueCache = struct {
    const Self = @This();

    allocator: Allocator,
    values: std.StringHashMap(RetainedValue),
    max_per_namespace: usize,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator, max_per_namespace: usize) Self {
        return .{
            .allocator = allocator,
            .values = std.StringHashMap(RetainedValue).init(allocator),
            .max_per_namespace = max_per_namespace,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.values.iterator();
        while (it.next()) |entry| {
            var value = entry.value_ptr;
            value.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.values.deinit();
    }

    /// Get or evict a retained value by path
    /// Returns null if not found or expired (evicts if expired)
    /// Caller owns the returned value and must deinit it
    pub fn getOrEvict(self: *Self, path: Path) ?RetainedValue {
        self.mutex.lock();
        defer self.mutex.unlock();

        const path_str = path.toString(self.allocator) catch return null;
        defer self.allocator.free(path_str);

        const entry = self.values.getEntry(path_str);
        if (entry == null) return null;

        var value = entry.?.value_ptr;

        // Check expiration
        if (value.isExpired()) {
            // Evict expired value
            var evicted = value.*;
            _ = self.values.remove(path_str);
            evicted.deinit(self.allocator);
            return null;
        }

        value.markDelivered();

        // Return a clone that the caller owns
        return RetainedValue.init(
            self.allocator,
            value.path,
            value.envelope_data,
            value.lamport_clock,
            if (value.expires_at) |exp| exp - @as(u64, @intCast(std.time.timestamp())) else null,
        ) catch return null;
    }

    /// Update or insert a retained value
    /// Uses Lamport clock for conflict resolution
    pub fn updateRetained(
        self: *Self,
        path: Path,
        envelope_data: []const u8,
        lamport_clock: u64,
        ttl_seconds: ?u64,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const path_str = try path.toString(self.allocator);
        errdefer self.allocator.free(path_str);

        // Check if value exists
        if (self.values.getEntry(path_str)) |entry| {
            const existing = entry.value_ptr;

            // Lamport clock comparison: higher clock wins
            if (lamport_clock < existing.lamport_clock) {
                // New value is older, reject
                self.allocator.free(path_str);
                return;
            }

            // Replace existing value - deinit old value but keep the key
            var old_value = existing.*;
            old_value.deinit(self.allocator);

            // Create new retained value reusing the existing key
            var new_value = try RetainedValue.init(
                self.allocator,
                path,
                envelope_data,
                lamport_clock,
                ttl_seconds,
            );
            errdefer new_value.deinit(self.allocator);

            // Update in place (key stays, value replaced)
            entry.value_ptr.* = new_value;
            
            // Free the path_str we allocated (key already exists)
            self.allocator.free(path_str);
            return;
        }

        // Check capacity and evict oldest if needed
        if (self.values.count() >= self.max_per_namespace) {
            try self.evictOldest();
        }

        // Create new retained value
        var new_value = try RetainedValue.init(
            self.allocator,
            path,
            envelope_data,
            lamport_clock,
            ttl_seconds,
        );
        errdefer new_value.deinit(self.allocator);

        try self.values.put(path_str, new_value);
    }

    /// Remove a retained value by path
    pub fn remove(self: *Self, path: Path) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const path_str = path.toString(self.allocator) catch return;
        defer self.allocator.free(path_str);

        if (self.values.fetchRemove(path_str)) |kv| {
            var value = kv.value;
            value.deinit(self.allocator);
            self.allocator.free(kv.key);
        }
    }

    /// Find all retained values matching a pattern
    pub fn matching(
        self: *Self,
        pattern: Pattern,
        allocator: Allocator,
    ) ![]RetainedValue {
        self.mutex.lock();
        defer self.mutex.unlock();

        var results: std.ArrayList(RetainedValue) = .empty;
        errdefer {
            for (results.items) |*item| {
                item.deinit(allocator);
            }
            results.deinit(allocator);
        }

        var it = self.values.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            var path = try Path.parse(allocator, key);

            if (pattern.matchesPath(path)) {
                var value = entry.value_ptr;

                // Skip expired values (evict them)
                if (value.isExpired()) {
                    path.deinit();
                    continue;
                }

                // Clone the retained value for the result
                const cloned = try RetainedValue.init(
                    allocator,
                    path,
                    value.envelope_data,
                    value.lamport_clock,
                    if (value.expires_at) |exp| exp - @as(u64, @intCast(std.time.timestamp())) else null,
                );
                path.deinit(); // Deinit the parsed path (RetainedValue.init clones it)
                try results.append(allocator, cloned);
            } else {
                path.deinit();
            }
        }

        return results.toOwnedSlice(allocator);
    }

    /// Evict the least recently used value
    fn evictOldest(self: *Self) !void {
        var oldest_key: ?[]const u8 = null;
        var oldest_time: u64 = std.math.maxInt(u64);

        var it = self.values.iterator();
        while (it.next()) |entry| {
            const value = entry.value_ptr;
            if (value.last_accessed < oldest_time) {
                oldest_time = value.last_accessed;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (self.values.fetchRemove(key)) |kv| {
                var value = kv.value;
                value.deinit(self.allocator);
                self.allocator.free(kv.key);
            }
        }
    }

    /// Get count of retained values
    pub fn count(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.values.count();
    }

    /// Clear all retained values
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.values.iterator();
        while (it.next()) |entry| {
            var value = entry.value_ptr;
            value.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.values.clearRetainingCapacity();
    }
};

const testing = std.testing;

test "RetainedValue lifecycle" {
    const allocator = testing.allocator;

    var path = try Path.parse(allocator, "sensor/berlin/temp");
    defer path.deinit();
    const envelope_data = "test payload";

    var retained = try RetainedValue.init(
        allocator,
        path,
        envelope_data,
        42, // lamport_clock
        null, // no TTL
    );
    defer retained.deinit(allocator);

    try testing.expectEqual(@as(u64, 42), retained.lamport_clock);
    try testing.expectEqual(@as(u32, 0), retained.delivery_count);
    try testing.expect(!retained.isExpired());

    retained.markDelivered();
    try testing.expectEqual(@as(u32, 1), retained.delivery_count);
}

test "RetainedValueCache basic operations" {
    const allocator = testing.allocator;

    var cache = RetainedValueCache.init(allocator, 100);
    defer cache.deinit();

    var path = try Path.parse(allocator, "sensor/berlin/temp");
    defer path.deinit();

    // Update retained value
    try cache.updateRetained(path, "payload1", 1, null);
    try testing.expectEqual(@as(usize, 1), cache.count());

    // Get retained value
    var value = cache.getOrEvict(path);
    try testing.expect(value != null);
    if (value) |*v| {
        try testing.expectEqualStrings("payload1", v.envelope_data);
        try testing.expectEqual(@as(u64, 1), v.lamport_clock);
        v.deinit(allocator);
    }
}

test "RetainedValueCache Lamport clock ordering" {
    const allocator = testing.allocator;

    var cache = RetainedValueCache.init(allocator, 100);
    defer cache.deinit();

    var path = try Path.parse(allocator, "sensor/berlin/temp");
    defer path.deinit();

    // Insert with clock 5
    try cache.updateRetained(path, "payload5", 5, null);

    // Try to update with lower clock (should be rejected)
    try cache.updateRetained(path, "payload3", 3, null);

    // Value should still be payload5
    var value = cache.getOrEvict(path);
    try testing.expect(value != null);
    if (value) |*v| {
        try testing.expectEqualStrings("payload5", v.envelope_data);
        v.deinit(allocator);
    }

    // Update with higher clock (should succeed)
    try cache.updateRetained(path, "payload10", 10, null);

    var value2 = cache.getOrEvict(path);
    try testing.expect(value2 != null);
    if (value2) |*v| {
        try testing.expectEqualStrings("payload10", v.envelope_data);
        v.deinit(allocator);
    }
}

test "RetainedValueCache LRU eviction" {
    const allocator = testing.allocator;

    var cache = RetainedValueCache.init(allocator, 2);
    defer cache.deinit();

    var path1 = try Path.parse(allocator, "sensor/a");
    defer path1.deinit();
    var path2 = try Path.parse(allocator, "sensor/b");
    defer path2.deinit();
    var path3 = try Path.parse(allocator, "sensor/c");
    defer path3.deinit();

    try cache.updateRetained(path1, "payload1", 1, null);
    try cache.updateRetained(path2, "payload2", 2, null);

    // Access path1 to make it more recent
    var value1 = cache.getOrEvict(path1);
    if (value1) |*v| {
        v.deinit(allocator);
    }

    // Add third item - should evict path2 (least recently used)
    try cache.updateRetained(path3, "payload3", 3, null);

    try testing.expectEqual(@as(usize, 2), cache.count());

    // path1 should still be there
    var check1 = cache.getOrEvict(path1);
    try testing.expect(check1 != null);
    if (check1) |*v| {
        v.deinit(allocator);
    }

    // path2 should be evicted
    try testing.expect(cache.getOrEvict(path2) == null);

    // path3 should be added
    var check3 = cache.getOrEvict(path3);
    try testing.expect(check3 != null);
    if (check3) |*v| {
        v.deinit(allocator);
    }
}

test "RetainedValueCache pattern matching" {
    const allocator = testing.allocator;

    var cache = RetainedValueCache.init(allocator, 100);
    defer cache.deinit();

    var path1 = try Path.parse(allocator, "sensor/berlin/temp");
    defer path1.deinit();
    var path2 = try Path.parse(allocator, "sensor/berlin/humidity");
    defer path2.deinit();
    var path3 = try Path.parse(allocator, "sensor/london/temp");
    defer path3.deinit();

    try cache.updateRetained(path1, "temp1", 1, null);
    try cache.updateRetained(path2, "hum1", 1, null);
    try cache.updateRetained(path3, "temp2", 1, null);

    var pattern = try Pattern.parse(allocator, "sensor/berlin/+");
    defer pattern.deinit();

    const matches = try cache.matching(pattern, allocator);
    defer {
        for (matches) |*m| {
            m.deinit(allocator);
        }
        allocator.free(matches);
    }

    try testing.expectEqual(@as(usize, 2), matches.len);
}

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
