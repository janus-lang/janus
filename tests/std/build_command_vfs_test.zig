// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const profiles = @import("../../src/profiles.zig");
const Build = @import("../../src/build_command.zig");
const vfs = @import("../../std/vfs_adapter.zig");

fn stub_check(_: std.mem.Allocator) bool { return true; }

fn stub_codegen(_: []const u8, output_path: []const u8, _: std.mem.Allocator, _: anytype) !void {
    // Write a minimal artifact via VFS
    try vfs.createFileTruncWrite(output_path, "ARTIFACT");
}

test "BuildCommand uses VFS for I/O with stubbed codegen" {
    // Arrange
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var store = vfs.MemoryStore.init(alloc);
    defer store.deinit();
    vfs.set(vfs.memory(&store));

    // Seed source file in memory VFS
    try vfs.writeFile("/src/main.jan", "print(\"hi\")\n");

    var cmd = try Build.BuildCommand.init(alloc, profiles.ProfileConfig.init(.core));
    cmd.setDeps(&stub_check, &stub_codegen);

    // Act
    try cmd.build("/src/main.jan", "/out/app.bin");

    // Assert: output written and cache created
    const st_out = try vfs.statFile("/out/app.bin");
    try std.testing.expect(st_out.kind == .file and st_out.size == "ARTIFACT".len);

    const cache_name = try std.fmt.allocPrint(alloc, ".janus/cache-{s}", .{cmd.profile_config.profile.toString()});
    defer alloc.free(cache_name);
    const st_cache = try vfs.statFile(cache_name);
    try std.testing.expect(st_cache.kind == .file);
}
