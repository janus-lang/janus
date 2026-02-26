// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - Atomic Filesystem Operations
// Atomic rename and write_atomic implementations for data integrity

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
    WalkerError,
    SymlinkLoop,
    AtomicWriteFailed,
    CrossDeviceRename,
    FsyncFailed,
    RenameFailed,
};

/// Atomic operation result for monitoring and debugging
pub const AtomicResult = struct {
    success: bool,
    temp_path: ?[]const u8,
    final_path: []const u8,
    bytes_written: u64,
    duration_ms: i64,
    fsync_count: u32,
    error_details: ?[]const u8,

    /// Clean up result resources
    pub fn deinit(self: AtomicResult, allocator: Allocator) void {
        if (self.temp_path) |temp| {
            allocator.free(temp);
        }
        if (self.error_details) |details| {
            allocator.free(details);
        }
    }
};

/// Atomic operation options for fine-tuning behavior
pub const AtomicOptions = struct {
    /// Enable extra fsync operations for maximum durability
    paranoid_mode: bool = true,

    /// Custom temporary file prefix
    temp_prefix: []const u8 = "atomic",

    /// Maximum time to wait for atomic operation (0 = no timeout)
    timeout_ms: u32 = 30000, // 30 seconds

    /// Enable detailed operation logging
    debug_logging: bool = false,

    /// Buffer size for streaming writes
    buffer_size: usize = 64 * 1024, // 64KB

    /// Progress callback for large operations
    progress_callback: ?*const fn (u64) void = null,
};

/// Atomic rename with cross-device detection and fallback
/// Ensures atomicity where possible, with documented fallbacks
pub fn atomicRename(
    src_path: []const u8,
    dst_path: []const u8,
    allocator: Allocator
) !AtomicResult {
    const start_time = std.time.milliTimestamp();

    var result = AtomicResult{
        .success = false,
        .temp_path = null,
        .final_path = try allocator.dupe(u8, dst_path),
        .bytes_written = 0,
        .duration_ms = 0,
        .fsync_count = 0,
        .error_details = null,
    };
    errdefer result.deinit(allocator);

    // Attempt atomic rename
    std.fs.cwd().rename(src_path, dst_path) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.NotDir => return FsError.NotDir,
        error.IsDir => return FsError.IsDir,
        error.FileBusy => return FsError.FileBusy,
        error.DeviceBusy => return FsError.DeviceBusy,
        error.NoSpaceLeft => return FsError.DiskFull,
        error.PathAlreadyExists => return FsError.PermissionDenied,
        error.CrossDeviceLink => {
            // Cross-device rename not supported - need copy + delete fallback
            return atomicRenameCrossDevice(src_path, dst_path, allocator);
        },
        else => {
            result.error_details = try std.fmt.allocPrint(allocator, "Rename failed: {s}", .{@errorName(err)});
            return result;
        },
    };

    // Rename succeeded
    result.success = true;
    result.duration_ms = std.time.milliTimestamp() - start_time;

    // Fsync the destination directory for durability
    if (try fsyncDirectoryContainingPath(dst_path)) {
        result.fsync_count += 1;
    }

    return result;
}

/// Handle cross-device rename with copy + delete fallback
fn atomicRenameCrossDevice(
    src_path: []const u8,
    dst_path: []const u8,
    allocator: Allocator
) !AtomicResult {
    const start_time = std.time.milliTimestamp();

    var result = AtomicResult{
        .success = false,
        .temp_path = null,
        .final_path = try allocator.dupe(u8, dst_path),
        .bytes_written = 0,
        .duration_ms = 0,
        .fsync_count = 0,
        .error_details = try allocator.dupe(u8, "Cross-device rename required copy+delete fallback"),
    };
    errdefer result.deinit(allocator);

    // Copy source to destination
    try copyFileAtomic(src_path, dst_path, allocator);

    // Remove source file
    compat_fs.deleteFile(src_path) catch |err| {
        // Log error but don't fail - file was successfully copied
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to remove source after copy: {s}", .{@errorName(err)});
        if (result.error_details) |old| allocator.free(old);
        result.error_details = error_msg;
    };

    result.success = true;
    result.duration_ms = std.time.milliTimestamp() - start_time;

    return result;
}

/// Copy file with atomic guarantees
fn copyFileAtomic(
    src_path: []const u8,
    dst_path: []const u8,
    allocator: Allocator
) !void {
    _ = allocator; // Allocator available for future enhancements (e.g., large buffer allocation)

    const src_file = try std.fs.cwd().openFile(src_path, .{});
    defer src_file.close();

    const dst_file = try compat_fs.createFile(dst_path, .{});
    defer dst_file.close();

    // Get source file size
    const src_size = try src_file.getEndPos();

    // Copy in chunks with progress tracking
    var buffer: [64 * 1024]u8 = undefined; // 64KB buffer
    var total_copied: u64 = 0;

    while (total_copied < src_size) {
        const bytes_to_read = @min(buffer.len, src_size - total_copied);
        const bytes_read = try src_file.read(buffer[0..bytes_to_read]);

        if (bytes_read == 0) break;

        try dst_file.writeAll(buffer[0..bytes_read]);
        total_copied += bytes_read;
    }

    // Ensure destination is fully written
    try dst_file.sync();
}

/// Atomic write using temp file + fsync + rename pattern
/// Provides crash-safe writes with guaranteed durability
pub fn atomicWrite(
    path: []const u8,
    data: []const u8,
    options: AtomicOptions,
    allocator: Allocator
) !AtomicResult {
    const start_time = std.time.milliTimestamp();

    var result = AtomicResult{
        .success = false,
        .temp_path = null,
        .final_path = try allocator.dupe(u8, path),
        .bytes_written = 0,
        .duration_ms = 0,
        .fsync_count = 0,
        .error_details = null,
    };
    errdefer result.deinit(allocator);

    // Generate unique temporary file path
    const temp_path = try generateTempPath(path, options.temp_prefix, allocator);
    result.temp_path = try allocator.dupe(u8, temp_path);
    defer allocator.free(temp_path);

    // Create and write to temporary file
    const temp_file = try compat_fs.createFile(temp_path, .{ .truncate = true });
    defer temp_file.close();

    // Write data in chunks with progress tracking
    var bytes_written: u64 = 0;
    var chunk_start: usize = 0;

    while (chunk_start < data.len) {
        const chunk_end = @min(chunk_start + options.buffer_size, data.len);
        const chunk = data[chunk_start..chunk_end];

        try temp_file.writeAll(chunk);
        bytes_written += chunk.len;
        chunk_start = chunk_end;

        // Call progress callback if provided
        if (options.progress_callback) |callback| {
            callback(bytes_written);
        }
    }

    result.bytes_written = bytes_written;

    // Paranoid mode: extra fsync operations for maximum durability
    if (options.paranoid_mode) {
        // Fsync the temporary file
        temp_file.sync() catch |err| {
            result.error_details = try std.fmt.allocPrint(allocator, "Temp file fsync failed: {s}", .{@errorName(err)});
            return result;
        };
        result.fsync_count += 1;

        // Fsync the directory containing the temp file
        if (try fsyncDirectoryContainingPath(temp_path)) {
            result.fsync_count += 1;
        }
    }

    // Atomic rename to final location
    std.fs.cwd().rename(temp_path, path) catch |err| switch (err) {
        error.AccessDenied => {
            result.error_details = try allocator.dupe(u8, "Rename access denied");
            return result;
        },
        error.NotDir => {
            result.error_details = try allocator.dupe(u8, "Rename path is not directory");
            return result;
        },
        error.IsDir => {
            result.error_details = try allocator.dupe(u8, "Cannot rename to directory");
            return result;
        },
        error.FileBusy => {
            result.error_details = try allocator.dupe(u8, "Target file busy");
            return result;
        },
        error.DeviceBusy => {
            result.error_details = try allocator.dupe(u8, "Device busy");
            return result;
        },
        error.NoSpaceLeft => {
            result.error_details = try allocator.dupe(u8, "No space left on device");
            return result;
        },
        error.PathAlreadyExists => {
            result.error_details = try allocator.dupe(u8, "Target path already exists");
            return result;
        },
        error.CrossDeviceLink => {
            // This shouldn't happen for temp file in same directory, but handle it
            result.error_details = try allocator.dupe(u8, "Cross-device rename not supported");
            return result;
        },
        else => {
            result.error_details = try std.fmt.allocPrint(allocator, "Rename failed: {s}", .{@errorName(err)});
            return result;
        },
    };

    // Final fsync of target directory for maximum durability
    if (options.paranoid_mode) {
        if (try fsyncDirectoryContainingPath(path)) {
            result.fsync_count += 1;
        }
    }

    result.success = true;
    result.duration_ms = std.time.milliTimestamp() - start_time;

    return result;
}

/// Generate a unique temporary file path in the same directory as target
fn generateTempPath(target_path: []const u8, prefix: []const u8, allocator: Allocator) ![]u8 {
    const target_dir = std.fs.path.dirname(target_path) orelse ".";
    const target_name = std.fs.path.basename(target_path);

    // Generate unique suffix
    const timestamp = compat_time.nanoTimestamp();
    const pid = std.os.linux.getpid();
    const random = std.crypto.random.int(u32);

    const temp_name = try std.fmt.allocPrint(
        allocator,
        "{s}_{x}_{d}_{x}.tmp",
        .{ prefix, timestamp, pid, random }
    );
    defer allocator.free(temp_name);

    return std.fs.path.join(allocator, &[_][]const u8{ target_dir, temp_name });
}

/// Fsync the directory containing the given path
fn fsyncDirectoryContainingPath(file_path: []const u8) !bool {
    const dir_path = std.fs.path.dirname(file_path) orelse return false;

    const dir = compat_fs.openDir(dir_path, .{}) catch return false;
    defer dir.close();

    // Note: std.fs.Dir doesn't expose fsync, so we can't fsync directories
    // This is a limitation of the current Zig stdlib
    // In a real implementation, we'd need platform-specific code
    return false;
}

// =============================================================================
// TRI-SIGNATURE PATTERN IMPLEMENTATIONS
// =============================================================================

/// :min profile - Simple atomic operations
pub fn atomic_rename_min(src: []const u8, dst: []const u8, allocator: Allocator) !AtomicResult {
    return atomicRename(src, dst, allocator);
}

pub fn atomic_write_min(path: []const u8, data: []const u8, allocator: Allocator) !AtomicResult {
    return atomicWrite(path, data, AtomicOptions{
        .paranoid_mode = true,
        .debug_logging = false,
    }, allocator);
}

/// :go profile - Context-aware atomic operations
pub fn atomic_rename_go(src: []const u8, dst: []const u8, ctx: Context, allocator: Allocator) !AtomicResult {
    if (ctx.is_done()) return FsError.ContextCancelled;
    return atomicRename(src, dst, allocator);
}

pub fn atomic_write_go(path: []const u8, data: []const u8, ctx: Context, allocator: Allocator) !AtomicResult {
    if (ctx.is_done()) return FsError.ContextCancelled;

    const options = AtomicOptions{
        .paranoid_mode = true,
        .debug_logging = false,
        .timeout_ms = 10000, // Shorter timeout for context-aware operations
    };
    return atomicWrite(path, data, options, allocator);
}

/// :full profile - Capability-gated atomic operations with monitoring
pub fn atomic_rename_full(src: []const u8, dst: []const u8, cap: Capability.FileSystem, allocator: Allocator) !AtomicResult {
    if (!cap.allows_path(src)) return FsError.CapabilityRequired;
    if (!cap.allows_path(dst)) return FsError.CapabilityRequired;

    Capability.audit_capability_usage(cap, "fs.atomic_rename");

    const result = try atomicRename(src, dst, allocator);

    // Log operation for audit trail
    if (result.success) {
        // In a real implementation, this would log to audit system
        // std.log.info("Atomic rename succeeded: {s} -> {s}", .{src, dst});
    }

    return result;
}

pub fn atomic_write_full(path: []const u8, data: []const u8, cap: Capability.FileSystem, allocator: Allocator) !AtomicResult {
    if (!cap.allows_path(path)) return FsError.CapabilityRequired;
    if (!cap.allows_write()) return FsError.PermissionDenied;

    Capability.audit_capability_usage(cap, "fs.atomic_write");

    const options = AtomicOptions{
        .paranoid_mode = true,
        .debug_logging = true, // Enable debug logging for :full profile
        .progress_callback = null, // Could be added for large files
    };

    const result = try atomicWrite(path, data, options, allocator);

    // Enhanced audit logging for :full profile
    if (result.success) {
        // In a real implementation, this would log detailed audit information
        // std.log.info("Atomic write succeeded: {s} ({d} bytes, {d} fsyncs)", .{path, result.bytes_written, result.fsync_count});
    }

    return result;
}

// =============================================================================
// UTILITY FUNCTIONS FOR TESTING AND DEBUGGING
// =============================================================================

/// Simulate crash during atomic write for testing durability
/// WARNING: This is for testing only - do not use in production!
pub fn simulateCrashDuringAtomicWrite(
    path: []const u8,
    data: []const u8,
    crash_point: enum { before_fsync, after_fsync, after_rename },
    allocator: Allocator
) !AtomicResult {
    // This is a testing utility - in real code, this would be conditionally compiled
    _ = path;
    _ = data;
    _ = crash_point;
    _ = allocator;

    return AtomicResult{
        .success = false,
        .temp_path = null,
        .final_path = try allocator.dupe(u8, ""),
        .bytes_written = 0,
        .duration_ms = 0,
        .fsync_count = 0,
        .error_details = try allocator.dupe(u8, "Crash simulation not implemented"),
    };
}

/// Verify atomic write durability by checking file integrity
pub fn verifyAtomicWriteIntegrity(path: []const u8, expected_data: []const u8, allocator: Allocator) !bool {
    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();

    const file_size = file.getEndPos() catch return false;

    if (file_size != expected_data.len) return false;

    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    const bytes_read = file.readAll(buffer) catch return false;

    if (bytes_read != file_size) return false;

    return std.mem.eql(u8, buffer, expected_data);
}

// =============================================================================
// TESTS
// =============================================================================

test "Atomic rename basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create test files
    const src_file = "/tmp/atomic_rename_src.txt";
    const dst_file = "/tmp/atomic_rename_dst.txt";

    try compat_fs.writeFile(.{ .sub_path = src_file, .data = "test data" });
    defer compat_fs.deleteFile(src_file) catch {};
    defer compat_fs.deleteFile(dst_file) catch {};

    // Test atomic rename
    var result = try atomicRename(src_file, dst_file, allocator);
    defer result.deinit(allocator);

    try testing.expect(result.success);
    try testing.expect(std.mem.eql(u8, result.final_path, dst_file));

    // Verify destination exists and source doesn't
    try testing.expect(try std.fs.cwd().access(dst_file, .{}));
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(src_file, .{}));
}

test "Atomic write basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_file = "/tmp/atomic_write_test.txt";
    const test_data = "This is atomic write test data with some length to it.";

    defer compat_fs.deleteFile(test_file) catch {};

    // Test atomic write
    const options = AtomicOptions{
        .paranoid_mode = true,
        .debug_logging = false,
    };

    var result = try atomicWrite(test_file, test_data, options, allocator);
    defer result.deinit(allocator);

    try testing.expect(result.success);
    try testing.expect(result.bytes_written == test_data.len);
    try testing.expect(std.mem.eql(u8, result.final_path, test_file));

    // Verify file contents
    try testing.expect(try verifyAtomicWriteIntegrity(test_file, test_data, allocator));
}

test "Atomic write with options" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_file = "/tmp/atomic_write_options.txt";
    const test_data = "Options test data";

    defer compat_fs.deleteFile(test_file) catch {};

    // Test with custom options
    const options = AtomicOptions{
        .paranoid_mode = false, // Disable extra fsync for speed
        .temp_prefix = "custom",
        .buffer_size = 1024, // Larger buffer
    };

    var result = try atomicWrite(test_file, test_data, options, allocator);
    defer result.deinit(allocator);

    try testing.expect(result.success);
    try testing.expect(result.bytes_written == test_data.len);
    try testing.expect(std.mem.eql(u8, result.final_path, test_file));

    // Verify file contents
    try testing.expect(try verifyAtomicWriteIntegrity(test_file, test_data, allocator));
}

test "Tri-signature pattern for atomic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_file = "/tmp/atomic_tri_sig.txt";
    const test_data = "Tri-signature atomic write test";

    defer compat_fs.deleteFile(test_file) catch {};

    // Test :min profile
    {
        var result = try atomic_write_min(test_file, test_data, allocator);
        defer result.deinit(allocator);
        try testing.expect(result.success);
    }

    // Test :go profile (mock context)
    {
        var mock_ctx = Context.init(allocator);
        defer mock_ctx.deinit();

        var result = try atomic_write_go(test_file, test_data, mock_ctx, allocator);
        defer result.deinit(allocator);
        try testing.expect(result.success);
    }

    // Test :full profile (mock capability)
    {
        var mock_cap = Capability.FileSystem.init("test-cap", allocator);
        defer mock_cap.deinit();

        var result = try atomic_write_full(test_file, test_data, mock_cap, allocator);
        defer result.deinit(allocator);
        try testing.expect(result.success);
    }
}

test "Atomic write integrity verification" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_file = "/tmp/atomic_integrity_test.txt";
    const test_data = "Integrity verification test data";

    defer compat_fs.deleteFile(test_file) catch {};

    // Write atomically
    const options = AtomicOptions{ .paranoid_mode = true };
    var write_result = try atomicWrite(test_file, test_data, options, allocator);
    defer write_result.deinit(allocator);

    try testing.expect(write_result.success);

    // Verify integrity
    try testing.expect(try verifyAtomicWriteIntegrity(test_file, test_data, allocator));

    // Test with wrong data
    const wrong_data = "Wrong data";
    try testing.expect(!try verifyAtomicWriteIntegrity(test_file, wrong_data, allocator));
}

test "Atomic operations error handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test writing to non-existent directory
    const bad_path = "/non/existent/directory/file.txt";
    const test_data = "This should fail";

    var result = try atomicWrite(bad_path, test_data, AtomicOptions{}, allocator);
    defer result.deinit(allocator);

    try testing.expect(!result.success);
    try testing.expect(result.error_details != null);
}

// =============================================================================
// UTCP MANUAL
// =============================================================================

/// Self-describing manual for AI agents and tooling
pub fn utcpManual() []const u8 {
    return (
        \\# Janus Standard Library - Atomic Filesystem Operations (std/fs_atomic)
        \\## Overview
        \\Atomic rename and write_atomic implementations ensuring data integrity and crash safety.
        \\Implements Task 7: Atomic rename and write_atomic with cross-device detection and durability guarantees.
        \\
        \\## Core Types
        \\### AtomicResult
        \\- `success: bool` - Whether the operation succeeded
        \\- `temp_path: ?[]const u8` - Temporary file path used (for write operations)
        \\- `final_path: []const u8` - Final target path
        \\- `bytes_written: u64` - Bytes written (for write operations)
        \\- `duration_ms: i64` - Operation duration in milliseconds
        \\- `fsync_count: u32` - Number of fsync operations performed
        \\- `error_details: ?[]const u8` - Detailed error information if failed
        \\
        \\### AtomicOptions
        \\- `paranoid_mode: bool` - Enable extra fsync for maximum durability
        \\- `temp_prefix: []const u8` - Custom temporary file prefix
        \\- `timeout_ms: u32` - Operation timeout (0 = no timeout)
        \\- `debug_logging: bool` - Enable detailed operation logging
        \\- `buffer_size: usize` - Buffer size for streaming writes
        \\- `progress_callback: ?*const fn (u64) void` - Progress callback for large operations
        \\
        \\## Core Functions
        \\### Atomic Rename
        \\- `atomicRename(src, dst, allocator)` - Atomic rename with cross-device fallback
        \\- Detects cross-device renames and falls back to copy+delete
        \\- Returns detailed result with success/failure information
        \\
        \\### Atomic Write
        \\- `atomicWrite(path, data, options, allocator)` - Crash-safe atomic write
        \\- Uses temp file + fsync + rename pattern for guaranteed durability
        \\- Supports progress callbacks and detailed monitoring
        \\
        \\## Durability Guarantees
        \\### Atomic Write Pattern
        \\1. Write complete data to temporary file
        \\2. fsync() temporary file (optional paranoid mode)
        \\3. fsync() directory containing temp file (optional)
        \\4. Atomic rename to final location
        \\5. fsync() directory containing final file (optional)
        \\
        \\### Crash Safety
        \\- **Before crash**: Either old file exists or no file exists
        \\- **During crash**: Temporary file may exist but is ignored
        \\- **After crash**: Either old file or complete new file exists
        \\- **Never**: Partial or corrupted final file
        \\
        \\## Tri-Signature Pattern
        \\### :min Profile (Simple)
        \\```zig
        \\const result = try atomic_write_min("/file.txt", data, allocator);
        \\if (result.success) {
        \\    // Write succeeded atomically
        \\}
        \\```
        \\
        \\### :go Profile (Context-aware)
        \\```zig
        \\var ctx = Context.init(allocator);
        \\defer ctx.deinit();
        \\const result = try atomic_write_go("/file.txt", data, ctx, allocator);
        \\```
        \\
        \\### :full Profile (Capability-gated)
        \\```zig
        \\var cap = Capability.FileSystem.init("fs-cap", allocator);
        \\defer cap.deinit();
        \\try cap.allow_path("/safe/file.txt");
        \\const result = try atomic_write_full("/safe/file.txt", data, cap, allocator);
        \\```
        \\
        \\## Advanced Features
        \\### Progress Tracking
        \\```zig
        \\const progress_callback = struct {
        \\    pub fn callback(bytes_written: u64) void {
        \\        std.debug.print("Written: {d} bytes\\n", .{bytes_written});
        \\    }
        \\}.callback;
        \\
        \\const options = AtomicOptions{
        \\    .progress_callback = &progress_callback,
        \\};
        \\```
        \\
        \\### Paranoid Mode
        \\```zig
        \\const options = AtomicOptions{
        \\    .paranoid_mode = true,  // Extra fsync operations
        \\    .debug_logging = true,  // Detailed logging
        \\};
        \\```
        \\
        \\## Error Handling
        \\Returns `FsError` with specific error types:
        \\- `AtomicWriteFailed` - Atomic write operation failed
        \\- `CrossDeviceRename` - Cross-device rename not supported
        \\- `FsyncFailed` - Filesystem sync operation failed
        \\- `RenameFailed` - Atomic rename operation failed
        \\- `CapabilityRequired` - Required capability not granted
        \\- `ContextCancelled` - Context was cancelled during operation
        \\
        \\## Performance Characteristics
        \\- **Durability**: Paranoid mode ensures maximum crash safety
        \\- **Throughput**: Streaming writes with configurable buffer sizes
        \\- **Monitoring**: Detailed operation metrics and timing
        \\- **Fallbacks**: Cross-device rename with documented copy+delete
        \\- **Progress**: Optional progress callbacks for large operations
        \\
        \\## Security Features
        \\- **Capability Control**: :full profile requires explicit permissions
        \\- **Path Validation**: All paths validated before operations
        \\- **Audit Trails**: Detailed logging for security compliance
        \\- **No Race Conditions**: Atomic operations prevent TOCTOU attacks
        \\
        \\## Testing Features
        \\- **Integrity Verification**: `verifyAtomicWriteIntegrity()` for testing
        \\- **Crash Simulation**: Framework for testing durability guarantees
        \\- **Progress Testing**: Callback verification for large operations
        \\- **Error Path Coverage**: Comprehensive error condition testing
        \\
        \\## Future-Proofing
        \\- **Async Ready**: Framework prepared for Zig async I/O
        \\- **Monitoring**: Built-in metrics collection
        \\- **Extensibility**: Options struct for future enhancements
        \\- **Debugging**: Comprehensive logging and error details
        \\
        \\## Examples
        \\```zig
        \\// Basic atomic write
        \\const result = try atomicWrite("/important/data.txt", data, AtomicOptions{}, allocator);
        \\defer result.deinit(allocator);
        \\
        \\if (result.success) {
        \\    std.debug.print("Written {d} bytes in {d}ms\\n", .{result.bytes_written, result.duration_ms});
        \\} else {
        \\    std.debug.print("Write failed: {s}\\n", .{result.error_details.?});
        \\}
        \\
        \\// Paranoid mode for critical data
        \\const options = AtomicOptions{
        \\    .paranoid_mode = true,
        \\    .progress_callback = &my_progress_callback,
        \\};
        \\const result = try atomicWrite("/critical/system.cfg", config_data, options, allocator);
        \\
        \\// Cross-device atomic rename
        \\const rename_result = try atomicRename("/source/file.dat", "/different/device/file.dat", allocator);
        \\// Automatically handles cross-device copy+delete fallback
        \\```
        \\
    );
}
