// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - Main Module
// Demonstrates tri-signature pattern across all standard library modules

const std = @import("std");

// =============================================================================
// CORE MODULES: Foundation for all profiles
// =============================================================================

/// Core types and allocator patterns (available in all profiles)
pub const core = @import("core.zig");

/// I/O operations with capability security (available in all profiles)
pub const io = @import("io.zig");

// ===== CONVENIENCE FUNCTIONS FOR :MIN PROFILE =====

/// Simple print function - available in all profiles, no capabilities required
/// This is the "Hello, World" function that just works
pub const print = io.print;

/// Print with newline - convenience for all profiles
pub const println = io.println;

/// String operations with encoding honesty (available in all profiles)
pub const string = @import("string.zig");

// =============================================================================
// PROFILE-SPECIFIC MODULES: Progressive capability enhancement
// =============================================================================

/// Context module - structured concurrency and cancellation
/// Available in: :go, :full profiles
pub const context = @import("context.zig");

/// Capabilities module - capability-based security
/// Available in: :full profile only
pub const capabilities = @import("capabilities.zig");

// =============================================================================
// DOMAIN MODULES: Tri-signature pattern implementations
// =============================================================================

/// File system operations with tri-signature pattern
/// - :min: fs.read(path, allocator)
/// - :go: fs.read_with_context(path, ctx, allocator)
/// - :full: fs.read_with_capability(path, cap, allocator)
pub const fs = @import("fs.zig");

/// Network HTTP operations with tri-signature pattern
/// - :min: http.get(url, allocator)
/// - :go: http.get_with_context(url, ctx, allocator)
/// - :full: http.get_with_capability(url, cap, allocator)
pub const http = @import("net/http.zig");

/// Database operations with tri-signature pattern
/// - :min: db.query(sql, allocator)
/// - :go: db.query_with_context(sql, ctx, allocator)
/// - :full: db.query_with_capability(sql, cap, allocator)
pub const db = @import("db.zig");

// =============================================================================
// PROFILE COMPATIBILITY LAYER: Unified API across profiles
// =============================================================================

/// Profile-aware standard library interface
/// Provides unified API that adapts to the current profile
pub const ProfileAware = struct {
    /// Current profile detection (would be set by compiler)
    pub const current_profile = .min; // Default to :min for safety

    /// Profile-aware file operations
    pub const File = struct {
        /// Read file with profile-appropriate signature
        pub fn read(args: anytype) fs.FsError![]u8 {
            return fs.read_file(args);
        }

        /// Write file with profile-appropriate signature
        pub fn write(args: anytype) fs.FsError!void {
            return fs.write_file(args);
        }

        /// Get file info with profile-appropriate signature
        pub fn info(args: anytype) fs.FsError!fs.FileInfo {
            const ArgsType = @TypeOf(args);
            const fields = @typeInfo(ArgsType).Struct.fields;

            if (fields.len == 2) {
                return fs.file_info_min(args.path, args.allocator);
            } else if (fields.len == 3 and @hasField(ArgsType, "ctx")) {
                return fs.file_info_go(args.path, args.ctx, args.allocator);
            } else if (fields.len == 3 and @hasField(ArgsType, "cap")) {
                return fs.file_info_full(args.path, args.cap, args.allocator);
            } else {
                @compileError("Invalid arguments for file info - check profile requirements");
            }
        }
    };

    /// Profile-aware HTTP operations
    pub const Http = struct {
        /// HTTP GET with profile-appropriate signature
        pub fn get(args: anytype) http.HttpError!http.HttpResponse {
            return http.http_get(args);
        }

        /// HTTP POST with profile-appropriate signature (placeholder)
        pub fn post(args: anytype) http.HttpError!http.HttpResponse {
            // Would implement similar tri-signature pattern for POST
            _ = args;
            @compileError("HTTP POST not yet implemented");
        }
    };

    /// Profile-aware database operations
    pub const Database = struct {
        /// Database query with profile-appropriate signature
        pub fn query(args: anytype) db.DbError!db.ResultSet {
            return db.query(args);
        }

        /// Begin transaction with profile-appropriate signature
        pub fn begin_transaction(args: anytype) db.DbError!db.Transaction {
            return db.begin_transaction(args);
        }

        /// Select operation with profile-appropriate signature
        pub fn select(table: []const u8, where_clause: ?[]const u8, args: anytype) db.DbError!db.ResultSet {
            return db.select(table, where_clause, args);
        }
    };
};

// =============================================================================
// CONVENIENCE EXPORTS: Common patterns for each profile
// =============================================================================

/// :min profile convenience functions
pub const min = struct {
    /// File operations for :min profile
    pub fn read_file(path: []const u8, allocator: std.mem.Allocator) fs.FsError![]u8 {
        return fs.read(.{ .path = path, .allocator = allocator });
    }

    pub fn write_file(path: []const u8, content: []const u8, allocator: std.mem.Allocator) fs.FsError!void {
        return fs.write(.{ .path = path, .content = content, .allocator = allocator });
    }

    /// HTTP operations for :min profile
    pub fn http_get(url: []const u8, allocator: std.mem.Allocator) http.HttpError!http.HttpResponse {
        return http.get(.{ .url = url, .allocator = allocator });
    }

    /// Database operations for :min profile
    pub fn db_query(sql: []const u8, allocator: std.mem.Allocator) db.DbError!db.ResultSet {
        return db.execute(.{ .sql = sql, .allocator = allocator });
    }
};

/// :go profile convenience functions
pub const go = struct {
    /// File operations for :go profile
    pub fn read_file(path: []const u8, ctx: context.Context, allocator: std.mem.Allocator) fs.FsError![]u8 {
        return fs.read(.{ .path = path, .ctx = ctx, .allocator = allocator });
    }

    pub fn write_file(path: []const u8, content: []const u8, ctx: context.Context, allocator: std.mem.Allocator) fs.FsError!void {
        return fs.write(.{ .path = path, .content = content, .ctx = ctx, .allocator = allocator });
    }

    /// HTTP operations for :go profile
    pub fn http_get(url: []const u8, ctx: context.Context, allocator: std.mem.Allocator) http.HttpError!http.HttpResponse {
        return http.get(.{ .url = url, .ctx = ctx, .allocator = allocator });
    }

    /// Database operations for :go profile
    pub fn db_query(sql: []const u8, ctx: context.Context, allocator: std.mem.Allocator) db.DbError!db.ResultSet {
        return db.execute(.{ .sql = sql, .ctx = ctx, .allocator = allocator });
    }
};

/// :full profile convenience functions
pub const full = struct {
    /// File operations for :full profile
    pub fn read_file(path: []const u8, cap: capabilities.FileSystem, allocator: std.mem.Allocator) fs.FsError![]u8 {
        return fs.read(.{ .path = path, .cap = cap, .allocator = allocator });
    }

    pub fn write_file(path: []const u8, content: []const u8, cap: capabilities.FileSystem, allocator: std.mem.Allocator) fs.FsError!void {
        return fs.write(.{ .path = path, .content = content, .cap = cap, .allocator = allocator });
    }

    /// HTTP operations for :full profile
    pub fn http_get(url: []const u8, cap: capabilities.NetHttp, allocator: std.mem.Allocator) http.HttpError!http.HttpResponse {
        return http.get(.{ .url = url, .cap = cap, .allocator = allocator });
    }

    /// Database operations for :full profile
    pub fn db_query(sql: []const u8, cap: capabilities.Database, allocator: std.mem.Allocator) db.DbError!db.ResultSet {
        return db.execute(.{ .sql = sql, .cap = cap, .allocator = allocator });
    }
};

// =============================================================================
// STANDARD LIBRARY METADATA: Version and feature information
// =============================================================================

/// Standard library version information
pub const version = struct {
    pub const major = 0;
    pub const minor = 1;
    pub const patch = 0;
    pub const pre_release = "alpha";

    pub fn string(allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}", .{ major, minor, patch, pre_release });
    }
};

/// Feature availability by profile
pub const features = struct {
    pub const min_features = [_][]const u8{
        "core.allocators",
        "io.basic",
        "string.operations",
        "fs.sync",
        "http.sync",
        "db.sync",
    };

    pub const go_features = min_features ++ [_][]const u8{
        "context.cancellation",
        "context.timeout",
        "fs.async",
        "http.async",
        "db.async",
        "concurrency.structured",
    };

    pub const full_features = go_features ++ [_][]const u8{
        "capabilities.security",
        "capabilities.audit",
        "fs.capability_gated",
        "http.capability_gated",
        "db.capability_gated",
        "effects.tracking",
    };

    pub fn available_in_profile(feature: []const u8, profile: anytype) bool {
        const feature_list = switch (profile) {
            .min => min_features,
            .go => go_features,
            .full => full_features,
        };

        for (feature_list) |available_feature| {
            if (std.mem.eql(u8, feature, available_feature)) {
                return true;
            }
        }
        return false;
    }
};

// =============================================================================
// TESTS: Standard library integration and tri-signature pattern validation
// =============================================================================

test "tri-signature pattern consistency" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test that all modules follow the tri-signature pattern
    // Each operation should work with :min, :go, and :full signatures

    // File system tri-signature test
    {
        // :min signature
        const content_min = try fs.read(.{ .path = "/test/file.txt", .allocator = allocator });
        defer allocator.free(content_min);
        try testing.expect(std.mem.indexOf(u8, content_min, "min profile") != null);

        // :go signature (mock context)
        var mock_ctx = context.Context.init(allocator);
        defer mock_ctx.deinit();

        const content_go = try fs.read(.{ .path = "/test/file.txt", .ctx = mock_ctx, .allocator = allocator });
        defer allocator.free(content_go);
        try testing.expect(std.mem.indexOf(u8, content_go, "go profile") != null);

        // :full signature (mock capability)
        var mock_cap = capabilities.FileSystem.init("test-fs", allocator);
        defer mock_cap.deinit();
        try mock_cap.allow_path("/test");

        const content_full = try fs.read(.{ .path = "/test/file.txt", .cap = mock_cap, .allocator = allocator });
        defer allocator.free(content_full);
        try testing.expect(std.mem.indexOf(u8, content_full, "full profile") != null);
    }

    // HTTP tri-signature test
    {
        // :min signature
        var response_min = try http.http_get(.{ .url = "https://example.com", .allocator = allocator });
        defer response_min.deinit();
        try testing.expect(response_min.status_code == 200);

        // :go signature (mock context)
        var mock_ctx = context.Context.init(allocator);
        defer mock_ctx.deinit();

        var response_go = try http.http_get(.{ .url = "https://example.com", .ctx = mock_ctx, .allocator = allocator });
        defer response_go.deinit();
        try testing.expect(response_go.status_code == 200);

        // :full signature (mock capability)
        var mock_cap = capabilities.NetHttp.init("test-http", allocator);
        defer mock_cap.deinit();

        var response_full = try http.http_get(.{ .url = "https://example.com", .cap = mock_cap, .allocator = allocator });
        defer response_full.deinit();
        try testing.expect(response_full.status_code == 200);
    }

    // Database tri-signature test
    {
        // :min signature
        var result_min = try db.query(.{ .sql = "SELECT 1", .allocator = allocator });
        defer result_min.deinit();
        try testing.expect(result_min.row_count() == 1);

        // :go signature (mock context)
        var mock_ctx = context.Context.init(allocator);
        defer mock_ctx.deinit();

        var result_go = try db.query(.{ .sql = "SELECT 1", .ctx = mock_ctx, .allocator = allocator });
        defer result_go.deinit();
        try testing.expect(result_go.row_count() == 1);

        // :full signature (mock capability)
        var mock_cap = capabilities.Database.init("test-db", "postgresql://localhost/test", allocator);
        defer mock_cap.deinit();

        var result_full = try db.query(.{ .sql = "SELECT 1", .cap = mock_cap, .allocator = allocator });
        defer result_full.deinit();
        try testing.expect(result_full.row_count() == 1);
    }
}

test "profile-aware convenience functions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test :min profile convenience functions
    {
        const content = try min.read_file("/test/file.txt", allocator);
        defer allocator.free(content);
        try testing.expect(std.mem.indexOf(u8, content, "min profile") != null);

        var response = try min.http_get("https://example.com", allocator);
        defer response.deinit();
        try testing.expect(response.status_code == 200);

        var result = try min.db_query("SELECT 1", allocator);
        defer result.deinit();
        try testing.expect(result.row_count() == 1);
    }

    // Test :go profile convenience functions
    {
        var mock_ctx = context.Context.init(allocator);
        defer mock_ctx.deinit();

        const content = try go.read_file("/test/file.txt", mock_ctx, allocator);
        defer allocator.free(content);
        try testing.expect(std.mem.indexOf(u8, content, "go profile") != null);

        var response = try go.http_get("https://example.com", mock_ctx, allocator);
        defer response.deinit();
        try testing.expect(response.status_code == 200);

        var result = try go.db_query("SELECT 1", mock_ctx, allocator);
        defer result.deinit();
        try testing.expect(result.row_count() == 1);
    }

    // Test :full profile convenience functions
    {
        var fs_cap = capabilities.FileSystem.init("test-fs", allocator);
        defer fs_cap.deinit();
        try fs_cap.allow_path("/test");

        var http_cap = capabilities.NetHttp.init("test-http", allocator);
        defer http_cap.deinit();

        var db_cap = capabilities.Database.init("test-db", "postgresql://localhost/test", allocator);
        defer db_cap.deinit();

        const content = try full.read_file("/test/file.txt", fs_cap, allocator);
        defer allocator.free(content);
        try testing.expect(std.mem.indexOf(u8, content, "full profile") != null);

        var response = try full.http_get("https://example.com", http_cap, allocator);
        defer response.deinit();
        try testing.expect(response.status_code == 200);

        var result = try full.db_query("SELECT 1", db_cap, allocator);
        defer result.deinit();
        try testing.expect(result.row_count() == 1);
    }
}

test "feature availability by profile" {
    const testing = std.testing;

    // Test feature availability
    try testing.expect(features.available_in_profile("core.allocators", .min));
    try testing.expect(features.available_in_profile("core.allocators", .go));
    try testing.expect(features.available_in_profile("core.allocators", .full));

    try testing.expect(!features.available_in_profile("context.cancellation", .min));
    try testing.expect(features.available_in_profile("context.cancellation", .go));
    try testing.expect(features.available_in_profile("context.cancellation", .full));

    try testing.expect(!features.available_in_profile("capabilities.security", .min));
    try testing.expect(!features.available_in_profile("capabilities.security", .go));
    try testing.expect(features.available_in_profile("capabilities.security", .full));
}

test "standard library version" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const version_string = try version.string(allocator);
    defer allocator.free(version_string);

    try testing.expect(std.mem.indexOf(u8, version_string, "0.1.0-alpha") != null);
}
