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

/// Comprehensive dispatch table serialization system for build caching
pub const DispatchTableSerializer = struct {
    allocator: Allocator,

    // Version tracking for compatibility
    format_version: u32,

    // Serialization statistics
    stats: SerializationStats,

    // Cache management
    cache_directory: []const u8,
    cache_index: CacheIndex,

    const Self = @This();

    /// Current serialization format version
    pub const CURRENT_FORMAT_VERSION: u32 = 1;

    /// Magic number for dispatch table cache files
    pub const CACHE_FILE_MAGIC: u32 = 0x4A414E55; // "JANU" in ASCII

    /// Statistics for serialization operations
    pub const SerializationStats = struct {
        tables_serialized: u32,
        tables_deserialized: u32,
        cache_hits: u32,
        cache_misses: u32,

        // Size metrics
        total_serialized_bytes: usize,
        total_deserialized_bytes: usize,
        compression_ratio: f32,

        // Performance metrics
        serialization_time_ns: u64,
        deserialization_time_ns: u64,
        cache_lookup_time_ns: u64,

        pub fn getAverageSerializationTime(self: *const SerializationStats) f64 {
            if (self.tables_serialized == 0) return 0.0;
            return @as(f64, @floatFromInt(self.serialization_time_ns)) / @as(f64, @floatFromInt(self.tables_serialized));
        }

        pub fn getAverageDeserializationTime(self: *const SerializationStats) f64 {
            if (self.tables_deserialized == 0) return 0.0;
            return @as(f64, @floatFromInt(self.deserialization_time_ns)) / @as(f64, @floatFromInt(self.tables_deserialized));
        }

        pub fn getCacheHitRatio(self: *const SerializationStats) f64 {
            const total_lookups = self.cache_hits + self.cache_misses;
            if (total_lookups == 0) return 0.0;
            return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total_lookups));
        }

        pub fn format(self: SerializationStats, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Serialization Statistics:\n");
            try writer.print("  Tables: {} serialized, {} deserialized\n", .{ self.tables_serialized, self.tables_deserialized });
            try writer.print("  Cache: {} hits, {} misses ({d:.1}% hit ratio)\n", .{ self.cache_hits, self.cache_misses, self.getCacheHitRatio() * 100.0 });
            try writer.print("  Size: {} serialized, {} deserialized ({d:.1}% compression)\n", .{ self.total_serialized_bytes, self.total_deserialized_bytes, self.compression_ratio * 100.0 });
            try writer.print("  Performance: {d:.1}μs avg serialization, {d:.1}μs avg deserialization\n", .{ self.getAverageSerializationTime() / 1000.0, self.getAverageDeserializationTime() / 1000.0 });
        }
    };

    /// Cache index for fast lookup of cached dispatch tables
    pub const CacheIndex = struct {
        entries: HashMap(CacheKey, CacheEntry),

        pub const CacheKey = struct {
            signature_hash: u64,
            type_signature_hash: u64,
            dependencies_hash: u64,

            pub fn hash(self: CacheKey) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hasher.update(std.mem.asBytes(&self.signature_hash));
                hasher.update(std.mem.asBytes(&self.type_signature_hash));
                hasher.update(std.mem.asBytes(&self.dependencies_hash));
                return hasher.final();
            }

            pub fn eql(self: CacheKey, other: CacheKey) bool {
                return self.signature_hash == other.signature_hash and
                    self.type_signature_hash == other.type_signature_hash and
                    self.dependencies_hash == other.dependencies_hash;
            }
        };

        pub const CacheEntry = struct {
            file_path: []const u8,
            file_size: usize,
            creation_time: u64,
            last_access_time: u64,
            access_count: u32,
            format_version: u32,

            // Metadata for validation
            original_table_hash: u64,
            optimization_config_hash: u64,

            pub fn isValid(self: *const CacheEntry, current_time: u64, max_age_seconds: u64) bool {
                return (current_time - self.creation_time) <= (max_age_seconds * std.time.ns_per_s);
            }

            pub fn updateAccess(self: *CacheEntry, current_time: u64) void {
                self.last_access_time = current_time;
                self.access_count += 1;
            }
        };

        pub fn init(allocator: Allocator) CacheIndex {
            return CacheIndex{
                .entries = HashMap(CacheKey, CacheEntry).init(allocator),
            };
        }

        pub fn deinit(self: *CacheIndex, allocator: Allocator) void {
            var iter = self.entries.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.value_ptr.file_path);
            }
            self.entries.deinit();
        }

        pub fn put(self: *CacheIndex, allocator: Allocator, key: CacheKey, entry: CacheEntry) !void {
            const owned_path = try allocator.dupe(u8, entry.file_path);
            var owned_entry = entry;
            owned_entry.file_path = owned_path;
            try self.entries.put(key, owned_entry);
        }

        pub fn get(self: *CacheIndex, key: CacheKey) ?*CacheEntry {
            return self.entries.getPtr(key);
        }

        pub fn remove(self: *CacheIndex, allocator: Allocator, key: CacheKey) void {
            if (self.entries.fetchRemove(key)) |removed| {
                allocator.free(removed.value.file_path);
            }
        }
    };

    /// Serialized dispatch table format
    pub const SerializedDispatchTable = struct {
        // File header
        magic: u32,
        format_version: u32,
        table_hash: u64,
        creation_timestamp: u64,

        // Table metadata
        signature_name_len: u32,
        type_signature_len: u32,
        entry_count: u32,

        // Optimization metadata
        optimization_applied: DispatchTableOptimizer.OptimizationResult.OptimizationType,
        compression_ratio: f32,
        memory_saved: usize,

        // Checksums for integrity
        metadata_checksum: u32,
        data_checksum: u32,

        // Variable-length data follows:
        // - signature_name: [signature_name_len]u8
        // - type_signature: [type_signature_len]TypeId
        // - entries: [entry_count]SerializedDispatchEntry
        // - decision_tree: SerializedDecisionTree (if present)
        // - compression_data: []u8 (if compressed)

        pub fn calculateSize(signature_name: []const u8, type_signature: []const TypeId, entry_count: u32, has_decision_tree: bool, compression_data_len: usize) usize {
            var size = @sizeOf(SerializedDispatchTable);
            size += signature_name.len;
            size += type_signature.len * @sizeOf(TypeId);
            size += entry_count * @sizeOf(SerializedDispatchEntry);

            if (has_decision_tree) {
                size += @sizeOf(SerializedDecisionTree);
            }

            size += compression_data_len;

            return size;
        }
    };

    /// Serialized dispatch entry format
    pub const SerializedDispatchEntry = struct {
        type_pattern: u64,
        specificity_score: u32,
        call_frequency: u32,

        // Implementation reference
        function_name_len: u32,
        module_name_len: u32,
        function_id: u32,

        // Variable-length data:
        // - function_name: [function_name_len]u8
        // - module_name: [module_name_len]u8
    };

    /// Serialized decision tree format
    pub const SerializedDecisionTree = struct {
        node_count: u32,
        root_node_index: u32,

        // Variable-length data:
        // - nodes: [node_count]SerializedDecisionTreeNode
    };

    /// Serialized decision tree node format
    pub const SerializedDecisionTreeNode = struct {
        discriminator_type_index: u16,
        discriminator_type_id: TypeId,
        left_child_index: u32, // u32::MAX if null
        right_child_index: u32, // u32::MAX if null

        // Leaf node data
        is_leaf: bool,
        implementation_index: u32, // Index into serialized entries, u32::MAX if null

        // Performance data
        access_count: u32,
        last_access_time: u64,
    };

    pub fn init(allocator: Allocator, cache_directory: []const u8) !Self {
        // Ensure cache directory exists
        std.fs.cwd().makeDir(cache_directory) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        var self = Self{
            .allocator = allocator,
            .format_version = CURRENT_FORMAT_VERSION,
            .stats = std.mem.zeroes(SerializationStats),
            .cache_directory = try allocator.dupe(u8, cache_directory),
            .cache_index = CacheIndex.init(allocator),
        };

        // Load existing cache index
        try self.loadCacheIndex();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.saveCacheIndex() catch {}; // Best effort save
        self.cache_index.deinit(self.allocator);
        self.allocator.free(self.cache_directory);
    }

    /// Serialize a dispatch table to cache
    pub fn serializeTable(self: *Self, table: *OptimizedDispatchTable, optimization_result: ?DispatchTableOptimizer.OptimizationResult) ![]const u8 {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.stats.serialization_time_ns += @intCast(end_time - start_time);
            self.stats.tables_serialized += 1;
        }

        // Calculate cache key
        const cache_key = try self.calculateCacheKey(table);

        // Generate file path
        const file_path = try self.generateCacheFilePath(cache_key);
        defer self.allocator.free(file_path);

        // Serialize to memory buffer first
        var buffer: ArrayList(u8) = .empty;
        defer buffer.deinit();

        try self.serializeToBuffer(table, optimization_result, &buffer);

        // Write to file
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        try file.writeAll(buffer.items);

        // Update cache index
        const cache_entry = CacheIndex.CacheEntry{
            .file_path = file_path,
            .file_size = buffer.items.len,
            .creation_time = @intCast(std.time.nanoTimestamp()),
            .last_access_time = @intCast(std.time.nanoTimestamp()),
            .access_count = 0,
            .format_version = self.format_version,
            .original_table_hash = self.calculateTableHash(table),
            .optimization_config_hash = if (optimization_result) |result| self.calculateOptimizationHash(&result) else 0,
        };

        try self.cache_index.put(self.allocator, cache_key, cache_entry);

        self.stats.total_serialized_bytes += buffer.items.len;

        return try self.allocator.dupe(u8, file_path);
    }

    /// Deserialize a dispatch table from cache
    pub fn deserializeTable(self: *Self, cache_key: CacheIndex.CacheKey, type_registry: *TypeRegistry) !?*OptimizedDispatchTable {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.stats.cache_lookup_time_ns += @intCast(end_time - start_time);
        }

        // Check cache index
        if (self.cache_index.get(cache_key)) |cache_entry| {
            // Validate cache entry
            const current_time = @intCast(std.time.nanoTimestamp());
            if (!cache_entry.isValid(current_time, 24 * 60 * 60)) { // 24 hour max age
                self.cache_index.remove(self.allocator, cache_key);
                self.stats.cache_misses += 1;
                return null;
            }

            // Update access statistics
            cache_entry.updateAccess(current_time);
            self.stats.cache_hits += 1;

            // Load and deserialize file
            const deserialize_start = std.time.nanoTimestamp();
            defer {
                const deserialize_end = std.time.nanoTimestamp();
                self.stats.deserialization_time_ns += @intCast(deserialize_end - deserialize_start);
                self.stats.tables_deserialized += 1;
            }

            const file_data = std.fs.cwd().readFileAlloc(self.allocator, cache_entry.file_path, std.math.maxInt(usize)) catch |err| switch (err) {
                error.FileNotFound => {
                    // Cache entry is stale, remove it
                    self.cache_index.remove(self.allocator, cache_key);
                    self.stats.cache_misses += 1;
                    return null;
                },
                else => return err,
            };
            defer self.allocator.free(file_data);

            self.stats.total_deserialized_bytes += file_data.len;

            return try self.deserializeFromBuffer(file_data, type_registry);
        } else {
            self.stats.cache_misses += 1;
            return null;
        }
    }

    /// Check if a dispatch table is cached
    pub fn isCached(self: *Self, table: *OptimizedDispatchTable) !bool {
        const cache_key = try self.calculateCacheKey(table);

        if (self.cache_index.get(cache_key)) |cache_entry| {
            const current_time = @intCast(std.time.nanoTimestamp());
            return cache_entry.isValid(current_time, 24 * 60 * 60);
        }

        return false;
    }

    /// Invalidate cached dispatch table
    pub fn invalidateCache(self: *Self, table: *OptimizedDispatchTable) !void {
        const cache_key = try self.calculateCacheKey(table);

        if (self.cache_index.get(cache_key)) |cache_entry| {
            // Delete cache file
            std.fs.cwd().deleteFile(cache_entry.file_path) catch {};

            // Remove from index
            self.cache_index.remove(self.allocator, cache_key);
        }
    }

    /// Clean up old cache entries
    pub fn cleanupCache(self: *Self, max_age_seconds: u64, max_cache_size_bytes: usize) !void {
        const current_time = @intCast(std.time.nanoTimestamp());
        var total_cache_size: usize = 0;

        // Collect entries for cleanup
        var entries_to_remove: ArrayList(CacheIndex.CacheKey) = .empty;
        defer entries_to_remove.deinit();

        var iter = self.cache_index.entries.iterator();
        while (iter.next()) |entry| {
            const cache_entry = entry.value_ptr;

            // Remove expired entries
            if (!cache_entry.isValid(current_time, max_age_seconds)) {
                try entries_to_remove.append(entry.key_ptr.*);
                continue;
            }

            total_cache_size += cache_entry.file_size;
        }

        // Remove expired entries
        for (entries_to_remove.items) |key| {
            if (self.cache_index.get(key)) |cache_entry| {
                std.fs.cwd().deleteFile(cache_entry.file_path) catch {};
            }
            self.cache_index.remove(self.allocator, key);
        }

        // If still over size limit, remove least recently used entries
        if (total_cache_size > max_cache_size_bytes) {
            try self.cleanupBySize(max_cache_size_bytes);
        }
    }

    /// Get serialization statistics
    pub fn getStats(self: *const Self) SerializationStats {
        return self.stats;
    }

    /// Reset serialization statistics
    pub fn resetStats(self: *Self) void {
        self.stats = std.mem.zeroes(SerializationStats);
    }

    /// Generate cache report
    pub fn generateCacheReport(self: *Self, writer: anytype) !void {
        try writer.print("Dispatch Table Cache Report\n");
        try writer.print("===========================\n\n");

        try writer.print("{}\n\n", .{self.stats});

        // Cache index analysis
        try writer.print("Cache Index Analysis:\n");
        try writer.print("---------------------\n");
        try writer.print("  Total entries: {}\n", .{self.cache_index.entries.count()});

        var total_size: usize = 0;
        var oldest_entry: u64 = std.math.maxInt(u64);
        var newest_entry: u64 = 0;
        var most_accessed_count: u32 = 0;

        var iter = self.cache_index.entries.iterator();
        while (iter.next()) |entry| {
            const cache_entry = entry.value_ptr;
            total_size += cache_entry.file_size;

            if (cache_entry.creation_time < oldest_entry) {
                oldest_entry = cache_entry.creation_time;
            }
            if (cache_entry.creation_time > newest_entry) {
                newest_entry = cache_entry.creation_time;
            }
            if (cache_entry.access_count > most_accessed_count) {
                most_accessed_count = cache_entry.access_count;
            }
        }

        try writer.print("  Total cache size: {} bytes\n", .{total_size});
        try writer.print("  Age range: {} - {} ns\n", .{ oldest_entry, newest_entry });
        try writer.print("  Most accessed entry: {} times\n", .{most_accessed_count});

        // Recommendations
        try writer.print("\nCache Optimization Recommendations:\n");
        try writer.print("------------------------------------\n");

        if (self.stats.getCacheHitRatio() < 0.5) {
            try writer.print("  - Cache hit ratio is low (<50%)\n");
            try writer.print("    Consider increasing cache size or adjusting invalidation strategy\n");
        }

        if (total_size > 100 * 1024 * 1024) { // 100MB
            try writer.print("  - Cache size is large (>100MB)\n");
            try writer.print("    Consider implementing more aggressive cleanup policies\n");
        }

        if (self.cache_index.entries.count() > 1000) {
            try writer.print("  - Large number of cache entries (>1000)\n");
            try writer.print("    Consider implementing entry limits or LRU eviction\n");
        }
    }

    // Private helper methods

    fn calculateCacheKey(self: *Self, table: *OptimizedDispatchTable) !CacheIndex.CacheKey {
        const signature_hash = self.hashString(table.signature_name);
        const type_signature_hash = self.hashTypeSignature(table.type_signature);
        const dependencies_hash = self.calculateDependenciesHash(table);

        return CacheIndex.CacheKey{
            .signature_hash = signature_hash,
            .type_signature_hash = type_signature_hash,
            .dependencies_hash = dependencies_hash,
        };
    }

    fn generateCacheFilePath(self: *Self, cache_key: CacheIndex.CacheKey) ![]const u8 {
        const key_hash = cache_key.hash();
        const filename = try std.fmt.allocPrint(self.allocator, "dispatch_table_{x}.jdc", .{key_hash});
        defer self.allocator.free(filename);

        return try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_directory, filename });
    }

    fn serializeToBuffer(self: *Self, table: *OptimizedDispatchTable, optimization_result: ?DispatchTableOptimizer.OptimizationResult, buffer: *ArrayList(u8)) !void {
        const writer = buffer.writer();

        // Calculate sizes
        const has_decision_tree = table.decision_tree != null;
        const compression_data_len: usize = if (table.is_compressed) table.compressed_data.len else 0;

        // Write header
        const header = SerializedDispatchTable{
            .magic = CACHE_FILE_MAGIC,
            .format_version = self.format_version,
            .table_hash = self.calculateTableHash(table),
            .creation_timestamp = @intCast(std.time.nanoTimestamp()),
            .signature_name_len = @intCast(table.signature_name.len),
            .type_signature_len = @intCast(table.type_signature.len),
            .entry_count = table.entry_count,
            .optimization_applied = if (optimization_result) |result| result.optimization_applied else .none,
            .compression_ratio = if (optimization_result) |result| @floatCast(result.memory_saved) else 0.0,
            .memory_saved = if (optimization_result) |result| result.memory_saved else 0,
            .metadata_checksum = 0, // Will be calculated later
            .data_checksum = 0, // Will be calculated later
        };

        try writer.writeStruct(header);

        // Write variable-length data
        try writer.writeAll(table.signature_name);
        try writer.writeAll(std.mem.sliceAsBytes(table.type_signature));

        // Write dispatch entries
        for (table.entries[0..table.entry_count]) |entry| {
            try self.serializeDispatchEntry(entry, writer);
        }

        // Write decision tree if present
        if (has_decision_tree) {
            try self.serializeDecisionTree(table.decision_tree.?, writer);
        }

        // Write compression data if present
        if (compression_data_len > 0) {
            try writer.writeAll(table.compressed_data);
        }

        // Calculate and update checksums
        try self.updateChecksums(buffer);
    }

    fn deserializeFromBuffer(self: *Self, data: []const u8, type_registry: *TypeRegistry) !*OptimizedDispatchTable {
        var stream = std.io.fixedBufferStream(data);
        const reader = stream.reader();

        // Read and validate header
        const header = try reader.readStruct(SerializedDispatchTable);

        if (header.magic != CACHE_FILE_MAGIC) {
            return error.InvalidCacheFile;
        }

        if (header.format_version != self.format_version) {
            return error.IncompatibleVersion;
        }

        // Validate checksums
        if (!try self.validateChecksums(data, header)) {
            return error.CorruptedCacheFile;
        }

        // Read variable-length data
        const signature_name = try self.allocator.alloc(u8, header.signature_name_len);
        try reader.readNoEof(signature_name);

        const type_signature = try self.allocator.alloc(TypeId, header.type_signature_len);
        try reader.readNoEof(std.mem.sliceAsBytes(type_signature));

        // Create dispatch table
        var table = try OptimizedDispatchTable.init(self.allocator, signature_name, type_signature);

        // Read dispatch entries
        for (0..header.entry_count) |_| {
            const entry = try self.deserializeDispatchEntry(reader, type_registry);
            try table.addImplementation(entry.implementation_ptr);
        }

        // Read decision tree if present (simplified check)
        if (stream.pos < data.len) {
            // Attempt to read decision tree
            // This is a simplified implementation
        }

        return table;
    }

    fn serializeDispatchEntry(self: *Self, entry: OptimizedDispatchTable.DispatchEntry, writer: anytype) !void {
        const impl = entry.implementation_ptr;

        const serialized_entry = SerializedDispatchEntry{
            .type_pattern = entry.type_pattern,
            .specificity_score = entry.specificity_score,
            .call_frequency = entry.call_frequency,
            .function_name_len = @intCast(impl.function_id.name.len),
            .module_name_len = @intCast(impl.function_id.module.len),
            .function_id = impl.function_id.id,
        };

        try writer.writeStruct(serialized_entry);
        try writer.writeAll(impl.function_id.name);
        try writer.writeAll(impl.function_id.module);
    }

    fn deserializeDispatchEntry(self: *Self, reader: anytype, type_registry: *TypeRegistry) !OptimizedDispatchTable.DispatchEntry {
        _ = type_registry;

        const serialized_entry = try reader.readStruct(SerializedDispatchEntry);

        const function_name = try self.allocator.alloc(u8, serialized_entry.function_name_len);
        try reader.readNoEof(function_name);

        const module_name = try self.allocator.alloc(u8, serialized_entry.module_name_len);
        try reader.readNoEof(module_name);

        // Create implementation (simplified)
        const impl = try self.allocator.create(SignatureAnalyzer.Implementation);
        impl.* = SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{
                .name = function_name,
                .module = module_name,
                .id = serialized_entry.function_id,
            },
            .param_type_ids = &.{}, // Would need to be reconstructed
            .return_type_id = 0, // Would need to be reconstructed
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = serialized_entry.specificity_score,
        };

        return OptimizedDispatchTable.DispatchEntry{
            .type_pattern = serialized_entry.type_pattern,
            .implementation_ptr = impl,
            .specificity_score = serialized_entry.specificity_score,
            .call_frequency = serialized_entry.call_frequency,
        };
    }

    fn serializeDecisionTree(self: *Self, root: *OptimizedDispatchTable.DecisionTreeNode, writer: anytype) !void {
        // Count nodes first
        const node_count = self.countDecisionTreeNodes(root);

        const tree_header = SerializedDecisionTree{
            .node_count = node_count,
            .root_node_index = 0,
        };

        try writer.writeStruct(tree_header);

        // Serialize nodes in breadth-first order
        var nodes: ArrayList(*OptimizedDispatchTable.DecisionTreeNode) = .empty;
        defer nodes.deinit();

        try nodes.append(root);

        var node_index: u32 = 0;
        while (node_index < nodes.items.len) {
            const node = nodes.items[node_index];

            // Add children to queue
            var left_index: u32 = std.math.maxInt(u32);
            var right_index: u32 = std.math.maxInt(u32);

            if (node.left_child) |left| {
                left_index = @intCast(nodes.items.len);
                try nodes.append(left);
            }

            if (node.right_child) |right| {
                right_index = @intCast(nodes.items.len);
                try nodes.append(right);
            }

            // Serialize node
            const serialized_node = SerializedDecisionTreeNode{
                .discriminator_type_index = node.discriminator_type_index,
                .discriminator_type_id = node.discriminator_type_id,
                .left_child_index = left_index,
                .right_child_index = right_index,
                .is_leaf = node.is_leaf,
                .implementation_index = if (node.implementation) |_| 0 else std.math.maxInt(u32), // Simplified
                .access_count = node.access_count,
                .last_access_time = node.last_access_time,
            };

            try writer.writeStruct(serialized_node);
            node_index += 1;
        }
    }

    fn countDecisionTreeNodes(self: *Self, node: *OptimizedDispatchTable.DecisionTreeNode) u32 {
        _ = self;
        var count: u32 = 1;

        if (node.left_child) |left| {
            count += self.countDecisionTreeNodes(left);
        }

        if (node.right_child) |right| {
            count += self.countDecisionTreeNodes(right);
        }

        return count;
    }

    fn updateChecksums(self: *Self, buffer: *ArrayList(u8)) !void {
        _ = self;

        // Calculate checksums for the serialized data
        const data = buffer.items;
        const header_size = @sizeOf(SerializedDispatchTable);

        if (data.len < header_size) return error.InvalidBuffer;

        // Calculate metadata checksum (header only)
        var metadata_hasher = std.hash.Crc32.init();
        metadata_hasher.update(data[0..header_size]);
        const metadata_checksum = metadata_hasher.final();

        // Calculate data checksum (everything after header)
        var data_hasher = std.hash.Crc32.init();
        if (data.len > header_size) {
            data_hasher.update(data[header_size..]);
        }
        const data_checksum = data_hasher.final();

        // Update checksums in header
        std.mem.writeInt(u32, data[@offsetOf(SerializedDispatchTable, "metadata_checksum")..][0..4], metadata_checksum, .little);
        std.mem.writeInt(u32, data[@offsetOf(SerializedDispatchTable, "data_checksum")..][0..4], data_checksum, .little);
    }

    fn validateChecksums(self: *Self, data: []const u8, header: SerializedDispatchTable) !bool {
        _ = self;

        const header_size = @sizeOf(SerializedDispatchTable);

        if (data.len < header_size) return false;

        // Validate metadata checksum
        var metadata_hasher = std.hash.Crc32.init();
        var header_copy = header;
        header_copy.metadata_checksum = 0;
        header_copy.data_checksum = 0;
        metadata_hasher.update(std.mem.asBytes(&header_copy));

        if (metadata_hasher.final() != header.metadata_checksum) {
            return false;
        }

        // Validate data checksum
        var data_hasher = std.hash.Crc32.init();
        if (data.len > header_size) {
            data_hasher.update(data[header_size..]);
        }

        return data_hasher.final() == header.data_checksum;
    }

    fn calculateTableHash(self: *Self, table: *OptimizedDispatchTable) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(table.signature_name);
        hasher.update(std.mem.sliceAsBytes(table.type_signature));
        hasher.update(std.mem.asBytes(&table.entry_count));

        for (table.entries[0..table.entry_count]) |entry| {
            hasher.update(std.mem.asBytes(&entry.type_pattern));
            hasher.update(std.mem.asBytes(&entry.specificity_score));
        }

        return hasher.final();
    }

    fn calculateOptimizationHash(self: *Self, result: *const DispatchTableOptimizer.OptimizationResult) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(std.mem.asBytes(&result.optimization_applied));
        hasher.update(std.mem.asBytes(&result.memory_saved));
        hasher.update(std.mem.asBytes(&result.performance_improvement));

        return hasher.final();
    }

    fn calculateDependenciesHash(self: *Self, table: *OptimizedDispatchTable) u64 {
        _ = self;
        _ = table;

        // In a real implementation, this would hash:
        // - Module dependencies
        // - Type system state
        // - Compiler version
        // - Build configuration

        return 0x1234567890ABCDEF; // Placeholder
    }

    fn hashString(self: *Self, s: []const u8) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(s);
        return hasher.final();
    }

    fn hashTypeSignature(self: *Self, types: []const TypeId) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.sliceAsBytes(types));
        return hasher.final();
    }

    fn loadCacheIndex(self: *Self) !void {
        const index_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_directory, "cache_index.json" });
        defer self.allocator.free(index_path);

        // Load cache index from JSON file (simplified implementation)
        // In a real implementation, this would parse JSON and populate the cache index
    }

    fn saveCacheIndex(self: *Self) !void {
        const index_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_directory, "cache_index.json" });
        defer self.allocator.free(index_path);

        // Save cache index to JSON file (simplified implementation)
        // In a real implementation, this would serialize the cache index to JSON
    }

    fn cleanupBySize(self: *Self, max_size_bytes: usize) !void {
        // Collect entries sorted by last access time (LRU)
        var entries: ArrayList(struct { key: CacheIndex.CacheKey, entry: *CacheIndex.CacheEntry }) = .empty;
        defer entries.deinit();

        var iter = self.cache_index.entries.iterator();
        while (iter.next()) |entry| {
            try entries.append(.{ .key = entry.key_ptr.*, .entry = entry.value_ptr });
        }

        // Sort by last access time (oldest first)
        const Context = struct {
            pub fn lessThan(context: @This(), a: @TypeOf(entries.items[0]), b: @TypeOf(entries.items[0])) bool {
                _ = context;
                return a.entry.last_access_time < b.entry.last_access_time;
            }
        };

        std.mem.sort(@TypeOf(entries.items[0]), entries.items, Context{}, Context.lessThan);

        // Remove entries until under size limit
        var current_size: usize = 0;

        // Calculate current size
        for (entries.items) |entry| {
            current_size += entry.entry.file_size;
        }

        // Remove oldest entries
        for (entries.items) |entry| {
            if (current_size <= max_size_bytes) break;

            // Delete file
            std.fs.cwd().deleteFile(entry.entry.file_path) catch {};

            // Remove from index
            self.cache_index.remove(self.allocator, entry.key);

            current_size -= entry.entry.file_size;
        }
    }
};

// Tests

test "DispatchTableSerializer basic functionality" {
    const allocator = testing.allocator;

    // Create temporary cache directory
    const cache_dir = "test_cache";
    std.fs.cwd().makeDir(cache_dir) catch {};
    defer std.fs.cwd().deleteTree(cache_dir) catch {};

    var serializer = try DispatchTableSerializer.init(allocator, cache_dir);
    defer serializer.deinit();

    // Create test dispatch table
    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});

    var table = try OptimizedDispatchTable.init(allocator, "test_func", &[_]TypeId{int_type});
    defer table.deinit();

    // Test serialization
    const cache_path = try serializer.serializeTable(&table, null);
    defer allocator.free(cache_path);

    try testing.expect(cache_path.len > 0);

    // Test cache check
    const is_cached = try serializer.isCached(&table);
    try testing.expect(is_cached);

    // Test deserialization
    const cache_key = try serializer.calculateCacheKey(&table);
    const deserialized_table = try serializer.deserializeTable(cache_key, &type_registry);

    if (deserialized_table) |dt| {
        defer dt.deinit();
        try testing.expectEqualStrings("test_func", dt.signature_name);
    }

    // Test statistics
    const stats = serializer.getStats();
    try testing.expect(stats.tables_serialized > 0);
}

test "DispatchTableSerializer cache management" {
    const allocator = testing.allocator;

    const cache_dir = "test_cache_mgmt";
    std.fs.cwd().makeDir(cache_dir) catch {};
    defer std.fs.cwd().deleteTree(cache_dir) catch {};

    var serializer = try DispatchTableSerializer.init(allocator, cache_dir);
    defer serializer.deinit();

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});

    // Create multiple test tables
    var tables: [3]*OptimizedDispatchTable = undefined;
    for (&tables, 0..) |*table, i| {
        const name = try std.fmt.allocPrint(allocator, "test_func_{}", .{i});
        defer allocator.free(name);

        table.* = try OptimizedDispatchTable.init(allocator, name, &[_]TypeId{int_type});
    }
    defer {
        for (tables) |table| {
            table.deinit();
        }
    }

    // Serialize all tables
    for (tables) |table| {
        const cache_path = try serializer.serializeTable(table, null);
        allocator.free(cache_path);
    }

    // Test cache cleanup
    try serializer.cleanupCache(0, 0); // Remove all entries

    // Verify cache is empty
    for (tables) |table| {
        const is_cached = try serializer.isCached(table);
        try testing.expect(!is_cached);
    }
}

test "DispatchTableSerializer format versioning" {
    const allocator = testing.allocator;

    const cache_dir = "test_cache_version";
    std.fs.cwd().makeDir(cache_dir) catch {};
    defer std.fs.cwd().deleteTree(cache_dir) catch {};

    var serializer = try DispatchTableSerializer.init(allocator, cache_dir);
    defer serializer.deinit();

    // Test format version compatibility
    try testing.expectEqual(DispatchTableSerializer.CURRENT_FORMAT_VERSION, serializer.format_version);

    // Test magic number
    try testing.expectEqual(@as(u32, 0x4A414E55), DispatchTableSerializer.CACHE_FILE_MAGIC);
}
