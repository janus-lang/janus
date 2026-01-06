// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub const Issue = struct {
    path: []const u8,
    message: []const u8,
};

pub const PropertyType = enum { string, integer, boolean, object, array, number };

pub const Property = struct {
    name: []const u8,
    ty: PropertyType,
};

pub const Schema = struct {
    properties: []const Property,
    required: []const []const u8,
};

fn schemaForTool(name: []const u8) ?Schema {
    if (std.mem.eql(u8, name, "compile")) {
        return Schema{
            .properties = &.{
                .{ .name = "source_file", .ty = .string },
                .{ .name = "output_dir", .ty = .string },
            },
            .required = &.{ "source_file" },
        };
    } else if (std.mem.eql(u8, name, "query_ast")) {
        return Schema{
            .properties = &.{ .{ .name = "symbol", .ty = .string } },
            .required = &.{ "symbol" },
        };
    } else if (std.mem.eql(u8, name, "diagnostics.list")) {
        return Schema{
            .properties = &.{ .{ .name = "project", .ty = .string } },
            .required = &.{},
        };
    }
    return null;
}

fn checkTypeMatches(expected: PropertyType, v: std.json.Value) bool {
    return switch (expected) {
        .string => v == .string,
        .integer => v == .integer,
        .boolean => v == .bool,
        .object => v == .object,
        .array => v == .array,
        .number => v == .float or v == .integer,
    };
}

/// Validate JSON value against the tool schema; appends issues (owned slices) to `issues`.
pub fn validateToolInput(allocator: std.mem.Allocator, tool: []const u8, v: std.json.Value, issues: *std.ArrayList(Issue)) !void {
    const schema = schemaForTool(tool) orelse {
        // Unknown tool; treat as not our responsibility here
        return;
    };
    if (v != .object) {
        try appendIssue(allocator, issues, "$", "body must be a JSON object");
        return;
    }

    const obj = v.object;
    // Required fields
    for (schema.required) |req| {
        if (!obj.contains(req)) {
            const path = try std.fmt.allocPrint(allocator, "$.{s}", .{req});
            defer allocator.free(path);
            try appendIssue(allocator, issues, path, "required property missing");
        }
    }

    // Type checks for declared properties (ignore extras)
    for (schema.properties) |prop| {
        if (obj.get(prop.name)) |pv| {
            if (!checkTypeMatches(prop.ty, pv)) {
                const path = try std.fmt.allocPrint(allocator, "$.{s}", .{prop.name});
                defer allocator.free(path);
                try appendIssue(allocator, issues, path, "type mismatch");
            }
        }
    }
}

fn appendIssue(allocator: std.mem.Allocator, issues: *std.ArrayList(Issue), path: []const u8, message: []const u8) !void {
    const p = try allocator.dupe(u8, path);
    errdefer allocator.free(p);
    const m = try allocator.dupe(u8, message);
    errdefer allocator.free(m);
    try issues.append(allocator, .{ .path = p, .message = m });
}

// ---------------- Tests ----------------

test "validator: compile requires source_file" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var issues = std.ArrayList(Issue){};
    defer { for (issues.items) |it| { a.free(it.path); a.free(it.message); } issues.deinit(a); }
    var parsed = try std.json.parseFromSlice(std.json.Value, a, "{}", .{});
    defer parsed.deinit();
    try validateToolInput(a, "compile", parsed.value, &issues);
    try std.testing.expect(issues.items.len > 0);
}

test "validator: compile accepts valid types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var issues = std.ArrayList(Issue){};
    defer { for (issues.items) |it| { a.free(it.path); a.free(it.message); } issues.deinit(a); }
    const body = "{\"source_file\":\"src/main.jan\",\"output_dir\":\"zig-out\"}";
    var parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    defer parsed.deinit();
    try validateToolInput(a, "compile", parsed.value, &issues);
    try std.testing.expectEqual(@as(usize, 0), issues.items.len);
}

test "validator: diagnostics.list invalid project type" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var issues = std.ArrayList(Issue){};
    defer { for (issues.items) |it| { a.free(it.path); a.free(it.message); } issues.deinit(a); }
    var parsed = try std.json.parseFromSlice(std.json.Value, a, "{\"project\":5}", .{});
    defer parsed.deinit();
    try validateToolInput(a, "diagnostics.list", parsed.value, &issues);
    try std.testing.expect(issues.items.len > 0);
}
