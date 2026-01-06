// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const json_helpers = @import("json_helpers.zig");

/// Result objects are stringified upstream; adapters return a generic value via write function.

pub fn compileAdapter(body: std.json.Value, allocator: std.mem.Allocator, writer: anytype) !void {
    if (body != .object) return error.Invalid;
    const obj = body.object;
    const source = obj.get("source_file").?.string;
    const out_dir = if (obj.get("output_dir")) |v| v.string else "zig-out";
    const artifact = try std.fmt.allocPrint(allocator, "{s}/{s}.o", .{ out_dir, std.fs.path.stem(source) });
    defer allocator.free(artifact);
    try json_helpers.writeMinified(writer, .{ .tool = "compile", .status = "queued", .source_file = source, .output_dir = out_dir, .artifact = artifact });
}

pub fn queryAstAdapter(body: std.json.Value, allocator: std.mem.Allocator, writer: anytype) !void {
    _ = allocator;
    if (body != .object) return error.Invalid;
    const symbol = body.object.get("symbol").?.string;
    try json_helpers.writeMinified(writer, .{ .tool = "query_ast", .symbol = symbol, .matches = [_][]const u8{}, .count = 0 });
}

pub fn diagnosticsListAdapter(body: std.json.Value, allocator: std.mem.Allocator, writer: anytype) !void {
    _ = allocator;
    const project = if (body == .object) blk: {
        break :blk if (body.object.get("project")) |v| v.string else "";
    } else "";
    try json_helpers.writeMinified(writer, .{ .tool = "diagnostics.list", .project = project, .diagnostics = [_]std.json.Value{} });
}

// ---------------- Tests ----------------

test "compileAdapter returns artifact path" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    const body = "{\"source_file\":\"src/main.jan\",\"output_dir\":\"zig-out\"}";
    var parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    defer parsed.deinit();
    var buf = std.ArrayList(u8){}; defer buf.deinit(a);
    try compileAdapter(parsed.value, a, buf.writer(a));
    const s = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, s, "\"artifact\":\"zig-out/main.o\"") != null);
}

test "queryAstAdapter returns empty matches" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    const body = "{\"symbol\":\"Foo\"}";
    var parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    defer parsed.deinit();
    var buf = std.ArrayList(u8){}; defer buf.deinit(a);
    try queryAstAdapter(parsed.value, a, buf.writer(a));
    const s = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, s, "\"matches\":[]") != null);
}

test "diagnosticsListAdapter returns diagnostics array" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    const body = "{}";
    var parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    defer parsed.deinit();
    var buf = std.ArrayList(u8){}; defer buf.deinit(a);
    try diagnosticsListAdapter(parsed.value, a, buf.writer(a));
    const s = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, s, "\"diagnostics\":[]") != null);
}
