// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("janus_lib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // argv0

    var data: []u8 = undefined;
    var data_owned = false;
    defer if (data_owned) allocator.free(data);

    if (args.next()) |path| {
        // Read file
        data = try std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024 * 1024);
        data_owned = true;
    } else {
        // Read stdin using the 0.15 streaming API
        data = try std.fs.File.stdin().readToEndAlloc(allocator, 64 * 1024 * 1024);
        data_owned = true;
    }

    const cid = janus.blake3Hash(data);
    const hex = try janus.contentIdToHex(cid, allocator);
    defer allocator.free(hex);
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("{s}\n", .{hex});
    try stdout.flush();
}
