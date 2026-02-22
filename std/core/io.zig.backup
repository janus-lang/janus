// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Standard Library - :core Profile I/O Module
//!
//! Simple, teaching-friendly I/O operations for the :core profile.
//! No capabilities, no contexts - just functions that work.
//!
//! Functions:
//! - print(message)     - Print message to stdout
//! - println(message)   - Print message with newline
//! - eprint(message)    - Print to stderr
//! - eprintln(message)  - Print to stderr with newline
//! - input(prompt)      - Read line from stdin with prompt

const std = @import("std");

// =============================================================================
// STDOUT OPERATIONS
// =============================================================================

/// Print a message to stdout without newline
/// This is the simplest "Hello, World" function - it just works.
///
/// Example:
/// ```janus
/// io.print("Hello, ")
/// io.print("World!")  // Output: Hello, World!
/// ```
pub fn print(message: []const u8) void {
    const stdout = std.fs.File.stdout();
    stdout.writeAll(message) catch return;
}

/// Print a message to stdout with newline
/// The most common output function for :core profile.
///
/// Example:
/// ```janus
/// io.println("Hello, World!")  // Output: Hello, World!\n
/// ```
pub fn println(message: []const u8) void {
    const stdout = std.fs.File.stdout();
    stdout.writeAll(message) catch return;
    stdout.writeAll("\n") catch return;
}

/// Print formatted output to stdout (convenience for Zig interop)
/// For :core profile, prefer println() with string concatenation.
pub fn printf(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.fs.File.stdout();
    std.fmt.format(stdout.writer(&.{}), fmt, args) catch return;
}

// =============================================================================
// STDERR OPERATIONS
// =============================================================================

/// Print a message to stderr without newline
/// Use for error messages and diagnostics.
pub fn eprint(message: []const u8) void {
    const stderr = std.fs.File.stderr();
    stderr.writeAll(message) catch return;
}

/// Print a message to stderr with newline
/// The standard way to output errors in :core profile.
///
/// Example:
/// ```janus
/// io.eprintln("Error: File not found")
/// ```
pub fn eprintln(message: []const u8) void {
    const stderr = std.fs.File.stderr();
    stderr.writeAll(message) catch return;
    stderr.writeAll("\n") catch return;
}

// =============================================================================
// STDIN OPERATIONS
// =============================================================================

/// Read a line from stdin with an optional prompt
/// Returns the line without the trailing newline.
///
/// Example:
/// ```janus
/// let name = io.input("Enter your name: ")
/// io.println("Hello, " + name)
/// ```
pub fn input(allocator: std.mem.Allocator, prompt: ?[]const u8) ![]u8 {
    // Print prompt if provided
    if (prompt) |p| {
        print(p);
    }

    const stdin = std.fs.File.stdin();
    var buffer: [4096]u8 = undefined;
    const reader = stdin.reader(&buffer);

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    while (true) {
        const byte = reader.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        if (byte == '\n') break;
        try result.append(byte);
    }

    return result.toOwnedSlice();
}

/// Read a line from stdin without prompt (simpler signature)
pub fn readLine(allocator: std.mem.Allocator) ![]u8 {
    return input(allocator, null);
}

// =============================================================================
// FORMATTED OUTPUT (for common types)
// =============================================================================

/// Print an integer value
pub fn printInt(value: i64) void {
    var buffer: [32]u8 = undefined;
    const str = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return;
    print(str);
}

/// Print an integer value with newline
pub fn printlnInt(value: i64) void {
    var buffer: [32]u8 = undefined;
    const str = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return;
    println(str);
}

/// Print a float value
pub fn printFloat(value: f64) void {
    var buffer: [64]u8 = undefined;
    const str = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return;
    print(str);
}

/// Print a float value with newline
pub fn printlnFloat(value: f64) void {
    var buffer: [64]u8 = undefined;
    const str = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return;
    println(str);
}

/// Print a boolean value
pub fn printBool(value: bool) void {
    print(if (value) "true" else "false");
}

/// Print a boolean value with newline
pub fn printlnBool(value: bool) void {
    println(if (value) "true" else "false");
}

// =============================================================================
// TESTS
// =============================================================================

test "print functions don't crash" {
    // These tests just verify the functions don't panic
    // Actual output goes to stdout/stderr
    print("test");
    println("test");
    eprint("test");
    eprintln("test");
    printInt(42);
    printlnInt(42);
    printFloat(3.14);
    printlnFloat(3.14);
    printBool(true);
    printlnBool(false);
}
