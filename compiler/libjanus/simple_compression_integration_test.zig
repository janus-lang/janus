// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// Simple integration test to verify Task 18.1 compilation
test "compression integration compiles" {
    // Test that the integration compiles without runtime execution
    const DispatchTableOptimizer = @import("dispatch_table_optimizer.zig").DispatchTableOptimizer;
    const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;

    // Verify the integration methods exist
    const config = DispatchTableOptimizer.OptimizationConfig.default();
    try testing.expect(config.enable_advanced_compression);

    // Test that compression fields were added to OptimizedDispatchTable
    const allocator = testing.allocator;
    var table = OptimizedDispatchTable{
        .allocator = allocator,
        .entries = &.{},
        .entry_count = 0,
        .signature_name = "test",
        .type_signature = &.{},
        .memory_stats = std.mem.zeroes(OptimizedDispatchTable.MemoryStats),
        .decision_tree = null,
        .compression_system = null,
        .compressed_data = &.{},
        .decompression_cache = null,
        .is_compressed = false,
    };

    // Verify compression fields exist and have correct types
    try testing.expect(table.compression_system == null);
    try testing.expect(table.compressed_data.len == 0);
    try testing.expect(table.decompression_cache == null);
    try testing.expect(table.is_compressed == false);

    // Test that compression stats can be retrieved
    const stats = table.getCompressionStats();
    try testing.expect(stats == null); // Should be null for uncompressed table
}

test "module dispatcher compression integration compiles" {
    // Test that ModuleDispatcher has compression integration
    const ModuleDispatcher = @import("module_dispatch.zig").ModuleDispatcher;
    const TypeRegistry = @import("type_registry.zig").TypeRegistry;
    const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
    const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;

    const allocator = testing.allocator;

    var type_registry = TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);
    defer specificity_analyzer.deinit();

    var module_dispatcher = ModuleDispatcher.init(
        allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );
    defer module_dispatcher.deinit();

    // Verify compression integration fields exist
    try testing.expect(@hasField(@TypeOf(module_dispatcher), "dispatch_table_optimizer"));
    try testing.expect(@hasField(@TypeOf(module_dispatcher), "compression_config"));
    try testing.expect(@hasField(@TypeOf(module_dispatcher), "compressed_dispatch_tables"));
}
