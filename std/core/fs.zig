// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Standard Library - :core Profile File System Module
//!
//! Simple file system operations for the :core profile.
//! Teaching-friendly API with clear semantics.
//!
//! Functions:
//! - readFile(path)       - Read entire file as string
//! - writeFile(path, content) - Write content to file
//! - listDirectory(path)  - List directory contents
//! - isDirectory(path)    - Check if path is a directory
//! - isFile(path)         - Check if path is a file
//! - exists(path)         - Check if path exists
//! - fileSize(path)       - Get file size in bytes

const std = @import("std");
const compat_fs = @import("compat_fs");

/// File system errors for :core profile
pub const FsError = error{
    FileNotFound,
    PermissionDenied,
    NotADirectory,
    NotAFile,
    InvalidPath,
    OutOfMemory,
    IoError,
};

/// Directory entry information
pub const DirEntry = struct {
    name: []const u8,
    is_dir: bool,
    size: u64,

    pub fn deinit(self: DirEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

// =============================================================================
// FILE OPERATIONS
// =============================================================================

/// Read entire file contents as a string
/// Caller owns the returned memory and must free it.
///
/// Example:
/// ```janus
/// let content = fs.readFile("hello.txt")
/// io.println(content)
/// ```
pub fn readFile(allocator: std.mem.Allocator, path: []const u8) FsError![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => FsError.FileNotFound,
            error.AccessDenied => FsError.PermissionDenied,
            error.NameTooLong, error.InvalidUtf8, error.BadPathName => FsError.InvalidPath,
            else => FsError.IoError,
        };
    };
    defer file.close();

    const stat = file.stat() catch return FsError.IoError;
    const content = allocator.alloc(u8, stat.size) catch return FsError.OutOfMemory;

    const bytes_read = file.readAll(content) catch {
        allocator.free(content);
        return FsError.IoError;
    };

    // Shrink if needed (shouldn't happen for regular files)
    if (bytes_read < stat.size) {
        return allocator.realloc(content, bytes_read) catch {
            allocator.free(content);
            return FsError.OutOfMemory;
        };
    }

    return content;
}

/// Write content to a file (creates or overwrites)
///
/// Example:
/// ```janus
/// fs.writeFile("output.txt", "Hello, World!")
/// ```
pub fn writeFile(path: []const u8, content: []const u8) FsError!void {
    const file = compat_fs.createFile(path, .{}) catch |err| {
        return switch (err) {
            error.AccessDenied => FsError.PermissionDenied,
            error.NameTooLong, error.InvalidUtf8, error.BadPathName => FsError.InvalidPath,
            else => FsError.IoError,
        };
    };
    defer file.close();

    file.writeAll(content) catch return FsError.IoError;
}

/// Append content to a file (creates if doesn't exist)
pub fn appendFile(path: []const u8, content: []const u8) FsError!void {
    const file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch |err| {
        return switch (err) {
            error.FileNotFound => {
                // Create the file if it doesn't exist
                return writeFile(path, content);
            },
            error.AccessDenied => FsError.PermissionDenied,
            else => FsError.IoError,
        };
    };
    defer file.close();

    file.seekFromEnd(0) catch return FsError.IoError;
    file.writeAll(content) catch return FsError.IoError;
}

// =============================================================================
// DIRECTORY OPERATIONS
// =============================================================================

/// List all entries in a directory
/// Returns array of DirEntry structs. Caller must free entries and the array.
///
/// Example:
/// ```janus
/// let entries = fs.listDirectory(".")
/// for entry in entries {
///     if entry.is_dir {
///         io.println("[DIR] " + entry.name)
///     } else {
///         io.println("      " + entry.name)
///     }
/// }
/// ```
pub fn listDirectory(allocator: std.mem.Allocator, path: []const u8) FsError![]DirEntry {
    var dir = compat_fs.openDir(path, .{ .iterate = true }) catch |err| {
        return switch (err) {
            error.FileNotFound => FsError.FileNotFound,
            error.AccessDenied => FsError.PermissionDenied,
            error.NotDir => FsError.NotADirectory,
            else => FsError.IoError,
        };
    };
    defer dir.close();

    var entries = std.ArrayListUnmanaged(DirEntry){};
    errdefer {
        for (entries.items) |entry| {
            entry.deinit(allocator);
        }
        entries.deinit(allocator);
    }

    var iter = dir.iterate();
    while (iter.next() catch return FsError.IoError) |entry| {
        const name = allocator.dupe(u8, entry.name) catch return FsError.OutOfMemory;

        // Get size for files
        const size: u64 = if (entry.kind == .file) blk: {
            const stat = dir.statFile(entry.name) catch break :blk 0;
            break :blk stat.size;
        } else 0;

        entries.append(allocator, .{
            .name = name,
            .is_dir = entry.kind == .directory,
            .size = size,
        }) catch {
            allocator.free(name);
            return FsError.OutOfMemory;
        };
    }

    return entries.toOwnedSlice(allocator) catch return FsError.OutOfMemory;
}

/// Get just the names of entries in a directory (simpler API)
/// Caller must free each name and the array.
pub fn listDirectoryNames(allocator: std.mem.Allocator, path: []const u8) FsError![][]const u8 {
    const entries = try listDirectory(allocator, path);
    defer {
        for (entries) |entry| {
            entry.deinit(allocator);
        }
        allocator.free(entries);
    }

    var names = std.ArrayListUnmanaged([]const u8){};
    errdefer names.deinit(allocator);

    for (entries) |entry| {
        const name = allocator.dupe(u8, entry.name) catch return FsError.OutOfMemory;
        names.append(allocator, name) catch {
            allocator.free(name);
            return FsError.OutOfMemory;
        };
    }

    return names.toOwnedSlice(allocator) catch return FsError.OutOfMemory;
}

// =============================================================================
// PATH QUERIES
// =============================================================================

/// Check if a path exists (file or directory)
///
/// Example:
/// ```janus
/// if fs.exists("config.json") {
///     io.println("Config found!")
/// }
/// ```
pub fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Check if path is a directory
///
/// Example:
/// ```janus
/// if fs.isDirectory(path) {
///     io.println(path + " is a directory")
/// }
/// ```
pub fn isDirectory(path: []const u8) bool {
    const stat = compat_fs.statFile(path) catch return false;
    return stat.kind == .directory;
}

/// Check if path is a regular file
///
/// Example:
/// ```janus
/// if fs.isFile(path) {
///     io.println(path + " is a file")
/// }
/// ```
pub fn isFile(path: []const u8) bool {
    const stat = compat_fs.statFile(path) catch return false;
    return stat.kind == .file;
}

/// Get file size in bytes (returns 0 for directories or non-existent paths)
pub fn fileSize(path: []const u8) u64 {
    const stat = compat_fs.statFile(path) catch return 0;
    return stat.size;
}

/// Get the current working directory
pub fn cwd(allocator: std.mem.Allocator) FsError![]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fs.cwd().realpath(".", &buf) catch return FsError.IoError;
    return allocator.dupe(u8, path) catch return FsError.OutOfMemory;
}

// =============================================================================
// FILE MANAGEMENT
// =============================================================================

/// Delete a file
pub fn deleteFile(path: []const u8) FsError!void {
    compat_fs.deleteFile(path) catch |err| {
        return switch (err) {
            error.FileNotFound => FsError.FileNotFound,
            error.AccessDenied => FsError.PermissionDenied,
            else => FsError.IoError,
        };
    };
}

/// Create a directory
pub fn createDirectory(path: []const u8) FsError!void {
    compat_fs.makeDir(path) catch |err| {
        return switch (err) {
            error.AccessDenied => FsError.PermissionDenied,
            else => FsError.IoError,
        };
    };
}

/// Delete an empty directory
pub fn deleteDirectory(path: []const u8) FsError!void {
    std.fs.cwd().deleteDir(path) catch |err| {
        return switch (err) {
            error.FileNotFound => FsError.FileNotFound,
            error.AccessDenied => FsError.PermissionDenied,
            error.DirNotEmpty => FsError.IoError,
            else => FsError.IoError,
        };
    };
}

// =============================================================================
// TESTS
// =============================================================================

test "exists and path queries" {
    // Test with current directory (should always exist)
    try std.testing.expect(exists("."));
    try std.testing.expect(isDirectory("."));
    try std.testing.expect(!isFile("."));

    // Test with non-existent path
    try std.testing.expect(!exists("__nonexistent_path_12345__"));
    try std.testing.expect(!isDirectory("__nonexistent_path_12345__"));
    try std.testing.expect(!isFile("__nonexistent_path_12345__"));
}

test "file read/write" {
    const allocator = std.testing.allocator;
    const test_path = "/tmp/janus_core_fs_test.txt";
    const test_content = "Hello from :core profile!";

    // Clean up any existing test file
    deleteFile(test_path) catch {};

    // Write test file
    try writeFile(test_path, test_content);
    defer deleteFile(test_path) catch {};

    // Verify it exists
    try std.testing.expect(exists(test_path));
    try std.testing.expect(isFile(test_path));
    try std.testing.expect(!isDirectory(test_path));

    // Read and verify content
    const content = try readFile(allocator, test_path);
    defer allocator.free(content);
    try std.testing.expectEqualStrings(test_content, content);

    // Verify file size
    try std.testing.expectEqual(@as(u64, test_content.len), fileSize(test_path));
}

test "list directory" {
    const allocator = std.testing.allocator;

    // List current directory (should succeed)
    const entries = try listDirectory(allocator, ".");
    defer {
        for (entries) |entry| {
            entry.deinit(allocator);
        }
        allocator.free(entries);
    }

    // Should have at least some entries
    try std.testing.expect(entries.len > 0);
}

test "cwd" {
    const allocator = std.testing.allocator;
    const path = try cwd(allocator);
    defer allocator.free(path);

    // Should return a non-empty path
    try std.testing.expect(path.len > 0);
}
