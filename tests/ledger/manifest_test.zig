// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const manifest = @import("../../compiler/libjanus/ledger/manifest.zig");
const kdl_parser = @import("../../compiler/libjanus/ledger/kdl_parser.zig");
const json_parser = @import("../../compiler/libjanus/ledger/json_parser.zig");

test "manifest: KDL parser basic functionality" {
    const allocator = testing.allocator;

    const kdl_input =
        \\nameest-package"
        \\version "1.0.0"
        \\
        \\dependency "crypto" {
        \\    git "https://github.com/example/crypto.git" tag="v2.1.0"
        \\    capability "fs" path="./data"
        \\    capability "net" hosts="api.example.com"
        \\}
        \\
        \\dev-dependency "test-utils" {
        \\    path "./test-utils"
        \\}
    ;

    var parsed_manifest = try kdl_parser.parseManifest(kdl_input, allocator);
    defer parsed_manifest.deinit();

    // Test basic fields
    try testing.expectEqualStrings("test-package", parsed_manifest.name);
    try testing.expectEqualStrings("1.0.0", parsed_manifest.version);

    // Test dependencies
    try testing.expect(parsed_manifest.dependencies.len == 1);
    const crypto_dep = parsed_manifest.dependencies[0];
    try testing.expectEqualStrings("crypto", crypto_dep.name);

    // Test git source
    switch (crypto_dep.source) {
        .git => |git| {
            try testing.expectEqualStrings("https://github.com/example/crypto.git", git.url);
            try testing.expectEqualStrings("v2.1.0", git.ref);
        },
        else => try testing.expect(false), // Should be git source
    }

    // Test capabilities
    try testing.expect(crypto_dep.capabilities.len == 2);
    try testing.expectEqualStrings("fs", crypto_dep.capabilities[0].name);
    try testing.expectEqualStrings("net", crypto_dep.capabilities[1].name);

    // Test dev dependencies
    try testing.expect(parsed_manifest.dev_dependencies.len == 1);
    const test_dep = parsed_manifest.dev_dependencies[0];
    try testing.expectEqualStrings("test-utils", test_dep.name);

    switch (test_dep.source) {
        .path => |path| {
            try testing.expectEqualStrings("./test-utils", path.path);
        },
        else => try testing.expect(false), // Should be path source
    }
}

test "manifest: KDL lexer token recognition" {
    const allocator = testing.allocator;

    var lexer = kdl_parser.Lexer.init("name \"test\" { }");

    const token1 = try lexer.nextToken();
    try testing.expect(token1.type == .identifier);
    try testing.expectEqualStrings("name", token1.value);

    const token2 = try lexer.nextToken();
    try testing.expect(token2.type == .string);
    try testing.expectEqualStrings("\"test\"", token2.value);

    const token3 = try lexer.nextToken();
    try testing.expect(token3.type == .left_brace);

    const token4 = try lexer.nextToken();
    try testing.expect(token4.type == .right_brace);

    const token5 = try lexer.nextToken();
    try testing.expect(token5.type == .eof);
}

test "manifest: JSON lockfile parsing" {
    const allocator = testing.allocator;

    const json_input =
        \\{
        \\  "version": 1,
        \\  "packages": {
        \\    "crypto": {
        \\      "name": "crypto",
        \\      "version": "2.1.0",
        \\      "content_id": "a1b2c3d4e5f6789012345678901234567890123456789012345678901234567890",
        \\      "source": {
        \\        "type": "git",
        \\        "url": "https://github.com/example/crypto.git",
        \\        "ref": "v2.1.0"
        \\      },
        \\      "capabilities": [
        \\        {
        \\          "name": "fs",
        \\          "params": {
        \\            "path": "./data"
        \\          }
        \\        }
        \\      ],
        \\      "dependencies": ["base64", "hash"]
        \\    }
        \\  }
        \\}
    ;

    var lockfile = try json_parser.parseLockfile(json_input, allocator);
    defer lockfile.deinit();

    // Test version
    try testing.expect(lockfile.version == 1);

    // Test packages
    try testing.expect(lockfile.packages.count() == 1);

    const crypto_pkg = lockfile.packages.get("crypto").?;
    try testing.expectEqualStrings("crypto", crypto_pkg.name);
    try testing.expectEqualStrings("2.1.0", crypto_pkg.version);

    // Test content_id parsing
    const expected_id = [_]u8{ 0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78 };
    try testing.expectEqualSlices(u8, &expected_id, &crypto_pkg.content_id);

    // Test source
    switch (crypto_pkg.source) {
        .git => |git| {
            try testing.expectEqualStrings("https://github.com/example/crypto.git", git.url);
            try testing.expectEqualStrings("v2.1.0", git.ref);
        },
        else => try testing.expect(false),
    }

    // Test capabilities
    try testing.expect(crypto_pkg.capabilities.len == 1);
    try testing.expectEqualStrings("fs", crypto_pkg.capabilities[0].name);

    const fs_path = crypto_pkg.capabilities[0].params.get("path").?;
    try testing.expectEqualStrings("./data", fs_path);

    // Test dependencies
    try testing.expect(crypto_pkg.dependencies.len == 2);
    try testing.expectEqualStrings("base64", crypto_pkg.dependencies[0]);
    try testing.expectEqualStrings("hash", crypto_pkg.dependencies[1]);
}

test "manifest: JSON lockfile serialization roundtrip" {
    const allocator = testing.allocator;

    // Create a lockfile programmatically
    var lockfile = manifest.Lockfile.init(allocator);
    defer lockfile.deinit();

    lockfile.version = 1;

    // Create a test package
    var capabilities = try allocator.alloc(manifest.Capability, 1);
    capabilities[0] = manifest.Capability.init(allocator);
    capabilities[0].name = try allocator.dupe(u8, "fs");
    try capabilities[0].params.put("path", "./data");

    var dependencies = try allocator.alloc([]const u8, 1);
    dependencies[0] = try allocator.dupe(u8, "base64");

    const test_package = manifest.ResolvedPackage{
        .name = try allocator.dupe(u8, "crypto"),
        .version = try allocator.dupe(u8, "2.1.0"),
        .content_id = [_]u8{ 0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56, 0x78 },
        .source = manifest.PackageRef.Source{
            .git = .{
                .url = try allocator.dupe(u8, "https://github.com/example/crypto.git"),
                .ref = try allocator.dupe(u8, "v2.1.0"),
            },
        },
        .capabilities = capabilities,
        .dependencies = dependencies,
    };

    try lockfile.packages.put("crypto", test_package);

    // Serialize to JSON
    const json_output = try json_parser.serializeLockfile(&lockfile, allocator);
    defer allocator.free(json_output);

    // Parse it back
    var parsed_lockfile = try json_parser.parseLockfile(json_output, allocator);
    defer parsed_lockfile.deinit();

    // Verify roundtrip
    try testing.expect(parsed_lockfile.version == lockfile.version);
    try testing.expect(parsed_lockfile.packages.count() == 1);

    const parsed_pkg = parsed_lockfile.packages.get("crypto").?;
    try testing.expectEqualStrings("crypto", parsed_pkg.name);
    try testing.expectEqualStrings("2.1.0", parsed_pkg.version);
    try testing.expectEqualSlices(u8, &test_package.content_id, &parsed_pkg.content_id);
}

test "manifest: KDL parser error handling" {
    const allocator = testing.allocator;

    // Test invalid KDL
    const invalid_kdl = "name { invalid syntax";
    try testing.expectError(kdl_parser.KDLError.UnexpectedEOF, kdl_parser.parseManifest(invalid_kdl, allocator));

    // Test missing required fields
    const incomplete_kdl = "name \"test\""; // missing version
    var incomplete_manifest = try kdl_parser.parseManifest(incomplete_kdl, allocator);
    defer incomplete_manifest.deinit();

    // Should parse but have empty version
    try testing.expectEqualStrings("", incomplete_manifest.version);
}

test "manifest: JSON parser error handling" {
    const allocator = testing.allocator;

    // Test invalid JSON
    const invalid_json = "{ invalid json }";
    try testing.expectError(manifest.LockfileError.InvalidJSON, json_parser.parseLockfile(invalid_json, allocator));

    // Test unsupported version
    const unsupported_version = "{\"version\": 999, \"packages\": {}}";
    try testing.expectError(manifest.LockfileError.UnsupportedVersion, json_parser.parseLockfile(unsupported_version, allocator));

    // Test invalid content_id
    const invalid_content_id = "{\"version\": 1, \"packages\": {\"test\": {\"name\": \"test\", \"version\": \"1.0.0\", \"content_id\": \"invalid\", \"source\": {\"type\": \"git\", \"url\": \"test\", \"ref\": \"main\"}, \"capabilities\": [], \"dependencies\": []}}}";
    try testing.expectError(manifest.LockfileError.InvalidContentId, json_parser.parseLockfile(invalid_content_id, allocator));
}

test "manifest: complex KDL parsing with comments" {
    const allocator = testing.allocator;

    const kdl_with_comments =
        \\// Package manifest for test project
        \\name "complex-package"
        \\version "2.0.0-beta.1"
        \\
        \\// Production dependencies
        \\dependency "http-client" {
        \\    git "https://github.com/example/http-client.git" branch="main"
        \\    capability "net" hosts="*.api.example.com"
        \\    capability "fs" path="./cache" mode="rw"
        \\}
        \\
        \\dependency "crypto-utils" {
        \\    tar "https://releases.example.com/crypto-utils-3.1.0.tar.gz" checksum="sha256:abcd1234..."
        \\}
        \\
        \\// Development dependencies
        \\dev-dependency "test-framework" {
        \\    path "../test-framework"
        \\    capability "fs" path="./test-data"
        \\}
    ;

    var parsed_manifest = try kdl_parser.parseManifest(kdl_with_comments, allocator);
    defer parsed_manifest.deinit();

    try testing.expectEqualStrings("complex-package", parsed_manifest.name);
    try testing.expectEqualStrings("2.0.0-beta.1", parsed_manifest.version);
    try testing.expect(parsed_manifest.dependencies.len == 2);
    try testing.expect(parsed_manifest.dev_dependencies.len == 1);

    // Test tar source parsing
    const crypto_dep = parsed_manifest.dependencies[1];
    try testing.expectEqualStrings("crypto-utils", crypto_dep.name);
    switch (crypto_dep.source) {
        .tar => |tar| {
            try testing.expectEqualStrings("https://releases.example.com/crypto-utils-3.1.0.tar.gz", tar.url);
            try testing.expect(tar.checksum != null);
            try testing.expectEqualStrings("sha256:abcd1234...", tar.checksum.?);
        },
        else => try testing.expect(false),
    }
}
