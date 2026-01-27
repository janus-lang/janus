// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Core String Operations - Exported for Native Grafting
//!
//! This module provides C-exported string functions that Janus can call
//! via `use zig "std/core/string_ops.zig"`.
//!
//! All functions use C-compatible types:
//! - Strings are passed as ptr + len pairs
//! - Results use out-parameters or return simple values
//! - No Zig allocators - uses Janus runtime when allocation needed

const std = @import("std");

// ============================================================================
// SEARCH OPERATIONS (no allocation needed)
// ============================================================================

/// Check if string contains substring
/// Returns 1 (true) or 0 (false)
pub export fn str_contains(
    haystack_ptr: [*]const u8,
    haystack_len: usize,
    needle_ptr: [*]const u8,
    needle_len: usize,
) callconv(.c) i32 {
    const haystack = haystack_ptr[0..haystack_len];
    const needle = needle_ptr[0..needle_len];
    return if (std.mem.indexOf(u8, haystack, needle) != null) 1 else 0;
}

/// Find first occurrence of substring
/// Returns index or -1 if not found
pub export fn str_index_of(
    str_ptr: [*]const u8,
    str_len: usize,
    needle_ptr: [*]const u8,
    needle_len: usize,
) callconv(.c) i64 {
    const str = str_ptr[0..str_len];
    const needle = needle_ptr[0..needle_len];
    if (std.mem.indexOf(u8, str, needle)) |idx| {
        return @intCast(idx);
    }
    return -1;
}

/// Find last occurrence of substring
/// Returns index or -1 if not found
pub export fn str_last_index_of(
    str_ptr: [*]const u8,
    str_len: usize,
    needle_ptr: [*]const u8,
    needle_len: usize,
) callconv(.c) i64 {
    const str = str_ptr[0..str_len];
    const needle = needle_ptr[0..needle_len];
    if (std.mem.lastIndexOf(u8, str, needle)) |idx| {
        return @intCast(idx);
    }
    return -1;
}

/// Find first occurrence of a single character
/// Returns index or -1 if not found
pub export fn str_index_of_char(
    str_ptr: [*]const u8,
    str_len: usize,
    ch: u8,
) callconv(.c) i64 {
    const str = str_ptr[0..str_len];
    if (std.mem.indexOfScalar(u8, str, ch)) |idx| {
        return @intCast(idx);
    }
    return -1;
}

/// Find last occurrence of a single character
/// Returns index or -1 if not found
pub export fn str_last_index_of_char(
    str_ptr: [*]const u8,
    str_len: usize,
    ch: u8,
) callconv(.c) i64 {
    const str = str_ptr[0..str_len];
    if (std.mem.lastIndexOfScalar(u8, str, ch)) |idx| {
        return @intCast(idx);
    }
    return -1;
}

// ============================================================================
// PREFIX/SUFFIX OPERATIONS
// ============================================================================

/// Check if string starts with prefix
/// Returns 1 (true) or 0 (false)
pub export fn str_starts_with(
    str_ptr: [*]const u8,
    str_len: usize,
    prefix_ptr: [*]const u8,
    prefix_len: usize,
) callconv(.c) i32 {
    const str = str_ptr[0..str_len];
    const prefix = prefix_ptr[0..prefix_len];
    return if (std.mem.startsWith(u8, str, prefix)) 1 else 0;
}

/// Check if string ends with suffix
/// Returns 1 (true) or 0 (false)
pub export fn str_ends_with(
    str_ptr: [*]const u8,
    str_len: usize,
    suffix_ptr: [*]const u8,
    suffix_len: usize,
) callconv(.c) i32 {
    const str = str_ptr[0..str_len];
    const suffix = suffix_ptr[0..suffix_len];
    return if (std.mem.endsWith(u8, str, suffix)) 1 else 0;
}

// ============================================================================
// COMPARISON OPERATIONS
// ============================================================================

/// Compare two strings for equality
/// Returns 1 (true) or 0 (false)
pub export fn str_equals(
    a_ptr: [*]const u8,
    a_len: usize,
    b_ptr: [*]const u8,
    b_len: usize,
) callconv(.c) i32 {
    const a = a_ptr[0..a_len];
    const b = b_ptr[0..b_len];
    return if (std.mem.eql(u8, a, b)) 1 else 0;
}

/// Compare two strings (case-insensitive, ASCII only)
/// Returns 1 (true) or 0 (false)
pub export fn str_equals_ignore_case(
    a_ptr: [*]const u8,
    a_len: usize,
    b_ptr: [*]const u8,
    b_len: usize,
) callconv(.c) i32 {
    if (a_len != b_len) return 0;
    const a = a_ptr[0..a_len];
    const b = b_ptr[0..b_len];
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return 0;
    }
    return 1;
}

/// Lexicographic comparison
/// Returns -1 (a < b), 0 (a == b), or 1 (a > b)
pub export fn str_compare(
    a_ptr: [*]const u8,
    a_len: usize,
    b_ptr: [*]const u8,
    b_len: usize,
) callconv(.c) i32 {
    const a = a_ptr[0..a_len];
    const b = b_ptr[0..b_len];
    const order = std.mem.order(u8, a, b);
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

// ============================================================================
// TRANSFORMATION (in-place or buffer-based)
// ============================================================================

/// Convert ASCII characters to uppercase in-place
/// Modifies the buffer directly
pub export fn str_to_upper_inplace(
    str_ptr: [*]u8,
    str_len: usize,
) callconv(.c) void {
    const str = str_ptr[0..str_len];
    for (str) |*c| {
        c.* = std.ascii.toUpper(c.*);
    }
}

/// Convert ASCII characters to lowercase in-place
/// Modifies the buffer directly
pub export fn str_to_lower_inplace(
    str_ptr: [*]u8,
    str_len: usize,
) callconv(.c) void {
    const str = str_ptr[0..str_len];
    for (str) |*c| {
        c.* = std.ascii.toLower(c.*);
    }
}

/// Copy and convert to uppercase
/// Returns number of bytes written
pub export fn str_to_upper(
    src_ptr: [*]const u8,
    src_len: usize,
    dst_ptr: [*]u8,
    dst_len: usize,
) callconv(.c) usize {
    const copy_len = @min(src_len, dst_len);
    const src = src_ptr[0..copy_len];
    const dst = dst_ptr[0..copy_len];
    for (src, dst) |c, *d| {
        d.* = std.ascii.toUpper(c);
    }
    return copy_len;
}

/// Copy and convert to lowercase
/// Returns number of bytes written
pub export fn str_to_lower(
    src_ptr: [*]const u8,
    src_len: usize,
    dst_ptr: [*]u8,
    dst_len: usize,
) callconv(.c) usize {
    const copy_len = @min(src_len, dst_len);
    const src = src_ptr[0..copy_len];
    const dst = dst_ptr[0..copy_len];
    for (src, dst) |c, *d| {
        d.* = std.ascii.toLower(c);
    }
    return copy_len;
}

// ============================================================================
// TRIM OPERATIONS (return slice into original)
// ============================================================================

/// Trim leading and trailing whitespace
/// Returns new start offset and length via out-parameters
pub export fn str_trim(
    str_ptr: [*]const u8,
    str_len: usize,
    out_start: *usize,
    out_len: *usize,
) callconv(.c) void {
    const str = str_ptr[0..str_len];
    const trimmed = std.mem.trim(u8, str, " \t\n\r");

    // Calculate offset from original
    out_start.* = @intFromPtr(trimmed.ptr) - @intFromPtr(str_ptr);
    out_len.* = trimmed.len;
}

/// Trim leading whitespace only
pub export fn str_trim_start(
    str_ptr: [*]const u8,
    str_len: usize,
    out_start: *usize,
    out_len: *usize,
) callconv(.c) void {
    const str = str_ptr[0..str_len];
    const trimmed = std.mem.trimLeft(u8, str, " \t\n\r");

    out_start.* = @intFromPtr(trimmed.ptr) - @intFromPtr(str_ptr);
    out_len.* = trimmed.len;
}

/// Trim trailing whitespace only
pub export fn str_trim_end(
    str_ptr: [*]const u8,
    str_len: usize,
    out_start: *usize,
    out_len: *usize,
) callconv(.c) void {
    const str = str_ptr[0..str_len];
    const trimmed = std.mem.trimRight(u8, str, " \t\n\r");

    out_start.* = @intFromPtr(trimmed.ptr) - @intFromPtr(str_ptr);
    out_len.* = trimmed.len;
}

// ============================================================================
// LENGTH AND VALIDATION
// ============================================================================

/// Get string length in bytes (trivial but useful for consistency)
pub export fn str_length(
    str_ptr: [*]const u8,
    str_len: usize,
) callconv(.c) usize {
    _ = str_ptr;
    return str_len;
}

/// Get string length in Unicode codepoints
/// Returns -1 if invalid UTF-8
pub export fn str_char_count(
    str_ptr: [*]const u8,
    str_len: usize,
) callconv(.c) i64 {
    const str = str_ptr[0..str_len];
    if (std.unicode.utf8CountCodepoints(str)) |count| {
        return @intCast(count);
    } else |_| {
        return -1;
    }
}

/// Validate UTF-8 encoding
/// Returns 1 (valid) or 0 (invalid)
pub export fn str_is_valid_utf8(
    str_ptr: [*]const u8,
    str_len: usize,
) callconv(.c) i32 {
    const str = str_ptr[0..str_len];
    return if (std.unicode.utf8ValidateSlice(str)) 1 else 0;
}

/// Check if string is empty
/// Returns 1 (true) or 0 (false)
pub export fn str_is_empty(
    str_ptr: [*]const u8,
    str_len: usize,
) callconv(.c) i32 {
    _ = str_ptr;
    return if (str_len == 0) 1 else 0;
}

// ============================================================================
// SUBSTRING (returns slice parameters)
// ============================================================================

/// Get substring by byte indices (start inclusive, end exclusive)
/// Returns new start offset and length via out-parameters
/// Returns 0 on success, -1 on out of bounds
pub export fn str_substring(
    str_ptr: [*]const u8,
    str_len: usize,
    start: usize,
    end: usize,
    out_ptr: *[*]const u8,
    out_len: *usize,
) callconv(.c) i32 {
    if (start > str_len or end > str_len or start > end) {
        out_ptr.* = str_ptr;
        out_len.* = 0;
        return -1;
    }
    out_ptr.* = str_ptr + start;
    out_len.* = end - start;
    return 0;
}

// ============================================================================
// COPY OPERATIONS
// ============================================================================

/// Copy string to destination buffer
/// Returns number of bytes copied
pub export fn str_copy(
    src_ptr: [*]const u8,
    src_len: usize,
    dst_ptr: [*]u8,
    dst_len: usize,
) callconv(.c) usize {
    const copy_len = @min(src_len, dst_len);
    @memcpy(dst_ptr[0..copy_len], src_ptr[0..copy_len]);
    return copy_len;
}

/// Concatenate two strings into destination buffer
/// Returns total bytes written, or 0 if buffer too small
pub export fn str_concat(
    a_ptr: [*]const u8,
    a_len: usize,
    b_ptr: [*]const u8,
    b_len: usize,
    dst_ptr: [*]u8,
    dst_len: usize,
) callconv(.c) usize {
    const total_len = a_len + b_len;
    if (total_len > dst_len) return 0;

    @memcpy(dst_ptr[0..a_len], a_ptr[0..a_len]);
    @memcpy(dst_ptr[a_len .. a_len + b_len], b_ptr[0..b_len]);
    return total_len;
}

// ============================================================================
// TESTS
// ============================================================================

test "str_contains" {
    const hello = "Hello, World!";
    try std.testing.expectEqual(@as(i32, 1), str_contains(hello.ptr, hello.len, "World".ptr, 5));
    try std.testing.expectEqual(@as(i32, 0), str_contains(hello.ptr, hello.len, "Foo".ptr, 3));
}

test "str_index_of" {
    const hello = "Hello, World!";
    try std.testing.expectEqual(@as(i64, 7), str_index_of(hello.ptr, hello.len, "World".ptr, 5));
    try std.testing.expectEqual(@as(i64, -1), str_index_of(hello.ptr, hello.len, "Foo".ptr, 3));
}

test "str_starts_with" {
    const hello = "Hello, World!";
    try std.testing.expectEqual(@as(i32, 1), str_starts_with(hello.ptr, hello.len, "Hello".ptr, 5));
    try std.testing.expectEqual(@as(i32, 0), str_starts_with(hello.ptr, hello.len, "World".ptr, 5));
}

test "str_ends_with" {
    const hello = "Hello, World!";
    try std.testing.expectEqual(@as(i32, 1), str_ends_with(hello.ptr, hello.len, "World!".ptr, 6));
    try std.testing.expectEqual(@as(i32, 0), str_ends_with(hello.ptr, hello.len, "Hello".ptr, 5));
}

test "str_to_upper" {
    var buffer: [20]u8 = undefined;
    const src = "hello";
    const len = str_to_upper(src.ptr, src.len, &buffer, buffer.len);
    try std.testing.expectEqualStrings("HELLO", buffer[0..len]);
}

test "str_to_lower" {
    var buffer: [20]u8 = undefined;
    const src = "HELLO";
    const len = str_to_lower(src.ptr, src.len, &buffer, buffer.len);
    try std.testing.expectEqualStrings("hello", buffer[0..len]);
}

test "str_trim" {
    const input = "  hello  ";
    var start: usize = undefined;
    var len: usize = undefined;
    str_trim(input.ptr, input.len, &start, &len);
    try std.testing.expectEqual(@as(usize, 2), start);
    try std.testing.expectEqual(@as(usize, 5), len);
}

test "str_char_count" {
    const ascii = "Hello";
    try std.testing.expectEqual(@as(i64, 5), str_char_count(ascii.ptr, ascii.len));

    const utf8 = "Hello, 世界";
    try std.testing.expectEqual(@as(i64, 9), str_char_count(utf8.ptr, utf8.len));
}
