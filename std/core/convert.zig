// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Standard Library - :core Profile Type Conversion Module
//!
//! Simple, teaching-friendly type conversion operations.
//! Explicit about what can fail and what succeeds.
//!
//! Functions:
//! - toString(value)     - Convert any value to string
//! - toInt(s)            - Parse string as integer
//! - toFloat(s)          - Parse string as float
//! - toBool(s)           - Parse string as boolean
//! - intToFloat(i)       - Convert integer to float
//! - floatToInt(f)       - Convert float to integer (truncates)

const std = @import("std");

/// Conversion errors for :core profile
pub const ConvertError = error{
    InvalidNumber,
    InvalidBoolean,
    Overflow,
    OutOfMemory,
};

// =============================================================================
// TO STRING CONVERSIONS
// =============================================================================

/// Convert an integer to string
/// Caller owns the returned memory.
///
/// Example:
/// ```janus
/// let s = convert.intToString(42)  // "42"
/// ```
pub fn intToString(allocator: std.mem.Allocator, value: i64) ConvertError![]u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{value}) catch return ConvertError.OutOfMemory;
}

/// Convert a float to string
/// Caller owns the returned memory.
///
/// Example:
/// ```janus
/// let s = convert.floatToString(3.14)  // "3.14"
/// ```
pub fn floatToString(allocator: std.mem.Allocator, value: f64) ConvertError![]u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{value}) catch return ConvertError.OutOfMemory;
}

/// Convert a boolean to string
/// Returns "true" or "false" (no allocation needed).
///
/// Example:
/// ```janus
/// let s = convert.boolToString(true)  // "true"
/// ```
pub fn boolToString(value: bool) []const u8 {
    return if (value) "true" else "false";
}

/// Generic toString for common types (Zig comptime magic)
/// Caller owns the returned memory for allocated types.
pub fn toString(allocator: std.mem.Allocator, value: anytype) ConvertError![]u8 {
    const T = @TypeOf(value);

    if (T == bool) {
        return allocator.dupe(u8, boolToString(value)) catch return ConvertError.OutOfMemory;
    } else if (T == i64 or T == i32 or T == i16 or T == i8 or
        T == u64 or T == u32 or T == u16 or T == u8 or
        T == isize or T == usize)
    {
        return std.fmt.allocPrint(allocator, "{d}", .{value}) catch return ConvertError.OutOfMemory;
    } else if (T == f64 or T == f32) {
        return std.fmt.allocPrint(allocator, "{d}", .{value}) catch return ConvertError.OutOfMemory;
    } else if (T == []const u8 or T == []u8) {
        return allocator.dupe(u8, value) catch return ConvertError.OutOfMemory;
    } else {
        return std.fmt.allocPrint(allocator, "{any}", .{value}) catch return ConvertError.OutOfMemory;
    }
}

// =============================================================================
// FROM STRING CONVERSIONS
// =============================================================================

/// Parse a string as an integer (i64)
/// Accepts decimal, hex (0x), octal (0o), and binary (0b) formats.
///
/// Example:
/// ```janus
/// let n = convert.toInt("42")      // 42
/// let h = convert.toInt("0xFF")    // 255
/// ```
pub fn toInt(s: []const u8) ConvertError!i64 {
    // Trim whitespace
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    if (trimmed.len == 0) return ConvertError.InvalidNumber;

    return std.fmt.parseInt(i64, trimmed, 0) catch |err| {
        return switch (err) {
            error.Overflow => ConvertError.Overflow,
            error.InvalidCharacter => ConvertError.InvalidNumber,
        };
    };
}

/// Parse a string as an integer with specific radix
pub fn toIntRadix(s: []const u8, radix: u8) ConvertError!i64 {
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    if (trimmed.len == 0) return ConvertError.InvalidNumber;

    return std.fmt.parseInt(i64, trimmed, radix) catch |err| {
        return switch (err) {
            error.Overflow => ConvertError.Overflow,
            error.InvalidCharacter => ConvertError.InvalidNumber,
        };
    };
}

/// Parse a string as unsigned integer (u64)
pub fn toUInt(s: []const u8) ConvertError!u64 {
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    if (trimmed.len == 0) return ConvertError.InvalidNumber;

    return std.fmt.parseInt(u64, trimmed, 0) catch |err| {
        return switch (err) {
            error.Overflow => ConvertError.Overflow,
            error.InvalidCharacter => ConvertError.InvalidNumber,
        };
    };
}

/// Parse a string as a float (f64)
///
/// Example:
/// ```janus
/// let f = convert.toFloat("3.14")   // 3.14
/// let e = convert.toFloat("1e-10")  // 0.0000000001
/// ```
pub fn toFloat(s: []const u8) ConvertError!f64 {
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    if (trimmed.len == 0) return ConvertError.InvalidNumber;

    return std.fmt.parseFloat(f64, trimmed) catch return ConvertError.InvalidNumber;
}

/// Parse a string as a boolean
/// Accepts: "true", "false", "1", "0", "yes", "no" (case-insensitive)
///
/// Example:
/// ```janus
/// let b = convert.toBool("true")   // true
/// let n = convert.toBool("no")     // false
/// ```
pub fn toBool(s: []const u8) ConvertError!bool {
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    if (trimmed.len == 0) return ConvertError.InvalidBoolean;

    // Create lowercase version for comparison
    var lower: [10]u8 = undefined;
    if (trimmed.len > lower.len) return ConvertError.InvalidBoolean;

    for (trimmed, 0..) |c, i| {
        lower[i] = std.ascii.toLower(c);
    }
    const lower_slice = lower[0..trimmed.len];

    if (std.mem.eql(u8, lower_slice, "true") or
        std.mem.eql(u8, lower_slice, "1") or
        std.mem.eql(u8, lower_slice, "yes") or
        std.mem.eql(u8, lower_slice, "on"))
    {
        return true;
    }

    if (std.mem.eql(u8, lower_slice, "false") or
        std.mem.eql(u8, lower_slice, "0") or
        std.mem.eql(u8, lower_slice, "no") or
        std.mem.eql(u8, lower_slice, "off"))
    {
        return false;
    }

    return ConvertError.InvalidBoolean;
}

// =============================================================================
// NUMERIC CONVERSIONS
// =============================================================================

/// Convert integer to float
/// Always succeeds for valid integers within f64 range.
pub fn intToFloat(value: i64) f64 {
    return @floatFromInt(value);
}

/// Convert float to integer (truncates toward zero)
///
/// Example:
/// ```janus
/// let n = convert.floatToInt(3.7)   // 3
/// let m = convert.floatToInt(-2.3)  // -2
/// ```
pub fn floatToInt(value: f64) ConvertError!i64 {
    if (value != value) return ConvertError.InvalidNumber; // NaN check
    if (value > @as(f64, @floatFromInt(std.math.maxInt(i64))) or
        value < @as(f64, @floatFromInt(std.math.minInt(i64))))
    {
        return ConvertError.Overflow;
    }
    return @intFromFloat(value);
}

/// Convert float to integer with rounding
pub fn floatToIntRounded(value: f64) ConvertError!i64 {
    if (value != value) return ConvertError.InvalidNumber; // NaN check
    const rounded = @round(value);
    if (rounded > @as(f64, @floatFromInt(std.math.maxInt(i64))) or
        rounded < @as(f64, @floatFromInt(std.math.minInt(i64))))
    {
        return ConvertError.Overflow;
    }
    return @intFromFloat(rounded);
}

/// Convert float to integer (floor - round toward negative infinity)
pub fn floatToIntFloor(value: f64) ConvertError!i64 {
    if (value != value) return ConvertError.InvalidNumber;
    const floored = @floor(value);
    if (floored > @as(f64, @floatFromInt(std.math.maxInt(i64))) or
        floored < @as(f64, @floatFromInt(std.math.minInt(i64))))
    {
        return ConvertError.Overflow;
    }
    return @intFromFloat(floored);
}

/// Convert float to integer (ceil - round toward positive infinity)
pub fn floatToIntCeil(value: f64) ConvertError!i64 {
    if (value != value) return ConvertError.InvalidNumber;
    const ceiled = @ceil(value);
    if (ceiled > @as(f64, @floatFromInt(std.math.maxInt(i64))) or
        ceiled < @as(f64, @floatFromInt(std.math.minInt(i64))))
    {
        return ConvertError.Overflow;
    }
    return @intFromFloat(ceiled);
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/// Check if a string represents a valid integer
pub fn isValidInt(s: []const u8) bool {
    _ = toInt(s) catch return false;
    return true;
}

/// Check if a string represents a valid float
pub fn isValidFloat(s: []const u8) bool {
    _ = toFloat(s) catch return false;
    return true;
}

/// Check if a string represents a valid boolean
pub fn isValidBool(s: []const u8) bool {
    _ = toBool(s) catch return false;
    return true;
}

/// Parse with default value on failure
pub fn toIntOrDefault(s: []const u8, default: i64) i64 {
    return toInt(s) catch default;
}

/// Parse with default value on failure
pub fn toFloatOrDefault(s: []const u8, default: f64) f64 {
    return toFloat(s) catch default;
}

/// Parse with default value on failure
pub fn toBoolOrDefault(s: []const u8, default: bool) bool {
    return toBool(s) catch default;
}

// =============================================================================
// FORMATTING HELPERS
// =============================================================================

/// Format an integer with thousand separators
/// Caller owns the returned memory.
pub fn formatIntWithCommas(allocator: std.mem.Allocator, value: i64) ConvertError![]u8 {
    const str = try intToString(allocator, if (value < 0) -value else value);
    defer allocator.free(str);

    // Calculate number of commas needed
    const num_commas = if (str.len > 0) (str.len - 1) / 3 else 0;
    const new_len = str.len + num_commas + @as(usize, if (value < 0) 1 else 0);

    const result = allocator.alloc(u8, new_len) catch return ConvertError.OutOfMemory;

    var write_pos: usize = 0;
    if (value < 0) {
        result[0] = '-';
        write_pos = 1;
    }

    var digits_written: usize = 0;
    const first_group_size = str.len - (num_commas * 3);

    for (str, 0..) |c, i| {
        if (digits_written > 0 and (str.len - i) % 3 == 0) {
            result[write_pos] = ',';
            write_pos += 1;
        }
        result[write_pos] = c;
        write_pos += 1;
        digits_written += 1;
        _ = first_group_size;
    }

    return result;
}

/// Format a float with specified decimal places
/// Caller owns the returned memory.
pub fn formatFloat(allocator: std.mem.Allocator, value: f64, decimal_places: u8) ConvertError![]u8 {
    // Use a buffer for formatting
    var buf: [64]u8 = undefined;
    const fmt_str = switch (decimal_places) {
        0 => "{d:.0}",
        1 => "{d:.1}",
        2 => "{d:.2}",
        3 => "{d:.3}",
        4 => "{d:.4}",
        5 => "{d:.5}",
        6 => "{d:.6}",
        else => "{d}",
    };

    const len = (std.fmt.bufPrint(&buf, fmt_str, .{value}) catch return ConvertError.OutOfMemory).len;
    return allocator.dupe(u8, buf[0..len]) catch return ConvertError.OutOfMemory;
}

// =============================================================================
// TESTS
// =============================================================================

test "integer conversions" {
    const allocator = std.testing.allocator;

    // toInt
    try std.testing.expectEqual(@as(i64, 42), try toInt("42"));
    try std.testing.expectEqual(@as(i64, -42), try toInt("-42"));
    try std.testing.expectEqual(@as(i64, 255), try toInt("0xFF"));
    try std.testing.expectEqual(@as(i64, 8), try toInt("0o10"));
    try std.testing.expectEqual(@as(i64, 5), try toInt("0b101"));
    try std.testing.expectError(ConvertError.InvalidNumber, toInt("abc"));
    try std.testing.expectError(ConvertError.InvalidNumber, toInt(""));

    // intToString
    const s42 = try intToString(allocator, 42);
    defer allocator.free(s42);
    try std.testing.expectEqualStrings("42", s42);

    const sneg = try intToString(allocator, -123);
    defer allocator.free(sneg);
    try std.testing.expectEqualStrings("-123", sneg);
}

test "float conversions" {
    const allocator = std.testing.allocator;

    // toFloat
    try std.testing.expectEqual(@as(f64, 3.14), try toFloat("3.14"));
    try std.testing.expectEqual(@as(f64, -2.5), try toFloat("-2.5"));
    try std.testing.expectEqual(@as(f64, 1e10), try toFloat("1e10"));
    try std.testing.expectError(ConvertError.InvalidNumber, toFloat("abc"));

    // floatToString
    const sf = try floatToString(allocator, 3.14);
    defer allocator.free(sf);
    try std.testing.expect(std.mem.startsWith(u8, sf, "3.14"));
}

test "boolean conversions" {
    try std.testing.expect(try toBool("true"));
    try std.testing.expect(try toBool("TRUE"));
    try std.testing.expect(try toBool("1"));
    try std.testing.expect(try toBool("yes"));
    try std.testing.expect(!try toBool("false"));
    try std.testing.expect(!try toBool("FALSE"));
    try std.testing.expect(!try toBool("0"));
    try std.testing.expect(!try toBool("no"));
    try std.testing.expectError(ConvertError.InvalidBoolean, toBool("maybe"));

    try std.testing.expectEqualStrings("true", boolToString(true));
    try std.testing.expectEqualStrings("false", boolToString(false));
}

test "numeric type conversions" {
    try std.testing.expectEqual(@as(f64, 42.0), intToFloat(42));
    try std.testing.expectEqual(@as(i64, 3), try floatToInt(3.7));
    try std.testing.expectEqual(@as(i64, -2), try floatToInt(-2.3));
    try std.testing.expectEqual(@as(i64, 4), try floatToIntRounded(3.7));
    try std.testing.expectEqual(@as(i64, 3), try floatToIntFloor(3.7));
    try std.testing.expectEqual(@as(i64, 4), try floatToIntCeil(3.1));
}

test "validation functions" {
    try std.testing.expect(isValidInt("42"));
    try std.testing.expect(isValidInt("-100"));
    try std.testing.expect(!isValidInt("abc"));

    try std.testing.expect(isValidFloat("3.14"));
    try std.testing.expect(isValidFloat("-1e5"));
    try std.testing.expect(!isValidFloat("abc"));

    try std.testing.expect(isValidBool("true"));
    try std.testing.expect(isValidBool("no"));
    try std.testing.expect(!isValidBool("maybe"));
}

test "default value parsers" {
    try std.testing.expectEqual(@as(i64, 42), toIntOrDefault("42", 0));
    try std.testing.expectEqual(@as(i64, 0), toIntOrDefault("abc", 0));
    try std.testing.expectEqual(@as(f64, 3.14), toFloatOrDefault("3.14", 0.0));
    try std.testing.expectEqual(@as(f64, 0.0), toFloatOrDefault("abc", 0.0));
    try std.testing.expect(toBoolOrDefault("true", false));
    try std.testing.expect(!toBoolOrDefault("abc", false));
}
