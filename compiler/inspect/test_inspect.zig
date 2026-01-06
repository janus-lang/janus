// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const core = @import("core.zig");

test "Inspector initialization" {
    const inspector = core.Inspector.init(std.testing.allocator);
    // No deinit needed for current struct, but good practice to have logic ready
    _ = inspector;
}

test "Inspector text output" {
    var inspector = core.Inspector.init(std.testing.allocator);
    const result = try inspector.inspectSource("fn main() {}", .{ .format = .text });
    defer std.testing.allocator.free(result);

    // Dump starts with root node name
    try std.testing.expect(std.mem.startsWith(u8, result, "source_file"));
}

test "Inspector json output" {
    var inspector = core.Inspector.init(std.testing.allocator);
    const result = try inspector.inspectSource("fn main() {}", .{ .format = .json });
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.startsWith(u8, result, "{ \"nodes\": ["));
}
