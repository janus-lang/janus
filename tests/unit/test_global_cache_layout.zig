// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const cache_support = @import("build_support/global_cache.zig");

test "ensureLocalGlobalCache creates required layout" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const gpa = std.testing.allocator;
    const base_path = try tmp.dir.realpathAlloc(gpa, ".");
    defer gpa.free(base_path);

    const cache_root = cache_support.CacheDirectory{
        .path = base_path,
        .handle = tmp.dir,
    };

    const new_cache = try cache_support.ensureLocalGlobalCache(cache_root, gpa, "global-test");
    defer new_cache.handle.close();
    try std.testing.expect(new_cache.path != null);
    const cache_path = new_cache.path.?;
    defer gpa.free(cache_path);
    try std.testing.expect(std.mem.endsWith(u8, cache_path, "global-test"));

    inline for (cache_support.required_buckets) |bucket| {
        const child = try new_cache.handle.openDir(bucket, .{});
        child.close();
    }
}
