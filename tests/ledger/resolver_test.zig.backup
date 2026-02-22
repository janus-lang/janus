// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const resolver = @import("../../compiler/libjanus/ledger/resolver.zig");
const manifest = @import("../../compiler/libjanus/ledger/manifest.zig");
const cas = @import("../../compiler/libjanus/ledger/cas.zig");

test "resolver: initialization and cleanup" {
    const allocator = testing.allocator;

    const cas_root = "test_resolver_cas";
    std.fs.cwd().deleteTree(cas_root) catch {};
    defer std.fs.cwd().deleteTree(cas_root) catch {};

    var test_resolver = try resolver.Resolver.init(cas_root, allocator);
    defer test_resolver.deinit();

    // Verify CAS directory was created
    var cas_dir = try std.fs.cwd().openDir(cas_root, .{});
    cas_dir.close();
}

test "resolver: capability change detection" {
    const allocator = testing.allocator;

    // Create old package with capabilities
    var old_cap = manifest.Capability.init(allocator);
    old_cap.name = try allocator.dupe(u8, "fs");
    try old_cap.params.put("path", "./data");
    defer old_cap.deinit();

    const old_capabilities = try allocator.alloc(manifest.Capability, 1);
    old_capabilities[0] = old_cap;

    const old_pkg = manifest.ResolvedPackage{
        .name = try allocator.dupe(u8, "test-pkg"),
        .version = try allocator.dupe(u8, "1.0.0"),
        .content_id = std.mem.zeroes([32]u8),
        .source = manifest.PackageRef.Source{ .git = .{ .url = "test", .ref = "main" } },
        .capabilities = old_capabilities,
        .dependencies = &[_][]const u8{},
    };
    defer {
        allocator.free(old_pkg.name);
        allocator.free(old_pkg.version);
        allocator.free(old_capabilities);
    }

    // Create new package with modified capabilities
    var new_cap = manifest.Capability.init(allocator);
    new_cap.name = try allocator.dupe(u8, "fs");
    try new_cap.params.put("path", "./different-data"); // Changed parameter
    defer new_cap.deinit();

    const new_capabilities = try allocator.alloc(manifest.Capability, 1);
    new_capabilities[0] = new_cap;

    const new_pkg = manifest.ResolvedPackage{
        .name = try allocator.dupe(u8, "test-pkg"),
        .version = try allocator.dupe(u8, "1.1.0"),
        .content_id = std.mem.zeroes([32]u8),
        .source = manifest.PackageRef.Source{ .git = .{ .url = "test", .ref = "main" } },
        .capabilities = new_capabilities,
        .dependencies = &[_][]const u8{},
    };
    defer {
        allocator.free(new_pkg.name);
        allocator.free(new_pkg.version);
        allocator.free(new_capabilities);
    }

    const cas_root = "test_resolver_changes";
    std.fs.cwd().deleteTree(cas_root) catch {};
    defer std.fs.cwd().deleteTree(cas_root) catch {};

    var test_resolver = try resolver.Resolver.init(cas_root, allocator);
    defer test_resolver.deinit();

    // Detect changes
    const changes = try test_resolver.detectCapabilityChanges("test-pkg", &old_pkg, &new_pkg);
    defer {
        for (changes) |*change| {
            allocator.free(change.package_name);
            if (change.old_capability) |*cap| {
                cap.deinit();
            }
            if (change.new_capability) |*cap| {
                cap.deinit();
            }
        }
        allocator.free(changes);
    }

    // Should detect one modification
    try testing.expect(changes.len == 1);
    try testing.expect(changes[0].change_type == .modified);
    try testing.expectEqualStrings("test-pkg", changes[0].package_name);
    try testing.expectEqualStrings("fs", changes[0].new_capability.?.name);
}

test "resolver: URL construction from sources" {
    const allocator = testing.allocator;

    const cas_root = "test_resolver_urls";
    std.fs.cwd().deleteTree(cas_root) catch {};
    defer std.fs.cwd().deleteTree(cas_root) catch {};

    var test_resolver = try resolver.Resolver.init(cas_root, allocator);
    defer test_resolver.deinit();

    // Test git source URL construction
    const git_source = manifest.PackageRef.Source{
        .git = .{
            .url = "https://github.com/example/repo.git",
            .ref = "v1.0.0",
        },
    };

    const git_url = try test_resolver.constructUrl(git_source);
    defer allocator.free(git_url);

    try testing.expectEqualStrings("git+https://github.com/example/repo.git#v1.0.0", git_url);

    // Test file source URL construction
    const file_source = manifest.PackageRef.Source{
        .path = .{
            .path = "/local/path/to/package",
        },
    };

    const file_url = try test_resolver.constructUrl(file_source);
    defer allocator.free(file_url);

    try testing.expectEqualStrings("file:///local/path/to/package", file_url);

    // Test tar source URL construction
    const tar_source = manifest.PackageRef.Source{
        .tar = .{
            .url = "https://example.com/package.tar.gz",
            .checksum = null,
        },
    };

    const tar_url = try test_resolver.constructUrl(tar_source);
    defer allocator.free(tar_url);

    try testing.expectEqualStrings("https://example.com/package.tar.gz", tar_url);
}

test "resolver: capability equality checking" {
    const allocator = testing.allocator;

    const cas_root = "test_resolver_equality";
    std.fs.cwd().deleteTree(cas_root) catch {};
    defer std.fs.cwd().deleteTree(cas_root) catch {};

    var test_resolver = try resolver.Resolver.init(cas_root, allocator);
    defer test_resolver.deinit();

    // Create identical capabilities
    var cap1 = manifest.Capability.init(allocator);
    cap1.name = try allocator.dupe(u8, "fs");
    try cap1.params.put("path", "./data");
    try cap1.params.put("mode", "rw");
    defer cap1.deinit();

    var cap2 = manifest.Capability.init(allocator);
    cap2.name = try allocator.dupe(u8, "fs");
    try cap2.params.put("path", "./data");
    try cap2.params.put("mode", "rw");
    defer cap2.deinit();

    try testing.expect(test_resolver.capabilitiesEqual(&cap1, &cap2));

    // Create different capabilities
    var cap3 = manifest.Capability.init(allocator);
    cap3.name = try allocator.dupe(u8, "fs");
    try cap3.params.put("path", "./different-data"); // Different parameter
    try cap3.params.put("mode", "rw");
    defer cap3.deinit();

    try testing.expect(!test_resolver.capabilitiesEqual(&cap1, &cap3));

    // Different capability names
    var cap4 = manifest.Capability.init(allocator);
    cap4.name = try allocator.dupe(u8, "net"); // Different name
    try cap4.params.put("path", "./data");
    try cap4.params.put("mode", "rw");
    defer cap4.deinit();

    try testing.expect(!test_resolver.capabilitiesEqual(&cap1, &cap4));
}

test "resolver: file transport integration" {
    const allocator = testing.allocator;

    const cas_root = "test_resolver_integration";
    std.fs.cwd().deleteTree(cas_root) catch {};
    defer std.fs.cwd().deleteTree(cas_root) catch {};

    // Create test package directory
    const test_pkg_dir = "test_package_source";
    std.fs.cwd().deleteTree(test_pkg_dir) catch {};
    defer std.fs.cwd().deleteTree(test_pkg_dir) catch {};

    try std.fs.cwd().makeDir(test_pkg_dir);
    try std.fs.cwd().writeFile(.{ .sub_path = test_pkg_dir ++ "/main.zig", .data = "pub fn main() {}" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_pkg_dir ++ "/README.md", .data = "# Test Package" });

    var test_resolver = try resolver.Resolver.init(cas_root, allocator);
    defer test_resolver.deinit();

    // Create package reference
    const pkg_ref = manifest.PackageRef{
        .name = "test-package",
        .source = manifest.PackageRef.Source{
            .path = .{ .path = test_pkg_dir },
        },
        .capabilities = &[_]manifest.Capability{},
    };

    // Create empty lockfile
    var empty_lockfile = manifest.Lockfile.init(allocator);
    defer empty_lockfile.deinit();

    // Resolve the package
    const resolved_pkg = try test_resolver.resolveSinglePackage(pkg_ref, &empty_lockfile);
    defer test_resolver.freeResolvedPackage(&resolved_pkg);

    // Verify the package was resolved
    try testing.expectEqualStrings("test-package", resolved_pkg.name);
    try testing.expect(resolved_pkg.content_id.len == 32); // BLAKE3 hash length

    // Verify content was stored in CAS
    try testing.expect(test_resolver.cas_instance.exists(resolved_pkg.content_id));

    // Verify integrity
    try testing.expect(try test_resolver.cas_instance.verify(resolved_pkg.content_id));
}

test "resolver: capability change prompting" {
    const allocator = testing.allocator;

    // Create test capability changes
    var cap_change = resolver.CapabilityChange{
        .package_name = try allocator.dupe(u8, "test-pkg"),
        .change_type = .added,
        .old_capability = null,
        .new_capability = null,
    };
    defer allocator.free(cap_change.package_name);

    var new_cap = manifest.Capability.init(allocator);
    new_cap.name = try allocator.dupe(u8, "fs");
    try new_cap.params.put("path", "./data");
    cap_change.new_capability = new_cap;
    defer new_cap.deinit();

    const changes = [_]resolver.CapabilityChange{cap_change};

    // Test prompting (output to a buffer)
    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();

    const result = try resolver.Resolver.promptCapabilityChanges(&changes, output_buffer.writer());

    // Should return false (requires explicit approval)
    try testing.expect(!result);

    // Should have written prompt to buffer
    try testing.expect(output_buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, output_buffer.items, "CAPABILITY CHANGES DETECTED") != null);
    try testing.expect(std.mem.indexOf(u8, output_buffer.items, "test-pkg") != null);
}

test "resolver: error handling" {
    const allocator = testing.allocator;

    const cas_root = "test_resolver_errors";
    std.fs.cwd().deleteTree(cas_root) catch {};
    defer std.fs.cwd().deleteTree(cas_root) catch {};

    var test_resolver = try resolver.Resolver.init(cas_root, allocator);
    defer test_resolver.deinit();

    // Test loading non-existent manifest
    const manifest_error = test_resolver.loadManifest();
    try testing.expectError(resolver.ResolverError.ManifestNotFound, manifest_error);

    // Test loading non-existent lockfile
    const lockfile_error = test_resolver.loadLockfile();
    try testing.expectError(resolver.ResolverError.LockfileParseError, lockfile_error);
}

test "resolver: memory management" {
    const allocator = testing.allocator;

    const cas_root = "test_resolver_memory";
    std.fs.cwd().deleteTree(cas_root) catch {};
    defer std.fs.cwd().deleteTree(cas_root) catch {};

    var test_resolver = try resolver.Resolver.init(cas_root, allocator);
    defer test_resolver.deinit();

    // Test cloning various structures
    const original_source = manifest.PackageRef.Source{
        .git = .{
            .url = "https://github.com/example/repo.git",
            .ref = "v1.0.0",
        },
    };

    const cloned_source = try test_resolver.cloneSource(original_source);
    defer {
        switch (cloned_source) {
            .git => |git| {
                allocator.free(git.url);
                allocator.free(git.ref);
            },
            else => {},
        }
    }

    // Verify cloned source is independent
    switch (cloned_source) {
        .git => |git| {
            try testing.expectEqualStrings("https://github.com/example/repo.git", git.url);
            try testing.expectEqualStrings("v1.0.0", git.ref);
        },
        else => try testing.expect(false),
    }
}
