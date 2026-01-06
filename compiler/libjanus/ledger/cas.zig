// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const blake3 = @import("blake3.zig");

// Content-Addressed Storage (CAS) Core
// Implements BLAKE3 tree hashing and project-local storage for verified dependencies
//
// This module provides the cryptographic foundation for the Janus Ledger,
// ensuring that every dependency is identified by a verifiable hash of its
// normalized source archive.
//
// The CAS embodies the principle of "Cryptographic Integrity & Verifiability":
// Every dependency SHALL be identified by the BLAKE2b hash of its normalized source archive.

pub const ContentId = [32]u8; // BLAKE2b hash (256 bits)

pub const CASError = error{
    InvalidContentId,
    ContentNotFound,
    CorruptedContent,
    NormalizationFailed,
    StorageError,
    OutOfMemory,
};

// Archive entry for normalization
const ArchiveEntry = struct {
    path: []const u8,
    content: []const u8,
    // Normalized metadata (no timestamps, permissions, etc.)
    is_executable: bool = false,
};

// Content-Addressed Storage implementation
pub const CAS = struct {
    root_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(root_path: []const u8, allocator: std.mem.Allocator) CAS {
        return CAS{
            .root_path = root_path,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CAS) void {
        _ = self;
        // CAS is stateless - no cleanup needed
    }

    // Calculate BLAKE2b hash of normalized source archive
    pub fn hashArchive(self: *CAS, archive_data: []const u8) !ContentId {

        // First normalize the archive
        const normalized = try normalizeArchive(archive_data, self.allocator);
        defer self.allocator.free(normalized);

        // Calculate BLAKE3 hash
        return blake3Hash(normalized);
    }

    // Store verified content in CAS with content-addressed path
    pub fn store(self: *CAS, content_id: ContentId, data: []const u8) !void {
        // Create CAS directory if it doesn't exist
        std.fs.cwd().makeDir(self.root_path) catch |err| switch (err) {
            error.PathAlreadyExists => {}, // OK
            else => return err,
        };

        // Generate content-addressed path: .janus/cas/blake3_hex/
        const hex_id = try contentIdToHex(content_id, self.allocator);
        defer self.allocator.free(hex_id);

        const content_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.root_path, hex_id });
        defer self.allocator.free(content_dir);

        // Create content directory
        std.fs.cwd().makeDir(content_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {}, // OK - content already exists
            else => return err,
        };

        // Write content to archive file
        const archive_path = try std.fs.path.join(self.allocator, &[_][]const u8{ content_dir, "archive" });
        defer self.allocator.free(archive_path);

        const file = try std.fs.cwd().createFile(archive_path, .{});
        defer file.close();
        try file.writeAll(data);
    }

    // Retrieve content by CID
    pub fn retrieve(self: *CAS, content_id: ContentId, allocator: std.mem.Allocator) ![]u8 {
        const hex_id = try contentIdToHex(content_id, self.allocator);
        defer self.allocator.free(hex_id);

        const archive_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.root_path, hex_id, "archive" });
        defer self.allocator.free(archive_path);

        // Read the archive file
        const file = std.fs.cwd().openFile(archive_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return CASError.ContentNotFound,
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024 * 100); // 100MB max
        return content;
    }

    // Verify integrity of stored content
    pub fn verify(self: *CAS, content_id: ContentId) !bool {
        // Retrieve the content
        const content = self.retrieve(content_id, self.allocator) catch |err| switch (err) {
            CASError.ContentNotFound => return false,
            else => return err,
        };
        defer self.allocator.free(content);

        // Recalculate hash and compare
        const calculated_id = try self.hashArchive(content);
        return std.mem.eql(u8, &content_id, &calculated_id);
    }

    // Check if content exists in CAS
    pub fn exists(self: *CAS, content_id: ContentId) bool {
        const hex_id = contentIdToHex(content_id, self.allocator) catch return false;
        defer self.allocator.free(hex_id);

        const archive_path = std.fs.path.join(self.allocator, &[_][]const u8{ self.root_path, hex_id, "archive" }) catch return false;
        defer self.allocator.free(archive_path);

        const file = std.fs.cwd().openFile(archive_path, .{}) catch return false;
        file.close();
        return true;
    }
};

// Calculate BLAKE3 hash of data (256-bit output)
// Uses the official BLAKE3 implementation via C bindings
pub fn blake3Hash(data: []const u8) ContentId {
    return blake3.hash(data);
}

// Convert ContentId to hex string
pub fn contentIdToHex(content_id: ContentId, allocator: std.mem.Allocator) ![]u8 {
    const hex_chars = "0123456789abcdef";
    var hex = try allocator.alloc(u8, content_id.len * 2);

    for (content_id, 0..) |byte, i| {
        hex[i * 2] = hex_chars[byte >> 4];
        hex[i * 2 + 1] = hex_chars[byte & 0xF];
    }

    return hex;
}

// Parse hex string to ContentId
pub fn hexToContentId(hex: []const u8) !ContentId {
    if (hex.len != 64) return CASError.InvalidContentId; // 32 bytes * 2 hex chars

    var content_id: ContentId = undefined;
    for (0..32) |i| {
        const high = try std.fmt.charToDigit(hex[i * 2], 16);
        const low = try std.fmt.charToDigit(hex[i * 2 + 1], 16);
        content_id[i] = (high << 4) | low;
    }

    return content_id;
}

// Archive normalization for reproducible hashing
// Strips timestamps, permissions, and other non-deterministic metadata
pub fn normalizeArchive(archive_data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // For now, implement a simple normalization that sorts entries by path
    // and strips metadata. In a full implementation, this would handle
    // tar/zip archives with proper metadata stripping.

    // Simple implementation: assume archive_data is already a normalized format
    // or is raw source code that doesn't need complex normalization

    var normalized = std.ArrayList(u8).init(allocator);
    defer normalized.deinit();

    // For source code files, normalize line endings to LF
    var i: usize = 0;
    while (i < archive_data.len) {
        if (i + 1 < archive_data.len and archive_data[i] == '\r' and archive_data[i + 1] == '\n') {
            // Convert CRLF to LF
            try normalized.append('\n');
            i += 2;
        } else if (archive_data[i] == '\r') {
            // Convert CR to LF
            try normalized.append('\n');
            i += 1;
        } else {
            try normalized.append(archive_data[i]);
            i += 1;
        }
    }

    return try allocator.dupe(u8, normalized.items);
}

// Create a normalized archive from a directory structure
pub fn createNormalizedArchive(entries: []const ArchiveEntry, allocator: std.mem.Allocator) ![]u8 {
    // Sort entries by path for deterministic ordering
    const sorted_entries = try allocator.dupe(ArchiveEntry, entries);
    defer allocator.free(sorted_entries);

    std.sort.insertion(ArchiveEntry, sorted_entries, {}, compareArchiveEntries);

    // Create a simple archive format:
    // [path_len:u32][path][content_len:u32][content][flags:u8]
    var archive = std.ArrayList(u8).init(allocator);
    defer archive.deinit();

    for (sorted_entries) |entry| {
        // Write path length and path
        const path_len = @as(u32, @intCast(entry.path.len));
        try archive.writer().writeInt(u32, path_len, .little);
        try archive.appendSlice(entry.path);

        // Write content length and content
        const content_len = @as(u32, @intCast(entry.content.len));
        try archive.writer().writeInt(u32, content_len, .little);
        try archive.appendSlice(entry.content);

        // Write flags
        const flags: u8 = if (entry.is_executable) 1 else 0;
        try archive.append(flags);
    }

    return try allocator.dupe(u8, archive.items);
}

// Compare function for sorting archive entries
fn compareArchiveEntries(context: void, a: ArchiveEntry, b: ArchiveEntry) bool {
    _ = context;
    return std.mem.lessThan(u8, a.path, b.path);
}

// Utility function to create CAS directory structure
pub fn initializeCAS(cas_root: []const u8) !void {
    std.fs.cwd().makeDir(cas_root) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // OK
        else => return err,
    };
}
