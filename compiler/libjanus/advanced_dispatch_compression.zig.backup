// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;

/// Advanced compression techniques specifically designed for dispatch tables
/// Implements domain-specific optimizations that understand the structure and semantics
/// of multiple dispatch systems
pub const AdvancedDispatchCompression = struct {
    allocator: Allocator,

    // Compression dictionaries
    type_dictionary: TypeDictionary,
    pattern_dictionary: PatternDictionary,
    implementation_pool: ImplementationPool,

    // Statistics
    compression_stats: CompressionStats,

    pub const CompressionStats = struct {
        original_bytes: usize,
        compressed_bytes: usize,
        dictionary_bytes: usize,

        delta_compression_savings: usize,
        pattern_compression_savings: usize,
        dictionary_compression_savings: usize,

        pub fn getTotalCompressionRatio(self: *const CompressionStats) f64 {
            if (self.original_bytes == 0) return 1.0;
            const total_compressed = self.compressed_bytes + self.dictionary_bytes;
            return @as(f64, @floatFromInt(total_compressed)) / @as(f64, @floatFromInt(self.original_bytes));
        }

        pub fn getEffectiveCompressionRatio(self: *const CompressionStats) f64 {
            if (self.original_bytes == 0) return 1.0;
            return @as(f64, @floatFromInt(self.compressed_bytes)) / @as(f64, @floatFromInt(self.original_bytes));
        }
    };

    /// Type dictionary for compressing TypeId sequences
    pub const TypeDictionary = struct {
        type_to_index: AutoHashMap(TypeId, u16),
        index_to_type: ArrayList(TypeId),
        frequency_map: AutoHashMap(TypeId, u32),

        pub fn init(allocator: Allocator) TypeDictionary {
            return TypeDictionary{
                .type_to_index = AutoHashMap(TypeId, u16).init(allocator),
                .index_to_type = ArrayList(TypeId).init(allocator),
                .frequency_map = AutoHashMap(TypeId, u32).init(allocator),
            };
        }

        pub fn deinit(self: *TypeDictionary) void {
            self.type_to_index.deinit();
            self.index_to_type.deinit();
            self.frequency_map.deinit();
        }

        /// Add a type to the dictionary, returns its compressed index
        pub fn addType(self: *TypeDictionary, type_id: TypeId) !u16 {
            if (self.type_to_index.get(type_id)) |index| {
                // Update frequency
                const current_freq = self.frequency_map.get(type_id) orelse 0;
                try self.frequency_map.put(type_id, current_freq + 1);
                return index;
            }

            const index = @as(u16, @intCast(self.index_to_type.items.len));
            try self.type_to_index.put(type_id, index);
            try self.index_to_type.append(type_id);
            try self.frequency_map.put(type_id, 1);

            return index;
        }

        /// Get compressed index for a type
        pub fn getIndex(self: *const TypeDictionary, type_id: TypeId) ?u16 {
            return self.type_to_index.get(type_id);
        }

        /// Get type from compressed index
        pub fn getType(self: *const TypeDictionary, index: u16) ?TypeId {
            if (index >= self.index_to_type.items.len) return null;
            return self.index_to_type.items[index];
        }

        /// Optimize dictionary by frequency (Huffman-like encoding)
        pub fn optimizeByFrequency(self: *TypeDictionary) !void {
            // Create frequency-sorted list
            var freq_pairs = ArrayList(FrequencyPair).init(self.index_to_type.allocator);
            defer freq_pairs.deinit();

            for (self.index_to_type.items, 0..) |type_id, i| {
                const frequency = self.frequency_map.get(type_id) orelse 0;
                try freq_pairs.append(FrequencyPair{
                    .type_id = type_id,
                    .frequency = frequency,
                    .old_index = @intCast(i),
                });
            }

            // Sort by frequency (descending)
            std.sort.sort(FrequencyPair, freq_pairs.items, {}, FrequencyPair.compareByFrequency);

            // Rebuild mappings with frequency-optimized indices
            self.type_to_index.clearRetainingCapacity();
            self.index_to_type.clearRetainingCapacity();

            for (freq_pairs.items, 0..) |pair, new_index| {
                try self.type_to_index.put(pair.type_id, @intCast(new_index));
                try self.index_to_type.append(pair.type_id);
            }
        }

        const FrequencyPair = struct {
            type_id: TypeId,
            frequency: u32,
            old_index: u16,

            fn compareByFrequency(context: void, a: FrequencyPair, b: FrequencyPair) bool {
                _ = context;
                return a.frequency > b.frequency;
            }
        };
    };

    /// Pattern dictionary for compressing common type patterns
    pub const PatternDictionary = struct {
        patterns: ArrayList(TypePattern),
        pattern_to_index: AutoHashMap(u64, u16), // Hash -> index
        frequency_map: AutoHashMap(u16, u32),

        pub const TypePattern = struct {
            types: []TypeId,
            hash: u64,
            frequency: u32,

            pub fn calculateHash(types: []const TypeId) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hasher.update(std.mem.sliceAsBytes(types));
                return hasher.final();
            }
        };

        pub fn init(allocator: Allocator) PatternDictionary {
            return PatternDictionary{
                .patterns = ArrayList(TypePattern).init(allocator),
                .pattern_to_index = AutoHashMap(u64, u16).init(allocator),
                .frequency_map = AutoHashMap(u16, u32).init(allocator),
            };
        }

        pub fn deinit(self: *PatternDictionary) void {
            for (self.patterns.items) |pattern| {
                self.patterns.allocator.free(pattern.types);
            }
            self.patterns.deinit();
            self.pattern_to_index.deinit();
            self.frequency_map.deinit();
        }

        /// Add a pattern to the dictionary
        pub fn addPattern(self: *PatternDictionary, types: []const TypeId) !u16 {
            const hash = TypePattern.calculateHash(types);

            if (self.pattern_to_index.get(hash)) |index| {
                // Update frequency
                const current_freq = self.frequency_map.get(index) orelse 0;
                try self.frequency_map.put(index, current_freq + 1);
                return index;
            }

            const index = @as(u16, @intCast(self.patterns.items.len));
            const owned_types = try self.patterns.allocator.dupe(TypeId, types);

            try self.patterns.append(TypePattern{
                .types = owned_types,
                .hash = hash,
                .frequency = 1,
            });

            try self.pattern_to_index.put(hash, index);
            try self.frequency_map.put(index, 1);

            return index;
        }

        /// Get pattern index by hash
        pub fn getPatternIndex(self: *const PatternDictionary, types: []const TypeId) ?u16 {
            const hash = TypePattern.calculateHash(types);
            return self.pattern_to_index.get(hash);
        }

        /// Get pattern by index
        pub fn getPattern(self: *const PatternDictionary, index: u16) ?*const TypePattern {
            if (index >= self.patterns.items.len) return null;
            return &self.patterns.items[index];
        }
    };

    /// Implementation pool for deduplicating function implementations
    pub const ImplementationPool = struct {
        implementations: ArrayList(Implementation),
        impl_to_index: AutoHashMap(u64, u16), // Hash -> index

        pub const Implementation = struct {
            function_name: []const u8,
            module_name: []const u8,
            signature_hash: u64,
            reference_count: u32,
        };

        pub fn init(allocator: Allocator) ImplementationPool {
            return ImplementationPool{
                .implementations = ArrayList(Implementation).init(allocator),
                .impl_to_index = AutoHashMap(u64, u16).init(allocator),
            };
        }

        pub fn deinit(self: *ImplementationPool) void {
            for (self.implementations.items) |impl| {
                self.implementations.allocator.free(impl.function_name);
                self.implementations.allocator.free(impl.module_name);
            }
            self.implementations.deinit();
            self.impl_to_index.deinit();
        }

        /// Add implementation to pool
        pub fn addImplementation(self: *ImplementationPool, function_name: []const u8, module_name: []const u8, signature_hash: u64) !u16 {
            const impl_hash = self.calculateImplementationHash(function_name, module_name, signature_hash);

            if (self.impl_to_index.get(impl_hash)) |index| {
                self.implementations.items[index].reference_count += 1;
                return index;
            }

            const index = @as(u16, @intCast(self.implementations.items.len));

            try self.implementations.append(Implementation{
                .function_name = try self.implementations.allocator.dupe(u8, function_name),
                .module_name = try self.implementations.allocator.dupe(u8, module_name),
                .signature_hash = signature_hash,
                .reference_count = 1,
            });

            try self.impl_to_index.put(impl_hash, index);
            return index;
        }

        fn calculateImplementationHash(self: *ImplementationPool, function_name: []const u8, module_name: []const u8, signature_hash: u64) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(function_name);
            hasher.update(module_name);
            hasher.update(std.mem.asBytes(&signature_hash));
            return hasher.final();
        }
    };

    /// Delta-compressed type sequence
    pub const DeltaCompressedSequence = struct {
        base_value: TypeId,
        deltas: []i16, // Signed deltas, using varint encoding
        length: u16,

        pub fn compress(allocator: Allocator, types: []const TypeId) !DeltaCompressedSequence {
            if (types.len == 0) {
                return DeltaCompressedSequence{
                    .base_value = 0,
                    .deltas = &.{},
                    .length = 0,
                };
            }

            const base_value = types[0];
            var deltas = try allocator.alloc(i16, types.len - 1);

            for (types[1..], 0..) |type_id, i| {
                const delta = @as(i32, @intCast(type_id)) - @as(i32, @intCast(if (i == 0) base_value else types[i]));
                deltas[i] = @as(i16, @intCast(std.math.clamp(delta, std.math.minInt(i16), std.math.maxInt(i16))));
            }

            return DeltaCompressedSequence{
                .base_value = base_value,
                .deltas = deltas,
                .length = @intCast(types.len),
            };
        }

        pub fn decompress(self: *const DeltaCompressedSequence, allocator: Allocator) ![]TypeId {
            if (self.length == 0) return &.{};

            var types = try allocator.alloc(TypeId, self.length);
            types[0] = self.base_value;

            for (self.deltas, 1..) |delta, i| {
                types[i] = @as(TypeId, @intCast(@as(i32, @intCast(types[i - 1])) + delta));
            }

            return types;
        }

        pub fn getCompressedSize(self: *const DeltaCompressedSequence) usize {
            return @sizeOf(TypeId) + @sizeOf(u16) + self.deltas.len * @sizeOf(i16);
        }

        pub fn getOriginalSize(self: *const DeltaCompressedSequence) usize {
            return self.length * @sizeOf(TypeId);
        }

        pub fn deinit(self: *DeltaCompressedSequence, allocator: Allocator) void {
            allocator.free(self.deltas);
        }
    };

    /// Compressed dispatch entry using all optimization techniques
    pub const CompressedDispatchEntry = struct {
        // Pattern compression
        pattern_index: u16, // Index into pattern dictionary
        pattern_delta: ?DeltaCompressedSequence, // Delta compression for unique patterns

        // Implementation compression
        implementation_index: u16, // Index into implementation pool

        // Metadata compression
        specificity_score: u8, // Quantized to 8 bits
        call_frequency: u16, // Quantized to 16 bits with logarithmic scaling
        flags: u8, // Packed boolean flags

        // Bloom filter bits for fast negative lookups
        bloom_bits: u32,

        pub const FLAGS_STATIC_DISPATCH = 0x01;
        pub const FLAGS_HOT_PATH = 0x02;
        pub const FLAGS_FALLBACK = 0x04;
        pub const FLAGS_CROSS_MODULE = 0x08;
        pub const FLAGS_GENERIC = 0x10;
        pub const FLAGS_DELTA_COMPRESSED = 0x20;

        pub fn calculateBloomBits(types: []const TypeId) u32 {
            var bits: u32 = 0;
            for (types) |type_id| {
                // Use multiple hash functions for better distribution
                const hash1 = std.hash.Wyhash.hash(0, std.mem.asBytes(&type_id));
                const hash2 = std.hash.Wyhash.hash(1, std.mem.asBytes(&type_id));

                bits |= (@as(u32, 1) << @intCast(hash1 % 32));
                bits |= (@as(u32, 1) << @intCast(hash2 % 32));
            }
            return bits;
        }

        pub fn mightMatch(self: *const CompressedDispatchEntry, query_bloom_bits: u32) bool {
            return (self.bloom_bits & query_bloom_bits) == query_bloom_bits;
        }

        pub fn getMemoryUsage(self: *const CompressedDispatchEntry) usize {
            var size = @sizeOf(CompressedDispatchEntry);
            if (self.pattern_delta) |delta| {
                size += delta.getCompressedSize();
            }
            return size;
        }
    };

    /// Compressed dispatch table with all optimizations applied
    pub const CompressedDispatchTable = struct {
        signature_name: []const u8,
        entries: []CompressedDispatchEntry,

        // Dictionaries (shared across tables)
        type_dictionary_index: u16,
        pattern_dictionary_index: u16,
        implementation_pool_index: u16,

        // Decision tree for fast lookup
        decision_tree: ?*DecisionTreeNode,

        // Performance metadata
        total_calls: u64,
        cache_efficiency: f32,

        pub const DecisionTreeNode = struct {
            // Predicate-based compression: encode rules instead of explicit entries
            predicate: Predicate,
            true_branch: ?*DecisionTreeNode,
            false_branch: ?*DecisionTreeNode,
            leaf_entry_index: ?u16, // If this is a leaf node

            pub const Predicate = union(enum) {
                type_equals: struct { arg_index: u8, type_id: TypeId },
                type_subtype_of: struct { arg_index: u8, parent_type: TypeId },
                type_in_set: struct { arg_index: u8, type_set_bits: u64 }, // Bit set for up to 64 types
                pattern_matches: struct { pattern_index: u16 },
                bloom_filter: struct { bloom_bits: u32 },
                always_true,
                always_false,
            };

            pub fn evaluate(self: *const DecisionTreeNode, query_types: []const TypeId, compression: *const AdvancedDispatchCompression) bool {
                return switch (self.predicate) {
                    .type_equals => |pred| {
                        if (pred.arg_index >= query_types.len) return false;
                        return query_types[pred.arg_index] == pred.type_id;
                    },
                    .type_subtype_of => |pred| {
                        if (pred.arg_index >= query_types.len) return false;
                        // Would need type registry access for subtype checking
                        _ = compression;
                        return false; // Simplified for now
                    },
                    .type_in_set => |pred| {
                        if (pred.arg_index >= query_types.len) return false;
                        const type_id = query_types[pred.arg_index];
                        if (type_id >= 64) return false; // Outside bit set range
                        return (pred.type_set_bits & (@as(u64, 1) << @intCast(type_id))) != 0;
                    },
                    .pattern_matches => |pred| {
                        if (compression.pattern_dictionary.getPattern(pred.pattern_index)) |pattern| {
                            return std.mem.eql(TypeId, query_types, pattern.types);
                        }
                        return false;
                    },
                    .bloom_filter => |pred| {
                        const query_bloom = CompressedDispatchEntry.calculateBloomBits(query_types);
                        return (pred.bloom_bits & query_bloom) == query_bloom;
                    },
                    .always_true => true,
                    .always_false => false,
                };
            }
        };

        pub fn lookup(self: *const CompressedDispatchTable, query_types: []const TypeId, compression: *const AdvancedDispatchCompression) ?u16 {
            if (self.decision_tree) |tree| {
                return self.traverseDecisionTree(tree, query_types, compression);
            }

            // Fallback to linear search with bloom filter optimization
            const query_bloom = CompressedDispatchEntry.calculateBloomBits(query_types);

            for (self.entries, 0..) |entry, i| {
                if (!entry.mightMatch(query_bloom)) continue;

                // Full pattern match (would need to decompress pattern)
                if (self.matchesPattern(&entry, query_types, compression)) {
                    return @intCast(i);
                }
            }

            return null;
        }

        fn traverseDecisionTree(self: *const CompressedDispatchTable, node: *const DecisionTreeNode, query_types: []const TypeId, compression: *const AdvancedDispatchCompression) ?u16 {
            if (node.leaf_entry_index) |index| {
                return index;
            }

            const predicate_result = node.evaluate(query_types, compression);
            const next_node = if (predicate_result) node.true_branch else node.false_branch;

            if (next_node) |next| {
                return self.traverseDecisionTree(next, query_types, compression);
            }

            return null;
        }

        fn matchesPattern(self: *const CompressedDispatchTable, entry: *const CompressedDispatchEntry, query_types: []const TypeId, compression: *const AdvancedDispatchCompression) bool {
            _ = self;

            // Get pattern from dictionary
            if (compression.pattern_dictionary.getPattern(entry.pattern_index)) |pattern| {
                return std.mem.eql(TypeId, query_types, pattern.types);
            }

            // If pattern has delta compression, decompress and compare
            if (entry.pattern_delta) |delta| {
                const decompressed = delta.decompress(compression.allocator) catch return false;
                defer compression.allocator.free(decompressed);
                return std.mem.eql(TypeId, query_types, decompressed);
            }

            return false;
        }
    };

    pub fn init(allocator: Allocator) AdvancedDispatchCompression {
        return AdvancedDispatchCompression{
            .allocator = allocator,
            .type_dictionary = TypeDictionary.init(allocator),
            .pattern_dictionary = PatternDictionary.init(allocator),
            .implementation_pool = ImplementationPool.init(allocator),
            .compression_stats = std.mem.zeroes(CompressionStats),
        };
    }

    pub fn deinit(self: *AdvancedDispatchCompression) void {
        self.type_dictionary.deinit();
        self.pattern_dictionary.deinit();
        self.implementation_pool.deinit();
    }

    /// Compress a dispatch table using all available techniques
    pub fn compressDispatchTable(self: *AdvancedDispatchCompression, entries: []const DispatchEntry, signature_name: []const u8) !CompressedDispatchTable {
        const original_size = entries.len * @sizeOf(DispatchEntry);
        self.compression_stats.original_bytes += original_size;

        // Build dictionaries from the entries
        try self.buildDictionaries(entries);

        // Compress entries
        var compressed_entries = try self.allocator.alloc(CompressedDispatchEntry, entries.len);
        var compressed_size: usize = 0;

        for (entries, 0..) |entry, i| {
            compressed_entries[i] = try self.compressEntry(&entry);
            compressed_size += compressed_entries[i].getMemoryUsage();
        }

        // Build decision tree for fast lookup
        const decision_tree = try self.buildDecisionTree(compressed_entries);

        self.compression_stats.compressed_bytes += compressed_size;

        return CompressedDispatchTable{
            .signature_name = try self.allocator.dupe(u8, signature_name),
            .entries = compressed_entries,
            .type_dictionary_index = 0, // Simplified
            .pattern_dictionary_index = 0, // Simplified
            .implementation_pool_index = 0, // Simplified
            .decision_tree = decision_tree,
            .total_calls = 0,
            .cache_efficiency = 0.0,
        };
    }

    /// Build dictionaries from dispatch entries
    fn buildDictionaries(self: *AdvancedDispatchCompression, entries: []const DispatchEntry) !void {
        for (entries) |entry| {
            // Add types to type dictionary
            for (entry.type_pattern) |type_id| {
                _ = try self.type_dictionary.addType(type_id);
            }

            // Add pattern to pattern dictionary
            _ = try self.pattern_dictionary.addPattern(entry.type_pattern);

            // Add implementation to pool
            _ = try self.implementation_pool.addImplementation(entry.function_name, entry.module_name, entry.signature_hash);
        }

        // Optimize dictionaries by frequency
        try self.type_dictionary.optimizeByFrequency();
    }

    /// Compress a single dispatch entry
    fn compressEntry(self: *AdvancedDispatchCompression, entry: *const DispatchEntry) !CompressedDispatchEntry {
        // Get pattern index
        const pattern_index = self.pattern_dictionary.getPatternIndex(entry.type_pattern) orelse 0;

        // Try delta compression for the pattern
        var pattern_delta: ?DeltaCompressedSequence = null;
        var flags: u8 = 0;

        if (entry.type_pattern.len > 1) {
            const delta_compressed = try DeltaCompressedSequence.compress(self.allocator, entry.type_pattern);
            if (delta_compressed.getCompressedSize() < delta_compressed.getOriginalSize()) {
                pattern_delta = delta_compressed;
                flags |= CompressedDispatchEntry.FLAGS_DELTA_COMPRESSED;
                self.compression_stats.delta_compression_savings += delta_compressed.getOriginalSize() - delta_compressed.getCompressedSize();
            } else {
                delta_compressed.deinit(self.allocator);
            }
        }

        // Get implementation index
        const impl_index = try self.implementation_pool.addImplementation(entry.function_name, entry.module_name, entry.signature_hash);

        // Set other flags
        if (entry.is_static_dispatch) flags |= CompressedDispatchEntry.FLAGS_STATIC_DISPATCH;
        if (entry.is_hot_path) flags |= CompressedDispatchEntry.FLAGS_HOT_PATH;
        if (entry.is_fallback) flags |= CompressedDispatchEntry.FLAGS_FALLBACK;

        // Calculate bloom filter bits
        const bloom_bits = CompressedDispatchEntry.calculateBloomBits(entry.type_pattern);

        return CompressedDispatchEntry{
            .pattern_index = pattern_index,
            .pattern_delta = pattern_delta,
            .implementation_index = impl_index,
            .specificity_score = @as(u8, @intCast(@min(entry.specificity_score, 255))),
            .call_frequency = @as(u16, @intCast(@min(entry.call_frequency, 65535))),
            .flags = flags,
            .bloom_bits = bloom_bits,
        };
    }

    /// Build decision tree for fast dispatch
    fn buildDecisionTree(self: *AdvancedDispatchCompression, entries: []const CompressedDispatchEntry) !?*CompressedDispatchTable.DecisionTreeNode {
        if (entries.len == 0) return null;
        if (entries.len == 1) {
            // Leaf node
            const node = try self.allocator.create(CompressedDispatchTable.DecisionTreeNode);
            node.* = CompressedDispatchTable.DecisionTreeNode{
                .predicate = .always_true,
                .true_branch = null,
                .false_branch = null,
                .leaf_entry_index = 0,
            };
            return node;
        }

        // Find best predicate to split on
        const best_predicate = try self.findBestPredicate(entries);

        // Split entries based on predicate
        var true_entries = ArrayList(CompressedDispatchEntry).init(self.allocator);
        var false_entries = ArrayList(CompressedDispatchEntry).init(self.allocator);
        defer true_entries.deinit();
        defer false_entries.deinit();

        for (entries) |entry| {
            // Simplified predicate evaluation for tree building
            if (self.evaluatePredicateForEntry(&best_predicate, &entry)) {
                try true_entries.append(entry);
            } else {
                try false_entries.append(entry);
            }
        }

        // Recursively build subtrees
        const true_branch = if (true_entries.items.len > 0)
            try self.buildDecisionTree(true_entries.items)
        else
            null;

        const false_branch = if (false_entries.items.len > 0)
            try self.buildDecisionTree(false_entries.items)
        else
            null;

        const node = try self.allocator.create(CompressedDispatchTable.DecisionTreeNode);
        node.* = CompressedDispatchTable.DecisionTreeNode{
            .predicate = best_predicate,
            .true_branch = true_branch,
            .false_branch = false_branch,
            .leaf_entry_index = null,
        };

        return node;
    }

    /// Find the best predicate to split entries
    fn findBestPredicate(self: *AdvancedDispatchCompression, entries: []const CompressedDispatchEntry) !CompressedDispatchTable.DecisionTreeNode.Predicate {
        _ = self;
        _ = entries;

        // Simplified: just use bloom filter predicate
        // In a real implementation, this would analyze the entries and find the predicate
        // that best splits them (e.g., using information gain)
        return CompressedDispatchTable.DecisionTreeNode.Predicate{ .bloom_filter = .{ .bloom_bits = 0xFFFFFFFF } };
    }

    /// Evaluate predicate for a single entry (used during tree building)
    fn evaluatePredicateForEntry(self: *AdvancedDispatchCompression, predicate: *const CompressedDispatchTable.DecisionTreeNode.Predicate, entry: *const CompressedDispatchEntry) bool {
        _ = self;

        return switch (predicate.*) {
            .bloom_filter => |pred| (entry.bloom_bits & pred.bloom_bits) != 0,
            .always_true => true,
            .always_false => false,
            else => false, // Simplified
        };
    }

    /// Generate compression report
    pub fn generateCompressionReport(self: *const AdvancedDispatchCompression, writer: anytype) !void {
        try writer.print("=== Advanced Dispatch Compression Report ===\n");
        try writer.print("Original size: {} bytes\n", .{self.compression_stats.original_bytes});
        try writer.print("Compressed size: {} bytes\n", .{self.compression_stats.compressed_bytes});
        try writer.print("Dictionary overhead: {} bytes\n", .{self.compression_stats.dictionary_bytes});
        try writer.print("Total compression ratio: {d:.3}\n", .{self.compression_stats.getTotalCompressionRatio()});
        try writer.print("Effective compression ratio: {d:.3}\n", .{self.compression_stats.getEffectiveCompressionRatio()});

        try writer.print("\nTechnique-specific savings:\n");
        try writer.print("  Delta compression: {} bytes\n", .{self.compression_stats.delta_compression_savings});
        try writer.print("  Pattern compression: {} bytes\n", .{self.compression_stats.pattern_compression_savings});
        try writer.print("  Dictionary compression: {} bytes\n", .{self.compression_stats.dictionary_compression_savings});

        try writer.print("\nDictionary statistics:\n");
        try writer.print("  Type dictionary: {} entries\n", .{self.type_dictionary.index_to_type.items.len});
        try writer.print("  Pattern dictionary: {} entries\n", .{self.pattern_dictionary.patterns.items.len});
        try writer.print("  Implementation pool: {} entries\n", .{self.implementation_pool.implementations.items.len});
    }

    // Simplified dispatch entry structure for the compression system
    pub const DispatchEntry = struct {
        type_pattern: []const TypeId,
        function_name: []const u8,
        module_name: []const u8,
        signature_hash: u64,
        specificity_score: u32,
        call_frequency: u32,
        is_static_dispatch: bool,
        is_hot_path: bool,
        is_fallback: bool,
    };
};
