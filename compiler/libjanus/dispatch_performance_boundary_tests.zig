// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;
const ModuleDispatcher = @import("module_dispatch.zig").ModuleDispatcher;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchTableOptimizer = @import("dispatch_table_optimizer.zig").DispatchTableOptimizer;

/// Performance boundary tests ensuring dispatch overhead remains within acceptable limits
/// These tests verify that the dispatch system meets performance requirements
pub const DispatchPerformanceBoundaryTests = struct {
    allocator: Allocator,
    type_registry: TypeRegistry,
    signature_analyzer: SignatureAnalyzer,
    specificity_analyzer: SpecificityAnalyzer,
    module_dispatcher: ModuleDispatcher,
    dispatch_optimizer: DispatchTableOptimizer,

    const Self = @This();

    // Performance boundaries (in nanoseconds)
    const STATIC_DISPATCH_BOUND_NS = 50; // Static dispatch should be < 50ns
    const SMALL_TABLE_BOUND_NS = 500; // Small tables (< 10 entries) should be < 500ns
    const MEDIUM_TABLE_BOUND_NS = 1000; // Medium tables (< 100 entries) should be < 1μs
    const LARGE_TABLE_BOUND_NS = 5000; // Large tables (< 1000 entries) should be < 5μs
    const COMPRESSION_OVERHEAD_BOUND = 1.2; // Compressed lookup should be < 1.2x uncompressed

    pub fn init(allocator: Allocator) !Self {
        var type_registry = TypeRegistry.init(allocator);
        var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
        var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);
        var module_dispatcher = ModuleDispatcher.init(
            allocator,
            &type_registry,
            &signature_analyzer,
            &specificity_analyzer,
        );
        var dispatch_optimizer = DispatchTableOptimizer.init(allocator);

        return Self{
            .allocator = allocator,
            .type_registry = type_registry,
            .signature_analyzer = signature_analyzer,
            .specificity_analyzer = specificity_analyzer,
            .module_dispatcher = module_dispatcher,
            .dispatch_optimizer = dispatch_optimizer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.dispatch_optimizer.deinit();
        self.module_dispatcher.deinit();
        self.specificity_analyzer.deinit();
        self.signature_analyzer.deinit();
        self.type_registry.deinit();
    }

    /// Test static dispatch performance (should be zero overhead)
    pub fn testStaticDispatchPerformance(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        // Create single implementation (static dispatch case)
        const add_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "add", .module = "math" },
            .param_type_ids = &[_]TypeRegistry.TypeId{ int_type, int_type },
            .return_type_id = int_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        const implementations = &[_]*const SignatureAnalyzer.Implementation{&add_impl};
        const test_args = &[_]TypeRegistry.TypeId{ int_type, int_type };

        // Warm up
        for (0..1000) |_| {
            _ = try self.specificity_analyzer.findMostSpecific(implementations, test_args);
        }

        // Measure performance
        const iterations = 100_000;
        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations, test_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => try testing.expect(false),
            }
        }

        const end_time = std.time.nanoTimestamp();
        const total_time_ns = end_time - start_time;
        const avg_time_ns = total_time_ns / iterations;

        std.debug.print("Static dispatch performance: {} ns average\n", .{avg_time_ns});

        // Verify static dispatch is within bounds
        try testing.expect(avg_time_ns < STATIC_DISPATCH_BOUND_NS);
        std.debug.print("✅ Static dispatch within {} ns bound\n", .{STATIC_DISPATCH_BOUND_NS});
    }

    /// Test small dispatch table performance
    pub fn testSmallTablePerformance(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});
        const string_type = try self.type_registry.registerType("string", .primitive, &.{});

        // Create small table (5 implementations)
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        const type_combinations = [_][2]TypeRegistry.TypeId{
            .{ int_type, int_type },
            .{ float_type, float_type },
            .{ string_type, string_type },
            .{ int_type, float_type },
            .{ float_type, string_type },
        };

        for (type_combinations, 0..) |combo, i| {
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "op", .module = "math" },
                .param_type_ids = &[_]TypeRegistry.TypeId{ combo[0], combo[1] },
                .return_type_id = combo[0],
                .effects = .{},
                .specificity_rank = @intCast(100 + i),
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        const test_args = &[_]TypeRegistry.TypeId{ int_type, int_type };

        // Warm up
        for (0..1000) |_| {
            _ = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
        }

        // Measure performance
        const iterations = 50_000;
        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => try testing.expect(false),
            }
        }

        const end_time = std.time.nanoTimestamp();
        const total_time_ns = end_time - start_time;
        const avg_time_ns = total_time_ns / iterations;

        std.debug.print("Small table performance: {} ns average ({} implementations)\n", .{ avg_time_ns, implementations.items.len });

        // Verify small table is within bounds
        try testing.expect(avg_time_ns < SMALL_TABLE_BOUND_NS);
        std.debug.print("✅ Small table within {} ns bound\n", .{SMALL_TABLE_BOUND_NS});
    }

    /// Test medium dispatch table performance
    pub fn testMediumTablePerformance(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        // Create medium table (50 implementations)
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        const medium_count = 50;
        for (0..medium_count) |i| {
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "medium_func", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
                .return_type_id = int_type,
                .effects = .{},
                .specificity_rank = @intCast(100 + i),
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        const test_args = &[_]TypeRegistry.TypeId{int_type};

        // Warm up
        for (0..1000) |_| {
            _ = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
        }

        // Measure performance
        const iterations = 20_000;
        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => try testing.expect(false),
            }
        }

        const end_time = std.time.nanoTimestamp();
        const total_time_ns = end_time - start_time;
        const avg_time_ns = total_time_ns / iterations;

        std.debug.print("Medium table performance: {} ns average ({} implementations)\n", .{ avg_time_ns, implementations.items.len });

        // Verify medium table is within bounds
        try testing.expect(avg_time_ns < MEDIUM_TABLE_BOUND_NS);
        std.debug.print("✅ Medium table within {} ns bound\n", .{MEDIUM_TABLE_BOUND_NS});
    }

    /// Test large dispatch table performance
    pub fn testLargeTablePerformance(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        // Create large table (500 implementations)
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        const large_count = 500;
        for (0..large_count) |i| {
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "large_func", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
                .return_type_id = int_type,
                .effects = .{},
                .specificity_rank = @intCast(100 + i),
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        const test_args = &[_]TypeRegistry.TypeId{int_type};

        // Warm up
        for (0..100) |_| {
            _ = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
        }

        // Measure performance
        const iterations = 5_000;
        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => try testing.expect(false),
            }
        }

        const end_time = std.time.nanoTimestamp();
        const total_time_ns = end_time - start_time;
        const avg_time_ns = total_time_ns / iterations;

        std.debug.print("Large table performance: {} ns average ({} implementations)\n", .{ avg_time_ns, implementations.items.len });

        // Verify large table is within bounds
        try testing.expect(avg_time_ns < LARGE_TABLE_BOUND_NS);
        std.debug.print("✅ Large table within {} ns bound\n", .{LARGE_TABLE_BOUND_NS});
    }

    /// Test compression overhead performance
    pub fn testCompressionOverheadPerformance(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});

        const math_module = try self.module_dispatcher.registerModule(
            "math",
            "/test/math.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        // Create implementations for compression testing
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        const compression_test_count = 20;
        for (0..compression_test_count) |i| {
            const param_type = if (i % 2 == 0) int_type else float_type;
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "compress_test", .module = "math" },
                .param_type_ids = &[_]TypeRegistry.TypeId{param_type},
                .return_type_id = param_type,
                .effects = .{},
                .specificity_rank = @intCast(100 + i),
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        try self.module_dispatcher.exportSignature(
            math_module,
            "compress_test",
            implementations.items,
            .public,
            null,
        );

        try self.module_dispatcher.loadModule(math_module);

        // Create compressed dispatch table
        const compressed_table = try self.module_dispatcher.createCompressedDispatchTable("compress_test");
        const test_args = &[_]TypeRegistry.TypeId{int_type};

        // Measure uncompressed performance (using specificity analyzer directly)
        const uncompressed_iterations = 10_000;
        const uncompressed_start = std.time.nanoTimestamp();

        for (0..uncompressed_iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => try testing.expect(false),
            }
        }

        const uncompressed_end = std.time.nanoTimestamp();
        const uncompressed_avg_ns = (uncompressed_end - uncompressed_start) / uncompressed_iterations;

        // Measure compressed performance
        const compressed_iterations = 10_000;
        const compressed_start = std.time.nanoTimestamp();

        for (0..compressed_iterations) |_| {
            const result = try compressed_table.compressedLookup(test_args);
            if (result) |impl| {
                std.mem.doNotOptimizeAway(impl);
            }
        }

        const compressed_end = std.time.nanoTimestamp();
        const compressed_avg_ns = (compressed_end - compressed_start) / compressed_iterations;

        const overhead_ratio = @as(f64, @floatFromInt(compressed_avg_ns)) / @as(f64, @floatFromInt(uncompressed_avg_ns));

        std.debug.print("Compression performance:\n");
        std.debug.print("  Uncompressed: {} ns average\n", .{uncompressed_avg_ns});
        std.debug.print("  Compressed: {} ns average\n", .{compressed_avg_ns});
        std.debug.print("  Overhead ratio: {d:.2}x\n", .{overhead_ratio});

        // Verify compression overhead is within bounds
        try testing.expect(overhead_ratio < COMPRESSION_OVERHEAD_BOUND);
        std.debug.print("✅ Compression overhead within {d:.1}x bound\n", .{COMPRESSION_OVERHEAD_BOUND});

        // Check compression statistics
        if (compressed_table.getCompressionStats()) |stats| {
            std.debug.print("  Compression ratio: {d:.1}%\n", .{stats.compression_ratio * 100.0});
            std.debug.print("  Memory saved: {} bytes\n", .{stats.memory_saved});
        }
    }

    /// Test scalability characteristics (O(1) vs O(log n) vs O(n))
    pub fn testScalabilityCharacteristics(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        // Test different table sizes to verify algorithmic complexity
        const table_sizes = [_]u32{ 10, 50, 100, 500, 1000 };
        var performance_results: ArrayList(ScalabilityResult) = .empty;
        defer performance_results.deinit();

        for (table_sizes) |size| {
            // Create table of specified size
            var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
            defer implementations.deinit();

            var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
            defer impl_storage.deinit();

            for (0..size) |i| {
                const impl = SignatureAnalyzer.Implementation{
                    .function_id = .{ .name = "scale_test", .module = "test" },
                    .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
                    .return_type_id = int_type,
                    .effects = .{},
                    .specificity_rank = @intCast(100 + i),
                    .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
                };
                try impl_storage.append(impl);
                try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
            }

            const test_args = &[_]TypeRegistry.TypeId{int_type};

            // Measure performance for this table size
            const iterations = 10_000;
            const start_time = std.time.nanoTimestamp();

            for (0..iterations) |_| {
                const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
                switch (result) {
                    .unique => |impl| {
                        std.mem.doNotOptimizeAway(impl);
                    },
                    else => try testing.expect(false),
                }
            }

            const end_time = std.time.nanoTimestamp();
            const avg_time_ns = (end_time - start_time) / iterations;

            try performance_results.append(ScalabilityResult{
                .table_size = size,
                .avg_time_ns = avg_time_ns,
            });

            std.debug.print("Scalability test: {} implementations -> {} ns\n", .{ size, avg_time_ns });
        }

        // Analyze scalability characteristics
        std.debug.print("\nScalability analysis:\n");
        for (performance_results.items, 0..) |result, i| {
            if (i > 0) {
                const prev_result = performance_results.items[i - 1];
                const size_ratio = @as(f64, @floatFromInt(result.table_size)) / @as(f64, @floatFromInt(prev_result.table_size));
                const time_ratio = @as(f64, @floatFromInt(result.avg_time_ns)) / @as(f64, @floatFromInt(prev_result.avg_time_ns));

                std.debug.print("  {}x size increase -> {d:.2}x time increase\n", .{ @as(u32, @intFromFloat(size_ratio)), time_ratio });

                // For good algorithmic complexity, time increase should be much less than size increase
                // O(1): time_ratio ≈ 1.0
                // O(log n): time_ratio ≈ log(size_ratio)
                // O(n): time_ratio ≈ size_ratio

                if (time_ratio > size_ratio * 0.8) {
                    std.debug.print("⚠️  Warning: Performance scaling appears linear (O(n))\n");
                } else if (time_ratio > std.math.log2(size_ratio) * 2.0) {
                    std.debug.print("⚠️  Warning: Performance scaling appears logarithmic (O(log n))\n");
                } else {
                    std.debug.print("✅ Good: Performance scaling appears constant (O(1))\n");
                }
            }
        }
    }

    /// Test memory efficiency boundaries
    pub fn testMemoryEfficiencyBounds(self: *Self) !void {
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});

        const math_module = try self.module_dispatcher.registerModule(
            "math",
            "/test/math.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        // Create implementations for memory testing
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        const memory_test_count = 100;
        for (0..memory_test_count) |i| {
            const param_type = if (i % 2 == 0) int_type else float_type;
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "memory_test", .module = "math" },
                .param_type_ids = &[_]TypeRegistry.TypeId{param_type},
                .return_type_id = param_type,
                .effects = .{},
                .specificity_rank = @intCast(100 + i),
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        try self.module_dispatcher.exportSignature(
            math_module,
            "memory_test",
            implementations.items,
            .public,
            null,
        );

        try self.module_dispatcher.loadModule(math_module);

        // Create dispatch table and measure memory usage
        const dispatch_table = try self.module_dispatcher.createCompressedDispatchTable("memory_test");

        const memory_stats = dispatch_table.getMemoryStats();
        std.debug.print("Memory efficiency test:\n");
        std.debug.print("  Total memory: {} bytes\n", .{memory_stats.total_bytes});
        std.debug.print("  Entry memory: {} bytes\n", .{memory_stats.entry_bytes});
        std.debug.print("  Cache lines used: {}\n", .{memory_stats.cache_lines_used});
        std.debug.print("  Cache efficiency: {d:.1}%\n", .{memory_stats.cache_efficiency * 100.0});

        // Memory efficiency bounds
        const bytes_per_implementation = memory_stats.total_bytes / memory_test_count;
        const max_bytes_per_impl = 128; // Should not exceed 128 bytes per implementation

        try testing.expect(bytes_per_implementation < max_bytes_per_impl);
        std.debug.print("✅ Memory efficiency: {} bytes per implementation (< {} bound)\n", .{ bytes_per_implementation, max_bytes_per_impl });

        // Cache efficiency should be reasonable
        try testing.expect(memory_stats.cache_efficiency > 0.5); // At least 50% cache efficient
        std.debug.print("✅ Cache efficiency: {d:.1}% (> 50% bound)\n", .{memory_stats.cache_efficiency * 100.0});

        // Test compression effectiveness
        if (dispatch_table.getCompressionStats()) |compression_stats| {
            std.debug.print("  Compression ratio: {d:.1}%\n", .{compression_stats.compression_ratio * 100.0});
            std.debug.print("  Memory saved: {} bytes\n", .{compression_stats.memory_saved});

            // Compression should provide some benefit for large tables
            if (memory_test_count > 50) {
                try testing.expect(compression_stats.compression_ratio < 0.9); // At least 10% compression
                std.debug.print("✅ Compression effective: {d:.1}% ratio\n", .{compression_stats.compression_ratio * 100.0});
            }
        }
    }

    const ScalabilityResult = struct {
        table_size: u32,
        avg_time_ns: u64,
    };

    /// Run all performance boundary tests
    pub fn runAllPerformanceTests(self: *Self) !void {
        std.debug.print("Running dispatch performance boundary tests...\n");

        std.debug.print("1. Testing static dispatch performance...\n");
        try self.testStaticDispatchPerformance();

        std.debug.print("2. Testing small table performance...\n");
        try self.testSmallTablePerformance();

        std.debug.print("3. Testing medium table performance...\n");
        try self.testMediumTablePerformance();

        std.debug.print("4. Testing large table performance...\n");
        try self.testLargeTablePerformance();

        std.debug.print("5. Testing compression overhead performance...\n");
        try self.testCompressionOverheadPerformance();

        std.debug.print("6. Testing scalability characteristics...\n");
        try self.testScalabilityCharacteristics();

        std.debug.print("7. Testing memory efficiency bounds...\n");
        try self.testMemoryEfficiencyBounds();

        std.debug.print("All performance boundary tests passed! ✅\n");
    }
};

// Test functions for zig test runner
test "dispatch performance boundaries - static dispatch" {
    var perf_tests = try DispatchPerformanceBoundaryTests.init(testing.allocator);
    defer perf_tests.deinit();

    try perf_tests.testStaticDispatchPerformance();
}

test "dispatch performance boundaries - small table" {
    var perf_tests = try DispatchPerformanceBoundaryTests.init(testing.allocator);
    defer perf_tests.deinit();

    try perf_tests.testSmallTablePerformance();
}

test "dispatch performance boundaries - medium table" {
    var perf_tests = try DispatchPerformanceBoundaryTests.init(testing.allocator);
    defer perf_tests.deinit();

    try perf_tests.testMediumTablePerformance();
}

test "dispatch performance boundaries - large table" {
    var perf_tests = try DispatchPerformanceBoundaryTests.init(testing.allocator);
    defer perf_tests.deinit();

    try perf_tests.testLargeTablePerformance();
}

test "dispatch performance boundaries - compression overhead" {
    var perf_tests = try DispatchPerformanceBoundaryTests.init(testing.allocator);
    defer perf_tests.deinit();

    try perf_tests.testCompressionOverheadPerformance();
}

test "dispatch performance boundaries - scalability" {
    var perf_tests = try DispatchPerformanceBoundaryTests.init(testing.allocator);
    defer perf_tests.deinit();

    try perf_tests.testScalabilityCharacteristics();
}

test "dispatch performance boundaries - memory efficiency" {
    var perf_tests = try DispatchPerformanceBoundaryTests.init(testing.allocator);
    defer perf_tests.deinit();

    try perf_tests.testMemoryEfficiencyBounds();
}

test "dispatch performance boundaries - all tests" {
    var perf_tests = try DispatchPerformanceBoundaryTests.init(testing.allocator);
    defer perf_tests.deinit();

    try perf_tests.runAllPerformanceTests();
}
