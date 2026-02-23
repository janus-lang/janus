// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const testing = std.testing;

const DispatchTableSerialization = @import("dispatch_table_serialization.zig").DispatchTableSerialization;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const ModuleDispatcher = @import("module_dispatch.zig").ModuleDispatcher;

/// Build cache system for dispatch tables enabling incremental compilation
/// Caches pre-computed dispatch tables to avoid recomputation across builds
pub const DispatchBuildCache = struct {
    allocator: Allocator,
    cache_dir: []const u8,
    serializer: DispatchTableSerialization,
    build_hash: u64,

    const Self = @This();

    // Cache file structure
    const CACHE_VERSION = "v1";
    const CACHE_EXTENSION = ".jdsc";
    const INDEX_FILE = "dispatch_cache_index.json";

    pub fn init(allocator: Allocator, cache_dir: []const u8) !Self {
        // Ensure cache directory exists
        compat_fs.makeDir(cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return Self{
            .allocator = allocator,
            .cache_dir = try allocator.dupe(u8, cache_dir),
            .serializer = DispatchTableSerialization.init(allocator),
            .build_hash = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.cache_dir);
    }

    /// Set build hash for cache invalidation
    pub fn setBuildHash(self: *Self, source_files: []const []const u8) !void {
        var hasher = std.hash.Wyhash.init(0);

        for (source_files) |file_path| {
            // Hash file path
            hasher.update(file_path);

            // Hash file modification time
            const file = std.fs.cwd().openFile(file_path, .{}) catch continue;
            defer file.close();

            const stat = file.stat() catch continue;
            hasher.update(std.mem.asBytes(&stat.mtime));
        }

        self.build_hash = hasher.final();
    }

    /// Check if cached dispatch tables are valid for current build
    pub fn isCacheValid(self: *Self, signature_name: []const u8) !bool {
        const cache_path = try self.getCachePath(signature_name);
        defer self.allocator.free(cache_path);

        // Check if cache file exists
        const file = std.fs.cwd().openFile(cache_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer file.close();

        // Read cache header to check build hash
        var header_bytes: [@sizeOf(CacheHeader)]u8 = undefined;
        _ = try file.readAll(&header_bytes);

        const header = @as(*const CacheHeader, @ptrCast(@alignCast(&header_bytes))).*;

        // Validate magic and version
        if (!std.mem.eql(u8, &header.magic, "JDSC")) return false;
        if (!self.serializer.version.isCompatible(header.version)) return false;

        // Check build hash
        return header.build_hash == self.build_hash;
    }

    /// Cache dispatch table for signature
    pub fn cacheTable(self: *Self, signature_name: []const u8, table: *const OptimizedDispatchTable) !void {
        const cache_path = try self.getCachePath(signature_name);
        defer self.allocator.free(cache_path);

        // Serialize table
        const serialized_data = try self.serializer.serializeTable(table);
        defer self.allocator.free(serialized_data);

        // Write to cache file
        var file = try compat_fs.createFile(cache_path, .{});
        defer file.close();

        // Write cache header
        const header = CacheHeader{
            .magic = [_]u8{ 'J', 'D', 'S', 'C' },
            .version = self.serializer.version,
            .table_count = 1,
            .total_size = @intCast(serialized_data.len),
            .build_hash = self.build_hash,
        };

        try file.writeAll(std.mem.asBytes(&header));
        try file.writeAll(serialized_data);

        // Update cache index
        try self.updateCacheIndex(signature_name, cache_path);
    }

    /// Load cached dispatch table for signature
    pub fn loadTable(self: *Self, signature_name: []const u8) !?*OptimizedDispatchTable {
        if (!try self.isCacheValid(signature_name)) {
            return null;
        }

        const cache_path = try self.getCachePath(signature_name);
        defer self.allocator.free(cache_path);

        var file = try std.fs.cwd().openFile(cache_path, .{});
        defer file.close();

        // Skip header
        try file.seekTo(@sizeOf(CacheHeader));

        // Read serialized data
        const remaining_size = try file.getEndPos() - @sizeOf(CacheHeader);
        const data = try self.allocator.alloc(u8, remaining_size);
        defer self.allocator.free(data);

        _ = try file.readAll(data);

        // Deserialize table
        return try self.serializer.deserializeTable(data);
    }

    /// Cache multiple dispatch tables in batch
    pub fn cacheTables(self: *Self, tables: []const TableCacheEntry) !void {
        const batch_cache_path = try self.getBatchCachePath();
        defer self.allocator.free(batch_cache_path);

        try self.serializer.serializeCache(@ptrCast(tables.ptr), // Cast to expected type
            batch_cache_path);

        // Update index for all tables
        for (tables) |entry| {
            try self.updateCacheIndex(entry.signature_name, batch_cache_path);
        }
    }

    /// Load multiple dispatch tables from batch cache
    pub fn loadTables(self: *Self) ![]const *OptimizedDispatchTable {
        const batch_cache_path = try self.getBatchCachePath();
        defer self.allocator.free(batch_cache_path);

        // Check if batch cache is valid
        if (!try self.isBatchCacheValid()) {
            return &[_]*OptimizedDispatchTable{};
        }

        return try self.serializer.deserializeCache(batch_cache_path);
    }

    /// Invalidate cache for specific signature
    pub fn invalidateSignature(self: *Self, signature_name: []const u8) !void {
        const cache_path = try self.getCachePath(signature_name);
        defer self.allocator.free(cache_path);

        compat_fs.deleteFile(cache_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };

        try self.removeFromCacheIndex(signature_name);
    }

    /// Invalidate entire cache
    pub fn invalidateAll(self: *Self) !void {
        var cache_dir = try compat_fs.openDir(self.cache_dir, .{ .iterate = true });
        defer cache_dir.close();

        var iterator = cache_dir.iterate();
        while (try iterator.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, CACHE_EXTENSION)) {
                try cache_dir.deleteFile(entry.name);
            }
        }

        // Remove index file
        cache_dir.deleteFile(INDEX_FILE) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }

    /// Get cache statistics
    pub fn getCacheStats(self: *Self) !CacheStats {
        var stats = CacheStats{
            .total_files = 0,
            .total_size_bytes = 0,
            .valid_files = 0,
            .invalid_files = 0,
        };

        var cache_dir = try compat_fs.openDir(self.cache_dir, .{ .iterate = true });
        defer cache_dir.close();

        var iterator = cache_dir.iterate();
        while (try iterator.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, CACHE_EXTENSION)) {
                stats.total_files += 1;

                const file_stat = try cache_dir.statFile(entry.name);
                stats.total_size_bytes += file_stat.size;

                // Check if file is valid (simplified check)
                const signature_name = entry.name[0 .. entry.name.len - CACHE_EXTENSION.len];
                if (try self.isCacheValid(signature_name)) {
                    stats.valid_files += 1;
                } else {
                    stats.invalid_files += 1;
                }
            }
        }

        return stats;
    }

    // Helper types and structures
    pub const TableCacheEntry = struct {
        signature_name: []const u8,
        table: *const OptimizedDispatchTable,
    };

    pub const CacheStats = struct {
        total_files: u32,
        total_size_bytes: u64,
        valid_files: u32,
        invalid_files: u32,

        pub fn getHitRate(self: CacheStats) f64 {
            if (self.total_files == 0) return 0.0;
            return @as(f64, @floatFromInt(self.valid_files)) / @as(f64, @floatFromInt(self.total_files));
        }
    };

    const CacheHeader = struct {
        magic: [4]u8,
        version: DispatchTableSerialization.SerializationVersion,
        table_count: u32,
        total_size: u64,
        build_hash: u64,
    };

    const CacheIndex = struct {
        version: []const u8,
        build_hash: u64,
        entries: HashMap([]const u8, CacheIndexEntry),

        const CacheIndexEntry = struct {
            signature_name: []const u8,
            cache_file_path: []const u8,
            last_modified: i64,
            size_bytes: u64,
        };
    };

    // Helper functions
    fn getCachePath(self: *Self, signature_name: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}{s}", .{ self.cache_dir, signature_name, CACHE_EXTENSION });
    }

    fn getBatchCachePath(self: *Self) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/batch{s}", .{ self.cache_dir, CACHE_EXTENSION });
    }

    fn isBatchCacheValid(self: *Self) !bool {
        const cache_path = try self.getBatchCachePath();
        defer self.allocator.free(cache_path);

        const file = std.fs.cwd().openFile(cache_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        file.close();

        return true;
    }

    fn updateCacheIndex(self: *Self, signature_name: []const u8, cache_path: []const u8) !void {
        _ = signature_name;
        _ = cache_path;
        // TODO: Implement cache index updating
    }

    fn removeFromCacheIndex(self: *Self, signature_name: []const u8) !void {
        _ = signature_name;
        // TODO: Implement cache index removal
    }
};
