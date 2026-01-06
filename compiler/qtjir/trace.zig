// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Observability: Scope Tokens for Lowering Traceability

const std = @import("std");

/// Enable trace logging - configurable via build option: -Dtrace-qtjir=true
/// This follows "Mechanism over Policy" - the user decides when to enable tracing
/// For standalone test modules (without compiler_options), defaults to false
pub const enable_trace = blk: {
    // Try to import compiler_options, fall back to false if not available
    const has_options = @import("builtin").is_test == false;
    if (has_options) {
        const compiler_options = @import("compiler_options");
        break :blk compiler_options.trace_qtjir;
    } else {
        break :blk false;
    }
};

/// Scope token for tracing lowering operations
pub const ScopeToken = struct {
    operation: []const u8,
    context: []const u8,
    start_time: i64,

    pub fn init(operation: []const u8, context: []const u8) ScopeToken {
        return .{
            .operation = operation,
            .context = context,
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn end(self: *const ScopeToken) void {
        if (enable_trace) {
            const duration = std.time.milliTimestamp() - self.start_time;
            std.debug.print("[TRACE] {s} {s} completed in {d}ms\n", .{
                self.operation,
                self.context,
                duration,
            });
        }
    }
};

/// Macro for creating scope tokens (use defer for automatic cleanup)
pub fn trace(operation: []const u8, context: []const u8) ScopeToken {
    if (enable_trace) {
        const token = ScopeToken.init(operation, context);
        std.debug.print("[TRACE] {s} {s} started\n", .{ operation, context });
        return token;
    } else {
        return .{ .operation = "", .context = "", .start_time = 0 };
    }
}

/// Error tracking with scope
pub fn traceError(
    scope: []const u8,
    err: anyerror,
    context: []const u8,
) void {
    if (enable_trace) {
        std.debug.print("[ERROR] {s}: {s} in {s}\n", .{
            scope,
            @errorName(err),
            context,
        });
    }
}

/// Debug helper for dumping current state
pub fn dumpContext(
    scope: []const u8,
    comptime fmt: []const u8,
    args: anytype,
) void {
    if (enable_trace) {
        std.debug.print("[DEBUG] {s}: ", .{scope});
        std.debug.print(fmt ++ "\n", args);
    }
}
