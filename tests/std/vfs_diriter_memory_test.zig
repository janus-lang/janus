// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const vfs = @import("../../std/vfs_adapter.zig");

test "vfs DirIter lists memory store entries" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var store = vfs.MemoryStore.init(alloc);
    defer store.deinit();
    vfs.set(vfs.memory(&store));

    try vfs.makeDir("/root");
    try vfs.makeDir("/root/dirA");
    try vfs.makeDir("/root/dirB");
    try vfs.writeFile("/root/file1.txt", "x");
    try vfs.writeFile("/root/file2.txt", "y");

    var it = try vfs.openDirIter(alloc, "/root");
    defer it.deinit();

    var names = std.StringHashMap(void).init(alloc);
    defer names.deinit();
    while (try it.next()) |e| {
        try names.put(try alloc.dupe(u8, e.name), {});
    }
    try std.testing.expect(names.contains("dirA"));
    try std.testing.expect(names.contains("dirB"));
    try std.testing.expect(names.contains("file1.txt"));
    try std.testing.expect(names.contains("file2.txt"));
}
