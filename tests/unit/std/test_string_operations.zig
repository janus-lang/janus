// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Comprehensive tests for std/string.zig operations
//! Tests encoding honesty, boundary safety, zero-copy operations, and allocator sovereignty

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const string = @import("std_string");

test "encoding honesty - all encoding assumptions are explicit" {
    const testing_allocator = testing.allocator;

    // Test UTF-8 string creation
    const utf8_bytes = "Hello, 世界! 🌍";
    const utf8_string = try string.fromUtf8(testing_allocator, utf8_bytes);
    defer utf8_string.deinit();
    try testing.expectEqual(string.Encoding.utf8, utf8_string.encoding);
    try testing.expectEqualStrings(utf8_bytes, utf8_string.bytes);

    // Test string literal (no allocation)
    const literal = string.fromLiteral("Hello, World!");
    try testing.expectEqual(string.Encoding.utf8, literal.encoding);
    try testing.expect(literal.allocator == null);

    // Test encoding validation
    try string.validateUtf8(utf8_bytes);

    // Test invalid UTF-8 detection
    const invalid_utf8 = [_]u8{ 0xFF, 0xFE, 0xFD };
    try testing.expectError(string.StringError.InvalidUtf8, string.validateUtf8(&invalid_utf8));
}

test "boundary safety - UTF-8 operations respect codepoint boundaries" {
    const testing_allocator = testing.allocator;

    // Test string with multi-byte UTF-8 characters
    const utf8_text = "Hello, 世界! 🌍";
    const utf8_string = try string.fromUtf8(testing_allocator, utf8_text);
    defer utf8_string.deinit();

    // Test codepoint count vs byte count
    const codepoint_count = try string.codepointCount(utf8_string);
    const byte_count = string.length(utf8_string);

    try testing.expectEqual(@as(usize, 12), codepoint_count); // 12 codepoints
    try testing.expectEqual(@as(usize, 19), byte_count); // 19 bytes (multi-byte chars)

    // Test codepoint-aware slicing
    const codepoint_slice = try string.sliceCodepoints(utf8_string, 7, 9); // "世界"
    try testing.expectEqualStrings("世界", codepoint_slice.bytes);

    // Test that byte slicing in the middle of a codepoint would be caught
    // (This is more of a design verification than a runtime test)
    const byte_slice = try string.slice(utf8_string, 0, 7); // "Hello, "
    try testing.expectEqualStrings("Hello, ", byte_slice.bytes);
}

test "zero-copy operations - most operations work on slices without copying" {
    const testing_allocator = testing.allocator;

    const original_text = "Hello, World! This is a test string.";
    const original = try string.fromUtf8(testing_allocator, original_text);
    defer original.deinit();

    // Test zero-copy slicing
    const slice1 = try string.slice(original, 0, 5); // "Hello"
    const slice2 = try string.slice(original, 7, 12); // "World"

    // Slices should not own their data
    try testing.expect(slice1.allocator == null);
    try testing.expect(slice2.allocator == null);

    // Slices should point into original data
    try testing.expectEqualStrings("Hello", slice1.bytes);
    try testing.expectEqualStrings("World", slice2.bytes);

    // Test zero-copy iteration
    var codepoint_iter = string.iterateCodepoints(original);
    var codepoint_count: usize = 0;
    while (codepoint_iter.next()) |_| {
        codepoint_count += 1;
    }
    try testing.expectEqual(@as(usize, 36), codepoint_count);

    var byte_iter = string.iterateBytes(original);
    var byte_count: usize = 0;
    while (byte_iter.next()) |_| {
        byte_count += 1;
    }
    try testing.expectEqual(original_text.len, byte_count);
}

test "allocator sovereignty - string building requires explicit allocators" {
    const testing_allocator = testing.allocator;

    // Test string concatenation with explicit allocator
    const str1 = string.fromLiteral("Hello, ");
    const str2 = string.fromLiteral("World!");

    const strings = [_]string.String{ str1, str2 };
    const concatenated = try string.concat(testing_allocator, &strings);
    defer concatenated.deinit();

    try testing.expectEqualStrings("Hello, World!", concatenated.bytes);
    try testing.expect(concatenated.allocator != null);

    // Test string builder with explicit allocator
    var builder = string.StringBuilder.init(testing_allocator);
    defer builder.deinit();

    try builder.appendBytes("Hello");
    try builder.appendBytes(", ");
    try builder.append(string.fromLiteral("World!"));

    const built_string = try builder.toString();
    defer built_string.deinit();

    try testing.expectEqualStrings("Hello, World!", built_string.bytes);
    try testing.expect(built_string.allocator != null);
}

test "string comparison - explicit semantics" {
    const testing_allocator = testing.allocator;

    const str1 = try string.fromUtf8(testing_allocator, "Hello, World!");
    defer str1.deinit();

    const str2 = try string.fromUtf8(testing_allocator, "Hello, World!");
    defer str2.deinit();

    const str3 = string.fromLiteral("Hello, World!");
    const str4 = string.fromLiteral("Different String");

    // Test byte equality
    try testing.expect(string.equalBytes(str1, str2));
    try testing.expect(string.equalBytes(str1, str3));
    try testing.expect(!string.equalBytes(str1, str4));

    // Test codepoint equality (should be same as byte equality for valid UTF-8)
    try testing.expect(try string.equalCodepoints(str1, str2));
    try testing.expect(try string.equalCodepoints(str1, str3));
    try testing.expect(!try string.equalCodepoints(str1, str4));
}

test "string formatting with explicit allocation" {
    const testing_allocator = testing.allocator;

    const template = string.fromLiteral("Hello, {}! You have {} messages and {} is {}.");
    const args = [_]string.FormatArg{
        .{ .string = string.fromLiteral("Alice") },
        .{ .integer = 42 },
        .{ .string = string.fromLiteral("debugging") },
        .{ .boolean = true },
    };

    const formatted = try string.format(testing_allocator, template, &args);
    defer formatted.deinit();

    const expected = "Hello, Alice! You have 42 messages and debugging is true.";
    try testing.expectEqualStrings(expected, formatted.bytes);
    try testing.expect(formatted.allocator != null);
}

test "string splitting and joining" {
    const testing_allocator = testing.allocator;

    // Test splitting
    const original = string.fromLiteral("apple,banana,cherry,date");
    const parts = try string.split(testing_allocator, original, ",");
    defer testing_allocator.free(parts);

    try testing.expectEqual(@as(usize, 4), parts.len);
    try testing.expectEqualStrings("apple", parts[0].bytes);
    try testing.expectEqualStrings("banana", parts[1].bytes);
    try testing.expectEqualStrings("cherry", parts[2].bytes);
    try testing.expectEqualStrings("date", parts[3].bytes);

    // Test joining
    const rejoined = try string.join(testing_allocator, parts, ",");
    defer rejoined.deinit();

    try testing.expectEqualStrings("apple,banana,cherry,date", rejoined.bytes);

    // Test joining with different delimiter
    const pipe_joined = try string.join(testing_allocator, parts, " | ");
    defer pipe_joined.deinit();

    try testing.expectEqualStrings("apple | banana | cherry | date", pipe_joined.bytes);
}

test "UTF-8 codepoint iteration and validation" {
    const testing_allocator = testing.allocator;

    // Test string with various UTF-8 characters
    const utf8_text = "A🌍B世C界D"; // Mix of ASCII, emoji, and CJK
    const utf8_string = try string.fromUtf8(testing_allocator, utf8_text);
    defer utf8_string.deinit();

    // Test codepoint iteration
    var iter = string.iterateCodepoints(utf8_string);
    const expected_codepoints = [_]u32{ 'A', 0x1F30D, 'B', 0x4E16, 'C', 0x754C, 'D' };

    for (expected_codepoints) |expected| {
        const actual = iter.next();
        try testing.expect(actual != null);
        try testing.expectEqual(expected, actual.?);
    }

    // Should be no more codepoints
    try testing.expect(iter.next() == null);

    // Test codepoint count
    const count = try string.codepointCount(utf8_string);
    try testing.expectEqual(@as(usize, 7), count);
}

test "error handling and edge cases" {
    const testing_allocator = testing.allocator;

    // Test invalid UTF-8
    const invalid_utf8 = [_]u8{ 0xFF, 0xFE, 0xFD };
    try testing.expectError(string.StringError.InvalidUtf8, string.fromUtf8(testing_allocator, &invalid_utf8));

    // Test out of bounds slicing
    const test_string = string.fromLiteral("Hello");
    try testing.expectError(string.StringError.OutOfBounds, string.slice(test_string, 10, 20));
    try testing.expectError(string.StringError.OutOfBounds, string.slice(test_string, 3, 2)); // start > end

    // Test encoding mismatch
    const bytes_string = string.String{
        .bytes = "test",
        .encoding = .bytes,
        .allocator = null,
    };
    try testing.expectError(string.StringError.EncodingMismatch, string.codepointCount(bytes_string));
    try testing.expectError(string.StringError.EncodingMismatch, string.sliceCodepoints(bytes_string, 0, 1));

    // Test empty string operations
    const empty = string.fromLiteral("");
    try testing.expectEqual(@as(usize, 0), string.length(empty));
    try testing.expectEqual(@as(usize, 0), try string.codepointCount(empty));

    const empty_slice = try string.slice(empty, 0, 0);
    try testing.expectEqual(@as(usize, 0), string.length(empty_slice));
}

test "memory management and lifecycle" {
    const testing_allocator = testing.allocator;

    // Test that string literals don't allocate
    const literal = string.fromLiteral("This is a literal");
    try testing.expect(literal.allocator == null);
    // No need to deinit literals

    // Test that allocated strings properly track their allocator
    const allocated = try string.fromUtf8(testing_allocator, "This is allocated");
    try testing.expect(allocated.allocator != null);
    allocated.deinit(); // Should not leak

    // Test string builder lifecycle
    var builder = string.StringBuilder.init(testing_allocator);
    try builder.appendBytes("Test");
    try builder.appendBytes(" String");

    const built = try builder.toString();
    try testing.expectEqualStrings("Test String", built.bytes);

    // Clean up in correct order
    built.deinit();
    builder.deinit();
}

test "performance characteristics" {
    const testing_allocator = testing.allocator;

    // Test that string operations have reasonable performance
    const large_text = "This is a test string that will be repeated many times. " ** 1000;

    const start_time = compat_time.nanoTimestamp();

    const large_string = try string.fromUtf8(testing_allocator, large_text);
    defer large_string.deinit();

    // Test slicing performance (should be O(1))
    const slice1 = try string.slice(large_string, 0, 100);
    const slice2 = try string.slice(large_string, 1000, 2000);

    // Test iteration performance
    var iter = string.iterateBytes(large_string);
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }

    const end_time = compat_time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Verify correctness
    try testing.expectEqual(large_text.len, count);
    try testing.expectEqualStrings(large_text[0..100], slice1.bytes);
    try testing.expectEqualStrings(large_text[1000..2000], slice2.bytes);

    // Performance should be reasonable (less than 100ms for these operations)
    try testing.expect(duration_ms < 100.0);
}

test "string builder advanced operations" {
    const testing_allocator = testing.allocator;

    var builder = string.StringBuilder.init(testing_allocator);
    defer builder.deinit();

    // Test building a complex string
    try builder.appendBytes("Function: ");
    try builder.append(string.fromLiteral("processData"));
    try builder.appendBytes("(");

    const params = [_]string.String{
        string.fromLiteral("input"),
        string.fromLiteral("output"),
        string.fromLiteral("options"),
    };

    for (params, 0..) |param, i| {
        try builder.append(param);
        if (i < params.len - 1) {
            try builder.appendBytes(", ");
        }
    }

    try builder.appendBytes(")");

    const result = try builder.toString();
    defer result.deinit();

    const expected = "Function: processData(input, output, options)";
    try testing.expectEqualStrings(expected, result.bytes);
}

test "comprehensive UTF-8 edge cases" {
    const testing_allocator = testing.allocator;

    // Test various UTF-8 edge cases
    const edge_cases = [_][]const u8{
        "A", // Single ASCII
        "🌍", // Single emoji (4 bytes)
        "世", // Single CJK (3 bytes)
        "é", // Single accented (2 bytes)
        "", // Empty string
        "A🌍B世C界Dé", // Mixed characters
    };

    for (edge_cases) |case| {
        const test_string = try string.fromUtf8(testing_allocator, case);
        defer test_string.deinit();

        // Validate UTF-8
        try string.validateUtf8(case);

        // Test codepoint count
        const count = try string.codepointCount(test_string);
        const std_count = std.unicode.utf8CountCodepoints(case) catch unreachable;
        try testing.expectEqual(std_count, count);

        // Test iteration consistency
        var iter = string.iterateCodepoints(test_string);
        var iter_count: usize = 0;
        while (iter.next()) |_| {
            iter_count += 1;
        }
        try testing.expectEqual(count, iter_count);

        // Test round-trip through bytes
        const bytes = string.toBytes(test_string);
        try testing.expectEqualStrings(case, bytes);
    }
}
