// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const vfs = @import("../../std/vfs_adapter.zig");

test "memory vfs read/write" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var store = vfs.MemoryStore.init(gpa.allocator());
    defer store.deinit();

    vfs.set(vfs.memory(&store));

    try vfs.makeDir("/mem");
    try vfs.writeFile("/mem/hello.txt", "world");

    const data = try vfs.readFileAlloc(gpa.allocator(), "/mem/hello.txt", 1024);
    defer gpa.allocator().free(data);
    try std.testing.expectEqualStrings("world", data);
}
