// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const vfs = @import("../../std/vfs_adapter.zig");
const cli = @import("../../src/janus_main.zig");

test "cacheInspectCollectVfs reads sizes and flags from MemoryStore" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var store = vfs.MemoryStore.init(alloc);
    defer store.deinit();
    vfs.set(vfs.memory(&store));

    // Prepare paths
    try vfs.makeDir("/cache");
    try vfs.makeDir("/cache/objects");
    try vfs.makeDir("/cache/objects/cafe");
    try vfs.writeFile("/cache/objects/cafe/meta-debug.json", "{\"onnx\":{\"file\":\"artifact-debug.bin\"}}\n");
    try vfs.createFileTruncWrite("/cache/objects/cafe/artifact-debug.bin", "BIN");
    try vfs.createFileTruncWrite("/cache/objects/cafe/ir-debug.txt", "IR");
    try vfs.writeFile("/cache/objects/cafe/graph-debug-summary.json", "SUM");

    const info = try cli.cacheInspectCollectVfs("/cache", "cafe", "debug", alloc);
    try std.testing.expect(info.have_meta);
    try std.testing.expect(info.artifact_size != null and info.artifact_size.? == 3);
    try std.testing.expect(info.ir_size != null and info.ir_size.? == 2);
    try std.testing.expect(info.summary_present);
}
