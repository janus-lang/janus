// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

test "basic test" {
    std.debug.print("Hello from basic test!\n", .{});
    try testing.expect(true);
}
