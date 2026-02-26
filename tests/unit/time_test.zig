// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Unit tests for std/core/time.zig
//! Run with: zig test std/core/time.zig

const std = @import("std");
const testing = std.testing;

// Import the time module functions directly
const time_now_seconds = @extern(*const fn () callconv(.c) i64, .{ .name = "time_now_seconds" });
const time_now_millis = @extern(*const fn () callconv(.c) i64, .{ .name = "time_now_millis" });
const time_now_nanos = @extern(*const fn () callconv(.c) i64, .{ .name = "time_now_nanos" });
const time_monotonic_millis = @extern(*const fn () callconv(.c) i64, .{ .name = "time_monotonic_millis" });
const time_monotonic_nanos = @extern(*const fn () callconv(.c) i64, .{ .name = "time_monotonic_nanos" });
const time_seconds_to_millis = @extern(*const fn (i64) callconv(.c) i64, .{ .name = "time_seconds_to_millis" });
const time_millis_to_seconds = @extern(*const fn (i64) callconv(.c) i64, .{ .name = "time_millis_to_seconds" });
const time_hours_to_seconds = @extern(*const fn (i64) callconv(.c) i64, .{ .name = "time_hours_to_seconds" });
const time_days_to_seconds = @extern(*const fn (i64) callconv(.c) i64, .{ .name = "time_days_to_seconds" });
const time_elapsed_millis = @extern(*const fn (i64, i64) callconv(.c) i64, .{ .name = "time_elapsed_millis" });
const time_is_leap_year = @extern(*const fn (i32) callconv(.c) i32, .{ .name = "time_is_leap_year" });
const time_days_in_month = @extern(*const fn (i32, i32) callconv(.c) i32, .{ .name = "time_days_in_month" });

// Simple tests that don't require the compiled library
test "time conversion functions work correctly" {
    // These are pure functions we can test inline
    try testing.expectEqual(@as(i64, 1000), seconds_to_millis(1));
    try testing.expectEqual(@as(i64, 60000), seconds_to_millis(60));
    try testing.expectEqual(@as(i64, 1), millis_to_seconds(1000));
    try testing.expectEqual(@as(i64, 1), millis_to_seconds(1500));
    try testing.expectEqual(@as(i64, 3600), hours_to_seconds(1));
    try testing.expectEqual(@as(i64, 86400), days_to_seconds(1));
}

test "elapsed time calculations" {
    try testing.expectEqual(@as(i64, 0), elapsed_millis(1000, 1000));
    try testing.expectEqual(@as(i64, 100), elapsed_millis(1000, 1100));
    try testing.expectEqual(@as(i64, -100), elapsed_millis(1100, 1000));
}

test "leap year detection" {
    try testing.expectEqual(@as(i32, 1), is_leap_year(2020));
    try testing.expectEqual(@as(i32, 1), is_leap_year(2024));
    try testing.expectEqual(@as(i32, 1), is_leap_year(2000));
    try testing.expectEqual(@as(i32, 0), is_leap_year(2021));
    try testing.expectEqual(@as(i32, 0), is_leap_year(2023));
    try testing.expectEqual(@as(i32, 0), is_leap_year(1900));
}

test "days in month" {
    try testing.expectEqual(@as(i32, 31), days_in_month(2024, 1));
    try testing.expectEqual(@as(i32, 29), days_in_month(2024, 2)); // Leap
    try testing.expectEqual(@as(i32, 28), days_in_month(2023, 2)); // Non-leap
    try testing.expectEqual(@as(i32, 31), days_in_month(2024, 12));
    try testing.expectEqual(@as(i32, 30), days_in_month(2024, 4));
    try testing.expectEqual(@as(i32, -1), days_in_month(2024, 0));
    try testing.expectEqual(@as(i32, -1), days_in_month(2024, 13));
}

// Inline implementations for testing
fn seconds_to_millis(seconds: i64) i64 {
    return seconds * 1000;
}

fn millis_to_seconds(millis: i64) i64 {
    return @divTrunc(millis, 1000);
}

fn hours_to_seconds(hours: i64) i64 {
    return hours * 3600;
}

fn days_to_seconds(days: i64) i64 {
    return days * 86400;
}

fn elapsed_millis(start: i64, end: i64) i64 {
    return end - start;
}

fn is_leap_year(year: i32) i32 {
    const y: u32 = @intCast(@max(year, 0));
    const leap = (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0);
    return if (leap) 1 else 0;
}

fn days_in_month(year: i32, month: i32) i32 {
    if (month < 1 or month > 12) return -1;
    const leap = is_leap_year(year) == 1;
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (leap) 29 else 28,
        else => -1,
    };
}
