// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const testing = std.testing;
const transport = @import("../../compiler/libjanus/ledger/transport.zig");
const cas = @import("../../compiler/libjanus/ledger/cas.zig");

test "transport: registry creation and transport lookup" {
    const allocator = testing.allocator;

    var registry = try transport.createDefaultRegistry(allocator);
    defer registry.deinit();

    // Test git+https transport lookup
    const git_transport = registry.findTransport("git+https://github.com/example/repo.git");
    try testing.expect(git_transport != null);
    try testing.expectEqualStrings("git+https", git_transport.?.name);

    // Test https git transport lookup
    const https_git_transport = registry.findTransport("https://github.com/example/repo.git");
    try testing.expect(https_git_transport != null);
    try testing.expectEqualStrings("git+https", https_git_transport.?.name);

    // Test file transport lookup
    const file_transport = registry.findTransport("file:///path/to/local/repo");
    try testing.expect(file_transport != null);
    try testing.expectEqualStrings("file", file_transport.?.name);

    // Test unsupported scheme
    const unsupported = registry.findTransport("ftp://example.com/file");
    try testing.expect(unsupported == null);
}

test "transport: git URL parsing" {
    const allocator = testing.allocator;

    // Test various git URL formats
    const test_cases = [_]struct {
        url: []const u8,
        expected_repo: []const u8,
        expected_ref: []const u8,
        expected_type: []const u8,
    }{
        .{
            .url = "git+https://github.com/example/repo.git#tag=v1.0.0",
            .expected_repo = "https://github.com/example/repo.git",
            .expected_ref = "v1.0.0",
            .expected_type = "tag",
        },
        .{
            .url = "https://github.com/example/repo.git#branch=main",
            .expected_repo = "https://github.com/example/repo.git",
            .expected_ref = "main",
            .expected_type = "branch",
        },
        .{
            .url = "git+https://github.com/example/repo.git#commit=abc123",
            .expected_repo = "https://github.com/example/repo.git",
            .expected_ref = "abc123",
            .expected_type = "commit",
        },
        .{
            .url = "https://github.com/example/repo.git",
            .expected_repo = "https://github.com/example/repo.git",
            .expected_ref = "main",
            .expected_type = "branch",
        },
    };

    // Note: This test would require access to the internal parseGitUrl function
    // In a real implementation, we might expose this for testing or test it indirectly
    std.debug.print("Git URL parsing test cases defined (would test parseGitUrl function)\n", .{});
}

test "transport: URL validation" {
    const allocator = testing.allocator;

    var registry = try transport.createDefaultRegistry(allocator);
    defer registry.deinit();

    // Test git+https URL validation
    const git_transport = registry.findTransport("git+https://github.com/example/repo.git").?;

    try testing.expect(git_transport.validateUrl("git+https://github.com/example/repo.git"));
    try testing.expect(git_transport.validateUrl("https://github.com/example/repo.git"));
    try testing.expect(!git_transport.validateUrl("https://example.com/not-a-git-repo"));
    try testing.expect(!git_transport.validateUrl("ftp://example.com/repo.git"));

    // Test file URL validation
    const file_transport = registry.findTransport("file:///path/to/repo").?;

    try testing.expect(file_transport.validateUrl("file:///absolute/path"));
    try testing.expect(file_transport.validateUrl("file://./relative/path"));
    try testing.expect(!file_transport.validateUrl("/absolute/path/without/scheme"));
    try testing.expect(!file_transport.validateUrl("https://example.com/file"));
}

test "transport: file transport with test directory" {
    const allocator = testing.allocator;

    // Create test directory structure
    const test_dir = "test_transport_dir";
    compat_fs.deleteTree(test_dir) catch {};
    defer compat_fs.deleteTree(test_dir) catch {};

    try compat_fs.makeDir(test_dir);

    // Create test files
    try compat_fs.writeFile(.{ .sub_path = test_dir ++ "/file1.txt", .data = "Hello, World!" });
    try compat_fs.writeFile(.{ .sub_path = test_dir ++ "/file2.txt", .data = "Janus Ledger" });

    // Create subdirectory with file
    try compat_fs.makeDir(test_dir ++ "/subdir");
    try compat_fs.writeFile(.{ .sub_path = test_dir ++ "/subdir/file3.txt", .data = "Nested content" });

    var registry = try transport.createDefaultRegistry(allocator);
    defer registry.deinit();

    // Fetch directory as archive
    const url = "file://" ++ test_dir;
    var result = try registry.fetch(url, allocator);
    defer result.deinit();

    // Verify metadata
    try testing.expectEqualStrings("file", result.metadata.get("transport").?);
    try testing.expectEqualStrings(test_dir, result.metadata.get("path").?);
    try testing.expectEqualStrings("directory", result.metadata.get("kind").?);

    // Verify content is not empty (archive format)
    try testing.expect(result.content.len > 0);

    // Verify content ID is deterministic
    var result2 = try registry.fetch(url, allocator);
    defer result2.deinit();

    try testing.expectEqualSlices(u8, &result.content_id, &result2.content_id);
}

test "transport: file transport with single file" {
    const allocator = testing.allocator;

    // Create test file
    const test_file = "test_transport_file.txt";
    const test_content = "This is test content for transport";

    try compat_fs.writeFile(.{ .sub_path = test_file, .data = test_content });
    defer compat_fs.deleteFile(test_file) catch {};

    var registry = try transport.createDefaultRegistry(allocator);
    defer registry.deinit();

    // Fetch single file
    const url = "file://" ++ test_file;
    var result = try registry.fetch(url, allocator);
    defer result.deinit();

    // Verify metadata
    try testing.expectEqualStrings("file", result.metadata.get("transport").?);
    try testing.expectEqualStrings(test_file, result.metadata.get("path").?);
    try testing.expectEqualStrings("file", result.metadata.get("kind").?);

    // Verify content matches (after normalization)
    const expected_content = try cas.normalizeArchive(test_content, allocator);
    defer allocator.free(expected_content);

    try testing.expectEqualSlices(u8, expected_content, result.content);
}

test "transport: integrity verification" {
    const allocator = testing.allocator;

    // Create test file
    const test_file = "test_integrity_file.txt";
    const test_content = "Content for integrity testing";

    try compat_fs.writeFile(.{ .sub_path = test_file, .data = test_content });
    defer compat_fs.deleteFile(test_file) catch {};

    var registry = try transport.createDefaultRegistry(allocator);
    defer registry.deinit();

    const url = "file://" ++ test_file;

    // First fetch to get the actual content ID
    var initial_result = try registry.fetch(url, allocator);
    const expected_id = initial_result.content_id;
    initial_result.deinit();

    // Fetch with correct expected content ID
    var verified_result = try transport.fetchWithVerification(&registry, url, expected_id, allocator);
    defer verified_result.deinit();

    try testing.expectEqualSlices(u8, &expected_id, &verified_result.content_id);

    // Test with wrong expected content ID
    var wrong_id: cas.ContentId = std.mem.zeroes(cas.ContentId);
    wrong_id[0] = 0xFF; // Make it different

    try testing.expectError(transport.TransportError.IntegrityCheckFailed, transport.fetchWithVerification(&registry, url, wrong_id, allocator));
}

test "transport: error handling" {
    const allocator = testing.allocator;

    var registry = try transport.createDefaultRegistry(allocator);
    defer registry.deinit();

    // Test unsupported scheme
    try testing.expectError(transport.TransportError.UnsupportedScheme, registry.fetch("ftp://example.com/file", allocator));

    // Test non-existent file
    try testing.expectError(transport.TransportError.ContentNotFound, registry.fetch("file:///non/existent/file", allocator));
}

test "transport: git availability check" {
    const allocator = testing.allocator;

    const git_available = transport.checkGitAvailable(allocator);
    std.debug.print("Git available: {}\n", .{git_available});

    // This test just verifies the function runs without crashing
    // The result depends on the test environment
}

test "transport: archive normalization determinism" {
    const allocator = testing.allocator;

    // Create test directory with files that have different timestamps
    const test_dir = "test_normalization_dir";
    compat_fs.deleteTree(test_dir) catch {};
    defer compat_fs.deleteTree(test_dir) catch {};

    try compat_fs.makeDir(test_dir);

    // Create files with different content but same logical structure
    try compat_fs.writeFile(.{ .sub_path = test_dir ++ "/a.txt", .data = "line1\r\nline2\r\n" });
    try compat_fs.writeFile(.{ .sub_path = test_dir ++ "/b.txt", .data = "content B" });

    // Wait a moment to ensure different timestamps
    std.time.sleep(1000000); // 1ms

    // Create the same files again in a different directory
    const test_dir2 = "test_normalization_dir2";
    compat_fs.deleteTree(test_dir2) catch {};
    defer compat_fs.deleteTree(test_dir2) catch {};

    try compat_fs.makeDir(test_dir2);
    try compat_fs.writeFile(.{ .sub_path = test_dir2 ++ "/a.txt", .data = "line1\nline2\n" }); // Different line endings
    try compat_fs.writeFile(.{ .sub_path = test_dir2 ++ "/b.txt", .data = "content B" });

    var registry = try transport.createDefaultRegistry(allocator);
    defer registry.deinit();

    // Fetch both directories
    var result1 = try registry.fetch("file://" ++ test_dir, allocator);
    defer result1.deinit();

    var result2 = try registry.fetch("file://" ++ test_dir2, allocator);
    defer result2.deinit();

    // Content IDs should be identical due to normalization
    try testing.expectEqualSlices(u8, &result1.content_id, &result2.content_id);
}
