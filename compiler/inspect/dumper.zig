// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const libjanus = @import("libjanus");
const janus_parser = libjanus.parser;

/// Writer backed by ArrayListUnmanaged(u8), replacing removed .writer() method.
const BufWriter = struct {
    buf: *std.ArrayListUnmanaged(u8),
    alloc: std.mem.Allocator,

    pub fn print(self: BufWriter, comptime fmt: []const u8, args: anytype) !void {
        var tmp: [4096]u8 = undefined;
        const result = std.fmt.bufPrint(&tmp, fmt, args) catch return error.NoSpaceLeft;
        try self.buf.appendSlice(self.alloc, result);
    }

    pub fn writeAll(self: BufWriter, data: []const u8) !void {
        try self.buf.appendSlice(self.alloc, data);
    }
};

fn bufWriter(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) BufWriter {
    return BufWriter{ .buf = buf, .alloc = allocator };
}

pub fn dumpAstText(snapshot: *const janus_parser.Snapshot, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    if (snapshot.nodeCount() > 0) {
        // Find source_file node (it might not be 0)
        var root_id: ?janus_parser.NodeId = null;
        const count = snapshot.nodeCount();
        for (0..count) |i| {
            const id: janus_parser.NodeId = @enumFromInt(i);
            if (snapshot.getNode(id)) |n| {
                if (n.kind == .source_file) {
                    root_id = id;
                    break;
                }
            }
        }

        if (root_id) |rid| {
            try dumpNodeText(&buf, allocator, snapshot, rid, 0);
        } else {
            // Fallback
            try buf.appendSlice(allocator, "(no source_file root found; linear dump)\n");
            for (0..count) |i| {
                const id: janus_parser.NodeId = @enumFromInt(i);
                if (snapshot.getNode(id)) |node| {
                    try bufWriter(&buf, allocator).print("{d}: {s}\n", .{ i, @tagName(node.kind) });
                }
            }
        }
    } else {
        try buf.appendSlice(allocator, "(empty ast)");
    }

    // Dump Diagnostics always
    try dumpDiagnostics(&buf, allocator, snapshot);

    return buf.toOwnedSlice(allocator);
}

pub fn dumpAstJson(snapshot: *const janus_parser.Snapshot, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);
    const w = bufWriter(&buf, allocator);

    try w.print("{{ \"nodes\": [", .{});

    const count = snapshot.nodeCount();
    for (0..count) |i| {
        const node_id: janus_parser.NodeId = @enumFromInt(i);
        if (snapshot.getNode(node_id)) |node| {
            if (i > 0) try w.print(",", .{});
            try w.print("{{ \"id\": {d}, \"kind\": \"{s}\" }}", .{ i, @tagName(node.kind) });
        }
    }

    try w.print("], \"diagnostics\": [", .{});

    const units = snapshot.core_snapshot.astdb.units.items;
    var first_diag = true;
    for (units) |unit| {
        for (unit.diags) |diag| {
            if (!first_diag) try w.print(",", .{});
            first_diag = false;

            try w.print("{{ \"severity\": \"{s}\", \"code\": \"{s}\"", .{ @tagName(diag.severity), @tagName(diag.code) });

            if (snapshot.core_snapshot.astdb.str_interner.get(diag.message)) |msg| {
                try w.print(", \"message\": {f}", .{std.json.fmt(msg, .{})});
            }

            try w.print(", \"line\": {d}, \"column\": {d} }}", .{ diag.span.line, diag.span.column });
        }
    }

    try w.print("] }}", .{});
    return buf.toOwnedSlice(allocator);
}

fn dumpDiagnostics(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, snapshot: *const janus_parser.Snapshot) !void {
    const units = snapshot.core_snapshot.astdb.units.items;
    var diag_count: usize = 0;
    for (units) |unit| {
        diag_count += unit.diags.len;
    }

    if (diag_count > 0) {
        try buf.appendSlice(allocator, "\nDiagnostics:\n");
        const w = bufWriter(buf, allocator);
        for (units) |unit| {
            for (unit.diags) |diag| {
                try indent(buf, allocator, 1);
                try w.print("[{s}] {s}", .{ @tagName(diag.severity), @tagName(diag.code) });
                if (snapshot.core_snapshot.astdb.str_interner.get(diag.message)) |msg| {
                    try w.print(": {s}", .{msg});
                }
                try w.print(" at {d}:{d}\n", .{ diag.span.line, diag.span.column });
            }
        }
    }
}

fn dumpNodeText(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, snapshot: *const janus_parser.Snapshot, node_id: janus_parser.NodeId, depth: u32) !void {
    const node = snapshot.getNode(node_id) orelse return;

    try indent(buf, allocator, depth);
    try bufWriter(buf, allocator).print("{s}", .{@tagName(node.kind)});
    try buf.appendSlice(allocator, "\n");

    // Dump children
    const children = snapshot.core_snapshot.getChildren(node_id);
    for (children) |child_id| {
        try dumpNodeText(buf, allocator, snapshot, child_id, depth + 1);
    }
}

fn indent(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, depth: u32) !void {
    var i: u32 = 0;
    while (i < depth) : (i += 1) {
        try buf.appendSlice(allocator, "  ");
    }
}
