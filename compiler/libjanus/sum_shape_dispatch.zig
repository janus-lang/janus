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

/// Sum type variant information
pub const SumVariant = struct {
    name: []const u8,
    type_id: TypeId,
    tag_value: u32,
    payload_type: ?TypeId,

    pub fn format(self: SumVariant, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}({})", .{ self.name, self.type_id });
        if (self.payload_type) |payload| {
            try writer.print(" -> {}", .{payload});
        }
    }
};

/// Sum type definition
pub const SumType = struct {
    type_id: TypeId,
    name: []const u8,
    variants: []const SumVariant,
    is_closed: bool,
    exhaustive_check_required: bool,

    pub fn format(self: SumType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("sum {s} = ", .{self.name});
        for (self.variants, 0..) |variant, i| {
            if (i > 0) try writer.print(" | ", .{});
            try writer.print("{}", .{variant});
        }
        if (self.is_closed) {
            try writer.print(" (closed)", .{});
        }
    }
};

/// Shape type field information
pub const ShapeField = struct {
    name: []const u8,
    type_id: TypeId,
    is_required: bool,
    default_value: ?[]const u8,

    pub fn format(self: ShapeField, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (!self.is_required) try writer.print("?", .{});
        try writer.print("{s}: {}", .{ self.name, self.type_id });
        if (self.default_value) |default| {
            try writer.print(" = {s}", .{default});
        }
    }
};

/// Shape type definition
pub const ShapeType = struct {
    type_id: TypeId,
    name: []const u8,
    fields: []const ShapeField,
    is_open: bool,
    structural_compatibility: bool,

    pub fn format(self: ShapeType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("shape {s} {{ ", .{self.name});
        for (self.fields, 0..) |field, i| {
            if (i > 0) try writer.print(", ", .{});
            try writer.print("{}", .{field});
        }
        try writer.writeAll(" }");
        if (self.is_open) {
            try writer.print(" (open)", .{});
        }
    }
};

/// Sum type dispatch pattern
pub const SumDispatchPattern = struct {
    sum_type: TypeId,
    variant_patterns: []const VariantPattern,
    is_exhaustive: bool,

    pub const VariantPattern = struct {
        variant_name: []const u8,
        variant_type: TypeId,
        implementation: *const SignatureAnalyzer.Implementation,
        payload_binding: ?[]const u8,
    };

    pub fn format(self: SumDispatchPattern, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("match {} {{ ", .{self.sum_type});
        for (self.variant_patterns, 0..) |pattern, i| {
            if (i > 0) try writer.print(", ", .{});
            try writer.print("{s}", .{pattern.variant_name});
            if (pattern.payload_binding) |binding| {
                try writer.print("({s})", .{binding});
            }
        }
        try writer.writeAll(" }");
        if (self.is_exhaustive) {
            try writer.print(" (exhaustive)", .{});
        }
    }
};

/// Shape compatibility result
pub const ShapeCompatibility = struct {
    compatible: bool,
    missing_fields: []const []const u8,
    extra_fields: []const []const u8,
    type_mismatches: []const FieldTypeMismatch,

    pub const FieldTypeMismatch = struct {
        field_name: []const u8,
        expected_type: TypeId,
        actual_type: TypeId,
    };

    pub fn format(self: ShapeCompatibility, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (self.compatible) {
            try writer.print("Compatible", .{});
        } else {
            try writer.print("Incompatible", .{});
            if (self.missing_fields.len > 0) {
                try writer.print(" (missing: ", .{});
                for (self.missing_fields, 0..) |field, i| {
                    if (i > 0) try writer.print(", ", .{});
                    try writer.print("{s}", .{field});
                }
                try writer.print(")", .{});
            }
            if (self.type_mismatches.len > 0) {
                try writer.print(" (type mismatches: {})", .{self.type_mismatches.len});
            }
        }
    }
};

/// Exhaustiveness check result
pub const ExhaustivenessCheck = struct {
    is_exhaustive: bool,
    missing_variants: []const SumVariant,
    unreachable_patterns: []const SumDispatchPattern.VariantPattern,

    pub fn format(self: ExhaustivenessCheck, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (self.is_exhaustive) {
            try writer.print("Exhaustive", .{});
        } else {
            try writer.print("Non-exhaustive", .{});
            if (self.missing_variants.len > 0) {
                try writer.print(" (missing: ", .{});
                for (self.missing_variants, 0..) |variant, i| {
                    if (i > 0) try writer.print(", ", .{});
                    try writer.print("{s}", .{variant.name});
                }
                try writer.print(")", .{});
            }
        }
        if (self.unreachable_patterns.len > 0) {
            try writer.print(" (unreachable: {})", .{self.unreachable_patterns.len});
        }
    }
};

/// Sum type and shape type dispatch system
pub const SumShapeDispatcher = struct {
    allocator: Allocator,
    type_registry: *const TypeRegistry,
    signature_analyzer: *const SignatureAnalyzer,
    specificity_analyzer: *SpecificityAnalyzer,

    // Sum type tracking
    sum_types: std.AutoHashMap(TypeId, SumType),
    sum_dispatch_patterns: std.AutoHashMap(TypeId, ArrayList(SumDispatchPattern)),

    // Shape type tracking
    shape_types: std.AutoHashMap(TypeId, ShapeType),
    shape_compatibility_cache: std.AutoHashMap(CompatibilityCacheKey, ShapeCompatibility),

    const CompatibilityCacheKey = struct {
        shape_type: TypeId,
        target_type: TypeId,

        pub fn hash(self: CompatibilityCacheKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&self.shape_type));
            hasher.update(std.mem.asBytes(&self.target_type));
            return hasher.final();
        }

        pub fn eql(self: CompatibilityCacheKey, other: CompatibilityCacheKey) bool {
            return self.shape_type == other.shape_type and self.target_type == other.target_type;
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
            .sum_types = std.AutoHashMap(TypeId, SumType).init(allocator),
            .sum_dispatch_patterns = std.AutoHashMap(TypeId, ArrayList(SumDispatchPattern)).init(allocator),
            .shape_types = std.AutoHashMap(TypeId, ShapeType).init(allocator),
            .shape_compatibility_cache = std.AutoHashMap(CompatibilityCacheKey, ShapeCompatibility).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up sum types
        var sum_iter = self.sum_types.iterator();
        while (sum_iter.next()) |entry| {
            self.freeSumType(entry.value_ptr);
        }
        self.sum_types.deinit();

        // Clean up sum dispatch patterns
        var pattern_iter = self.sum_dispatch_patterns.iterator();
        while (pattern_iter.next()) |entry| {
            for (entry.value_ptr.items) |*pattern| {
                self.freeSumDispatchPattern(pattern);
            }
            entry.value_ptr.deinit();
        }
        self.sum_dispatch_patterns.deinit();

        // Clean up shape types
        var shape_iter = self.shape_types.iterator();
        while (shape_iter.next()) |entry| {
            self.freeShapeType(entry.value_ptr);
        }
        self.shape_types.deinit();

        // Clean up compatibility cache
        var cache_iter = self.shape_compatibility_cache.iterator();
        while (cache_iter.next()) |entry| {
            self.freeShapeCompatibility(entry.value_ptr);
        }
        self.shape_compatibility_cache.deinit();
    }

    /// Register a sum type
    pub fn registerSumType(
        self: *Self,
        type_id: TypeId,
        name: []const u8,
        variants: []const SumVariant,
        is_closed: bool,
    ) !void {
        const sum_type = SumType{
            .type_id = type_id,
            .name = try self.allocator.dupe(u8, name),
            .variants = try self.allocator.dupe(SumVariant, variants),
            .is_closed = is_closed,
            .exhaustive_check_required = is_closed,
        };

        try self.sum_types.put(type_id, sum_type);
        try self.sum_dispatch_patterns.put(type_id, ArrayList(SumDispatchPattern).empty);
    }

    /// Register a shape type
    pub fn registerShapeType(
        self: *Self,
        type_id: TypeId,
        name: []const u8,
        fields: []const ShapeField,
        is_open: bool,
    ) !void {
        const shape_type = ShapeType{
            .type_id = type_id,
            .name = try self.allocator.dupe(u8, name),
            .fields = try self.allocator.dupe(ShapeField, fields),
            .is_open = is_open,
            .structural_compatibility = true,
        };

        try self.shape_types.put(type_id, shape_type);
    }

    /// Add a sum type dispatch pattern
    pub fn addSumDispatchPattern(
        self: *Self,
        sum_type_id: TypeId,
        pattern: SumDispatchPattern,
    ) !void {
        var patterns = self.sum_dispatch_patterns.get(sum_type_id) orelse {
            return error.SumTypeNotRegistered;
        };

        try patterns.append(pattern);
    }

    /// Resolve sum type dispatch for a specific variant
    pub fn resolveSumDispatch(
        self: *Self,
        sum_type_id: TypeId,
        variant_name: []const u8,
        argument_types: []const TypeId,
    ) !?*const SignatureAnalyzer.Implementation {
        const sum_type = self.sum_types.get(sum_type_id) orelse return null;
        const patterns = self.sum_dispatch_patterns.get(sum_type_id) orelse return null;

        // Find the variant
        var target_variant: ?SumVariant = null;
        for (sum_type.variants) |variant| {
            if (std.mem.eql(u8, variant.name, variant_name)) {
                target_variant = variant;
                break;
            }
        }

        if (target_variant == null) return null;

        // Find matching pattern
        for (patterns.items) |pattern| {
            for (pattern.variant_patterns) |variant_pattern| {
                if (std.mem.eql(u8, variant_pattern.variant_name, variant_name)) {
                    // Check if argument types match
                    if (self.argumentsMatch(variant_pattern.implementation, argument_types)) {
                        return variant_pattern.implementation;
                    }
                }
            }
        }

        return null;
    }

    /// Check shape type compatibility
    pub fn checkShapeCompatibility(
        self: *Self,
        shape_type_id: TypeId,
        target_type_id: TypeId,
    ) !ShapeCompatibility {
        const cache_key = CompatibilityCacheKey{
            .shape_type = shape_type_id,
            .target_type = target_type_id,
        };

        // Check cache first
        if (self.shape_compatibility_cache.get(cache_key)) |cached| {
            return cached;
        }

        const shape_type = self.shape_types.get(shape_type_id) orelse {
            return ShapeCompatibility{
                .compatible = false,
                .missing_fields = try self.allocator.alloc([]const u8, 0),
                .extra_fields = try self.allocator.alloc([]const u8, 0),
                .type_mismatches = try self.allocator.alloc(ShapeCompatibility.FieldTypeMismatch, 0),
            };
        };

        const target_shape = self.shape_types.get(target_type_id);
        if (target_shape == null) {
            // Target is not a shape type - check structural compatibility differently
            return try self.checkStructuralCompatibility(&shape_type, target_type_id);
        }

        // Both are shape types - compare fields
        var missing_fields: ArrayList([]const u8) = .empty;
        defer missing_fields.deinit();

        var extra_fields: ArrayList([]const u8) = .empty;
        defer extra_fields.deinit();

        var type_mismatches: ArrayList(ShapeCompatibility.FieldTypeMismatch) = .empty;
        defer type_mismatches.deinit();

        // Check required fields in shape_type are present in target
        for (shape_type.fields) |field| {
            if (!field.is_required) continue;

            var found = false;
            for (target_shape.?.fields) |target_field| {
                if (std.mem.eql(u8, field.name, target_field.name)) {
                    found = true;
                    // Check type compatibility
                    if (field.type_id != target_field.type_id and
                        !self.type_registry.isSubtype(target_field.type_id, field.type_id))
                    {
                        try type_mismatches.append(ShapeCompatibility.FieldTypeMismatch{
                            .field_name = field.name,
                            .expected_type = field.type_id,
                            .actual_type = target_field.type_id,
                        });
                    }
                    break;
                }
            }

            if (!found) {
                try missing_fields.append(field.name);
            }
        }

        // Check for extra fields if shape is closed
        if (!shape_type.is_open) {
            for (target_shape.?.fields) |target_field| {
                var found = false;
                for (shape_type.fields) |field| {
                    if (std.mem.eql(u8, field.name, target_field.name)) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    try extra_fields.append(target_field.name);
                }
            }
        }

        const compatible = missing_fields.items.len == 0 and
            type_mismatches.items.len == 0 and
            (shape_type.is_open or extra_fields.items.len == 0);

        const result = ShapeCompatibility{
            .compatible = compatible,
            .missing_fields = try self.allocator.dupe([]const u8, missing_fields.items),
            .extra_fields = try self.allocator.dupe([]const u8, extra_fields.items),
            .type_mismatches = try self.allocator.dupe(ShapeCompatibility.FieldTypeMismatch, type_mismatches.items),
        };

        // Don't cache the result to avoid double-free issues
        // try self.shape_compatibility_cache.put(cache_key, result);

        return result;
    }

    /// Check exhaustiveness of sum type dispatch patterns
    pub fn checkExhaustiveness(
        self: *Self,
        sum_type_id: TypeId,
    ) !ExhaustivenessCheck {
        const sum_type = self.sum_types.get(sum_type_id) orelse {
            return ExhaustivenessCheck{
                .is_exhaustive = false,
                .missing_variants = try self.allocator.alloc(SumVariant, 0),
                .unreachable_patterns = try self.allocator.alloc(SumDispatchPattern.VariantPattern, 0),
            };
        };

        if (!sum_type.is_closed) {
            // Open sum types cannot be exhaustively checked
            return ExhaustivenessCheck{
                .is_exhaustive = false,
                .missing_variants = try self.allocator.alloc(SumVariant, 0),
                .unreachable_patterns = try self.allocator.alloc(SumDispatchPattern.VariantPattern, 0),
            };
        }

        const patterns = self.sum_dispatch_patterns.get(sum_type_id) orelse {
            return ExhaustivenessCheck{
                .is_exhaustive = false,
                .missing_variants = try self.allocator.dupe(SumVariant, sum_type.variants),
                .unreachable_patterns = &.{},
            };
        };

        var covered_variants = std.StringHashMap(bool).init(self.allocator);
        defer covered_variants.deinit();

        var unreachable_patterns: ArrayList(SumDispatchPattern.VariantPattern) = .empty;
        defer unreachable_patterns.deinit();

        // Mark covered variants
        for (patterns.items) |pattern| {
            for (pattern.variant_patterns) |variant_pattern| {
                const already_covered = covered_variants.get(variant_pattern.variant_name) orelse false;
                if (already_covered) {
                    try unreachable_patterns.append(variant_pattern);
                } else {
                    try covered_variants.put(variant_pattern.variant_name, true);
                }
            }
        }

        // Find missing variants
        var missing_variants: ArrayList(SumVariant) = .empty;
        defer missing_variants.deinit();

        for (sum_type.variants) |variant| {
            if (!covered_variants.contains(variant.name)) {
                try missing_variants.append(variant);
            }
        }

        const is_exhaustive = missing_variants.items.len == 0;

        return ExhaustivenessCheck{
            .is_exhaustive = is_exhaustive,
            .missing_variants = try self.allocator.dupe(SumVariant, missing_variants.items),
            .unreachable_patterns = try self.allocator.dupe(SumDispatchPattern.VariantPattern, unreachable_patterns.items),
        };
    }

    /// Resolve shape-based dispatch
    pub fn resolveShapeDispatch(
        self: *Self,
        shape_type_id: TypeId,
        target_type_id: TypeId,
        implementations: []const SignatureAnalyzer.Implementation,
    ) !?*const SignatureAnalyzer.Implementation {
        const compatibility = try self.checkShapeCompatibility(shape_type_id, target_type_id);
        if (!compatibility.compatible) {
            return null;
        }

        // Find the most specific implementation that accepts the target type
        var candidates: ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer candidates.deinit();

        for (implementations) |*impl| {
            if (self.implementationAcceptsType(impl, target_type_id)) {
                try candidates.append(impl);
            }
        }

        if (candidates.items.len == 0) return null;
        if (candidates.items.len == 1) return candidates.items[0];

        // Use specificity analysis to select the best candidate
        const arg_types = [_]TypeId{target_type_id};
        var result = try self.specificity_analyzer.findMostSpecific(candidates.items, &arg_types);
        defer result.deinit(self.allocator);

        switch (result) {
            .unique => |impl| return impl,
            .ambiguous => return null, // Ambiguous - caller should handle
            .no_match => return null,
        }
    }

    /// Get all sum types
    pub fn getAllSumTypes(self: *Self) ![]const SumType {
        var types: ArrayList(SumType) = .empty;
        defer types.deinit();

        var iter = self.sum_types.iterator();
        while (iter.next()) |entry| {
            try types.append(entry.value_ptr.*);
        }

        return self.allocator.dupe(SumType, types.items);
    }

    /// Get all shape types
    pub fn getAllShapeTypes(self: *Self) ![]const ShapeType {
        var types: ArrayList(ShapeType) = .empty;
        defer types.deinit();

        var iter = self.shape_types.iterator();
        while (iter.next()) |entry| {
            try types.append(entry.value_ptr.*);
        }

        return self.allocator.dupe(ShapeType, types.items);
    }

    /// Check structural compatibility for non-shape target types
    fn checkStructuralCompatibility(
        self: *Self,
        shape_type: *const ShapeType,
        target_type_id: TypeId,
    ) !ShapeCompatibility {
        _ = shape_type;
        _ = target_type_id;

        // Simplified implementation - in practice would need deep type introspection
        return ShapeCompatibility{
            .compatible = false,
            .missing_fields = try self.allocator.alloc([]const u8, 0),
            .extra_fields = try self.allocator.alloc([]const u8, 0),
            .type_mismatches = try self.allocator.alloc(ShapeCompatibility.FieldTypeMismatch, 0),
        };
    }

    /// Check if arguments match an implementation
    fn argumentsMatch(
        self: *Self,
        implementation: *const SignatureAnalyzer.Implementation,
        argument_types: []const TypeId,
    ) bool {
        if (implementation.param_type_ids.len != argument_types.len) {
            return false;
        }

        for (implementation.param_type_ids, argument_types) |param_type, arg_type| {
            if (!self.type_registry.isSubtype(arg_type, param_type)) {
                return false;
            }
        }

        return true;
    }

    /// Check if an implementation accepts a specific type
    fn implementationAcceptsType(
        self: *Self,
        implementation: *const SignatureAnalyzer.Implementation,
        type_id: TypeId,
    ) bool {
        if (implementation.param_type_ids.len == 0) return false;

        return self.type_registry.isSubtype(type_id, implementation.param_type_ids[0]);
    }

    /// Free sum type memory
    fn freeSumType(self: *Self, sum_type: *SumType) void {
        self.allocator.free(sum_type.name);
        self.allocator.free(sum_type.variants);
    }

    /// Free sum dispatch pattern memory
    fn freeSumDispatchPattern(self: *Self, pattern: *SumDispatchPattern) void {
        self.allocator.free(pattern.variant_patterns);
    }

    /// Free shape type memory
    fn freeShapeType(self: *Self, shape_type: *ShapeType) void {
        self.allocator.free(shape_type.name);
        self.allocator.free(shape_type.fields);
    }

    /// Free shape compatibility memory
    fn freeShapeCompatibility(self: *Self, compatibility: *ShapeCompatibility) void {
        self.allocator.free(compatibility.missing_fields);
        self.allocator.free(compatibility.extra_fields);
        self.allocator.free(compatibility.type_mismatches);
    }
};

// Tests
test "SumShapeDispatcher sum type registration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = SumShapeDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const option_type = try type_registry.registerType("Option", .sum_closed, &.{});
    const some_type = try type_registry.registerType("Some", .primitive, &.{});
    const none_type = try type_registry.registerType("None", .primitive, &.{});

    const variants = [_]SumVariant{
        SumVariant{
            .name = "Some",
            .type_id = some_type,
            .tag_value = 0,
            .payload_type = some_type,
        },
        SumVariant{
            .name = "None",
            .type_id = none_type,
            .tag_value = 1,
            .payload_type = null,
        },
    };

    try dispatcher.registerSumType(option_type, "Option", &variants, true);

    const sum_types = try dispatcher.getAllSumTypes();
    defer allocator.free(sum_types);

    try testing.expectEqual(@as(usize, 1), sum_types.len);
    try testing.expectEqualStrings("Option", sum_types[0].name);
    try testing.expectEqual(@as(usize, 2), sum_types[0].variants.len);
    try testing.expect(sum_types[0].is_closed);
}

test "SumShapeDispatcher shape type registration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = SumShapeDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const person_type = try type_registry.registerType("Person", .shape, &.{});
    const string_type = try type_registry.registerType("string", .primitive, &.{});
    const int_type = try type_registry.registerType("int", .primitive, &.{});

    const fields = [_]ShapeField{
        ShapeField{
            .name = "name",
            .type_id = string_type,
            .is_required = true,
            .default_value = null,
        },
        ShapeField{
            .name = "age",
            .type_id = int_type,
            .is_required = false,
            .default_value = "0",
        },
    };

    try dispatcher.registerShapeType(person_type, "Person", &fields, false);

    const shape_types = try dispatcher.getAllShapeTypes();
    defer allocator.free(shape_types);

    try testing.expectEqual(@as(usize, 1), shape_types.len);
    try testing.expectEqualStrings("Person", shape_types[0].name);
    try testing.expectEqual(@as(usize, 2), shape_types[0].fields.len);
    try testing.expect(!shape_types[0].is_open);
}

test "SumShapeDispatcher shape compatibility checking" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = SumShapeDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const person_type = try type_registry.registerType("Person", .shape, &.{});
    const employee_type = try type_registry.registerType("Employee", .shape, &.{});
    const string_type = try type_registry.registerType("string", .primitive, &.{});
    const int_type = try type_registry.registerType("int", .primitive, &.{});

    // Person shape: { name: string, age?: int }
    const person_fields = [_]ShapeField{
        ShapeField{
            .name = "name",
            .type_id = string_type,
            .is_required = true,
            .default_value = null,
        },
        ShapeField{
            .name = "age",
            .type_id = int_type,
            .is_required = false,
            .default_value = null,
        },
    };

    // Employee shape: { name: string, age: int, id: string }
    const employee_fields = [_]ShapeField{
        ShapeField{
            .name = "name",
            .type_id = string_type,
            .is_required = true,
            .default_value = null,
        },
        ShapeField{
            .name = "age",
            .type_id = int_type,
            .is_required = true,
            .default_value = null,
        },
        ShapeField{
            .name = "id",
            .type_id = string_type,
            .is_required = true,
            .default_value = null,
        },
    };

    try dispatcher.registerShapeType(person_type, "Person", &person_fields, true); // Open shape
    try dispatcher.registerShapeType(employee_type, "Employee", &employee_fields, false); // Closed shape

    // Check compatibility: Employee should be compatible with Person (has all required fields)
    var compatibility = try dispatcher.checkShapeCompatibility(person_type, employee_type);
    defer dispatcher.freeShapeCompatibility(&compatibility);

    try testing.expect(compatibility.compatible);
    try testing.expectEqual(@as(usize, 0), compatibility.missing_fields.len);

    // Check reverse compatibility: Person should not be compatible with Employee (missing id field)
    var reverse_compatibility = try dispatcher.checkShapeCompatibility(employee_type, person_type);
    defer dispatcher.freeShapeCompatibility(&reverse_compatibility);

    try testing.expect(!reverse_compatibility.compatible);
    try testing.expect(reverse_compatibility.missing_fields.len > 0);
}

test "SumShapeDispatcher exhaustiveness checking" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = SumShapeDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const result_type = try type_registry.registerType("Result", .sum_closed, &.{});
    const ok_type = try type_registry.registerType("Ok", .primitive, &.{});
    const err_type = try type_registry.registerType("Err", .primitive, &.{});

    const variants = [_]SumVariant{
        SumVariant{
            .name = "Ok",
            .type_id = ok_type,
            .tag_value = 0,
            .payload_type = ok_type,
        },
        SumVariant{
            .name = "Err",
            .type_id = err_type,
            .tag_value = 1,
            .payload_type = err_type,
        },
    };

    try dispatcher.registerSumType(result_type, "Result", &variants, true);

    // Check exhaustiveness with no patterns (should be non-exhaustive)
    const exhaustiveness = try dispatcher.checkExhaustiveness(result_type);
    defer {
        allocator.free(exhaustiveness.missing_variants);
        allocator.free(exhaustiveness.unreachable_patterns);
    }

    try testing.expect(!exhaustiveness.is_exhaustive);
    try testing.expectEqual(@as(usize, 2), exhaustiveness.missing_variants.len);
}

test "SumShapeDispatcher formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test SumVariant formatting
    const variant = SumVariant{
        .name = "Some",
        .type_id = 1,
        .tag_value = 0,
        .payload_type = 2,
    };

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{variant});
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Some") != null);

    // Test ShapeField formatting
    buffer.clearRetainingCapacity();
    const field = ShapeField{
        .name = "name",
        .type_id = 1,
        .is_required = true,
        .default_value = null,
    };

    try std.fmt.format(buffer.writer(), "{}", .{field});
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "name") != null);
}
