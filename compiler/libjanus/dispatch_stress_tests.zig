// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const Random = std.Random;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;
const ModuleDispatcher = @import("module_dispatch.zig").ModuleDispatcher;

/// Stress tests for large signature groups and deep type hierarchies
/// Tests the dispatch system under extreme conditions
pub const DispatchStressTests = struct {
    allocator: Allocator,
    rng: Random,
    type_registry: TypeRegistry,
    signature_analyzer: SignatureAnalyzer,
    specificity_analyzer: SpecificityAnalyzer,
    module_dispatcher: ModuleDispatcher,

    const Self = @This();

    // Stress test parameters
    const LARGE_SIGNATURE_SIZE = 1000; // 1000 implementations per signature
    const MASSIVE_SIGNATURE_SIZE = 5000; // 5000 implementations for extreme stress
    const DEEP_HIERARCHY_DEPTH = 20; // 20 levels deep type hierarchy
    const WIDE_HIERARCHY_BREADTH = 50; // 50 types per level
    const STRESS_TEST_ITERATIONS = 10000; // 10k iterations for stress testing

    pub fn init(allocator: Allocator, seed: u64) !Self {
        var prng = std.rand.DefaultPrng.init(seed);
        var type_registry = TypeRegistry.init(allocator);
        var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
        var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);
        var module_dispatcher = ModuleDispatcher.init(
            allocator,
            &type_registry,
            &signature_analyzer,
            &specificity_analyzer,
        );

        return Self{
            .allocator = allocator,
            .rng = prng.random(),
            .type_registry = type_registry,
            .signature_analyzer = signature_analyzer,
            .specificity_analyzer = specificity_analyzer,
            .module_dispatcher = module_dispatcher,
        };
    }

    pub fn deinit(self: *Self) void {
        self.module_dispatcher.deinit();
        self.specificity_analyzer.deinit();
        self.signature_analyzer.deinit();
        self.type_registry.deinit();
    }

    /// Stress Test 1: Large Signature Groups
    pub fn testLargeSignatureGroups(self: *Self) !void {
        std.debug.print("🔥 Stress testing large signature groups...\n");

        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});

        // Create large signature group
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        std.debug.print("  Creating {} implementations...\n", .{LARGE_SIGNATURE_SIZE});

        for (0..LARGE_SIGNATURE_SIZE) |i| {
            const param_type = if (i % 2 == 0) int_type else float_type;
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "large_func", .module = "stress" },
                .param_type_ids = &[_]TypeRegistry.TypeId{param_type},
                .return_type_id = param_type,
                .effects = .{},
                .specificity_rank = @intCast(100 + i), // All different specificity
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        std.debug.print("  Testing dispatch performance with large signature...\n");

        const test_args = &[_]TypeRegistry.TypeId{int_type};
        const iterations = 1000;

        const start_time = compat_time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => try testing.expect(false),
            }
        }

        const end_time = compat_time.nanoTimestamp();
        const avg_time_ns = (end_time - start_time) / iterations;

        std.debug.print("  Large signature performance: {} ns average\n", .{avg_time_ns});

        // Performance should still be reasonable even with large signatures
        const max_acceptable_ns = 10_000; // 10μs max for very large signatures
        try testing.expect(avg_time_ns < max_acceptable_ns);

        std.debug.print("  ✅ Large signature group stress test passed\n");
    }

    /// Stress Test 2: Massive Signature Groups (Extreme)
    pub fn testMassiveSignatureGroups(self: *Self) !void {
        std.debug.print("🌋 Extreme stress testing with massive signature groups...\n");

        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        // Create massive signature group
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        std.debug.print("  Creating {} implementations (this may take a moment)...\n", .{MASSIVE_SIGNATURE_SIZE});

        for (0..MASSIVE_SIGNATURE_SIZE) |i| {
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "massive_func", .module = "stress" },
                .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
                .return_type_id = int_type,
                .effects = .{},
                .specificity_rank = @intCast(100 + i),
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);

            // Progress indicator
            if (i % 1000 == 0) {
                std.debug.print("    Progress: {}/{}\n", .{ i, MASSIVE_SIGNATURE_SIZE });
            }
        }

        std.debug.print("  Testing dispatch with massive signature...\n");

        const test_args = &[_]TypeRegistry.TypeId{int_type};
        const iterations = 100; // Fewer iterations for massive test

        const start_time = compat_time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => try testing.expect(false),
            }
        }

        const end_time = compat_time.nanoTimestamp();
        const avg_time_ns = (end_time - start_time) / iterations;

        std.debug.print("  Massive signature performance: {} ns average\n", .{avg_time_ns});

        // Even with massive signatures, should complete in reasonable time
        const max_acceptable_ns = 50_000; // 50μs max for massive signatures
        try testing.expect(avg_time_ns < max_acceptable_ns);

        // Memory usage check
        const memory_per_impl = (implementations.items.len * @sizeOf(SignatureAnalyzer.Implementation)) / implementations.items.len;
        std.debug.print("  Memory per implementation: {} bytes\n", .{memory_per_impl});

        std.debug.print("  ✅ Massive signature group stress test passed\n");
    }

    /// Stress Test 3: Deep Type Hierarchies
    pub fn testDeepTypeHierarchies(self: *Self) !void {
        std.debug.print("🏔️ Stress testing deep type hierarchies...\n");

        // Create deep inheritance chain
        var type_chain: ArrayList(TypeRegistry.TypeId) = .empty;
        defer type_chain.deinit();

        std.debug.print("  Creating {}-level deep type hierarchy...\n", .{DEEP_HIERARCHY_DEPTH});

        // Create base type
        const base_type = try self.type_registry.registerType("Base", .table_open, &.{});
        try type_chain.append(base_type);

        // Create deep chain
        for (1..DEEP_HIERARCHY_DEPTH) |i| {
            const type_name = try std.fmt.allocPrint(self.allocator, "Level{}", .{i});
            defer self.allocator.free(type_name);

            const parent_type = type_chain.items[i - 1];
            const child_type = try self.type_registry.registerType(type_name, .table_open, &[_]TypeRegistry.TypeId{parent_type});
            try type_chain.append(child_type);
        }

        // Create implementations for each level
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        for (type_chain.items, 0..) |type_id, i| {
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "deep_func", .module = "stress" },
                .param_type_ids = &[_]TypeRegistry.TypeId{type_id},
                .return_type_id = type_id,
                .effects = .{},
                .specificity_rank = @intCast(100 + (DEEP_HIERARCHY_DEPTH - i)), // Deeper = more specific
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        std.debug.print("  Testing dispatch with deep hierarchy...\n");

        // Test dispatch at various levels
        for (type_chain.items, 0..) |type_id, level| {
            const test_args = &[_]TypeRegistry.TypeId{type_id};
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);

            switch (result) {
                .unique => |impl| {
                    // Should find the most specific implementation for this level
                    try testing.expect(impl.param_type_ids[0] == type_id);
                },
                .ambiguous => {
                    std.debug.print("    ⚠️  Ambiguity at level {}\n", .{level});
                },
                .no_match => try testing.expect(false),
            }
        }

        // Performance test with deepest type
        const deepest_type = type_chain.items[type_chain.items.len - 1];
        const deepest_args = &[_]TypeRegistry.TypeId{deepest_type};
        const iterations = 1000;

        const start_time = compat_time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, deepest_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => {},
            }
        }

        const end_time = compat_time.nanoTimestamp();
        const avg_time_ns = (end_time - start_time) / iterations;

        std.debug.print("  Deep hierarchy performance: {} ns average\n", .{avg_time_ns});

        // Should handle deep hierarchies efficiently
        const max_acceptable_ns = 5_000; // 5μs max for deep hierarchies
        try testing.expect(avg_time_ns < max_acceptable_ns);

        std.debug.print("  ✅ Deep type hierarchy stress test passed\n");
    }

    /// Stress Test 4: Wide Type Hierarchies
    pub fn testWideTypeHierarchies(self: *Self) !void {
        std.debug.print("🌊 Stress testing wide type hierarchies...\n");

        // Create wide inheritance pattern
        const base_type = try self.type_registry.registerType("WideBase", .table_open, &.{});

        var child_types: ArrayList(TypeRegistry.TypeId) = .empty;
        defer child_types.deinit();

        std.debug.print("  Creating wide hierarchy with {} child types...\n", .{WIDE_HIERARCHY_BREADTH});

        // Create many child types
        for (0..WIDE_HIERARCHY_BREADTH) |i| {
            const type_name = try std.fmt.allocPrint(self.allocator, "WideChild{}", .{i});
            defer self.allocator.free(type_name);

            const child_type = try self.type_registry.registerType(type_name, .table_sealed, &[_]TypeRegistry.TypeId{base_type});
            try child_types.append(child_type);
        }

        // Create implementations for base and all children
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        // Base implementation
        const base_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "wide_func", .module = "stress" },
            .param_type_ids = &[_]TypeRegistry.TypeId{base_type},
            .return_type_id = base_type,
            .effects = .{},
            .specificity_rank = 50, // Less specific
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };
        try impl_storage.append(base_impl);
        try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);

        // Child implementations
        for (child_types.items, 0..) |child_type, i| {
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "wide_func", .module = "stress" },
                .param_type_ids = &[_]TypeRegistry.TypeId{child_type},
                .return_type_id = child_type,
                .effects = .{},
                .specificity_rank = @intCast(100 + i), // More specific
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 2), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        std.debug.print("  Testing dispatch with wide hierarchy...\n");

        // Test dispatch for each child type
        for (child_types.items, 0..) |child_type, i| {
            const test_args = &[_]TypeRegistry.TypeId{child_type};
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);

            switch (result) {
                .unique => |impl| {
                    try testing.expect(impl.param_type_ids[0] == child_type);
                    try testing.expect(impl.specificity_rank == @as(u32, @intCast(100 + i)));
                },
                else => try testing.expect(false),
            }
        }

        // Performance test
        const random_child = child_types.items[self.rng.intRangeAtMost(usize, 0, child_types.items.len - 1)];
        const test_args = &[_]TypeRegistry.TypeId{random_child};
        const iterations = 1000;

        const start_time = compat_time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => {},
            }
        }

        const end_time = compat_time.nanoTimestamp();
        const avg_time_ns = (end_time - start_time) / iterations;

        std.debug.print("  Wide hierarchy performance: {} ns average\n", .{avg_time_ns});

        // Should handle wide hierarchies efficiently
        const max_acceptable_ns = 3_000; // 3μs max for wide hierarchies
        try testing.expect(avg_time_ns < max_acceptable_ns);

        std.debug.print("  ✅ Wide type hierarchy stress test passed\n");
    }

    /// Stress Test 5: Combined Large Signatures + Deep Hierarchies
    pub fn testCombinedStress(self: *Self) !void {
        std.debug.print("💥 Combined stress test: Large signatures + Deep hierarchies...\n");

        // Create moderate depth hierarchy
        const hierarchy_depth = 10;
        var type_chain: ArrayList(TypeRegistry.TypeId) = .empty;
        defer type_chain.deinit();

        const base_type = try self.type_registry.registerType("CombinedBase", .table_open, &.{});
        try type_chain.append(base_type);

        for (1..hierarchy_depth) |i| {
            const type_name = try std.fmt.allocPrint(self.allocator, "Combined{}", .{i});
            defer self.allocator.free(type_name);

            const parent_type = type_chain.items[i - 1];
            const child_type = try self.type_registry.registerType(type_name, .table_open, &[_]TypeRegistry.TypeId{parent_type});
            try type_chain.append(child_type);
        }

        // Create large number of implementations across the hierarchy
        const impls_per_level = 100;
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        std.debug.print("  Creating {} implementations across {} hierarchy levels...\n", .{ impls_per_level * hierarchy_depth, hierarchy_depth });

        for (type_chain.items, 0..) |type_id, level| {
            for (0..impls_per_level) |i| {
                const impl = SignatureAnalyzer.Implementation{
                    .function_id = .{ .name = "combined_func", .module = "stress" },
                    .param_type_ids = &[_]TypeRegistry.TypeId{type_id},
                    .return_type_id = type_id,
                    .effects = .{},
                    .specificity_rank = @intCast(100 + (hierarchy_depth - level) * 1000 + i),
                    .source_location = .{ .start = 0, .end = 10, .line = @intCast(level * impls_per_level + i + 1), .column = 1 },
                };
                try impl_storage.append(impl);
                try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
            }
        }

        std.debug.print("  Total implementations: {}\n", .{implementations.items.len});

        // Stress test dispatch performance
        const deepest_type = type_chain.items[type_chain.items.len - 1];
        const test_args = &[_]TypeRegistry.TypeId{deepest_type};
        const iterations = 500;

        std.debug.print("  Running {} dispatch iterations...\n", .{iterations});

        const start_time = compat_time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try self.specificity_analyzer.findMostSpecific(implementations.items, test_args);
            switch (result) {
                .unique => |impl| {
                    std.mem.doNotOptimizeAway(impl);
                },
                else => {},
            }
        }

        const end_time = compat_time.nanoTimestamp();
        const avg_time_ns = (end_time - start_time) / iterations;

        std.debug.print("  Combined stress performance: {} ns average\n", .{avg_time_ns});

        // Should handle combined stress reasonably
        const max_acceptable_ns = 20_000; // 20μs max for combined stress
        try testing.expect(avg_time_ns < max_acceptable_ns);

        std.debug.print("  ✅ Combined stress test passed\n");
    }

    /// Stress Test 6: Memory Pressure Test
    pub fn testMemoryPressure(self: *Self) !void {
        std.debug.print("🧠 Memory pressure stress test...\n");

        const int_type = try self.type_registry.registerType("int", .primitive, &.{});

        // Create many modules with many signatures
        const module_count = 50;
        const signatures_per_module = 20;
        const impls_per_signature = 50;

        var modules: ArrayList(u32) = .empty;
        defer modules.deinit();

        std.debug.print("  Creating {} modules with {} signatures each...\n", .{ module_count, signatures_per_module });

        for (0..module_count) |i| {
            const module_name = try std.fmt.allocPrint(self.allocator, "stress_module_{}", .{i});
            defer self.allocator.free(module_name);

            const module_path = try std.fmt.allocPrint(self.allocator, "/stress/{}.jan", .{i});
            defer self.allocator.free(module_path);

            const module_id = try self.module_dispatcher.registerModule(
                module_name,
                module_path,
                .{ .major = 1, .minor = 0, .patch = 0 },
                &.{},
            );

            try modules.append(module_id);

            // Create signatures for this module
            for (0..signatures_per_module) |j| {
                const sig_name = try std.fmt.allocPrint(self.allocator, "stress_func_{}", .{j});
                defer self.allocator.free(sig_name);

                // Create implementations for this signature
                var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
                defer implementations.deinit();

                var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
                defer impl_storage.deinit();

                for (0..impls_per_signature) |k| {
                    const impl = SignatureAnalyzer.Implementation{
                        .function_id = .{ .name = sig_name, .module = module_name },
                        .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
                        .return_type_id = int_type,
                        .effects = .{},
                        .specificity_rank = @intCast(100 + k),
                        .source_location = .{ .start = 0, .end = 10, .line = @intCast(k + 1), .column = 1 },
                    };
                    try impl_storage.append(impl);
                    try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
                }

                try self.module_dispatcher.exportSignature(
                    module_id,
                    sig_name,
                    implementations.items,
                    .public,
                    null,
                );
            }

            try self.module_dispatcher.loadModule(module_id);

            // Progress indicator
            if (i % 10 == 0) {
                std.debug.print("    Loaded {}/{} modules\n", .{ i + 1, module_count });
            }
        }

        std.debug.print("  Testing dispatch table creation under memory pressure...\n");

        // Create dispatch tables for some signatures
        const test_signatures = 10;
        for (0..test_signatures) |i| {
            const sig_name = try std.fmt.allocPrint(self.allocator, "stress_func_{}", .{i});
            defer self.allocator.free(sig_name);

            const dispatch_table = try self.module_dispatcher.createCompressedDispatchTable(sig_name);

            // Verify table was created successfully
            try testing.expect(dispatch_table.entry_count > 0);

            const memory_stats = dispatch_table.getMemoryStats();
            std.debug.print("    Table {}: {} bytes, {} entries\n", .{ i, memory_stats.total_bytes, dispatch_table.entry_count });
        }

        std.debug.print("  ✅ Memory pressure stress test passed\n");
    }

    /// Run all stress tests
    pub fn runAllStressTests(self: *Self) !void {
        std.debug.print("🔥 Running Dispatch Stress Tests\n");
        std.debug.print("===============================\n\n");

        const start_time = compat_time.nanoTimestamp();

        try self.testLargeSignatureGroups();
        std.debug.print("\n");

        try self.testMassiveSignatureGroups();
        std.debug.print("\n");

        try self.testDeepTypeHierarchies();
        std.debug.print("\n");

        try self.testWideTypeHierarchies();
        std.debug.print("\n");

        try self.testCombinedStress();
        std.debug.print("\n");

        try self.testMemoryPressure();
        std.debug.print("\n");

        const end_time = compat_time.nanoTimestamp();
        const total_time_ms = (end_time - start_time) / 1_000_000;

        std.debug.print("🎉 All stress tests passed!\n");
        std.debug.print("Total stress test time: {} ms\n", .{total_time_ms});
        std.debug.print("The dispatch system handles extreme conditions successfully.\n");
    }
};

// Test functions for zig test runner
test "dispatch stress tests - large signature groups" {
    var stress_tests = try DispatchStressTests.init(testing.allocator, 42);
    defer stress_tests.deinit();

    try stress_tests.testLargeSignatureGroups();
}

test "dispatch stress tests - deep type hierarchies" {
    var stress_tests = try DispatchStressTests.init(testing.allocator, 42);
    defer stress_tests.deinit();

    try stress_tests.testDeepTypeHierarchies();
}

test "dispatch stress tests - wide type hierarchies" {
    var stress_tests = try DispatchStressTests.init(testing.allocator, 42);
    defer stress_tests.deinit();

    try stress_tests.testWideTypeHierarchies();
}

test "dispatch stress tests - combined stress" {
    var stress_tests = try DispatchStressTests.init(testing.allocator, 42);
    defer stress_tests.deinit();

    try stress_tests.testCombinedStress();
}

test "dispatch stress tests - memory pressure" {
    var stress_tests = try DispatchStressTests.init(testing.allocator, 42);
    defer stress_tests.deinit();

    try stress_tests.testMemoryPressure();
}

test "dispatch stress tests - all tests" {
    var stress_tests = try DispatchStressTests.init(testing.allocator, 42);
    defer stress_tests.deinit();

    try stress_tests.runAllStressTests();
}
