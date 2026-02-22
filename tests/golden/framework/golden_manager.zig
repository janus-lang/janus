// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// Golden Test Framework - GoldenManager
// Task 4: Implement GoldenManager for reference storage and retrieval
// Requirements: 2.1, 2.2, 7.1, 7.3

/// Platform-specific golden file management with versioning and backup
pub const GoldenManager = struct {
    allocator: std.mem.Allocator,
    base_path: []const u8,
    platform_info: PlatformInfo,
    version_info: VersionInfo,

    const Self = @

    pub const PlatformInfo = struct {
        os: []const u8,
        arch: []const u8,
        abi: []const u8,

        pub fn current(allocator: std.mem.Allocator) !PlatformInfo {
            const builtin = @import("builtin");
            return PlatformInfo{
                .os = try allocator.dupe(u8, @tagName(builtin.os.tag)),
                .arch = try allocator.dupe(u8, @tagName(builtin.cpu.arch)),
                .abi = try allocator.dupe(u8, @tagName(builtin.abi)),
            };
        }

        pub fn deinit(self: *PlatformInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.os);
            allocator.free(self.arch);
            allocator.free(self.abi);
        }

        pub fn toString(self: *const PlatformInfo, allocator: std.mem.Allocator) ![]const u8 {
            return try std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{ self.os, self.arch, self.abi });
        }
    };

    pub const VersionInfo = struct {
        compiler_version: []const u8,
        llvm_version: []const u8,

        pub fn current(allocator: std.mem.Allocator) !VersionInfo {
            // For now, use placeholder versions - real implementation would detect actual versions
            return VersionInfo{
                .compiler_version = try allocator.dupe(u8, "0.1.0-pre-alpha"),
                .llvm_version = try allocator.dupe(u8, "17.0.0"),
            };
        }

        pub fn deinit(self: *VersionInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.compiler_version);
            allocator.free(self.llvm_version);
        }
    };

    pub const GoldenFileInfo = struct {
        test_name: []const u8,
        optimization_level: OptimizationLevel,
        platform_specific: bool,

        pub const OptimizationLevel = enum {
            debug,
            release_safe,
            release_fast,
            release_small,

            pub fn toString(self: OptimizationLevel) []const u8 {
                return switch (self) {
                    .debug => "debug",
                    .release_safe => "release_safe",
                    .release_fast => "release_fast",
                    .release_small => "release_small",
                };
            }
        };
    };

    pub const StorageResult = struct {
        path: []const u8,
        backup_created: bool,
        version_updated: bool,

        pub fn deinit(self: *StorageResult, allocator: std.mem.Allocator) void {
            allocator.free(self.path);
        }
    };

    pub fn init(allocator: std.mem.Allocator, base_path: []const u8) !Self {
        const platform_info = try PlatformInfo.current(allocator);
        const version_info = try VersionInfo.current(allocator);

        // Ensure base directory exists
        std.fs.cwd().makePath(base_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return Self{
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, base_path),
            .platform_info = platform_info,
            .version_info = version_info,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.base_path);
        self.platform_info.deinit(self.allocator);
        self.version_info.deinit(self.allocator);
    }

    /// Generate golden file path with platform and optimization level
    pub fn generateGoldenPath(self: *const Self, file_info: GoldenFileInfo) ![]const u8 {
        const platform_str = if (file_info.platform_specific)
            try self.platform_info.toString(self.allocator)
        else
            try self.allocator.dupe(u8, "common");
        defer self.allocator.free(platform_str);

        const opt_level = file_info.optimization_level.toString();

        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/references/{s}/{s}/{s}.ll",
            .{ self.base_path, platform_str, opt_level, file_info.test_name }
        );
    }

    /// Store golden reference with versioning and backup
    pub fn storeGoldenReference(self: *const Self, file_info: GoldenFileInfo, ir_content: []const u8) !StorageResult {
        const golden_path = try self.generateGoldenPath(file_info);

        var backup_created = false;
        var version_updated = false;

        // Create backup if file exists
        if (std.fs.cwd().openFile(golden_path, .{})) |existing_file| {
            existing_file.close();

            const backup_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}.backup.{d}",
                .{ golden_path, std.time.timestamp() }
            );
            defer self.allocator.free(backup_path);

            try std.fs.cwd().copyFile(golden_path, std.fs.cwd(), backup_path, .{});
            backup_created = true;
        } else |_| {
            // File doesn't exist, no backup needed
        }

        // Ensure directory exists
        if (std.fs.path.dirname(golden_path)) |dir_path| {
            std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }

        // Write golden reference
        const file = try std.fs.cwd().createFile(golden_path, .{});
        defer file.close();

        try file.writeAll(ir_content);

        // Write metadata file
        const metadata_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}.meta",
            .{golden_path}
        );
        defer self.allocator.free(metadata_path);

        const metadata_file = try std.fs.cwd().createFile(metadata_path, .{});
        defer metadata_file.close();

        const metadata = try std.fmt.allocPrint(
            self.allocator,
            \\{{
            \\  "test_name": "{s}",
            \\  "optimization_level": "{s}",
            \\  "platform": "{s}",
            \\  "compiler_version": "{s}",
            \\  "llvm_version": "{s}",
            \\  "created_at": "{d}",
            \\  "content_hash": "{s}"
            \\}}
            ,
            .{
                file_info.test_name,
                file_info.optimization_level.toString(),
                try self.platform_info.toString(self.allocator),
                self.version_info.compiler_version,
                self.version_info.llvm_version,
                std.time.timestamp(),
                "placeholder-hash", // TODO: Calculate actual content hash
            }
        );
        defer self.allocator.free(metadata);

        try metadata_file.writeAll(metadata);
        version_updated = true;

        return StorageResult{
            .path = golden_path,
            .backup_created = backup_created,
            .version_updated = version_updated,
        };
    }

    /// Retrieve golden reference content
    pub fn retrieveGoldenReference(self: *const Self, file_info: GoldenFileInfo) !?[]const u8 {
        const golden_path = try self.generateGoldenPath(file_info);
        defer self.allocator.free(golden_path);

        const file = std.fs.cwd().openFile(golden_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        return content;
    }

    /// Check if golden reference exists
    pub fn hasGoldenReference(self: *const Self, file_info: GoldenFileInfo) !bool {
        const golden_path = try self.generateGoldenPath(file_info);
        defer self.allocator.free(golden_path);

        std.fs.cwd().access(golden_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };

        return true;
    }

    /// List all golden references for a test
    pub fn listGoldenReferences(self: *const Self, test_name: []const u8) ![]GoldenFileInfo {
        var references: std.ArrayList(GoldenFileInfo) = .empty;

        // Search in common directory
        const common_path = try std.fmt.allocPrint(self.allocator, "{s}/references/common", .{self.base_path});
        defer self.allocator.free(common_path);

        try self.scanDirectoryForReferences(common_path, test_name, false, &references);

        // Search in platform-specific directory
        const platform_str = try self.platform_info.toString(self.allocator);
        defer self.allocator.free(platform_str);

        const platform_path = try std.fmt.allocPrint(self.allocator, "{s}/references/{s}", .{ self.base_path, platform_str });
        defer self.allocator.free(platform_path);

        try self.scanDirectoryForReferences(platform_path, test_name, true, &references);

        return try references.toOwnedSlice(alloc);
    }

    fn scanDirectoryForReferences(
        self: *const Self,
        dir_path: []const u8,
        test_name: []const u8,
        platform_specific: bool,
        references: *std.ArrayList(GoldenFileInfo)
    ) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return, // Directory doesn't exist, skip
            else => return err,
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .directory) continue;

            const opt_level = std.meta.stringToEnum(GoldenFileInfo.OptimizationLevel, entry.name) orelse continue;

            const test_file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.ll", .{ entry.name, test_name });
            defer self.allocator.free(test_file_path);

            dir.access(test_file_path, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };

            try references.append(GoldenFileInfo{
                .test_name = try self.allocator.dupe(u8, test_name),
                .optimization_level = opt_level,
                .platform_specific = platform_specific,
            });
        }
    }

    /// Verify golden file integrity
    pub fn verifyIntegrity(self: *const Self, file_info: GoldenFileInfo) !bool {
        const golden_path = try self.generateGoldenPath(file_info);
        defer self.allocator.free(golden_path);

        const metadata_path = try std.fmt.allocPrint(self.allocator, "{s}.meta", .{golden_path});
        defer self.allocator.free(metadata_path);

        // Check if both files exist
        std.fs.cwd().access(golden_path, .{}) catch return false;
        std.fs.cwd().access(metadata_path, .{}) catch return false;

        // TODO: Verify content hash matches metadata
        // For now, just check file existence
        return true;
    }
};

// Tests
test "GoldenManager initialization" {
    var manager = try GoldenManager.init(testing.allocator, "test_golden");
    defer manager.deinit();

    try testing.expect(std.mem.eql(u8, manager.base_path, "test_golden"));
    try testing.expect(manager.platform_info.os.len > 0);
    try testing.expect(manager.platform_info.arch.len > 0);
}

test "Golden path generation" {
    var manager = try GoldenManager.init(testing.allocator, "test_golden");
    defer manager.deinit();

    const file_info = GoldenManager.GoldenFileInfo{
        .test_name = "test_dispatch",
        .optimization_level = .release_safe,
        .platform_specific = false,
    };

    const path = try manager.generateGoldenPath(file_info);
    defer testing.allocator.free(path);

    try testing.expect(std.mem.indexOf(u8, path, "test_dispatch.ll") != null);
    try testing.expect(std.mem.indexOf(u8, path, "release_safe") != null);
    try testing.expect(std.mem.indexOf(u8, path, "common") != null);
}

test "Golden reference storage and retrieval" {
    var manager = try GoldenManager.init(testing.allocator, "test_golden_storage");
    defer manager.deinit();

    const file_info = GoldenManager.GoldenFileInfo{
        .test_name = "test_storage",
        .optimization_level = .debug,
        .platform_specific = false,
    };

    const test_ir = "define i32 @test() { ret i32 42 }";

    // Store golden reference
    var result = try manager.storeGoldenReference(file_info, test_ir);
    defer result.deinit(testing.allocator);

    try testing.expect(result.version_updated);

    // Retrieve golden reference
    const retrieved = try manager.retrieveGoldenReference(file_info);
    defer if (retrieved) |content| testing.allocator.free(content);

    try testing.expect(retrieved != null);
    try testing.expectEqualStrings(test_ir, retrieved.?);

    // Check existence
    try testing.expect(try manager.hasGoldenReference(file_info));

    // Cleanup
    const golden_path = try manager.generateGoldenPath(file_info);
    defer testing.allocator.free(golden_path);
    std.fs.cwd().deleteFile(golden_path) catch {};

    const metadata_path = try std.fmt.allocPrint(testing.allocator, "{s}.meta", .{golden_path});
    defer testing.allocator.free(metadata_path);
    std.fs.cwd().deleteFile(metadata_path) catch {};
}
