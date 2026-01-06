// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("janus_lib");
const api = janus.api;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var files = std.ArrayList([]const u8){};
    defer files.deinit(allocator);

    if (args.len > 1) {
        var i: usize = 1;
        while (i < args.len) : (i += 1) try files.append(allocator, args[i]);
    } else {
        // default to examples/*.jan
        var dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
        defer dir.close();
        var it = dir.iterate();
        while (try it.next()) |e| {
            if (e.kind == .file and std.mem.endsWith(u8, e.name, ".jan")) {
                const full = try std.fmt.allocPrint(allocator, "examples/{s}", .{e.name});
                defer allocator.free(full);
                try files.append(allocator, try allocator.dupe(u8, full));
            }
        }
    }

    // 1) File-based fuzzing
    for (files.items) |path| {
        const data = std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024) catch |e| {
            std.debug.print("skip {s}: {s}\n", .{ path, @errorName(e) });
            continue;
        };
        defer allocator.free(data);

        // Pipeline: parse → analyze → IR → verify
        const snapshot = api.parse_root(data, allocator) catch |e| {
            std.debug.print("parse failed {s}: {s}\n", .{ path, @errorName(e) });
            continue;
        };
        defer snapshot.deinit();

        var sem = api.analyze(snapshot, allocator) catch |e| {
            std.debug.print("analyze failed {s}: {s}\n", .{ path, @errorName(e) });
            continue;
        };
        defer sem.deinit();

        var irm = api.generateIR(snapshot, &sem, allocator) catch |e| {
            std.debug.print("ir gen failed {s}: {s}\n", .{ path, @errorName(e) });
            continue;
        };
        defer irm.deinit();

        irm.verify(allocator) catch |e| {
            std.debug.print("verify failed {s}: {s}\n", .{ path, @errorName(e) });
            continue;
        };
    }

    // 2) Random source generation (property-style)
    var prng = std.Random.Xoshiro256.init(@as(u64, @bitCast(std.time.milliTimestamp())));
    var n: usize = 0;
    while (n < 16) : (n += 1) {
        const src = try genRandomProgram(&prng, allocator);
        defer allocator.free(src);
        const snapshot = api.parse_root(src, allocator) catch continue;
        defer snapshot.deinit();
        var sem = api.analyze(snapshot, allocator) catch continue;
        defer sem.deinit();
        var irm = api.generateIR(snapshot, &sem, allocator) catch continue;
        defer irm.deinit();
        _ = irm.verify(allocator) catch continue;
    }
}

fn genRandomProgram(prng: *std.Random.Xoshiro256, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "func main() do\n");
    const stmt_count = 1 + @as(usize, prng.random().int(u8) % 5);
    var i: usize = 0;
    while (i < stmt_count) : (i += 1) {
        switch (prng.random().int(u8) % 4) {
            0 => try out.appendSlice(allocator, "  let x := 1\n"),
            1 => try out.appendSlice(allocator, "  let y := true\n"),
            2 => try out.appendSlice(allocator, "  if true do\n    let z := 2\n  end\n"),
            else => try out.appendSlice(allocator, "  while false do\n  end\n"),
        }
    }
    try out.appendSlice(allocator, "end\n");
    return allocator.dupe(u8, out.items);
}
