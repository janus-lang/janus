// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Simple tri-signature demonstration
fn operation_min(value: i32, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "min: {d}", .{value});
}

fn operation_go(value: i32, ctx: bool, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "go: {d} (ctx: {})", .{ value, ctx });
}

fn operation_full(value: i32, cap: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "full: {d} (cap: {s})", .{ value, cap });
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Test :min profile
    const result_min = try operation_min(42, allocator);
    defer allocator.free(result_min);
    std.log.info("{s}", .{result_min});

    // Test :go profile
    const result_go = try operation_go(42, true, allocator);
    defer allocator.free(result_go);
    std.log.info("{s}", .{result_go});

    // Test :full profile
    const result_full = try operation_full(42, "test-cap", allocator);
    defer allocator.free(result_full);
    std.log.info("{s}", .{result_full});
}

test "basic tri-signature" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try operation_min(42, allocator);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "min: 42") != null);
}
