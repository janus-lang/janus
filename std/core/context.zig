// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Context System - Core Definition
// Purpose: Unified dependency injection for explicit resource management
// Doctrine: Syntactic Honesty - All dependencies are visible
//
// Profile Applicability:
// - :core      - Uses allocator directly (no context)
// - :service   - Uses Context for deadline/cancellation
// - :sovereign - Uses Context + explicit Capability tokens

const std = @import("std");

/// Logger interface for structured logging
pub const Logger = struct {
    allocator: std.mem.Allocator,
    level: LogLevel,

    pub const LogLevel = enum {
        trace,
        debug,
        info,
        warn,
        err,
        fatal,
    };

    pub fn init(allocator: std.mem.Allocator) Logger {
        return Logger{
            .allocator = allocator,
            .level = .info,
        };
    }

    pub fn log(self: *Logger, level: LogLevel, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;

        const level_str = switch (level) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };

        std.debug.print("[{s}] " ++ fmt ++ "\n", .{level_str} ++ args);
    }

    pub fn trace(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.trace, fmt, args);
    }

    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.debug, fmt, args);
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.info, fmt, args);
    }

    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.warn, fmt, args);
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.err, fmt, args);
    }

    pub fn fatal(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.fatal, fmt, args);
    }
};

/// Capability tokens for :sovereign profile
/// These are unforgeable tokens that grant specific permissions
pub const CapabilitySet = struct {
    allocator: std.mem.Allocator,

    // Core capabilities
    fs_read: bool = false,
    fs_write: bool = false,
    net_connect: bool = false,
    net_listen: bool = false,
    sys_exec: bool = false,
    accelerator_use: bool = false,
    stdout_write: bool = false,
    stderr_write: bool = false,

    // Paths allowed for filesystem operations
    allowed_paths: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) CapabilitySet {
        return CapabilitySet{
            .allocator = allocator,
            .allowed_paths = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *CapabilitySet) void {
        for (self.allowed_paths.items) |path| {
            self.allocator.free(path);
        }
        self.allowed_paths.deinit(self.allocator);
    }

    /// Grant filesystem read capability
    pub fn grantFsRead(self: *CapabilitySet) void {
        self.fs_read = true;
    }

    /// Grant filesystem write capability
    pub fn grantFsWrite(self: *CapabilitySet) void {
        self.fs_write = true;
    }

    /// Grant network connect capability
    pub fn grantNetConnect(self: *CapabilitySet) void {
        self.net_connect = true;
    }

    /// Grant accelerator usage capability
    pub fn grantAccelerator(self: *CapabilitySet) void {
        self.accelerator_use = true;
    }

    /// Grant stdout write capability
    pub fn grantStdoutWrite(self: *CapabilitySet) void {
        self.stdout_write = true;
    }

    /// Grant stderr write capability
    pub fn grantStderrWrite(self: *CapabilitySet) void {
        self.stderr_write = true;
    }

    /// Add allowed path for filesystem operations
    pub fn allowPath(self: *CapabilitySet, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.allowed_paths.append(self.allocator, owned_path);
    }

    /// Check if a path is allowed
    pub fn isPathAllowed(self: *const CapabilitySet, path: []const u8) bool {
        if (self.allowed_paths.items.len == 0) return true; // No restrictions

        for (self.allowed_paths.items) |allowed| {
            if (std.mem.startsWith(u8, path, allowed)) return true;
        }
        return false;
    }
};

/// The unified Janus Context
/// Doctrine: Carries all implicit dependencies explicitly
///
/// Profile Usage:
/// - :core      - Not used (functions take allocator directly)
/// - :service   - Passed for deadline/cancellation/values
/// - :sovereign - Passed with explicit capability checks
pub const Context = struct {
    /// Memory allocator - required for all allocating operations
    allocator: std.mem.Allocator,

    /// Structured logger - optional, uses stderr if null
    logger: ?*Logger,

    /// Capability tokens - controls what operations are allowed
    capabilities: *CapabilitySet,

    /// Deadline for cancellation (Unix timestamp in milliseconds)
    deadline: ?i64,

    /// Request-scoped values (trace IDs, user context, etc.)
    values: std.StringHashMap([]const u8),

    /// Is this context cancelled?
    cancelled: bool,

    const Self = @This();

    /// Create a new root context
    /// This is the entry point for :service and :sovereign profiles
    pub fn init(allocator: std.mem.Allocator, capabilities: *CapabilitySet) Context {
        return Context{
            .allocator = allocator,
            .logger = null,
            .capabilities = capabilities,
            .deadline = null,
            .values = std.StringHashMap([]const u8).init(allocator),
            .cancelled = false,
        };
    }

    /// Create context with logger
    pub fn withLogger(self: Context, logger: *Logger) Context {
        var new_ctx = self;
        new_ctx.logger = logger;
        return new_ctx;
    }

    /// Create context with deadline (for timeouts)
    pub fn withDeadline(self: Context, deadline_ms: i64) Context {
        var new_ctx = self;
        new_ctx.deadline = deadline_ms;
        return new_ctx;
    }

    /// Create context with timeout (relative to now)
    pub fn withTimeout(self: Context, timeout_ms: u32) Context {
        const now = std.time.milliTimestamp();
        return self.withDeadline(now + timeout_ms);
    }

    /// Add a value to context (creates shallow copy)
    pub fn withValue(self: Context, key: []const u8, value: []const u8) !Context {
        var new_ctx = self;
        new_ctx.values = std.StringHashMap([]const u8).init(self.allocator);

        // Copy existing values
        var iter = self.values.iterator();
        while (iter.next()) |entry| {
            try new_ctx.values.put(
                try self.allocator.dupe(u8, entry.key_ptr.*),
                try self.allocator.dupe(u8, entry.value_ptr.*),
            );
        }

        // Add new value
        try new_ctx.values.put(
            try self.allocator.dupe(u8, key),
            try self.allocator.dupe(u8, value),
        );

        return new_ctx;
    }

    /// Get value from context
    pub fn getValue(self: *const Context, key: []const u8) ?[]const u8 {
        return self.values.get(key);
    }

    /// Check if context is cancelled
    pub fn isCancelled(self: *const Context) bool {
        return self.cancelled;
    }

    /// Check if deadline has been exceeded
    pub fn isDeadlineExceeded(self: *const Context) bool {
        if (self.deadline) |deadline| {
            return std.time.milliTimestamp() > deadline;
        }
        return false;
    }

    /// Check if context is done (cancelled or deadline exceeded)
    pub fn isDone(self: *const Context) bool {
        return self.isCancelled() or self.isDeadlineExceeded();
    }

    /// Cancel this context
    pub fn cancel(self: *Context) void {
        self.cancelled = true;
    }

    /// Check filesystem read capability
    pub fn canReadFs(self: *const Context) bool {
        return self.capabilities.fs_read;
    }

    /// Check filesystem write capability
    pub fn canWriteFs(self: *const Context) bool {
        return self.capabilities.fs_write;
    }

    /// Check stdout write capability
    pub fn canWriteStdout(self: *const Context) bool {
        return self.capabilities.stdout_write;
    }

    /// Check stderr write capability
    pub fn canWriteStderr(self: *const Context) bool {
        return self.capabilities.stderr_write;
    }

    /// Check if path is allowed for filesystem operations
    pub fn isPathAllowed(self: *const Context, path: []const u8) bool {
        return self.capabilities.isPathAllowed(path);
    }

    /// Log at info level (convenience)
    pub fn logInfo(self: *const Context, comptime fmt: []const u8, args: anytype) void {
        if (self.logger) |logger| {
            var log = logger;
            log.info(fmt, args);
        }
    }

    /// Clean up context resources
    pub fn deinit(self: *Context) void {
        var iter = self.values.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.values.deinit();
    }
};

/// Context errors
pub const ContextError = error{
    Cancelled,
    DeadlineExceeded,
    CapabilityDenied,
    ValueNotFound,
};

/// Create a background context (for long-running operations)
pub fn background(allocator: std.mem.Allocator, capabilities: *CapabilitySet) Context {
    return Context.init(allocator, capabilities);
}

/// Create a TODO context (placeholder during development)
pub fn todo(allocator: std.mem.Allocator, capabilities: *CapabilitySet) Context {
    return Context.init(allocator, capabilities);
}

// =============================================================================
// Tests
// =============================================================================

test "Context: Basic initialization" {
    const allocator = std.testing.allocator;

    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    try std.testing.expect(!ctx.isCancelled());
    try std.testing.expect(!ctx.isDeadlineExceeded());
    try std.testing.expect(!ctx.isDone());
}

test "Context: Cancellation" {
    const allocator = std.testing.allocator;

    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    try std.testing.expect(!ctx.isCancelled());

    ctx.cancel();

    try std.testing.expect(ctx.isCancelled());
    try std.testing.expect(ctx.isDone());
}

test "Context: Deadline" {
    const allocator = std.testing.allocator;

    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    // Set deadline in the past
    const past_deadline = std.time.milliTimestamp() - 1000;
    var ctx_with_deadline = ctx.withDeadline(past_deadline);

    try std.testing.expect(ctx_with_deadline.isDeadlineExceeded());
    try std.testing.expect(ctx_with_deadline.isDone());
}

test "Context: Capability checks" {
    const allocator = std.testing.allocator;

    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();

    // Initially no capabilities
    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    try std.testing.expect(!ctx.canReadFs());
    try std.testing.expect(!ctx.canWriteFs());

    // Grant capabilities
    caps.grantFsRead();
    caps.grantFsWrite();

    try std.testing.expect(ctx.canReadFs());
    try std.testing.expect(ctx.canWriteFs());
}

test "Context: Path restrictions" {
    const allocator = std.testing.allocator;

    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();

    try caps.allowPath("/home/user/safe/");

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    try std.testing.expect(ctx.isPathAllowed("/home/user/safe/file.txt"));
    try std.testing.expect(!ctx.isPathAllowed("/etc/passwd"));
}

test "Context: Values" {
    const allocator = std.testing.allocator;

    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();

    var ctx = Context.init(allocator, &caps);
    defer ctx.deinit();

    var ctx_with_value = try ctx.withValue("trace_id", "abc123");
    defer ctx_with_value.deinit();

    const value = ctx_with_value.getValue("trace_id");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("abc123", value.?);
}

test "CapabilitySet: Basic operations" {
    const allocator = std.testing.allocator;

    var caps = CapabilitySet.init(allocator);
    defer caps.deinit();

    try std.testing.expect(!caps.fs_read);

    caps.grantFsRead();
    caps.grantAccelerator();

    try std.testing.expect(caps.fs_read);
    try std.testing.expect(caps.accelerator_use);
    try std.testing.expect(!caps.net_connect);

    // Test stdout/stderr capabilities
    try std.testing.expect(!caps.stdout_write);
    try std.testing.expect(!caps.stderr_write);
    caps.grantStdoutWrite();
    caps.grantStderrWrite();
    try std.testing.expect(caps.stdout_write);
    try std.testing.expect(caps.stderr_write);
}

test "Logger: Basic logging" {
    const allocator = std.testing.allocator;

    var logger = Logger.init(allocator);

    // Just verify it doesn't crash - output goes to stderr
    logger.info("Test message: {d}", .{42});
    logger.debug("Debug message", .{});
}
