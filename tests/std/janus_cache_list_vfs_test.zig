// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const vfs = @import("../../std/vfs_adapter.zig");
const cli = @import("../../src/janus_main.zig");

test "cacheListCollectVfs lists artifacts from MemoryStore" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var store = vfs.MemoryStore.init(alloc);
    defer store.deinit();
    vfs.set(vfs.memory(&store));

    // Build cache tree: /cache/objects/abcd/{artifact-one.bin, note.txt}
    try vfs.makeDir("/cache");
    try vfs.makeDir("/cache/objects");
    try vfs.makeDir("/cache/objects/abcd");
    try vfs.writeFile("/cache/objects/abcd/artifact-one.bin", "X");
    try vfs.writeFile("/cache/objects/abcd/note.txt", "N");

    var list = try cli.cacheListCollectVfs("/cache", null, alloc);
    defer {
        for (list.items) |s| alloc.free(s);
        list.deinit();
    }
    var found = false;
    for (list.items) |name| if (std.mem.eql(u8, name, "artifact-one.bin")) { found = true; break; }
    try std.testing.expect(found);
}
