// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Build Cache — content-addressed artifact storage keyed by BLAKE3 CIDs

const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub const BuildCache = struct {
    allocator: Allocator,
    root: []const u8, // e.g., ".janus/cache"

    pub fn init(allocator: Allocator, root: []const u8) BuildCache {
        return .{ .allocator = allocator, .root = root };
    }

    pub fn deinit(self: *BuildCache) void {
        _ = self; // nothing to free; caller owns root slice
    }

    /// Store an artifact blob under Graph CID + flavor key.
    /// Layout: <root>/objects/<hex>/artifact-<flavor>.bin
    pub fn store(self: *BuildCache, cid: [32]u8, flavor: []const u8, bytes: []const u8) !void {
        const hex = try self.cidHex(cid);
        defer self.allocator.free(hex);

        var path_buf = std.ArrayList(u8){};
        defer path_buf.deinit(self.allocator);
        try path_buf.writer(self.allocator).print("{s}/objects/{s}", .{ self.root, hex });
        const dir_path = try path_buf.toOwnedSlice(self.allocator);
        defer self.allocator.free(dir_path);

        // Ensure directory exists
        std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Write to temp file then atomically rename
        const final_name = try std.fmt.allocPrint(self.allocator, "artifact-{s}.bin", .{flavor});
        defer self.allocator.free(final_name);
        const tmp_name = try std.fmt.allocPrint(self.allocator, ".artifact-{s}.tmp-{d}", .{ flavor, std.time.nanoTimestamp() });
        defer self.allocator.free(tmp_name);

        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = false });
        defer dir.close();

        {
            var file = try dir.createFile(tmp_name, .{ .truncate = true, .read = false, .exclusive = true });
            defer file.close();
            try file.writeAll(bytes);
            try file.sync();
        }
        // If a writer beat us, rename will fail; treat as success (idempotent store)
        dir.rename(tmp_name, final_name) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    /// Store metadata JSON for an artifact under meta-<flavor>.json
    pub fn storeMeta(self: *BuildCache, cid: [32]u8, flavor: []const u8, json_bytes: []const u8) !void {
        const hex = try self.cidHex(cid);
        defer self.allocator.free(hex);

        var path_buf = std.ArrayList(u8){};
        defer path_buf.deinit(self.allocator);
        try path_buf.writer(self.allocator).print("{s}/objects/{s}", .{ self.root, hex });
        const dir_path = try path_buf.toOwnedSlice(self.allocator);
        defer self.allocator.free(dir_path);

        std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const final_name = try std.fmt.allocPrint(self.allocator, "meta-{s}.json", .{flavor});
        defer self.allocator.free(final_name);
        const tmp_name = try std.fmt.allocPrint(self.allocator, ".meta-{s}.tmp-{d}", .{ flavor, std.time.nanoTimestamp() });
        defer self.allocator.free(tmp_name);

        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = false });
        defer dir.close();

        {
            var file = try dir.createFile(tmp_name, .{ .truncate = true, .read = false, .exclusive = true });
            defer file.close();
            try file.writeAll(json_bytes);
            try file.sync();
        }
        dir.rename(tmp_name, final_name) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    /// List artifact flavors for a given CID
    pub fn listFlavors(self: *BuildCache, cid: [32]u8, allocator: Allocator) ![][:0]const u8 {
        const hex = try self.cidHex(cid);
        defer self.allocator.free(hex);
        const dir_path = try std.fmt.allocPrint(allocator, "{s}/objects/{s}", .{ self.root, hex });
        defer allocator.free(dir_path);
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return &[_][:0]const u8{};
        defer dir.close();
        var it = dir.iterate();
        var flavors = std.ArrayList([:0]const u8){};
        defer flavors.deinit(allocator);
        while (try it.next()) |ent| {
            if (ent.kind == .file) {
                if (std.mem.startsWith(u8, ent.name, "artifact-") and std.mem.endsWith(u8, ent.name, ".bin")) {
                    const core = ent.name[9 .. ent.name.len - 4];
                    const dup = try allocator.dupeZ(u8, core);
                    try flavors.append(allocator, dup);
                }
            }
        }
        return try flavors.toOwnedSlice(allocator);
    }

    /// Load artifact for CID+flavor. Caller frees returned buffer.
    pub fn load(self: *BuildCache, cid: [32]u8, flavor: []const u8) ![]u8 {
        const hex = try self.cidHex(cid);
        defer self.allocator.free(hex);
        const path = try std.fmt.allocPrint(self.allocator, "{s}/objects/{s}/artifact-{s}.bin", .{ self.root, hex, flavor });
        defer self.allocator.free(path);
        return std.fs.cwd().readFileAlloc(self.allocator, path, 64 * 1024 * 1024);
    }

    pub fn exists(self: *BuildCache, cid: [32]u8, flavor: []const u8) bool {
        const hex = self.cidHex(cid) catch return false;
        defer self.allocator.free(hex);
        const path = std.fmt.allocPrint(self.allocator, "{s}/objects/{s}/artifact-{s}.bin", .{ self.root, hex, flavor }) catch return false;
        defer self.allocator.free(path);
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Store an arbitrary named file under the CID directory.
    pub fn storeNamed(self: *BuildCache, cid: [32]u8, filename: []const u8, bytes: []const u8) !void {
        const hex = try self.cidHex(cid);
        defer self.allocator.free(hex);
        const dir_path = try std.fmt.allocPrint(self.allocator, "{s}/objects/{s}", .{ self.root, hex });
        defer self.allocator.free(dir_path);
        std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = false });
        defer dir.close();

        const tmp = try std.fmt.allocPrint(self.allocator, ".{s}.tmp-{d}", .{ filename, std.time.nanoTimestamp() });
        defer self.allocator.free(tmp);
        {
            var f = try dir.createFile(tmp, .{ .truncate = true, .exclusive = true });
            defer f.close();
            try f.writeAll(bytes);
            try f.sync();
        }
        dir.rename(tmp, filename) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    fn cidHex(self: *BuildCache, cid: [32]u8) ![]u8 {
        const hex_value = std.fmt.bytesToHex(cid, .lower);
        return try self.allocator.dupe(u8, &hex_value);
    }
};

// ------------------ Tests ------------------
const testing = std.testing;

test "BuildCache: store and load by Graph CID and flavor" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();

    // Create a temp root under CWD
    const root = try std.fmt.allocPrint(A, ".janus/cache-test-{d}", .{std.time.milliTimestamp()});
    defer {
        std.fs.cwd().deleteTree(root) catch {};
        A.free(root);
    }

    var bc = BuildCache.init(A, root);
    defer bc.deinit();

    // Fake CID for testing
    var cid: [32]u8 = undefined;
    @memset(&cid, 0);
    cid[0] = 0x42;
    const flavor = "npu-O2";
    const payload = "artifact payload bytes";

    try bc.store(cid, flavor, payload);
    try testing.expect(bc.exists(cid, flavor));
    const loaded = try bc.load(cid, flavor, A);
    defer A.free(loaded);
    try testing.expectEqualStrings(payload, loaded);
}
