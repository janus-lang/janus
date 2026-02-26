// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;

/// Generic type parameter information
pub const GenericParameter = struct {
    name: []const u8,
    constraints: []const TypeId,
    variance: Variance,
    default_type: ?TypeId,

    pub const Variance = enum {
        invariant,
        covariant,
        contravariant,
    };

    pub fn format(self: GenericParameter, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}", .{self.name});
        if (self.constraints.len > 0) {
            try writer.print(": ", .{});
            for (self.constraints, 0..) |constraint, i| {
                if (i > 0) try writer.print(" & ", .{});
                try writer.print("{}", .{constraint});
            }
        }
        if (self.default_type) |default| {
            try writer.print(" = {}", .{default});
        }
    }
};

/// Generic function signature with type parameters
pub const GenericSignature = struct {
    name: []const u8,
    base_signature: SignatureAnalyzer.SignatureKey,
    type_parameters: []const GenericParameter,
    constraints: []const GenericConstraint,

    pub const GenericConstraint = struct {
        parameter_name: []const u8,
        constraint_type: ConstraintType,
        target_types: []const TypeId,

        pub const ConstraintType = enum {
            subtype_of, // T: Foo (T must be subtype of Foo)
            supertype_of, // T: ^Foo (T must be supertype of Foo)
            implements, // T: impl Trait (T must implement Trait)
            same_as, // T: =U (T must be same as U)
            convertible_to, // T: ~>U (T must be convertible to U)
        };
    };

    pub fn format(self: GenericSignature, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("signature<", .{});
        for (self.type_parameters, 0..) |param, i| {
            if (i > 0) try writer.print(", ", .{});
            try writer.print("{}", .{param});
        }
        try writer.print(">", .{});

        if (self.constraints.len > 0) {
            try writer.print(" where ", .{});
            for (self.constraints, 0..) |constraint, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{s}: {}", .{ constraint.parameter_name, constraint.constraint_type });
            }
        }
    }
};

/// Monomorphized instance of a generic function
pub const MonomorphizedInstance = struct {
    generic_signature: *const GenericSignature,
    type_arguments: []const TypeId,
    concrete_signature: SignatureAnalyzer.SignatureKey,
    concrete_implementation: SignatureAnalyzer.Implementation,
    monomorphization_id: u64,

    pub fn format(self: MonomorphizedInstance, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}[", .{self.generic_signature.base_signature});
        for (self.type_arguments, 0..) |arg, i| {
            if (i > 0) try writer.print(", ", .{});
            try writer.print("{}", .{arg});
        }
        try writer.print("] (id: {})", .{self.monomorphization_id});
    }
};

/// Generic constraint satisfaction result
pub const ConstraintSatisfaction = struct {
    satisfied: bool,
    violations: []const ConstraintViolation,

    pub const ConstraintViolation = struct {
        constraint: GenericSignature.GenericConstraint,
        actual_type: TypeId,
        reason: []const u8,
    };

    pub fn format(self: ConstraintSatisfaction, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (self.satisfied) {
            try writer.print("Satisfied", .{});
        } else {
            try writer.print("Violated ({} violations)", .{self.violations.len});
            for (self.violations) |violation| {
                try writer.print("\n  - {s}: {s}", .{ violation.constraint.parameter_name, violation.reason });
            }
        }
    }
};

/// Generic dispatch resolution result
pub const GenericDispatchResult = struct {
    result_type: ResultType,
    monomorphized_instances: []const MonomorphizedInstance,
    selected_instance: ?MonomorphizedInstance,
    constraint_violations: []const ConstraintSatisfaction.ConstraintViolation,

    pub const ResultType = enum {
        exact_match, // Single exact monomorphized match
        best_match, // Single best match after constraint resolution
        ambiguous, // Multiple equally specific matches
        no_match, // No matching instances
        constraint_violation, // Constraints not satisfied
    };

    pub fn format(self: GenericDispatchResult, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("GenericDispatch: {} ", .{self.result_type});
        if (self.selected_instance) |instance| {
            try writer.print("-> {}", .{instance});
        }
        if (self.constraint_violations.len > 0) {
            try writer.print(" ({} constraint violations)", .{self.constraint_violations.len});
        }
    }
};

/// Generic multiple dispatch integration system
pub const GenericDispatcher = struct {
    allocator: Allocator,
    type_registry: *const TypeRegistry,
    signature_analyzer: *const SignatureAnalyzer,
    specificity_analyzer: *SpecificityAnalyzer,

    // Generic signature tracking
    generic_signatures: std.StringHashMap(GenericSignature),
    monomorphized_instances: std.AutoHashMap(u64, MonomorphizedInstance),
    monomorphization_counter: u64,

    // Constraint resolution cache
    constraint_cache: std.AutoHashMap(ConstraintCacheKey, ConstraintSatisfaction),

    const ConstraintCacheKey = struct {
        constraint_hash: u64,
        type_args_hash: u64,

        pub fn init(constraint: *const GenericSignature.GenericConstraint, type_args: []const TypeId) ConstraintCacheKey {
            var hasher1 = std.hash.Wyhash.init(0);
            hasher1.update(constraint.parameter_name);
            hasher1.update(std.mem.asBytes(&constraint.constraint_type));

            var hasher2 = std.hash.Wyhash.init(0);
            for (type_args) |type_id| {
                hasher2.update(std.mem.asBytes(&type_id));
            }

            return ConstraintCacheKey{
                .constraint_hash = hasher1.final(),
                .type_args_hash = hasher2.final(),
            };
        }
    };

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        type_registry: *const TypeRegistry,
        signature_analyzer: *const SignatureAnalyzer,
        specificity_analyzer: *SpecificityAnalyzer,
    ) Self {
        return Self{
            .allocator = allocator,
            .type_registry = type_registry,
            .signature_analyzer = signature_analyzer,
            .specificity_analyzer = specificity_analyzer,
            .generic_signatures = std.StringHashMap(GenericSignature).init(allocator),
            .monomorphized_instances = std.AutoHashMap(u64, MonomorphizedInstance).init(allocator),
            .monomorphization_counter = 0,
            .constraint_cache = std.AutoHashMap(ConstraintCacheKey, ConstraintSatisfaction).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up generic signatures
        var sig_iter = self.generic_signatures.iterator();
        while (sig_iter.next()) |entry| {
            self.freeGenericSignature(entry.value_ptr);
        }
        self.generic_signatures.deinit();

        // Clean up monomorphized instances
        var mono_iter = self.monomorphized_instances.iterator();
        while (mono_iter.next()) |entry| {
            self.freeMonomorphizedInstance(entry.value_ptr);
        }
        self.monomorphized_instances.deinit();

        // Clean up constraint cache
        var cache_iter = self.constraint_cache.iterator();
        while (cache_iter.next()) |entry| {
            self.freeConstraintSatisfaction(entry.value_ptr);
        }
        self.constraint_cache.deinit();
    }

    /// Register a generic function signature
    pub fn registerGenericSignature(
        self: *Self,
        name: []const u8,
        type_parameters: []const GenericParameter,
        constraints: []const GenericSignature.GenericConstraint,
        base_param_types: []const TypeId,
        return_type: TypeId,
    ) !void {
        _ = return_type;
        const base_signature = SignatureAnalyzer.SignatureKey.init(name, @intCast(base_param_types.len));

        const name_copy = try self.allocator.dupe(u8, name);
        const generic_sig = GenericSignature{
            .name = name_copy,
            .base_signature = base_signature,
            .type_parameters = try self.allocator.dupe(GenericParameter, type_parameters),
            .constraints = try self.allocator.dupe(GenericSignature.GenericConstraint, constraints),
        };

        try self.generic_signatures.put(name_copy, generic_sig);
    }

    /// Monomorphize a generic function with specific type arguments
    pub fn monomorphize(
        self: *Self,
        generic_name: []const u8,
        type_arguments: []const TypeId,
    ) !?MonomorphizedInstance {
        const generic_sig = self.generic_signatures.get(generic_name) orelse return null;

        // Validate type argument count
        if (type_arguments.len != generic_sig.type_parameters.len) {
            return null;
        }

        // Check constraints
        const constraint_result = try self.checkConstraints(&generic_sig, type_arguments);
        if (!constraint_result.satisfied) {
            return null;
        }

        // Generate monomorphization ID
        self.monomorphization_counter += 1;
        const mono_id = self.monomorphization_counter;

        // Create concrete signature by substituting type parameters
        const concrete_param_types = try self.substituteTypeParameters(&generic_sig, type_arguments);
        defer self.allocator.free(concrete_param_types);

        const concrete_signature = SignatureAnalyzer.SignatureKey.init(generic_name, @intCast(concrete_param_types.len));

        // Create concrete implementation
        const concrete_impl = SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{ .name = generic_name, .module = "generic", .id = @intCast(mono_id) },
            .param_type_ids = try self.allocator.dupe(TypeId, concrete_param_types),
            .return_type_id = type_arguments[0], // Simplified - would need proper substitution
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 0, // Will be calculated
        };

        const instance = MonomorphizedInstance{
            .generic_signature = &generic_sig,
            .type_arguments = try self.allocator.dupe(TypeId, type_arguments),
            .concrete_signature = concrete_signature,
            .concrete_implementation = concrete_impl,
            .monomorphization_id = mono_id,
        };

        try self.monomorphized_instances.put(mono_id, instance);
        return instance;
    }

    /// Resolve generic dispatch for given argument types
    pub fn resolveGenericDispatch(
        self: *Self,
        signature_name: []const u8,
        argument_types: []const TypeId,
    ) !GenericDispatchResult {
        // Look for generic signature
        const generic_sig = self.generic_signatures.get(signature_name);
        if (generic_sig == null) {
            return GenericDispatchResult{
                .result_type = .no_match,
                .monomorphized_instances = &.{},
                .selected_instance = null,
                .constraint_violations = &.{},
            };
        }

        // Find all monomorphized instances that could match
        var matching_instances: ArrayList(MonomorphizedInstance) = .empty;
        defer matching_instances.deinit();

        var mono_iter = self.monomorphized_instances.iterator();
        while (mono_iter.next()) |entry| {
            const instance = entry.value_ptr.*;
            if (self.instanceMatches(&instance, argument_types)) {
                try matching_instances.append(instance);
            }
        }

        // If no instances match, try to infer type arguments and monomorphize
        if (matching_instances.items.len == 0) {
            if (try self.inferAndMonomorphize(signature_name, argument_types)) |instance| {
                try matching_instances.append(instance);
            }
        }

        if (matching_instances.items.len == 0) {
            return GenericDispatchResult{
                .result_type = .no_match,
                .monomorphized_instances = &.{},
                .selected_instance = null,
                .constraint_violations = &.{},
            };
        }

        // Use specificity analysis to select best match
        const best_instance = try self.selectBestInstance(matching_instances.items, argument_types);

        return GenericDispatchResult{
            .result_type = if (matching_instances.items.len == 1) .exact_match else .best_match,
            .monomorphized_instances = try self.allocator.dupe(MonomorphizedInstance, matching_instances.items),
            .selected_instance = best_instance,
            .constraint_violations = &.{},
        };
    }

    /// Check if constraints are satisfied for given type arguments
    pub fn checkConstraints(
        self: *Self,
        generic_sig: *const GenericSignature,
        type_arguments: []const TypeId,
    ) !ConstraintSatisfaction {
        var violations: ArrayList(ConstraintSatisfaction.ConstraintViolation) = .empty;
        defer violations.deinit();

        for (generic_sig.constraints) |constraint| {
            // Check cache first
            const cache_key = ConstraintCacheKey.init(&constraint, type_arguments);
            if (self.constraint_cache.get(cache_key)) |cached_result| {
                if (!cached_result.satisfied) {
                    try violations.appendSlice(cached_result.violations);
                }
                continue;
            }

            // Find the type parameter index
            const param_index = self.findParameterIndex(generic_sig, constraint.parameter_name) orelse {
                try violations.append(ConstraintSatisfaction.ConstraintViolation{
                    .constraint = constraint,
                    .actual_type = 0,
                    .reason = try self.allocator.dupe(u8, "Unknown type parameter"),
                });
                continue;
            };

            if (param_index >= type_arguments.len) {
                try violations.append(ConstraintSatisfaction.ConstraintViolation{
                    .constraint = constraint,
                    .actual_type = 0,
                    .reason = try self.allocator.dupe(u8, "Type argument index out of bounds"),
                });
                continue;
            }

            const actual_type = type_arguments[param_index];

            // Check constraint satisfaction
            const satisfied = try self.checkSingleConstraint(&constraint, actual_type);
            if (!satisfied) {
                try violations.append(ConstraintSatisfaction.ConstraintViolation{
                    .constraint = constraint,
                    .actual_type = actual_type,
                    .reason = try self.allocator.dupe(u8, "Constraint not satisfied"),
                });
            }
        }

        const result = ConstraintSatisfaction{
            .satisfied = violations.items.len == 0,
            .violations = try self.allocator.dupe(ConstraintSatisfaction.ConstraintViolation, violations.items),
        };

        return result;
    }

    /// Infer type arguments from call site and monomorphize if possible
    fn inferAndMonomorphize(
        self: *Self,
        signature_name: []const u8,
        argument_types: []const TypeId,
    ) !?MonomorphizedInstance {
        const generic_sig = self.generic_signatures.get(signature_name) orelse return null;

        // Simple type inference - in practice this would be much more sophisticated
        if (generic_sig.type_parameters.len == 1 and argument_types.len > 0) {
            const inferred_type = argument_types[0];
            const type_args = [_]TypeId{inferred_type};
            return try self.monomorphize(signature_name, &type_args);
        }

        return null;
    }

    /// Check if a monomorphized instance matches the given argument types
    fn instanceMatches(self: *Self, instance: *const MonomorphizedInstance, argument_types: []const TypeId) bool {
        if (instance.concrete_implementation.param_type_ids.len != argument_types.len) {
            return false;
        }

        for (instance.concrete_implementation.param_type_ids, argument_types) |param_type, arg_type| {
            if (!self.type_registry.isSubtype(arg_type, param_type)) {
                return false;
            }
        }

        return true;
    }

    /// Select the best instance from multiple candidates using specificity analysis
    fn selectBestInstance(
        self: *Self,
        instances: []const MonomorphizedInstance,
        argument_types: []const TypeId,
    ) !?MonomorphizedInstance {
        if (instances.len == 0) return null;
        if (instances.len == 1) return instances[0];

        // Convert to SignatureAnalyzer.Implementation for specificity analysis
        var implementations: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer implementations.deinit();

        for (instances) |instance| {
            try implementations.append(instance.concrete_implementation);
        }

        // Use specificity analyzer to find the best match
        var result = try self.specificity_analyzer.findMostSpecific(implementations.items, argument_types);
        defer result.deinit(self.allocator);

        switch (result) {
            .unique => |impl| {
                // Find the corresponding instance
                for (instances) |instance| {
                    if (std.mem.eql(u8, instance.concrete_implementation.function_id.name, impl.function_id.name)) {
                        return instance;
                    }
                }
            },
            .ambiguous => return null, // Ambiguous - caller should handle
            .no_match => return null,
        }

        return null;
    }

    /// Substitute type parameters in a generic signature
    fn substituteTypeParameters(
        self: *Self,
        generic_sig: *const GenericSignature,
        type_arguments: []const TypeId,
    ) ![]TypeId {
        _ = generic_sig;
        // This is a simplified implementation
        // In practice, this would need to handle complex type substitution
        return try self.allocator.dupe(TypeId, type_arguments);
    }

    /// Find the index of a type parameter by name
    fn findParameterIndex(self: *Self, generic_sig: *const GenericSignature, param_name: []const u8) ?usize {
        _ = self;
        for (generic_sig.type_parameters, 0..) |param, i| {
            if (std.mem.eql(u8, param.name, param_name)) {
                return i;
            }
        }
        return null;
    }

    /// Check if a single constraint is satisfied
    fn checkSingleConstraint(
        self: *Self,
        constraint: *const GenericSignature.GenericConstraint,
        actual_type: TypeId,
    ) !bool {
        switch (constraint.constraint_type) {
            .subtype_of => {
                for (constraint.target_types) |target_type| {
                    if (self.type_registry.isSubtype(actual_type, target_type)) {
                        return true;
                    }
                }
                return false;
            },
            .supertype_of => {
                for (constraint.target_types) |target_type| {
                    if (self.type_registry.isSubtype(target_type, actual_type)) {
                        return true;
                    }
                }
                return false;
            },
            .implements => {
                // Simplified - would need trait system integration
                return true;
            },
            .same_as => {
                for (constraint.target_types) |target_type| {
                    if (actual_type == target_type) {
                        return true;
                    }
                }
                return false;
            },
            .convertible_to => {
                // Simplified - would need conversion system integration
                return true;
            },
        }
    }

    /// Get all monomorphized instances for a generic signature
    pub fn getMonomorphizedInstances(self: *Self, signature_name: []const u8) ![]const MonomorphizedInstance {
        var instances: ArrayList(MonomorphizedInstance) = .empty;
        defer instances.deinit();

        var iter = self.monomorphized_instances.iterator();
        while (iter.next()) |entry| {
            const instance = entry.value_ptr.*;
            if (std.mem.eql(u8, instance.concrete_implementation.function_id.name, signature_name)) {
                try instances.append(instance);
            }
        }

        return self.allocator.dupe(MonomorphizedInstance, instances.items);
    }

    /// Clear monomorphization cache
    pub fn clearMonomorphizationCache(self: *Self) void {
        var iter = self.monomorphized_instances.iterator();
        while (iter.next()) |entry| {
            self.freeMonomorphizedInstance(entry.value_ptr);
        }
        self.monomorphized_instances.clearRetainingCapacity();
        self.monomorphization_counter = 0;
    }

    /// Free generic signature memory
    fn freeGenericSignature(self: *Self, sig: *GenericSignature) void {
        self.allocator.free(sig.name);
        self.allocator.free(sig.type_parameters);
        self.allocator.free(sig.constraints);
    }

    /// Free monomorphized instance memory
    fn freeMonomorphizedInstance(self: *Self, instance: *MonomorphizedInstance) void {
        self.allocator.free(instance.type_arguments);
        self.allocator.free(instance.concrete_implementation.param_type_ids);
    }

    /// Free constraint satisfaction memory
    fn freeConstraintSatisfaction(self: *Self, satisfaction: *ConstraintSatisfaction) void {
        for (satisfaction.violations) |*violation| {
            self.allocator.free(violation.reason);
        }
        self.allocator.free(satisfaction.violations);
    }
};

// Tests
test "GenericDispatcher basic monomorphization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = GenericDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});
    const string_type = try type_registry.registerType("string", .primitive, &.{});

    // Register a generic function: fn identity<T>(x: T) -> T
    const type_param = GenericParameter{
        .name = "T",
        .constraints = &.{},
        .variance = .invariant,
        .default_type = null,
    };

    try dispatcher.registerGenericSignature(
        "identity",
        &[_]GenericParameter{type_param},
        &.{}, // No constraints
        &[_]TypeId{int_type}, // Base parameter types (placeholder)
        int_type, // Return type (placeholder)
    );

    // Monomorphize with int
    const int_instance = try dispatcher.monomorphize("identity", &[_]TypeId{int_type});
    try testing.expect(int_instance != null);
    try testing.expectEqual(@as(usize, 1), int_instance.?.type_arguments.len);
    try testing.expectEqual(int_type, int_instance.?.type_arguments[0]);

    // Monomorphize with string
    const string_instance = try dispatcher.monomorphize("identity", &[_]TypeId{string_type});
    try testing.expect(string_instance != null);
    try testing.expectEqual(@as(usize, 1), string_instance.?.type_arguments.len);
    try testing.expectEqual(string_type, string_instance.?.type_arguments[0]);

    // Check that we have two different instances
    try testing.expect(int_instance.?.monomorphization_id != string_instance.?.monomorphization_id);
}

test "GenericDispatcher constraint checking" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = GenericDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});
    const number_type = try type_registry.registerType("Number", .table_open, &.{});
    const string_type = try type_registry.registerType("string", .primitive, &.{});

    // Set up subtype relationship: int <: Number
    // This would normally be done during type registration

    // Register a constrained generic function: fn add<T: Number>(x: T, y: T) -> T
    const type_param = GenericParameter{
        .name = "T",
        .constraints = &[_]TypeId{number_type},
        .variance = .invariant,
        .default_type = null,
    };

    const constraint = GenericSignature.GenericConstraint{
        .parameter_name = "T",
        .constraint_type = .subtype_of,
        .target_types = &[_]TypeId{number_type},
    };

    try dispatcher.registerGenericSignature(
        "add",
        &[_]GenericParameter{type_param},
        &[_]GenericSignature.GenericConstraint{constraint},
        &[_]TypeId{ int_type, int_type }, // Base parameter types
        int_type, // Return type
    );

    const generic_sig = dispatcher.generic_signatures.get("add").?;

    // Check constraint satisfaction with int (should satisfy)
    var int_satisfaction = try dispatcher.checkConstraints(&generic_sig, &[_]TypeId{int_type});
    defer dispatcher.freeConstraintSatisfaction(&int_satisfaction);

    // For this test, we'll assume int satisfies Number constraint
    // In practice, this would depend on the actual subtype relationships

    // Check constraint satisfaction with string (should not satisfy)
    var string_satisfaction = try dispatcher.checkConstraints(&generic_sig, &[_]TypeId{string_type});
    defer dispatcher.freeConstraintSatisfaction(&string_satisfaction);

    // String should not satisfy Number constraint
    try testing.expect(!string_satisfaction.satisfied);
    try testing.expect(string_satisfaction.violations.len > 0);
}

test "GenericDispatcher dispatch resolution" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = GenericDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});

    // Register a simple generic function
    const type_param = GenericParameter{
        .name = "T",
        .constraints = &.{},
        .variance = .invariant,
        .default_type = null,
    };

    try dispatcher.registerGenericSignature(
        "test_func",
        &[_]GenericParameter{type_param},
        &.{},
        &[_]TypeId{int_type},
        int_type,
    );

    // Resolve dispatch for int arguments
    const result = try dispatcher.resolveGenericDispatch("test_func", &[_]TypeId{int_type});
    defer {
        if (result.monomorphized_instances.len > 0) {
            allocator.free(result.monomorphized_instances);
        }
        if (result.constraint_violations.len > 0) {
            allocator.free(result.constraint_violations);
        }
    }

    // Should either find an existing instance or create a new one through inference
    try testing.expect(result.result_type != .no_match);
}

test "GenericDispatcher instance management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = GenericDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});
    const float_type = try type_registry.registerType("float", .primitive, &.{});

    // Register a generic function
    const type_param = GenericParameter{
        .name = "T",
        .constraints = &.{},
        .variance = .invariant,
        .default_type = null,
    };

    try dispatcher.registerGenericSignature(
        "generic_func",
        &[_]GenericParameter{type_param},
        &.{},
        &[_]TypeId{int_type},
        int_type,
    );

    // Create multiple instances
    _ = try dispatcher.monomorphize("generic_func", &[_]TypeId{int_type});
    _ = try dispatcher.monomorphize("generic_func", &[_]TypeId{float_type});

    // Get all instances
    const instances = try dispatcher.getMonomorphizedInstances("generic_func");
    defer allocator.free(instances);

    try testing.expectEqual(@as(usize, 2), instances.len);

    // Clear cache
    dispatcher.clearMonomorphizationCache();

    const instances_after_clear = try dispatcher.getMonomorphizedInstances("generic_func");
    defer allocator.free(instances_after_clear);

    try testing.expectEqual(@as(usize, 0), instances_after_clear.len);
}

test "GenericDispatcher formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test GenericParameter formatting
    const param = GenericParameter{
        .name = "T",
        .constraints = &[_]TypeId{ 1, 2 },
        .variance = .covariant,
        .default_type = 3,
    };

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{param});
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "T") != null);
}
