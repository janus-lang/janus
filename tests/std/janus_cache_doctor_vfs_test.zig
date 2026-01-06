// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const vfs = @import("../../std/vfs_adapter.zig");
const cli = @import("../../src/janus_main.zig");

test "cacheDoctorCollectVfs counts and total size from MemoryStore" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var store = vfs.MemoryStore.init(A);
    defer store.deinit();
    vfs.set(vfs.memory(&store));

    // Two CIDs with files totaling 10 bytes
    try vfs.makeDir("/cache");
    try vfs.makeDir("/cache/objects");
    try vfs.makeDir("/cache/objects/c1");
    try vfs.createFileTruncWrite("/cache/objects/c1/artifact-a.bin", "AAA"); // 3
    try vfs.createFileTruncWrite("/cache/objects/c1/ir-a.txt", "BB");        // 2
    try vfs.makeDir("/cache/objects/c2");
    try vfs.createFileTruncWrite("/cache/objects/c2/graph-a-summary.json", "CCCCC"); // 5

    var stats = try cli.cacheDoctorCollectVfs("/cache", A);
    defer { for (stats.hogs) |h| A.free(h.cid); }
    try std.testing.expect(stats.cid_count == 2);
    try std.testing.expect(stats.total_size == 10);
    // Counts by prefix
    try std.testing.expect(stats.art == 1);
    try std.testing.expect(stats.ir == 1);
    try std.testing.expect(stats.summary == 1);
}
