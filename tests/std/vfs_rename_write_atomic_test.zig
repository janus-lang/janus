// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const vfs = @import("../../std/vfs_adapter.zig");

test "vfs.writeAtomic writes content atomically in MemoryStore" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var store = vfs.MemoryStore.init(A);
    defer store.deinit();
    store.enableDeterministic();
    vfs.set(vfs.memory(&store));

    try vfs.writeAtomic("/mem/file.txt", "HELLO");
    const st = try vfs.statFile("/mem/file.txt");
    try std.testing.expect(st.size == 5);
    const bytes = try vfs.readFileAlloc(A, "/mem/file.txt", 1024);
    defer A.free(bytes);
    try std.testing.expectEqualStrings("HELLO", bytes);
}

test "vfs.rename moves files and directories in MemoryStore" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var store = vfs.MemoryStore.init(A);
    defer store.deinit();
    store.enableDeterministic();
    vfs.set(vfs.memory(&store));

    try vfs.writeFile("/x.txt", "X");
    try vfs.rename("/x.txt", "/y.txt");
    const st_y = try vfs.statFile("/y.txt");
    try std.testing.expect(st_y.size == 1);

    try vfs.makeDir("/dir");
    try vfs.makeDir("/dir/sub");
    try vfs.writeFile("/dir/sub/a.bin", "AB");
    try vfs.rename("/dir", "/moved");
    const st_a = try vfs.statFile("/moved/sub/a.bin");
    try std.testing.expect(st_a.size == 2);
}
