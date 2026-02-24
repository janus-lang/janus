/// Zig 0.16 compat: timestamp functions.
/// Replaces std.time.nanoTimestamp() and std.time.timestamp() which were removed.
const std = @import("std");

/// Returns nanoseconds since epoch (CLOCK_REALTIME). Replaces std.time.nanoTimestamp().
pub fn nanoTimestamp() i128 {
    var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.os.linux.clock_gettime(.REALTIME, &ts);
    return @as(i128, ts.sec) * 1_000_000_000 + @as(i128, ts.nsec);
}

/// Returns seconds since epoch. Replaces std.time.timestamp().
pub fn timestamp() i64 {
    var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.os.linux.clock_gettime(.REALTIME, &ts);
    return @intCast(ts.sec);
}

/// Returns milliseconds since epoch. Replaces std.time.milliTimestamp().
pub fn milliTimestamp() i64 {
    var ts: std.os.linux.timespec = .{ .sec = 0, .nsec = 0 };
    _ = std.os.linux.clock_gettime(.REALTIME, &ts);
    return @as(i64, ts.sec) * 1000 + @divFloor(@as(i64, ts.nsec), 1_000_000);
}

/// Sleep for the given number of nanoseconds. Replaces std.Thread.sleep() removed in Zig 0.16.
pub fn sleep(ns: u64) void {
    const secs = ns / 1_000_000_000;
    const rem_ns = ns % 1_000_000_000;
    var req: std.os.linux.timespec = .{
        .sec = @intCast(secs),
        .nsec = @intCast(rem_ns),
    };
    while (true) {
        var rem: std.os.linux.timespec = .{ .sec = 0, .nsec = 0 };
        const rc = std.os.linux.nanosleep(&req, &rem);
        if (rc == 0) return;
        // EINTR — interrupted by signal, retry with remaining time
        req = rem;
    }
}
