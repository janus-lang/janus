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
        const fd = try std.posix.openat(std.posix.AT.FDCWD, path, 0, 0);
        defer std.posix.close(fd);
        const stat = try std.posix.fstat(fd);
        const size = @intCast(usize, stat.size);
        data = try allocator.alloc(u8, size);
        data_owned = true;
        _ = try std.posix.read(fd, data);
    } else {
        // Read stdin - use posix read
        var stdin_buffer: [65536]u8 = undefined;
        var total_read: usize = 0;
        while (true) {
            const bytes_read = std.posix.read(std.posix.STDIN_FILENO, stdin_buffer[total_read..]) catch break;
            if (bytes_read == 0) break;
            total_read += bytes_read;
            if (total_read >= stdin_buffer.len) {
                // Expand buffer
                const new_buffer = try allocator.alloc(u8, total_read * 2);
                @memcpy(new_buffer[0..total_read], stdin_buffer[0..total_read]);
                allocator.free(data);
                data = new_buffer;
            }
        }
        data = try allocator.resizeOrFree(std.mem.sliceTo(std.posix.STDIN_FILENO, 0), total_read);
        data_owned = true;
    }

    const cid = janus.blake3Hash(data);
    const hex = try janus.contentIdToHex(cid, allocator);
    defer allocator.free(hex);
    std.debug.print("{s}\n", .{hex});
}
