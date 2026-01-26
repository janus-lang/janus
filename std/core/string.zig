// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Standard Library - :core Profile String Module
//!
//! Simple, teaching-friendly string operations for the :core profile.
//! All strings are UTF-8 encoded byte slices.
//!
//! Functions:
//! - length(s)              - Get string length in bytes
//! - charCount(s)           - Get string length in Unicode characters
//! - startsWith(s, prefix)  - Check if string starts with prefix
//! - endsWith(s, suffix)    - Check if string ends with suffix
//! - contains(s, substr)    - Check if string contains substring
//! - indexOf(s, substr)     - Find first occurrence of substring
//! - trim(s)                - Remove leading/trailing whitespace
//! - toUpper(s)             - Convert to uppercase (ASCII only)
//! - toLower(s)             - Convert to lowercase (ASCII only)
//! - split(s, delim)        - Split string by delimiter
//! - join(parts, delim)     - Join strings with delimiter
//! - concat(a, b)           - Concatenate two strings
//! - repeat(s, n)           - Repeat string n times
//! - replace(s, old, new)   - Replace all occurrences
//! - substring(s, start, len) - Extract substring

const std = @import("std");

/// String errors for :core profile
pub const StringError = error{
    InvalidUtf8,
    OutOfBounds,
    OutOfMemory,
    EmptyString,
};

// =============================================================================
// LENGTH OPERATIONS
// =============================================================================

/// Get string length in bytes
/// This is the fast O(1) operation for UTF-8 strings.
///
/// Example:
/// ```janus
/// let s = "Hello"
/// io.println(string(string.length(s)))  // Output: 5
/// ```
pub fn length(s: []const u8) usize {
    return s.len;
}

/// Get string length in Unicode characters (codepoints)
/// This is O(n) as it must scan the string.
///
/// Example:
/// ```janus
/// let s = "Hello, 世界"
/// io.println(string(string.charCount(s)))  // Output: 9
/// ```
pub fn charCount(s: []const u8) StringError!usize {
    return std.unicode.utf8CountCodepoints(s) catch return StringError.InvalidUtf8;
}

/// Check if string is empty
pub fn isEmpty(s: []const u8) bool {
    return s.len == 0;
}

// =============================================================================
// SEARCH OPERATIONS
// =============================================================================

/// Check if string starts with the given prefix
///
/// Example:
/// ```janus
/// if string.startsWith(filename, ".") {
///     io.println("Hidden file!")
/// }
/// ```
pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, s, prefix);
}

/// Check if string ends with the given suffix
///
/// Example:
/// ```janus
/// if string.endsWith(filename, ".jan") {
///     io.println("Janus source file!")
/// }
/// ```
pub fn endsWith(s: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, s, suffix);
}

/// Check if string contains the given substring
///
/// Example:
/// ```janus
/// if string.contains(text, "error") {
///     io.eprintln("Found an error!")
/// }
/// ```
pub fn contains(s: []const u8, substr: []const u8) bool {
    return std.mem.indexOf(u8, s, substr) != null;
}

/// Find the first occurrence of substring, returns null if not found
pub fn indexOf(s: []const u8, substr: []const u8) ?usize {
    return std.mem.indexOf(u8, s, substr);
}

/// Find the last occurrence of substring, returns null if not found
pub fn lastIndexOf(s: []const u8, substr: []const u8) ?usize {
    return std.mem.lastIndexOf(u8, s, substr);
}

// =============================================================================
// TRANSFORMATION OPERATIONS
// =============================================================================

/// Remove leading and trailing whitespace
/// Returns a slice into the original string (no allocation).
pub fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\n\r");
}

/// Remove leading whitespace only
pub fn trimStart(s: []const u8) []const u8 {
    return std.mem.trimLeft(u8, s, " \t\n\r");
}

/// Remove trailing whitespace only
pub fn trimEnd(s: []const u8) []const u8 {
    return std.mem.trimRight(u8, s, " \t\n\r");
}

/// Convert ASCII characters to uppercase
/// Caller owns the returned memory.
pub fn toUpper(allocator: std.mem.Allocator, s: []const u8) StringError![]u8 {
    const result = allocator.alloc(u8, s.len) catch return StringError.OutOfMemory;
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

/// Convert ASCII characters to lowercase
/// Caller owns the returned memory.
pub fn toLower(allocator: std.mem.Allocator, s: []const u8) StringError![]u8 {
    const result = allocator.alloc(u8, s.len) catch return StringError.OutOfMemory;
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

// =============================================================================
// SPLIT AND JOIN
// =============================================================================

/// Split string by delimiter
/// Caller owns the returned array and each string slice.
///
/// Example:
/// ```janus
/// let parts = string.split("a,b,c", ",")
/// for part in parts {
///     io.println(part)
/// }
/// ```
pub fn split(allocator: std.mem.Allocator, s: []const u8, delimiter: []const u8) StringError![][]const u8 {
    var parts = std.ArrayListUnmanaged([]const u8){};
    errdefer parts.deinit(allocator);

    var iter = std.mem.splitSequence(u8, s, delimiter);
    while (iter.next()) |part| {
        parts.append(allocator, part) catch return StringError.OutOfMemory;
    }

    return parts.toOwnedSlice(allocator) catch return StringError.OutOfMemory;
}

/// Split string into at most n parts
pub fn splitN(allocator: std.mem.Allocator, s: []const u8, delimiter: []const u8, n: usize) StringError![][]const u8 {
    var parts = std.ArrayListUnmanaged([]const u8){};
    errdefer parts.deinit(allocator);

    var iter = std.mem.splitSequence(u8, s, delimiter);
    var cnt: usize = 0;

    while (iter.next()) |part| {
        if (cnt >= n - 1 and iter.rest().len > 0) {
            // Last part gets everything remaining
            const remaining_start = @intFromPtr(part.ptr) - @intFromPtr(s.ptr);
            parts.append(allocator, s[remaining_start..]) catch return StringError.OutOfMemory;
            break;
        }
        parts.append(allocator, part) catch return StringError.OutOfMemory;
        cnt += 1;
    }

    return parts.toOwnedSlice(allocator) catch return StringError.OutOfMemory;
}

/// Join strings with delimiter
/// Caller owns the returned memory.
///
/// Example:
/// ```janus
/// let path = string.join(["home", "user", "docs"], "/")
/// io.println(path)  // Output: home/user/docs
/// ```
pub fn join(allocator: std.mem.Allocator, parts: []const []const u8, delimiter: []const u8) StringError![]u8 {
    if (parts.len == 0) {
        return allocator.alloc(u8, 0) catch return StringError.OutOfMemory;
    }

    // Calculate total length
    var total_len: usize = 0;
    for (parts, 0..) |part, i| {
        total_len += part.len;
        if (i < parts.len - 1) {
            total_len += delimiter.len;
        }
    }

    const result = allocator.alloc(u8, total_len) catch return StringError.OutOfMemory;
    var pos: usize = 0;

    for (parts, 0..) |part, i| {
        @memcpy(result[pos .. pos + part.len], part);
        pos += part.len;
        if (i < parts.len - 1) {
            @memcpy(result[pos .. pos + delimiter.len], delimiter);
            pos += delimiter.len;
        }
    }

    return result;
}

// =============================================================================
// CONCATENATION AND REPETITION
// =============================================================================

/// Concatenate two strings
/// Caller owns the returned memory.
pub fn concat(allocator: std.mem.Allocator, a: []const u8, b: []const u8) StringError![]u8 {
    const result = allocator.alloc(u8, a.len + b.len) catch return StringError.OutOfMemory;
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}

/// Concatenate multiple strings
/// Caller owns the returned memory.
pub fn concatMany(allocator: std.mem.Allocator, strings: []const []const u8) StringError![]u8 {
    var total_len: usize = 0;
    for (strings) |s| {
        total_len += s.len;
    }

    const result = allocator.alloc(u8, total_len) catch return StringError.OutOfMemory;
    var pos: usize = 0;

    for (strings) |s| {
        @memcpy(result[pos .. pos + s.len], s);
        pos += s.len;
    }

    return result;
}

/// Repeat a string n times
/// Caller owns the returned memory.
pub fn repeat(allocator: std.mem.Allocator, s: []const u8, n: usize) StringError![]u8 {
    if (n == 0) {
        return allocator.alloc(u8, 0) catch return StringError.OutOfMemory;
    }

    const result = allocator.alloc(u8, s.len * n) catch return StringError.OutOfMemory;
    var pos: usize = 0;

    for (0..n) |_| {
        @memcpy(result[pos .. pos + s.len], s);
        pos += s.len;
    }

    return result;
}

// =============================================================================
// SUBSTRING OPERATIONS
// =============================================================================

/// Extract a substring starting at index with given length
/// Returns a slice into the original string (no allocation).
pub fn substring(s: []const u8, start: usize, len: usize) StringError![]const u8 {
    if (start > s.len) return StringError.OutOfBounds;
    const actual_len = @min(len, s.len - start);
    return s[start .. start + actual_len];
}

/// Extract substring from start to end (exclusive)
/// Returns a slice into the original string (no allocation).
pub fn slice(s: []const u8, start: usize, end: usize) StringError![]const u8 {
    if (start > s.len or end > s.len or start > end) {
        return StringError.OutOfBounds;
    }
    return s[start..end];
}

/// Get character at index (as single-character string)
pub fn charAt(s: []const u8, index: usize) StringError![]const u8 {
    if (index >= s.len) return StringError.OutOfBounds;
    return s[index .. index + 1];
}

// =============================================================================
// REPLACE OPERATIONS
// =============================================================================

/// Replace all occurrences of old with new
/// Caller owns the returned memory.
pub fn replace(allocator: std.mem.Allocator, s: []const u8, old: []const u8, new: []const u8) StringError![]u8 {
    if (old.len == 0) {
        return allocator.dupe(u8, s) catch return StringError.OutOfMemory;
    }

    // Count occurrences
    var count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, s, pos, old)) |idx| {
        count += 1;
        pos = idx + old.len;
    }

    if (count == 0) {
        return allocator.dupe(u8, s) catch return StringError.OutOfMemory;
    }

    // Calculate new length
    const new_len = s.len - (count * old.len) + (count * new.len);
    const result = allocator.alloc(u8, new_len) catch return StringError.OutOfMemory;

    // Build result
    var read_pos: usize = 0;
    var write_pos: usize = 0;

    while (std.mem.indexOfPos(u8, s, read_pos, old)) |idx| {
        // Copy bytes before match
        const before_len = idx - read_pos;
        @memcpy(result[write_pos .. write_pos + before_len], s[read_pos..idx]);
        write_pos += before_len;

        // Copy replacement
        @memcpy(result[write_pos .. write_pos + new.len], new);
        write_pos += new.len;

        read_pos = idx + old.len;
    }

    // Copy remaining bytes
    const remaining = s.len - read_pos;
    @memcpy(result[write_pos .. write_pos + remaining], s[read_pos..]);

    return result;
}

/// Replace first occurrence only
pub fn replaceFirst(allocator: std.mem.Allocator, s: []const u8, old: []const u8, new: []const u8) StringError![]u8 {
    if (std.mem.indexOf(u8, s, old)) |idx| {
        const new_len = s.len - old.len + new.len;
        const result = allocator.alloc(u8, new_len) catch return StringError.OutOfMemory;

        @memcpy(result[0..idx], s[0..idx]);
        @memcpy(result[idx .. idx + new.len], new);
        @memcpy(result[idx + new.len ..], s[idx + old.len ..]);

        return result;
    }

    return allocator.dupe(u8, s) catch return StringError.OutOfMemory;
}

// =============================================================================
// COMPARISON
// =============================================================================

/// Compare two strings for equality
pub fn equals(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Compare two strings (case-insensitive, ASCII only)
pub fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

/// Lexicographic comparison: returns -1, 0, or 1
pub fn compare(a: []const u8, b: []const u8) i32 {
    const order = std.mem.order(u8, a, b);
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

// =============================================================================
// TESTS
// =============================================================================

test "length operations" {
    try std.testing.expectEqual(@as(usize, 5), length("Hello"));
    try std.testing.expectEqual(@as(usize, 0), length(""));
    try std.testing.expectEqual(@as(usize, 9), try charCount("Hello, 世界"));
    try std.testing.expect(isEmpty(""));
    try std.testing.expect(!isEmpty("x"));
}

test "search operations" {
    try std.testing.expect(startsWith("Hello, World", "Hello"));
    try std.testing.expect(!startsWith("Hello, World", "World"));
    try std.testing.expect(endsWith("file.txt", ".txt"));
    try std.testing.expect(!endsWith("file.txt", ".md"));
    try std.testing.expect(contains("Hello, World", "World"));
    try std.testing.expect(!contains("Hello, World", "Foo"));
    try std.testing.expectEqual(@as(?usize, 7), indexOf("Hello, World", "World"));
    try std.testing.expectEqual(@as(?usize, null), indexOf("Hello, World", "Foo"));
}

test "transformation operations" {
    try std.testing.expectEqualStrings("Hello", trim("  Hello  "));
    try std.testing.expectEqualStrings("Hello  ", trimStart("  Hello  "));
    try std.testing.expectEqualStrings("  Hello", trimEnd("  Hello  "));

    const allocator = std.testing.allocator;

    const upper = try toUpper(allocator, "hello");
    defer allocator.free(upper);
    try std.testing.expectEqualStrings("HELLO", upper);

    const lower = try toLower(allocator, "HELLO");
    defer allocator.free(lower);
    try std.testing.expectEqualStrings("hello", lower);
}

test "split and join" {
    const allocator = std.testing.allocator;

    const parts = try split(allocator, "a,b,c", ",");
    defer allocator.free(parts);
    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("a", parts[0]);
    try std.testing.expectEqualStrings("b", parts[1]);
    try std.testing.expectEqualStrings("c", parts[2]);

    const joined = try join(allocator, parts, "-");
    defer allocator.free(joined);
    try std.testing.expectEqualStrings("a-b-c", joined);
}

test "concat and repeat" {
    const allocator = std.testing.allocator;

    const combined = try concat(allocator, "Hello, ", "World!");
    defer allocator.free(combined);
    try std.testing.expectEqualStrings("Hello, World!", combined);

    const repeated = try repeat(allocator, "ab", 3);
    defer allocator.free(repeated);
    try std.testing.expectEqualStrings("ababab", repeated);
}

test "substring operations" {
    try std.testing.expectEqualStrings("llo", try substring("Hello", 2, 3));
    try std.testing.expectEqualStrings("llo", try slice("Hello", 2, 5));
    try std.testing.expectEqualStrings("e", try charAt("Hello", 1));
}

test "replace operations" {
    const allocator = std.testing.allocator;

    const replaced = try replace(allocator, "hello world world", "world", "Janus");
    defer allocator.free(replaced);
    try std.testing.expectEqualStrings("hello Janus Janus", replaced);

    const replaced_first = try replaceFirst(allocator, "hello world world", "world", "Janus");
    defer allocator.free(replaced_first);
    try std.testing.expectEqualStrings("hello Janus world", replaced_first);
}

test "comparison" {
    try std.testing.expect(equals("hello", "hello"));
    try std.testing.expect(!equals("hello", "Hello"));
    try std.testing.expect(equalsIgnoreCase("hello", "HELLO"));
    try std.testing.expectEqual(@as(i32, 0), compare("abc", "abc"));
    try std.testing.expectEqual(@as(i32, -1), compare("abc", "abd"));
    try std.testing.expectEqual(@as(i32, 1), compare("abd", "abc"));
}
