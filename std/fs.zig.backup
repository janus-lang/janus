// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - File System Module
// Demonstrates tri-signature pattern: same name, rising capability across profiles

const std = @import("std");
const Context = @import("std_context.zig").Context;
const Capability = @import("capabilities.zig");

/// File system errors
pub const FsError = error{
    FileNotFound,
    PermissionDenied,
    InvalidPath,
    CapabilityRequired,
    ContextCancelled,
    OutOfMemory,
    Unknown,
};

/// File metadata
pub const FileInfo = struct {
    size: u64,
    modified_time: i64,
    is_directory: bool,
    permissions: u32,
};

// =============================================================================
// TRI-SIGNATURE PATTERN: Same name, rising capability
// =============================================================================

/// :min profile - Simple synchronous file reading
/// Available in: min, go, full
pub fn read_file_min(path: []const u8, allocator: std.mem.Allocator) FsError![]u8 {
    // Simple implementation for :min profile
    // No context, no capabilities, just basic functionality

    if (path.len == 0) return FsError.InvalidPath;

    // Real file reading implementation
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return FsError.FileNotFound,
        error.AccessDenied => return FsError.PermissionDenied,
        error.NameTooLong => return FsError.InvalidPath,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };
    defer file.close();

    const file_size = file.getEndPos() catch return FsError.Unknown;
    const content = allocator.alloc(u8, file_size) catch return FsError.OutOfMemory;

    const bytes_read = file.readAll(content) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.InputOutput => return FsError.Unknown,
        error.IsDir => return FsError.InvalidPath,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };

    // Shrink allocation to actual size if needed
    if (bytes_read < file_size) {
        const actual_content = allocator.realloc(content, bytes_read) catch {
            allocator.free(content);
            return FsError.OutOfMemory;
        };
        return actual_content;
    }

    return content;
}

/// :go profile - Context-aware file reading with cancellation
/// Available in: go, full
pub fn read_file_go(path: []const u8, ctx: Context, allocator: std.mem.Allocator) FsError![]u8 {
    // Enhanced implementation with context support
    // Includes timeout, cancellation, structured error handling

    if (path.len == 0) return FsError.InvalidPath;

    // Check context for cancellation/timeout
    if (ctx.is_done()) return FsError.ContextCancelled;

    // Real file reading implementation with context awareness
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return FsError.FileNotFound,
        error.AccessDenied => return FsError.PermissionDenied,
        error.NameTooLong => return FsError.InvalidPath,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };
    defer file.close();

    const file_size = file.getEndPos() catch return FsError.Unknown;
    const content = allocator.alloc(u8, file_size) catch return FsError.OutOfMemory;

    const bytes_read = file.readAll(content) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.InputOutput => return FsError.Unknown,
        error.IsDir => return FsError.InvalidPath,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };

    // Shrink allocation to actual size if needed
    if (bytes_read < file_size) {
        const actual_content = allocator.realloc(content, bytes_read) catch {
            allocator.free(content);
            return FsError.OutOfMemory;
        };
        return actual_content;
    }

    return content;
}

/// :full profile - Capability-gated file reading with security
/// Available in: full only
pub fn read_file_full(path: []const u8, cap: Capability.FileSystem, allocator: std.mem.Allocator) FsError![]u8 {
    // Full implementation with capability-based security
    // Explicit permission required, audit trails, effect tracking

    if (path.len == 0) return FsError.InvalidPath;

    // Validate capability
    if (!cap.allows_path(path)) return FsError.CapabilityRequired;

    // Audit capability usage
    Capability.audit_capability_usage(cap, "fs.read");

    // Real file reading implementation with capability validation
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return FsError.FileNotFound,
        error.AccessDenied => return FsError.PermissionDenied,
        error.NameTooLong => return FsError.InvalidPath,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };
    defer file.close();

    const file_size = file.getEndPos() catch return FsError.Unknown;
    const content = allocator.alloc(u8, file_size) catch return FsError.OutOfMemory;

    const bytes_read = file.readAll(content) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.InputOutput => return FsError.Unknown,
        error.IsDir => return FsError.InvalidPath,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };

    // Shrink allocation to actual size if needed
    if (bytes_read < file_size) {
        const actual_content = allocator.realloc(content, bytes_read) catch {
            allocator.free(content);
            return FsError.OutOfMemory;
        };
        return actual_content;
    }

    return content;
}

// =============================================================================
// WRITE OPERATIONS: Tri-signature pattern for file writing
// =============================================================================

/// :min profile - Simple synchronous file writing
pub fn write_file_min(path: []const u8, content: []const u8, allocator: std.mem.Allocator) FsError!void {
    _ = allocator; // Not used in this implementation

    if (path.len == 0) return FsError.InvalidPath;

    // Real file writing implementation
    const file = std.fs.cwd().createFile(path, .{}) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.FileNotFound => return FsError.FileNotFound,
        error.NameTooLong => return FsError.InvalidPath,
        error.NoSpaceLeft => return FsError.OutOfMemory,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };
    defer file.close();

    file.writeAll(content) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.NoSpaceLeft => return FsError.OutOfMemory,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };
}

/// :go profile - Context-aware file writing
pub fn write_file_go(path: []const u8, content: []const u8, ctx: Context, allocator: std.mem.Allocator) FsError!void {
    _ = allocator; // Not used in this implementation

    if (path.len == 0) return FsError.InvalidPath;
    if (ctx.is_done()) return FsError.ContextCancelled;

    // Real file writing implementation with context awareness
    const file = std.fs.cwd().createFile(path, .{}) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.FileNotFound => return FsError.FileNotFound,
        error.NameTooLong => return FsError.InvalidPath,
        error.NoSpaceLeft => return FsError.OutOfMemory,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };
    defer file.close();

    file.writeAll(content) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.NoSpaceLeft => return FsError.OutOfMemory,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };
}

/// :full profile - Capability-gated file writing
pub fn write_file_full(path: []const u8, content: []const u8, cap: Capability.FileSystem, allocator: std.mem.Allocator) FsError!void {
    _ = allocator; // Not used in this implementation

    if (path.len == 0) return FsError.InvalidPath;
    if (!cap.allows_path(path)) return FsError.CapabilityRequired;
    if (!cap.allows_write()) return FsError.PermissionDenied;

    // Audit capability usage
    Capability.audit_capability_usage(cap, "fs.write");

    // Real file writing implementation with capability validation
    const file = std.fs.cwd().createFile(path, .{}) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.FileNotFound => return FsError.FileNotFound,
        error.NameTooLong => return FsError.InvalidPath,
        error.NoSpaceLeft => return FsError.OutOfMemory,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };
    defer file.close();

    file.writeAll(content) catch |err| switch (err) {
        error.AccessDenied => return FsError.PermissionDenied,
        error.NoSpaceLeft => return FsError.OutOfMemory,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };
}

// =============================================================================
// METADATA OPERATIONS: File information retrieval
// =============================================================================

/// :min profile - Simple file info
pub fn file_info_min(path: []const u8, allocator: std.mem.Allocator) FsError!FileInfo {
    _ = allocator; // Not used in this implementation

    if (path.len == 0) return FsError.InvalidPath;

    // Real file info implementation
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return FsError.FileNotFound,
        error.AccessDenied => return FsError.PermissionDenied,
        error.NameTooLong => return FsError.InvalidPath,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };

    return FileInfo{
        .size = stat.size,
        .modified_time = @intCast(stat.mtime),
        .is_directory = stat.kind == .directory,
        .permissions = @intCast(stat.mode),
    };
}

/// :go profile - Context-aware file info
pub fn file_info_go(path: []const u8, ctx: Context, allocator: std.mem.Allocator) FsError!FileInfo {
    _ = allocator; // Not used in this implementation

    if (path.len == 0) return FsError.InvalidPath;
    if (ctx.is_done()) return FsError.ContextCancelled;

    // Real file info implementation with context awareness
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return FsError.FileNotFound,
        error.AccessDenied => return FsError.PermissionDenied,
        error.NameTooLong => return FsError.InvalidPath,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };

    return FileInfo{
        .size = stat.size,
        .modified_time = @intCast(stat.mtime),
        .is_directory = stat.kind == .directory,
        .permissions = @intCast(stat.mode),
    };
}

/// :full profile - Capability-gated file info
pub fn file_info_full(path: []const u8, cap: Capability.FileSystem, allocator: std.mem.Allocator) FsError!FileInfo {
    _ = allocator; // Not used in this implementation

    if (path.len == 0) return FsError.InvalidPath;
    if (!cap.allows_path(path)) return FsError.CapabilityRequired;

    // Audit capability usage
    Capability.audit_capability_usage(cap, "fs.stat");

    // Real file info implementation with capability validation
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return FsError.FileNotFound,
        error.AccessDenied => return FsError.PermissionDenied,
        error.NameTooLong => return FsError.InvalidPath,
        error.SystemResources => return FsError.OutOfMemory,
        else => return FsError.Unknown,
    };

    return FileInfo{
        .size = stat.size,
        .modified_time = @intCast(stat.mtime),
        .is_directory = stat.kind == .directory,
        .permissions = @intCast(stat.mode),
    };
}

// =============================================================================
// PROFILE-AWARE DISPATCH: Single entry point, profile-specific behavior
// =============================================================================

/// Universal read_file function - dispatches to profile-specific implementation
pub fn read_file(args: anytype) FsError![]u8 {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info != .@"struct") {
        @compileError("read_file requires struct arguments");
    }

    const fields = args_info.@"struct".fields;

    // Dispatch based on argument signature
    if (fields.len == 2) {
        // :min profile: read_file(.{ .path = path, .allocator = allocator })
        return read_file_min(args.path, args.allocator);
    } else if (fields.len == 3 and @hasField(ArgsType, "ctx")) {
        // :go profile: read_file(.{ .path = path, .ctx = ctx, .allocator = allocator })
        return read_file_go(args.path, args.ctx, args.allocator);
    } else if (fields.len == 3 and @hasField(ArgsType, "cap")) {
        // :full profile: read_file(.{ .path = path, .cap = cap, .allocator = allocator })
        return read_file_full(args.path, args.cap, args.allocator);
    } else {
        @compileError("Invalid arguments for read_file - check profile requirements");
    }
}

/// Universal write_file function - dispatches to profile-specific implementation
pub fn write_file(args: anytype) FsError!void {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info != .@"struct") {
        @compileError("write_file requires struct arguments");
    }

    const fields = args_info.@"struct".fields;

    // Dispatch based on argument signature
    if (fields.len == 3) {
        // :min profile: write_file(.{ .path = path, .content = content, .allocator = allocator })
        return write_file_min(args.path, args.content, args.allocator);
    } else if (fields.len == 4 and @hasField(ArgsType, "ctx")) {
        // :go profile: write_file(.{ .path = path, .content = content, .ctx = ctx, .allocator = allocator })
        return write_file_go(args.path, args.content, args.ctx, args.allocator);
    } else if (fields.len == 4 and @hasField(ArgsType, "cap")) {
        // :full profile: write_file(.{ .path = path, .content = content, .cap = cap, .allocator = allocator })
        return write_file_full(args.path, args.content, args.cap, args.allocator);
    } else {
        @compileError("Invalid arguments for write_file - check profile requirements");
    }
}

// =============================================================================
// CONVENIENCE WRAPPERS: Profile-specific convenience functions
// =============================================================================

/// Convenience wrapper for :min profile
pub fn read(path: []const u8, allocator: std.mem.Allocator) FsError![]u8 {
    return read_file(.{ .path = path, .allocator = allocator });
}

/// Convenience wrapper for :go profile
pub fn read_with_context(path: []const u8, ctx: Context, allocator: std.mem.Allocator) FsError![]u8 {
    return read_file(.{ .path = path, .ctx = ctx, .allocator = allocator });
}

/// Convenience wrapper for :full profile
pub fn read_with_capability(path: []const u8, cap: Capability.FileSystem, allocator: std.mem.Allocator) FsError![]u8 {
    return read_file(.{ .path = path, .cap = cap, .allocator = allocator });
}

// =============================================================================
// PHYSICALFS CONVENIENCE READS: Task 5.1 Implementation
// =============================================================================

/// Read file as UTF-8 string using PhysicalFS (convenience wrapper)
/// Automatically handles file opening, reading, and closing
pub fn read_string(path: []const u8, allocator: std.mem.Allocator) FsError![]u8 {
    const PhysicalFS = @import("physical_fs.zig").PhysicalFS;
    var fs = PhysicalFS.init(allocator);
    defer fs.deinit();

    return fs.readString(path);
}

// =============================================================================
// MODERN FORWARD-LOOKING FEATURES: Streaming and Async Support
// =============================================================================

/// Streaming file reader for large files (forward-looking feature)
/// Provides chunked reading with progress callbacks
pub const StreamingReader = struct {
    file: @import("physical_fs.zig").File,
    buffer_size: usize,
    allocator: std.mem.Allocator,

    /// Initialize streaming reader
    pub fn init(path: []const u8, buffer_size: usize, allocator: std.mem.Allocator) !StreamingReader {
        const PhysicalFS = @import("physical_fs.zig").PhysicalFS;
        var fs = PhysicalFS.init(allocator);
        defer fs.deinit();

        const file = try fs.openFile(path);

        return StreamingReader{
            .file = file,
            .buffer_size = buffer_size,
            .allocator = allocator,
        };
    }

    /// Read next chunk with optional progress callback
    pub fn readChunk(self: *StreamingReader, progress_callback: ?*const fn (usize) void) !?[]u8 {
        const buffer = try self.allocator.alloc(u8, self.buffer_size);
        errdefer self.allocator.free(buffer);

        const bytes_read = try self.file.read(buffer);

        if (bytes_read == 0) {
            self.allocator.free(buffer);
            return null; // EOF
        }

        // Shrink buffer to actual size if needed
        if (bytes_read < self.buffer_size) {
            const actual_buffer = try self.allocator.realloc(buffer, bytes_read);
            if (progress_callback) |callback| {
                callback(bytes_read);
            }
            return actual_buffer;
        }

        if (progress_callback) |callback| {
            callback(bytes_read);
        }

        return buffer;
    }

    /// Get total file size
    pub fn getSize(self: StreamingReader) !u64 {
        return self.file.metadata().size;
    }

    /// Clean up streaming reader
    pub fn deinit(self: *StreamingReader) void {
        self.file.deinit();
    }
};

/// Async file operations (forward-looking feature for future Zig async support)
/// Placeholder for when Zig gains better async I/O support
pub const AsyncFileOps = struct {
    /// Async file reading (placeholder for future implementation)
    /// When Zig async I/O matures, this will provide non-blocking file operations
    pub fn readAsync(path: []const u8, allocator: std.mem.Allocator, callback: anytype) !void {
        _ = path;
        _ = allocator;
        _ = callback;

        // TODO: Implement when Zig async I/O is more mature
        // For now, this is a forward-looking placeholder
        return FsError.NotSupported;
    }

    /// Async file writing (placeholder for future implementation)
    pub fn writeAsync(path: []const u8, content: []const u8, allocator: std.mem.Allocator, callback: anytype) !void {
        _ = path;
        _ = content;
        _ = allocator;
        _ = callback;

        // TODO: Implement when Zig async I/O is more mature
        return FsError.NotSupported;
    }
};

// =============================================================================
// FILE WATCHING AND MONITORING (Modern Feature)
/// File change monitoring (forward-looking for hot reload, etc.)
pub const FileWatcher = struct {
    allocator: std.mem.Allocator,
    watched_paths: std.StringHashMap(void),

    /// Initialize file watcher
    pub fn init(allocator: std.mem.Allocator) FileWatcher {
        return FileWatcher{
            .allocator = allocator,
            .watched_paths = std.StringHashMap(void).init(allocator),
        };
    }

    /// Watch a file for changes
    pub fn watchFile(self: *FileWatcher, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.watched_paths.put(path_copy, {});
    }

    /// Check if any watched files have changed
    /// Returns list of changed files
    pub fn checkChanges(self: FileWatcher) ![]const []const u8 {
        var changed_files = std.ArrayList([]const u8).init(self.allocator);
        defer changed_files.deinit();

        // TODO: Implement actual file change detection
        // For now, this is a placeholder for future inotify/kqueue integration
        // Would iterate through self.watched_paths and check modification times
        _ = self; // Placeholder - would use self.watched_paths in real implementation

        return changed_files.toOwnedSlice();
    }

    /// Stop watching a file
    pub fn unwatchFile(self: *FileWatcher, path: []const u8) void {
        // Remove from watched paths (we don't care if it was present or not)
        _ = self.watched_paths.remove(path);
    }

    /// Clean up file watcher
    pub fn deinit(self: *FileWatcher) void {
        var it = self.watched_paths.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.watched_paths.deinit();
    }
};

/// Convenience wrapper for :min profile
pub fn write(path: []const u8, content: []const u8, allocator: std.mem.Allocator) FsError!void {
    return write_file(.{ .path = path, .content = content, .allocator = allocator });
}

/// Convenience wrapper for :go profile
pub fn write_with_context(path: []const u8, content: []const u8, ctx: Context, allocator: std.mem.Allocator) FsError!void {
    return write_file(.{ .path = path, .content = content, .ctx = ctx, .allocator = allocator });
}

/// Convenience wrapper for :full profile
pub fn write_with_capability(path: []const u8, content: []const u8, cap: Capability.FileSystem, allocator: std.mem.Allocator) FsError!void {
    return write_file(.{ .path = path, .content = content, .cap = cap, .allocator = allocator });
}

// =============================================================================
// TESTS: Behavior parity across profiles
// =============================================================================

test "read_file tri-signature pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test :min profile
    {
        const content = try read_file_min("/test/file.txt", allocator);
        defer allocator.free(content);

        try testing.expect(std.mem.indexOf(u8, content, "min profile") != null);
        try testing.expect(std.mem.indexOf(u8, content, "/test/file.txt") != null);
    }

    // Test :go profile (mock context)
    {
        var mock_ctx = Context.init(allocator);
        defer mock_ctx.deinit();

        const content = try read_file_go("/test/file.txt", mock_ctx, allocator);
        defer allocator.free(content);

        try testing.expect(std.mem.indexOf(u8, content, "go profile") != null);
        try testing.expect(std.mem.indexOf(u8, content, "Context: active") != null);
    }

    // Test :full profile (mock capability)
    {
        var mock_cap = Capability.FileSystem.init("test-fs-cap", allocator);
        defer mock_cap.deinit();

        try mock_cap.allow_path("/test");

        const content = try read_file_full("/test/file.txt", mock_cap, allocator);
        defer allocator.free(content);

        try testing.expect(std.mem.indexOf(u8, content, "full profile") != null);
        try testing.expect(std.mem.indexOf(u8, content, "test-fs-cap") != null);
    }
}

test "write_file tri-signature pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test :min profile
    try write_file_min("/test/output.txt", "test content", allocator);

    // Test :go profile (mock context)
    {
        var mock_ctx = Context.init(allocator);
        defer mock_ctx.deinit();

        try write_file_go("/test/output.txt", "test content", mock_ctx, allocator);
    }

    // Test :full profile (mock capability)
    {
        var mock_cap = Capability.FileSystem.init("test-fs-cap", allocator);
        defer mock_cap.deinit();

        try mock_cap.allow_path("/test");

        try write_file_full("/test/output.txt", "test content", mock_cap, allocator);
    }
}

test "file_info tri-signature pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test :min profile
    {
        const info = try file_info_min("/test/file.txt", allocator);
        try testing.expect(info.size == 1024);
        try testing.expect(!info.is_directory);
    }

    // Test :go profile (mock context)
    {
        var mock_ctx = Context.init(allocator);
        defer mock_ctx.deinit();

        const info = try file_info_go("/test/file.txt", mock_ctx, allocator);
        try testing.expect(info.size == 2048);
        try testing.expect(!info.is_directory);
    }

    // Test :full profile (mock capability)
    {
        var mock_cap = Capability.FileSystem.init("test-fs-cap", allocator);
        defer mock_cap.deinit();

        try mock_cap.allow_path("/test");

        const info = try file_info_full("/test/file.txt", mock_cap, allocator);
        try testing.expect(info.size == 4096);
        try testing.expect(!info.is_directory);
    }
}

test "profile-aware dispatch" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test dispatch to :min implementation
    {
        const content = try read_file(.{ .path = "/test/file.txt", .allocator = allocator });
        defer allocator.free(content);

        try testing.expect(std.mem.indexOf(u8, content, "min profile") != null);
    }

    // Test write dispatch to :min implementation
    try write_file(.{ .path = "/test/output.txt", .content = "test", .allocator = allocator });

    // Note: :go and :full tests would require proper Context and Capability implementations
}

test "capability validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cap = Capability.FileSystem.init("restricted-fs", allocator);
    defer cap.deinit();

    // Allow only /safe paths
    try cap.allow_path("/safe");

    // Should succeed for allowed path
    const content = try read_file_full("/safe/file.txt", cap, allocator);
    defer allocator.free(content);

    // Should fail for disallowed path
    try testing.expectError(FsError.CapabilityRequired, read_file_full("/etc/passwd", cap, allocator));
}

// =============================================================================
// UTCP MANUAL: AI-driven discovery and manipulation
// =============================================================================

/// Self-describing manual for AI agents and tooling
/// Provides comprehensive interface documentation for automated usage
pub fn utcpManual() []const u8 {
    return (
        \\# Janus Standard Library - File System Module (std/fs)
        \\## Overview
        \\Tri-signature file system operations with rising capability across profiles.
        \\Supports :min (simple), :go (context-aware), and :full (capability-gated) profiles.
        \\
        \\## Core Functions
        \\### File Reading
        \\- `read_file_min(path, allocator)` - Simple synchronous file reading
        \\- `read_file_go(path, context, allocator)` - Context-aware reading with cancellation
        \\- `read_file_full(path, capability, allocator)` - Capability-gated reading with security
        \\- `read_file(args)` - Profile-aware dispatch function
        \\
        \\### File Writing
        \\- `write_file_min(path, content, allocator)` - Simple synchronous file writing
        \\- `write_file_go(path, content, context, allocator)` - Context-aware writing
        \\- `write_file_full(path, content, capability, allocator)` - Capability-gated writing
        \\- `write_file(args)` - Profile-aware dispatch function
        \\
        \\### File Information
        \\- `file_info_min(path, allocator)` - Simple file metadata
        \\- `file_info_go(path, context, allocator)` - Context-aware file metadata
        \\- `file_info_full(path, capability, allocator)` - Capability-gated file metadata
        \\
        \\## Profile Usage
        \\### :min Profile (Simple)
        \\```zig
        \\const content = try read_file(.{ .path = "/file.txt", .allocator = allocator });
        \\try write_file(.{ .path = "/output.txt", .content = "data", .allocator = allocator });
        \\```
        \\
        \\### :go Profile (Context-aware)
        \\```zig
        \\var ctx = Context.init(allocator);
        \\defer ctx.deinit();
        \\const content = try read_file(.{ .path = "/file.txt", .ctx = ctx, .allocator = allocator });
        \\```
        \\
        \\### :full Profile (Capability-gated)
        \\```zig
        \\var cap = Capability.FileSystem.init("fs-cap", allocator);
        \\defer cap.deinit();
        \\try cap.allow_path("/safe");
        \\const content = try read_file(.{ .path = "/safe/file.txt", .cap = cap, .allocator = allocator });
        \\```
        \\
        \\## Error Handling
        \\Returns `FsError` with specific error types:
        \\- `FileNotFound` - File does not exist
        \\- `PermissionDenied` - Access denied or capability insufficient
        \\- `InvalidPath` - Path is malformed or empty
        \\- `CapabilityRequired` - Required capability not granted
        \\- `ContextCancelled` - Context was cancelled or deadline exceeded
        \\- `OutOfMemory` - Memory allocation failed
        \\- `Unknown` - Unexpected system error
        \\
        \\## Security Model
        \\- **:min**: No security, direct file access (use for trusted environments)
        \\- **:go**: Context-based timeouts and cancellation (prevents hanging)
        \\- **:full**: Capability-based authorization with audit trails (defense in depth)
        \\
        \\## Performance Characteristics
        \\- Zero-copy where possible using Zig's I/O system
        \\- Explicit memory management with allocator sovereignty
        \\- Context cancellation support for cooperative concurrency
        \\- Capability validation with minimal runtime overhead
        \\
        \\## Integration Points
        \\- Works with `std_context.zig` for structured concurrency
        \\- Integrates with `capabilities.zig` for security boundaries
        \\- Compatible with Zig's standard library file operations
        \\- Supports all Janus language profiles (:min, :go, :elixir, :full)
        \\
        \\## Best Practices
        \\1. Always handle `FsError` explicitly - no silent failures
        \\2. Use appropriate profile for your security requirements
        \\3. Manage memory explicitly with proper allocator usage
        \\4. Validate capabilities before file operations in :full profile
        \\5. Use context deadlines for timeout-sensitive operations
        \\6. Audit capability usage for security compliance
        \\
        \\## Examples
        \\See test functions for comprehensive usage examples across all profiles.
        \\Test coverage includes error conditions, capability validation, and profile dispatch.
        \\
    );
}
