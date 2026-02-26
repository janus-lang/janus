// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! NS-Msg: Namespace Type System (Zig 0.15+ compatible)

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const Path = types.Path;
const Pattern = types.Pattern;

pub const NamespaceSchema = struct {
    const Self = @This();

    name: []const u8,
    path_template: []const u8,
    segment_names: std.ArrayList([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, path_template: []const u8) !Self {
        var schema = Self{
            .name = try allocator.dupe(u8, name),
            .path_template = try allocator.dupe(u8, path_template),
            .segment_names = .empty,
            .allocator = allocator,
        };

        var list: std.ArrayList([]const u8) = .empty;
        // Note: No defer deinit here - ownership moves to schema

        var it = std.mem.splitScalar(u8, path_template, '/');
        while (it.next()) |segment| {
            if (segment.len == 0) continue;
            
            if (std.mem.startsWith(u8, segment, "{") and std.mem.endsWith(u8, segment, "}")) {
                const name_inner = segment[1..segment.len-1];
                try list.append(allocator, try allocator.dupe(u8, name_inner));
            } else {
                try list.append(allocator, try allocator.dupe(u8, segment));
            }
        }

        schema.segment_names = list;
        return schema;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.path_template);
        for (self.segment_names.items) |seg| {
            self.allocator.free(seg);
        }
        self.segment_names.deinit(self.allocator);
    }

    pub fn segmentCount(self: Self) usize {
        return self.segment_names.items.len;
    }

    pub fn buildPath(self: Self, values: []const []const u8) !Path {
        if (values.len != self.segmentCount()) {
            return error.ValueCountMismatch;
        }

        var path = Path.init(self.allocator);
        errdefer path.deinit();

        for (values) |value| {
            try path.append(value);
        }

        return path;
    }
};

pub const NamespaceRegistry = struct {
    const Self = @This();

    schemas: std.StringHashMap(NamespaceSchema),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return .{
            .schemas = std.StringHashMap(NamespaceSchema).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.schemas.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.schemas.deinit();
    }

    pub fn register(self: *Self, schema: NamespaceSchema) !void {
        try self.schemas.put(schema.name, schema);
    }

    pub fn get(self: Self, name: []const u8) ?*const NamespaceSchema {
        return self.schemas.getPtr(name);
    }

    pub fn has(self: Self, name: []const u8) bool {
        return self.schemas.contains(name);
    }
};

pub fn createStandardRegistry(allocator: Allocator) !NamespaceRegistry {
    var registry = NamespaceRegistry.init(allocator);
    errdefer registry.deinit();

    const sensor = try NamespaceSchema.init(allocator, "Sensor", "sensor/{geohash}/{metric}");
    try registry.register(sensor);

    const feed = try NamespaceSchema.init(allocator, "Feed", "feed/{chapter}/{scope}/{post_id}");
    try registry.register(feed);

    const query = try NamespaceSchema.init(allocator, "Query", "query/{service}/{operation}");
    try registry.register(query);

    const membrane = try NamespaceSchema.init(allocator, "Membrane", "$MEMBRANE/{signal}");
    try registry.register(membrane);

    return registry;
}

const testing = std.testing;

test "NamespaceSchema parsing" {
    const allocator = testing.allocator;

    var schema = try NamespaceSchema.init(allocator, "Sensor", "sensor/{geohash}/{metric}");
    defer schema.deinit();

    try testing.expectEqualStrings("Sensor", schema.name);
    try testing.expectEqual(@as(usize, 3), schema.segmentCount());
}

test "NamespaceSchema buildPath" {
    const allocator = testing.allocator;

    var schema = try NamespaceSchema.init(allocator, "Sensor", "sensor/{geohash}/{metric}");
    defer schema.deinit();

    const values = [_][]const u8{ "sensor", "u33dc0", "pm25" };
    var path = try schema.buildPath(&values);
    defer path.deinit();

    try testing.expectEqual(@as(usize, 3), path.len());
}

test "NamespaceRegistry" {
    const allocator = testing.allocator;

    var registry = try createStandardRegistry(allocator);
    defer registry.deinit();

    try testing.expect(registry.has("Sensor"));
    try testing.expect(registry.has("Feed"));
    try testing.expect(registry.has("Query"));
    try testing.expect(registry.has("Membrane"));
}
