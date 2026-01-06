// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// UTCP Manuals — tensor tools with capability + :npu profile declaration

const std = @import("std");
const utcp = @import("utcp_registry.zig");

pub const TensorToolCtx = struct {
    tool_name: []const u8,
    required_caps: []const []const u8,
    optional_caps: []const []const u8,
    profile: []const u8 = ":npu",
};

/// ManualFn adapter: emits a JSON object describing the tensor tool with
/// x-janus-capabilities and x-janus-profile fields per SPEC.
pub fn tensorToolManual(ctx_ptr: *const anyopaque, alloc: std.mem.Allocator) anyerror![]const u8 {
    const ctx: *const TensorToolCtx = @ptrCast(@alignCast(ctx_ptr));
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    const w = out.writer();

    try w.print("{{\n  \"name\": \"{s}\",\n  \"summary\": \"Executes a tensor graph\",\n  \"x-janus-profile\": \"{s}\",\n  \"x-janus-capabilities\": {{\n    \"required\": [", .{ ctx.tool_name, ctx.profile });

    for (ctx.required_caps, 0..) |cap, i| {
        try w.print("\"{s}\"{s}", .{ cap, if (i + 1 < ctx.required_caps.len) "," else "" });
    }
    try w.print("]", .{});
    if (ctx.optional_caps.len > 0) {
        try w.print(",\n    \"optional\": [", .{});
        for (ctx.optional_caps, 0..) |cap, i| {
            try w.print("\"{s}\"{s}", .{ cap, if (i + 1 < ctx.optional_caps.len) "," else "" });
        }
        try w.print("]", .{});
    }
    try w.print("\n  }}\n}}", .{});
    return out.toOwnedSlice();
}

pub fn toManualFn() utcp.ManualFn {
    return tensorToolManual;
}

// ------------------ Tests ------------------
const testing = std.testing;

test "tensor tool manual includes profile and capabilities" {
    const req = [_][]const u8{ "npu.execute", "fs.read:/models" };
    const opt = [_][]const u8{ "net.http:POST:https://hooks.example.com" };
    var ctx = TensorToolCtx{ .tool_name = "tensor.execute", .required_caps = &req, .optional_caps = &opt };
    const json = try tensorToolManual(@ptrCast(&ctx), testing.allocator);
    defer testing.allocator.free(json);
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "x-janus-profile"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, ":npu"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "x-janus-capabilities"));
}
