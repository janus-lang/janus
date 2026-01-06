// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const CAS = @import("../../compiler/libjanus/ledger/cas.zig");

test "cas: BLAKE3 hash calculation" {
    const test_data = "Hello, Janus Ledger!";
    const hash1 = CAS.blake3Hash(test_data);
    const hash2 = CAS.blake3Hash(test_data);

    // Same input should produce same hash
    try testing.expectEqualSlices(u8, &hash1, &hash2);

    // Different input should produce different hash
    const different_data = "Hello, Different Data!";
    const hash3 = CAS.blake3Hash(different_data);
    try testing.expect(!std.mem.eql(u8, &hash1, &hash3));
}

test "cas: ContentId hex conversion" {
    const allocator = testing.allocator;

    const test_data = "test data for hashing";
    const content_id = CAS.blake3Hash(test_data);

    // Convert to hex
    const hex = try CAS.contentIdToHex(content_id, allocator);
    defer allocator.free(hex);

    // Should be 64 characters (32 bytes * 2)
    try testing.expect(hex.len == 64);

    // Convert back from hex
    const parsed_id = try CAS.hexToContentId(hex);
    try testing.expectEqualSlices(u8, &content_id, &parsed_id);
}

test "cas: archive normalization" {
    const allocator = testing.allocator;

    // Test CRLF normalization
    const crlf_data = "line1\r\nline2\r\nline3\r\n";
    const normalized = try CAS.normalizeArchive(crlf_data, allocator);
    defer allocator.free(normalized);

    const expected = "line1\nline2\nline3\n";
    try testing.expectEqualStrings(expected, normalized);

    // Test CR normalization
    const cr_data = "line1\rline2\rline3\r";
    const normalized_cr = try CAS.normalizeArchive(cr_data, allocator);
    defer allocator.free(normalized_cr);

    const expected_cr = "line1\nline2\nline3\n";
    try testing.expectEqualStrings(expected_cr, normalized_cr);
}

test "cas: normalized archive creation" {
    const allocator = testing.allocator;

    const entries = [_]CAS.ArchiveEntry{
        .{ .path = "src/main.zig", .content = "pub fn main() {}", .is_executable = false },
        .{ .path = "build.zig", .content = "const std = @import(\"std\");", .is_executable = false },
        .{ .path = "README.md", .content = "# Test Project", .is_executable = false },
    };

    const archive1 = try CAS.createNormalizedArchive(&entries, allocator);
    defer allocator.free(archive1);

    // Create same entries in different order
    const entries_reordered = [_]CAS.ArchiveEntry{
        .{ .path = "README.md", .content = "# Test Project", .is_executable = false },
        .{ .path = "src/main.zig", .content = "pub fn main() {}", .is_executable = false },
        .{ .path = "build.zig", .content = "const std = @import(\"std\");", .is_executable = false },
    };

    const archive2 = try CAS.createNormalizedArchive(&entries_reordered, allocator);
    defer allocator.free(archive2);

    // Should produce identical archives (deterministic ordering)
    try testing.expectEqualSlices(u8, archive1, archive2);

    // Hash should be identical
    const hash1 = CAS.blake3Hash(archive1);
    const hash2 = CAS.blake3Hash(archive2);
    try testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "cas: store and retrieve content" {
    const allocator = testing.allocator;
    const test_cas_root = "test_cas";

    // Clean up any existing test directory
    std.fs.cwd().deleteTree(test_cas_root) catch {};
    defer std.fs.cwd().deleteTree(test_cas_root) catch {};

    var cas = CAS.CAS.init(test_cas_root, allocator);
    defer cas.deinit();

    const test_content = "This is test content for the CAS";
    const content_id = try cas.hashArchive(test_content);

    // Store content
    try cas.store(content_id, test_content);

    // Verify it exists
    try testing.expect(cas.exists(content_id));

    // Retrieve content
    const retrieved = try cas.retrieve(content_id, allocator);
    defer allocator.free(retrieved);

    // Should match original
    try testing.expectEqualStrings(test_content, retrieved);

    // Verify integrity
    try testing.expect(try cas.verify(content_id));
}

test "cas: content integrity verification" {
    const allocator = testing.allocator;
    const test_cas_root = "test_cas_integrity";

    // Clean up any existing test directory
    std.fs.cwd().deleteTree(test_cas_root) catch {};
    defer std.fs.cwd().deleteTree(test_cas_root) catch {};

    var cas = CAS.CAS.init(test_cas_root, allocator);
    defer cas.deinit();

    const test_content = "Content for integrity testing";
    const content_id = try cas.hashArchive(test_content);

    // Store content
    try cas.store(content_id, test_content);

    // Verify integrity passes
    try testing.expect(try cas.verify(content_id));

    // Test with wrong content ID
    const wrong_content = "Different content";
    const wrong_id = try cas.hashArchive(wrong_content);

    // Should not exist
    try testing.expect(!cas.exists(wrong_id));

    // Verification should fail for non-existent content
    try testing.expect(!try cas.verify(wrong_id));
}

test "cas: error handling" {
    const allocator = testing.allocator;

    // Test invalid hex parsing
    try testing.expectError(CAS.CASError.InvalidContentId, CAS.hexToContentId("invalid"));
    try testing.expectError(CAS.CASError.InvalidContentId, CAS.hexToContentId("too_short"));

    // Test non-existent content retrieval
    var cas = CAS.CAS.init("nonexistent_cas", allocator);
    defer cas.deinit();

    const fake_id: CAS.ContentId = std.mem.zeroes(CAS.ContentId);
    try testing.expectError(CAS.CASError.ContentNotFound, cas.retrieve(fake_id, allocator));
}

test "cas: deterministic hashing across runs" {
    const allocator = testing.allocator;

    // Create identical archive entries
    const entries = [_]CAS.ArchiveEntry{
        .{ .path = "file1.txt", .content = "content1", .is_executable = false },
        .{ .path = "file2.txt", .content = "content2", .is_executable = true },
    };

    // Create archive multiple times
    const archive1 = try CAS.createNormalizedArchive(&entries, allocator);
    defer allocator.free(archive1);

    const archive2 = try CAS.createNormalizedArchive(&entries, allocator);
    defer allocator.free(archive2);

    // Should be byte-identical
    try testing.expectEqualSlices(u8, archive1, archive2);

    // Hashes should be identical
    const hash1 = CAS.blake3Hash(archive1);
    const hash2 = CAS.blake3Hash(archive2);
    try testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "cas: CAS initialization" {
    const test_cas_root = "test_cas_init";

    // Clean up any existing test directory
    std.fs.cwd().deleteTree(test_cas_root) catch {};
    defer std.fs.cwd().deleteTree(test_cas_root) catch {};

    // Initialize CAS
    try CAS.initializeCAS(test_cas_root);

    // Directory should exist
    const dir = try std.fs.cwd().openDir(test_cas_root, .{});
    dir.close();

    // Should be idempotent
    try CAS.initializeCAS(test_cas_root);
}

test "cas: large content handling" {
    const allocator = testing.allocator;
    const test_cas_root = "test_cas_large";

    // Clean up any existing test directory
    std.fs.cwd().deleteTree(test_cas_root) catch {};
    defer std.fs.cwd().deleteTree(test_cas_root) catch {};

    var cas = CAS.CAS.init(test_cas_root, allocator);
    defer cas.deinit();

    // Create large content (1MB)
    const large_content = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(large_content);

    // Fill with pattern
    for (large_content, 0..) |*byte, i| {
        byte.* = @as(u8, @intCast(i % 256));
    }

    const content_id = try cas.hashArchive(large_content);

    // Store and retrieve
    try cas.store(content_id, large_content);
    const retrieved = try cas.retrieve(content_id, allocator);
    defer allocator.free(retrieved);

    // Should match
    try testing.expectEqualSlices(u8, large_content, retrieved);
    try testing.expect(try cas.verify(content_id));
}
