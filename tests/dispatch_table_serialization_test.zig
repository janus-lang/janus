// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const TypeRegistry = @import("../compiler/libjanus/type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("../compiler/libjanus/signature_analyzer.zig").SignatureAnalyzer;
const OptimizedDispatchTable = @import("../compiler/libjanus/optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchTableOptimizer = @import("../compiler/libjanus/dispatch_table_optimizer.zig").DispatchTableOptimizer;
const DispatchTableSerializer = @import("../compiler/libjanus/dispatch_table_serialization.zig").DispatchTableSerializer;

/// Comprehensive test suite for dispatch table serialization
const SerializationTestSuite = struct {
    allocator: Allocator,
    type_registry: *TypeRegistry,
    serializer: *DispatchTableSerializer,
    cache_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const cache_dir = "test_serialization_cache";
        std.fs.cwd().makeDir(cache_dir) catch {};

        var type_registry = try allocator.create(TypeRegistry);
        type_registry.* = try TypeRegistry.init(allocator);

        var serializer = try allocator.create(DispatchTableSerializer);
        serializer.* = try DispatchTableSerializer.init(allocator, cache_dir);

        return Self{
            .allocator = allocator,
            .type_registry = type_registry,
            .serializer = serializer,
            .cache_dir = cache_dir,
        };
    }

    pub fn deinit(self: *Self) void {
        self.serializer.deinit();
        self.allocator.destroy(self.serializer);

        self.type_registry.deinit();
        self.allocator.destroy(self.type_registry);

        std.fs.cwd().deleteTree(self.cache_dir) catch {};
    }

    /// Test basic serialization and deserialization
    pub fn testBasicSerialization(self: *Self) !void {
        // Create test types
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});

        // Create dispatch table
        var table = try OptimizedDispatchTable.init(self.allocator, "test_func", &[_]TypeId{ int_type, float_type });
        defer table.deinit();

        // Add test implementation
        const impl = try self.createTestImplementation("test_func", "test_module", 1, &[_]TypeId{ int_type, float_type }, int_type);
        defer self.freeTestImplementation(impl);

        try table.addImplementation(impl);

        // Serialize table
        const cache_path = try self.serializer.serializeTable(&table, null);
        defer self.allocator.free(cache_path);

        // Verify cache file exists
        const file = std.fs.cwd().openFile(cache_path, .{}) catch |err| {
            std.debug.print("Failed to open cache file: {}\n", .{err});
            return err;
        };
        file.close();

        // Test cache lookup
        const is_cached = try self.serializer.isCached(&table);
        try testing.expect(is_cached);

        // Deserialize table
        const cache_key = try self.serializer.calculateCacheKey(&table);
        const deserialized_table = try self.serializer.deserializeTable(cache_key, self.type_registry);

        if (deserialized_table) |dt| {
            defer dt.deinit();

            // Verify basic properties
            try testing.expectEqualStrings("test_func", dt.signature_name);
            try testing.expectEqual(@as(u32, 1), dt.entry_count);
            try testing.expectEqual(int_type, dt.type_signature[0]);
            try testing.expectEqual(float_type, dt.type_signature[1]);
        } else {
            return error.DeserializationFailed;
        }
    }

    /// Test serialization with optimization results
    pub fn testOptimizedSerialization(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        var table = try OptimizedDispatchTable.init(self.allocator, "optimized_func", &[_]TypeId{int_type});
        defer table.deinit();

        // Add multiple implementations to trigger optimization
        for (0..5) |i| {
            const impl = try self.createTestImplementation("optimized_func", "test_module", @intCast(i + 1), &[_]TypeId{int_type}, int_type);
            defer self.freeTestImplementation(impl);
            try table.addImplementation(impl);
        }

        // Create optimization result
        const optimization_result = DispatchTableOptimizer.OptimizationResult{
            .original_table = &table,
            .optimized_table = null,
            .compressed_table = null,
            .shared_table = null,
            .advanced_compressed_table = null,
            .optimization_applied = .compression,
            .memory_saved = 1024,
            .performance_improvement = 15.5,
            .compression_metrics = null,
        };

        // Serialize with optimization result
        const cache_path = try self.serializer.serializeTable(&table, optimization_result);
        defer self.allocator.free(cache_path);

        // Verify serialization statistics
        const stats = self.serializer.getStats();
        try testing.expect(stats.tables_serialized > 0);
        try testing.expect(stats.total_serialized_bytes > 0);
    }

    /// Test cache invalidation and cleanup
    pub fn testCacheManagement(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        // Create multiple tables for cache management testing
        var tables: [3]*OptimizedDispatchTable = undefined;
        for (&tables, 0..) |*table, i| {
            const name = try std.fmt.allocPrint(self.allocator, "cache_test_func_{}", .{i});
            defer self.allocator.free(name);

            table.* = try OptimizedDispatchTable.init(self.allocator, name, &[_]TypeId{int_type});

            const impl = try self.createTestImplementation(name, "test_module", @intCast(i + 1), &[_]TypeId{int_type}, int_type);
            defer self.freeTestImplementation(impl);
            try table.*.addImplementation(impl);
        }
        defer {
            for (tables) |table| {
                table.deinit();
            }
        }

        // Serialize all tables
        var cache_paths: ArrayList([]const u8) = .empty;
        defer {
            for (cache_paths.items) |path| {
                self.allocator.free(path);
            }
            cache_paths.deinit();
        }

        for (tables) |table| {
            const cache_path = try self.serializer.serializeTable(table, null);
            try cache_paths.append(cache_path);
        }

        // Verify all tables are cached
        for (tables) |table| {
            const is_cached = try self.serializer.isCached(table);
            try testing.expect(is_cached);
        }

        // Test individual cache invalidation
        try self.serializer.invalidateCache(tables[0]);

        const is_invalidated = try self.serializer.isCached(tables[0]);
        try testing.expect(!is_invalidated);

        // Other tables should still be cached
        for (tables[1..]) |table| {
            const is_still_cached = try self.serializer.isCached(table);
            try testing.expect(is_still_cached);
        }

        // Test cache cleanup (remove all)
        try self.serializer.cleanupCache(0, 0); // Max age 0, max size 0

        // All remaining tables should be uncached
        for (tables[1..]) |table| {
            const is_cleaned = try self.serializer.isCached(table);
            try testing.expect(!is_cleaned);
        }
    }

    /// Test cache size limits and LRU eviction
    pub fn testCacheSizeLimits(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        // Create tables with different access patterns
        var tables: [5]*OptimizedDispatchTable = undefined;
        for (&tables, 0..) |*table, i| {
            const name = try std.fmt.allocPrint(self.allocator, "size_test_func_{}", .{i});
            defer self.allocator.free(name);

            table.* = try OptimizedDispatchTable.init(self.allocator, name, &[_]TypeId{int_type});

            // Add multiple implementations to increase table size
            for (0..10) |j| {
                const impl = try self.createTestImplementation(name, "test_module", @intCast(j + 1), &[_]TypeId{int_type}, int_type);
                defer self.freeTestImplementation(impl);
                try table.*.addImplementation(impl);
            }
        }
        defer {
            for (tables) |table| {
                table.deinit();
            }
        }

        // Serialize all tables
        for (tables) |table| {
            const cache_path = try self.serializer.serializeTable(table, null);
            self.allocator.free(cache_path);
        }

        // Simulate access pattern (access some tables more than others)
        for (0..3) |_| {
            for (tables[0..2]) |table| {
                const cache_key = try self.serializer.calculateCacheKey(table);
                _ = try self.serializer.deserializeTable(cache_key, self.type_registry);
            }
        }

        // Test size-based cleanup with very small limit
        try self.serializer.cleanupCache(std.math.maxInt(u64), 1024); // 1KB limit

        // Some tables should be evicted (LRU)
        var cached_count: u32 = 0;
        for (tables) |table| {
            if (try self.serializer.isCached(table)) {
                cached_count += 1;
            }
        }

        // Should have fewer cached tables due to size limit
        try testing.expect(cached_count < tables.len);
    }

    /// Test format version compatibility
    pub fn testVersionCompatibility(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        var table = try OptimizedDispatchTable.init(self.allocator, "version_test", &[_]TypeId{int_type});
        defer table.deinit();

        const impl = try self.createTestImplementation("version_test", "test_module", 1, &[_]TypeId{int_type}, int_type);
        defer self.freeTestImplementation(impl);
        try table.addImplementation(impl);

        // Serialize with current version
        const cache_path = try self.serializer.serializeTable(&table, null);
        defer self.allocator.free(cache_path);

        // Verify format version is correct
        try testing.expectEqual(DispatchTableSerializer.CURRENT_FORMAT_VERSION, self.serializer.format_version);

        // Read cache file and verify magic number and version
        const file_data = try std.fs.cwd().readFileAlloc(self.allocator, cache_path, std.math.maxInt(usize));
        defer self.allocator.free(file_data);

        if (file_data.len >= @sizeOf(DispatchTableSerializer.SerializedDispatchTable)) {
            const header = std.mem.bytesToValue(DispatchTableSerializer.SerializedDispatchTable, file_data[0..@sizeOf(DispatchTableSerializer.SerializedDispatchTable)]);

            try testing.expectEqual(DispatchTableSerializer.CACHE_FILE_MAGIC, header.magic);
            try testing.expectEqual(DispatchTableSerializer.CURRENT_FORMAT_VERSION, header.format_version);
        }
    }

    /// Test checksum validation and corruption detection
    pub fn testChecksumValidation(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        var table = try OptimizedDispatchTable.init(self.allocator, "checksum_test", &[_]TypeId{int_type});
        defer table.deinit();

        const impl = try self.createTestImplementation("checksum_test", "test_module", 1, &[_]TypeId{int_type}, int_type);
        defer self.freeTestImplementation(impl);
        try table.addImplementation(impl);

        // Serialize table
        const cache_path = try self.serializer.serializeTable(&table, null);
        defer self.allocator.free(cache_path);

        // Read and corrupt the cache file
        var file_data = try std.fs.cwd().readFileAlloc(self.allocator, cache_path, std.math.maxInt(usize));
        defer self.allocator.free(file_data);

        // Corrupt some data (change a byte in the middle)
        if (file_data.len > 100) {
            file_data[50] = ~file_data[50];
        }

        // Write corrupted data back
        const corrupted_file = try std.fs.cwd().createFile(cache_path, .{});
        defer corrupted_file.close();
        try corrupted_file.writeAll(file_data);

        // Attempt to deserialize corrupted file
        const cache_key = try self.serializer.calculateCacheKey(&table);
        const result = self.serializer.deserializeTable(cache_key, self.type_registry);

        // Should fail due to checksum mismatch
        try testing.expectError(error.CorruptedCacheFile, result);
    }

    /// Test performance characteristics
    pub fn testPerformanceCharacteristics(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});
        const string_type = try self.type_registry.registerType("string", .primitive, &.{});

        // Create large dispatch table
        var large_table = try OptimizedDispatchTable.init(self.allocator, "perf_test", &[_]TypeId{ int_type, float_type, string_type });
        defer large_table.deinit();

        // Add many implementations
        for (0..100) |i| {
            const impl = try self.createTestImplementation("perf_test", "test_module", @intCast(i + 1), &[_]TypeId{ int_type, float_type, string_type }, int_type);
            defer self.freeTestImplementation(impl);
            try large_table.addImplementation(impl);
        }

        // Reset statistics
        self.serializer.resetStats();

        // Measure serialization performance
        const serialize_start = std.time.nanoTimestamp();
        const cache_path = try self.serializer.serializeTable(&large_table, null);
        const serialize_end = std.time.nanoTimestamp();
        defer self.allocator.free(cache_path);

        const serialize_time = serialize_end - serialize_start;

        // Measure deserialization performance
        const cache_key = try self.serializer.calculateCacheKey(&large_table);

        const deserialize_start = std.time.nanoTimestamp();
        const deserialized_table = try self.serializer.deserializeTable(cache_key, self.type_registry);
        const deserialize_end = std.time.nanoTimestamp();

        if (deserialized_table) |dt| {
            defer dt.deinit();
        }

        const deserialize_time = deserialize_end - deserialize_start;

        // Verify performance is reasonable
        const max_serialize_time = 10 * std.time.ns_per_ms; // 10ms max
        const max_deserialize_time = 5 * std.time.ns_per_ms; // 5ms max

        try testing.expect(serialize_time < max_serialize_time);
        try testing.expect(deserialize_time < max_deserialize_time);

        // Check statistics
        const stats = self.serializer.getStats();
        try testing.expect(stats.tables_serialized > 0);
        try testing.expect(stats.tables_deserialized > 0);
        try testing.expect(stats.total_serialized_bytes > 0);
        try testing.expect(stats.total_deserialized_bytes > 0);
    }

    /// Test concurrent access patterns
    pub fn testConcurrentAccess(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        // Create multiple tables for concurrent testing
        var tables: [10]*OptimizedDispatchTable = undefined;
        for (&tables, 0..) |*table, i| {
            const name = try std.fmt.allocPrint(self.allocator, "concurrent_test_{}", .{i});
            defer self.allocator.free(name);

            table.* = try OptimizedDispatchTable.init(self.allocator, name, &[_]TypeId{int_type});

            const impl = try self.createTestImplementation(name, "test_module", @intCast(i + 1), &[_]TypeId{int_type}, int_type);
            defer self.freeTestImplementation(impl);
            try table.*.addImplementation(impl);
        }
        defer {
            for (tables) |table| {
                table.deinit();
            }
        }

        // Serialize all tables (simulating concurrent builds)
        var cache_paths: ArrayList([]const u8) = .empty;
        defer {
            for (cache_paths.items) |path| {
                self.allocator.free(path);
            }
            cache_paths.deinit();
        }

        for (tables) |table| {
            const cache_path = try self.serializer.serializeTable(table, null);
            try cache_paths.append(cache_path);
        }

        // Verify all tables can be deserialized
        for (tables) |table| {
            const cache_key = try self.serializer.calculateCacheKey(table);
            const deserialized = try self.serializer.deserializeTable(cache_key, self.type_registry);

            if (deserialized) |dt| {
                defer dt.deinit();
                try testing.expect(dt.entry_count > 0);
            }
        }
    }

    // Helper methods

    fn createTestImplementation(self: *Self, name: []const u8, module: []const u8, id: u32, param_types: []const TypeId, return_type: TypeId) !*SignatureAnalyzer.Implementation {
        const impl = try self.allocator.create(SignatureAnalyzer.Implementation);

        impl.* = SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{
                .name = try self.allocator.dupe(u8, name),
                .module = try self.allocator.dupe(u8, module),
                .id = id,
            },
            .param_type_ids = try self.allocator.dupe(TypeId, param_types),
            .return_type_id = return_type,
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 100,
        };

        return impl;
    }

    fn freeTestImplementation(self: *Self, impl: *SignatureAnalyzer.Implementation) void {
        self.allocator.free(impl.function_id.name);
        self.allocator.free(impl.function_id.module);
        self.allocator.free(impl.param_type_ids);
        self.allocator.destroy(impl);
    }
};

// Test runner

test "DispatchTableSerializer comprehensive test suite" {
    const allocator = testing.allocator;

    var test_suite = try SerializationTestSuite.init(allocator);
    defer test_suite.deinit();

    // Run all tests
    try test_suite.testBasicSerialization();
    try test_suite.testOptimizedSerialization();
    try test_suite.testCacheManagement();
    try test_suite.testCacheSizeLimits();
    try test_suite.testVersionCompatibility();
    try test_suite.testChecksumValidation();
    try test_suite.testPerformanceCharacteristics();
    try test_suite.testConcurrentAccess();
}

// Individual test cases for specific scenarios

test "SerializedDispatchTable size calculation" {
    const signature_name = "test_function";
    const type_signature = [_]TypeId{ 1, 2, 3 };
    const entry_count = 5;
    const has_decision_tree = true;
    const compression_data_len = 1024;

    const calculated_size = DispatchTableSerializer.SerializedDispatchTable.calculateSize(
        signature_name,
        &type_signature,
        entry_count,
        has_decision_tree,
        compression_data_len,
    );

    const expected_size = @sizeOf(DispatchTableSerializer.SerializedDispatchTable) +
        signature_name.len +
        type_signature.len * @sizeOf(TypeId) +
        entry_count * @sizeOf(DispatchTableSerializer.SerializedDispatchEntry) +
        @sizeOf(DispatchTableSerializer.SerializedDecisionTree) +
        compression_data_len;

    try testing.expectEqual(expected_size, calculated_size);
}

test "CacheIndex key hashing and equality" {
    const key1 = DispatchTableSerializer.CacheIndex.CacheKey{
        .signature_hash = 0x1234567890ABCDEF,
        .type_signature_hash = 0xFEDCBA0987654321,
        .dependencies_hash = 0x1111222233334444,
    };

    const key2 = DispatchTableSerializer.CacheIndex.CacheKey{
        .signature_hash = 0x1234567890ABCDEF,
        .type_signature_hash = 0xFEDCBA0987654321,
        .dependencies_hash = 0x1111222233334444,
    };

    const key3 = DispatchTableSerializer.CacheIndex.CacheKey{
        .signature_hash = 0x1234567890ABCDEF,
        .type_signature_hash = 0xFEDCBA0987654321,
        .dependencies_hash = 0x5555666677778888, // Different dependencies
    };

    // Test equality
    try testing.expect(key1.eql(key2));
    try testing.expect(!key1.eql(key3));

    // Test hash consistency
    try testing.expectEqual(key1.hash(), key2.hash());
    try testing.expect(key1.hash() != key3.hash());
}

test "SerializationStats calculations" {
    var stats = DispatchTableSerializer.SerializationStats{
        .tables_serialized = 10,
        .tables_deserialized = 8,
        .cache_hits = 15,
        .cache_misses = 5,
        .total_serialized_bytes = 10000,
        .total_deserialized_bytes = 8000,
        .compression_ratio = 0.8,
        .serialization_time_ns = 1000000, // 1ms total
        .deserialization_time_ns = 800000, // 0.8ms total
        .cache_lookup_time_ns = 50000, // 0.05ms total
    };

    // Test average calculations
    try testing.expectEqual(@as(f64, 100000.0), stats.getAverageSerializationTime()); // 100μs per table
    try testing.expectEqual(@as(f64, 100000.0), stats.getAverageDeserializationTime()); // 100μs per table

    // Test cache hit ratio
    try testing.expectEqual(@as(f64, 0.75), stats.getCacheHitRatio()); // 15/(15+5) = 0.75
}

test "CacheEntry validation" {
    const current_time = @as(u64, @intCast(std.time.nanoTimestamp()));
    const one_hour_ago = current_time - (60 * 60 * std.time.ns_per_s);
    const one_day_ago = current_time - (24 * 60 * 60 * std.time.ns_per_s);

    var entry = DispatchTableSerializer.CacheIndex.CacheEntry{
        .file_path = "test.cache",
        .file_size = 1024,
        .creation_time = one_hour_ago,
        .last_access_time = one_hour_ago,
        .access_count = 0,
        .format_version = 1,
        .original_table_hash = 0x1234,
        .optimization_config_hash = 0x5678,
    };

    // Test validity with different max ages
    try testing.expect(entry.isValid(current_time, 2 * 60 * 60)); // 2 hours max age - should be valid
    try testing.expect(!entry.isValid(current_time, 30 * 60)); // 30 minutes max age - should be invalid

    // Test access update
    entry.updateAccess(current_time);
    try testing.expectEqual(current_time, entry.last_access_time);
    try testing.expectEqual(@as(u32, 1), entry.access_count);
}
