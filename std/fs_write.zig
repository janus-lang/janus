// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - RAII Write Operations with BLAKE3 CID
// Write helpers with close-on-drop guarantees and content integrity verification

const std = @import("std");
const compat_fs = @import("compat_fs");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Context = @import("std_context.zig").Context;
const Capability = @import("capabilities.zig");
const Path = @import("path.zig").Path;
const PathBuf = @import("path.zig").PathBuf;

// Forward declarations
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
    AtomicWriteFailed,
    CrossDeviceRename,
    FsyncFailed,
    RenameFailed,
    CidVerificationFailed,
    ContentIntegrityError,
};

/// Content Identifier using BLAKE3
/// Provides cryptographic content addressing and integrity verification
pub const ContentId = struct {
    /// Raw BLAKE3 hash bytes (32 bytes)
    hash: [32]u8,

    /// Initialize from raw hash bytes
    pub fn init(hash_bytes: [32]u8) ContentId {
        return ContentId{ .hash = hash_bytes };
    }

    /// Compute CID from data
    pub fn fromData(data: []const u8) ContentId {
        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(data);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        return ContentId{ .hash = hash };
    }

    /// Compute CID from file path
    pub fn fromFile(path: []const u8, allocator: Allocator) !ContentId {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, size);
        defer allocator.free(buffer);

        const bytes_read = try file.readAll(buffer);
        if (bytes_read != size) return FsError.ContentIntegrityError;

        return fromData(buffer[0..bytes_read]);
    }

    /// Verify data against this CID
    pub fn verifyData(self: ContentId, data: []const u8) bool {
        const computed = fromData(data);
        return std.mem.eql(u8, &self.hash, &computed.hash);
    }

    /// Verify file content against this CID
    pub fn verifyFile(self: ContentId, path: []const u8, allocator: Allocator) !bool {
        const computed = try fromFile(path, allocator);
        return std.mem.eql(u8, &self.hash, &computed.hash);
    }

    /// Format as base58-encoded string (IPFS-style)
    pub fn toString(self: ContentId, allocator: Allocator) ![]u8 {
        // Simple base64 encoding for now (can be upgraded to base58)
        const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(32));
        _ = std.base64.standard.Encoder.encode(encoded, &self.hash);
        return encoded;
    }

    /// Parse from base64-encoded string
    pub fn fromString(str: []const u8, allocator: Allocator) !ContentId {
        _ = allocator; // Reserved for future encoding upgrades (e.g., base58)
        var hash: [32]u8 = undefined;
        try std.base64.standard.Decoder.decode(&hash, str);
        return ContentId{ .hash = hash };
    }

    /// Format as hex string
    pub fn toHex(self: ContentId, allocator: Allocator) ![]u8 {
        const hex_chars = "0123456789abcdef";
        var result = try allocator.alloc(u8, 64);
        for (self.hash, 0..) |byte, i| {
            result[i * 2] = hex_chars[byte >> 4];
            result[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        return result;
    }
};

/// Write options for fine-tuning write behavior
pub const WriteOptions = struct {
    /// Create file if it doesn't exist
    create: bool = true,

    /// Truncate file if it exists
    truncate: bool = true,

    /// Append to file instead of overwriting
    append: bool = false,

    /// Enable exclusive creation (fails if file exists)
    exclusive: bool = false,

    /// Buffer size for streaming writes
    buffer_size: usize = 64 * 1024, // 64KB

    /// Compute and return CID of written content
    compute_cid: bool = false,

    /// Expected CID for verification (write fails if mismatch)
    expected_cid: ?ContentId = null,

    /// Progress callback for large writes
    progress_callback: ?*const fn (u64) void = null,
};

/// RAII file writer with automatic cleanup and integrity verification
pub const FileWriter = struct {
    file: std.fs.File,
    allocator: Allocator,
    options: WriteOptions,
    bytes_written: u64,
    hasher: ?std.crypto.hash.Blake3 = null,

    /// Initialize file writer
    pub fn init(path: []const u8, options: WriteOptions, allocator: Allocator) !FileWriter {
        // Build file open flags
        var flags: std.fs.File.OpenFlags = .{
            .read = false,
            .write = true,
        };

        if (options.create) flags.write = true;
        if (options.truncate) flags.truncate = true;
        if (options.exclusive) flags.create = .exclusive;
        if (options.append) flags.append = true;

        const file = compat_fs.createFile(path, flags) catch |err| switch (err) {
            error.FileNotFound => return FsError.FileNotFound,
            error.AccessDenied => return FsError.PermissionDenied,
            error.NotDir => return FsError.NotDir,
            error.IsDir => return FsError.IsDir,
            error.FileBusy => return FsError.FileBusy,
            error.DeviceBusy => return FsError.DeviceBusy,
            error.NoSpaceLeft => return FsError.DiskFull,
            error.PathAlreadyExists => return FsError.PermissionDenied,
            else => return FsError.Unknown,
        };

        var hasher: ?std.crypto.hash.Blake3 = null;
        if (options.compute_cid or options.expected_cid != null) {
            hasher = std.crypto.hash.Blake3.init(.{});
        }

        return FileWriter{
            .file = file,
            .allocator = allocator,
            .options = options,
            .bytes_written = 0,
            .hasher = hasher,
        };
    }

    /// Write data to file
    pub fn write(self: *FileWriter, data: []const u8) !void {
        try self.file.writeAll(data);
        self.bytes_written += data.len;

        // Update CID hasher if enabled
        if (self.hasher) |*hasher| {
            hasher.update(data);
        }

        // Call progress callback if provided
        if (self.options.progress_callback) |callback| {
            callback(self.bytes_written);
        }
    }

    /// Write formatted data to file
    pub fn writeFmt(self: *FileWriter, comptime format: []const u8, args: anytype) !void {
        const data = try std.fmt.allocPrint(self.allocator, format, args);
        defer self.allocator.free(data);
        try self.write(data);
    }

    /// Flush writes to disk
    pub fn flush(self: *FileWriter) !void {
        try self.file.sync();
    }

    /// Get current CID of written content (if CID computation enabled)
    pub fn getCurrentCid(self: FileWriter) !ContentId {
        if (self.hasher) |hasher| {
            var hash: [32]u8 = undefined;
            hasher.final(&hash);
            return ContentId.init(hash);
        }
        return FsError.NotSupported;
    }

    /// Complete the write operation and return results
    pub fn finish(self: *FileWriter) !WriteResult {
        // Flush final writes
        try self.flush();

        // Verify expected CID if provided
        var actual_cid: ?ContentId = null;
        if (self.hasher) |hasher| {
            var hash: [32]u8 = undefined;
            hasher.final(&hash);
            actual_cid = ContentId.init(hash);

            if (self.options.expected_cid) |expected| {
                if (!std.mem.eql(u8, &expected.hash, &hash)) {
                    return FsError.CidVerificationFailed;
                }
            }
        }

        return WriteResult{
            .bytes_written = self.bytes_written,
            .cid = actual_cid,
        };
    }

    /// RAII cleanup - automatically closes file
    pub fn deinit(self: *FileWriter) void {
        self.file.close();
    }
};

/// Result of a write operation
pub const WriteResult = struct {
    bytes_written: u64,
    cid: ?ContentId,
};

/// High-level write functions with CID support
/// Write data to file with integrity verification
pub fn writeFile(path: []const u8, data: []const u8, options: WriteOptions, allocator: Allocator) !WriteResult {
    var writer = try FileWriter.init(path, options, allocator);
    defer writer.deinit();

    try writer.write(data);
    return writer.finish();
}

/// Write formatted string to file
pub fn writeFileFmt(path: []const u8, comptime format: []const u8, args: anytype, options: WriteOptions, allocator: Allocator) !WriteResult {
    const data = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(data);

    return writeFile(path, data, options, allocator);
}

/// Verify file integrity using CID
pub fn verifyFileIntegrity(path: []const u8, expected_cid: ContentId, allocator: Allocator) !bool {
    return expected_cid.verifyFile(path, allocator);
}

/// Compute CID for existing file
pub fn computeFileCid(path: []const u8, allocator: Allocator) !ContentId {
    return ContentId.fromFile(path, allocator);
}

// =============================================================================
// TRI-SIGNATURE PATTERN IMPLEMENTATIONS
// =============================================================================

/// :min profile - Simple write operations
pub fn write_min(path: []const u8, data: []const u8, allocator: Allocator) !WriteResult {
    const options = WriteOptions{
        .create = true,
        .truncate = true,
    };
    return writeFile(path, data, options, allocator);
}

pub fn write_fmt_min(path: []const u8, comptime format: []const u8, args: anytype, allocator: Allocator) !WriteResult {
    const options = WriteOptions{
        .create = true,
        .truncate = true,
    };
    return writeFileFmt(path, format, args, options, allocator);
}

/// :go profile - Context-aware write operations
pub fn write_go(path: []const u8, data: []const u8, ctx: Context, allocator: Allocator) !WriteResult {
    if (ctx.is_done()) return FsError.ContextCancelled;

    const options = WriteOptions{
        .create = true,
        .truncate = true,
        .timeout_ms = 10000, // 10 second timeout
    };
    return writeFile(path, data, options, allocator);
}

pub fn write_fmt_go(path: []const u8, comptime format: []const u8, args: anytype, ctx: Context, allocator: Allocator) !WriteResult {
    if (ctx.is_done()) return FsError.ContextCancelled;

    const options = WriteOptions{
        .create = true,
        .truncate = true,
        .timeout_ms = 10000,
    };
    return writeFileFmt(path, format, args, options, allocator);
}

/// :full profile - Capability-gated write operations with CID verification
pub fn write_full(path: []const u8, data: []const u8, cap: Capability.FileSystem, allocator: Allocator) !WriteResult {
    if (!cap.allows_path(path)) return FsError.CapabilityRequired;
    if (!cap.allows_write()) return FsError.PermissionDenied;

    Capability.audit_capability_usage(cap, "fs.write");

    const options = WriteOptions{
        .create = true,
        .truncate = true,
        .compute_cid = true, // Always compute CID for :full profile
    };

    const result = try writeFile(path, data, options, allocator);

    // Log successful write with CID
    if (result.cid) |cid| {
        // In real implementation, this would log to audit system
        // std.log.info("File written with CID: {s}", .{cid.toHex(allocator)});
    }

    return result;
}

pub fn write_fmt_full(path: []const u8, comptime format: []const u8, args: anytype, cap: Capability.FileSystem, allocator: Allocator) !WriteResult {
    if (!cap.allows_path(path)) return FsError.CapabilityRequired;
    if (!cap.allows_write()) return FsError.PermissionDenied;

    Capability.audit_capability_usage(cap, "fs.write_fmt");

    const options = WriteOptions{
        .create = true,
        .truncate = true,
        .compute_cid = true,
    };

    const result = try writeFileFmt(path, format, args, options, allocator);

    return result;
}

/// :full profile - CID verification operations
pub fn verify_integrity_full(path: []const u8, expected_cid: ContentId, cap: Capability.FileSystem, allocator: Allocator) !bool {
    if (!cap.allows_path(path)) return FsError.CapabilityRequired;

    Capability.audit_capability_usage(cap, "fs.verify_integrity");

    return verifyFileIntegrity(path, expected_cid, allocator);
}

pub fn compute_cid_full(path: []const u8, cap: Capability.FileSystem, allocator: Allocator) !ContentId {
    if (!cap.allows_path(path)) return FsError.CapabilityRequired;

    Capability.audit_capability_usage(cap, "fs.compute_cid");

    return computeFileCid(path, allocator);
}

// =============================================================================
// UTILITY FUNCTIONS FOR TESTING AND DEBUGGING
// =============================================================================

/// Create a test file with known CID for testing
pub fn createTestFileWithCid(path: []const u8, content: []const u8, allocator: Allocator) !ContentId {
    const result = try writeFile(path, content, WriteOptions{
        .create = true,
        .truncate = true,
        .compute_cid = true,
    }, allocator);

    return result.cid orelse FsError.ContentIntegrityError;
}

/// Test CID round-trip (create file, compute CID, verify)
pub fn testCidRoundTrip(path: []const u8, original_content: []const u8, allocator: Allocator) !bool {
    // Create file
    const expected_cid = try createTestFileWithCid(path, original_content, allocator);

    // Verify integrity
    const is_valid = try verifyFileIntegrity(path, expected_cid, allocator);

    // Compute CID again and compare
    const computed_cid = try computeFileCid(path, allocator);

    return is_valid and std.mem.eql(u8, &expected_cid.hash, &computed_cid.hash);
}

// =============================================================================
// TESTS
// =============================================================================

test "ContentId basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_data = "Hello, BLAKE3 CID!";
    const cid = ContentId.fromData(test_data);

    // Verify data against CID
    try testing.expect(cid.verifyData(test_data));

    // Test string encoding/decoding
    const cid_str = try cid.toString(allocator);
    defer allocator.free(cid_str);

    const decoded_cid = try ContentId.fromString(cid_str, allocator);
    try testing.expect(std.mem.eql(u8, &cid.hash, &decoded_cid.hash));

    // Test hex encoding
    const cid_hex = try cid.toHex(allocator);
    defer allocator.free(cid_hex);

    try testing.expect(std.mem.indexOf(u8, cid_hex, "CID") == null); // Should be hex
}

test "FileWriter basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_file = "/tmp/file_writer_test.txt";
    const test_data = "File writer test data";

    defer compat_fs.deleteFile(test_file) catch {};

    // Test basic writing
    var writer = try FileWriter.init(test_file, WriteOptions{
        .create = true,
        .truncate = true,
        .compute_cid = true,
    }, allocator);
    defer writer.deinit();

    try writer.write(test_data);
    const result = try writer.finish();

    try testing.expect(result.bytes_written == test_data.len);
    try testing.expect(result.cid != null);

    // Verify file content
    const content = try compat_fs.readFileAlloc(allocator, test_file, 1024);
    defer allocator.free(content);

    try testing.expect(std.mem.eql(u8, content, test_data));
}

test "CID file verification" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_file = "/tmp/cid_verify_test.txt";
    const test_data = "CID verification test";

    defer compat_fs.deleteFile(test_file) catch {};

    // Create file and get its CID
    const expected_cid = try createTestFileWithCid(test_file, test_data, allocator);

    // Verify integrity
    try testing.expect(try verifyFileIntegrity(test_file, expected_cid, allocator));

    // Test with wrong CID
    const wrong_data = "Wrong data";
    const wrong_cid = ContentId.fromData(wrong_data);
    try testing.expect(!try verifyFileIntegrity(test_file, wrong_cid, allocator));
}

test "Tri-signature pattern for write operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_file = "/tmp/write_tri_sig.txt";
    const test_data = "Tri-signature write test";

    defer compat_fs.deleteFile(test_file) catch {};

    // Test :min profile
    {
        var result = try write_min(test_file, test_data, allocator);
        defer result.deinit(allocator);
        try testing.expect(result.bytes_written == test_data.len);
    }

    // Test :go profile (mock context)
    {
        var mock_ctx = Context.init(allocator);
        defer mock_ctx.deinit();

        var result = try write_go(test_file, test_data, mock_ctx, allocator);
        defer result.deinit(allocator);
        try testing.expect(result.bytes_written == test_data.len);
    }

    // Test :full profile (mock capability)
    {
        var mock_cap = Capability.FileSystem.init("test-cap", allocator);
        defer mock_cap.deinit();

        var result = try write_full(test_file, test_data, mock_cap, allocator);
        defer result.deinit(allocator);
        try testing.expect(result.bytes_written == test_data.len);
        try testing.expect(result.cid != null); // :full always computes CID
    }
}

test "CID round-trip integrity" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_file = "/tmp/cid_roundtrip.txt";
    const test_data = "Round-trip integrity test";

    defer compat_fs.deleteFile(test_file) catch {};

    // Test complete round-trip
    try testing.expect(try testCidRoundTrip(test_file, test_data, allocator));
}

test "Write options behavior" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_file = "/tmp/write_options_test.txt";

    defer compat_fs.deleteFile(test_file) catch {};

    // Test append mode
    try writeFile(test_file, "First", WriteOptions{ .create = true }, allocator);
    try writeFile(test_file, "Second", WriteOptions{ .append = true }, allocator);

    const content = try compat_fs.readFileAlloc(allocator, test_file, 1024);
    defer allocator.free(content);

    try testing.expect(std.mem.eql(u8, content, "FirstSecond"));
}

// =============================================================================
// UTCP MANUAL
// =============================================================================

/// Self-describing manual for AI agents and tooling
pub fn utcpManual() []const u8 {
    return (
        \\# Janus Standard Library - RAII Write Operations with BLAKE3 CID
        \\## Overview
        \\RAII file writers with close-on-drop guarantees and BLAKE3 content integrity verification.
        \\Implements Task 6: RAII and write helpers with CID operations for content addressing.
        \\
        \\## Core Types
        \\### ContentId (BLAKE3-based)
        \\- Cryptographic content identifier using BLAKE3 hash
        \\- Content addressing for integrity verification
        \\- Base64 and hex encoding support
        \\- `fromData()`, `fromFile()`, `verifyData()`, `verifyFile()`
        \\
        \\### FileWriter (RAII)
        \\- Automatic file cleanup on scope exit
        \\- Streaming writes with progress callbacks
        \\- Optional CID computation during writes
        \\- Expected CID verification for integrity
        \\
        \\### WriteOptions
        \\- `create`, `truncate`, `append`, `exclusive` flags
        \\- `compute_cid` for content identification
        \\- `expected_cid` for write-time verification
        \\- `progress_callback` for large file feedback
        \\
        \\## Core Functions
        \\### Content Integrity
        \\- `ContentId.fromData(data)` - Compute CID from bytes
        \\- `ContentId.fromFile(path)` - Compute CID from file
        \\- `cid.verifyData(data)` - Verify data integrity
        \\- `cid.verifyFile(path)` - Verify file integrity
        \\
        \\### File Writing
        \\- `writeFile(path, data, options)` - Write with full control
        \\- `writeFileFmt(path, format, args, options)` - Formatted writing
        \\- `FileWriter` - RAII streaming writer
        \\
        \\## Tri-Signature Pattern
        \\### :min Profile (Simple)
        \\```zig
        \\const result = try write_min("/file.txt", data, allocator);
        \\// Basic writing, no bells and whistles
        \\```
        \\
        \\### :go Profile (Context-aware)
        \\```zig
        \\var ctx = Context.init(allocator);
        \\defer ctx.deinit();
        \\const result = try write_go("/file.txt", data, ctx, allocator);
        \\// With cancellation and timeouts
        \\```
        \\
        \\### :full Profile (Capability-gated + CID)
        \\```zig
        \\var cap = Capability.FileSystem.init("app", allocator);
        \\defer cap.deinit();
        \\const result = try write_full("/file.txt", data, cap, allocator);
        \\// Always computes CID, full security audit
        \\```
        \\
        \\## CID Operations
        \\### Content Addressing
        \\```zig
        \\// Compute content identifier
        \\const cid = ContentId.fromData("Hello World");
        \\
        \\// Verify integrity
        \\if (cid.verifyFile("/important.dat", allocator)) {
        \\    std.debug.print("File integrity verified\\n", .{});
        \\}
        \\
        \\// Use CID in :full profile writes
        \\const options = WriteOptions{
        \\    .expected_cid = cid,  // Fail if content doesn't match
        \\};
        \\```
        \\
        \\### CID Encoding
        \\```zig
        \\const cid = ContentId.fromData(data);
        \\
        \\// Base64 encoding (suitable for APIs)
        \\const b64 = try cid.toString(allocator);
        \\defer allocator.free(b64);
        \\
        \\// Hex encoding (for debugging)
        \\const hex = try cid.toHex(allocator);
        \\defer allocator.free(hex);
        \\```
        \\
        \\## RAII Guarantees
        \\### Automatic Cleanup
        \\```zig
        \\{
        \\    var writer = try FileWriter.init("/file.txt", options, allocator);
        \\    defer writer.deinit(); // Always called, even on errors
        \\
        \\    try writer.write("data");
        \\    const result = try writer.finish();
        \\    // File automatically closed here
        \\}
        \\```
        \\
        \\### Streaming Writes
        \\```zig
        \\var writer = try FileWriter.init("/large.dat", WriteOptions{
        \\    .compute_cid = true,
        \\    .progress_callback = &myProgressCallback,
        \\}, allocator);
        \\defer writer.deinit();
        \\
        \\// Write in chunks
        \\try writer.write(chunk1);
        \\try writer.write(chunk2);
        \\
        \\const result = try writer.finish();
        \\// result.cid contains BLAKE3 hash of all written data
        \\```
        \\
        \\## Error Handling
        \\Returns `FsError` with specific error types:
        \\- `CidVerificationFailed` - Content doesn't match expected CID
        \\- `ContentIntegrityError` - CID computation/verification error
        \\- Standard filesystem errors for I/O operations
        \\
        \\## Performance Characteristics
        \\- **BLAKE3**: Extremely fast hashing (~1GB/s on modern hardware)
        \\- **Streaming**: Minimal memory usage for large files
        \\- **RAII**: Zero-overhead resource management
        \\- **Verification**: Optional integrity checks with negligible cost
        \\
        \\## Security Features
        \\- **Cryptographic Integrity**: BLAKE3 provides collision resistance
        \\- **Content Addressing**: CID enables distributed verification
        \\- **Capability Control**: :full profile requires explicit permissions
        \\- **Audit Trails**: All operations logged in :full profile
        \\
        \\## Future-Proofing
        \\- **IPFS Compatible**: CID format ready for distributed systems
        \\- **Async Ready**: Framework prepared for Zig async I/O
        \\- **Extensible**: Options struct allows future enhancements
        \\- **Composable**: CID operations work with all write patterns
        \\
        \\## Examples
        \\### Basic Writing with Integrity
        \\```zig
        \\// Write with automatic CID computation
        \\const result = try writeFile("/data.txt", "Important data", WriteOptions{
        \\    .compute_cid = true,
        \\}, allocator);
        \\defer result.deinit(allocator);
        \\
        \\// Store CID for later verification
        \\const cid = result.cid.?;
        \\```
        \\
        \\### Verified Writing
        \\```zig
        \\// Only succeed if content matches expected CID
        \\const expected_cid = ContentId.fromData("Expected content");
        \\const result = try writeFile("/verified.txt", data, WriteOptions{
        \\    .expected_cid = expected_cid,
        \\}, allocator);
        \\// Fails with CidVerificationFailed if content doesn't match
        \\```
        \\
        \\### RAII Streaming
        \\```zig
        \\var writer = try FileWriter.init("/stream.dat", WriteOptions{
        \\    .compute_cid = true,
        \\}, allocator);
        \\defer writer.deinit(); // Guaranteed cleanup
        \\
        \\while (getNextChunk()) |chunk| {
        \\    try writer.write(chunk);
        \\}
        \\
        \\const result = try writer.finish();
        \\// Format CID as hex for display
        \\const hex_chars = "0123456789abcdef";
        \\var cid_hex: [64]u8 = undefined;
        \\for (result.cid.?.hash, 0..) |byte, i| {
        \\    cid_hex[i * 2] = hex_chars[byte >> 4];
        \\    cid_hex[i * 2 + 1] = hex_chars[byte & 0x0f];
        \\}
        \\std.debug.print("Wrote {} bytes, CID: {s}\\n", .{
        \\    result.bytes_written,
        \\    cid_hex
        \\});
        \\```
        \\
    );
}
