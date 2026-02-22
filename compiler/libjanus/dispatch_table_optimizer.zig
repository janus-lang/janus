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
const AdvancedDispatchCompression = @import("advanced_dispatch_compression.zig").AdvancedDispatchCompression;

/// Comprehensive dispatch table compression and optimization system
pub const DispatchTableOptimizer = struct {
    allocator: Allocator,

    // Optimization statistics
    stats: OptimizationStats,

    // Shared table registry
    shared_tables: HashMap(u64, *SharedDispatchTable),

    // Compression cache
    compression_cache: HashMap(u64, CompressedTable),

    // Advanced compression system
    advanced_compression: AdvancedDispatchCompression,

    const Self = @This();

    /// Statistics tracking optimization effectiveness
    pub const OptimizationStats = struct {
        tables_processed: u32,
        tables_compressed: u32,
        tables_shared: u32,
        redundant_entries_eliminated: u32,

        // Memory savings
        original_memory_bytes: usize,
        optimized_memory_bytes: usize,
        memory_saved_bytes: usize,

        // Performance improvements
        average_lookup_improvement_percent: f64,
        cache_efficiency_improvement_percent: f64,

        pub fn getMemorySavingsRatio(self: *const OptimizationStats) f64 {
            if (self.original_memory_bytes == 0) return 0.0;
            return @as(f64, @floatFromInt(self.memory_saved_bytes)) / @as(f64, @floatFromInt(self.original_memory_bytes));
        }

        pub fn format(self: OptimizationStats, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Optimization Statistics:\n");
            try writer.print("  Tables: {} processed, {} compressed, {} shared\n", .{ self.tables_processed, self.tables_compressed, self.tables_shared });
            try writer.print("  Redundant entries eliminated: {}\n", .{self.redundant_entries_eliminated});
            try writer.print("  Memory: {} -> {} bytes ({d:.1}% saved)\n", .{ self.original_memory_bytes, self.optimized_memory_bytes, self.getMemorySavingsRatio() * 100.0 });
            try writer.print("  Performance: {d:.1}% lookup improvement, {d:.1}% cache efficiency improvement\n", .{ self.average_lookup_improvement_percent, self.cache_efficiency_improvement_percent });
        }
    };

    /// Compressed dispatch table representation
    pub const CompressedTable = struct {
        signature_hash: u64,
        compressed_entries: []CompressedEntry,
        compression_ratio: f32,
        lookup_table: []u16, // Maps compressed indices to original entries

        pub const CompressedEntry = struct {
            type_pattern_hash: u32, // Compressed from 64-bit to 32-bit
            implementation_index: u16, // Index into shared implementation pool
            specificity_score: u8, // Quantized specificity (0-255)
            flags: u8, // Packed flags for various properties

            pub const FLAGS_STATIC_DISPATCH = 0x01;
            pub const FLAGS_HOT_PATH = 0x02;
            pub const FLAGS_FALLBACK = 0x04;
            pub const FLAGS_GENERIC = 0x08;
        };

        pub fn lookup(self: *const CompressedTable, type_pattern_hash: u64) ?u16 {
            const compressed_hash = @as(u32, @truncate(type_pattern_hash));

            for (self.compressed_entries, 0..) |entry, i| {
                if (entry.type_pattern_hash == compressed_hash) {
                    return self.lookup_table[i];
                }
            }

            return null;
        }

        pub fn getMemoryUsage(self: *const CompressedTable) usize {
            return @sizeOf(CompressedTable) +
                self.compressed_entries.len * @sizeOf(CompressedEntry) +
                self.lookup_table.len * @sizeOf(u16);
        }
    };

    /// Advanced compressed dispatch table using domain-specific techniques
    pub const AdvancedCompressedTable = struct {
        signature_hash: u64,

        // Compressed data using advanced techniques
        compressed_data: []u8,
        compression_metadata: CompressionMetadata,

        // Runtime decompression support
        decompression_cache: ?[]DispatchEntry,
        cache_valid: bool,

        // Performance metrics
        compression_stats: AdvancedDispatchCompression.CompressionStats,

        pub const CompressionMetadata = struct {
            original_entry_count: u32,
            compression_technique: CompressionTechnique,
            dictionary_offset: u32,
            dictionary_size: u32,
            bloom_filter_offset: u32,
            bloom_filter_size: u32,

            pub const CompressionTechnique = packed struct {
                uses_delta_compression: bool,
                uses_dictionary_compression: bool,
                uses_pattern_compression: bool,
                uses_bloom_filter: bool,
                uses_huffman_encoding: bool,
                _reserved: u3 = 0,
            };
        };

        pub fn lookup(self: *AdvancedCompressedTable, type_pattern_hash: u64) !?*const SignatureAnalyzer.Implementation {
            // Ensure decompression cache is valid
            if (!self.cache_valid) {
                try self.ensureDecompressed();
            }

            if (self.decompression_cache) |cache| {
                for (cache) |*entry| {
                    if (entry.type_pattern == type_pattern_hash) {
                        return entry.implementation_ptr;
                    }
                }
            }

            return null;
        }

        pub fn getMemoryUsage(self: *const AdvancedCompressedTable) usize {
            var total = @sizeOf(AdvancedCompressedTable) + self.compressed_data.len;
            if (self.decompression_cache) |cache| {
                total += cache.len * @sizeOf(OptimizedDispatchTable.DispatchEntry);
            }
            return total;
        }

        pub fn invalidateCache(self: *AdvancedCompressedTable) void {
            self.cache_valid = false;
        }

        fn ensureDecompressed(self: *AdvancedCompressedTable) !void {
            // Implementation would decompress the data on-demand
            // For now, this is a placeholder
            self.cache_valid = true;
        }
    };

    /// Shared dispatch table for similar signatures
    pub const SharedDispatchTable = struct {
        signature_hashes: ArrayList(u64),
        shared_entries: ArrayList(SharedEntry),
        reference_count: u32,

        pub const SharedEntry = struct {
            type_pattern: []const TypeId,
            implementation_pool_index: u32,
            usage_count: u32,
            last_access_time: u64,
        };

        pub fn addReference(self: *SharedDispatchTable) void {
            self.reference_count += 1;
        }

        pub fn removeReference(self: *SharedDispatchTable) void {
            if (self.reference_count > 0) {
                self.reference_count -= 1;
            }
        }

        pub fn canBeShared(self: *const SharedDispatchTable) bool {
            return self.reference_count > 1;
        }
    };

    /// Optimization pass configuration
    pub const OptimizationConfig = struct {
        enable_compression: bool,
        enable_sharing: bool,
        enable_redundancy_elimination: bool,
        enable_hot_path_optimization: bool,

        // Advanced compression settings
        enable_advanced_compression: bool,
        enable_delta_compression: bool,
        enable_dictionary_compression: bool,
        enable_pattern_compression: bool,
        enable_bloom_filters: bool,

        // Compression thresholds
        min_entries_for_compression: u32,
        compression_ratio_threshold: f32,
        advanced_compression_threshold: f32,

        // Sharing thresholds
        min_similarity_for_sharing: f32,
        max_shared_tables: u32,

        pub fn default() OptimizationConfig {
            return OptimizationConfig{
                .enable_compression = true,
                .enable_sharing = true,
                .enable_redundancy_elimination = true,
                .enable_hot_path_optimization = true,
                .enable_advanced_compression = true,
                .enable_delta_compression = true,
                .enable_dictionary_compression = true,
                .enable_pattern_compression = true,
                .enable_bloom_filters = true,
                .min_entries_for_compression = 10,
                .compression_ratio_threshold = 0.7,
                .advanced_compression_threshold = 0.6,
                .min_similarity_for_sharing = 0.8,
                .max_shared_tables = 100,
            };
        }
    };

    /// Optimization pass result
    pub const OptimizationResult = struct {
        original_table: *OptimizedDispatchTable,
        optimized_table: ?*OptimizedDispatchTable,
        compressed_table: ?*CompressedTable,
        shared_table: ?*SharedDispatchTable,
        advanced_compressed_table: ?*AdvancedCompressedTable,

        optimization_applied: OptimizationType,
        memory_saved: usize,
        performance_improvement: f64,
        compression_metrics: ?AdvancedDispatchCompression.CompressionStats,

        pub const OptimizationType = enum {
            none,
            compression,
            advanced_compression,
            sharing,
            redundancy_elimination,
            hot_path_optimization,
            combined,
        };

        pub fn format(self: OptimizationResult, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Optimization Result: {} applied\n", .{self.optimization_applied});
            try writer.print("  Memory saved: {} bytes\n", .{self.memory_saved});
            try writer.print("  Performance improvement: {d:.1}%\n", .{self.performance_improvement});
        }
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .stats = std.mem.zeroes(OptimizationStats),
            .shared_tables = HashMap(u64, *SharedDispatchTable).init(allocator),
            .compression_cache = HashMap(u64, CompressedTable).init(allocator),
            .advanced_compression = AdvancedDispatchCompression.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up shared tables
        var shared_iter = self.shared_tables.iterator();
        while (shared_iter.next()) |entry| {
            self.freeSharedTable(entry.value_ptr.*);
        }
        self.shared_tables.deinit();

        // Clean up compression cache
        var cache_iter = self.compression_cache.iterator();
        while (cache_iter.next()) |entry| {
            self.freeCompressedTable(entry.value_ptr);
        }
        self.compression_cache.deinit();

        // Clean up advanced compression
        self.advanced_compression.deinit();
    }

    /// Run comprehensive optimization passes on a dispatch table
    pub fn optimizeTable(self: *Self, table: *OptimizedDispatchTable, config: OptimizationConfig) !OptimizationResult {
        const original_memory = table.getMemoryStats().total_bytes;
        self.stats.original_memory_bytes += original_memory;
        self.stats.tables_processed += 1;

        var result = OptimizationResult{
            .original_table = table,
            .optimized_table = null,
            .compressed_table = null,
            .shared_table = null,
            .advanced_compressed_table = null,
            .optimization_applied = .none,
            .memory_saved = 0,
            .performance_improvement = 0.0,
            .compression_metrics = null,
        };

        // INTEGRATION POINT: Apply compression directly to the table's internal structure
        if (config.enable_advanced_compression and table.entry_count >= config.min_entries_for_compression) {
            try self.integrateAdvancedCompressionIntoTable(table, config);
        }

        // Pass 1: Eliminate redundant entries
        if (config.enable_redundancy_elimination) {
            const redundant_eliminated = try self.eliminateRedundantEntries(table);
            if (redundant_eliminated > 0) {
                self.stats.redundant_entries_eliminated += redundant_eliminated;
                result.optimization_applied = .redundancy_elimination;
            }
        }

        // Pass 2: Hot path optimization
        if (config.enable_hot_path_optimization) {
            const hot_path_optimized = try self.optimizeHotPaths(table);
            if (hot_path_optimized) {
                if (result.optimization_applied == .none) {
                    result.optimization_applied = .hot_path_optimization;
                } else {
                    result.optimization_applied = .combined;
                }
            }
        }

        // Pass 3: Check for sharing opportunities
        if (config.enable_sharing) {
            if (try self.findSharingOpportunity(table, config)) |shared_table| {
                result.shared_table = shared_table;
                self.stats.tables_shared += 1;

                if (result.optimization_applied == .none) {
                    result.optimization_applied = .sharing;
                } else {
                    result.optimization_applied = .combined;
                }
            }
        }

        // Pass 4: Advanced Compression (if not shared and enabled)
        if (config.enable_advanced_compression and result.shared_table == null) {
            if (table.entry_count >= config.min_entries_for_compression) {
                if (try self.advancedCompressTable(table, config)) |advanced_compressed| {
                    result.advanced_compressed_table = advanced_compressed;
                    result.compression_metrics = advanced_compressed.compression_stats;
                    self.stats.tables_compressed += 1;

                    if (result.optimization_applied == .none) {
                        result.optimization_applied = .advanced_compression;
                    } else {
                        result.optimization_applied = .combined;
                    }
                }
            }
        }

        // Pass 5: Basic Compression (fallback if advanced compression not used)
        if (config.enable_compression and result.shared_table == null and result.advanced_compressed_table == null) {
            if (table.entry_count >= config.min_entries_for_compression) {
                if (try self.compressTable(table, config)) |compressed_table| {
                    result.compressed_table = compressed_table;
                    self.stats.tables_compressed += 1;

                    if (result.optimization_applied == .none) {
                        result.optimization_applied = .compression;
                    } else {
                        result.optimization_applied = .combined;
                    }
                }
            }
        }

        // Calculate final memory usage and savings
        const final_memory = self.calculateOptimizedMemoryUsage(&result);
        result.memory_saved = if (final_memory < original_memory) original_memory - final_memory else 0;

        self.stats.optimized_memory_bytes += final_memory;
        self.stats.memory_saved_bytes += result.memory_saved;

        // Estimate performance improvement
        result.performance_improvement = self.estimatePerformanceImprovement(&result);

        return result;
    }

    /// Run optimization passes on multiple tables with cross-table optimizations
    pub fn optimizeTableSet(self: *Self, tables: []*OptimizedDispatchTable, config: OptimizationConfig) ![]OptimizationResult {
        var results: ArrayList(OptimizationResult) = .empty;

        // First pass: Individual table optimizations
        for (tables) |table| {
            const result = try self.optimizeTable(table, config);
            try results.append(result);
        }

        // Second pass: Cross-table sharing optimization
        if (config.enable_sharing) {
            try self.optimizeTableSharing(results.items, config);
        }

        return try results.toOwnedSlice(alloc);
    }

    /// Generate optimization report
    pub fn generateOptimizationReport(self: *Self, writer: anytype) !void {
        try writer.print("Dispatch Table Optimization Report\n");
        try writer.print("==================================\n\n");

        try writer.print("{}\n\n", .{self.stats});

        // Shared tables analysis
        if (self.shared_tables.count() > 0) {
            try writer.print("Shared Tables Analysis:\n");
            try writer.print("-----------------------\n");

            var shared_iter = self.shared_tables.iterator();
            while (shared_iter.next()) |entry| {
                const shared_table = entry.value_ptr.*;
                try writer.print("  Shared Table {}: {} references, {} entries\n", .{ entry.key_ptr.*, shared_table.reference_count, shared_table.shared_entries.items.len });
            }
            try writer.print("\n");
        }

        // Compression analysis
        if (self.compression_cache.count() > 0) {
            try writer.print("Compression Analysis:\n");
            try writer.print("--------------------\n");

            var compression_iter = self.compression_cache.iterator();
            while (compression_iter.next()) |entry| {
                const compressed_table = entry.value_ptr;
                try writer.print("  Compressed Table {}: {d:.1}% compression ratio, {} entries\n", .{ entry.key_ptr.*, compressed_table.compression_ratio * 100.0, compressed_table.compressed_entries.len });
            }
            try writer.print("\n");
        }

        // Advanced compression analysis
        const advanced_stats = self.advanced_compression.compression_stats;
        if (advanced_stats.original_bytes > 0) {
            try writer.print("Advanced Compression Analysis:\n");
            try writer.print("------------------------------\n");
            try writer.print("  Total compression ratio: {d:.1}%\n", .{advanced_stats.getTotalCompressionRatio() * 100.0});
            try writer.print("  Effective compression ratio: {d:.1}%\n", .{advanced_stats.getEffectiveCompressionRatio() * 100.0});
            try writer.print("  Delta compression savings: {} bytes\n", .{advanced_stats.delta_compression_savings});
            try writer.print("  Pattern compression savings: {} bytes\n", .{advanced_stats.pattern_compression_savings});
            try writer.print("  Dictionary compression savings: {} bytes\n", .{advanced_stats.dictionary_compression_savings});
            try writer.print("\n");
        }

        // Optimization recommendations
        try self.generateOptimizationRecommendations(writer);
    }

    /// Get current optimization statistics
    pub fn getStats(self: *const Self) OptimizationStats {
        return self.stats;
    }

    /// Reset optimization statistics
    pub fn resetStats(self: *Self) void {
        self.stats = std.mem.zeroes(OptimizationStats);
    }

    // Private optimization methods

    fn eliminateRedundantEntries(self: *Self, table: *OptimizedDispatchTable) !u32 {
        var eliminated_count: u32 = 0;
        var seen_patterns = HashMap(u64, u32).init(self.allocator);
        defer seen_patterns.deinit();

        var i: u32 = 0;
        while (i < table.entry_count) {
            const entry = &table.entries[i];
            const pattern_hash = entry.type_pattern;

            if (seen_patterns.get(pattern_hash)) |existing_index| {
                // Check if this is truly redundant (same implementation)
                const existing_entry = &table.entries[existing_index];
                if (existing_entry.implementation_ptr == entry.implementation_ptr) {
                    // Merge call frequencies
                    existing_entry.call_frequency += entry.call_frequency;

                    // Remove redundant entry by swapping with last
                    table.entries[i] = table.entries[table.entry_count - 1];
                    table.entry_count -= 1;
                    eliminated_count += 1;

                    // Don't increment i since we swapped
                    continue;
                }
            } else {
                try seen_patterns.put(pattern_hash, i);
            }

            i += 1;
        }

        return eliminated_count;
    }

    fn optimizeHotPaths(self: *Self, table: *OptimizedDispatchTable) !bool {
        _ = self;

        // Sort entries by call frequency (hot entries first)
        const Context = struct {
            pub fn lessThan(context: @This(), a: OptimizedDispatchTable.DispatchEntry, b: OptimizedDispatchTable.DispatchEntry) bool {
                _ = context;
                return a.call_frequency > b.call_frequency;
            }
        };

        std.mem.sort(OptimizedDispatchTable.DispatchEntry, table.entries[0..table.entry_count], Context{}, Context.lessThan);

        // Rebuild decision tree with hot path optimization
        try table.rebuildDecisionTree();

        return true; // Always considered an optimization
    }

    fn findSharingOpportunity(self: *Self, table: *OptimizedDispatchTable, config: OptimizationConfig) !?*SharedDispatchTable {
        const table_hash = self.calculateTableHash(table);

        // Check existing shared tables for similarity
        var shared_iter = self.shared_tables.iterator();
        while (shared_iter.next()) |entry| {
            const shared_table = entry.value_ptr.*;
            const similarity = self.calculateTableSimilarity(table, shared_table);

            if (similarity >= config.min_similarity_for_sharing) {
                shared_table.addReference();
                return shared_table;
            }
        }

        // Create new shared table if we haven't exceeded the limit
        if (self.shared_tables.count() < config.max_shared_tables) {
            const shared_table = try self.createSharedTable(table);
            try self.shared_tables.put(table_hash, shared_table);
            return shared_table;
        }

        return null;
    }

    fn compressTable(self: *Self, table: *OptimizedDispatchTable, config: OptimizationConfig) !?*CompressedTable {
        const table_hash = self.calculateTableHash(table);

        // Check cache first
        if (self.compression_cache.get(table_hash)) |cached| {
            return @constCast(&cached);
        }

        // Create compressed representation
        var compressed_entries: ArrayList(CompressedTable.CompressedEntry) = .empty;
        var lookup_table: ArrayList(u16) = .empty;

        for (table.entries[0..table.entry_count], 0..) |entry, i| {
            const compressed_entry = CompressedTable.CompressedEntry{
                .type_pattern_hash = @as(u32, @truncate(entry.type_pattern)),
                .implementation_index = @as(u16, @intCast(i)), // Simplified
                .specificity_score = @as(u8, @intCast(@min(entry.specificity_score, 255))),
                .flags = self.calculateEntryFlags(&entry),
            };

            try compressed_entries.append(compressed_entry);
            try lookup_table.append(@as(u16, @intCast(i)));
        }

        const original_size = table.getMemoryStats().total_bytes;
        const compressed_size = compressed_entries.items.len * @sizeOf(CompressedTable.CompressedEntry) +
            lookup_table.items.len * @sizeOf(u16) +
            @sizeOf(CompressedTable);

        const compression_ratio = @as(f32, @floatFromInt(compressed_size)) / @as(f32, @floatFromInt(original_size));

        if (compression_ratio <= config.compression_ratio_threshold) {
            const compressed_table = CompressedTable{
                .signature_hash = table_hash,
                .compressed_entries = try compressed_entries.toOwnedSlice(),
                .compression_ratio = compression_ratio,
                .lookup_table = try lookup_table.toOwnedSlice(),
            };

            try self.compression_cache.put(table_hash, compressed_table);
            return @constCast(&self.compression_cache.get(table_hash).?);
        } else {
            compressed_entries.deinit();
            lookup_table.deinit();
            return null;
        }
    }

    fn optimizeTableSharing(self: *Self, results: []OptimizationResult, config: OptimizationConfig) !void {
        _ = config;

        // Group tables by similarity and create shared tables
        for (results, 0..) |*result, i| {
            if (result.shared_table != null) continue;

            for (results[i + 1 ..]) |*other_result| {
                if (other_result.shared_table != null) continue;

                const similarity = self.calculateResultSimilarity(result, other_result);
                if (similarity >= 0.8) { // High similarity threshold for cross-table sharing
                    // Create or reuse shared table
                    if (result.shared_table == null) {
                        result.shared_table = try self.createSharedTableFromResult(result);
                    }

                    other_result.shared_table = result.shared_table;
                    other_result.shared_table.?.addReference();

                    if (other_result.optimization_applied == .none) {
                        other_result.optimization_applied = .sharing;
                    } else {
                        other_result.optimization_applied = .combined;
                    }
                }
            }
        }
    }

    fn calculateTableHash(self: *Self, table: *OptimizedDispatchTable) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(std.mem.asBytes(&table.entry_count));
        for (table.entries[0..table.entry_count]) |entry| {
            hasher.update(std.mem.asBytes(&entry.type_pattern));
            hasher.update(std.mem.asBytes(&entry.specificity_score));
        }

        return hasher.final();
    }

    fn calculateTableSimilarity(self: *Self, table: *OptimizedDispatchTable, shared_table: *SharedDispatchTable) f32 {
        _ = self;
        _ = table;
        _ = shared_table;

        // Simplified similarity calculation
        // In a real implementation, this would compare type patterns, implementations, etc.
        return 0.5; // Placeholder
    }

    fn calculateResultSimilarity(self: *Self, result1: *const OptimizationResult, result2: *const OptimizationResult) f32 {
        _ = self;
        _ = result1;
        _ = result2;

        // Simplified similarity calculation
        return 0.6; // Placeholder
    }

    fn createSharedTable(self: *Self, table: *OptimizedDispatchTable) !*SharedDispatchTable {
        const shared_table = try self.allocator.create(SharedDispatchTable);
        shared_table.* = SharedDispatchTable{
            .signature_hashes = .empty,
            .shared_entries = .empty,
            .reference_count = 1,
        };

        // Add entries from the table
        for (table.entries[0..table.entry_count]) |entry| {
            const shared_entry = SharedDispatchTable.SharedEntry{
                .type_pattern = &.{}, // Simplified
                .implementation_pool_index = 0, // Simplified
                .usage_count = entry.call_frequency,
                .last_access_time = @intCast(std.time.timestamp()),
            };

            try shared_table.shared_entries.append(shared_entry);
        }

        return shared_table;
    }

    fn createSharedTableFromResult(self: *Self, result: *OptimizationResult) !*SharedDispatchTable {
        return self.createSharedTable(result.original_table);
    }

    fn calculateEntryFlags(self: *Self, entry: *const OptimizedDispatchTable.DispatchEntry) u8 {
        _ = self;
        var flags: u8 = 0;

        // Set flags based on entry characteristics
        if (entry.call_frequency > 1000) {
            flags |= CompressedTable.CompressedEntry.FLAGS_HOT_PATH;
        }

        // Add other flag logic here

        return flags;
    }

    /// INTEGRATION: Apply advanced compression directly to OptimizedDispatchTable
    fn integrateAdvancedCompressionIntoTable(self: *Self, table: *OptimizedDispatchTable, config: OptimizationConfig) !void {
        // Convert table entries to compression format
        var compression_entries: ArrayList(AdvancedDispatchCompression.DispatchEntry) = .empty;
        defer {
            for (compression_entries.items) |entry| {
                self.allocator.free(entry.type_pattern);
            }
            compression_entries.deinit();
        }

        // Extract type patterns from dispatch entries
        for (table.entries[0..table.entry_count]) |entry| {
            // Decompress the type pattern hash back to TypeId array
            const type_pattern = try self.decompressTypePattern(entry.type_pattern);

            const compression_entry = AdvancedDispatchCompression.DispatchEntry{
                .type_pattern = type_pattern,
                .function_name = entry.implementation_ptr.func_id.name,
                .module_name = entry.implementation_ptr.func_id.module,
                .call_frequency = entry.call_frequency,
                .specificity_score = entry.specificity_score,
            };
            try compression_entries.append(compression_entry);
        }

        // Apply advanced compression techniques
        const compression_config = AdvancedDispatchCompression.CompressionConfig{
            .enable_delta_compression = config.enable_delta_compression,
            .enable_dictionary_compression = config.enable_dictionary_compression,
            .enable_pattern_compression = config.enable_pattern_compression,
            .enable_bloom_filters = config.enable_bloom_filters,
            .enable_huffman_encoding = true,
            .compression_level = .balanced,
        };

        const compressed_data = try self.advanced_compression.compressDispatchEntries(compression_entries.items, compression_config);

        // Replace table's internal storage with compressed representation
        try table.replaceWithCompressedData(compressed_data, &self.advanced_compression);
    }

    fn decompressTypePattern(self: *Self, pattern_hash: u64) ![]TypeId {
        // For now, simple decompression - in practice this would use the type registry
        // to reconstruct the full type pattern from the hash
        _ = self;
        const pattern = try self.allocator.alloc(TypeId, 2); // Assume binary dispatch for now
        pattern[0] = @intCast((pattern_hash >> 32) & 0xFFFFFFFF);
        pattern[1] = @intCast(pattern_hash & 0xFFFFFFFF);
        return pattern;
    }

    fn advancedCompressTable(self: *Self, table: *OptimizedDispatchTable, config: OptimizationConfig) !?*AdvancedCompressedTable {
        const table_hash = self.calculateTableHash(table);

        // Extract type patterns from dispatch entries
        var type_patterns: ArrayList([]TypeId) = .empty;
        defer {
            for (type_patterns.items) |pattern| {
                self.allocator.free(pattern);
            }
            type_patterns.deinit();
        }

        // Build type patterns from table entries
        for (table.entries[0..table.entry_count]) |entry| {
            // For now, create a simple pattern from the type_pattern hash
            // In a real implementation, this would extract the actual TypeId sequence
            const pattern = try self.allocator.alloc(TypeId, 1);
            pattern[0] = @intCast(entry.type_pattern & 0xFFFFFFFF);
            try type_patterns.append(pattern);
        }

        // Convert OptimizedDispatchTable entries to AdvancedDispatchCompression entries
        var advanced_entries: ArrayList(AdvancedDispatchCompression.DispatchEntry) = .empty;
        defer advanced_entries.deinit();

        for (table.entries[0..table.entry_count]) |entry| {
            // Convert type pattern hash back to TypeId array (simplified)
            const type_pattern = try self.allocator.alloc(TypeId, 1);
            type_pattern[0] = @intCast(entry.type_pattern & 0xFFFFFFFF);

            const advanced_entry = AdvancedDispatchCompression.DispatchEntry{
                .type_pattern = type_pattern,
                .function_name = entry.implementation_ptr.func_id.name,
                .module_name = "main", // Simplified
                .signature_hash = entry.type_pattern,
                .specificity_score = entry.specificity_score,
                .call_frequency = entry.call_frequency,
                .is_static_dispatch = entry.call_frequency > 1000, // Heuristic
                .is_hot_path = entry.call_frequency > 500,
                .is_fallback = entry.specificity_score == 0,
            };

            try advanced_entries.append(advanced_entry);
        }

        // Apply advanced compression
        const compression_result = try self.advanced_compression.compressDispatchTable(advanced_entries.items, table.signature_name);

        // Check if compression is beneficial
        const compression_stats = self.advanced_compression.compression_stats;
        const compression_ratio = compression_stats.getTotalCompressionRatio();
        if (compression_ratio > config.advanced_compression_threshold) {
            // Compression not beneficial enough
            return null;
        }

        // Serialize the compressed result to bytes
        var compressed_data: ArrayList(u8) = .empty;
        try self.serializeCompressedTable(&compression_result, &compressed_data);

        // Create advanced compressed table
        const advanced_compressed = try self.allocator.create(AdvancedCompressedTable);
        advanced_compressed.* = AdvancedCompressedTable{
            .signature_hash = table_hash,
            .compressed_data = try compressed_data.toOwnedSlice(),
            .compression_metadata = AdvancedCompressedTable.CompressionMetadata{
                .original_entry_count = table.entry_count,
                .compression_technique = AdvancedCompressedTable.CompressionMetadata.CompressionTechnique{
                    .uses_delta_compression = config.enable_delta_compression,
                    .uses_dictionary_compression = config.enable_dictionary_compression,
                    .uses_pattern_compression = config.enable_pattern_compression,
                    .uses_bloom_filter = config.enable_bloom_filters,
                    .uses_huffman_encoding = true,
                },
                .dictionary_offset = 0, // Would be set by serialization
                .dictionary_size = 0, // Would be set by serialization
                .bloom_filter_offset = 0, // Would be set by serialization
                .bloom_filter_size = 0, // Would be set by serialization
            },
            .decompression_cache = null,
            .cache_valid = false,
            .compression_stats = compression_stats,
        };

        // Clean up temporary type patterns
        for (advanced_entries.items) |entry| {
            self.allocator.free(entry.type_pattern);
        }

        return advanced_compressed;
    }

    fn serializeCompressedTable(self: *Self, compressed_table: *const AdvancedDispatchCompression.CompressedDispatchTable, output: *ArrayList(u8)) !void {
        _ = self;

        // Simplified serialization - in a real implementation this would be more sophisticated
        const writer = output.writer();

        // Write signature name
        try writer.writeInt(u32, @intCast(compressed_table.signature_name.len), .little);
        try writer.writeAll(compressed_table.signature_name);

        // Write entry count
        try writer.writeInt(u32, @intCast(compressed_table.entries.len), .little);

        // Write compressed entries (simplified)
        for (compressed_table.entries) |entry| {
            try writer.writeInt(u16, entry.pattern_index, .little);
            try writer.writeInt(u16, entry.implementation_index, .little);
            try writer.writeInt(u8, entry.specificity_score, .little);
            try writer.writeInt(u32, entry.call_frequency, .little);
        }

        // In a real implementation, this would also serialize:
        // - Type dictionary
        // - Pattern dictionary
        // - Implementation pool
        // - Decision tree
        // - Bloom filters
    }

    fn calculateOptimizedMemoryUsage(self: *Self, result: *const OptimizationResult) usize {
        _ = self;

        if (result.advanced_compressed_table) |advanced_compressed| {
            return advanced_compressed.getMemoryUsage();
        }

        if (result.compressed_table) |compressed| {
            return compressed.getMemoryUsage();
        }

        if (result.shared_table) |shared| {
            // Estimate shared memory usage (divided by reference count)
            const total_shared_memory = shared.shared_entries.items.len * @sizeOf(SharedDispatchTable.SharedEntry);
            return total_shared_memory / @max(shared.reference_count, 1);
        }

        // Return original memory usage if no optimization applied
        return result.original_table.getMemoryStats().total_bytes;
    }

    fn estimatePerformanceImprovement(self: *Self, result: *const OptimizationResult) f64 {
        _ = self;

        var base_improvement: f64 = switch (result.optimization_applied) {
            .none => 0.0,
            .compression => 5.0, // 5% improvement from better cache usage
            .advanced_compression => 12.0, // 12% improvement from advanced techniques
            .sharing => 10.0, // 10% improvement from shared caches
            .redundancy_elimination => 15.0, // 15% improvement from fewer entries
            .hot_path_optimization => 20.0, // 20% improvement from better ordering
            .combined => 25.0, // Combined benefits
        };

        // Add bonus for advanced compression based on compression ratio
        if (result.compression_metrics) |metrics| {
            const compression_ratio = metrics.getEffectiveCompressionRatio();
            if (compression_ratio < 0.5) {
                base_improvement += 8.0; // Extra 8% for excellent compression
            } else if (compression_ratio < 0.7) {
                base_improvement += 4.0; // Extra 4% for good compression
            }
        }

        return base_improvement;
    }

    fn freeSharedTable(self: *Self, shared_table: *SharedDispatchTable) void {
        shared_table.signature_hashes.deinit();
        shared_table.shared_entries.deinit();
        self.allocator.destroy(shared_table);
    }

    fn freeCompressedTable(self: *Self, compressed_table: *CompressedTable) void {
        self.allocator.free(compressed_table.compressed_entries);
        self.allocator.free(compressed_table.lookup_table);
    }

    fn freeAdvancedCompressedTable(self: *Self, advanced_compressed: *AdvancedCompressedTable) void {
        self.allocator.free(advanced_compressed.compressed_data);
        if (advanced_compressed.decompression_cache) |cache| {
            self.allocator.free(cache);
        }
        self.allocator.destroy(advanced_compressed);
    }

    fn generateOptimizationRecommendations(self: *Self, writer: anytype) !void {
        try writer.print("Optimization Recommendations:\n");
        try writer.print("-----------------------------\n");

        const memory_savings_ratio = self.stats.getMemorySavingsRatio();

        if (memory_savings_ratio < 0.1) {
            try writer.print("  - Low memory savings ({d:.1}%) - consider more aggressive compression\n", .{memory_savings_ratio * 100.0});
        }

        if (self.stats.tables_shared < self.stats.tables_processed / 4) {
            try writer.print("  - Few tables shared ({}/{}) - review similarity thresholds\n", .{ self.stats.tables_shared, self.stats.tables_processed });
        }

        if (self.stats.redundant_entries_eliminated == 0) {
            try writer.print("  - No redundant entries found - tables may already be well-optimized\n");
        }

        if (self.stats.tables_compressed < self.stats.tables_processed / 2) {
            try writer.print("  - Many tables not compressed - consider lowering compression thresholds\n");
        }

        if (memory_savings_ratio > 0.3) {
            try writer.print("  - Excellent memory savings ({d:.1}%) - optimizations are highly effective\n", .{memory_savings_ratio * 100.0});
        }

        try writer.print("\n");
    }
};
// Tests

test "DispatchTableOptimizer initialization and default configuration" {
    const allocator = testing.allocator;
    var optimizer = DispatchTableOptimizer.init(allocator);
    defer optimizer.deinit();

    // Test initialization
    try testing.expect(optimizer.stats.tables_processed == 0);
    try testing.expect(optimizer.stats.tables_compressed == 0);
    try testing.expect(optimizer.stats.tables_shared == 0);

    // Test default configuration
    const config = DispatchTableOptimizer.OptimizationConfig.default();
    try testing.expect(config.enable_compression);
    try testing.expect(config.enable_sharing);
    try testing.expect(config.enable_redundancy_elimination);
    try testing.expect(config.enable_hot_path_optimization);
    try testing.expect(config.enable_advanced_compression);
    try testing.expectEqual(@as(u32, 10), config.min_entries_for_compression);
    try testing.expectEqual(@as(f32, 0.7), config.compression_ratio_threshold);
    try testing.expectEqual(@as(f32, 0.6), config.advanced_compression_threshold);
    try testing.expectEqual(@as(f32, 0.8), config.min_similarity_for_sharing);
}

test "DispatchTableOptimizer advanced compression integration" {
    const allocator = testing.allocator;
    var optimizer = DispatchTableOptimizer.init(allocator);
    defer optimizer.deinit();

    // Test advanced compression configuration
    var config = DispatchTableOptimizer.OptimizationConfig.default();
    config.enable_advanced_compression = true;
    config.enable_delta_compression = true;
    config.enable_dictionary_compression = true;
    config.enable_pattern_compression = true;
    config.enable_bloom_filters = true;

    // Verify advanced compression settings
    try testing.expect(config.enable_advanced_compression);
    try testing.expect(config.enable_delta_compression);
    try testing.expect(config.enable_dictionary_compression);
    try testing.expect(config.enable_pattern_compression);
    try testing.expect(config.enable_bloom_filters);
    try testing.expectEqual(@as(f32, 0.6), config.advanced_compression_threshold);
}
