// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub const CacheDirectory = std.Build.Cache.Directory;

pub const required_buckets = [_][]const u8{ "b", "h", "o", "tmp", "z" };

/// Ensure a writable global cache directory lives alongside the project's cache root.
/// Returns a `CacheDirectory` pointing at the prepared location. On error the caller
/// retains responsibility for the original cache directory.
pub fn ensureLocalGlobalCache(
    cache_root: CacheDirectory,
    allocator: std.mem.Allocator,
    subdir_name: []const u8,
) !CacheDirectory {
    var dir = try cache_root.handle.makeOpenPath(subdir_name, .{
        .access_sub_paths = true,
        .iterate = false,
    });
    errdefer dir.close();

    inline for (required_buckets) |bucket| {
        dir.makePath(bucket) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };
    }

    const path = try cache_root.join(allocator, &.{ subdir_name });
    errdefer allocator.free(path);
    errdefer allocator.free(path);

    return .{
        .path = path,
        .handle = dir,
    };
}
