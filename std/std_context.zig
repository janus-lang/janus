// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - Context Module
// Available in :go+ profiles for structured concurrency and cancellation

const std = @import("std");

/// Context provides deadline, cancellation, and value propagation
/// Inspired by Go's context.Context but with Janus's explicit semantics
pub const Context = struct {
    deadline: ?i64, // Unix timestamp in milliseconds
    cancelled: bool,
    values: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Create a new root context
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .deadline = null,
            .cancelled = false,
            .values = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    /// Create a context with deadline
    pub fn with_deadline(parent: Self, deadline_ms: i64, allocator: std.mem.Allocator) Self {
        var ctx = Self{
            .deadline = deadline_ms,
            .cancelled = parent.cancelled,
            .values = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };

        // Copy parent values
        var iter = parent.values.iterator();
        while (iter.next()) |entry| {
            ctx.values.put(allocator.dupe(u8, entry.key_ptr.*) catch unreachable, allocator.dupe(u8, entry.value_ptr.*) catch unreachable) catch unreachable;
        }

        return ctx;
    }

    /// Create a context with timeout (relative to now)
    pub fn with_timeout(parent: Self, timeout_ms: u32, allocator: std.mem.Allocator) Self {
        const now = std.time.milliTimestamp();
        return with_deadline(parent, now + timeout_ms, allocator);
    }

    /// Create a cancellable context
    pub fn with_cancel(parent: Self, allocator: std.mem.Allocator) Self {
        return Self{
            .deadline = parent.deadline,
            .cancelled = false, // Start uncancelled, can be cancelled later
            .values = parent.values, // Share values (shallow copy for demo)
            .allocator = allocator,
        };
    }

    /// Check if context is cancelled
    pub fn is_cancelled(self: Self) bool {
        return self.cancelled;
    }

    /// Check if context has exceeded deadline
    pub fn is_deadline_exceeded(self: Self) bool {
        if (self.deadline) |deadline| {
            const now = std.time.milliTimestamp();
            return now > deadline;
        }
        return false;
    }

    /// Check if context is done (cancelled or deadline exceeded)
    pub fn is_done(self: Self) bool {
        return self.is_cancelled() or self.is_deadline_exceeded();
    }

    /// Cancel the context
    pub fn cancel(self: *Self) void {
        self.cancelled = true;
    }

    /// Get value from context
    pub fn get_value(self: Self, key: []const u8) ?[]const u8 {
        return self.values.get(key);
    }

    /// Set value in context (creates new context)
    pub fn with_value(self: Self, key: []const u8, value: []const u8, allocator: std.mem.Allocator) !Self {
        var new_ctx = Self{
            .deadline = self.deadline,
            .cancelled = self.cancelled,
            .values = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };

        // Copy existing values
        var iter = self.values.iterator();
        while (iter.next()) |entry| {
            try new_ctx.values.put(try allocator.dupe(u8, entry.key_ptr.*), try allocator.dupe(u8, entry.value_ptr.*));
        }

        // Add new value
        try new_ctx.values.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));

        return new_ctx;
    }

    /// Get remaining time until deadline
    pub fn deadline_remaining_ms(self: Self) ?i64 {
        if (self.deadline) |deadline| {
            const now = std.time.milliTimestamp();
            const remaining = deadline - now;
            return if (remaining > 0) remaining else 0;
        }
        return null;
    }

    /// Clean up context resources
    pub fn deinit(self: *Self) void {
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
    ValueNotFound,
};

/// Convenience functions for common context operations
/// Create a background context (never cancelled, no deadline)
pub fn background(allocator: std.mem.Allocator) Context {
    return Context.init(allocator);
}

/// Create a TODO context (placeholder for development)
pub fn todo(allocator: std.mem.Allocator) Context {
    return Context.init(allocator);
}

/// Sleep with context cancellation support
pub fn sleep_with_context(ctx: Context, duration_ms: u32) ContextError!void {
    const start = std.time.milliTimestamp();
    const end = start + duration_ms;

    while (std.time.milliTimestamp() < end) {
        if (ctx.is_done()) {
            if (ctx.is_cancelled()) return ContextError.Cancelled;
            if (ctx.is_deadline_exceeded()) return ContextError.DeadlineExceeded;
        }

        // Sleep for a short interval and check again
        std.time.sleep(1_000_000); // 1ms
    }
}

// Tests
test "context creation and cancellation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test basic context
    var ctx = Context.init(allocator);
    defer ctx.deinit();

    try testing.expect(!ctx.is_cancelled());
    try testing.expect(!ctx.is_deadline_exceeded());
    try testing.expect(!ctx.is_done());

    // Test cancellation
    ctx.cancel();
    try testing.expect(ctx.is_cancelled());
    try testing.expect(ctx.is_done());
}

test "context with deadline" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parent = Context.init(allocator);
    defer parent.deinit();

    // Create context with deadline in the past
    const past_deadline = std.time.milliTimestamp() - 1000;
    var ctx = Context.with_deadline(parent, past_deadline, allocator);
    defer ctx.deinit();

    try testing.expect(ctx.is_deadline_exceeded());
    try testing.expect(ctx.is_done());
}

test "context with timeout" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parent = Context.init(allocator);
    defer parent.deinit();

    // Create context with 100ms timeout
    var ctx = Context.with_timeout(parent, 100, allocator);
    defer ctx.deinit();

    try testing.expect(!ctx.is_deadline_exceeded());

    // Check that deadline is set correctly
    const remaining = ctx.deadline_remaining_ms();
    try testing.expect(remaining != null);
    try testing.expect(remaining.? <= 100);
}

test "context values" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    // Add value to context
    var ctx_with_value = try ctx.with_value("user_id", "12345", allocator);
    defer ctx_with_value.deinit();

    // Retrieve value
    const value = ctx_with_value.get_value("user_id");
    try testing.expect(value != null);
    try testing.expectEqualStrings("12345", value.?);

    // Non-existent value
    const missing = ctx_with_value.get_value("missing");
    try testing.expect(missing == null);
}
