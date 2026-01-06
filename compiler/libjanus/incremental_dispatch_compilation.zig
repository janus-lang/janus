// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;

const DispatchBuildCache = @import("dispatch_build_cache.zig").DispatchBuildCache;
const ModuleDispatcher = @import("module_dispatch.zig").ModuleDispatcher;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchTableOptimizer = @import("dispatch_table_optimizer.zig").DispatchTableOptimizer;

/// Incremental compilation system for dispatch tables
/// Tracks changes and rebuilds only affected dispatch tables
pub const IncrementalDispatchCompilation = struct {
    allocator: Allocator,
    build_cache: DispatchBuildCache,
    dependency_tracker: DependencyTracker,
    change_detector: ChangeDetector,

    const Self = @This();

    pub fn init(allocator: Allocator, cache_dir: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .build_cache = try DispatchBuildCache.init(allocator, cache_dir),
            .dependency_tracker = DependencyTracker.init(allocator),
            .change_detector = ChangeDetector.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.build_cache.deinit();
        self.dependency_tracker.deinit();
        self.change_detector.deinit();
    }

    /// Perform incremental compilation of dispatch tables
    pub fn incrementalCompile(
        self: *Self,
        module_dispatcher: *ModuleDispatcher,
        source_files: []const []const u8,
        optimizer: *DispatchTableOptimizer,
    ) !IncrementalCompileResult {
        var result = IncrementalCompileResult.init(self.allocator);

        // Update build hash based on source files
        try self.build_cache.setBuildHash(source_files);

        // Detect changes in source files
        const changes = try self.change_detector.detectChanges(source_files);

        // Determine which signatures need recompilation
        const affected_signatures = try self.dependency_tracker.getAffectedSignatures(changes);

        // Load cached tables for unaffected signatures
        const all_signatures = try self.getAllSignatures(module_dispatcher);

        for (all_signatures) |signature_name| {
            if (self.isSignatureAffected(signature_name, affected_signatures)) {
                // Recompile affected signature
                const new_table = try self.recompileSignature(
                    module_dispatcher,
                    signature_name,
                    optimizer
                );

                // Cache the new table
                try self.build_cache.cacheTable(signature_name, new_table);

                try result.recompiled_signatures.append(signature_name);
                try result.new_tables.append(new_table);
            } else {
                // Try to load from cache
                if (try self.build_cache.loadTable(signature_name)) |cached_table| {
                    try result.cached_signatures.append(signature_name);
                    try result.cached_tables.append(cached_table);
                } else {
                    // Cache miss - need to recompile
                    const new_table = try self.recompileSignature(
                        module_dispatcher,
                        signature_name,
                        optimizer
                    );

                    try self.build_cache.cacheTable(signature_name, new_table);

                    try result.cache_misses.append(signature_name);
                    try result.new_tables.append(new_table);
                }
            }
        }

        // Update dependency tracking
        try self.dependency_tracker.updateDependencies(source_files, all_signatures);

        return result;
    }

    /// Get compilation statistics
    pub fn getCompilationStats(self: *Self) !CompilationStats {
        const cache_stats = try self.build_cache.getCacheStats();

        return CompilationStats{
            .cache_hit_rate = cache_stats.getHitRate(),
            .total_cached_files = cache_stats.total_files,
            .cache_size_bytes = cache_stats.total_size_bytes,
            .valid_cache_files = cache_stats.valid_files,
            .invalid_cache_files = cache_stats.invalid_files,
        };
    }

    /// Force recompilation of specific signature
    pub fn forceRecompile(
        self: *Self,
        module_dispatcher: *ModuleDispatcher,
        signature_name: []const u8,
        optimizer: *DispatchTableOptimizer,
    ) !*OptimizedDispatchTable {
        // Invalidate existing cache
        try self.build_cache.invalidateSignature(signature_name);

        // Recompile
        const new_table = try self.recompileSignature(module_dispatcher, signature_name, optimizer);

        // Cache the result
        try self.build_cache.cacheTable(signature_name, new_table);

        return new_table;
    }

    // Private helper methods
    fn recompileSignature(
        self: *Self,
        module_dispatcher: *ModuleDispatcher,
        signature_name: []const u8,
        optimizer: *DispatchTableOptimizer,
    ) !*OptimizedDispatchTable {
        _ = self;

        // Create dispatch table for signature
        const table = try module_dispatcher.createCompressedDispatchTable(signature_name);

        // Apply optimizations
        const config = DispatchTableOptimizer.OptimizationConfig.default();
        _ = try optimizer.optimizeTable(table, config);

        return table;
    }

    fn getAllSignatures(self: *Self, module_dispatcher: *ModuleDispatcher) ![][]const u8 {
        _ = self;
        _ = module_dispatcher;

        // This would extract all signature names from the module dispatcher
        // For now, return empty array as placeholder
        return &[_][]const u8{};
    }

    fn isSignatureAffected(self: *Self, signature_name: []const u8, affected_signatures: []const []const u8) bool {
        _ = self;

        for (affected_signatures) |affected| {
            if (std.mem.eql(u8, signature_name, affected)) {
                return true;
            }
        }
        return false;
    }
}
 // Helper structures for incremental compilation

    /// Tracks dependencies between source files and dispatch signatures
    const DependencyTracker = struct {
        allocator: Allocator,
        file_to_signatures: HashMap([]const u8, ArrayList([]const u8)),
        signature_to_files: HashMap([]const u8, ArrayList([]const u8)),

        pub fn init(allocator: Allocator) DependencyTracker {
            return DependencyTracker{
                .allocator = allocator,
                .file_to_signatures = HashMap([]const u8, ArrayList([]const u8)).init(allocator),
                .signature_to_files = HashMap([]const u8, ArrayList([]const u8)).init(allocator),
            };
        }

        pub fn deinit(self: *DependencyTracker) void {
            var file_iter = self.file_to_signatures.iterator();
            while (file_iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.file_to_signatures.deinit();

            var sig_iter = self.signature_to_files.iterator();
            while (sig_iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.signature_to_files.deinit();
        }

        pub fn updateDependencies(self: *DependencyTracker, source_files: []const []const u8, signatures: []const []const u8) !void {
            // Simplified dependency tracking - in practice would parse source files
            for (source_files) |file| {
                var file_signatures = ArrayList([]const u8).init(self.allocator);

                // For each signature, assume it could be in any file (simplified)
                for (signatures) |sig| {
                    try file_signatures.append(try self.allocator.dupe(u8, sig));
                }

                try self.file_to_signatures.put(try self.allocator.dupe(u8, file), file_signatures);
            }
        }

        pub fn getAffectedSignatures(self: *DependencyTracker, changed_files: []const []const u8) ![]const []const u8 {
            var affected = ArrayList([]const u8).init(self.allocator);
            defer affected.deinit();

            for (changed_files) |file| {
                if (self.file_to_signatures.get(file)) |signatures| {
                    for (signatures.items) |sig| {
                        try affected.append(sig);
                    }
                }
            }

            return affected.toOwnedSlice();
        }
    };

    /// Detects changes in source files
    const ChangeDetector = struct {
        allocator: Allocator,
        file_timestamps: HashMap([]const u8, i64),

        pub fn init(allocator: Allocator) ChangeDetector {
            return ChangeDetector{
                .allocator = allocator,
                .file_timestamps = HashMap([]const u8, i64).init(allocator),
            };
        }

        pub fn deinit(self: *ChangeDetector) void {
            self.file_timestamps.deinit();
        }

        pub fn detectChanges(self: *ChangeDetector, source_files: []const []const u8) ![]const []const u8 {
            var changed_files = ArrayList([]const u8).init(self.allocator);
            defer changed_files.deinit();

            for (source_files) |file_path| {
                const file = std.fs.cwd().openFile(file_path, .{}) catch continue;
                defer file.close();

                const stat = file.stat() catch continue;
                const current_mtime = stat.mtime;

                if (self.file_timestamps.get(file_path)) |last_mtime| {
                    if (current_mtime > last_mtime) {
                        try changed_files.append(file_path);
                        try self.file_timestamps.put(file_path, current_mtime);
                    }
                } else {
                    // New file
                    try changed_files.append(file_path);
                    try self.file_timestamps.put(try self.allocator.dupe(u8, file_path), current_mtime);
                }
            }

            return changed_files.toOwnedSlice();
        }
    };

    /// Result of incremental compilation
    pub const IncrementalCompileResult = struct {
        allocator: Allocator,
        recompiled_signatures: ArrayList([]const u8),
        cached_signatures: ArrayList([]const u8),
        cache_misses: ArrayList([]const u8),
        new_tables: ArrayList(*OptimizedDispatchTable),
        cached_tables: ArrayList(*OptimizedDispatchTable),

        pub fn init(allocator: Allocator) IncrementalCompileResult {
            return IncrementalCompileResult{
                .allocator = allocator,
                .recompiled_signatures = ArrayList([]const u8).init(allocator),
                .cached_signatures = ArrayList([]const u8).init(allocator),
                .cache_misses = ArrayList([]const u8).init(allocator),
                .new_tables = ArrayList(*OptimizedDispatchTable).init(allocator),
                .cached_tables = ArrayList(*OptimizedDispatchTable).init(allocator),
            };
        }

        pub fn deinit(self: *IncrementalCompileResult) void {
            self.recompiled_signatures.deinit();
            self.cached_signatures.deinit();
            self.cache_misses.deinit();
            self.new_tables.deinit();
            self.cached_tables.deinit();
        }

        pub fn getCacheHitRate(self: *const IncrementalCompileResult) f64 {
            const total = self.cached_signatures.items.len + self.recompiled_signatures.items.len + self.cache_misses.items.len;
            if (total == 0) return 0.0;
            return @as(f64, @floatFromInt(self.cached_signatures.items.len)) / @as(f64, @floatFromInt(total));
        }
    };

    /// Compilation statistics
    pub const CompilationStats = struct {
        cache_hit_rate: f64,
        total_cached_files: u32,
        cache_size_bytes: u64,
        valid_cache_files: u32,
        invalid_cache_files: u32,
    };
};
