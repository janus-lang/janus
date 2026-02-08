// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Standard Library - :core Profile Module
//!
//! The :core profile (aliases: :min, :teaching) provides the fundamental
//! building blocks for learning Janus and building simple applications.
//!
//! Design Principles:
//! - Simplicity first: No capabilities, no contexts, just functions
//! - Explicit allocation: All allocations require explicit allocators
//! - Deterministic execution: Single-threaded, predictable behavior
//! - Teaching-friendly: Clear error messages, intuitive APIs
//!
//! Available Types:
//! - i64, f64, bool, String, Array, HashMap
//!
//! Available Constructs:
//! - func, let, var, if, else, for, while, return

const std = @import("std");

// Re-export all :core profile modules
pub const io = @import("io.zig");
pub const fs = @import("fs.zig");
pub const string = @import("string.zig");
pub const convert = @import("convert.zig");
pub const array = @import("array.zig");
pub const context = @import("context.zig");
pub const time = @import("time.zig");

// =============================================================================
// CORE PROFILE TYPES
// =============================================================================

/// The fundamental signed integer type for :core profile
pub const Int = i64;

/// The fundamental floating-point type for :core profile
pub const Float = f64;

/// Boolean type (standard Zig bool)
pub const Bool = bool;

/// String type for :core profile - UTF-8 encoded
pub const String = []const u8;

/// Mutable string builder for :core profile
pub const StringBuilder = std.ArrayList(u8);

/// Generic dynamic array for :core profile
pub fn Array(comptime T: type) type {
    return std.ArrayListUnmanaged(T);
}

/// Generic hash map for :core profile
pub fn HashMap(comptime K: type, comptime V: type) type {
    return std.AutoHashMap(K, V);
}

/// String-keyed hash map for :core profile
pub fn StringMap(comptime V: type) type {
    return std.StringHashMap(V);
}

// =============================================================================
// CORE PROFILE ERROR TYPES
// =============================================================================

/// Unified error type for :core profile operations
pub const CoreError = error{
    // I/O errors
    FileNotFound,
    PermissionDenied,
    IoError,

    // String errors
    InvalidUtf8,
    InvalidFormat,

    // Conversion errors
    InvalidNumber,
    Overflow,

    // Collection errors
    OutOfBounds,
    KeyNotFound,

    // Memory errors
    OutOfMemory,
};

// =============================================================================
// VERSION AND METADATA
// =============================================================================

/// :core profile version
pub const version = struct {
    pub const major: u32 = 0;
    pub const minor: u32 = 1;
    pub const patch: u32 = 0;

    pub fn string() []const u8 {
        return "0.1.0";
    }
};

/// Profile metadata
pub const profile = struct {
    pub const name = "core";
    pub const aliases = [_][]const u8{ "min", "teaching" };
    pub const description = "Fundamental profile for learning and simple applications";

    /// Check if this profile supports a feature
    pub fn supportsFeature(feature: []const u8) bool {
        const supported = [_][]const u8{
            "basic_types",
            "functions",
            "control_flow",
            "arrays",
            "strings",
            "file_io",
            "console_io",
            "time",
        };

        for (supported) |f| {
            if (std.mem.eql(u8, feature, f)) return true;
        }
        return false;
    }
};

// =============================================================================
// TESTS
// =============================================================================

test "core profile types" {
    const allocator = std.testing.allocator;

    // Test Int
    const x: Int = 42;
    try std.testing.expectEqual(@as(Int, 42), x);

    // Test Float
    const y: Float = 3.14;
    try std.testing.expect(y > 3.0 and y < 4.0);

    // Test Bool
    const b: Bool = true;
    try std.testing.expect(b);

    // Test String
    const s: String = "Hello, Janus!";
    try std.testing.expectEqualStrings("Hello, Janus!", s);

    // Test Array
    var arr = Array(Int){};
    defer arr.deinit(allocator);
    try arr.append(allocator, 1);
    try arr.append(allocator, 2);
    try arr.append(allocator, 3);
    try std.testing.expectEqual(@as(usize, 3), arr.items.len);

    // Test HashMap
    var map = HashMap(Int, String).init(allocator);
    defer map.deinit();
    try map.put(1, "one");
    try map.put(2, "two");
    try std.testing.expectEqualStrings("one", map.get(1).?);
}

test "profile metadata" {
    try std.testing.expectEqualStrings("core", profile.name);
    try std.testing.expect(profile.supportsFeature("basic_types"));
    try std.testing.expect(profile.supportsFeature("file_io"));
    try std.testing.expect(!profile.supportsFeature("concurrency"));
    try std.testing.expect(!profile.supportsFeature("capabilities"));
}
