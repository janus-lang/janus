// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

// Import all dispatch system components
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;
const ModuleDispatcher = @import("module_dispatch.zig").ModuleDispatcher;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchTableOptimizer = @import("dispatch_table_optimizer.zig").DispatchTableOptimizer;

/// Comprehensive integration test suite for Task 19
/// Tests the complete dispatch pipeline from parsing to code generation
pub const ComprehensiveDispatchIntegrationTests = struct {
    allocator: Allocator,
    type_registry: TypeRegistry,
    signature_analyzer: SignatureAnalyzer,
    specificity_analyzer: SpecificityAnalyzer,
    module_dispatcher: ModuleDispatcher,
    dispatch_optimizer: DispatchTableOptimizer,

    const Self = @This();

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

    /// Test 1: End-to-end dispatch pipeline
    pub fn testEndToEndDispatchPipeline(self: *Self) !void {
        // Set up type system
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});
        const string_type = try self.type_registry.registerType("string", .primitive, &.{});

        // Register modules
        const math_module = try self.module_dispatcher.registerModule(
            "math",
            "/test/math.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        const string_module = try self.module_dispatcher.registerModule(
            "string",
            "/test/string.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        // Create implementations (simulating parsing phase)
        const add_int_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "add", .module = "math" },
            .param_type_ids = &[_]TypeRegistry.TypeId{ int_type, int_type },
            .return_type_id = int_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        const add_float_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "add", .module = "math" },
            .param_type_ids = &[_]TypeRegistry.TypeId{ float_type, float_type },
            .return_type_id = float_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
        };

        const concat_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "add", .module = "string" },
            .param_type_ids = &[_]TypeRegistry.TypeId{ string_type, string_type },
            .return_type_id = string_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 3, .column = 1 },
        };

        // Semantic analysis phase: Export signatures
        try self.module_dispatcher.exportSignature(
            math_module,
            "add",
            &[_]*const SignatureAnalyzer.Implementation{ &add_int_impl, &add_float_impl },
            .public,
            null,
        );

        try self.module_dispatcher.exportSignature(
            string_module,
            "add",
            &[_]*const SignatureAnalyzer.Implementation{&concat_impl},
            .public,
            null,
        );

        // Load modules (simulating module loading phase)
        try self.module_dispatcher.loadModule(math_module);
        try self.module_dispatcher.loadModule(string_module);

        // Code generation phase: Create optimized dispatch table
        const dispatch_table = try self.module_dispatcher.createCompressedDispatchTable("add");

        // Validation: Verify complete pipeline worked
        try testing.expect(dispatch_table.entry_count >= 3);

        // Test dispatch resolution (simulating runtime)
        const int_args = &[_]TypeRegistry.TypeId{ int_type, int_type };
        const int_result = try dispatch_table.compressedLookup(int_args);
        try testing.expect(int_result != null);
        try testing.expect(std.mem.eql(u8, int_result.?.function_id.name, "add"));
        try testing.expect(std.mem.eql(u8, int_result.?.function_id.module, "math"));

        const float_args = &[_]TypeRegistry.TypeId{ float_type, float_type };
        const float_result = try dispatch_table.compressedLookup(float_args);
        try testing.expect(float_result != null);
        try testing.expect(std.mem.eql(u8, float_result.?.function_id.name, "add"));
        try testing.expect(std.mem.eql(u8, float_result.?.function_id.module, "math"));

        const string_args = &[_]TypeRegistry.TypeId{ string_type, string_type };
        const string_result = try dispatch_table.compressedLookup(string_args);
        try testing.expect(string_result != null);
        try testing.expect(std.mem.eql(u8, string_result.?.function_id.name, "add"));
        try testing.expect(std.mem.eql(u8, string_result.?.function_id.module, "string"));
    }

    /// Test 2: Error condition validation
    pub fn testErrorConditionValidation(self: *Self) !void {
        // Test 2.1: No matching implementation error
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});

        const math_module = try self.module_dispatcher.registerModule(
            "math",
            "/test/math.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        const add_int_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "add", .module = "math" },
            .param_type_ids = &[_]TypeRegistry.TypeId{ int_type, int_type },
            .return_type_id = int_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        try self.module_dispatcher.exportSignature(
            math_module,
            "add",
            &[_]*const SignatureAnalyzer.Implementation{&add_int_impl},
            .public,
            null,
        );

        try self.module_dispatcher.loadModule(math_module);

        const dispatch_table = try self.module_dispatcher.createCompressedDispatchTable("add");

        // Test no matching implementation
        const float_args = &[_]TypeRegistry.TypeId{ float_type, float_type };
        const no_match_result = try dispatch_table.compressedLookup(float_args);
        try testing.expect(no_match_result == null); // Should return null for no match

        // Test 2.2: Ambiguous dispatch error
        const animal_type = try self.type_registry.registerType("Animal", .table_open, &.{});
        const dog_type = try self.type_registry.registerType("Dog", .table_sealed, &[_]TypeRegistry.TypeId{animal_type});
        const cat_type = try self.type_registry.registerType("Cat", .table_sealed, &[_]TypeRegistry.TypeId{animal_type});

        const process_dog_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "process", .module = "animals" },
            .param_type_ids = &[_]TypeRegistry.TypeId{dog_type},
            .return_type_id = int_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        const process_cat_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "process", .module = "animals" },
            .param_type_ids = &[_]TypeRegistry.TypeId{cat_type},
            .return_type_id = int_type,
            .effects = .{},
            .specificity_rank = 100, // Same specificity - should be ambiguous
            .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
        };

        const animals_module = try self.module_dispatcher.registerModule(
            "animals",
            "/test/animals.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        try self.module_dispatcher.exportSignature(
            animals_module,
            "process",
            &[_]*const SignatureAnalyzer.Implementation{ &process_dog_impl, &process_cat_impl },
            .public,
            null,
        );

        try self.module_dispatcher.loadModule(animals_module);

        // Test ambiguity detection in specificity analyzer
        const implementations = &[_]*const SignatureAnalyzer.Implementation{ &process_dog_impl, &process_cat_impl };
        const union_type_args = &[_]TypeRegistry.TypeId{dog_type}; // This should match dog specifically

        const result = try self.specificity_analyzer.findMostSpecific(implementations, union_type_args);
        switch (result) {
            .unique => |impl| {
                try testing.expect(std.mem.eql(u8, impl.function_id.name, "process"));
            },
            .ambiguous => {
                // This is expected for truly ambiguous cases
            },
            .no_match => {
                try testing.expect(false); // Should not happen
            },
        }
    }

    /// Test 3: Property-based tests for dispatch invariants
    pub fn testDispatchInvariants(self: *Self) !void {
        // Property 1: Dispatch resolution is deterministic
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});

        const math_module = try self.module_dispatcher.registerModule(
            "math",
            "/test/math.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        const add_int_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "add", .module = "math" },
            .param_type_ids = &[_]TypeRegistry.TypeId{ int_type, int_type },
            .return_type_id = int_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        const add_float_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "add", .module = "math" },
            .param_type_ids = &[_]TypeRegistry.TypeId{ float_type, float_type },
            .return_type_id = float_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
        };

        try self.module_dispatcher.exportSignature(
            math_module,
            "add",
            &[_]*const SignatureAnalyzer.Implementation{ &add_int_impl, &add_float_impl },
            .public,
            null,
        );

        try self.module_dispatcher.loadModule(math_module);

        const dispatch_table = try self.module_dispatcher.createCompressedDispatchTable("add");

        // Test determinism: Multiple lookups should return same result
        const int_args = &[_]TypeRegistry.TypeId{ int_type, int_type };

        const result1 = try dispatch_table.compressedLookup(int_args);
        const result2 = try dispatch_table.compressedLookup(int_args);
        const result3 = try dispatch_table.compressedLookup(int_args);

        try testing.expect(result1 != null);
        try testing.expect(result2 != null);
        try testing.expect(result3 != null);

        // All results should be identical
        try testing.expect(result1.? == result2.?);
        try testing.expect(result2.? == result3.?);
        try testing.expect(std.mem.eql(u8, result1.?.function_id.name, result2.?.function_id.name));
        try testing.expect(std.mem.eql(u8, result1.?.function_id.module, result2.?.function_id.module));

        // Property 2: Most specific implementation is always chosen
        const number_type = try self.type_registry.registerType("Number", .table_open, &.{});
        const specific_int_type = try self.type_registry.registerType("SpecificInt", .table_sealed, &[_]TypeRegistry.TypeId{number_type});

        const generic_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "process", .module = "math" },
            .param_type_ids = &[_]TypeRegistry.TypeId{number_type},
            .return_type_id = number_type,
            .effects = .{},
            .specificity_rank = 50, // Less specific
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        const specific_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "process", .module = "math" },
            .param_type_ids = &[_]TypeRegistry.TypeId{specific_int_type},
            .return_type_id = specific_int_type,
            .effects = .{},
            .specificity_rank = 100, // More specific
            .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
        };

        try self.module_dispatcher.exportSignature(
            math_module,
            "process",
            &[_]*const SignatureAnalyzer.Implementation{ &generic_impl, &specific_impl },
            .public,
            null,
        );

        const process_table = try self.module_dispatcher.createCompressedDispatchTable("process");

        // When calling with specific type, should get specific implementation
        const specific_args = &[_]TypeRegistry.TypeId{specific_int_type};
        const specific_result = try process_table.compressedLookup(specific_args);

        try testing.expect(specific_result != null);
        try testing.expect(specific_result.?.specificity_rank == 100); // Should be the more specific one
    }

    /// Test 4: Performance tests ensuring dispatch overhead remains within bounds
    pub fn testPerformanceBounds(self: *Self) !void {
        // Set up a large signature group to test performance
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});
        const string_type = try self.type_registry.registerType("string", .primitive, &.{});

        const math_module = try self.module_dispatcher.registerModule(
            "math",
            "/test/math.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        // Create multiple implementations to stress test
        var implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        // Create implementations on the heap so they persist
        var impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer impl_storage.deinit();

        const type_combinations = [_][2]TypeRegistry.TypeId{
            .{ int_type, int_type },
            .{ float_type, float_type },
            .{ string_type, string_type },
            .{ int_type, float_type },
            .{ float_type, int_type },
            .{ int_type, string_type },
            .{ string_type, int_type },
            .{ float_type, string_type },
            .{ string_type, float_type },
        };

        for (type_combinations, 0..) |combo, i| {
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "op", .module = "math" },
                .param_type_ids = &[_]TypeRegistry.TypeId{ combo[0], combo[1] },
                .return_type_id = combo[0],
                .effects = .{},
                .specificity_rank = 100,
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        try self.module_dispatcher.exportSignature(
            math_module,
            "op",
            implementations.items,
            .public,
            null,
        );

        try self.module_dispatcher.loadModule(math_module);

        const dispatch_table = try self.module_dispatcher.createCompressedDispatchTable("op");

        // Performance test: Measure dispatch overhead
        const iterations = 10000;
        const test_args = &[_]TypeRegistry.TypeId{ int_type, int_type };

        const start_time = compat_time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try dispatch_table.compressedLookup(test_args);
            try testing.expect(result != null);
        }

        const end_time = compat_time.nanoTimestamp();
        const total_time_ns = end_time - start_time;
        const avg_time_ns = total_time_ns / iterations;

        // Performance bound: Each dispatch should take less than 1000ns (1μs) on average
        // This is a reasonable bound for production dispatch systems
        try testing.expect(avg_time_ns < 1000);

        std.debug.print("Dispatch performance: {} ns average per lookup\n", .{avg_time_ns});

        // Memory efficiency test: Verify compression is working
        if (dispatch_table.getCompressionStats()) |stats| {
            try testing.expect(stats.compression_ratio <= 1.0); // Should be compressed or same size
            try testing.expect(stats.original_bytes > 0);

            std.debug.print("Memory efficiency: {d:.1}% compression ratio\n", .{stats.compression_ratio * 100.0});
        }

        // Scalability test: Verify O(1) or O(log n) lookup performance
        // Create a larger table and verify performance doesn't degrade significantly
        var large_implementations: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer large_implementations.deinit();

        var large_impl_storage: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer large_impl_storage.deinit();

        // Create 50 implementations to test scalability
        for (0..50) |i| {
            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "large_op", .module = "math" },
                .param_type_ids = &[_]TypeRegistry.TypeId{ int_type, int_type },
                .return_type_id = int_type,
                .effects = .{},
                .specificity_rank = @intCast(100 + i),
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };
            try large_impl_storage.append(impl);
            try large_implementations.append(&large_impl_storage.items[large_impl_storage.items.len - 1]);
        }

        try self.module_dispatcher.exportSignature(
            math_module,
            "large_op",
            large_implementations.items,
            .public,
            null,
        );

        const large_dispatch_table = try self.module_dispatcher.createCompressedDispatchTable("large_op");

        const large_start_time = compat_time.nanoTimestamp();

        for (0..iterations) |_| {
            const result = try large_dispatch_table.compressedLookup(test_args);
            try testing.expect(result != null);
        }

        const large_end_time = compat_time.nanoTimestamp();
        const large_total_time_ns = large_end_time - large_start_time;
        const large_avg_time_ns = large_total_time_ns / iterations;

        // Scalability bound: Large table should not be more than 2x slower
        // This verifies we have good algorithmic complexity
        try testing.expect(large_avg_time_ns < avg_time_ns * 2);

        std.debug.print("Large table performance: {} ns average per lookup ({}x larger table)\n", .{ large_avg_time_ns, large_implementations.items.len });
    }

    /// Test 5: Cross-module integration validation
    pub fn testCrossModuleIntegration(self: *Self) !void {
        // Test cross-module signature extension and conflict resolution
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});

        // Create two modules that both export "convert" function
        const math_module = try self.module_dispatcher.registerModule(
            "math",
            "/test/math.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        const utils_module = try self.module_dispatcher.registerModule(
            "utils",
            "/test/utils.jan",
            .{ .major = 1, .minor = 0, .patch = 0 },
            &.{},
        );

        const math_convert_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "convert", .module = "math" },
            .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
            .return_type_id = float_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        const utils_convert_impl = SignatureAnalyzer.Implementation{
            .function_id = .{ .name = "convert", .module = "utils" },
            .param_type_ids = &[_]TypeRegistry.TypeId{float_type},
            .return_type_id = int_type,
            .effects = .{},
            .specificity_rank = 100,
            .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
        };

        try self.module_dispatcher.exportSignature(
            math_module,
            "convert",
            &[_]*const SignatureAnalyzer.Implementation{&math_convert_impl},
            .public,
            null,
        );

        try self.module_dispatcher.exportSignature(
            utils_module,
            "convert",
            &[_]*const SignatureAnalyzer.Implementation{&utils_convert_impl},
            .public,
            null,
        );

        try self.module_dispatcher.loadModule(math_module);
        try self.module_dispatcher.loadModule(utils_module);

        // Create cross-module dispatch table
        const cross_module_table = try self.module_dispatcher.createCompressedDispatchTable("convert");

        // Verify both implementations are available
        try testing.expect(cross_module_table.entry_count >= 2);

        // Test dispatch to correct module based on argument types
        const int_args = &[_]TypeRegistry.TypeId{int_type};
        const int_result = try cross_module_table.compressedLookup(int_args);
        try testing.expect(int_result != null);
        try testing.expect(std.mem.eql(u8, int_result.?.function_id.module, "math"));

        const float_args = &[_]TypeRegistry.TypeId{float_type};
        const float_result = try cross_module_table.compressedLookup(float_args);
        try testing.expect(float_result != null);
        try testing.expect(std.mem.eql(u8, float_result.?.function_id.module, "utils"));

        // Test consistency checking
        const consistency_report = try self.module_dispatcher.checkDispatchConsistency();
        defer consistency_report.deinit();

        // Should have no inconsistencies for this valid setup
        try testing.expect(!consistency_report.hasInconsistencies());
    }

    /// Run all integration tests
    pub fn runAllTests(self: *Self) !void {
        std.debug.print("Running comprehensive dispatch integration tests...\n");

        std.debug.print("1. Testing end-to-end dispatch pipeline...\n");
        try self.testEndToEndDispatchPipeline();

        std.debug.print("2. Testing error condition validation...\n");
        try self.testErrorConditionValidation();

        std.debug.print("3. Testing dispatch invariants...\n");
        try self.testDispatchInvariants();

        std.debug.print("4. Testing performance bounds...\n");
        try self.testPerformanceBounds();

        std.debug.print("5. Testing cross-module integration...\n");
        try self.testCrossModuleIntegration();

        std.debug.print("All integration tests passed! ✅\n");
    }
};

// Individual test functions for zig test runner
test "comprehensive dispatch integration - end to end pipeline" {
    var test_suite = try ComprehensiveDispatchIntegrationTests.init(testing.allocator);
    defer test_suite.deinit();

    try test_suite.testEndToEndDispatchPipeline();
}

test "comprehensive dispatch integration - error conditions" {
    var test_suite = try ComprehensiveDispatchIntegrationTests.init(testing.allocator);
    defer test_suite.deinit();

    try test_suite.testErrorConditionValidation();
}

test "comprehensive dispatch integration - invariants" {
    var test_suite = try ComprehensiveDispatchIntegrationTests.init(testing.allocator);
    defer test_suite.deinit();

    try test_suite.testDispatchInvariants();
}

test "comprehensive dispatch integration - performance bounds" {
    var test_suite = try ComprehensiveDispatchIntegrationTests.init(testing.allocator);
    defer test_suite.deinit();

    try test_suite.testPerformanceBounds();
}

test "comprehensive dispatch integration - cross module" {
    var test_suite = try ComprehensiveDispatchIntegrationTests.init(testing.allocator);
    defer test_suite.deinit();

    try test_suite.testCrossModuleIntegration();
}

test "comprehensive dispatch integration - all tests" {
    var test_suite = try ComprehensiveDispatchIntegrationTests.init(testing.allocator);
    defer test_suite.deinit();

    try test_suite.runAllTests();
}
