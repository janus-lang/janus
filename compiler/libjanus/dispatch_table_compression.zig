// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;

// Optional compression backends
const zstd = @import("zstd"); // Optional: requires zstd dependency
const lz4 = @import("lz4"); // Optional: requires lz4 dependency

/// Dispatch table compression and optimization system
/// Implements various techniques to reduce memory usage and improve performance
pub const DispatchTableCompression = struct {
    allocator: Allocator,
    type_registry: *TypeRegistry,

    // Compression statistics
    compression_stats: CompressionStats,

    // Shared table registry for deduplication
    shared_tables: AutoHashMap(TableSignature, *SharedDispatchTable),

    // Optimization passes
    optimization_passes: ArrayList(OptimizationPass),

    pub const CompressionStats = struct {
        original_size_bytes: usize,
        compressed_size_bytes: usize,
        tables_compressed: u32,
        tables_shared: u32,
        redundant_entries_eliminated: u32,

        pub fn getCompressionRatio(self: *const CompressionStats) f64 {
            if (self.original_size_bytes == 0) return 1.0;
            return @as(f64, @floatFromInt(self.compressed_size_bytes)) / @as(f64, @floatFromInt(self.original_size_bytes));
        }

        pub fn getSpaceSaved(self: *const CompressionStats) usize {
            return self.original_size_bytes - self.compressed_size_bytes;
        }
    };

    pub const TableSignature = struct {
        signature_name: []const u8,
        type_pattern_hash: u64,
        implementation_count: u32,

        pub fn hash(self: *const TableSignature) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(self.signature_name);
            hasher.update(std.mem.asBytes(&self.type_pattern_hash));
            hasher.update(std.mem.asBytes(&self.implementation_count));
            return hasher.final();
        }

        pub fn eql(self: *const TableSignature, other: *const TableSignature) bool {
            return std.mem.eql(u8, self.signature_name, other.signature_name) and
                self.type_pattern_hash == other.type_pattern_hash and
                self.implementation_count == other.implementation_count;
        }
    };

    pub const SharedDispatchTable = struct {
        signature: TableSignature,
        compressed_entries: []CompressedEntry,
        reference_count: u32,
        memory_usage: usize,

        pub fn addReference(self: *SharedDispatchTable) void {
            self.reference_count += 1;
        }

        pub fn removeReference(self: *SharedDispatchTable, allocator: Allocator) bool {
            self.reference_count -= 1;
            if (self.reference_count == 0) {
                allocator.free(self.compressed_entries);
                return true; // Can be deallocated
            }
            return false;
        }
    };

    pub const CompressedEntry = struct {
        // Compressed type pattern using bit vectors
        type_pattern_bits: u64, // Up to 64 types can be encoded in bits
        type_pattern_overflow: ?[]const TypeId, // For patterns with >64 types

        // Implementation reference
        implementation_index: u16, // Index into shared implementation table

        // Frequency data for optimization
        call_frequency: u32,
        last_access_time: u64,

        pub fn getMemoryUsage(self: *const CompressedEntry) usize {
            var size = @sizeOf(CompressedEntry);
            if (self.type_pattern_overflow) |overflow| {
                size += overflow.len * @sizeOf(TypeId);
            }
            return size;
        }
    };

    pub const OptimizationPass = struct {
        name: []const u8,
        pass_function: *const fn (*DispatchTableCompression, *OptimizedDispatchTable) anyerror!OptimizationResult,
        enabled: bool,
        priority: u8, // Higher priority runs first

        pub const OptimizationResult = struct {
            entries_eliminated: u32,
            memory_saved: usize,
            performance_improvement_estimate: f64,
            applied: bool,
        };
    };

    pub fn init(allocator: Allocator, type_registry: *TypeRegistry) DispatchTableCompression {
        var compression = DispatchTableCompression{
            .allocator = allocator,
            .type_registry = type_registry,
            .compression_stats = CompressionStats{
                .original_size_bytes = 0,
                .compressed_size_bytes = 0,
                .tables_compressed = 0,
                .tables_shared = 0,
                .redundant_entries_eliminated = 0,
            },
            .shared_tables = AutoHashMap(TableSignature, *SharedDispatchTable).init(allocator),
            .optimization_passes = .empty,
        };

        // Register default optimization passes
        compression.registerDefaultOptimizationPasses() catch |err| {
            std.log.warn("Failed to register default optimization passes: {}", .{err});
        };

        return compression;
    }

    pub fn deinit(self: *DispatchTableCompression) void {
        // Clean up shared tables
        var iterator = self.shared_tables.iterator();
        while (iterator.next()) |entry| {
            const shared_table = entry.value_ptr.*;
            self.allocator.free(shared_table.compressed_entries);
            self.allocator.destroy(shared_table);
        }
        self.shared_tables.deinit();

        self.optimization_passes.deinit();
    }

    /// Compress a dispatch table using various optimization techniques
    pub fn compressTable(self: *DispatchTableCompression, table: *OptimizedDispatchTable) !CompressionResult {
        const original_size = table.getMemoryStats().total_bytes;
        self.compression_stats.original_size_bytes += original_size;

        var result = CompressionResult{
            .original_size = original_size,
            .compressed_size = original_size,
            .compression_ratio = 1.0,
            .techniques_applied = .empty,
            .shared_table = null,
        };

        // Try to find existing shared table
        const signature = try self.calculateTableSignature(table);
        if (self.shared_tables.get(signature)) |shared_table| {
            shared_table.addReference();
            result.shared_table = shared_table;
            result.compressed_size = 0; // No additional memory needed
            result.compression_ratio = 0.0;

            try result.techniques_applied.append(.table_sharing);
            self.compression_stats.tables_shared += 1;

            return result;
        }

        // Apply optimization passes
        var optimized_table = try table.clone(self.allocator);
        defer optimized_table.deinit();

        for (self.optimization_passes.items) |pass| {
            if (!pass.enabled) continue;

            const pass_result = try pass.pass_function(self, optimized_table);
            if (pass_result.applied) {
                result.compressed_size -= pass_result.memory_saved;
                self.compression_stats.redundant_entries_eliminated += pass_result.entries_eliminated;

                // Record which technique was applied
                const technique = self.passNameToTechnique(pass.name);
                try result.techniques_applied.append(technique);
            }
        }

        // Create compressed entries
        const compressed_entries = try self.createCompressedEntries(optimized_table);

        // Create shared table if beneficial
        if (result.compressed_size < original_size * 0.8) { // 20% savings threshold
            const shared_table = try self.allocator.create(SharedDispatchTable);
            shared_table.* = SharedDispatchTable{
                .signature = signature,
                .compressed_entries = compressed_entries,
                .reference_count = 1,
                .memory_usage = result.compressed_size,
            };

            try self.shared_tables.put(signature, shared_table);
            result.shared_table = shared_table;

            try result.techniques_applied.append(.entry_compression);
        } else {
            // Not worth compressing, clean up
            self.allocator.free(compressed_entries);
            result.compressed_size = original_size;
            result.compression_ratio = 1.0;
        }

        result.compression_ratio = @as(f64, @floatFromInt(result.compressed_size)) / @as(f64, @floatFromInt(original_size));
        self.compression_stats.compressed_size_bytes += result.compressed_size;
        self.compression_stats.tables_compressed += 1;

        return result;
    }

    /// Apply optimization passes to eliminate redundant entries
    pub fn optimizeTable(self: *DispatchTableCompression, table: *OptimizedDispatchTable) !OptimizationSummary {
        var summary = OptimizationSummary{
            .passes_applied = .empty,
            .total_entries_eliminated = 0,
            .total_memory_saved = 0,
            .total_performance_improvement = 0.0,
        };

        // Sort passes by priority
        std.sort.sort(OptimizationPass, self.optimization_passes.items, {}, comparePassPriority);

        for (self.optimization_passes.items) |pass| {
            if (!pass.enabled) continue;

            const pass_result = try pass.pass_function(self, table);

            try summary.passes_applied.append(PassResult{
                .pass_name = pass.name,
                .result = pass_result,
            });

            if (pass_result.applied) {
                summary.total_entries_eliminated += pass_result.entries_eliminated;
                summary.total_memory_saved += pass_result.memory_saved;
                summary.total_performance_improvement += pass_result.performance_improvement_estimate;
            }
        }

        return summary;
    }

    /// Register default optimization passes
    fn registerDefaultOptimizationPasses(self: *DispatchTableCompression) !void {
        // Dead entry elimination
        try self.optimization_passes.append(OptimizationPass{
            .name = "dead_entry_elimination",
            .pass_function = deadEntryEliminationPass,
            .enabled = true,
            .priority = 100,
        });

        // Redundant entry merging
        try self.optimization_passes.append(OptimizationPass{
            .name = "redundant_entry_merging",
            .pass_function = redundantEntryMergingPass,
            .enabled = true,
            .priority = 90,
        });

        // Frequency-based reordering
        try self.optimization_passes.append(OptimizationPass{
            .name = "frequency_reordering",
            .pass_function = frequencyReorderingPass,
            .enabled = true,
            .priority = 80,
        });

        // Type pattern compression
        try self.optimization_passes.append(OptimizationPass{
            .name = "type_pattern_compression",
            .pass_function = typePatternCompressionPass,
            .enabled = true,
            .priority = 70,
        });

        // Cache line alignment
        try self.optimization_passes.append(OptimizationPass{
            .name = "cache_line_alignment",
            .pass_function = cacheLineAlignmentPass,
            .enabled = true,
            .priority = 60,
        });
    }

    /// Calculate signature for table sharing
    fn calculateTableSignature(self: *DispatchTableCompression, table: *OptimizedDispatchTable) !TableSignature {
        _ = self;

        var hasher = std.hash.Wyhash.init(0);

        // Hash the type patterns
        const entries = table.getEntries();
        for (entries) |entry| {
            hasher.update(std.mem.sliceAsBytes(entry.type_pattern));
        }

        return TableSignature{
            .signature_name = table.getSignatureName(),
            .type_pattern_hash = hasher.final(),
            .implementation_count = @intCast(entries.len),
        };
    }

    /// Create compressed entries from optimized table
    fn createCompressedEntries(self: *DispatchTableCompression, table: *OptimizedDispatchTable) ![]CompressedEntry {
        const entries = table.getEntries();
        var compressed_entries = try self.allocator.alloc(CompressedEntry, entries.len);

        for (entries, 0..) |entry, i| {
            compressed_entries[i] = try self.compressEntry(entry);
        }

        return compressed_entries;
    }

    /// Compress a single dispatch entry
    fn compressEntry(self: *DispatchTableCompression, entry: OptimizedDispatchTable.DispatchEntry) !CompressedEntry {
        var compressed = CompressedEntry{
            .type_pattern_bits = 0,
            .type_pattern_overflow = null,
            .implementation_index = 0, // TODO: Map to shared implementation table
            .call_frequency = entry.call_count,
            .last_access_time = compat_time.nanoTimestamp(),
        };

        // Compress type pattern into bit vector if possible
        if (entry.type_pattern.len <= 64) {
            for (entry.type_pattern, 0..) |type_id, bit_index| {
                if (type_id != 0) { // Assuming 0 is invalid type
                    compressed.type_pattern_bits |= (@as(u64, 1) << @intCast(bit_index));
                }
            }
        } else {
            // Use overflow array for large patterns
            compressed.type_pattern_overflow = try self.allocator.dupe(TypeId, entry.type_pattern);
        }

        return compressed;
    }

    /// Convert pass name to compression technique enum
    fn passNameToTechnique(self: *DispatchTableCompression, pass_name: []const u8) CompressionTechnique {
        _ = self;

        if (std.mem.eql(u8, pass_name, "dead_entry_elimination")) return .dead_entry_elimination;
        if (std.mem.eql(u8, pass_name, "redundant_entry_merging")) return .redundant_merging;
        if (std.mem.eql(u8, pass_name, "frequency_reordering")) return .frequency_reordering;
        if (std.mem.eql(u8, pass_name, "type_pattern_compression")) return .pattern_compression;
        if (std.mem.eql(u8, pass_name, "cache_line_alignment")) return .cache_alignment;

        return .other;
    }

    /// Compare optimization passes by priority
    fn comparePassPriority(context: void, a: OptimizationPass, b: OptimizationPass) bool {
        _ = context;
        return a.priority > b.priority; // Higher priority first
    }

    pub const CompressionResult = struct {
        original_size: usize,
        compressed_size: usize,
        compression_ratio: f64,
        techniques_applied: ArrayList(CompressionTechnique),
        shared_table: ?*SharedDispatchTable,

        pub fn deinit(self: *CompressionResult) void {
            self.techniques_applied.deinit();
        }
    };

    pub const CompressionTechnique = enum {
        dead_entry_elimination,
        redundant_merging,
        frequency_reordering,
        pattern_compression,
        cache_alignment,
        table_sharing,
        entry_compression,
        zstd_compression,
        lz4_compression,
        custom_compression,
        other,
    };

    pub const CompressionBackend = enum {
        none, // No general-purpose compression
        zstd, // Zstandard - best compression ratio
        lz4, // LZ4 - fastest compression/decompression
        custom, // Custom algorithm optimized for dispatch tables

        pub fn getCompressionLevel(self: CompressionBackend) i32 {
            return switch (self) {
                .none => 0,
                .zstd => 3, // Balanced compression level for zstd
                .lz4 => 1, // LZ4 has limited levels
                .custom => 5, // Custom algorithm level
            };
        }

        pub fn isAvailable(self: CompressionBackend) bool {
            return switch (self) {
                .none, .custom => true,
                .zstd => @hasDecl(@This(), "zstd"),
                .lz4 => @hasDecl(@This(), "lz4"),
            };
        }
    };

    pub const CompressionConfig = struct {
        // Semantic compression settings
        enable_dead_entry_elimination: bool = true,
        enable_redundant_merging: bool = true,
        enable_frequency_reordering: bool = true,
        enable_pattern_compression: bool = true,
        enable_cache_alignment: bool = true,
        enable_table_sharing: bool = true,

        // General-purpose compression settings
        backend: CompressionBackend = .none,
        compression_level: ?i32 = null, // null = use backend default
        min_size_for_compression: usize = 1024, // Don't compress small tables

        // Hybrid compression settings
        semantic_first: bool = true, // Apply semantic compression before general compression
        compression_threshold: f64 = 0.1, // Minimum 10% savings to apply compression

        pub fn getEffectiveCompressionLevel(self: *const CompressionConfig) i32 {
            return self.compression_level orelse self.backend.getCompressionLevel();
        }
    };

    pub const OptimizationSummary = struct {
        passes_applied: ArrayList(PassResult),
        total_entries_eliminated: u32,
        total_memory_saved: usize,
        total_performance_improvement: f64,

        pub fn deinit(self: *OptimizationSummary) void {
            self.passes_applied.deinit();
        }
    };

    pub const PassResult = struct {
        pass_name: []const u8,
        result: OptimizationPass.OptimizationResult,
    };

    /// Generate compression report
    pub fn generateCompressionReport(self: *const DispatchTableCompression, writer: anytype) !void {
        try writer.print("=== Dispatch Table Compression Report ===\n");
        try writer.print("Tables processed: {}\n", .{self.compression_stats.tables_compressed});
        try writer.print("Tables shared: {}\n", .{self.compression_stats.tables_shared});
        try writer.print("Redundant entries eliminated: {}\n", .{self.compression_stats.redundant_entries_eliminated});
        try writer.print("Original size: {} bytes\n", .{self.compression_stats.original_size_bytes});
        try writer.print("Compressed size: {} bytes\n", .{self.compression_stats.compressed_size_bytes});
        try writer.print("Space saved: {} bytes\n", .{self.compression_stats.getSpaceSaved()});
        try writer.print("Compression ratio: {d:.2}%\n", .{self.compression_stats.getCompressionRatio() * 100});

        try writer.print("\nShared Tables:\n");
        var iterator = self.shared_tables.iterator();
        while (iterator.next()) |entry| {
            const signature = entry.key_ptr.*;
            const shared_table = entry.value_ptr.*;
            try writer.print("  {s}: {} references, {} bytes\n", .{
                signature.signature_name,
                shared_table.reference_count,
                shared_table.memory_usage,
            });
        }

        try writer.print("\nOptimization Passes:\n");
        for (self.optimization_passes.items) |pass| {
            const status = if (pass.enabled) "enabled" else "disabled";
            try writer.print("  {s}: {} (priority: {})\n", .{ pass.name, status, pass.priority });
        }
    }
};

// Type alias for convenience
const TypeId = TypeRegistry.TypeId;

/// Dead entry elimination pass - removes entries that are never called
fn deadEntryEliminationPass(compression: *DispatchTableCompression, table: *OptimizedDispatchTable) !DispatchTableCompression.OptimizationPass.OptimizationResult {
    _ = compression;

    const entries = table.getEntries();
    var eliminated_count: u32 = 0;
    var memory_saved: usize = 0;

    // Identify dead entries (never called)
    var dead_indices: ArrayList(usize) = .empty;
    defer dead_indices.deinit();

    for (entries, 0..) |entry, i| {
        if (entry.call_count == 0) {
            try dead_indices.append(i);
            eliminated_count += 1;
            memory_saved += @sizeOf(OptimizedDispatchTable.DispatchEntry);
        }
    }

    // Remove dead entries if any found
    if (dead_indices.items.len > 0) {
        try table.removeEntries(dead_indices.items);

        return DispatchTableCompression.OptimizationPass.OptimizationResult{
            .entries_eliminated = eliminated_count,
            .memory_saved = memory_saved,
            .performance_improvement_estimate = @as(f64, @floatFromInt(eliminated_count)) * 0.1, // Estimate 10% improvement per eliminated entry
            .applied = true,
        };
    }

    return DispatchTableCompression.OptimizationPass.OptimizationResult{
        .entries_eliminated = 0,
        .memory_saved = 0,
        .performance_improvement_estimate = 0.0,
        .applied = false,
    };
}

/// Redundant entry merging pass - merges entries with identical type patterns
fn redundantEntryMergingPass(compression: *DispatchTableCompression, table: *OptimizedDispatchTable) !DispatchTableCompression.OptimizationPass.OptimizationResult {
    _ = compression;

    const entries = table.getEntries();
    var eliminated_count: u32 = 0;
    var memory_saved: usize = 0;

    // Group entries by type pattern
    var pattern_groups = AutoHashMap(u64, ArrayList(usize)).init(table.allocator);
    defer {
        var iterator = pattern_groups.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        pattern_groups.deinit();
    }

    for (entries, 0..) |entry, i| {
        const pattern_hash = hashTypePattern(entry.type_pattern);

        var group = pattern_groups.get(pattern_hash) orelse ArrayList(usize).empty;
        try group.append(i);
        try pattern_groups.put(pattern_hash, group);
    }

    // Merge redundant entries
    var entries_to_remove: ArrayList(usize) = .empty;
    defer entries_to_remove.deinit();

    var iterator = pattern_groups.iterator();
    while (iterator.next()) |entry| {
        const group = entry.value_ptr.*;
        if (group.items.len > 1) {
            // Keep the first entry, merge others into it
            const keep_index = group.items[0];
            var total_calls: u64 = 0;

            for (group.items) |index| {
                total_calls += entries[index].call_count;
                if (index != keep_index) {
                    try entries_to_remove.append(index);
                    eliminated_count += 1;
                    memory_saved += @sizeOf(OptimizedDispatchTable.DispatchEntry);
                }
            }

            // Update the kept entry with merged call count
            try table.updateEntryCallCount(keep_index, total_calls);
        }
    }

    if (entries_to_remove.items.len > 0) {
        try table.removeEntries(entries_to_remove.items);

        return DispatchTableCompression.OptimizationPass.OptimizationResult{
            .entries_eliminated = eliminated_count,
            .memory_saved = memory_saved,
            .performance_improvement_estimate = @as(f64, @floatFromInt(eliminated_count)) * 0.05, // Estimate 5% improvement per merged entry
            .applied = true,
        };
    }

    return DispatchTableCompression.OptimizationPass.OptimizationResult{
        .entries_eliminated = 0,
        .memory_saved = 0,
        .performance_improvement_estimate = 0.0,
        .applied = false,
    };
}

/// Frequency-based reordering pass - reorders entries by call frequency
fn frequencyReorderingPass(compression: *DispatchTableCompression, table: *OptimizedDispatchTable) !DispatchTableCompression.OptimizationPass.OptimizationResult {
    _ = compression;

    const entries = table.getEntries();
    if (entries.len <= 1) {
        return DispatchTableCompression.OptimizationPass.OptimizationResult{
            .entries_eliminated = 0,
            .memory_saved = 0,
            .performance_improvement_estimate = 0.0,
            .applied = false,
        };
    }

    // Create indices sorted by call frequency (descending)
    var indices = try table.allocator.alloc(usize, entries.len);
    defer table.allocator.free(indices);

    for (indices, 0..) |*index, i| {
        index.* = i;
    }

    std.sort.sort(usize, indices, entries, compareByCallFrequency);

    // Check if reordering is beneficial
    var reordering_beneficial = false;
    for (indices, 0..) |index, i| {
        if (index != i) {
            reordering_beneficial = true;
            break;
        }
    }

    if (reordering_beneficial) {
        try table.reorderEntries(indices);

        // Estimate performance improvement based on frequency distribution
        var total_calls: u64 = 0;
        var weighted_position: f64 = 0.0;

        for (entries, 0..) |entry, i| {
            total_calls += entry.call_count;
            weighted_position += @as(f64, @floatFromInt(entry.call_count)) * @as(f64, @floatFromInt(i));
        }

        const avg_position = if (total_calls > 0) weighted_position / @as(f64, @floatFromInt(total_calls)) else 0.0;
        const improvement_estimate = (1.0 - avg_position / @as(f64, @floatFromInt(entries.len))) * 0.2; // Up to 20% improvement

        return DispatchTableCompression.OptimizationPass.OptimizationResult{
            .entries_eliminated = 0,
            .memory_saved = 0,
            .performance_improvement_estimate = improvement_estimate,
            .applied = true,
        };
    }

    return DispatchTableCompression.OptimizationPass.OptimizationResult{
        .entries_eliminated = 0,
        .memory_saved = 0,
        .performance_improvement_estimate = 0.0,
        .applied = false,
    };
}

/// Type pattern compression pass - compresses type patterns using bit vectors
fn typePatternCompressionPass(compression: *DispatchTableCompression, table: *OptimizedDispatchTable) !DispatchTableCompression.OptimizationPass.OptimizationResult {
    _ = compression;

    const entries = table.getEntries();
    var memory_saved: usize = 0;
    var patterns_compressed: u32 = 0;

    for (entries) |entry| {
        if (entry.type_pattern.len <= 64) {
            // Can compress to bit vector
            const original_size = entry.type_pattern.len * @sizeOf(TypeId);
            const compressed_size = @sizeOf(u64);

            if (compressed_size < original_size) {
                memory_saved += original_size - compressed_size;
                patterns_compressed += 1;
            }
        }
    }

    if (patterns_compressed > 0) {
        // Apply compression (this would modify the table structure)
        try table.enablePatternCompression();

        return DispatchTableCompression.OptimizationPass.OptimizationResult{
            .entries_eliminated = 0,
            .memory_saved = memory_saved,
            .performance_improvement_estimate = @as(f64, @floatFromInt(patterns_compressed)) * 0.02, // 2% improvement per compressed pattern
            .applied = true,
        };
    }

    return DispatchTableCompression.OptimizationPass.OptimizationResult{
        .entries_eliminated = 0,
        .memory_saved = 0,
        .performance_improvement_estimate = 0.0,
        .applied = false,
    };
}

/// Cache line alignment pass - aligns frequently accessed entries to cache boundaries
fn cacheLineAlignmentPass(compression: *DispatchTableCompression, table: *OptimizedDispatchTable) !DispatchTableCompression.OptimizationPass.OptimizationResult {
    _ = compression;

    const entries = table.getEntries();
    if (entries.len == 0) {
        return DispatchTableCompression.OptimizationPass.OptimizationResult{
            .entries_eliminated = 0,
            .memory_saved = 0,
            .performance_improvement_estimate = 0.0,
            .applied = false,
        };
    }

    // Calculate current cache efficiency
    const current_efficiency = table.getMemoryStats().cache_efficiency;

    // Apply cache line alignment
    try table.optimizeForCacheLocality();

    // Calculate new cache efficiency
    const new_efficiency = table.getMemoryStats().cache_efficiency;

    if (new_efficiency > current_efficiency) {
        const improvement = new_efficiency - current_efficiency;

        return DispatchTableCompression.OptimizationPass.OptimizationResult{
            .entries_eliminated = 0,
            .memory_saved = 0,
            .performance_improvement_estimate = improvement * 0.3, // Cache improvements can be significant
            .applied = true,
        };
    }

    return DispatchTableCompression.OptimizationPass.OptimizationResult{
        .entries_eliminated = 0,
        .memory_saved = 0,
        .performance_improvement_estimate = 0.0,
        .applied = false,
    };
}

/// Hash a type pattern for comparison
fn hashTypePattern(pattern: []const TypeId) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.sliceAsBytes(pattern));
    return hasher.final();
}

/// Compare entries by call frequency (descending order)
fn compareByCallFrequency(entries: []const OptimizedDispatchTable.DispatchEntry, a_index: usize, b_index: usize) bool {
    return entries[a_index].call_count > entries[b_index].call_count;
}

/// General-purpose compression backend implementations
pub const CompressionBackends = struct {

    /// Compress data using specified backend
    pub fn compress(allocator: Allocator, backend: DispatchTableCompression.CompressionBackend, data: []const u8, level: i32) ![]u8 {
        return switch (backend) {
            .none => try allocator.dupe(u8, data), // No compression
            .zstd => compressZstd(allocator, data, level),
            .lz4 => compressLz4(allocator, data, level),
            .custom => compressCustom(allocator, data, level),
        };
    }

    /// Decompress data using the specified backend
    pub fn decompress(allocator: Allocator, backend: DispatchTableCompression.CompressionBackend, compressed_data: []const u8, original_size: usize) ![]u8 {
        return switch (backend) {
            .none => try allocator.dupe(u8, compressed_data), // No decompression
            .zstd => decompressZstd(allocator, compressed_data, original_size),
            .lz4 => decompressLz4(allocator, compressed_data, original_size),
            .custom => decompressCustom(allocator, compressed_data, original_size),
        };
    }

    /// Zstandard compression (if available)
    fn compressZstd(allocator: Allocator, data: []const u8, level: i32) ![]u8 {
        if (!@hasDecl(@This(), "zstd")) {
            return error.ZstdNotAvailable;
        }

        // This would use the actual zstd library
        // For now, we'll simulate compression with a simple algorithm
        _ = level;
        return simulateCompression(allocator, data, 0.6); // Simulate 60% compression ratio
    }

    /// Zstandard decompression (if available)
    fn decompressZstd(allocator: Allocator, compressed_data: []const u8, original_size: usize) ![]u8 {
        if (!@hasDecl(@This(), "zstd")) {
            return error.ZstdNotAvailable;
        }

        // This would use the actual zstd library
        return simulateDecompression(allocator, compressed_data, original_size);
    }

    /// LZ4 compression (if available)
    fn compressLz4(allocator: Allocator, data: []const u8, level: i32) ![]u8 {
        if (!@hasDecl(@This(), "lz4")) {
            return error.Lz4NotAvailable;
        }

        // This would use the actual LZ4 library
        _ = level;
        return simulateCompression(allocator, data, 0.75); // Simulate 75% compression ratio (faster but less compression)
    }

    /// LZ4 decompression (if available)
    fn decompressLz4(allocator: Allocator, compressed_data: []const u8, original_size: usize) ![]u8 {
        if (!@hasDecl(@This(), "lz4")) {
            return error.Lz4NotAvailable;
        }

        // This would use the actual LZ4 library
        return simulateDecompression(allocator, compressed_data, original_size);
    }

    /// Custom compression algorithm optimized for dispatch table data
    fn compressCustom(allocator: Allocator, data: []const u8, level: i32) ![]u8 {
        // Custom algorithm that understands dispatch table structure
        var compressed: ArrayList(u8) = .empty;
        defer compressed.deinit();

        // Header: compression method and original size
        try compressed.append(0xDT); // Dispatch Table magic
        try compressed.append(@intCast(level));
        try compressed.appendSlice(std.mem.asBytes(&data.len));

        // Simple run-length encoding for repeated patterns
        v = 0;
        while (i < data.len) {
            const byte = data[i];
            var count: u8 = 1;

            // Count consecutive identical bytes
            while (i + count < data.len and data[i + count] == byte and count < 255) {
                count += 1;
            }

            if (count > 3) {
                // Use RLE for runs of 4 or more
                try compressed.append(0xFF); // RLE marker
                try compressed.append(count);
                try compressed.append(byte);
            } else {
                // Store bytes directly
                for (0..count) |_| {
                    try compressed.append(byte);
                }
            }

            i += count;
        }

        return try compressed.toOwnedSlice(alloc);
    }

    /// Custom decompression algorithm
    fn decompressCustom(allocator: Allocator, compressed_data: []const u8, original_size: usize) ![]u8 {
        if (compressed_data.len < 6) return error.InvalidCompressedData;

        // Verify header
        if (compressed_data[0] != 0xDT) return error.InvalidMagic;

        const level = compressed_data[1];
        _ = level; // Not used in decompression

        const stored_size = std.mem.bytesToValue(usize, compressed_data[2..6]);
        if (stored_size != original_size) return error.SizeMismatch;

        var decompressed = try allocator.alloc(u8, original_size);
        var src_pos: usize = 6;
        var dst_pos: usize = 0;

        while (src_pos < compressed_data.len and dst_pos < original_size) {
            if (compressed_data[src_pos] == 0xFF and src_pos + 2 < compressed_data.len) {
                // RLE sequence
                const count = compressed_data[src_pos + 1];
                const byte = compressed_data[src_pos + 2];

                for (0..count) |_| {
                    if (dst_pos >= original_size) break;
                    decompressed[dst_pos] = byte;
                    dst_pos += 1;
                }

                src_pos += 3;
            } else {
                // Direct byte
                decompressed[dst_pos] = compressed_data[src_pos];
                dst_pos += 1;
                src_pos += 1;
            }
        }

        return decompressed;
    }

    /// Simulate compression for testing (when real libraries aren't available)
    fn simulateCompression(allocator: Allocator, data: []const u8, ratio: f64) ![]u8 {
        const compressed_size = @max(1, @as(usize, @intFromFloat(@as(f64, @floatFromInt(data.len)) * ratio)));
        var compressed = try allocator.alloc(u8, compressed_size + 8); // +8 for header

        // Simple header with original size
        std.mem.writeIntLittle(u64, compressed[0..8], data.len);

        // Fill with pseudo-compressed data (for testing)
        for (compressed[8..], 0..) |*byte, i| {
            byte.* = @intCast((data[i % data.len] ^ @as(u8, @intCast(i))) & 0xFF);
        }

        return compressed;
    }

    /// Simulate decompression for testing
    fn simulateDecompression(allocator: Allocator, compressed_data: []const u8, original_size: usize) ![]u8 {
        if (compressed_data.len < 8) return error.InvalidData;

        const stored_size = std.mem.readIntLittle(u64, compressed_data[0..8]);
        if (stored_size != original_size) return error.SizeMismatch;

        var decompressed = try allocator.alloc(u8, original_size);

        // Reverse the pseudo-compression
        for (decompressed, 0..) |*byte, i| {
            const compressed_byte = compressed_data[8 + (i % (compressed_data.len - 8))];
            byte.* = compressed_byte ^ @as(u8, @intCast(i));
        }

        return decompressed;
    }
};

/// Hybrid compression that combines semantic and general-purpose compression
pub const HybridCompression = struct {

    /// Apply hybrid compression to dispatch table
    pub fn compressTable(
        allocator: Allocator,
        table_data: []const u8,
        config: DispatchTableCompression.CompressionConfig
    ) !HybridCompressionResult {
        var result = HybridCompressionResult{
            .original_size = table_data.len,
            .semantic_compressed_size = table_data.len,
            .final_compressed_size = table_data.len,
            .semantic_data = null,
            .compressed_data = null,
            .backend_used = config.backend,
            .compression_ratio = 1.0,
        };

        var current_data = table_data;

        // Step 1: Apply semantic compression if enabled
        if (config.semantic_first) {
            const semantic_result = try applySemanticCompression(allocator, current_data);
            if (semantic_result.compressed_size < current_data.len) {
                result.semantic_data = semantic_result.data;
                result.semantic_compressed_size = semantic_result.compressed_size;
                current_data = semantic_result.data;
            }
        }

        // Step 2: Apply general-purpose compression if beneficial
        if (config.backend != .none and
            current_data.len >= config.min_size_for_compression and
            config.backend.isAvailable()) {

            const level = config.getEffectiveCompressionLevel();
            const compressed = CompressionBackends.compress(allocator, config.backend, current_data, level) catch |err| {
                std.log.warn("General compression failed: {}, falling back to semantic only", .{err});
                result.compressed_data = if (result.semantic_data) |data| try allocator.dupe(u8, data) else try allocator.dupe(u8, table_data);
                result.final_compressed_size = current_data.len;
                return result;
            };

            // Check if compression is beneficial
            const compression_savings = @as(f64, @floatFromInt(current_data.len - compressed.len)) / @as(f64, @floatFromInt(current_data.len));
            if (compression_savings >= config.compression_threshold) {
                result.compressed_data = compressed;
                result.final_compressed_size = compressed.len;
            } else {
                // Compression not beneficial, use uncompressed data
                allocator.free(compressed);
                result.compressed_data = try allocator.dupe(u8, current_data);
                result.final_compressed_size = current_data.len;
                result.backend_used = .none;
            }
        } else {
            // No general compression, use current data
            result.compressed_data = try allocator.dupe(u8, current_data);
            result.final_compressed_size = current_data.len;
        }

        result.compression_ratio = @as(f64, @floatFromInt(result.final_compressed_size)) / @as(f64, @floatFromInt(result.original_size));

        return result;
    }

    /// Decompress hybrid-compressed data
    pub fn decable(
        allocator: Allocator,
        compressed_result: *const HybridCompressionResult
    ) ![]u8 {
        var current_data = compressed_result.compressed_data orelse return error.NoCompressedData;

        // Step 1: Decompress general-purpose compression if used
        var decompressed_data: []u8 = undefined;
        if (compressed_result.backend_used != .none) {
            decompressed_data = try CompressionBackends.decompress(
                allocator,
                compressed_result.backend_used,
                current_data,
                compressed_result.semantic_compressed_size
            );
        } else {
            decompressed_data = try allocator.dupe(u8, current_data);
        }
        defer if (compressed_result.backend_used != .none) allocator.free(decompressed_data);

        // Step 2: Decompress semantic compression if used
        if (compressed_result.semantic_data != null) {
            return applySemanticDecompression(allocator, decompressed_data, compressed_result.original_size);
        } else {
            return try allocator.dupe(u8, decompressed_data);
        }
    }

    /// Apply semantic compression specific to dispatch table structure
    fn applySemanticCompression(allocator: Allocator, data: []const u8) !SemanticCompressionResult {
        // This would implement dispatch-table-specific compression
        // For now, simulate with simple duplicate removal

        var compressed: ArrayList(u8) = .empty;
        defer compressed.deinit();

        // Simple duplicate pattern removal
        var i: usize = 0;
        while (i < data.len) {
            const byte = data[i];

            // Look for patterns of repeated 4-byte sequences (simulating TypeId patterns)
            if (i + 8 <= data.len) {
                const pattern = data[i..i+4];
                const next_pattern = data[i+4..i+8];

                if (std.mem.eql(u8, pattern, next_pattern)) {
                    // Found repeated pattern, encode it
                    try compressed.append(0xFE); // Pattern marker
                    try compressed.appendSlice(pattern);

                    // Count how many times it repeats
                    var count: u8 = 2;
                    var pos = i + 8;
                    while (pos + 4 <= data.len and std.mem.eql(u8, data[pos..pos+4], pattern) and count < 255) {
                        count += 1;
                        pos += 4;
                    }

                    try compressed.append(count);
                    i = pos;
                } else {
                    try compressed.append(byte);
                    i += 1;
                }
            } else {
                try compressed.append(byte);
                i += 1;
            }
        }

        return SemanticCompressionResult{
            .data = try compressed.toOwnedSlice(),
            .compressed_size = compressed.items.len,
        };
    }

    /// Apply semantic decompression
    fn applySemanticDecompression(allocator: Allocator, compressed_data: []const u8, original_size: usize) ![]u8 {
        var decompressed: ArrayList(u8) = .empty;
        defer decompressed.deinit();

        var i: usize = 0;
        while (i < compressed_data.len) {
            if (compressed_data[i] == 0xFE and i + 6 < compressed_data.len) {
                // Pattern marker found
                const pattern = compressed_data[i+1..i+5];
                const count = compressed_data[i+5];

                // Repeat the pattern          for (0..count) |_| {
                    try decompressed.appendSlice(pattern);
                }

                i += 6;
            } else {
                try decompressed.append(compressed_data[i]);
                i += 1;
            }
        }

        // Verify size
        if (decompressed.items.len != original_size) {
            return error.DecompressionSizeMismatch;
        }

        return try decompressed.toOwnedSlice(alloc);
    }

    const SemanticCompressionResult = struct {
        data: []u8,
        compressed_size: usize,
    };

    pub const HybridCompressionResult = struct {
        original_size: usize,
        semantic_compressed_size: usize,
        final_compressed_size: usize,
        semantic_data: ?[]u8,
        compressed_data: ?[]u8,
        backend_used: DispatchTableCompression.CompressionBackend,
        compression_ratio: f64,

        pub fn deinit(self: *HybridCompressionResult, allocator: Allocator) void {
            if (self.semantic_data) |data| {
                allocator.free(data);
            }
            if (self.compressed_data) |data| {
                allocator.free(data);
            }
        }

        pub fn getCompressionSavings(self: *const HybridCompressionResult) usize {
            return self.original_size - self.final_compressed_size;
        }

        pub fn getCompressionRatio(self: *const HybridCompressionResult) f64 {
            return self.compression_ratio;
        }
    };
};

/// Compression benchmark and selection system
pub const CompressionBenchmark = struct {

    /// Benchmark different compression backends and select the best one
    pub fn selectOptimalBackend(
        allocator: Allocator,
        sample_data: []const u8,
        performance_weight: f64, // 0.0 = prioritize compression ratio, 1.0 = prioritize speed
    ) !BenchmarkResult {
        const backends = [_]DispatchTableCompression.CompressionBackend{ .none, .lz4, .zstd, .custom };
        var results: ArrayList(BackendResult) = .empty;
        defer results.deinit();

        for (backends) |backend| {
            if (!backend.isAvailable()) continue;

            const result = try benchmarkBackend(allocator, backend, sample_data);
            try results.append(result);
        }

        // Select best backend based on weighted score
        var best_backend = DispatchTableCompression.CompressionBackend.none;
        var best_score: f64 = 0.0;

        for (results.items) |result| {
            // Score = (1 - compression_ratio) * (performance_weight) + speed_score * performance_weight
            const compression_score = 1.0 - result.compression_ratio;
            const speed_score = 1.0 / (1.0 + result.compression_time_ms / 1000.0); // Normalize speed
            const total_score = compression_score * (1.0 - performance_weight) + speed_score * performance_weight;

            if (total_score > best_score) {
                best_score = total_score;
                best_backend = result.backend;
            }
        }

        return BenchmarkResult{
            .recommended_backend = best_backend,
            .backend_results = try results.toOwnedSlice(),
            .performance_weight = performance_weight,
            .best_score = best_score,
        };
    }

    /// Benchmark a specific compression backend
    fn benchmarkBackend(
        allocator: Allocator,
        backend: DispatchTableCompression.CompressionBackend,
        data: []const u8
    ) !BackendResult {
        const level = backend.getCompressionLevel();

        // Measure compression time
        const compress_start = compat_time.nanoTimestamp();
        const compressed = try CompressionBackends.compress(allocator, backend, data, level);
        const compress_end = compat_time.nanoTimestamp();
        defer allocator.free(compressed);

        // Measure decompression time
        const decompress_start = compat_time.nanoTimestamp();
        const decompressed = try CompressionBackends.decompress(allocator, backend, compressed, data.len);
        const decompress_end = compat_time.nanoTimestamp();
        defer allocator.free(decompressed);

        // Verify correctness
        if (!std.mem.eql(u8, data, decompressed)) {
            return error.CompressionCorruption;
        }

        const compression_time = @as(f64, @floatFromInt(compress_end - compress_start)) / 1_000_000.0; // Convert to ms
        const decompression_time = @as(f64, @floatFromInt(decompress_end - decompress_start)) / 1_000_000.0;

        return BackendResult{
            .backend = backend,
            .original_size = data.len,
            .compressed_size = compressed.len,
            .compression_ratio = @as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(data.len)),
            .compression_time_ms = compression_time,
            .decompression_time_ms = decompression_time,
        };
    }

    pub const BenchmarkResult = struct {
        recommended_backend: DispatchTableCompression.CompressionBackend,
        backend_results: []BackendResult,
        performance_weight: f64,
        best_score: f64,

        pub fn deinit(self: *BenchmarkResult, allocator: Allocator) void {
            allocator.free(self.backend_results);
        }

        pub fn printReport(self: *const BenchmarkResult, writer: anytype) !void {
            try writer.print("=== Compression Backend Benchmark ===\n");
            try writer.print("Performance weight: {d:.2} (0.0=compression, 1.0=speed)\n", .{self.performance_weight});
            try writer.printended backend: {s}\n", .{@tagName(self.recommended_backend)});
            try writer.print("Best score: {d:.3}\n\n", .{self.best_score});

            try writer.print("Backend Results:\n");
            for (self.backend_results) |result| {
                try writer.print("  {s}:\n", .{@tagName(result.backend)});
                try writer.print("    Compression ratio: {d:.3}\n", .{result.compression_ratio});
                try writer.print("    Compression time: {d:.2} ms\n", .{result.compression_time_ms});
                try writer.print("    Decompression time: {d:.2} ms\n", .{result.decompression_time_ms});
                try writer.print("    Space saved: {} bytes\n", .{result.original_size - result.compressed_size});
            }
        }
    };

    pub const BackendResult = struct {
        backend: DispatchTableCompression.CompressionBackend,
        original_size: usize,
        compressed_size: usize,
        compression_ratio: f64,
        compression_time_ms: f64,
        decompression_time_ms: f64,
    };
};
