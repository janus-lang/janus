// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const simple_source = "hello";

    std.debug.print("Testing with simple source: '{s}'\n", .{simple_source});
    std.debug.print("Source length: {}\n", .{simple_source.len});

    // Manual tokenizer test
    var current_pos: u32 = 0;
    var count: u32 = 0;

    while (current_pos < simple_source.len and count < 10) {
        const c = simple_source[current_pos];
        std.debug.print("Position {}: '{c}' ({})\n", .{ current_pos, c, c });
        current_pos += 1;
        count += 1;
    }

    std.debug.print("Manual test completed\n");
}
