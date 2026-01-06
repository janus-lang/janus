// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const vfs = @import("../../std/vfs_adapter.zig");
const cli = @import("../../src/janus_main.zig");
const janus = @import("../../compiler/libjanus/api.zig");

fn hexDigest(alloc: std.mem.Allocator, data: []const u8) ![]u8 {
    const cid = janus.blake3Hash(data);
    return try janus.contentIdToHex(cid, alloc);
}

test "cacheVerifyCollectVfs computes OK/Bad counts" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    var store = vfs.MemoryStore.init(A);
    defer store.deinit();
    vfs.set(vfs.memory(&store));

    // OK CID
    try vfs.makeDir("/cache");
    try vfs.makeDir("/cache/objects");
    try vfs.makeDir("/cache/objects/okcid");
    try vfs.createFileTruncWrite("/cache/objects/okcid/artifact-debug.bin", "BIN");
    try vfs.createFileTruncWrite("/cache/objects/okcid/ir-debug.txt", "IR");
    const onnx_hex = try hexDigest(A, "BIN");
    defer A.free(onnx_hex);
    const ir_hex = try hexDigest(A, "IR");
    defer A.free(ir_hex);
    const meta_ok = try std.fmt.allocPrint(A, "{{\n  \"onnx\": {{ \"file\": \"artifact-debug.bin\", \"digest\": \"{s}\" }},\n  \"ir\":   {{ \"file\": \"ir-debug.txt\",     \"digest\": \"{s}\" }}\n}}\n", .{ onnx_hex, ir_hex });
    defer A.free(meta_ok);
    try vfs.createFileTruncWrite("/cache/objects/okcid/meta-debug.json", meta_ok);

    // BAD CID (wrong digest for IR, missing artifact)
    try vfs.makeDir("/cache/objects/badcid");
    try vfs.createFileTruncWrite("/cache/objects/badcid/ir-debug.txt", "IRX");
    const bad_meta = "{\n  \"onnx\": { \"file\": \"artifact-debug.bin\", \"digest\": \"deadbeef\" },\n  \"ir\":   { \"file\": \"ir-debug.txt\",     \"digest\": \"0000\" }\n}\n";
    try vfs.createFileTruncWrite("/cache/objects/badcid/meta-debug.json", bad_meta);

    const stats = try cli.cacheVerifyCollectVfs("/cache", A);
    // Expect 2 OK from okcid (onnx + ir), and at least 2 BAD from badcid (missing onnx file + ir mismatch)
    try std.testing.expect(stats.ok == 2);
    try std.testing.expect(stats.bad >= 2);
}
