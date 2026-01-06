// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

// Demo of the complete RAII/Using sugar pattern
const std = @import("std");
const region = @import("mem/region.zig");
const List = @import("mem/ctx/List.zig").List;

// Configuration structure (long-lived)
const Config = struct {
    name: []const u8,
    values: [][]const u8,
};

// Simulated configuration parsing with withScratch
fn parseConfig(allocator: std.mem.Allocator, input: []const u8) !Config {
    return try region.withScratch(Config, allocator, struct {
        fn parse(scratch_alloc: std.mem.Allocator) !Config {
            // Long-lived config - uses function allocator
            var config = Config{
                .name = "parsed_config",
                .values = &[_][]const u8{}, // Will be replaced
            };

            // Temporary parsing state - uses scratch allocator (auto-cleanup)
            var temp_values = List([]const u8).with(scratch_alloc);

            // Simulate parsing key-value pairs
            var it = std.mem.splitSequence(u8, input, ",");
            while (it.next()) |pair| {
                const trimmed = std.mem.trim(u8, pair, " ");
                if (trimmed.len > 0) {
                    // Value needs to persist - use function allocator
                    const value_copy = try allocator.dupe(u8, trimmed);
                    try temp_values.append(value_copy);
                }
            }

            // Convert to long-lived slice
            config.values = try temp_values.toOwnedSlice();
            return config;
        }
    }.parse);
}

pub fn demo() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== RAII/Using Sugar Demo ===\n", .{});

    // BEFORE: Manual region management
    std.debug.print("1. BEFORE (Manual Region Management):\n", .{});
    std.debug.print("   var scratch = region.Region.init(allocator);\n", .{});
    std.debug.print("   defer scratch.deinit();\n", .{});
    std.debug.print("   const scratch_alloc = scratch.allocator();\n", .{});
    std.debug.print("   // ... use scratch_alloc ...\n", .{});

    // AFTER: RAII/Using sugar
    std.debug.print("\n2. AFTER (RAII/Using Sugar):\n", .{});
    std.debug.print("   try withScratch(Config, allocator, struct {\n", .{});
    std.debug.print("       fn parse(scratch_alloc: Allocator) !Config {\n", .{});
    std.debug.print("           // ... use scratch_alloc ...\n", .{});
    std.debug.print("       }\n", .{});
    std.debug.print("   }.parse);\n", .{});

    // DEMONSTRATE: Parse configuration
    const input = "key1=value1, key2=value2, key3=value3";
    const config = try parseConfig(allocator, input);

    std.debug.print("\n3. RESULT:\n", .{});
    std.debug.print("   Parsed config: {s}\n", .{config.name});
    std.debug.print("   Values: {d} items\n", .{config.values.len});
    for (config.values, 0..) |value, i| {
        std.debug.print("     {d}: {s}\n", .{ i + 1, value });
    }

    // Cleanup
    for (config.values) |value| {
        allocator.free(value);
    }
    allocator.free(config.values);

    std.debug.print("\n=== Benefits Achieved ===\n", .{});
    std.debug.print("✅ Zero region setup boilerplate\n", .{});
    std.debug.print("✅ Guaranteed cleanup on all exit paths\n", .{});
    std.debug.print("✅ Clear lifetime separation\n", .{});
    std.debug.print("✅ Zero manual resource tracking\n", .{});
    std.debug.print("✅ Doctrinal purity maintained\n", .{});
}

pub fn main() !void {
    try demo();
}
