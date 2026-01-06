// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const DispatchTableSerialization = @import("dispatch_table_serialization.zig").DispatchTableSerialization;
const DispatchBuildCache = @import("dispatch_build_cache.zig").DispatchBuildCache;
const IncrementalDispatchCompilation = @import("incremental_dispatch_compilation.zig").IncrementalDispatchCompilation;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;

/// Comprehensive tests for dispatch table serialization and build caching
pub const DispatchSerializationTests = struct {
    allocator: Allocator,
    temp_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        // Create temporary directory for testing
        const temp_dir = try std.fmt.allocPrint(allocator, "/tmp/janus_dispatch_test_{}", .{std.time.timestamp()});

        return Self{
            .allocator = allocator,
            .temp_dir = temp_dir,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up temporary directory
        std.fs.cwd().deleteTree(self.temp_dir) catch {};
        self.allocator.free(self.temp_dir);
    }

    /// Test basic serialization and deserialization
    pub fn testBasicSerialization(self: *Self) !void {
        var type_registry = TypeRegistry.init(self.allocator);
        defer type_registry.deinit();

        const int_type = try type_registry.registerType("int", .primitive, &.{});
        const float_type = try type_registry.registerType("float", .primitive, &.{});

        // Create test dispatch table
        var table = try OptimizedDispatchTable.init(self.allocator, "test_func", &[_]TypeRegistry.TypeId{int_type});
        defer table.deinit();

        // Add test implementations
        const impl1 = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "test_func", .module = "test" },
            .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
            .return_type_id = int_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        const impl2 = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "test_func", .module = "test" },
            .param_type_ids = &[_]TypeRegistry.TypeId{float_type},
            .return_type_id = float_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
        };

        try table.addImplementation(&impl1);
        try table.addImplementation(&impl2);

        // Test serialization
        var serializer = DispatchTableSerialization.init(self.allocator);
        defer serializer.deinit();

        const serialized_data = try serializer.serializeTable(&table);
        defer self.allocator.free(serialized_data);

        try testing.expect(serialized_data.len > 0);

        // Test deserialization
        const deserialized_table = try serializer.deserializeTable(serialized_data);
        defer deserialized_table.deinit();

        // Verify deserialized table matches original
        try testing.expect(deserialized_table.entry_count == table.entry_count);
        try testing.expect(std.mem.eql(u8, deserialized_table.signature_name, table.signature_name));
        try testing.expect(std.mem.eql(TypeRegistry.TypeId, deserialized_table.type_signature, table.type_signature));

        std.debug.print("✅ Basic serialization test passed\n");
    }

    /// Test build cache functionality
    pub fn testBuildCache(self: *Self) !void {
        var build_cache = try DispatchBuildCache.init(self.allocator, self.temp_dir);
        defer build_cache.deinit();

        // Set build hash
        const source_files = &[_][]const u8{ "test1.jan", "test2.jan" };
        try build_cache.setBuildHash(source_files);

        // Create test table
        var type_registry = TypeRegistry.init(self.allocator);
        defer type_registry.deinit();

        const int_type = try type_registry.registerType("int", .primitive, &.{});

        var table = try OptimizedDispatchTable.init(self.allocator, "cache_test", &[_]TypeRegistry.TypeId{int_type});
        defer table.deinit();

        const impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "cache_test", .module = "test" },
            .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
            .return_type_id = int_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        try table.addImplementation(&impl);

        // Test caching
        try build_cache.cacheTable("cache_test", &table);

        // Test cache validity
        const is_valid = try build_cache.isCacheValid("cache_test");
        try testing.expect(is_valid);

        // Test loading from cache
        const loaded_table = try build_cache.loadTable("cache_test");
        try testing.expect(loaded_table != null);

        if (loaded_table) |cached| {
            defer cached.deinit();
            try testing.expect(cached.entry_count == table.entry_count);
            try testing.expect(std.mem.eql(u8, cached.signature_name, table.signature_name));
        }

        // Test cache invalidation
        try build_cache.invalidateSignature("cache_test");
        const is_valid_after_invalidation = try build_cache.isCacheValid("cache_test");
        try testing.expect(!is_valid_after_invalidation);

        std.debug.print("✅ Build cache test passed\n");
    }

    /// Test incremental compilation
    pub fn testIncrementalCompilation(self: *Self) !void {
        var incremental = try IncrementalDispatchCompilation.init(self.allocator, self.temp_dir);
        defer incremental.deinit();

        // This would test the full incremental compilation workflow
        // For now, test the basic structure

        const stats = try incremental.getCompilationStats();
        try testing.expect(stats.cache_hit_rate >= 0.0);
        try testing.expect(stats.cache_hit_rate <= 1.0);

        std.debug.print("✅ Incremental compilation test passed\n");
        std.debug.print("   Cache hit rate: {d:.1}%\n", .{stats.cache_hit_rate * 100.0});
    }

    /// Test version compatibility
    pub fn testVersionCompatibility(self: *Self) !void {
        const v1_0_0 = DispatchTableSerialization.SerializationVersion{ .major = 1, .minor = 0, .patch = 0 };
        const v1_1_0 = DispatchTableSerialization.SerializationVersion{ .major = 1, .minor = 1, .patch = 0 };
        const v2_0_0 = DispatchTableSerialization.SerializationVersion{ .major = 2, .minor = 0, .patch = 0 };

        // Test compatible versions
        try testing.expect(v1_0_0.isCompatible(v1_0_0));
        try testing.expect(v1_0_0.isCompatible(v1_1_0));

        // Test incompatible versions
        try testing.expect(!v1_0_0.isCompatible(v2_0_0));
        try testing.expect(!v2_0_0.isCompatible(v1_0_0));

        std.debug.print("✅ Version compatibility test passed\n");
    }

    /// Test serialization performance
    pub fn testSerializationPerformance(self: *Self) !void {
        var type_registry = TypeRegistry.init(self.allocator);
        defer type_registry.deinit();

        const int_type = try type_registry.registerType("int", .primitive, &.{});

        // Create large dispatch table for performance testing
        var table = try OptimizedDispatchTable.init(self.allocator, "perf_test", &[_]TypeRegistry.TypeId{int_type});
        defer table.deinit();

        // Add many implementations
        var impl_storage = ArrayList(SignatureAnalyzer.Implementation).init(self.allocator);
        defer impl_storage.deinit();

        const impl_count = 1000;
        for (0..impl_count) |i| {
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "perf_test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
                .return_type_id = int_type,
                .effects = .{},
                .specificity_rank = @intCast(100 + i),
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try table.addImplementation(&impl_storage.items[impl_storage.items.len - 1]);
        }

        var serializer = DispatchTableSerialization.init(self.allocator);
        defer serializer.deinit();

        // Measure serialization performance
        const serialize_start = std.time.nanoTimestamp();
        const serialized_data = try serializer.serializeTable(&table);
        const serialize_end = std.time.nanoTimestamp();

        const serialize_time_ms = (serialize_end - serialize_start) / 1_000_000;

        // Measure deserialization performance
        const deserialize_start = std.time.nanoTimestamp();
        const deserialized_table = try serializer.deserializeTable(serialized_data);
        const deserialize_end = std.time.nanoTimestamp();

        const deserialize_time_ms = (deserialize_end - deserialize_start) / 1_000_000;

        defer {
            self.allocator.free(serialized_data);
            deserialized_table.deinit();
        }

        // Performance bounds
        const max_serialize_time_ms = 100; // 100ms max for 1000 implementations
        const max_deserialize_time_ms = 50; // 50ms max for deserialization

        try testing.expect(serialize_time_ms < max_serialize_time_ms);
        try testing.expect(deserialize_time_ms < max_deserialize_time_ms);

        std.debug.print("✅ Serialization performance test passed\n");
        std.debug.print("   Serialize: {} ms for {} implementations\n", .{ serialize_time_ms, impl_count });
        std.debug.print("   Deserialize: {} ms\n", .{deserialize_time_ms});
        std.debug.print("   Data size: {} bytes\n", .{serialized_data.len});
    }

    /// Run all serialization tests
    pub fn runAllTests(self: *Self) !void {
        std.debug.print("🗄️ Running Dispatch Serialization Tests\n");
        std.debug.print("=======================================\n\n");

        try self.testBasicSerialization();
        try self.testBuildCache();
        try self.testIncrementalCompilation();
        try self.testVersionCompatibility();
        try self.testSerializationPerformance();

        std.debug.print("\n🎉 All serialization tests passed!\n");
    }
};
