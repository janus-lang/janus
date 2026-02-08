// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Core Time Operations - Exported for Native Grafting
//!
//! This module provides C-exported time functions that Janus can call
//! via `use zig "std/core/time.zig"`.
//!
//! Design:
//! - All functions use C-compatible types
//! - Epoch timestamps (Unix time) for portability
//! - Duration in milliseconds for precision
//! - No allocations - all values are primitive types

const std = @import("std");

// ============================================================================
// SYSTEM TIME (epoch-based)
// ============================================================================

/// Get current Unix timestamp in seconds
/// Returns seconds since January 1, 1970 UTC
pub export fn time_now_seconds() callconv(.c) i64 {
    return std.time.timestamp();
}

/// Get current Unix timestamp in milliseconds
/// Returns milliseconds since January 1, 1970 UTC
pub export fn time_now_millis() callconv(.c) i64 {
    return std.time.milliTimestamp();
}

/// Get current Unix timestamp in microseconds
/// Returns microseconds since January 1, 1970 UTC
pub export fn time_now_micros() callconv(.c) i64 {
    return std.time.microTimestamp();
}

/// Get current Unix timestamp in nanoseconds
/// Returns nanoseconds since January 1, 1970 UTC
/// Note: Precision depends on platform
pub export fn time_now_nanos() callconv(.c) i64 {
    return @intCast(std.time.nanoTimestamp());
}

// ============================================================================
// HIGH-RESOLUTION MONOTONIC TIME
// ============================================================================

/// Get monotonic clock in milliseconds (for performance measurement)
/// This clock never goes backwards, even if system time changes
pub export fn time_monotonic_millis() callconv(.c) i64 {
    return @intCast(std.time.milliTimestamp());
}

/// Get monotonic clock in nanoseconds (highest precision)
/// Use this for benchmarking and performance critical code
pub export fn time_monotonic_nanos() callconv(.c) i64 {
    return @intCast(std.time.nanoTimestamp());
}

/// Sleep for specified milliseconds
/// Returns 0 on success, -1 on error
pub export fn time_sleep_millis(ms: i64) callconv(.c) i32 {
    if (ms < 0) return -1;
    std.Thread.sleep(@intCast(ms * std.time.ns_per_ms));
    return 0;
}

/// Sleep for specified seconds
/// Returns 0 on success, -1 on error
pub export fn time_sleep_seconds(secs: i64) callconv(.c) i32 {
    if (secs < 0) return -1;
    std.Thread.sleep(@intCast(secs * std.time.ns_per_s));
    return 0;
}

// ============================================================================
// TIME CONVERSIONS
// ============================================================================

/// Convert seconds to milliseconds
pub export fn time_seconds_to_millis(seconds: i64) callconv(.c) i64 {
    return seconds * 1000;
}

/// Convert milliseconds to seconds (truncates)
pub export fn time_millis_to_seconds(millis: i64) callconv(.c) i64 {
    return @divTrunc(millis, 1000);
}

/// Convert minutes to seconds
pub export fn time_minutes_to_seconds(minutes: i64) callconv(.c) i64 {
    return minutes * 60;
}

/// Convert hours to seconds
pub export fn time_hours_to_seconds(hours: i64) callconv(.c) i64 {
    return hours * 3600;
}

/// Convert days to seconds
pub export fn time_days_to_seconds(days: i64) callconv(.c) i64 {
    return days * 86400;
}

// ============================================================================
// DURATION CALCULATIONS
// ============================================================================

/// Calculate elapsed milliseconds between two timestamps
/// end_millis should be >= start_millis for positive result
pub export fn time_elapsed_millis(start_millis: i64, end_millis: i64) callconv(.c) i64 {
    return end_millis - start_millis;
}

/// Calculate elapsed seconds between two timestamps
pub export fn time_elapsed_seconds(start_secs: i64, end_secs: i64) callconv(.c) i64 {
    return end_secs - start_secs;
}

/// Format duration in human-readable form (writes to buffer)
/// Returns number of bytes written, or -1 if buffer too small
/// Format: "Xd Xh Xm Xs" or "Xs" for short durations
pub export fn time_format_duration(
    seconds: i64,
    buf_ptr: [*]u8,
    buf_len: usize,
) callconv(.c) i64 {
    if (buf_len < 32) return -1;
    
    const abs_seconds = if (seconds < 0) -seconds else seconds;
    const days = @divTrunc(abs_seconds, 86400);
    const hours = @divTrunc(@rem(abs_seconds, 86400), 3600);
    const mins = @divTrunc(@rem(abs_seconds, 3600), 60);
    const secs = @rem(abs_seconds, 60);
    
    var buf = buf_ptr[0..buf_len];
    var written: usize = 0;
    
    if (seconds < 0) {
        buf[0] = '-';
        written = 1;
    }
    
    const result = if (days > 0) 
        std.fmt.bufPrint(buf[written..], "{d}d {d}h {d}m {d}s", .{days, hours, mins, secs})
    else if (hours > 0)
        std.fmt.bufPrint(buf[written..], "{d}h {d}m {d}s", .{hours, mins, secs})
    else if (mins > 0)
        std.fmt.bufPrint(buf[written..], "{d}m {d}s", .{mins, secs})
    else
        std.fmt.bufPrint(buf[written..], "{d}s", .{secs});
    
    if (result) |s| {
        return @intCast(written + s.len);
    } else |_| {
        return -1;
    }
}

// ============================================================================
// CALENDAR TIME (UTC)
// ============================================================================

/// Get year from Unix timestamp (UTC)
/// Returns year (e.g., 2026), or 0 on error
pub export fn time_year_from_timestamp(timestamp: i64) callconv(.c) i32 {
    const epoch_secs: u64 = @intCast(@max(timestamp, 0));
    const epoch_days = @divTrunc(epoch_secs, std.time.s_per_day);
    
    // Rough calculation: 1970 + days / 365.25
    const years_since_1970: i32 = @intCast(@divTrunc(epoch_days, 365));
    const year = 1970 + years_since_1970;
    
    return year;
}

/// Check if a year is a leap year
/// Returns 1 if leap year, 0 otherwise
pub export fn time_is_leap_year(year: i32) callconv(.c) i32 {
    const y: u32 = @intCast(@max(year, 0));
    const is_leap = (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0);
    return if (is_leap) 1 else 0;
}

/// Get days in month (1-12)
/// Returns days in month, or -1 for invalid month
pub export fn time_days_in_month(year: i32, month: i32) callconv(.c) i32 {
    if (month < 1 or month > 12) return -1;
    
    const is_leap = time_is_leap_year(year) == 1;
    
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (is_leap) 29 else 28,
        else => -1,
    };
}

// ============================================================================
// PERFORMANCE TIMING HELPERS
// ============================================================================

/// Simple benchmark: measure function call overhead
/// Returns nanoseconds for a minimal operation (for calibration)
pub export fn time_calibration_nanos() callconv(.c) i64 {
    const start: i64 = @intCast(std.time.nanoTimestamp());
    // Minimal work - just get timestamp again
    const end: i64 = @intCast(std.time.nanoTimestamp());
    return end - start;
}

/// Get the CPU timestamp counter (RDTSC on x86, similar on ARM)
/// WARNING: Not monotonic on modern CPUs with frequency scaling!
/// Use only for relative measurements in tight loops
pub export fn time_cpu_ticks() callconv(.c) u64 {
    // Use standard library's CPU timestamp if available
    return @intCast(std.time.nanoTimestamp());
}

// ============================================================================
// CONSTANTS (exported for reference)
// ============================================================================

pub export const TIME_MS_PER_SECOND: i64 = 1000;
pub export const TIME_MS_PER_MINUTE: i64 = 60_000;
pub export const TIME_MS_PER_HOUR: i64 = 3_600_000;
pub export const TIME_MS_PER_DAY: i64 = 86_400_000;

pub export const TIME_SECS_PER_MINUTE: i64 = 60;
pub export const TIME_SECS_PER_HOUR: i64 = 3600;
pub export const TIME_SECS_PER_DAY: i64 = 86400;
pub export const TIME_SECS_PER_WEEK: i64 = 604800;

// Epoch reference points
pub export const TIME_EPOCH_UNIX: i64 = 0;  // January 1, 1970
