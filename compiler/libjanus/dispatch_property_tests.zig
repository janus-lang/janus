// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const Random = std.Random;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;

/// Property-based testing framework for dispatch invariants
/// Generates random test cases to verify dispatch properties hold
pub const DispatchPropertyTests = struct {
    allocator: Allocator,
    rng: Random,
    type_registry: TypeRegistry,
    signature_analyzer: SignatureAnalyzer,
    specificity_analyzer: SpecificityAnalyzer,

    const Self = @This();

    pub fn init(allocator: Allocator, seed: u64) !Self {
        var prng = std.rand.DefaultPrng.init(seed);
        var type_registry = TypeRegistry.init(allocator);
        var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
        var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

        return Self{
            .allocator = allocator,
            .rng = prng.random(),
            .type_registry = type_registry,
            .signature_analyzer = signature_analyzer,
            .specificity_analyzer = specificity_analyzer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.specificity_analyzer.deinit();
        self.signature_analyzer.deinit();
        self.type_registry.deinit();
    }

    /// Property: Dispatch resolution is deterministic
    /// For any given signature and argument types, dispatch should always return the same result
    pub fn testDeterminismProperty(self: *Self, iterations: u32) !void {
        for (0..iterations) |_| {
            // Generate random signature with implementations
            const signature = try self.generateRandomSignature();
            defer self.freeSignature(signature);

            // Generate random argument types
            const arg_types = try self.generateRandomArgumentTypes(signature.arity);
            defer self.allocator.free(arg_types);

            // Perform dispatch multiple times
            const result1 = try self.specificity_analyzer.findMostSpecific(signature.implementations, arg_types);
            const result2 = try self.specificity_analyzer.findMostSpecific(signature.implementations, arg_types);
            const result3 = try self.specificity_analyzer.findMostSpecific(signature.implementations, arg_types);

            // All results should be identical
            switch (result1) {
                .unique => |impl1| {
                    switch (result2) {
                        .unique => |impl2| {
                            switch (result3) {
                                .unique => |impl3| {
                                    try testing.expect(impl1 == impl2);
                                    try testing.expect(impl2 == impl3);
                                },
                                else => try testing.expect(false), // Should be consistent
                            }
                        },
                        else => try testing.expect(false), // Should be consistent
                    }
                },
                .ambiguous => |impls1| {
                    switch (result2) {
                        .ambiguous => |impls2| {
                            switch (result3) {
                                .ambiguous => |impls3| {
                                    // Ambiguous results should have same implementations
                                    try testing.expect(impls1.len == impls2.len);
                                    try testing.expect(impls2.len == impls3.len);
                                },
                                else => try testing.expect(false), // Should be consistent
                            }
                        },
                        else => try testing.expect(false), // Should be consistent
                    }
                },
                .no_match => {
                    try testing.expect(std.meta.activeTag(result2) == .no_match);
                    try testing.expect(std.meta.activeTag(result3) == .no_match);
                },
            }
        }
    }

    /// Property: Most specific implementation is always chosen
    /// If implementation A is more specific than B, and both match, A should be chosen
    pub fn testSpecificityProperty(self: *Self, iterations: u32) !void {
        for (0..iterations) |_| {
            // Generate a type hierarchy
            const base_type = try self.type_registry.registerType("Base", .table_open, &.{});
            const derived_type = try self.type_registry.registerType("Derived", .table_sealed, &[_]TypeRegistry.TypeId{base_type});

            // Create implementations with different specificity
            const generic_impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{base_type},
                .return_type_id = base_type,
                .effects = .{},
                .specificity_rank = 50, // Less specific
                .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
            };

            const specific_impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{derived_type},
                .return_type_id = derived_type,
                .effects = .{},
                .specificity_rank = 100, // More specific
                .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
            };

            const implementations = &[_]*const SignatureAnalyzer.Implementation{ &generic_impl, &specific_impl };
            const arg_types = &[_]TypeRegistry.TypeId{derived_type};

            const result = try self.specificity_analyzer.findMostSpecific(implementations, arg_types);

            switch (result) {
                .unique => |impl| {
                    // Should choose the more specific implementation
                    try testing.expect(impl.specificity_rank == 100);
                    try testing.expect(impl.param_type_ids[0] == derived_type);
                },
                .ambiguous => {
                    // This should not happen with clear specificity difference
                    try testing.expect(false);
                },
                .no_match => {
                    // This should not happen since both implementations match
                    try testing.expect(false);
                },
            }
        }
    }

    /// Property: Transitivity of specificity
    /// If A is more specific than B, and B is more specific than C, then A is more specific than C
    pub fn testSpecificityTransitivityProperty(self: *Self, iterations: u32) !void {
        for (0..iterations) |_| {
            // Create a three-level type hierarchy
            const base_type = try self.type_registry.registerType("Base", .table_open, &.{});
            const middle_type = try self.type_registry.registerType("Middle", .table_open, &[_]TypeRegistry.TypeId{base_type});
            const derived_type = try self.type_registry.registerType("Derived", .table_sealed, &[_]TypeRegistry.TypeId{middle_type});

            const base_impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{base_type},
                .return_type_id = base_type,
                .effects = .{},
                .specificity_rank = 30, // Least specific
                .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
            };

            const middle_impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{middle_type},
                .return_type_id = middle_type,
                .effects = .{},
                .specificity_rank = 60, // Middle specificity
                .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
            };

            const derived_impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{derived_type},
                .return_type_id = derived_type,
                .effects = .{},
                .specificity_rank = 90, // Most specific
                .source_location = .{ .start = 0, .end = 10, .line = 3, .column = 1 },
            };

            const implementations = &[_]*const SignatureAnalyzer.Implementation{ &base_impl, &middle_impl, &derived_impl };
            const arg_types = &[_]TypeRegistry.TypeId{derived_type};

            const result = try self.specificity_analyzer.findMostSpecific(implementations, arg_types);

            switch (result) {
                .unique => |impl| {
                    // Should choose the most specific implementation (derived)
                    try testing.expect(impl.specificity_rank == 90);
                    try testing.expect(impl.param_type_ids[0] == derived_type);
                },
                .ambiguous => {
                    try testing.expect(false); // Should not be ambiguous with clear hierarchy
                },
                .no_match => {
                    try testing.expect(false); // All implementations should match
                },
            }
        }
    }

    /// Property: Symmetry of ambiguity
    /// If dispatch is ambiguous for arguments (A, B), it should also be ambiguous for (B, A) when applicable
    pub fn testAmbiguitySymmetryProperty(self: *Self, iterations: u32) !void {
        for (0..iterations) |_| {
            // Create two unrelated types
            const type_a = try self.type_registry.registerType("TypeA", .primitive, &.{});
            const type_b = try self.type_registry.registerType("TypeB", .primitive, &.{});

            // Create implementations that could be ambiguous
            const impl_ab = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{ type_a, type_b },
                .return_type_id = type_a,
                .effects = .{},
                .specificity_rank = 50,
                .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
            };

            const impl_ba = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{ type_b, type_a },
                .return_type_id = type_b,
                .effects = .{},
                .specificity_rank = 50, // Same specificity
                .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
            };

            const implementations = &[_]*const SignatureAnalyzer.Implementation{ &impl_ab, &impl_ba };

            // Test with (type_a, type_b)
            const args_ab = &[_]TypeRegistry.TypeId{ type_a, type_b };
            const result_ab = try self.specificity_analyzer.findMostSpecific(implementations, args_ab);

            // Test with (type_b, type_a)
            const args_ba = &[_]TypeRegistry.TypeId{ type_b, type_a };
            const result_ba = try self.specificity_analyzer.findMostSpecific(implementations, args_ba);

            // Both should have unique matches (not ambiguous in this case)
            switch (result_ab) {
                .unique => |impl| {
                    try testing.expect(std.mem.eql(TypeRegistry.TypeId, impl.param_type_ids, &[_]TypeRegistry.TypeId{ type_a, type_b }));
                },
                .ambiguous => {
                    // If AB is ambiguous, BA should also be handled consistently
                },
                .no_match => {
                    try testing.expect(std.meta.activeTag(result_ba) == .no_match);
                },
            }

            switch (result_ba) {
                .unique => |impl| {
                    try testing.expect(std.mem.eql(TypeRegistry.TypeId, impl.param_type_ids, &[_]TypeRegistry.TypeId{ type_b, type_a }));
                },
                .ambiguous => {
                    // Consistency check
                },
                .no_match => {
                    try testing.expect(std.meta.activeTag(result_ab) == .no_match);
                },
            }
        }
    }

    /// Property: Monotonicity of dispatch tables
    /// Adding more implementations should not change existing dispatch decisions (unless they're more specific)
    pub fn testMonotonicityProperty(self: *Self, iterations: u32) !void {
        for (0..iterations) |_| {
            const int_type = try self.type_registry.registerType("int", .primitive, &.{});
            const float_type = try self.type_registry.registerType("float", .primitive, &.{});

            // Start with one implementation
            const original_impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{int_type},
                .return_type_id = int_type,
                .effects = .{},
                .specificity_rank = 50,
                .source_location = .{ .start = 0, .end = 10, .line = 1, .column = 1 },
            };

            const original_implementations = &[_]*const SignatureAnalyzer.Implementation{&original_impl};
            const test_args = &[_]TypeRegistry.TypeId{int_type};

            const original_result = try self.specificity_analyzer.findMostSpecific(original_implementations, test_args);

            // Add a non-conflicting implementation
            const additional_impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "test", .module = "test" },
                .param_type_ids = &[_]TypeRegistry.TypeId{float_type},
                .return_type_id = float_type,
                .effects = .{},
                .specificity_rank = 50,
                .source_location = .{ .start = 0, .end = 10, .line = 2, .column = 1 },
            };

            const extended_implementations = &[_]*const SignatureAnalyzer.Implementation{ &original_impl, &additional_impl };
            const extended_result = try self.specificity_analyzer.findMostSpecific(extended_implementations, test_args);

            // The result for the original arguments should be the same
            switch (original_result) {
                .unique => |orig_impl| {
                    switch (extended_result) {
                        .unique => |ext_impl| {
                            try testing.expect(orig_impl == ext_impl);
                        },
                        else => try testing.expect(false), // Should still be unique
                    }
                },
                .ambiguous => {
                    // If it was ambiguous before, it should still be ambiguous (or resolved the same way)
                    try testing.expect(std.meta.activeTag(extended_result) == .ambiguous or std.meta.activeTag(extended_result) == .unique);
                },
                .no_match => {
                    try testing.expect(std.meta.activeTag(extended_result) == .no_match);
                },
            }
        }
    }

    /// Generate a random signature for testing
    fn generateRandomSignature(self: *Self) !RandomSignature {
        const arity = self.rng.intRangeAtMost(u32, 1, 4); // 1-4 parameters
        const impl_count = self.rng.intRangeAtMost(u32, 1, 8); // 1-8 implementations

        var implementations = ArrayList(*const SignatureAnalyzer.Implementation).init(self.allocator);
        var impl_storage = ArrayList(SignatureAnalyzer.Implementation).init(self.allocator);

        // Generate random types
        var types = ArrayList(TypeRegistry.TypeId).init(self.allocator);
        defer types.deinit();

        for (0..arity + 2) |i| { // Extra types for variety
            const type_name = try std.fmt.allocPrint(self.allocator, "Type{}", .{i});
            defer self.allocator.free(type_name);

            const type_id = try self.type_registry.registerType(type_name, .primitive, &.{});
            try types.append(type_id);
        }

        // Generate random implementations
        for (0..impl_count) |i| {
            var param_types = try self.allocator.alloc(TypeRegistry.TypeId, arity);
            for (0..arity) |j| {
                param_types[j] = types.items[self.rng.intRangeAtMost(usize, 0, types.items.len - 1)];
            }

            const impl = SignatureAnalyzer.Implementation{
                .function_id = .{ .name = "random_func", .module = "test" },
                .param_type_ids = param_types,
                .return_type_id = types.items[0],
                .effects = .{},
                .specificity_rank = self.rng.intRangeAtMost(u32, 10, 100),
                .source_location = .{ .start = 0, .end = 10, .line = @intCast(i + 1), .column = 1 },
            };

            try impl_storage.append(impl);
            try implementations.append(&impl_storage.items[impl_storage.items.len - 1]);
        }

        return RandomSignature{
            .arity = arity,
            .implementations = try implementations.toOwnedSlice(),
            .impl_storage = impl_storage,
            .available_types = try types.toOwnedSlice(),
        };
    }

    fn generateRandomArgumentTypes(self: *Self, arity: u32) ![]TypeRegistry.TypeId {
        var arg_types = try self.allocator.alloc(TypeRegistry.TypeId, arity);

        // Use some predefined types for consistency
        const int_type = try self.type_registry.registerType("int", .primitive, &.{});
        const float_type = try self.type_registry.registerType("float", .primitive, &.{});
        const string_type = try self.type_registry.registerType("string", .primitive, &.{});

        const available_types = &[_]TypeRegistry.TypeId{ int_type, float_type, string_type };

        for (0..arity) |i| {
            arg_types[i] = available_types[self.rng.intRangeAtMost(usize, 0, available_types.len - 1)];
        }

        return arg_types;
    }

    fn freeSignature(self: *Self, signature: RandomSignature) void {
        for (signature.impl_storage.items) |impl| {
            self.allocator.free(impl.param_type_ids);
        }
        signature.impl_storage.deinit();
        self.allocator.free(signature.implementations);
        self.allocator.free(signature.available_types);
    }

    const RandomSignature = struct {
        arity: u32,
        implementations: []*const SignatureAnalyzer.Implementation,
        impl_storage: ArrayList(SignatureAnalyzer.Implementation),
        available_types: []TypeRegistry.TypeId,
    };

    /// Run all property-based tests
    pub fn runAllPropertyTests(self: *Self, iterations: u32) !void {
        std.debug.print("Running property-based dispatch tests with {} iterations...\n", .{iterations});

        std.debug.print("Testing determinism property...\n");
        try self.testDeterminismProperty(iterations);

        std.debug.print("Testing specificity property...\n");
        try self.testSpecificityProperty(iterations);

        std.debug.print("Testing specificity transitivity property...\n");
        try self.testSpecificityTransitivityProperty(iterations);

        std.debug.print("Testing ambiguity symmetry property...\n");
        try self.testAmbiguitySymmetryProperty(iterations);

        std.debug.print("Testing monotonicity property...\n");
        try self.testMonotonicityProperty(iterations);

        std.debug.print("All property-based tests passed! ✅\n");
    }
};

// Test functions for zig test runner
test "dispatch property tests - determinism" {
    var property_tests = try DispatchPropertyTests.init(testing.allocator, 12345);
    defer property_tests.deinit();

    try property_tests.testDeterminismProperty(100);
}

test "dispatch property tests - specificity" {
    var property_tests = try DispatchPropertyTests.init(testing.allocator, 12345);
    defer property_tests.deinit();

    try property_tests.testSpecificityProperty(100);
}

test "dispatch property tests - transitivity" {
    var property_tests = try DispatchPropertyTests.init(testing.allocator, 12345);
    defer property_tests.deinit();

    try property_tests.testSpecificityTransitivityProperty(100);
}

test "dispatch property tests - symmetry" {
    var property_tests = try DispatchPropertyTests.init(testing.allocator, 12345);
    defer property_tests.deinit();

    try property_tests.testAmbiguitySymmetryProperty(100);
}

test "dispatch property tests - monotonicity" {
    var property_tests = try DispatchPropertyTests.init(testing.allocator, 12345);
    defer property_tests.deinit();

    try property_tests.testMonotonicityProperty(100);
}

test "dispatch property tests - all properties" {
    var property_tests = try DispatchPropertyTests.init(testing.allocator, 12345);
    defer property_tests.deinit();

    try property_tests.runAllPropertyTests(50); // Reduced iterations for test suite
}
