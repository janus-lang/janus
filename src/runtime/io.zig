// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Runtime: Core I/O Functions

const std = @import("std");

/// Print a string to stdout (for QTJIR compiled code)
/// This is the runtime function that LLVM-compiled code calls
export fn janus_print(str: [*:0]const u8) void {
    std.debug.print("{s}\n", .{str});
}

/// Print an integer to stdout
export fn janus_print_i32(value: i32) void {
    std.debug.print("{d}\n", .{value});
}

/// Print an integer to stdout (64-bit)
export fn janus_print_i64(value: i64) void {
    std.debug.print("{d}\n", .{value});
}

/// Print a float to stdout
export fn janus_print_f32(value: f32) void {
    std.debug.print("{d}\n", .{value});
}

/// Print a float to stdout (64-bit)
export fn janus_print_f64(value: f64) void {
    std.debug.print("{d}\n", .{value});
}

/// Print a boolean to stdout
export fn janus_print_bool(value: bool) void {
    const str = if (value) "true" else "false";
    std.debug.print("{s}\n", .{str});
}

// Test the runtime functions
test "janus_print functions" {
    // These are export functions meant to be called from compiled code
    // Just verify they compile
    _ = janus_print;
    _ = janus_print_i32;
    _ = janus_print_i64;
    _ = janus_print_f32;
    _ = janus_print_f64;
    _ = janus_print_bool;
}
