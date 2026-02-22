// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;
const ModuleDispatcher = @import("module_dispatch.zig").ModuleDispatcher;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchTableOptimizer = @import("dispatch_table_optimizer.zig").DispatchTableOptimizer;

// Integration test for Task 18.1: Advanced compression integration
test "compression integration with dispatch tables" {
    const allocator = testing.allocator;

    // Set up type registry
    var type_registry = TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});
    const float_type = try type_registry.registerType("float", .primitive, &.{});
    const string_type = try type_registry.registerType("string", .primitive, &.{});

    // Set up signature analyzer
    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    // Set up specificity analyzer
    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);
    defer specificity_analyzer.deinit();

    // Create module dispatcher with compression integration
    var module_dispatcher = ModuleDispatcher.init(
        allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );
    defer module_dispatcher.deinit();

    // Configure compression settings
    var compression_config = DispatchTableOptimizer.OptimizationConfig.default();
    compression_config.enable_advanced_compression = true;
    compression_config.enable_delta_compression = true;
    compression_config.enable_dictionary_compression = true;
    compression_config.min_entries_for_compression = 2; // Low threshold for testing

    module_dispatcher.configureCompression(compression_config);

    // Register test modules
    const math_module = try module_dispatcher.registerModule(
        "math",
        "/test/math.jan",
        .{ .major = 1, .minor = 0, .patch = 0 },
        &.{},
    );

    const string_module = try module_dispatcher.registerModule(
        "string",
        "/test/string.jan",
        .{ .major = 1, .minor = 0, .patch = 0 },
        &.{},
    );

    // Create test implementations
    const add_int_impl = SignatureAnalyzer.Implementation{
        .func_id = .{ .name = "add", .module = "math" },
        .param_type_ids = &[_]TypeRegistry.TypeId{ int_type, int_type },
        .return_type_id = int_type,
        .effects = .{},
        .specificity_rank = 100,
        .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
    };

    const add_float_impl = SignatureAnalyzer.Implementation{
        .func_id = .{ .name = "add", .module = "math" },
        .param_type_ids = &[_]TypeRegistry.TypeId{ float_type, float_type },
        .return_type_id = float_type,
        .effects = .{},
        .specificity_rank = 100,
        .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
    };

    const concat_impl = SignatureAnalyzer.Implementation{
        .func_id = .{ .name = "add", .module = "string" },
        .param_type_ids = &[_]TypeRegistry.TypeId{ string_type, string_type },
        .return_type_id = string_type,
        .effects = .{},
        .specificity_rank = 100,
        .source_location = .{ .start = 0, .end = 10, .line = 3, .column = 1 },
    };

    // Export signatures from modules
    try module_dispatcher.exportSignature(
        math_module,
        "add",
        &[_]*const SignatureAnalyzer.Implementation{ &add_int_impl, &add_float_impl },
        .public,
        null,
    );

    try module_dispatcher.exportSignature(
        string_module,
        "add",
        &[_]*const SignatureAnalyzer.Implementation{&concat_impl},
        .public,
        null,
    );

    // Load modules
    try module_dispatcher.loadModule(math_module);
    try module_dispatcher.loadModule(string_module);

    // Create compressed dispatch table for cross-module "add" signature
    const compressed_table = try module_dispatcher.createCompressedDispatchTable("add");

    // Verify the table was created and potentially compressed
    try testing.expect(compressed_table.entry_count >= 3); // Should have all 3 implementations

    // Test compression statistics
    if (compressed_table.getCompressionStats()) |stats| {
        try testing.expect(stats.compression_ratio <= 1.0); // Should be compressed or same size
        try testing.expect(stats.original_bytes > 0);
        try testing.expect(stats.compressed_bytes > 0);

        std.debug.print("Compression achieved: {}\n", .{stats});
    }

    // Test compressed lookup functionality
    const int_args = &[_]TypeRegistry.TypeId{ int_type, int_type };
    const result = try compressed_table.compressedLookup(int_args);
    try testing.expect(result != null);
    try testing.expect(std.mem.eql(u8, result.?.func_id.name, "add"));
    try testing.expect(std.mem.eql(u8, result.?.func_id.module, "math"));

    // Generate compression report
    var report_buffer = std.ArrayList(u8).init(allocator);
    defer report_buffer.deinit();

    try module_dispatcher.getCompressionReport(report_buffer.writer());
    const report = report_buffer.items;

    try testing.expect(report.len > 0);
    try testing.expect(std.mem.indexOf(u8, report, "Cross-Module Dispatch Compression Report") != null);

    std.debug.print("Compression Report:\n{s}\n", .{report});
}

// Test direct OptimizedDispatchTable compression integration
test "optimized dispatch table compression integration" {
    const allocator = testing.allocator;

    // Set up type registry
    var type_registry = TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});
    const float_type = try type_registry.registerType("float", .primitive, &.{});

    // Create dispatch table
    var table = try OptimizedDispatchTable.init(
        allocator,
        "test_func",
        &[_]TypeRegistry.TypeId{ int_type, int_type },
    );
    defer table.deinit();

    // Add test implementations
    const impl1 = SignatureAnalyzer.Implementation{
        .func_id = .{ .name = "test_func", .module = "test" },
        .param_type_ids = &[_]TypeRegistry.TypeId{ int_type, int_type },
        .return_type_id = int_type,
        .effects = .{},
        .specificity_rank = 100,
        .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
    };

    const impl2 = SignatureAnalyzer.Implementation{
        .func_id = .{ .name = "test_func", .module = "test" },
        .param_type_ids = &[_]TypeRegistry.TypeId{ float_type, float_type },
        .return_type_id = float_type,
        .effects = .{},
        .specificity_rank = 100,
        .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
    };

    try table.addImplementation(&impl1);
    try table.addImplementation(&impl2);

    // Test compression integration
    var optimizer = DispatchTableOptimizer.init(allocator);
    defer optimizer.deinit();

    var config = DispatchTableOptimizer.OptimizationConfig.default();
    config.enable_advanced_compression = true;
    config.min_entries_for_compression = 1; // Low threshold for testing

    const optimization_result = try optimizer.optimizeTable(&table, config);

    // Verify optimization was applied
    try testing.expect(optimization_result.optimization_applied != .none);

    if (optimization_result.compression_metrics) |metrics| {
        try testing.expect(metrics.original_bytes > 0);
        std.debug.print("Optimization result: {}\n", .{optimization_result});
        std.debug.print("Compression metrics: original={}, compressed={}, ratio={d:.2}\n", .{
            metrics.original_bytes,
            metrics.compressed_bytes,
            metrics.getTotalCompressionRatio(),
        });
    }

    // Test that compressed lookup still works
    const test_args = &[_]TypeRegistry.TypeId{ int_type, int_type };
    const lookup_result = try table.compressedLookup(test_args);
    try testing.expect(lookup_result != null);
    try testing.expect(std.mem.eql(u8, lookup_result.?.func_id.name, "test_func"));
}
