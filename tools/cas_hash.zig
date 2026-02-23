// SPDX-License-Identifier: LUL-1-0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("janus_lib");

// Use Init for Zig 0.16 compatibility
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Use the args from Init
    var iter = std.process.Args.iterate(init.minimal.args);
    
    _ = iter.next(); // skip argv0

    var data: []u8 = undefined;
    var data_owned = false;
    defer if (data_owned) allocator.free(data);

    if (iter.next()) |path| {
        // Read file using POSIX for Zig 0.16 compatibility (O_RDONLY = 0)
        const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0);
        defer _ = std.os.linux.close(fd);
        // fstat removed in Zig 0.16 — use statx with AT_EMPTY_PATH
        var stx: std.os.linux.Statx = undefined;
        if (std.os.linux.statx(fd, "", 0x1000, std.os.linux.STATX.BASIC_STATS, &stx) != 0) return error.StatFailed;
        const size: usize = @intCast(stx.size);
        data = try allocator.alloc(u8, size);
        data_owned = true;
        const nread = std.os.linux.read(fd, data.ptr, data.len);
        if (@as(isize, @bitCast(nread)) < 0) return error.ReadFailed;
    } else {
        // Read all of stdin into heap buffer
        var buf = try allocator.alloc(u8, 65536);
        var total_read: usize = 0;
        while (true) {
            if (total_read >= buf.len) {
                buf = try allocator.realloc(buf, buf.len * 2);
            }
            const rc = std.os.linux.read(0, buf[total_read..].ptr, buf.len - total_read);
            if (@as(isize, @bitCast(rc)) <= 0) break;
            total_read += rc;
        }
        data = buf[0..total_read];
        data_owned = true;
    }

    const cid = janus.blake3Hash(data);
    const hex = try janus.contentIdToHex(cid, allocator);
    defer allocator.free(hex);
    std.debug.print("{s}\n", .{hex});
}
