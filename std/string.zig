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

//! std/string.zig - Encoding-honest string operations
//!
//! This module implements the Zig backend for std/string.jan, providing:
//! - Encoding honesty: All encoding assumptions are explicit
//! - Boundary safety: UTF-8 operations respect codepoint boundaries
//! - Zero-copy bias: Most operations work on slices without copying
//! - Allocator sovereignty: String building requires explicit allocators

const std = @import("std");
const builtin = @import("builtin");

// ===== CORE TYPES =====

/// String types - explicit about encoding and ownership
pub const String = struct {
    bytes: []const u8,
    encoding: Encoding,
    allocator: ?std.mem.Allocator, // null for string literals

    pub fn deinit(self: String) void {
        if (self.allocator) |alloc| {
            alloc.free(self.bytes);
        }
    }
};

pub const Encoding = enum {
    utf8,
    ascii,
    latin1,
    bytes, // Raw bytes, no encoding assumptions
};

/// Error types for string operations
pub const StringError = error{
    InvalidUtf8,
    InvalidBoundary,
    EncodingMismatch,
    OutOfBounds,
    OutOfMemory,
};

/// Iterator types - zero-copy traversal
pub const CodepointIterator = struct {
    string: String,
    position: usize,

    pub fn next(self: *CodepointIterator) ?u32 {
        if (self.position >= self.string.bytes.len) return null;

        const bytes = self.string.bytes[self.position..];
        const codepoint_len = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return null;

        if (bytes.len < codepoint_len) return null;

        const codepoint = std.unicode.utf8Decode(bytes[0..codepoint_len]) catch return null;
        self.position += codepoint_len;

        return codepoint;
    }
};

pub const ByteIterator = struct {
    bytes: []const u8,
    position: usize,

    pub fn next(self: *ByteIterator) ?u8 {
        if (self.position >= self.bytes.len) return null;
        const byte = self.bytes[self.position];
        self.position += 1;
        return byte;
    }
};

// ===== STRING CREATION =====

/// String creation - explicit about allocation and encoding
pub fn fromUtf8(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) StringError!String {
    // Validate UTF-8 first
    try validateUtf8(bytes);

    // Allocate and copy
    const owned_bytes = allocator.dupe(u8, bytes) catch return StringError.OutOfMemory;

    return String{
        .bytes = owned_bytes,
        .encoding = .utf8,
        .allocator = allocator,
    };
}

pub fn fromUtf8Unchecked(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) StringError!String {
    const owned_bytes = allocator.dupe(u8, bytes) catch return StringError.OutOfMemory;

    return String{
        .bytes = owned_bytes,
        .encoding = .utf8,
        .allocator = allocator,
    };
}

pub fn fromLiteral(literal: []const u8) String {
    return String{
        .bytes = literal,
        .encoding = .utf8,
        .allocator = null, // String literals are not owned
    };
}

// ===== STRING OPERATIONS =====

/// String operations - zero-copy where possible
pub fn slice(
    string: String,
    start: usize,
    end: usize,
) StringError!String {
    if (start > string.bytes.len or end > string.bytes.len or start > end) {
        return StringError.OutOfBounds;
    }

    return String{
        .bytes = string.bytes[start..end],
        .encoding = string.encoding,
        .allocator = null, // Slices don't own their data
    };
}

pub fn sliceCodepoints(
    string: String,
    start: usize,
    end: usize,
) StringError!String {
    if (string.encoding != .utf8) {
        return StringError.EncodingMismatch;
    }

    var byte_start: usize = 0;
    var byte_end: usize = 0;
    var codepoint_index: usize = 0;
    var byte_index: usize = 0;

    // Find byte positions for codepoint boundaries
    while (byte_index < string.bytes.len and codepoint_index <= end) {
        if (codepoint_index == start) {
            byte_start = byte_index;
        }
        if (codepoint_index == end) {
            byte_end = byte_index;
            break;
        }

        const byte = string.bytes[byte_index];
        const codepoint_len = std.unicode.utf8ByteSequenceLength(byte) catch return StringError.InvalidUtf8;

        if (byte_index + codepoint_len > string.bytes.len) {
            return StringError.InvalidUtf8;
        }

        // Validate the codepoint
        _ = std.unicode.utf8Decode(string.bytes[byte_index .. byte_index + codepoint_len]) catch return StringError.InvalidUtf8;

        byte_index += codepoint_len;
        codepoint_index += 1;
    }

    // Handle end-of-string case
    if (codepoint_index == end) {
        byte_end = byte_index;
    } else if (end > codepoint_index) {
        return StringError.OutOfBounds;
    }

    return String{
        .bytes = string.bytes[byte_start..byte_end],
        .encoding = .utf8,
        .allocator = null, // Slices don't own their data
    };
}

// ===== VALIDATION AND CONVERSION =====

pub fn validateUtf8(bytes: []const u8) StringError!void {
    if (!std.unicode.utf8ValidateSlice(bytes)) {
        return StringError.InvalidUtf8;
    }
}

pub fn toBytes(string: String) []const u8 {
    return string.bytes;
}

pub fn length(string: String) usize {
    return string.bytes.len;
}

pub fn codepointCount(string: String) StringError!usize {
    if (string.encoding != .utf8) {
        return StringError.EncodingMismatch;
    }

    return std.unicode.utf8CountCodepoints(string.bytes) catch StringError.InvalidUtf8;
}

// ===== COMPARISON =====

/// Comparison - explicit semantics
pub fn equalBytes(a: String, b: String) bool {
    return std.mem.eql(u8, a.bytes, b.bytes);
}

pub fn equalCodepoints(a: String, b: String) StringError!bool {
    if (a.encoding != .utf8 or b.encoding != .utf8) {
        return StringError.EncodingMismatch;
    }

    // For UTF-8, byte equality implies codepoint equality
    return equalBytes(a, b);
}

// ===== ITERATION =====

/// Iteration - zero-copy traversal
pub fn iterateCodepoints(string: String) CodepointIterator {
    return CodepointIterator{
        .string = string,
        .position = 0,
    };
}

pub fn iterateBytes(string: String) ByteIterator {
    return ByteIterator{
        .bytes = string.bytes,
        .position = 0,
    };
}

// ===== STRING BUILDING =====

/// Format arguments for string formatting
pub const FormatArg = union(enum) {
    string: String,
    integer: i64,
    float: f64,
    boolean: bool,
};

/// String building - explicit allocation control
pub fn concat(
    allocator: std.mem.Allocator,
    strings: []const String,
) StringError!String {
    // Calculate total length
    var total_len: usize = 0;
    for (strings) |str| {
        total_len += str.bytes.len;
    }

    // Allocate buffer
    const buffer = allocator.alloc(u8, total_len) catch return StringError.OutOfMemory;

    // Copy strings
    var pos: usize = 0;
    for (strings) |str| {
        @memcpy(buffer[pos .. pos + str.bytes.len], str.bytes);
        pos += str.bytes.len;
    }

    return String{
        .bytes = buffer,
        .encoding = .utf8, // Assume UTF-8 for concatenation
        .allocator = allocator,
    };
}

pub fn format(
    allocator: std.mem.Allocator,
    template: String,
    args: []const FormatArg,
) StringError!String {
    // Simple format implementation - replace {} with arguments
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var template_pos: usize = 0;
    var arg_index: usize = 0;

    while (template_pos < template.bytes.len) {
        if (template_pos + 1 < template.bytes.len and
            template.bytes[template_pos] == '{' and
            template.bytes[template_pos + 1] == '}')
        {

            // Found placeholder
            if (arg_index >= args.len) {
                return StringError.OutOfBounds;
            }

            const arg = args[arg_index];
            switch (arg) {
                .string => |s| {
                    result.appendSlice(s.bytes) catch return StringError.OutOfMemory;
                },
                .integer => |i| {
                    const formatted = std.fmt.allocPrint(allocator, "{d}", .{i}) catch return StringError.OutOfMemory;
                    defer allocator.free(formatted);
                    result.appendSlice(formatted) catch return StringError.OutOfMemory;
                },
                .float => |f| {
                    const formatted = std.fmt.allocPrint(allocator, "{d}", .{f}) catch return StringError.OutOfMemory;
                    defer allocator.free(formatted);
                    result.appendSlice(formatted) catch return StringError.OutOfMemory;
                },
                .boolean => |b| {
                    const str = if (b) "true" else "false";
                    result.appendSlice(str) catch return StringError.OutOfMemory;
                },
            }

            template_pos += 2;
            arg_index += 1;
        } else {
            // Regular character
            result.append(template.bytes[template_pos]) catch return StringError.OutOfMemory;
            template_pos += 1;
        }
    }

    const final_bytes = result.toOwnedSlice() catch return StringError.OutOfMemory;

    return String{
        .bytes = final_bytes,
        .encoding = .utf8,
        .allocator = allocator,
    };
}

/// String builder for dynamic construction
pub const StringBuilder = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StringBuilder {
        return StringBuilder{
            .buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StringBuilder) void {
        self.buffer.deinit();
    }

    pub fn append(self: *StringBuilder, str: String) StringError!void {
        self.buffer.appendSlice(str.bytes) catch return StringError.OutOfMemory;
    }

    pub fn appendBytes(self: *StringBuilder, bytes: []const u8) StringError!void {
        self.buffer.appendSlice(bytes) catch return StringError.OutOfMemory;
    }

    pub fn toString(self: *StringBuilder) StringError!String {
        const final_bytes = self.buffer.toOwnedSlice() catch return StringError.OutOfMemory;

        return String{
            .bytes = final_bytes,
            .encoding = .utf8,
            .allocator = self.allocator,
        };
    }
};

// ===== UTILITY FUNCTIONS =====

/// Split string by delimiter
pub fn split(
    allocator: std.mem.Allocator,
    string: String,
    delimiter: []const u8,
) StringError![]String {
    var parts = std.ArrayList(String).init(allocator);
    defer parts.deinit();

    var start: usize = 0;
    var pos: usize = 0;

    while (pos <= string.bytes.len) {
        if (pos == string.bytes.len or std.mem.startsWith(u8, string.bytes[pos..], delimiter)) {
            // Found delimiter or end of string
            const part = String{
                .bytes = string.bytes[start..pos],
                .encoding = string.encoding,
                .allocator = null, // Parts don't own their data
            };
            parts.append(part) catch return StringError.OutOfMemory;

            if (pos < string.bytes.len) {
                pos += delimiter.len;
                start = pos;
            } else {
                break;
            }
        } else {
            pos += 1;
        }
    }

    return parts.toOwnedSlice() catch StringError.OutOfMemory;
}

/// Join strings with delimiter
pub fn join(
    allocator: std.mem.Allocator,
    strings: []const String,
    delimiter: []const u8,
) StringError!String {
    if (strings.len == 0) {
        return fromLiteral("");
    }

    // Calculate total length
    var total_len: usize = 0;
    for (strings, 0..) |str, i| {
        total_len += str.bytes.len;
        if (i < strings.len - 1) {
            total_len += delimiter.len;
        }
    }

    // Allocate buffer
    const buffer = allocator.alloc(u8, total_len) catch return StringError.OutOfMemory;

    // Copy strings with delimiters
    var pos: usize = 0;
    for (strings, 0..) |str, i| {
        @memcpy(buffer[pos .. pos + str.bytes.len], str.bytes);
        pos += str.bytes.len;

        if (i < strings.len - 1) {
            @memcpy(buffer[pos .. pos + delimiter.len], delimiter);
            pos += delimiter.len;
        }
    }

    return String{
        .bytes = buffer,
        .encoding = .utf8,
        .allocator = allocator,
    };
}

// ===== TESTS =====

test "string creation and validation" {
    const testing_allocator = std.testing.allocator;

    // Test valid UTF-8
    const valid_utf8 = "Hello, 世界! 🌍";
    const string = try fromUtf8(testing_allocator, valid_utf8);
    defer string.deinit();

    try std.testing.expectEqualStrings(valid_utf8, string.bytes);
    try std.testing.expectEqual(Encoding.utf8, string.encoding);

    // Test codepoint count
    const count = try codepointCount(string);
    try std.testing.expectEqual(@as(usize, 12), count); // "Hello, 世界! 🌍" has 12 codepoints
}

test "string slicing" {
    const testing_allocator = std.testing.allocator;

    const original = try fromUtf8(testing_allocator, "Hello, World!");
    defer original.deinit();

    // Test byte slicing
    const byte_slice = try slice(original, 0, 5);
    try std.testing.expectEqualStrings("Hello", byte_slice.bytes);

    // Test codepoint slicing
    const codepoint_slice = try sliceCodepoints(original, 7, 12);
    try std.testing.expectEqualStrings("World", codepoint_slice.bytes);
}

test "string concatenation" {
    const testing_allocator = std.testing.allocator;

    const str1 = fromLiteral("Hello, ");
    const str2 = fromLiteral("World!");

    const strings = [_]String{ str1, str2 };
    const result = try concat(testing_allocator, &strings);
    defer result.deinit();

    try std.testing.expectEqualStrings("Hello, World!", result.bytes);
}

test "string formatting" {
    const testing_allocator = std.testing.allocator;

    const template = fromLiteral("Hello, {}! You have {} messages.");
    const args = [_]FormatArg{
        .{ .string = fromLiteral("Alice") },
        .{ .integer = 42 },
    };

    const result = try format(testing_allocator, template, &args);
    defer result.deinit();

    try std.testing.expectEqualStrings("Hello, Alice! You have 42 messages.", result.bytes);
}

test "string builder" {
    const testing_allocator = std.testing.allocator;

    var builder = StringBuilder.init(testing_allocator);
    defer builder.deinit();

    try builder.appendBytes("Hello");
    try builder.appendBytes(", ");
    try builder.append(fromLiteral("World!"));

    const result = try builder.toString();
    defer result.deinit();

    try std.testing.expectEqualStrings("Hello, World!", result.bytes);
}

test "string splitting and joining" {
    const testing_allocator = std.testing.allocator;

    const original = fromLiteral("apple,banana,cherry");
    const parts = try split(testing_allocator, original, ",");
    defer testing_allocator.free(parts);

    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("apple", parts[0].bytes);
    try std.testing.expectEqualStrings("banana", parts[1].bytes);
    try std.testing.expectEqualStrings("cherry", parts[2].bytes);

    const rejoined = try join(testing_allocator, parts, ",");
    defer rejoined.deinit();

    try std.testing.expectEqualStrings("apple,banana,cherry", rejoined.bytes);
}

test "UTF-8 iteration" {
    const string = fromLiteral("Hello, 世界!");

    // Test codepoint iteration
    var codepoint_iter = iterateCodepoints(string);
    var codepoint_count: usize = 0;
    while (codepoint_iter.next()) |_| {
        codepoint_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 10), codepoint_count);

    // Test byte iteration
    var byte_iter = iterateBytes(string);
    var byte_count: usize = 0;
    while (byte_iter.next()) |_| {
        byte_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 14), byte_count); // UTF-8 bytes
}

test "error handling" {
    const testing_allocator = std.testing.allocator;

    // Test invalid UTF-8
    const invalid_utf8 = [_]u8{ 0xFF, 0xFE, 0xFD };
    const result = fromUtf8(testing_allocator, &invalid_utf8);
    try std.testing.expectError(StringError.InvalidUtf8, result);

    // Test out of bounds slicing
    const string = fromLiteral("Hello");
    const slice_result = slice(string, 10, 20);
    try std.testing.expectError(StringError.OutOfBounds, slice_result);
}
