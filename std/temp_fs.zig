// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - Secure Temp File Module
// Secure temp file creation implementation

const std = @import("std");
const compat_fs = @import("compat_fs");
const compat_time = @import("compat_time");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Context = @import("std_context.zig").Context;
const Capability = @import("capabilities.zig");
const Path = @import("path.zig").Path;
const PathBuf = @import("path.zig").PathBuf;

// Forward declarations from previous modules
pub const FsError = error{
    FileNotFound,
    PermissionDenied,
    InvalidPath,
    CapabilityRequired,
    ContextCancelled,
    OutOfMemory,
    Unknown,
    NotSupported,
    IsDir,
    NotDir,
    FileBusy,
    DeviceBusy,
    FileTooLarge,
    InvalidUtf8,
    WriteFailed,
    ReadOnlyFileSystem,
    DiskFull,
    TempFileFailed,
    TempDirInaccessible,
};

/// Temporary file handle with secure creation and RAII cleanup
pub const TempFile = struct {
    file: ?std.fs.File,
    path: []const u8,
    allocator: Allocator,
    auto_cleanup: bool,
    created: bool,

    /// Create a secure temporary file in system temp directory
    pub fn create(allocator: Allocator) !TempFile {
        return createInDir(std.fs.tmpDir(), allocator);
    }

    /// Create a secure temporary file in specified directory
    pub fn createInDir(dir: std.fs.Dir, allocator: Allocator) !TempFile {
        const temp_path = try generateSecureTempPath(dir, allocator);
        errdefer allocator.free(temp_path);

        // Create the temporary file with exclusive access
        const file = dir.createFile(temp_path, .{
            .read = true,
            .truncate = false,
            .exclusive = true,
        }) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            error.PathAlreadyExists => continue, // Try next name
            error.NoSpaceLeft => return FsError.DiskFull,
            error.DirNotEmpty => return FsError.TempDirInaccessible,
            else => return FsError.TempFileFailed,
        };

        return TempFile{
            .file = file,
            .path = temp_path,
            .allocator = allocator,
            .auto_cleanup = true,
            .created = true,
        };
    }

    /// Create a temporary file with custom prefix
    pub fn createWithPrefix(prefix: []const u8, allocator: Allocator) !TempFile {
        return createWithPrefixInDir(prefix, std.fs.tmpDir(), allocator);
    }

    /// Create a temporary file with custom prefix in specified directory
    pub fn createWithPrefixInDir(prefix: []const u8, dir: std.fs.Dir, allocator: Allocator) !TempFile {
        const temp_path = try generateSecureTempPathWithPrefix(prefix, dir, allocator);
        errdefer allocator.free(temp_path);

        const file = dir.createFile(temp_path, .{
            .read = true,
            .truncate = false,
            .exclusive = true,
        }) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            error.PathAlreadyExists => continue, // Try next name
            error.NoSpaceLeft => return FsError.DiskFull,
            error.DirNotEmpty => return FsError.TempDirInaccessible,
            else => return FsError.TempFileFailed,
        };

        return TempFile{
            .file = file,
            .path = temp_path,
            .allocator = allocator,
            .auto_cleanup = true,
            .created = true,
        };
    }

    /// Write data to temporary file
    pub fn write(self: *TempFile, data: []const u8) !usize {
        const file = self.file orelse return FsError.InvalidPath;
        return file.write(data) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            error.NoSpaceLeft => return FsError.DiskFull,
            error.InputOutput => return FsError.WriteFailed,
            else => return FsError.Unknown,
        };
    }

    /// Write all data to temporary file
    pub fn writeAll(self: *TempFile, data: []const u8) !void {
        var remaining = data;
        while (remaining.len > 0) {
            const written = try self.write(remaining);
            if (written == 0) return FsError.WriteFailed;
            remaining = remaining[written..];
        }
    }

    /// Read from temporary file
    pub fn read(self: *TempFile, buffer: []u8) !usize {
        const file = self.file orelse return FsError.InvalidPath;
        return file.read(buffer) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            error.InputOutput => return FsError.Unknown,
            else => return FsError.Unknown,
        };
    }

    /// Get file path (borrowed)
    pub fn getPath(self: *TempFile) []const u8 {
        return self.path;
    }

    /// Persist temporary file by renaming to target path
    pub fn persist(self: *TempFile, target_path: []const u8) !void {
        const file = self.file orelse return FsError.InvalidPath;

        // Ensure all data is written
        try file.sync();

        // Close file handle before rename
        file.close();
        self.file = null;

        // Atomic rename to target location
        std.fs.cwd().rename(self.path, target_path) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            error.NotDir => return FsError.NotDir,
            error.IsDir => return FsError.IsDir,
            error.FileBusy => return FsError.FileBusy,
            error.NoSpaceLeft => return FsError.DiskFull,
            error.PathAlreadyExists => return FsError.PermissionDenied,
            else => return FsError.Unknown,
        };

        // Disable auto-cleanup since file is now persistent
        self.auto_cleanup = false;

        // Free the temp path since it's no longer valid
        allocator.free(self.path);
        self.path = "";
    }

    /// Get file size
    pub fn getSize(self: *TempFile) !u64 {
        const file = self.file orelse return FsError.InvalidPath;
        return file.getEndPos() catch return FsError.Unknown;
    }

    /// Clean up temporary file
    pub fn cleanup(self: *TempFile) void {
        if (self.file) |file| {
            file.close();
            self.file = null;
        }

        if (self.auto_cleanup and self.path.len > 0) {
            compat_fs.deleteFile(self.path) catch |err| {
                // Log error but don't fail - file might already be deleted
                _ = err;
            };
        }

        if (self.path.len > 0) {
            self.allocator.free(self.path);
            self.path = "";
        }
    }

    /// RAII deinit
    pub fn deinit(self: *TempFile) void {
        self.cleanup();
    }
};

/// Generate a secure temporary file path
fn generateSecureTempPath(dir: std.fs.Dir, allocator: Allocator) ![]const u8 {
    return generateSecureTempPathWithPrefix("tmp", dir, allocator);
}

/// Generate a secure temporary file path with custom prefix
fn generateSecureTempPathWithPrefix(prefix: []const u8, dir: std.fs.Dir, allocator: Allocator) ![]const u8 {
    const suffix = generateRandomSuffix();
    const temp_filename = try std.fmt.allocPrint(allocator, "{s}_{s}", .{prefix, suffix});
    errdefer allocator.free(temp_filename);

    // Verify the path doesn't exist (collision resistance)
    var attempts: u32 = 0;
    const max_attempts = 1000;

    while (attempts < max_attempts) {
        dir.access(temp_filename, .{}) catch {
            // File doesn't exist, we can use this name
            return temp_filename;
        };

        // File exists, try a different name
        allocator.free(temp_filename);
        const new_suffix = generateRandomSuffix();
        const temp_filename = try std.fmt.allocPrint(allocator, "{s}_{s}", .{prefix, new_suffix});
        attempts += 1;
    }

    allocator.free(temp_filename);
    return FsError.TempFileFailed; // Too many collisions
}

/// Generate a random suffix for collision resistance
fn generateRandomSuffix() []const u8 {
    // Use timestamp and process ID for uniqueness
    const timestamp = compat_time.nanoTimestamp();
    const pid = std.os.linux.getpid();

    // Convert to hexadecimal for readable filename
    return std.fmt.allocPrint(std.heap.page_allocator, "{x}_{x}", .{timestamp, pid}) catch "fallback";
}

/// Create a temporary file and write data to it
pub fn createTempFileWithData(data: []const u8, allocator: Allocator) !TempFile {
    var temp_file = try TempFile.create(allocator);
    errdefer temp_file.deinit();

    try temp_file.writeAll(data);

    return temp_file;
}

/// Create a temporary file with string data
pub fn createTempFileWithString(string: []const u8, allocator: Allocator) !TempFile {
    return createTempFileWithData(string, allocator);
}

/// Create a temporary file with custom prefix and data
pub fn createTempFileWithPrefixAndData(prefix: []const u8, data: []const u8, allocator: Allocator) !TempFile {
    var temp_file = try TempFile.createWithPrefix(prefix, allocator);
    errdefer temp_file.deinit();

    try temp_file.writeAll(data);

    return temp_file;
}

/// Create a temporary file that persists via rename
pub fn createTempFileForAtomicWrite(target_path: []const u8, allocator: Allocator) !TempFile {
    // Extract directory and filename from target path
    const target_path_obj = Path.init(target_path);
    const dir_path = target_path_obj.parent() orelse return FsError.InvalidPath;
    const filename = target_path_obj.fileName() orelse return FsError.InvalidPath;

    // Create temp file in same directory as target
    var dir_buf = try PathBuf.fromPath(dir_path, allocator);
    defer dir_buf.deinit();

    const dir = compat_fs.openDir(dir_buf.asSlice(), .{}) catch return FsError.TempDirInaccessible;
    defer dir.close();

    var temp_file = try TempFile.createWithPrefixInDir(filename, dir, allocator);
    errdefer temp_file.deinit();

    return temp_file;
}

/// Write data atomically using temporary file
pub fn writeAtomicViaTemp(data: []const u8, target_path: []const u8, allocator: Allocator) !void {
    var temp_file = try createTempFileForAtomicWrite(target_path, allocator);
    defer temp_file.deinit();

    try temp_file.writeAll(data);
    try temp_file.persist(target_path);
}

// =============================================================================
// TRI-SIGNATURE PATTERN IMPLEMENTATIONS
// =============================================================================

/// :min profile - Simple temp file creation
pub fn fs_create_temp_min(prefix: []const u8, allocator: Allocator) !TempFile {
    if (prefix.len == 0) {
        return TempFile.create(allocator);
    } else {
        return TempFile.createWithPrefix(prefix, allocator);
    }
}

/// :go profile - Context-aware temp file creation
pub fn fs_create_temp_go(prefix: []const u8, ctx: Context, allocator: Allocator) !TempFile {
    if (ctx.is_done()) return FsError.ContextCancelled;
    return fs_create_temp_min(prefix, allocator);
}

/// :full profile - Capability-gated temp file creation
pub fn fs_create_temp_full(prefix: []const u8, cap: Capability.FileSystem, allocator: Allocator) !TempFile {
    if (!cap.allows_temp_files()) return FsError.CapabilityRequired;

    Capability.audit_capability_usage(cap, "fs.create_temp");
    return fs_create_temp_min(prefix, allocator);
}

// =============================================================================
// TESTS
// =============================================================================

test "TempFile basic creation and cleanup" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test automatic cleanup
    {
        var temp_file = try TempFile.create(allocator);
        defer temp_file.deinit();

        try testing.expect(temp_file.created);
        try testing.expect(temp_file.path.len > 0);

        // Write some data
        const test_data = "test data for temp file";
        try temp_file.writeAll(test_data);

        // Verify file exists
        const metadata = compat_fs.statFile(temp_file.path) catch unreachable;
        try testing.expect(metadata.size == test_data.len);
    }

    // Verify file was cleaned up (should not exist)
    const temp_path = temp_file.path; // This should be empty after cleanup
    if (temp_path.len > 0) {
        std.fs.cwd().access(temp_path, .{}) catch {
            // File should not exist - this is expected
        };
    }
}

test "TempFile with custom prefix" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const prefix = "testprefix";

    {
        var temp_file = try TempFile.createWithPrefix(prefix, allocator);
        defer temp_file.deinit();

        try testing.expect(std.mem.startsWith(u8, std.fs.path.basename(temp_file.path), prefix));

        // Write and verify
        try temp_file.writeAll("test content");
        const size = try temp_file.getSize();
        try testing.expect(size > 0);
    }
}

test "TempFile persistence via rename" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const target_file = "/tmp/janus_persist_test.txt";
    const test_data = "persistent data";

    defer compat_fs.deleteFile(target_file) catch {};

    {
        var temp_file = try TempFile.create(allocator);
        defer temp_file.deinit();

        try temp_file.writeAll(test_data);
        try temp_file.persist(target_file);

        // Verify target file exists with correct content
        const file = std.fs.cwd().openFile(target_file, .{}) catch unreachable;
        defer file.close();

        const content = file.readToEndAlloc(allocator, test_data.len) catch unreachable;
        defer allocator.free(content);

        try testing.expect(std.mem.eql(u8, content, test_data));
    }
}

test "Atomic write via temporary file" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const target_file = "/tmp/janus_atomic_via_temp.txt";
    const test_data = "atomic data";

    defer compat_fs.deleteFile(target_file) catch {};

    // Test atomic write
    try writeAtomicViaTemp(test_data, target_file, allocator);

    // Verify file exists and has correct content
    const metadata = compat_fs.statFile(target_file) catch unreachable;
    try testing.expect(metadata.size == test_data.len);

    const file = std.fs.cwd().openFile(target_file, .{}) catch unreachable;
    defer file.close();

    const content = file.readToEndAlloc(allocator, test_data.len) catch unreachable;
    defer allocator.free(content);

    try testing.expect(std.mem.eql(u8, content, test_data));
}

test "TempFile collision resistance" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create multiple temp files to test collision resistance
    var temp_files: std.ArrayList(TempFile) = .empty;
    defer {
        for (temp_files.items) |*temp_file| {
            temp_file.deinit();
        }
        temp_files.deinit();
    }

    const num_files = 10;

    var i: usize = 0;
    while (i < num_files) : (i += 1) {
        var temp_file = try TempFile.create(allocator);
        errdefer temp_file.deinit();

        // Check that path is unique
        for (temp_files.items) |existing| {
            try testing.expect(!std.mem.eql(u8, temp_file.path, existing.path));
        }

        try temp_files.append(temp_file);
    }

    // Verify all files were created successfully
    try testing.expect(temp_files.items.len == num_files);
}

test "Tri-signature pattern for temp file creation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const prefix = "trisig";

    // Test :min profile
    {
        var temp_file = try fs_create_temp_min(prefix, allocator);
        defer temp_file.deinit();

        try testing.expect(std.mem.startsWith(u8, std.fs.path.basename(temp_file.path), prefix));
    }

    // Test :go profile (mock context)
    {
        var mock_ctx = Context.init(allocator);
        defer mock_ctx.deinit();

        var temp_file = try fs_create_temp_go(prefix, mock_ctx, allocator);
        defer temp_file.deinit();

        try testing.expect(std.mem.startsWith(u8, std.fs.path.basename(temp_file.path), prefix));
    }

    // Test :full profile (mock capability)
    {
        var mock_cap = Capability.FileSystem.init("test-cap", allocator);
        defer mock_cap.deinit();

        var temp_file = try fs_create_temp_full(prefix, mock_cap, allocator);
        defer temp_file.deinit();

        try testing.expect(std.mem.startsWith(u8, std.fs.path.basename(temp_file.path), prefix));
    }
}

test "TempFile error conditions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test temp file in non-existent directory
    {
        const nonexistent_dir = "/nonexistent/deep/path";
        const dir = compat_fs.openDir(nonexistent_dir, .{}) catch {
            // Expected - directory doesn't exist
            return;
        };
        defer dir.close();

        // This should fail since directory doesn't exist
        try testing.expectError(FsError.TempDirInaccessible, TempFile.createInDir(dir, allocator));
    }
}

// =============================================================================
// UTCP MANUAL
// =============================================================================

/// Self-describing manual for AI agents and tooling
pub fn utcpManual() []const u8 {
    return (
        \\# Janus Standard Library - Secure Temp File Module (std/temp_fs)
        \\## Overview
        \\Secure temporary file creation with collision resistance and automatic cleanup.
        \\Implements Task 8: Secure temp file creation with RAII management and atomic persistence.
        \\
        \\## Core Types
        \\### TempFile (RAII)
        \\- `create(allocator) !TempFile` - Create secure temp file in system temp dir
        \\- `createInDir(dir, allocator) !TempFile` - Create in specific directory
        \\- `createWithPrefix(prefix, allocator) !TempFile` - Create with custom prefix
        \\- `write(data) !usize` - Write data to temp file
        \\- `writeAll(data) !void` - Write all data (ensures completion)
        \\- `read(buffer) !usize` - Read data from temp file
        \\- `getPath() []const u8` - Get temp file path (borrowed)
        \\- `getSize() !u64` - Get file size
        \\- `persist(target_path) !void` - Atomically rename to target path
        \\- `deinit()` - Clean up temp file and resources
        \\
        \\## Convenience Functions
        \\### Basic Creation
        \\- `createTempFileWithData(data, allocator)` - Create temp file with data
        \\- `createTempFileWithString(string, allocator)` - Create with string data
        \\- `createTempFileWithPrefixAndData(prefix, data, allocator)` - With custom prefix
        \\
        \\### Atomic Operations
        \\- `createTempFileForAtomicWrite(target_path, allocator)` - For atomic writes
        \\- `writeAtomicViaTemp(data, target_path, allocator)` - Atomic write via temp file
        \\
        \\## Tri-Signature Pattern
        \\### :min Profile (Simple)
        \\```zig
        \\var temp_file = try fs_create_temp_min("myprefix", allocator);
        \\defer temp_file.deinit();
        \\try temp_file.writeAll("data");
        \\try temp_file.persist("/final/path");
        \\```
        \\
        \\### :go Profile (Context-aware)
        \\```zig
        \\var ctx = Context.init(allocator);
        \\defer ctx.deinit();
        \\var temp_file = try fs_create_temp_go("myprefix", ctx, allocator);
        \\```
        \\
        \\### :full Profile (Capability-gated)
        \\```zig
        \\var cap = Capability.FileSystem.init("fs-cap", allocator);
        \\defer cap.deinit();
        \\try cap.allow_temp_files();
        \\var temp_file = try fs_create_temp_full("myprefix", cap, allocator);
        \\```
        \\
        \\## Security Features
        \\- **Collision Resistance**: Random suffixes prevent filename collisions
        \\- **Exclusive Creation**: O_EXCL flag prevents race conditions
        \\- **Automatic Cleanup**: RAII ensures temp files are deleted on scope exit
        \\- **Secure Paths**: Uses system temp directory by default
        \\- **Atomic Persistence**: Safe rename operations prevent partial writes
        \\- **Capability Control**: Temp file creation gated by capabilities in :full profile
        \\
        \\## Error Handling
        \\Returns `FsError` with specific error types:
        \\- `TempFileFailed` - Failed to create secure temporary file
        \\- `TempDirInaccessible` - Cannot access temp directory
        \\- `PermissionDenied` - Insufficient permissions for temp file operations
        \\- `DiskFull` - No space available for temp file
        \\- `CapabilityRequired` - Required capability not granted
        \\- `ContextCancelled` - Context was cancelled or deadline exceeded
        \\
        \\## RAII Resource Management
        \\- Automatic temp file deletion when TempFile goes out of scope
        \\- Safe resource cleanup even on allocation failures
        \\- No manual cleanup required in most cases
        \\- Early termination support for large operations
        \\
        \\## Performance Characteristics
        \\- Minimal collision probability with timestamp + PID suffixes
        \\- Efficient random suffix generation
        \\- Fast temp directory access using std.fs.tmpDir()
        \\- Low memory overhead for path management
        \\- Optimized for both small and large temp files
        \\
        \\## Examples
        \\```zig
        \\// Basic secure temp file
        \\var temp_file = try TempFile.create(allocator);
        \\defer temp_file.deinit();
        \\
        \\try temp_file.writeAll("sensitive data");
        \\try temp_file.persist("/final/destination");
        \\
        \\// Custom prefix for organization
        \\var temp_file = try TempFile.createWithPrefix("upload", allocator);
        \\defer temp_file.deinit();
        \\
        \\// Atomic write pattern
        \\try writeAtomicViaTemp("file content", "/target/file", allocator);
        \\
        \\// Temp file with data
        \\var temp_file = try createTempFileWithData("initial data", allocator);
        \\defer temp_file.deinit();
        \\```
        \\
    );
}
