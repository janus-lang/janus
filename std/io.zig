// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! std/io.zig - Capability-gated I/O operations
//!
//! This module implements the Zig backend for std/io.jan, pg:
//! - Allocator sovereignty: All allocations are explicit
//! - Capability security: All external access is gated
//! - Error transparency: All failure modes are visible
//! - Zero-copy bias: Avoid unnecessary data movement

const std = @import("std");
const compat_fs = @import("compat_fs");
const builtin = @import("builtin");

// Context System import (for :service and :sovereign profiles)
const context_module = @import("core/context.zig");
pub const Context = context_module.Context;
pub const CapabilitySet = context_module.CapabilitySet;
pub const Logger = context_module.Logger;

// =============================================================================
// TRI-SIGNATURE PATTERN: Profile-Specific APIs
// =============================================================================
//
// Janus enforces Progressive Disclosure through profile-specific function
// signatures. Each profile has its own API surface:
//
// :core      - Simple procedural (allocator-only)
// :service   - Context-aware (deadline, cancellation, logging)
// :sovereign - Capability-gated (explicit security tokens)
//
// Usage:
//   const io = @import("std/io.zig");
//
//   // :core profile - Simple
//   const data = try io.core.readFile("file.txt", allocator);
//
//   // :service profile - Context-aware
//   const data = try io.service.readFile("file.txt", &ctx);
//
//   // :sovereign profile - Capability-gated
//   const data = try io.sovereign.readFile("file.txt", cap, &ctx);
// =============================================================================

// ===== CORE TYPES =====

/// Capability types - these gate access to external resources
pub const FileReadCapability = struct {
    path: []const u8,

    pub fn validate(self: FileReadCapability) bool {
        // TODO: Implement cryptographic validation
        _ = self;
        return true;
    }
};

pub const FileWriteCapability = struct {
    path: []const u8,

    pub fn validate(self: FileWriteCapability) bool {
        // TODO: Implement cryptographic validation
        _ = self;
        return true;
    }
};

pub const StdinReadCapability = struct {
    pub fn validate(self: StdinReadCapability) bool {
        _ = self;
        return true;
    }
};

pub const StdoutWriteCapability = struct {
    pub fn validate(self: StdoutWriteCapability) bool {
        _ = self;
        return true;
    }
};

pub const StderrWriteCapability = struct {
    pub fn validate(self: StderrWriteCapability) bool {
        _ = self;
        return true;
    }
};

/// Error types - domain-specific and informative
pub const IoError = error{
    // File system errors
    FileNotFound,
    PermissionDenied,
    InvalidPath,

    // Stream errors
    EndOfFile,
    UnexpectedEof,
    BrokenPipe,
    Interrupted,

    // Generic with context
    OutOfMemory,
    InvalidArgument,
    Timeout,
    Cancelled,
    Unknown,
};

/// File handle - represents an open file with explicit capabilities
pub const File = struct {
    handle: std.fs.File,
    capabilities: FileCapabilities,

    const FileCapabilities = struct {
        can_read: bool,
        can_write: bool,
    };

    pub fn close(self: *File) void {
        self.handle.close();
    }

    pub fn read(self: File, buffer: []u8) IoError!usize {
        if (!self.capabilities.can_read) {
            return IoError.PermissionDenied;
        }

        return self.handle.read(buffer) catch |err| switch (err) {
            error.AccessDenied => IoError.PermissionDenied,
            error.BrokenPipe => IoError.BrokenPipe,
            error.ConnectionResetByPeer => IoError.BrokenPipe,
            error.InputOutput => IoError.Unknown,
            error.IsDir => IoError.InvalidPath,
            error.NotOpenForReading => IoError.PermissionDenied,
            error.OperationAborted => IoError.Interrupted,
            error.SystemResources => IoError.OutOfMemory,
            error.Unexpected => IoError.Unknown,
            error.WouldBlock => IoError.Unknown,
            error.LockViolation => IoError.PermissionDenied,
            error.ProcessNotFound => IoError.Unknown,
            error.ConnectionTimedOut => IoError.Timeout,
            error.SocketNotConnected => IoError.BrokenPipe,
            error.Canceled => IoError.Cancelled,
        };
    }

    pub fn write(self: File, data: []const u8) IoError!usize {
        if (!self.capabilities.can_write) {
            return IoError.PermissionDenied;
        }

        return self.handle.write(data) catch |err| switch (err) {
            error.AccessDenied => IoError.PermissionDenied,
            error.BrokenPipe => IoError.BrokenPipe,
            error.DeviceBusy => IoError.Unknown,
            error.DiskQuota => IoError.OutOfMemory,
            error.FileTooBig => IoError.OutOfMemory,
            error.InputOutput => IoError.Unknown,
            error.InvalidArgument => IoError.InvalidArgument,
            error.LockViolation => IoError.PermissionDenied,
            error.NoSpaceLeft => IoError.OutOfMemory,
            error.NotOpenForWriting => IoError.PermissionDenied,
            error.OperationAborted => IoError.Interrupted,
            error.SystemResources => IoError.OutOfMemory,
            error.Unexpected => IoError.Unknown,
            error.WouldBlock => IoError.Unknown,
            error.NoDevice => IoError.Unknown,
            error.ConnectionResetByPeer => IoError.BrokenPipe,
            error.ProcessNotFound => IoError.Unknown,
        };
    }
};

/// Buffer types - explicit about ownership and lifecycle
pub const ReadBuffer = struct {
    data: []const u8,
    allocator: ?std.mem.Allocator, // null for stack/static buffers

    pub fn deinit(self: ReadBuffer) void {
        if (self.allocator) |alloc| {
            alloc.free(self.data);
        }
    }
};

pub const WriteBuffer = struct {
    data: []const u8,
};

// ===== CORE FUNCTIONS =====

/// File operations - capability-gated and explicit about allocation
/// Note: This is a legacy API. Prefer using profile-specific namespaces:
///       core.readFile, service.readFile, or sovereign.readFile
pub fn openFile(
    path: []const u8,
    capability: anytype, // FileReadCapability or FileWriteCapability
) IoError!File {
    if (!capability.validate()) {
        return IoError.PermissionDenied;
    }

    // Determine access mode based on capability type
    const CapType = @TypeOf(capability);
    const access_mode = if (CapType == FileReadCapability)
        std.fs.File.OpenMode.read_only
    else if (CapType == FileWriteCapability)
        std.fs.File.OpenMode.write_only
    else
        @compileError("Invalid capability type for openFile");

    const file = std.fs.cwd().openFile(path, .{ .mode = access_mode }) catch |err| switch (err) {
        error.FileNotFound => return IoError.FileNotFound,
        error.AccessDenied => return IoError.PermissionDenied,
        error.NameTooLong => return IoError.InvalidPath,
        error.SystemResources => return IoError.OutOfMemory,
        else => return IoError.Unknown,
    };

    return File{
        .handle = file,
        .capabilities = .{
            .can_read = CapType == FileReadCapability,
            .can_write = CapType == FileWriteCapability,
        },
    };
}

pub fn readFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    capability: FileReadCapability,
) IoError!ReadBuffer {
    if (!capability.validate()) {
        return IoError.PermissionDenied;
    }

    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return IoError.FileNotFound,
        error.AccessDenied => return IoError.PermissionDenied,
        error.NameTooLong => return IoError.InvalidPath,
        error.SystemResources => return IoError.OutOfMemory,
        else => return IoError.Unknown,
    };
    defer file.close();

    const file_size = file.getEndPos() catch return IoError.Unknown;
    const contents = allocator.alloc(u8, file_size) catch return IoError.OutOfMemory;

    _ = file.readAll(contents) catch |err| {
        allocator.free(contents);
        return switch (err) {
            error.AccessDenied => IoError.PermissionDenied,
            error.BrokenPipe => IoError.BrokenPipe,
            error.ConnectionResetByPeer => IoError.BrokenPipe,
            error.InputOutput => IoError.Unknown,
            error.IsDir => IoError.InvalidPath,
            error.NotOpenForReading => IoError.PermissionDenied,
            error.OperationAborted => IoError.Interrupted,
            error.SystemResources => IoError.OutOfMemory,
            error.Unexpected => IoError.Unknown,
            error.WouldBlock => IoError.Unknown,
            error.LockViolation => IoError.PermissionDenied,
            error.ProcessNotFound => IoError.Unknown,
            error.ConnectionTimedOut => IoError.Timeout,
            error.SocketNotConnected => IoError.BrokenPipe,
            error.Canceled => IoError.Cancelled,
        };
    };

    return ReadBuffer{
        .data = contents,
        .allocator = allocator,
    };
}

pub fn writeFile(
    path: []const u8,
    content: WriteBuffer,
    capability: FileWriteCapability,
) IoError!void {
    if (!capability.validate()) {
        return IoError.PermissionDenied;
    }

    const file = compat_fs.createFile(path, .{}) catch |err| switch (err) {
        error.AccessDenied => return IoError.PermissionDenied,
        error.FileNotFound => return IoError.FileNotFound,
        error.NameTooLong => return IoError.InvalidPath,
        error.NoSpaceLeft => return IoError.OutOfMemory,
        error.SystemResources => return IoError.OutOfMemory,
        else => return IoError.Unknown,
    };
    defer file.close();

    file.writeAll(content.data) catch |err| switch (err) {
        error.AccessDenied => return IoError.PermissionDenied,
        error.BrokenPipe => return IoError.BrokenPipe,
        error.DeviceBusy => return IoError.Unknown,
        error.DiskQuota => return IoError.OutOfMemory,
        error.FileTooBig => return IoError.OutOfMemory,
        error.InputOutput => return IoError.Unknown,
        error.InvalidArgument => return IoError.InvalidArgument,
        error.LockViolation => return IoError.PermissionDenied,
        error.NoSpaceLeft => return IoError.OutOfMemory,
        error.NotOpenForWriting => return IoError.PermissionDenied,
        error.OperationAborted => return IoError.Interrupted,
        error.SystemResources => return IoError.OutOfMemory,
        error.Unexpected => return IoError.Unknown,
        error.WouldBlock => return IoError.Unknown,
        error.NoDevice => return IoError.Unknown,
        error.ConnectionResetByPeer => return IoError.BrokenPipe,
        error.ProcessNotFound => return IoError.Unknown,
        else => return IoError.Unknown,
    };
}

// ===== STREAMING OPERATIONS =====

/// Streaming operations - zero-copy where possible
pub fn readInto(
    file: File,
    buffer: []u8,
) IoError!usize {
    return file.read(buffer);
}

pub fn writeFrom(
    file: File,
    buffer: []const u8,
) IoError!usize {
    return file.write(buffer);
}

// ===== STANDARD STREAMS =====

/// Simple print function for :core profile - no capabilities required
/// This is the basic "Hello, World" function that just works
/// Note: Delegates to core.print for Single Brain doctrine compliance
pub fn print(message: []const u8) void {
    core.print(message);
}

/// Print with newline - convenience function for :core profile
/// Note: Delegates to core.println for Single Brain doctrine compliance
pub fn println(message: []const u8) void {
    core.println(message);
}

/// Standard streams - capability-gated
pub fn readStdin(
    allocator: std.mem.Allocator,
    capability: StdinReadCapability,
) IoError!ReadBuffer {
    if (!capability.validate()) {
        return IoError.PermissionDenied;
    }

    const stdin_file = std.fs.File.stdin();
    const contents = stdin_file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch |err| switch (err) {
        error.OutOfMemory => return IoError.OutOfMemory,
        error.StreamTooLong => return IoError.OutOfMemory,
        else => return IoError.Unknown,
    };

    return ReadBuffer{
        .data = contents,
        .allocator = allocator,
    };
}

pub fn writeStdout(
    content: WriteBuffer,
    capability: StdoutWriteCapability,
) IoError!void {
    if (!capability.validate()) {
        return IoError.PermissionDenied;
    }

    const stdout = std.fs.File.stdout();
    stdout.writeAll(content.data) catch |err| switch (err) {
        error.BrokenPipe => return IoError.BrokenPipe,
        error.DeviceBusy => return IoError.Unknown,
        error.DiskQuota => return IoError.OutOfMemory,
        error.FileTooBig => return IoError.OutOfMemory,
        error.InputOutput => return IoError.Unknown,
        error.InvalidArgument => return IoError.InvalidArgument,
        error.LockViolation => return IoError.PermissionDenied,
        error.NoSpaceLeft => return IoError.OutOfMemory,
        error.NotOpenForWriting => return IoError.PermissionDenied,
        error.OperationAborted => return IoError.Interrupted,
        error.SystemResources => return IoError.OutOfMemory,
        error.Unexpected => return IoError.Unknown,
        error.WouldBlock => return IoError.Unknown,
        error.AccessDenied => return IoError.PermissionDenied,
        error.NoDevice => return IoError.Unknown,
        error.ConnectionResetByPeer => return IoError.BrokenPipe,
        error.ProcessNotFound => return IoError.Unknown,
    };
}

pub fn writeStderr(
    content: WriteBuffer,
    capability: StderrWriteCapability,
) IoError!void {
    if (!capability.validate()) {
        return IoError.PermissionDenied;
    }

    const stderr = std.fs.File.stderr();
    stderr.writeAll(content.data) catch |err| switch (err) {
        error.BrokenPipe => return IoError.BrokenPipe,
        error.DeviceBusy => return IoError.Unknown,
        error.DiskQuota => return IoError.OutOfMemory,
        error.FileTooBig => return IoError.OutOfMemory,
        error.InputOutput => return IoError.Unknown,
        error.InvalidArgument => return IoError.InvalidArgument,
        error.LockViolation => return IoError.PermissionDenied,
        error.NoSpaceLeft => return IoError.OutOfMemory,
        error.NotOpenForWriting => return IoError.PermissionDenied,
        error.OperationAborted => return IoError.Interrupted,
        error.SystemResources => return IoError.OutOfMemory,
        error.Unexpected => return IoError.Unknown,
        error.WouldBlock => return IoError.Unknown,
        error.AccessDenied => return IoError.PermissionDenied,
        error.NoDevice => return IoError.Unknown,
        error.ConnectionResetByPeer => return IoError.BrokenPipe,
        error.ProcessNotFound => return IoError.Unknown,
    };
}

// =============================================================================
// PROFILE-SPECIFIC NAMESPACES (Tri-Signature Pattern)
// =============================================================================

// -----------------------------------------------------------------------------
// Private Implementation Functions (Single Brain Doctrine)
// -----------------------------------------------------------------------------
// These contain the actual I/O logic. Profile-specific functions delegate here
// after performing their profile-appropriate validation/checks.
// -----------------------------------------------------------------------------

/// Private: Read file contents into buffer
/// All profile-specific readFile functions delegate to this after validation.
fn _readFileImpl(path: []const u8, allocator: std.mem.Allocator) IoError!ReadBuffer {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return IoError.FileNotFound,
        error.AccessDenied => return IoError.PermissionDenied,
        error.NameTooLong => return IoError.InvalidPath,
        error.SystemResources => return IoError.OutOfMemory,
        else => return IoError.Unknown,
    };
    defer file.close();

    const file_size = file.getEndPos() catch return IoError.Unknown;
    const contents = allocator.alloc(u8, file_size) catch return IoError.OutOfMemory;

    _ = file.readAll(contents) catch |err| {
        allocator.free(contents);
        return mapReadError(err);
    };

    return ReadBuffer{
        .data = contents,
        .allocator = allocator,
    };
}

/// Private: Write content to file
/// All profile-specific writeFile functions delegate to this after validation.
fn _writeFileImpl(path: []const u8, content: []const u8) IoError!void {
    const file = compat_fs.createFile(path, .{}) catch |err| switch (err) {
        error.AccessDenied => return IoError.PermissionDenied,
        error.FileNotFound => return IoError.FileNotFound,
        error.NameTooLong => return IoError.InvalidPath,
        error.NoSpaceLeft => return IoError.OutOfMemory,
        error.SystemResources => return IoError.OutOfMemory,
        else => return IoError.Unknown,
    };
    defer file.close();

    file.writeAll(content) catch |err| return mapWriteError(err);
}

// -----------------------------------------------------------------------------
// :core Profile API
// -----------------------------------------------------------------------------

/// :core Profile API
/// Simple procedural interface with explicit allocator.
/// No context, no capabilities - just the minimum for teaching and simple tools.
pub const core = struct {
    /// Read entire file contents (:core profile)
    /// Simple signature: just path and allocator
    pub fn readFile(path: []const u8, allocator: std.mem.Allocator) IoError!ReadBuffer {
        return _readFileImpl(path, allocator);
    }

    /// Write content to file (:core profile)
    /// Simple signature: path and content only
    pub fn writeFile(path: []const u8, content: []const u8) IoError!void {
        return _writeFileImpl(path, content);
    }

    /// Print to stdout (:core profile)
    /// No error handling - "just works" for teaching
    pub fn print(message: []const u8) void {
        const stdout = std.fs.File.stdout();
        stdout.writeAll(message) catch return;
    }

    /// Print with newline (:core profile)
    pub fn println(message: []const u8) void {
        const stdout = std.fs.File.stdout();
        stdout.writeAll(message) catch return;
        stdout.writeAll("\n") catch return;
    }
};

// -----------------------------------------------------------------------------
// :service Profile API
// -----------------------------------------------------------------------------

/// :service Profile API
/// Context-aware interface with deadline, cancellation, and logging.
/// Uses allocator from Context, supports structured cancellation.
pub const service = struct {
    /// Read entire file contents (:service profile)
    /// Context-aware: respects deadline/cancellation, uses context allocator
    pub fn readFile(path: []const u8, ctx: *Context) IoError!ReadBuffer {
        // Pre-operation check: cancellation
        if (ctx.isDone()) {
            return IoError.Cancelled;
        }

        ctx.logInfo("Reading file: {s}", .{path});

        // Delegate to single implementation
        const result = _readFileImpl(path, ctx.allocator);

        if (result) |buffer| {
            ctx.logInfo("Read {d} bytes from {s}", .{ buffer.data.len, path });
            return buffer;
        } else |err| {
            return err;
        }
    }

    /// Write content to file (:service profile)
    /// Context-aware: respects deadline/cancellation, logs operations
    pub fn writeFile(path: []const u8, content: []const u8, ctx: *Context) IoError!void {
        // Pre-operation check: cancellation
        if (ctx.isDone()) {
            return IoError.Cancelled;
        }

        ctx.logInfo("Writing {d} bytes to: {s}", .{ content.len, path });

        // Delegate to single implementation
        try _writeFileImpl(path, content);

        ctx.logInfo("Write complete: {s}", .{path});
    }
};

// -----------------------------------------------------------------------------
// :sovereign Profile API
// -----------------------------------------------------------------------------

/// :sovereign Profile API
/// Full capability-gated interface with explicit security tokens.
/// Enforces path restrictions, requires capability validation.
pub const sovereign = struct {
    /// Capability token for filesystem read operations
    pub const CapFsRead = struct {
        path_pattern: ?[]const u8 = null, // null = all paths allowed

        pub fn forPath(path: []const u8) CapFsRead {
            return CapFsRead{ .path_pattern = path };
        }

        pub fn validate(self: CapFsRead, path: []const u8) bool {
            if (self.path_pattern) |pattern| {
                return std.mem.startsWith(u8, path, pattern);
            }
            return true;
        }
    };

    /// Capability token for filesystem write operations
    pub const CapFsWrite = struct {
        path_pattern: ?[]const u8 = null,

        pub fn forPath(path: []const u8) CapFsWrite {
            return CapFsWrite{ .path_pattern = path };
        }

        pub fn validate(self: CapFsWrite, path: []const u8) bool {
            if (self.path_pattern) |pattern| {
                return std.mem.startsWith(u8, path, pattern);
            }
            return true;
        }
    };

    /// Read entire file contents (:sovereign profile)
    /// Capability-gated: requires explicit CapFsRead token + Context
    pub fn readFile(path: []const u8, cap: CapFsRead, ctx: *Context) IoError!ReadBuffer {
        // Validate capability token
        if (!cap.validate(path)) {
            ctx.logInfo("SECURITY: Capability denied for path: {s}", .{path});
            return IoError.PermissionDenied;
        }

        // Validate context capabilities
        if (!ctx.canReadFs()) {
            ctx.logInfo("SECURITY: Context lacks fs_read capability", .{});
            return IoError.PermissionDenied;
        }

        // Validate path restrictions
        if (!ctx.isPathAllowed(path)) {
            ctx.logInfo("SECURITY: Path not in allowed list: {s}", .{path});
            return IoError.PermissionDenied;
        }

        // Check cancellation
        if (ctx.isDone()) {
            return IoError.Cancelled;
        }

        ctx.logInfo("SOVEREIGN: Reading file: {s}", .{path});

        // Delegate to single implementation
        const result = _readFileImpl(path, ctx.allocator);

        if (result) |buffer| {
            ctx.logInfo("SOVEREIGN: Read {d} bytes from {s}", .{ buffer.data.len, path });
            return buffer;
        } else |err| {
            return err;
        }
    }

    /// Write content to file (:sovereign profile)
    /// Capability-gated: requires explicit CapFsWrite token + Context
    pub fn writeFile(path: []const u8, content: []const u8, cap: CapFsWrite, ctx: *Context) IoError!void {
        // Validate capability token
        if (!cap.validate(path)) {
            ctx.logInfo("SECURITY: Write capability denied for path: {s}", .{path});
            return IoError.PermissionDenied;
        }

        // Validate context capabilities
        if (!ctx.canWriteFs()) {
            ctx.logInfo("SECURITY: Context lacks fs_write capability", .{});
            return IoError.PermissionDenied;
        }

        // Validate path restrictions
        if (!ctx.isPathAllowed(path)) {
            ctx.logInfo("SECURITY: Path not in allowed list: {s}", .{path});
            return IoError.PermissionDenied;
        }

        // Check cancellation
        if (ctx.isDone()) {
            return IoError.Cancelled;
        }

        ctx.logInfo("SOVEREIGN: Writing {d} bytes to: {s}", .{ content.len, path });

        // Delegate to single implementation
        try _writeFileImpl(path, content);

        ctx.logInfo("SOVEREIGN: Write complete: {s}", .{path});
    }
};

// =============================================================================
// Error Mapping Helpers (shared across profiles)
// =============================================================================

fn mapReadError(err: anytype) IoError {
    return switch (err) {
        error.AccessDenied => IoError.PermissionDenied,
        error.BrokenPipe => IoError.BrokenPipe,
        error.ConnectionResetByPeer => IoError.BrokenPipe,
        error.InputOutput => IoError.Unknown,
        error.IsDir => IoError.InvalidPath,
        error.NotOpenForReading => IoError.PermissionDenied,
        error.OperationAborted => IoError.Interrupted,
        error.SystemResources => IoError.OutOfMemory,
        error.Unexpected => IoError.Unknown,
        error.WouldBlock => IoError.Unknown,
        error.LockViolation => IoError.PermissionDenied,
        error.ProcessNotFound => IoError.Unknown,
        error.ConnectionTimedOut => IoError.Timeout,
        error.SocketNotConnected => IoError.BrokenPipe,
        error.Canceled => IoError.Cancelled,
    };
}

fn mapWriteError(err: anytype) IoError {
    return switch (err) {
        error.AccessDenied => IoError.PermissionDenied,
        error.BrokenPipe => IoError.BrokenPipe,
        error.DeviceBusy => IoError.Unknown,
        error.DiskQuota => IoError.OutOfMemory,
        error.FileTooBig => IoError.OutOfMemory,
        error.InputOutput => IoError.Unknown,
        error.InvalidArgument => IoError.InvalidArgument,
        error.LockViolation => IoError.PermissionDenied,
        error.NoSpaceLeft => IoError.OutOfMemory,
        error.NotOpenForWriting => IoError.PermissionDenied,
        error.OperationAborted => IoError.Interrupted,
        error.SystemResources => IoError.OutOfMemory,
        error.Unexpected => IoError.Unknown,
        error.WouldBlock => IoError.Unknown,
        error.NoDevice => IoError.Unknown,
        error.ConnectionResetByPeer => IoError.BrokenPipe,
        error.ProcessNotFound => IoError.Unknown,
        else => IoError.Unknown,
    };
}

// ===== TESTING UTILITIES =====

/// Test utilities for validating I/O operations
pub const testing = struct {
    pub fn createTestFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
        const capability = FileWriteCapability{ .path = path };
        const buffer = WriteBuffer{ .data = content };
        try writeFile(path, buffer, capability);
        _ = allocator;
    }

    pub fn deleteTestFile(path: []const u8) void {
        compat_fs.deleteFile(path) catch {};
    }

    pub fn readTestFile(allocator: std.mem.Allocator, path: []const u8) !ReadBuffer {
        const capability = FileReadCapability{ .path = path };
        return readFile(allocator, path, capability);
    }
};

// ===== TESTS =====

test "file operations with capabilities" {
    const testing_allocator = std.testing.allocator;
    const test_path = "test_file.txt";
    const test_content = "Hello, Janus Standard Library!";

    // Clean up any existing test file
    testing.deleteTestFile(test_path);
    defer testing.deleteTestFile(test_path);

    // Test file writing
    try testing.createTestFile(testing_allocator, test_path, test_content);

    // Test file reading
    const read_buffer = try testing.readTestFile(testing_allocator, test_path);
    defer read_buffer.deinit();

    try std.testing.expectEqualStrings(test_content, read_buffer.data);
}

test "capability validation" {
    const valid_read_cap = FileReadCapability{ .path = "test.txt" };
    const valid_write_cap = FileWriteCapability{ .path = "test.txt" };
    const valid_stdout_cap = StdoutWriteCapability{};

    try std.testing.expect(valid_read_cap.validate());
    try std.testing.expect(valid_write_cap.validate());
    try std.testing.expect(valid_stdout_cap.validate());
}

test "error handling" {
    const testing_allocator = std.testing.allocator;
    const nonexistent_path = "this_file_does_not_exist.txt";

    const capability = FileReadCapability{ .path = nonexistent_path };
    const result = readFile(testing_allocator, nonexistent_path, capability);

    try std.testing.expectError(IoError.FileNotFound, result);
}

test "buffer lifecycle management" {
    const testing_allocator = std.testing.allocator;
    const test_path = "test_buffer_lifecycle.txt";
    const test_content = "Buffer lifecycle test";

    testing.deleteTestFile(test_path);
    defer testing.deleteTestFile(test_path);

    // Create test file
    try testing.createTestFile(testing_allocator, test_path, test_content);

    // Read file and verify buffer management
    const read_buffer = try testing.readTestFile(testing_allocator, test_path);
    try std.testing.expectEqualStrings(test_content, read_buffer.data);

    // Verify allocator is set correctly
    try std.testing.expect(read_buffer.allocator != null);

    // Clean up - this should not leak memory
    read_buffer.deinit();
}

// =============================================================================
// TRI-SIGNATURE PATTERN TESTS
// =============================================================================

test ":core profile - simple read/write" {
    const allocator = std.testing.allocator;
    const test_path = "test_core_profile.txt";
    const test_content = "Hello from :core profile!";

    defer testing.deleteTestFile(test_path);

    // Write using :core API
    try core.writeFile(test_path, test_content);

    // Read using :core API
    const buffer = try core.readFile(test_path, allocator);
    defer buffer.deinit();

    try std.testing.expectEqualStrings(test_content, buffer.data);
}

test ":service profile - context-aware operations" {
    const allocator = std.testing.allocator;
    const test_path = "test_service_profile.txt";
    const test_content = "Hello from :service profile!";

    defer testing.deleteTestFile(test_path);

    // Setup context
    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    // Write using :service API (uses context allocator implicitly)
    try service.writeFile(test_path, test_content, &ctx);

    // Read using :service API
    const buffer = try service.readFile(test_path, &ctx);
    defer buffer.deinit();

    try std.testing.expectEqualStrings(test_content, buffer.data);
}

test ":service profile - cancellation" {
    const allocator = std.testing.allocator;

    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    // Cancel the context
    ctx.cancel();

    // Operations should fail with Cancelled error
    const result = service.readFile("any_file.txt", &ctx);
    try std.testing.expectError(IoError.Cancelled, result);
}

test ":sovereign profile - capability enforcement" {
    const allocator = std.testing.allocator;
    const test_path = "test_sovereign_profile.txt";
    const test_content = "Hello from :sovereign profile!";

    defer testing.deleteTestFile(test_path);

    // Setup context with filesystem capabilities
    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();
    caps.grantFsRead();
    caps.grantFsWrite();

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    // Create capability tokens
    const write_cap = sovereign.CapFsWrite{};
    const read_cap = sovereign.CapFsRead{};

    // Write using :sovereign API
    try sovereign.writeFile(test_path, test_content, write_cap, &ctx);

    // Read using :sovereign API
    const buffer = try sovereign.readFile(test_path, read_cap, &ctx);
    defer buffer.deinit();

    try std.testing.expectEqualStrings(test_content, buffer.data);
}

test ":sovereign profile - capability denied" {
    const allocator = std.testing.allocator;

    // Setup context WITHOUT filesystem capabilities
    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();
    // Note: NOT granting caps.grantFsRead()

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    const read_cap = sovereign.CapFsRead{};

    // Read should fail - context lacks fs_read capability
    const result = sovereign.readFile("any_file.txt", read_cap, &ctx);
    try std.testing.expectError(IoError.PermissionDenied, result);
}

test ":sovereign profile - path restriction" {
    const allocator = std.testing.allocator;

    // Setup context with path restrictions
    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();
    caps.grantFsRead();
    try caps.allowPath("/allowed/");

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    const read_cap = sovereign.CapFsRead{};

    // Read from non-allowed path should fail
    const result = sovereign.readFile("/etc/passwd", read_cap, &ctx);
    try std.testing.expectError(IoError.PermissionDenied, result);
}

test ":sovereign profile - capability token path validation" {
    const allocator = std.testing.allocator;

    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();
    caps.grantFsRead();

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    // Create capability token that only allows /safe/ paths
    const read_cap = sovereign.CapFsRead.forPath("/safe/");

    // Validate token directly
    try std.testing.expect(read_cap.validate("/safe/file.txt"));
    try std.testing.expect(!read_cap.validate("/unsafe/file.txt"));
}
