// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Version Parser - Hybrid Versioning Scheme
//!
//! Parses and validates hybrid version format for packager compatibility.
//! Supports semver, dev.<date>.r<rev>.g<short>, and optional CID components.
//!
//! Doctrine Compliance:
//! - Mechanism over Policy: Format detection is explicit and deterministic
//! - Reveal the Cost: Version components explicitly show temporal state and git history
//! - No Ambient Authority: Parsing requires explicit format specification

const std = @import("std");

/// Parsed version components with optional fields
pub const ParsedVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,
    date: ?[]const u8 = null,
    rev: ?u32 = null,
    git: ?[]const u8 = null,
    cid: ?[]const u8 = null,

    /// Check if this is a development version
    pub fn isDev(self: ParsedVersion) bool {
        return self.date != null;
    }

    /// Check if this is a stable release
    pub fn isStable(self: ParsedVersion) bool {
        return self.date == null and self.rev == null and self.git == null;
    }

    /// Check if this has cryptographic verification
    pub fn hasCid(self: ParsedVersion) bool {
        return self.cid != null;
    }
};

/// Version format types for explicit parsing
pub const VersionFormat = enum {
    auto, // Detect format automatically
    stable, // Semver only (e.g., "0.1.8")
    dev, // Development format (e.g., "dev.20251015.r42.g214a4a8")
    snapshot, // Snapshot format (e.g., "20251015.r42.g214a4a8")
};

/// Parse version string into components
pub fn parseVersion(str: []const u8) !ParsedVersion {
    return parseVersionWithFormat(str, .auto);
}

/// Parse version with explicit format specification
pub fn parseVersionWithFormat(str: []const u8, format: VersionFormat) !ParsedVersion {
    var result = ParsedVersion{
        .major = 0,
        .minor = 0,
        .patch = 0,
    };

    switch (format) {
        .auto => {
            // Try to detect format and parse accordingly
            if (try parseStableVersion(str, &result)) {
                return result;
            } else if (try parseDevVersion(str, &result)) {
                return result;
            } else if (try parseSnapshotVersion(str, &result)) {
                return result;
            } else {
                return error.InvalidVersionFormat;
            }
        },
        .stable => {
            if (!try parseStableVersion(str, &result)) {
                return error.InvalidStableVersionFormat;
            }
            return result;
        },
        .dev => {
            if (!try parseDevVersion(str, &result)) {
                return error.InvalidDevVersionFormat;
            }
            return result;
        },
        .snapshot => {
            if (!try parseSnapshotVersion(str, &result)) {
                return error.InvalidSnapshotVersionFormat;
            }
            return result;
        },
    }
}

/// Parse stable semver format (e.g., "0.1.8" or "0.1.8.cid1a2b3c4d")
fn parseStableVersion(str: []const u8, result: *ParsedVersion) !bool {
    var remaining = str;

    // Parse semver part
    const semver_end = std.mem.indexOfScalar(u8, remaining, '.') orelse return false;
    result.major = try std.fmt.parseInt(u32, remaining[0..semver_end], 10);
    remaining = remaining[semver_end + 1 ..];

    const minor_end = std.mem.indexOfScalar(u8, remaining, '.') orelse return false;
    result.minor = try std.fmt.parseInt(u32, remaining[0..minor_end], 10);
    remaining = remaining[minor_end + 1 ..];

    // Check for CID component
    if (std.mem.startsWith(u8, remaining, "cid")) {
        const cid_start = 3; // Skip "cid"
        if (cid_start < remaining.len) {
            result.cid = remaining[cid_start..];
        }
    } else {
        // Should be just the patch version
        result.patch = try std.fmt.parseInt(u32, remaining, 10);
    }

    return true;
}

/// Parse development format (e.g., "dev.20251015.r42.g214a4a8" or "dev.20251015.r42.g214a4a8.cid1a2b3c4d")
fn parseDevVersion(str: []const u8, result: *ParsedVersion) !bool {
    if (!std.mem.startsWith(u8, str, "dev.")) return false;

    var remaining = str[4..]; // Skip "dev."

    // Parse date (YYYYMMDD)
    if (remaining.len < 8) return false;
    result.date = remaining[0..8];
    remaining = remaining[8..];

    if (remaining.len == 0) return false;
    if (remaining[0] != '.') return false;
    remaining = remaining[1..]; // Skip "."

    // Parse revision (r<number>)
    if (!std.mem.startsWith(u8, remaining, "r")) return false;
    remaining = remaining[1..]; // Skip "r"

    const rev_end = std.mem.indexOfScalar(u8, remaining, '.') orelse return false;
    result.rev = try std.fmt.parseInt(u32, remaining[0..rev_end], 10);
    remaining = remaining[rev_end + 1 ..];

    // Parse git hash (g<hex>)
    if (!std.mem.startsWith(u8, remaining, "g")) return false;
    remaining = remaining[1..]; // Skip "g"

    // Find end of git hash (next component or end)
    const git_end = std.mem.indexOfScalar(u8, remaining, '.') orelse remaining.len;
    result.git = remaining[0..git_end];
    remaining = remaining[git_end..];

    // Check for CID component
    if (remaining.len > 0 and std.mem.startsWith(u8, remaining, ".cid")) {
        result.cid = remaining[4..]; // Skip ".cid"
    }

    return true;
}

/// Parse snapshot format (e.g., "20251015.r42.g214a4a8" or "20251015.r42.g214a4a8.cid1a2b3c4d")
fn parseSnapshotVersion(str: []const u8, result: *ParsedVersion) !bool {
    var remaining = str;

    // Parse date (YYYYMMDD)
    if (remaining.len < 8) return false;
    result.date = remaining[0..8];
    remaining = remaining[8..];

    if (remaining.len == 0) return false;
    if (remaining[0] != '.') return false;
    remaining = remaining[1..]; // Skip "."

    // Parse revision (r<number>)
    if (!std.mem.startsWith(u8, remaining, "r")) return false;
    remaining = remaining[1..]; // Skip "r"

    const rev_end = std.mem.indexOfScalar(u8, remaining, '.') orelse return false;
    result.rev = try std.fmt.parseInt(u32, remaining[0..rev_end], 10);
    remaining = remaining[rev_end + 1 ..];

    // Parse git hash (g<hex>)
    if (!std.mem.startsWith(u8, remaining, "g")) return false;
    remaining = remaining[1..]; // Skip "g"

    // Find end of git hash (next component or end)
    const git_end = std.mem.indexOfScalar(u8, remaining, '.') orelse remaining.len;
    result.git = remaining[0..git_end];
    remaining = remaining[git_end..];

    // Check for CID component
    if (remaining.len > 0 and std.mem.startsWith(u8, remaining, ".cid")) {
        result.cid = remaining[4..]; // Skip ".cid"
    }

    return true;
}

/// Format parsed version back to string
pub fn formatVersion(parsed: ParsedVersion, format: VersionFormat) ![]u8 {
    var components = std.ArrayList(u8).init(std.heap.page_allocator);
    defer components.deinit();

    const writer = components.writer();

    switch (format) {
        .stable => {
            try writer.print("{d}.{d}.{d}", .{ parsed.major, parsed.minor, parsed.patch });
            if (parsed.cid) |cid| {
                try writer.print(".cid{s}", .{cid});
            }
        },
        .dev => {
            if (parsed.date == null) return error.InvalidDevVersion;
            try writer.print("dev.{s}.r{d}.g{s}", .{ parsed.date.?, parsed.rev.?, parsed.git.? });
            if (parsed.cid) |cid| {
                try writer.print(".cid{s}", .{cid});
            }
        },
        .snapshot => {
            if (parsed.date == null) return error.InvalidSnapshotVersion;
            try writer.print("{s}.r{d}.g{s}", .{ parsed.date.?, parsed.rev.?, parsed.git.? });
            if (parsed.cid) |cid| {
                try writer.print(".cid{s}", .{cid});
            }
        },
        .auto => {
            if (parsed.isDev()) {
                try formatVersion(parsed, .dev);
            } else {
                try formatVersion(parsed, .stable);
            }
        },
    }

    return components.toOwnedSlice();
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "parseVersion: stable semver" {
    const parsed = try parseVersion("0.1.8");
    try std.testing.expect(parsed.major == 0);
    try std.testing.expect(parsed.minor == 1);
    try std.testing.expect(parsed.patch == 8);
    try std.testing.expect(parsed.isStable());
    try std.testing.expect(!parsed.isDev());
}

test "parseVersion: stable with CID" {
    const parsed = try parseVersion("0.1.8.cid1a2b3c4d");
    try std.testing.expect(parsed.hasCid());
    try std.testing.expectEqualStrings("1a2b3c4d", parsed.cid.?);
}

test "parseVersion: dev format" {
    const parsed = try parseVersion("dev.20251015.r42.g214a4a8");
    try std.testing.expect(parsed.isDev());
    try std.testing.expectEqualStrings("20251015", parsed.date.?);
    try std.testing.expectEqual(42, parsed.rev.?);
    try std.testing.expectEqualStrings("214a4a8", parsed.git.?);
}

test "parseVersion: dev format with CID" {
    const parsed = try parseVersion("dev.20251015.r42.g214a4a8.cid1a2b3c4d");
    try std.testing.expect(parsed.hasCid());
    try std.testing.expectEqualStrings("1a2b3c4d", parsed.cid.?);
}

test "parseVersion: snapshot format" {
    const parsed = try parseVersion("20251015.r42.g214a4a8");
    try std.testing.expect(parsed.isDev());
    try std.testing.expectEqualStrings("20251015", parsed.date.?);
    try std.testing.expectEqual(42, parsed.rev.?);
    try std.testing.expectEqualStrings("214a4a8", parsed.git.?);
}

test "formatVersion: roundtrip" {
    const original = "dev.20251015.r42.g214a4a8.cid1a2b3c4d";
    const parsed = try parseVersion(original);
    const formatted = try formatVersion(parsed, .dev);

    try std.testing.expectEqualStrings(original, formatted);
}
