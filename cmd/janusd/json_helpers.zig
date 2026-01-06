// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn writeMinified(writer: anytype, value: anytype) !void {
    const payload = try std.json.Stringify.valueAlloc(std.heap.page_allocator, value, .{ .whitespace = .minified });
    defer std.heap.page_allocator.free(payload);
    try writer.writeAll(payload);
}
