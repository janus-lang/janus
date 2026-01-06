// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const libjanus = @import("libjanus");
const janus_parser = libjanus.parser;

pub fn dumpAstText(snapshot: *const janus_parser.Snapshot, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    if (snapshot.nodeCount() > 0) {
        // Find source_file node (it might not be 0)
        var root_id: ?janus_parser.NodeId = null;
        const count = snapshot.nodeCount();
        for (0..count) |i| {
            const id: janus_parser.NodeId = @enumFromInt(i);
            if (snapshot.getNode(id)) |node| {
                if (node.kind == .source_file) {
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
                    try buf.writer(allocator).print("{d}: {s}\n", .{ i, @tagName(node.kind) });
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
    const writer = buf.writer(allocator);

    try writer.print("{{ \"nodes\": [", .{});

    const count = snapshot.nodeCount();
    for (0..count) |i| {
        const node_id: janus_parser.NodeId = @enumFromInt(i);
        if (snapshot.getNode(node_id)) |node| {
            if (i > 0) try writer.print(",", .{});
            try writer.print("{{ \"id\": {d}, \"kind\": \"{s}\" }}", .{ i, @tagName(node.kind) });
        }
    }

    try writer.print("], \"diagnostics\": [", .{});

    const units = snapshot.core_snapshot.astdb.units.items;
    var first_diag = true;
    for (units) |unit| {
        for (unit.diags) |diag| {
            if (!first_diag) try writer.print(",", .{});
            first_diag = false;

            try writer.print("{{ \"severity\": \"{s}\", \"code\": \"{s}\"", .{ @tagName(diag.severity), @tagName(diag.code) });

            if (snapshot.core_snapshot.astdb.str_interner.get(diag.message)) |msg| {
                try writer.print(", \"message\": {f}", .{std.json.fmt(msg, .{})});
            }

            try writer.print(", \"line\": {d}, \"column\": {d} }}", .{ diag.span.line, diag.span.column });
        }
    }

    try writer.print("] }}", .{});
    return buf.toOwnedSlice(allocator);
}

fn dumpDiagnostics(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, snapshot: *const janus_parser.Snapshot) !void {
    const units = snapshot.core_snapshot.astdb.units.items;
    var count: usize = 0;
    for (units) |unit| {
        count += unit.diags.len;
    }

    if (count > 0) {
        try buf.appendSlice(allocator, "\nDiagnostics:\n");
        for (units) |unit| {
            for (unit.diags) |diag| {
                try indent(buf, allocator, 1);
                try buf.writer(allocator).print("[{s}] {s}", .{ @tagName(diag.severity), @tagName(diag.code) });
                if (snapshot.core_snapshot.astdb.str_interner.get(diag.message)) |msg| {
                    try buf.writer(allocator).print(": {s}", .{msg});
                }
                try buf.writer(allocator).print(" at {d}:{d}\n", .{ diag.span.line, diag.span.column });
            }
        }
    }
}

fn dumpNodeText(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, snapshot: *const janus_parser.Snapshot, node_id: janus_parser.NodeId, depth: u32) !void {
    const node = snapshot.getNode(node_id) orelse return;

    try indent(buf, allocator, depth);
    try buf.writer(allocator).print("{s}", .{@tagName(node.kind)});
    try buf.appendSlice(allocator, "\n");

    // Children traversal
    // We access core_snapshot directly as per permissive visibility
    const children = snapshot.core_snapshot.getChildren(node_id);
    for (children) |child_id| {
        try dumpNodeText(buf, allocator, snapshot, child_id, depth + 1);
    }
}

fn indent(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, depth: u32) !void {
    for (0..depth) |_| try buf.appendSlice(allocator, "  ");
}
