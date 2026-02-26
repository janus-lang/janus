// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");

const canonical_allowed = [_][]const u8{
    "compiler/astdb/core.zig",
    "compiler/libjanus/astdb/core.zig",
};

const legacy_allowed = [_]struct {
    path: []const u8,
    reason: []const u8,
}{
    .{ .path = "compiler/semantic/source_span_utils.zig", .reason = "legacy span helper defining its own AstNode" },
    .{ .path = "compiler/libjanus/query/context.zig", .reason = "query subsystem placeholder for columnar records" },
    .{ .path = "compiler/libjanus/astdb/schema.zig", .reason = "schema placeholder awaiting node view integration" },
};

const max_file_bytes = 4 * 1024 * 1024;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var violations = std.ArrayList([]const u8){};
    defer {
        for (violations.items) |path| allocator.free(path);
        violations.deinit(allocator);
    }

    var legacy_seen = [_]bool{false} ** legacy_allowed.len;
    var root_dir = try compat_fs.openDir(".");
    defer root_dir.close();

    try scanDir(allocator, &root_dir, "", &violations, &legacy_seen);

    var warned = false;
    for (legacy_allowed, 0..) |legacy, i| {
        if (legacy_seen[i]) {
            warned = true;
            std.log.warn("legacy AST struct detected in {s}: {s}", .{ legacy.path, legacy.reason });
        }
    }
    if (warned) {
        std.log.warn("legacy AST definitions should migrate to ASTDB columnar APIs", .{});
    }

    if (violations.items.len != 0) {
        std.debug.print("\n✗ Rogue AST definitions detected (non-ASTDB):\n", .{});
        for (violations.items) |path| {
            std.debug.print("  - {s}\n", .{path});
        }
        std.debug.print("\nUse ASTDB capsules instead of bespoke node structs.\n", .{});
        return error.RogueAstDetected;
    }
}

fn shouldSkip(path: []const u8) bool {
    if (std.mem.eql(u8, path, "tools/check_rogue_ast.zig")) return true;
    return hasComponent(path, ".zig-cache/") or
        hasComponent(path, "zig-out/") or
        hasComponent(path, "third_party/") or
        hasComponent(path, "node_modules/") or
        hasComponent(path, "attic/") or
        hasComponent(path, "scratch");
}

fn hasComponent(path: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, path, needle) != null;
}

fn hasLegacyAstSignature(contents: []const u8) bool {
    return std.mem.indexOf(u8, contents, "AstNode = struct") != null or
        std.mem.indexOf(u8, contents, "struct AstNode") != null;
}

fn isCanonical(path: []const u8) bool {
    for (canonical_allowed) |allowed| {
        if (std.mem.eql(u8, path, allowed)) return true;
    }
    return false;
}

fn findLegacy(path: []const u8) ?usize {
    for (legacy_allowed, 0..) |legacy, i| {
        if (std.mem.eql(u8, path, legacy.path)) return i;
    }
    return null;
}

fn scanDir(
    allocator: std.mem.Allocator,
    dir: *compat_fs.DirHandle,
    prefix: []const u8,
    violations: *std.ArrayList([]const u8),
    legacy_seen: *[legacy_allowed.len]bool,
) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const rel_path = try joinPath(allocator, prefix, entry.name);

        switch (entry.kind) {
            .directory => {
                if (shouldSkip(rel_path)) {
                    allocator.free(rel_path);
                    continue;
                }
                var child = try compat_fs.openDir(rel_path);
                defer child.close();
                try scanDir(allocator, &child, rel_path, violations, legacy_seen);
                allocator.free(rel_path);
            },
            .file => {
                defer allocator.free(rel_path);
                if (!std.mem.endsWith(u8, rel_path, ".zig")) continue;
                if (shouldSkip(rel_path)) continue;

                const contents = try compat_fs.readFileAlloc(allocator, rel_path, max_file_bytes);
                defer allocator.free(contents);

                if (!hasLegacyAstSignature(contents)) continue;

                if (isCanonical(rel_path)) continue;

                if (findLegacy(rel_path)) |legacy_index| {
                    legacy_seen[legacy_index] = true;
                    continue;
                }

                const duped = try allocator.dupe(u8, rel_path);
                try violations.append(allocator, duped);
            },
            else => {
                allocator.free(rel_path);
            },
        }
    }
}

fn joinPath(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]const u8 {
    if (prefix.len == 0) return allocator.dupe(u8, name);
    return std.mem.concat(allocator, u8, &[_][]const u8{ prefix, "/", name });
}
