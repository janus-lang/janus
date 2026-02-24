// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// ABSOLUTE MINIMAL TEST - Understanding the fundamental issue
// This will help us understand exactly where the leaks are coming from

test "Absolute Minimal - Just Arena Dupe" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arena_allocator = arena.allocator();
        const duped = try arena_allocator.dupe(u8, "hello");
        _ = duped; // Use the duped string
    }

    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        return error.MemoryLeak;
    }

}

test "Absolute Minimal - Parent Alloc + Arena Dupe" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        // Parent allocator manages structure
        const strings = try allocator.alloc([]const u8, 10);
        defer allocator.free(strings);

        // Arena manages content
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arena_allocator = arena.allocator();
        const duped = try arena_allocator.dupe(u8, "hello");
        strings[0] = duped;
    }

    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        return error.MemoryLeak;
    }

}

test "Absolute Minimal - Struct with Arena" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const TestStruct = struct {
        arena: std.heap.ArenaAllocator,
        strings: [][]const u8,

        fn init(parent_allocator: std.mem.Allocator) !@This() {
            const strings = try parent_allocator.alloc([]const u8, 10);
            const arena = std.heap.ArenaAllocator.init(parent_allocator);
            return @This(){
                .arena = arena,
                .strings = strings,
            };
        }

        fn deinit(self: *@This(), parent_allocator: std.mem.Allocator) void {
            self.arena.deinit();
            parent_allocator.free(self.strings);
        }

        fn addString(self: *@This(), s: []const u8) !void {
            const arena_allocator = self.arena.allocator();
            const duped = try arena_allocator.dupe(u8, s);
            self.strings[0] = duped;
        }
    };

    {
        var test_struct = try TestStruct.init(allocator);
        defer test_struct.deinit(allocator);

        try test_struct.addString("hello");
    }

    // Check for memory leaks
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        return error.MemoryLeak;
    }

}
