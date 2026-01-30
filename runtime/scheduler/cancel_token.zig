// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Cancellation Tokens for Cooperative Cancellation
//!
//! CancelToken provides thread-safe, cooperative cancellation for async tasks.
//! Tasks must voluntarily check for cancellation - this is not preemptive.
//!
//! Design principles:
//! - Cancellation is cooperative (tasks must check)
//! - Cancel operations are idempotent and thread-safe
//! - Child tokens inherit cancellation from parents
//! - Callbacks enable reactive cancellation handling
//!
//! See: SPEC-019 Section 3.6 (Cancellation Tokens)

const std = @import("std");
const Atomic = std.atomic.Value;

// ============================================================================
// Cancellation Error
// ============================================================================

/// Error returned when a cancelled token is checked
pub const CancellationError = error{
    /// Normal cancellation requested
    Cancelled,
    /// Timeout-triggered cancellation
    Timeout,
    /// Parent nursery was cancelled
    ParentCancelled,
};

// ============================================================================
// Cancellation Reason
// ============================================================================

/// Reason for cancellation (stored in token)
pub const CancelReason = enum(u8) {
    /// Not cancelled
    None = 0,
    /// Explicit cancel() call
    Explicit = 1,
    /// Timeout expired
    Timeout = 2,
    /// Parent token was cancelled
    Parent = 3,
    /// Task/nursery failure triggered cancellation
    Failure = 4,
};

// ============================================================================
// Cancel Callback
// ============================================================================

/// Callback invoked when cancellation occurs
pub const CancelCallback = struct {
    /// User-provided context
    context: ?*anyopaque,
    /// Callback function
    callback_fn: *const fn (context: ?*anyopaque) void,

    /// Invoke the callback
    pub fn invoke(self: CancelCallback) void {
        self.callback_fn(self.context);
    }
};

// ============================================================================
// Cancel Token
// ============================================================================

/// Thread-safe cancellation token for cooperative task cancellation
///
/// Usage:
/// ```
/// let token = CancelToken.init(allocator);
/// defer token.deinit();
///
/// // In worker task:
/// while (!token.is_cancelled()) {
///     do_work();
///     token.check() catch return; // Or handle cancellation
/// }
///
/// // To request cancellation:
/// token.cancel();
/// ```
pub const CancelToken = struct {
    const Self = @This();

    /// Maximum number of callbacks per token
    const MAX_CALLBACKS = 8;

    /// Cancellation state (atomic for thread safety)
    cancelled: Atomic(bool),

    /// Reason for cancellation
    reason: Atomic(CancelReason),

    /// Parent token (if this is a child)
    parent: ?*Self,

    /// Registered callbacks (called on cancellation)
    callbacks: [MAX_CALLBACKS]?CancelCallback,
    callback_count: Atomic(usize),

    /// Allocator used for child tokens
    allocator: std.mem.Allocator,

    /// Reference count for shared ownership
    ref_count: Atomic(usize),

    // ------------------------------------------------------------------------
    // Initialization
    // ------------------------------------------------------------------------

    /// Create a new independent cancellation token
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .cancelled = Atomic(bool).init(false),
            .reason = Atomic(CancelReason).init(.None),
            .parent = null,
            .callbacks = [_]?CancelCallback{null} ** MAX_CALLBACKS,
            .callback_count = Atomic(usize).init(0),
            .allocator = allocator,
            .ref_count = Atomic(usize).init(1),
        };
    }

    /// Create a child token linked to a parent
    /// Child is automatically cancelled when parent is cancelled
    pub fn initChild(allocator: std.mem.Allocator, parent: *Self) !*Self {
        const child = try allocator.create(Self);
        child.* = Self{
            .cancelled = Atomic(bool).init(parent.is_cancelled()),
            .reason = Atomic(CancelReason).init(if (parent.is_cancelled()) .Parent else .None),
            .parent = parent,
            .callbacks = [_]?CancelCallback{null} ** MAX_CALLBACKS,
            .callback_count = Atomic(usize).init(0),
            .allocator = allocator,
            .ref_count = Atomic(usize).init(1),
        };

        // Register with parent for propagation
        parent.onCancel(.{
            .context = child,
            .callback_fn = childCancelCallback,
        }) catch {
            // Parent already cancelled - child starts cancelled
            child.cancelled.store(true, .release);
            child.reason.store(.Parent, .release);
        };

        // Increment parent ref count
        _ = parent.ref_count.fetchAdd(1, .monotonic);

        return child;
    }

    /// Callback for parent->child cancellation propagation
    fn childCancelCallback(context: ?*anyopaque) void {
        if (context) |ctx| {
            const child: *Self = @ptrCast(@alignCast(ctx));
            child.cancelWithReason(.Parent);
        }
    }

    /// Deinitialize the token
    pub fn deinit(self: *Self) void {
        const count = self.ref_count.fetchSub(1, .acq_rel);
        if (count == 1) {
            // Last reference - clean up
            if (self.parent) |parent| {
                _ = parent.ref_count.fetchSub(1, .acq_rel);
            }
            // If this was heap-allocated as a child, free it
            // Note: Root tokens are typically stack-allocated
        }
    }

    // ------------------------------------------------------------------------
    // Cancellation State
    // ------------------------------------------------------------------------

    /// Check if cancellation has been requested
    /// This is a non-throwing check - use for loop conditions
    pub fn is_cancelled(self: *const Self) bool {
        // Check self first, then parent chain
        if (self.cancelled.load(.acquire)) return true;
        if (self.parent) |parent| {
            if (parent.is_cancelled()) {
                // Propagate cancellation lazily
                @constCast(self).cancelled.store(true, .release);
                @constCast(self).reason.store(.Parent, .release);
                return true;
            }
        }
        return false;
    }

    /// Check for cancellation and throw if cancelled
    /// Use this at yield points in long-running tasks
    pub fn check(self: *const Self) CancellationError!void {
        if (self.is_cancelled()) {
            return switch (self.reason.load(.acquire)) {
                .None => CancellationError.Cancelled,
                .Explicit => CancellationError.Cancelled,
                .Timeout => CancellationError.Timeout,
                .Parent => CancellationError.ParentCancelled,
                .Failure => CancellationError.Cancelled,
            };
        }
    }

    /// Get the cancellation reason
    pub fn getReason(self: *const Self) CancelReason {
        return self.reason.load(.acquire);
    }

    // ------------------------------------------------------------------------
    // Cancellation Request
    // ------------------------------------------------------------------------

    /// Request cancellation (idempotent, thread-safe)
    /// This sets the cancelled flag and invokes all registered callbacks
    pub fn cancel(self: *Self) void {
        self.cancelWithReason(.Explicit);
    }

    /// Cancel with a specific reason
    pub fn cancelWithReason(self: *Self, reason: CancelReason) void {
        // Atomic compare-exchange to ensure single cancellation
        const was_cancelled = self.cancelled.cmpxchgStrong(
            false,
            true,
            .acq_rel,
            .acquire,
        );

        if (was_cancelled == null) {
            // We performed the cancellation - set reason and invoke callbacks
            self.reason.store(reason, .release);
            self.invokeCallbacks();
        }
        // If was_cancelled != null, already cancelled - idempotent
    }

    /// Cancel due to timeout
    pub fn cancelTimeout(self: *Self) void {
        self.cancelWithReason(.Timeout);
    }

    /// Cancel due to failure
    pub fn cancelFailure(self: *Self) void {
        self.cancelWithReason(.Failure);
    }

    // ------------------------------------------------------------------------
    // Callbacks
    // ------------------------------------------------------------------------

    /// Register a callback to be invoked on cancellation
    /// If already cancelled, callback is invoked immediately
    pub fn onCancel(self: *Self, callback: CancelCallback) !void {
        // Check if already cancelled
        if (self.is_cancelled()) {
            callback.invoke();
            return;
        }

        // Try to register callback
        const idx = self.callback_count.fetchAdd(1, .acq_rel);
        if (idx >= MAX_CALLBACKS) {
            _ = self.callback_count.fetchSub(1, .acq_rel);
            return error.TooManyCallbacks;
        }

        self.callbacks[idx] = callback;

        // Double-check: may have been cancelled while registering
        if (self.is_cancelled()) {
            callback.invoke();
        }
    }

    /// Invoke all registered callbacks
    fn invokeCallbacks(self: *Self) void {
        const count = self.callback_count.load(.acquire);
        for (self.callbacks[0..count]) |maybe_cb| {
            if (maybe_cb) |cb| {
                cb.invoke();
            }
        }
    }

    // ------------------------------------------------------------------------
    // Utility
    // ------------------------------------------------------------------------

    /// Create a token that cancels after a timeout
    /// Returns null if allocation fails
    pub fn withTimeout(allocator: std.mem.Allocator, timeout_ns: u64) !*Self {
        const token = try allocator.create(Self);
        token.* = Self.init(allocator);

        // Spawn timeout task (simplified - in real impl would use scheduler)
        // For now, this is a placeholder - actual timeout requires scheduler integration
        _ = timeout_ns; // TODO: Integrate with scheduler for actual timeout

        return token;
    }
};

// ============================================================================
// Combined Token (for multiple cancellation sources)
// ============================================================================

/// A token that is cancelled when ANY of its sources is cancelled
pub const CombinedToken = struct {
    const Self = @This();

    /// The combined token
    token: CancelToken,

    /// Source tokens (up to 4)
    sources: [4]?*CancelToken,
    source_count: usize,

    /// Create a combined token from multiple sources
    pub fn init(allocator: std.mem.Allocator, sources: []const *CancelToken) !Self {
        var self = Self{
            .token = CancelToken.init(allocator),
            .sources = [_]?*CancelToken{null} ** 4,
            .source_count = @min(sources.len, 4),
        };

        // Register with each source
        for (sources[0..self.source_count], 0..) |source, i| {
            self.sources[i] = source;

            // Check if already cancelled
            if (source.is_cancelled()) {
                self.token.cancel();
                return self;
            }

            // Register callback
            try source.onCancel(.{
                .context = &self.token,
                .callback_fn = struct {
                    fn cb(ctx: ?*anyopaque) void {
                        if (ctx) |c| {
                            const t: *CancelToken = @ptrCast(@alignCast(c));
                            t.cancel();
                        }
                    }
                }.cb,
            });
        }

        return self;
    }

    /// Get the combined token for checking
    pub fn getToken(self: *Self) *CancelToken {
        return &self.token;
    }

    pub fn deinit(self: *Self) void {
        self.token.deinit();
    }
};

// ============================================================================
// C ABI Exports (for runtime integration)
// ============================================================================

/// Create a new cancellation token
export fn janus_cancel_token_create() callconv(.c) ?*CancelToken {
    const allocator = std.heap.page_allocator;
    const token = allocator.create(CancelToken) catch return null;
    token.* = CancelToken.init(allocator);
    return token;
}

/// Create a child token linked to parent
export fn janus_cancel_token_child(parent: ?*CancelToken) callconv(.c) ?*CancelToken {
    const p = parent orelse return null;
    return CancelToken.initChild(std.heap.page_allocator, p) catch null;
}

/// Check if token is cancelled (non-throwing)
export fn janus_cancel_token_is_cancelled(token: ?*const CancelToken) callconv(.c) bool {
    const t = token orelse return true; // Null token = cancelled
    return t.is_cancelled();
}

/// Request cancellation
export fn janus_cancel_token_cancel(token: ?*CancelToken) callconv(.c) void {
    if (token) |t| {
        t.cancel();
    }
}

/// Destroy a cancellation token
export fn janus_cancel_token_destroy(token: ?*CancelToken) callconv(.c) void {
    if (token) |t| {
        t.deinit();
        std.heap.page_allocator.destroy(t);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "CancelToken: basic cancellation" {
    var token = CancelToken.init(std.testing.allocator);
    defer token.deinit();

    try std.testing.expect(!token.is_cancelled());
    try token.check(); // Should not error

    token.cancel();

    try std.testing.expect(token.is_cancelled());
    try std.testing.expectEqual(CancelReason.Explicit, token.getReason());
    try std.testing.expectError(CancellationError.Cancelled, token.check());
}

test "CancelToken: idempotent cancellation" {
    var token = CancelToken.init(std.testing.allocator);
    defer token.deinit();

    token.cancel();
    token.cancel(); // Second call should be no-op
    token.cancel(); // Third call should be no-op

    try std.testing.expect(token.is_cancelled());
}

test "CancelToken: parent-child propagation" {
    var parent = CancelToken.init(std.testing.allocator);
    defer parent.deinit();

    const child = try CancelToken.initChild(std.testing.allocator, &parent);
    defer child.deinit();

    try std.testing.expect(!parent.is_cancelled());
    try std.testing.expect(!child.is_cancelled());

    parent.cancel();

    try std.testing.expect(parent.is_cancelled());
    try std.testing.expect(child.is_cancelled());
    try std.testing.expectEqual(CancelReason.Parent, child.getReason());
}

test "CancelToken: callback invocation" {
    var token = CancelToken.init(std.testing.allocator);
    defer token.deinit();

    var callback_called = false;
    try token.onCancel(.{
        .context = &callback_called,
        .callback_fn = struct {
            fn cb(ctx: ?*anyopaque) void {
                if (ctx) |c| {
                    const flag: *bool = @ptrCast(@alignCast(c));
                    flag.* = true;
                }
            }
        }.cb,
    });

    try std.testing.expect(!callback_called);

    token.cancel();

    try std.testing.expect(callback_called);
}

test "CancelToken: timeout reason" {
    var token = CancelToken.init(std.testing.allocator);
    defer token.deinit();

    token.cancelTimeout();

    try std.testing.expect(token.is_cancelled());
    try std.testing.expectEqual(CancelReason.Timeout, token.getReason());
    try std.testing.expectError(CancellationError.Timeout, token.check());
}

test "CancelToken: already cancelled parent" {
    var parent = CancelToken.init(std.testing.allocator);
    defer parent.deinit();

    parent.cancel();

    const child = try CancelToken.initChild(std.testing.allocator, &parent);
    defer child.deinit();

    // Child should start cancelled
    try std.testing.expect(child.is_cancelled());
}
