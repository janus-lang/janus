// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const testing = std.testing;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchTableOptimizer = @import("dispatch_table_optimizer.zig").DispatchTableOptimizer;
const DispatchTableSerializer = @import("dispatch_table_serialization.zig").DispatchTableSerializer;

/// Build system integration for dispatch table caching
pub const BuildCacheManager = struct {
    allocator: Allocator,

    // Core components
    serializer: DispatchTableSerializer,
    optimizer: DispatchTableOptimizer,

    // Build state tracking
    build_session: BuildSession,
    dependency_tracker: DependencyTracker,

    // Cache configuration
    config: CacheConfig,

    // Performance monitoring
    metrics: BuildMetrics,

    const Self = @This();

    /// Build session tracking for incremental compilation
    pub const BuildSession = struct {
        session_id: u64,
        start_time: u64,
        source_files: HashMap([]const u8, FileInfo),
        dispatch_tables: HashMap([]const u8, *OptimizedDispatchTable),

        pub const FileInfo = struct {
            path: []const u8,
            last_modified: u64,
            content_hash: u64,
            dependencies: []const []const u8,
        };

        pub fn init(allocator: Allocator) BuildSession {
            return BuildSession{
                .session_id = @intCast(std.time.nanoTimestamp()),
                .start_time = @intCast(std.time.nanoTimestamp()),
                .source_files = HashMap([]const u8, FileInfo).init(allocator),
                .dispatch_tables = HashMap([]const u8, *OptimizedDispatchTable).init(allocator),
            };
        }

        pub fn deinit(self: *BuildSession, allocator: Allocator) void {
            // Clean up file info
            var file_iter = self.source_files.iterator();
            while (file_iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.path);
                for (entry.value_ptr.dependencies) |dep| {
                    allocator.free(dep);
                }
                allocator.free(entry.value_ptr.dependencies);
            }
            self.source_files.deinit();

            // Clean up dispatch tables
            var table_iter = self.dispatch_tables.iterator();
            while (table_iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.*.deinit();
                allocator.destroy(entry.value_ptr.*);
            }
            self.dispatch_tables.deinit();
        }

        pub fn addSourceFile(self: *BuildSession, allocator: Allocator, path: []const u8, last_modified: u64, content_hash: u64, dependencies: []const []const u8) !void {
            const owned_path = try allocator.dupe(u8, path);
            const owned_deps = try allocator.alloc([]const u8, dependencies.len);
            for (dependencies, 0..) |dep, i| {
                owned_deps[i] = try allocator.dupe(u8, dep);
            }

            const file_info = FileInfo{
                .path = try allocator.dupe(u8, path),
                .last_modified = last_modified,
                .content_hash = content_hash,
                .dependencies = owned_deps,
            };

            try self.source_files.put(owned_path, file_info);
        }

        pub fn addDispatchTable(self: *BuildSession, allocator: Allocator, signature: []const u8, table: *OptimizedDispatchTable) !void {
            const owned_signature = try allocator.dupe(u8, signature);
            try self.dispatch_tables.put(owned_signature, table);
        }

        pub fn getDispatchTable(self: *BuildSession, signature: []const u8) ?*OptimizedDispatchTable {
            return self.dispatch_tables.get(signature);
        }
    };

    /// Dependency tracking for cache invalidation
    pub const DependencyTracker = struct {
        allocator: Allocator,
        dependencies: HashMap([]const u8, DependencyInfo),

        pub const DependencyInfo = struct {
            dependents: ArrayList([]const u8),
            last_modified: u64,
            content_hash: u64,
        };

        pub fn init(allocator: Allocator) DependencyTracker {
            return DependencyTracker{
                .allocator = allocator,
                .dependencies = HashMap([]const u8, DependencyInfo).init(allocator),
            };
        }

        pub fn deinit(self: *DependencyTracker) void {
            var iter = self.dependencies.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                for (entry.value_ptr.dependents.items) |dependent| {
                    self.allocator.free(dependent);
                }
                entry.value_ptr.dependents.deinit();
            }
            self.dependencies.deinit();
        }

        pub fn addDependency(self: *DependencyTracker, file: []const u8, dependency: []const u8, last_modified: u64, content_hash: u64) !void {
            const owned_dep = try self.allocator.dupe(u8, dependency);

            if (self.dependencies.getPtr(owned_dep)) |dep_info| {
                // Update existing dependency
                dep_info.last_modified = last_modified;
                dep_info.content_hash = content_hash;

                // Add file as dependent if not already present
                for (dep_info.dependents.items) |dependent| {
                    if (std.mem.eql(u8, dependent, file)) {
                        return; // Already a dependent
                    }
                }

                const owned_file = try self.allocator.dupe(u8, file);
                try dep_info.dependents.append(owned_file);
            } else {
                // Create new dependency
                var dependents: ArrayList([]const u8) = .empty;
                const owned_file = try self.allocator.dupe(u8, file);
                try dependents.append(owned_file);

                const dep_info = DependencyInfo{
                    .dependents = dependents,
                    .last_modified = last_modified,
                    .content_hash = content_hash,
                };

                try self.dependencies.put(owned_dep, dep_info);
            }
        }

        pub fn getDependents(self: *DependencyTracker, dependency: []const u8) ?[]const []const u8 {
            if (self.dependencies.get(dependency)) |dep_info| {
                return dep_info.dependents.items;
            }
            return null;
        }

        pub fn hasChanged(self: *DependencyTracker, dependency: []const u8, current_modified: u64, current_hash: u64) bool {
            if (self.dependencies.get(dependency)) |dep_info| {
                return dep_info.last_modified != current_modified or dep_info.content_hash != current_hash;
            }
            return true; // Unknown dependency is considered changed
        }
    };

    /// Cache configuration
    pub const CacheConfig = struct {
        cache_directory: []const u8,
        max_cache_size_bytes: usize,
        max_cache_age_seconds: u64,
        enable_compression: bool,
        enable_incremental_updates: bool,
        cache_cleanup_interval_seconds: u64,

        pub fn default(allocator: Allocator) !CacheConfig {
            return CacheConfig{
                .cache_directory = try allocator.dupe(u8, ".janus_cache/dispatch_tables"),
                .max_cache_size_bytes = 100 * 1024 * 1024, // 100MB
                .max_cache_age_seconds = 7 * 24 * 60 * 60, // 1 week
                .enable_compression = true,
                .enable_incremental_updates = true,
                .cache_cleanup_interval_seconds = 24 * 60 * 60, // Daily cleanup
            };
        }
    };

    /// Build performance metrics
    pub const BuildMetrics = struct {
        total_build_time_ns: u64,
        cache_lookup_time_ns: u64,
        serialization_time_ns: u64,
        optimization_time_ns: u64,

        tables_from_cache: u32,
        tables_built_fresh: u32,
        tables_optimized: u32,

        cache_hit_ratio: f64,
        build_speedup_ratio: f64,

        pub fn reset(self: *BuildMetrics) void {
            self.* = std.mem.zeroes(BuildMetrics);
        }

        pub fn calculateCacheHitRatio(self: *BuildMetrics) void {
            const total_tables = self.tables_from_cache + self.tables_built_fresh;
            if (total_tables > 0) {
                self.cache_hit_ratio = @as(f64, @floatFromInt(self.tables_from_cache)) / @as(f64, @floatFromInt(total_tables));
            }
        }

        pub fn calculateSpeedupRatio(self: *BuildMetrics, baseline_time_ns: u64) void {
            if (self.total_build_time_ns > 0) {
                self.build_speedup_ratio = @as(f64, @floatFromInt(baseline_time_ns)) / @as(f64, @floatFromInt(self.total_build_time_ns));
            }
        }

        pub fn format(self: BuildMetrics, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Build Metrics:\n");
            try writer.print("  Total build time: {d:.1}ms\n", .{@as(f64, @floatFromInt(self.total_build_time_ns)) / 1_000_000.0});
            try writer.print("  Cache lookup time: {d:.1}ms\n", .{@as(f64, @floatFromInt(self.cache_lookup_time_ns)) / 1_000_000.0});
            try writer.print("  Serialization time: {d:.1}ms\n", .{@as(f64, @floatFromInt(self.serialization_time_ns)) / 1_000_000.0});
            try writer.print("  Optimization time: {d:.1}ms\n", .{@as(f64, @floatFromInt(self.optimization_time_ns)) / 1_000_000.0});
            try writer.print("  Tables: {} from cache, {} built fresh, {} optimized\n", .{ self.tables_from_cache, self.tables_built_fresh, self.tables_optimized });
            try writer.print("  Cache hit ratio: {d:.1}%\n", .{self.cache_hit_ratio * 100.0});
            try writer.print("  Build speedup: {d:.1}x\n", .{self.build_speedup_ratio});
        }
    };

    pub fn init(allocator: Allocator, config: CacheConfig) !Self {
        var serializer = try DispatchTableSerializer.init(allocator, config.cache_directory);
        var optimizer = DispatchTableOptimizer.init(allocator);

        return Self{
            .allocator = allocator,
            .serializer = serializer,
            .optimizer = optimizer,
            .build_session = BuildSession.init(allocator),
            .dependency_tracker = DependencyTracker.init(allocator),
            .config = config,
            .metrics = std.mem.zeroes(BuildMetrics),
        };
    }

    pub fn deinit(self: *Self) void {
        self.build_session.deinit(self.allocator);
        self.dependency_tracker.deinit();
        self.optimizer.deinit();
        self.serializer.deinit();
        self.allocator.free(self.config.cache_directory);
    }

    /// Start a new build session
    pub fn startBuildSession(self: *Self) !void {
        // Clean up previous session
        self.build_session.deinit(self.allocator);

        // Start new session
        self.build_session = BuildSession.init(self.allocator);
        self.metrics.reset();

        // Perform cache cleanup if needed
        try self.performCacheCleanupIfNeeded();
    }

    /// End the current build session
    pub fn endBuildSession(self: *Self) !void {
        const end_time = @as(u64, @intCast(std.time.nanoTimestamp()));
        self.metrics.total_build_time_ns = end_time - self.build_session.start_time;

        // Calculate final metrics
        self.metrics.calculateCacheHitRatio();

        // Save any new dispatch tables to cache
        try self.saveSessionTablesToCache();
    }

    /// Get or build a dispatch table for a signature
    pub fn getOrBuildDispatchTable(self: *Self, signature_name: []const u8, type_signature: []const TypeId, type_registry: *TypeRegistry, build_fn: *const fn ([]const u8, []const TypeId, *TypeRegistry) anyerror!*OptimizedDispatchTable) !*OptimizedDispatchTable {
        const lookup_start = std.time.nanoTimestamp();
        defer {
            const lookup_end = std.time.nanoTimestamp();
            self.metrics.cache_lookup_time_ns += @intCast(lookup_end - lookup_start);
        }

        // Check if already built in this session
        if (self.build_session.getDispatchTable(signature_name)) |existing_table| {
            return existing_table;
        }

        // Try to load from cache
        if (try self.loadFromCache(signature_name, type_signature, type_registry)) |cached_table| {
            try self.build_session.addDispatchTable(self.allocator, signature_name, cached_table);
            self.metrics.tables_from_cache += 1;
            return cached_table;
        }

        // Build fresh table
        const build_start = std.time.nanoTimestamp();
        const fresh_table = try build_fn(signature_name, type_signature, type_registry);
        const build_end = std.time.nanoTimestamp();

        // Optimize the table
        const optimize_start = std.time.nanoTimestamp();
        const optimization_config = DispatchTableOptimizer.OptimizationConfig.default();
        const optimization_result = try self.optimizer.optimizeTable(fresh_table, optimization_config);
        const optimize_end = std.time.nanoTimestamp();

        self.metrics.optimization_time_ns += @intCast(optimize_end - optimize_start);
        self.metrics.tables_built_fresh += 1;

        if (optimization_result.optimization_applied != .none) {
            self.metrics.tables_optimized += 1;
        }

        // Add to session
        try self.build_session.addDispatchTable(self.allocator, signature_name, fresh_table);

        return fresh_table;
    }

    /// Check if dependencies have changed and invalidate cache if needed
    pub fn validateDependencies(self: *Self, file_path: []const u8, dependencies: []const []const u8) !bool {
        var any_changed = false;

        for (dependencies) |dep| {
            // Get current file info
            const stat = std.fs.cwd().statFile(dep) catch |err| switch (err) {
                error.FileNotFound => {
                    // Dependency was deleted, invalidate
                    any_changed = true;
                    continue;
                },
                else => return err,
            };

            const current_modified = @as(u64, @intCast(stat.mtime));
            const current_hash = try self.calculateFileHash(dep);

            // Check if dependency changed
            if (self.dependency_tracker.hasChanged(dep, current_modified, current_hash)) {
                any_changed = true;

                // Invalidate all dependents
                if (self.dependency_tracker.getDependents(dep)) |dependents| {
                    for (dependents) |dependent| {
                        try self.invalidateCacheForFile(dependent);
                    }
                }
            }

            // Update dependency tracking
            try self.dependency_tracker.addDependency(file_path, dep, current_modified, current_hash);
        }

        return any_changed;
    }

    /// Generate build report
    pub fn generateBuildReport(self: *Self, writer: anytype) !void {
        try writer.print("Janus Build Cache Report\n");
        try writer.print("========================\n\n");

        // Build session info
        try writer.print("Build Session:\n");
        try writer.print("  Session ID: {}\n", .{self.build_session.session_id});
        try writer.print("  Source files: {}\n", .{self.build_session.source_files.count()});
        try writer.print("  Dispatch tables: {}\n", .{self.build_session.dispatch_tables.count()});
        try writer.print("\n");

        // Build metrics
        try writer.print("{}\n", .{self.metrics});

        // Cache statistics
        const cache_stats = self.serializer.getStats();
        try writer.print("Cache Statistics:\n");
        try writer.print("{}\n", .{cache_stats});

        // Optimization statistics
        const opt_stats = self.optimizer.getStats();
        try writer.print("Optimization Statistics:\n");
        try writer.print("{}\n", .{opt_stats});

        // Recommendations
        try self.generateOptimizationRecommendations(writer);
    }

    /// Get build metrics
    pub fn getMetrics(self: *const Self) BuildMetrics {
        return self.metrics;
    }

    // Private helper methods

    fn loadFromCache(self: *Self, signature_name: []const u8, type_signature: []const TypeId, type_registry: *TypeRegistry) !?*OptimizedDispatchTable {
        // Create temporary table to calculate cache key
        var temp_table = try OptimizedDispatchTable.init(self.allocator, signature_name, type_signature);
        defer temp_table.deinit();

        // Try to deserialize from cache
        const cache_key = try self.serializer.calculateCacheKey(&temp_table);
        return try self.serializer.deserializeTable(cache_key, type_registry);
    }

    fn saveSessionTablesToCache(self: *Self) !void {
        const serialize_start = std.time.nanoTimestamp();
        defer {
            const serialize_end = std.time.nanoTimestamp();
            self.metrics.serialization_time_ns += @intCast(serialize_end - serialize_start);
        }

        var table_iter = self.build_session.dispatch_tables.iterator();
        while (table_iter.next()) |entry| {
            const table = entry.value_ptr.*;

            // Only cache if not already cached
            if (!(try self.serializer.isCached(table))) {
                const cache_path = try self.serializer.serializeTable(table, null);
                self.allocator.free(cache_path);
            }
        }
    }

    fn performCacheCleanupIfNeeded(self: *Self) !void {
        // Check if cleanup is needed based on interval
        const current_time = @as(u64, @intCast(std.time.nanoTimestamp()));
        const last_cleanup_file = try std.fs.path.join(self.allocator, &[_][]const u8{ self.config.cache_directory, ".last_cleanup" });
        defer self.allocator.free(last_cleanup_file);

        const should_cleanup = blk: {
            const last_cleanup_data = std.fs.cwd().readFileAlloc(self.allocator, last_cleanup_file, 64) catch |err| switch (err) {
                error.FileNotFound => break :blk true,
                else => return err,
            };
            defer self.allocator.free(last_cleanup_data);

            const last_cleanup_time = std.fmt.parseInt(u64, std.mem.trim(u8, last_cleanup_data, " \n\r\t"), 10) catch break :blk true;
            const elapsed_seconds = (current_time - last_cleanup_time) / std.time.ns_per_s;

            break :blk elapsed_seconds >= self.config.cache_cleanup_interval_seconds;
        };

        if (should_cleanup) {
            try self.serializer.cleanupCache(self.config.max_cache_age_seconds, self.config.max_cache_size_bytes);

            // Update last cleanup time
            const cleanup_file = try std.fs.cwd().createFile(last_cleanup_file, .{});
            defer cleanup_file.close();

            try cleanup_file.writer().print("{}", .{current_time});
        }
    }

    fn calculateFileHash(self: *Self, file_path: []const u8) !u64 {
        _ = self;

        const file_data = try std.fs.cwd().readFileAlloc(self.allocator, file_path, std.math.maxInt(usize));
        defer self.allocator.free(file_data);

        var hasher = std.hash.Wyhash.init(0);
        hasher.update(file_data);
        return hasher.final();
    }

    fn invalidateCacheForFile(self: *Self, file_path: []const u8) !void {
        // In a real implementation, this would:
        // 1. Find all dispatch tables that depend on this file
        // 2. Invalidate their cache entries
        // 3. Remove them from the current build session

        _ = self;
        _ = file_path;

        // Placeholder implementation
    }

    fn generateOptimizationRecommendations(self: *Self, writer: anytype) !void {
        try writer.print("Build Optimization Recommendations:\n");
        try writer.print("------------------------------------\n");

        if (self.metrics.cache_hit_ratio < 0.5) {
            try writer.print("  - Low cache hit ratio ({d:.1}%)\n", .{self.metrics.cache_hit_ratio * 100.0});
            try writer.print("    Consider increasing cache size or improving dependency tracking\n");
        }

        if (self.metrics.tables_optimized == 0 and self.metrics.tables_built_fresh > 0) {
            try writer.print("  - No tables were optimized\n");
            try writer.print("    Consider enabling optimization or adjusting optimization thresholds\n");
        }

        const cache_time_ratio = @as(f64, @floatFromInt(self.metrics.cache_lookup_time_ns)) / @as(f64, @floatFromInt(self.metrics.total_build_time_ns));
        if (cache_time_ratio > 0.1) {
            try writer.print("  - Cache lookup time is high ({d:.1}% of total build time)\n", .{cache_time_ratio * 100.0});
            try writer.print("    Consider optimizing cache index or reducing cache size\n");
        }

        if (self.metrics.build_speedup_ratio < 1.5) {
            try writer.print("  - Build speedup is low ({d:.1}x)\n", .{self.metrics.build_speedup_ratio});
            try writer.print("    Consider improving caching strategy or reducing build overhead\n");
        }
    }
};

// Tests

test "BuildCacheManager basic functionality" {
    const allocator = testing.allocator;

    const config = try BuildCacheManager.CacheConfig.default(allocator);
    defer allocator.free(config.cache_directory);

    var cache_manager = try BuildCacheManager.init(allocator, config);
    defer cache_manager.deinit();

    // Start build session
    try cache_manager.startBuildSession();

    // Test build session
    try testing.expect(cache_manager.build_session.session_id > 0);
    try testing.expect(cache_manager.build_session.start_time > 0);

    // End build session
    try cache_manager.endBuildSession();

    // Check metrics
    const metrics = cache_manager.getMetrics();
    try testing.expect(metrics.total_build_time_ns > 0);
}

test "BuildSession file tracking" {
    const allocator = testing.allocator;

    var session = BuildCacheManager.BuildSession.init(allocator);
    defer session.deinit(allocator);

    // Add source file
    const dependencies = [_][]const u8{ "dep1.jan", "dep2.jan" };
    try session.addSourceFile(allocator, "test.jan", 12345, 0xABCD, &dependencies);

    // Verify file was added
    try testing.expect(session.source_files.count() == 1);

    const file_info = session.source_files.get("test.jan").?;
    try testing.expectEqualStrings("test.jan", file_info.path);
    try testing.expectEqual(@as(u64, 12345), file_info.last_modified);
    try testing.expectEqual(@as(u64, 0xABCD), file_info.content_hash);
    try testing.expectEqual(@as(usize, 2), file_info.dependencies.len);
}

test "DependencyTracker functionality" {
    const allocator = testing.allocator;

    var tracker = BuildCacheManager.DependencyTracker.init(allocator);
    defer tracker.deinit();

    // Add dependencies
    try tracker.addDependency("main.jan", "utils.jan", 12345, 0x1111);
    try tracker.addDependency("main.jan", "types.jan", 12346, 0x2222);
    try tracker.addDependency("other.jan", "utils.jan", 12345, 0x1111);

    // Test dependency lookup
    const utils_dependents = tracker.getDependents("utils.jan").?;
    try testing.expectEqual(@as(usize, 2), utils_dependents.len);

    // Test change detection
    try testing.expect(!tracker.hasChanged("utils.jan", 12345, 0x1111)); // No change
    try testing.expect(tracker.hasChanged("utils.jan", 12347, 0x1111)); // Time changed
    try testing.expect(tracker.hasChanged("utils.jan", 12345, 0x3333)); // Hash changed
}

test "BuildMetrics calculations" {
    var metrics = BuildCacheManager.BuildMetrics{
        .total_build_time_ns = 1000000,
        .cache_lookup_time_ns = 100000,
        .serialization_time_ns = 50000,
        .optimization_time_ns = 200000,
        .tables_from_cache = 8,
        .tables_built_fresh = 2,
        .tables_optimized = 5,
        .cache_hit_ratio = 0.0,
        .build_speedup_ratio = 0.0,
    };

    // Test cache hit ratio calculation
    metrics.calculateCacheHitRatio();
    try testing.expectEqual(@as(f64, 0.8), metrics.cache_hit_ratio); // 8/(8+2) = 0.8

    // Test speedup ratio calculation
    metrics.calculateSpeedupRatio(2000000); // 2x baseline
    try testing.expectEqual(@as(f64, 2.0), metrics.build_speedup_ratio);
}
