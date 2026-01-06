// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;

/// Source location information for error reporting
pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
    column: u32,

    pub fn format(self: SourceLocation, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}:{}:{}", .{ self.file, self.line, self.column });
    }
};

/// Implementation reference for error reporting
pub const ImplementationRef = struct {
    id: u32,
    param_types: []const TypeId,
    source_location: SourceLocation,
    specificity_score: u32,

    pub fn format(self: ImplementationRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("impl#{} at {}", .{ self.id, self.source_location });
    }
};

/// Reason why an implementation was rejected during dispatch
pub const RejectionReason = enum {
    type_mismatch,
    insufficient_specificity,
    ambiguous_with_other,
    generic_constraint_violation,
    capability_mismatch,

    pub fn description(self: RejectionReason) []const u8 {
        return switch (self) {
            .type_mismatch => "argument type does not match parameter type",
            .insufficient_specificity => "less specific than other available implementations",
            .ambiguous_with_other => "ambiguous with another equally specific implementation",
            .generic_constraint_violation => "generic type constraints not satisfied",
            .capability_mismatch => "required capabilities not available",
        };
    }
};

/// Detailed rejection information for an implementation
pub const RejectionInfo = struct {
    implementation: ImplementationRef,
    reason: RejectionReason,
    parameter_index: ?u32,
    expected_type: ?TypeId,
    actual_type: ?TypeId,
    conflicting_impl: ?ImplementationRef,
    additional_info: ?[]const u8,

    pub fn format(self: RejectionInfo, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}: {}", .{ self.implementation, self.reason.description() });

        if (self.parameter_index) |param_idx| {
            try writer.print(" (parameter {})", .{param_idx});
        }

        if (self.expected_type != null and self.actual_type != null) {
            try writer.print(" - expected type {}, got type {}", .{ self.expected_type.?, self.actual_type.? });
        }

        if (self.conflicting_impl) |conflict| {
            try writer.print(" - conflicts with {}", .{conflict});
        }

        if (self.additional_info) |info| {
            try writer.print(" - {s}", .{info});
        }
    }
};

/// Comprehensive error for ambiguous dispatch scenarios
pub const AmbiguousDispatchError = struct {
    signature_name: []const u8,
    argument_types: []const TypeId,
    conflicting_implementations: []const ImplementationRef,
    call_site: SourceLocation,
    specificity_analysis: []const SpecificityComparison,
    suggested_fixes: []const SuggestedFix,

    pub const SpecificityComparison = struct {
        impl1: ImplementationRef,
        impl2: ImplementationRef,
        comparison_result: SpecificityComparison.ComparisonResult,
        parameter_analysis: []const ParameterComparison,

        pub const ComparisonResult = enum {
            equally_specific,
            impl1_more_specific,
            impl2_more_specific,
            incomparable,
        };

        pub const ParameterComparison = struct {
            parameter_index: u32,
            type1: TypeId,
            type2: TypeId,
            relationship: TypeRelationship,

            pub const TypeRelationship = enum {
                identical,
                type1_subtype_of_type2,
                type2_subtype_of_type1,
                unrelated,
            };
        };
    };

    pub const SuggestedFix = struct {
        description: []const u8,
        fix_type: FixType,
        target_location: ?SourceLocation,
        suggested_code: ?[]const u8,

        pub const FixType = enum {
            add_type_annotation,
            make_implementation_more_specific,
            remove_conflicting_implementation,
            use_qualified_call,
        };
    };

    pub fn format(self: AmbiguousDispatchError, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Ambiguous dispatch for '{s}' at {}\n", .{ self.signature_name, self.call_site });
        try writer.print("Argument types: ", .{});
        for (self.argument_types, 0..) |arg_type, i| {
            if (i > 0) try writer.print(", ", .{});
            try writer.print("{}", .{arg_type});
        }
        try writer.print("\n\n", .{});

        try writer.print("Conflicting implementations:\n", .{});
        for (self.conflicting_implementations) |impl| {
            try writer.print("  - {}\n", .{impl});
        }
        try writer.print("\n", .{});

        if (self.specificity_analysis.len > 0) {
            try writer.print("Specificity analysis:\n", .{});
            for (self.specificity_analysis) |analysis| {
                try writer.print("  {} vs {}: ", .{ analysis.impl1, analysis.impl2 });
                switch (analysis.comparison_result) {
                    .equally_specific => try writer.print("equally specific\n", .{}),
                    .impl1_more_specific => try writer.print("first is more specific\n", .{}),
                    .impl2_more_specific => try writer.print("second is more specific\n", .{}),
                    .incomparable => try writer.print("incomparable\n", .{}),
                }

                for (analysis.parameter_analysis) |param| {
                    try writer.print("    Parameter {}: {} vs {} - ", .{ param.parameter_index, param.type1, param.type2 });
                    switch (param.relationship) {
                        .identical => try writer.print("identical\n", .{}),
                        .type1_subtype_of_type2 => try writer.print("first is subtype of second\n", .{}),
                        .type2_subtype_of_type1 => try writer.print("second is subtype of first\n", .{}),
                        .unrelated => try writer.print("unrelated\n", .{}),
                    }
                }
            }
            try writer.print("\n", .{});
        }

        if (self.suggested_fixes.len > 0) {
            try writer.print("Suggested fixes:\n", .{});
            for (self.suggested_fixes) |fix| {
                try writer.print("  - {s}", .{fix.description});
                if (fix.target_location) |loc| {
                    try writer.print(" at {}", .{loc});
                }
                try writer.print("\n", .{});
                if (fix.suggested_code) |code| {
                    try writer.print("    Suggested: {s}\n", .{code});
                }
            }
        }
    }
};

/// Comprehensive error for no matching implementation scenarios
pub const NoMatchingImplementationError = struct {
    signature_name: []const u8,
    argument_types: []const TypeId,
    call_site: SourceLocation,
    available_implementations: []const ImplementationRef,
    rejection_analysis: []const RejectionInfo,
    suggested_fixes: []const SuggestedFix,

    pub const SuggestedFix = struct {
        description: []const u8,
        fix_type: FixType,
        target_location: ?SourceLocation,
        suggested_code: ?[]const u8,

        pub const FixType = enum {
            add_missing_implementation,
            convert_argument_types,
            use_explicit_conversion,
            check_import_statements,
        };
    };

    pub fn format(self: NoMatchingImplementationError, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("No matching implementation for '{s}' at {}\n", .{ self.signature_name, self.call_site });
        try writer.print("Argument types: ", .{});
        for (self.argument_types, 0..) |arg_type, i| {
            if (i > 0) try writer.print(", ", .{});
            try writer.print("{}", .{arg_type});
        }
        try writer.print("\n\n", .{});

        if (self.available_implementations.len > 0) {
            try writer.print("Available implementations:\n", .{});
            for (self.available_implementations) |impl| {
                try writer.print("  - {}\n", .{impl});
            }
            try writer.print("\n", .{});
        }

        if (self.rejection_analysis.len > 0) {
            try writer.print("Rejection analysis:\n", .{});
            for (self.rejection_analysis) |rejection| {
                try writer.print("  - {}\n", .{rejection});
            }
            try writer.print("\n", .{});
        }

        if (self.suggested_fixes.len > 0) {
            try writer.print("Suggested fixes:\n", .{});
            for (self.suggested_fixes) |fix| {
                try writer.print("  - {s}", .{fix.description});
                if (fix.target_location) |loc| {
                    try writer.print(" at {}", .{loc});
                }
                try writer.print("\n", .{});
                if (fix.suggested_code) |code| {
                    try writer.print("    Suggested: {s}\n", .{code});
                }
            }
        }
    }
};

/// Comprehensive dispatch error reporting system
pub const DispatchErrorReporter = struct {
    allocator: Allocator,
    type_registry: *const TypeRegistry,

    const Self = @This();

    pub fn init(allocator: Allocator, type_registry: *const TypeRegistry) Self {
        return Self{
            .allocator = allocator,
            .type_registry = type_registry,
        };
    }

    /// Create detailed ambiguous dispatch error
    pub fn createAmbiguousDispatchError(
        self: *Self,
        signature_name: []const u8,
        argument_types: []const TypeId,
        call_site: SourceLocation,
        conflicting_implementations: []const ImplementationRef,
    ) !AmbiguousDispatchError {
        // Perform specificity analysis
        var specificity_analysis = ArrayList(AmbiguousDispatchError.SpecificityComparison).init(self.allocator);
        defer specificity_analysis.deinit();

        for (conflicting_implementations, 0..) |impl1, i| {
            for (conflicting_implementations[i + 1 ..]) |impl2| {
                const comparison = try self.analyzeSpecificity(impl1, impl2);
                try specificity_analysis.append(comparison);
            }
        }

        // Generate suggested fixes
        var suggested_fixes = ArrayList(AmbiguousDispatchError.SuggestedFix).init(self.allocator);
        defer suggested_fixes.deinit();

        try self.generateAmbiguityFixes(&suggested_fixes, conflicting_implementations, argument_types);

        return AmbiguousDispatchError{
            .signature_name = try self.allocator.dupe(u8, signature_name),
            .argument_types = try self.allocator.dupe(TypeId, argument_types),
            .conflicting_implementations = try self.allocator.dupe(ImplementationRef, conflicting_implementations),
            .call_site = call_site,
            .specificity_analysis = try self.allocator.dupe(AmbiguousDispatchError.SpecificityComparison, specificity_analysis.items),
            .suggested_fixes = try self.allocator.dupe(AmbiguousDispatchError.SuggestedFix, suggested_fixes.items),
        };
    }

    /// Create detailed no matching implementation error
    pub fn createNoMatchingImplementationError(
        self: *Self,
        signature_name: []const u8,
        argument_types: []const TypeId,
        call_site: SourceLocation,
        available_implementations: []const ImplementationRef,
    ) !NoMatchingImplementationError {
        // Analyze why each implementation was rejected
        var rejection_analysis = ArrayList(RejectionInfo).init(self.allocator);
        defer rejection_analysis.deinit();

        for (available_implementations) |impl| {
            const rejection = try self.analyzeRejection(impl, argument_types);
            try rejection_analysis.append(rejection);
        }

        // Generate suggested fixes
        var suggested_fixes = ArrayList(NoMatchingImplementationError.SuggestedFix).init(self.allocator);
        defer suggested_fixes.deinit();

        try self.generateNoMatchFixes(&suggested_fixes, available_implementations, argument_types);

        return NoMatchingImplementationError{
            .signature_name = try self.allocator.dupe(u8, signature_name),
            .argument_types = try self.allocator.dupe(TypeId, argument_types),
            .call_site = call_site,
            .available_implementations = try self.allocator.dupe(ImplementationRef, available_implementations),
            .rejection_analysis = try self.allocator.dupe(RejectionInfo, rejection_analysis.items),
            .suggested_fixes = try self.allocator.dupe(NoMatchingImplementationError.SuggestedFix, suggested_fixes.items),
        };
    }

    /// Analyze specificity relationship between two implementations
    fn analyzeSpecificity(
        self: *Self,
        impl1: ImplementationRef,
        impl2: ImplementationRef,
    ) !AmbiguousDispatchError.SpecificityComparison {
        var parameter_analysis = ArrayList(AmbiguousDispatchError.SpecificityComparison.ParameterComparison).init(self.allocator);
        defer parameter_analysis.deinit();

        const min_params = @min(impl1.param_types.len, impl2.param_types.len);
        var impl1_more_specific_count: u32 = 0;
        var impl2_more_specific_count: u32 = 0;

        for (0..min_params) |i| {
            const type1 = impl1.param_types[i];
            const type2 = impl2.param_types[i];

            const relationship = if (type1 == type2)
                AmbiguousDispatchError.SpecificityComparison.ParameterComparison.TypeRelationship.identical
            else if (self.type_registry.isSubtype(type1, type2))
                AmbiguousDispatchError.SpecificityComparison.ParameterComparison.TypeRelationship.type1_subtype_of_type2
            else if (self.type_registry.isSubtype(type2, type1))
                AmbiguousDispatchError.SpecificityComparison.ParameterComparison.TypeRelationship.type2_subtype_of_type1
            else
                AmbiguousDispatchError.SpecificityComparison.ParameterComparison.TypeRelationship.unrelated;

            try parameter_analysis.append(.{
                .parameter_index = @intCast(i),
                .type1 = type1,
                .type2 = type2,
                .relationship = relationship,
            });

            switch (relationship) {
                .type1_subtype_of_type2 => impl1_more_specific_count += 1,
                .type2_subtype_of_type1 => impl2_more_specific_count += 1,
                else => {},
            }
        }

        const comparison_result = if (impl1_more_specific_count > 0 and impl2_more_specific_count == 0)
            AmbiguousDispatchError.SpecificityComparison.ComparisonResult.impl1_more_specific
        else if (impl2_more_specific_count > 0 and impl1_more_specific_count == 0)
            AmbiguousDispatchError.SpecificityComparison.ComparisonResult.impl2_more_specific
        else if (impl1_more_specific_count == 0 and impl2_more_specific_count == 0)
            AmbiguousDispatchError.SpecificityComparison.ComparisonResult.equally_specific
        else
            AmbiguousDispatchError.SpecificityComparison.ComparisonResult.incomparable;

        return AmbiguousDispatchError.SpecificityComparison{
            .impl1 = impl1,
            .impl2 = impl2,
            .comparison_result = comparison_result,
            .parameter_analysis = try self.allocator.dupe(AmbiguousDispatchError.SpecificityComparison.ParameterComparison, parameter_analysis.items),
        };
    }

    /// Analyze why an implementation was rejected
    fn analyzeRejection(
        self: *Self,
        implementation: ImplementationRef,
        argument_types: []const TypeId,
    ) !RejectionInfo {
        // Check parameter count mismatch
        if (implementation.param_types.len != argument_types.len) {
            return RejectionInfo{
                .implementation = implementation,
                .reason = .type_mismatch,
                .parameter_index = null,
                .expected_type = null,
                .actual_type = null,
                .conflicting_impl = null,
                .additional_info = try std.fmt.allocPrint(self.allocator, "expected {} parameters, got {}", .{ implementation.param_types.len, argument_types.len }),
            };
        }

        // Check each parameter for type compatibility
        for (implementation.param_types, argument_types, 0..) |expected_type, actual_type, i| {
            if (!self.type_registry.isSubtype(actual_type, expected_type)) {
                return RejectionInfo{
                    .implementation = implementation,
                    .reason = .type_mismatch,
                    .parameter_index = @intCast(i),
                    .expected_type = expected_type,
                    .actual_type = actual_type,
                    .conflicting_impl = null,
                    .additional_info = null,
                };
            }
        }

        // If we get here, the implementation should have matched
        return RejectionInfo{
            .implementation = implementation,
            .reason = .insufficient_specificity,
            .parameter_index = null,
            .expected_type = null,
            .actual_type = null,
            .conflicting_impl = null,
            .additional_info = try self.allocator.dupe(u8, "implementation should have matched but was rejected"),
        };
    }

    /// Generate suggested fixes for ambiguous dispatch
    fn generateAmbiguityFixes(
        self: *Self,
        fixes: *ArrayList(AmbiguousDispatchError.SuggestedFix),
        conflicting_implementations: []const ImplementationRef,
        argument_types: []const TypeId,
    ) !void {
        _ = argument_types;

        // Suggest making one implementation more specific
        if (conflicting_implementations.len == 2) {
            try fixes.append(.{
                .description = try self.allocator.dupe(u8, "Make one implementation more specific by adding type constraints"),
                .fix_type = .make_implementation_more_specific,
                .target_location = conflicting_implementations[0].source_location,
                .suggested_code = null,
            });
        }

        // Suggest using qualified call
        try fixes.append(.{
            .description = try self.allocator.dupe(u8, "Use qualified function call to specify which implementation to use"),
            .fix_type = .use_qualified_call,
            .target_location = null,
            .suggested_code = try self.allocator.dupe(u8, "module::function_name(args)"),
        });

        // Suggest adding type annotations
        try fixes.append(.{
            .description = try self.allocator.dupe(u8, "Add explicit type annotations to arguments to disambiguate"),
            .fix_type = .add_type_annotation,
            .target_location = null,
            .suggested_code = try self.allocator.dupe(u8, "function_name(arg as SpecificType)"),
        });
    }

    /// Generate suggested fixes for no matching implementation
    fn generateNoMatchFixes(
        self: *Self,
        fixes: *ArrayList(NoMatchingImplementationError.SuggestedFix),
        available_implementations: []const ImplementationRef,
        argument_types: []const TypeId,
    ) !void {
        _ = available_implementations;
        _ = argument_types;

        // Suggest adding missing implementation
        try fixes.append(.{
            .description = try self.allocator.dupe(u8, "Add an implementation that matches the argument types"),
            .fix_type = .add_missing_implementation,
            .target_location = null,
            .suggested_code = try self.allocator.dupe(u8, "fn function_name(param: ArgType) -> ReturnType { ... }"),
        });

        // Suggest checking imports
        try fixes.append(.{
            .description = try self.allocator.dupe(u8, "Check that all required modules are imported"),
            .fix_type = .check_import_statements,
            .target_location = null,
            .suggested_code = try self.allocator.dupe(u8, "using module_name;"),
        });

        // Suggest explicit type conversion
        try fixes.append(.{
            .description = try self.allocator.dupe(u8, "Use explicit type conversion if arguments need to be converted"),
            .fix_type = .use_explicit_conversion,
            .target_location = null,
            .suggested_code = try self.allocator.dupe(u8, "function_name(convert(arg, TargetType))"),
        });
    }

    /// Clean up allocated error data
    pub fn freeAmbiguousDispatchError(self: *Self, error_info: *AmbiguousDispatchError) void {
        self.allocator.free(error_info.signature_name);
        self.allocator.free(error_info.argument_types);
        self.allocator.free(error_info.conflicting_implementations);

        for (error_info.specificity_analysis) |*analysis| {
            self.allocator.free(analysis.parameter_analysis);
        }
        self.allocator.free(error_info.specificity_analysis);

        for (error_info.suggested_fixes) |*fix| {
            self.allocator.free(fix.description);
            if (fix.suggested_code) |code| {
                self.allocator.free(code);
            }
        }
        self.allocator.free(error_info.suggested_fixes);
    }

    /// Clean up allocated error data
    pub fn freeNoMatchingImplementationError(self: *Self, error_info: *NoMatchingImplementationError) void {
        self.allocator.free(error_info.signature_name);
        self.allocator.free(error_info.argument_types);
        self.allocator.free(error_info.available_implementations);

        for (error_info.rejection_analysis) |*rejection| {
            if (rejection.additional_info) |info| {
                self.allocator.free(info);
            }
        }
        self.allocator.free(error_info.rejection_analysis);

        for (error_info.suggested_fixes) |*fix| {
            self.allocator.free(fix.description);
            if (fix.suggested_code) |code| {
                self.allocator.free(code);
            }
        }
        self.allocator.free(error_info.suggested_fixes);
    }
};

// Tests
test "DispatchErrorReporter ambiguous dispatch error" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});
    _ = try type_registry.registerType("float", .primitive, &.{});

    var reporter = DispatchErrorReporter.init(allocator, &type_registry);

    const impl1 = ImplementationRef{
        .id = 1,
        .param_types = &[_]TypeId{int_type},
        .source_location = .{ .file = "test.janus", .line = 10, .column = 5 },
        .specificity_score = 100,
    };

    const impl2 = ImplementationRef{
        .id = 2,
        .param_types = &[_]TypeId{int_type},
        .source_location = .{ .file = "test.janus", .line = 20, .column = 5 },
        .specificity_score = 100,
    };

    const conflicting_impls = [_]ImplementationRef{ impl1, impl2 };
    const arg_types = [_]TypeId{int_type};
    const call_site = SourceLocation{ .file = "main.janus", .line = 5, .column = 10 };

    var error_info = try reporter.createAmbiguousDispatchError(
        "test_function",
        &arg_types,
        call_site,
        &conflicting_impls,
    );
    defer reporter.freeAmbiguousDispatchError(&error_info);

    try testing.expectEqualStrings("test_function", error_info.signature_name);
    try testing.expectEqual(@as(usize, 1), error_info.argument_types.len);
    try testing.expectEqual(int_type, error_info.argument_types[0]);
    try testing.expectEqual(@as(usize, 2), error_info.conflicting_implementations.len);
    try testing.expect(error_info.specificity_analysis.len > 0);
    try testing.expect(error_info.suggested_fixes.len > 0);
}

test "DispatchErrorReporter no matching implementation error" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});
    const float_type = try type_registry.registerType("float", .primitive, &.{});

    var reporter = DispatchErrorReporter.init(allocator, &type_registry);

    const impl1 = ImplementationRef{
        .id = 1,
        .param_types = &[_]TypeId{float_type},
        .source_location = .{ .file = "test.janus", .line = 10, .column = 5 },
        .specificity_score = 100,
    };

    const available_impls = [_]ImplementationRef{impl1};
    const arg_types = [_]TypeId{int_type};
    const call_site = SourceLocation{ .file = "main.janus", .line = 5, .column = 10 };

    var error_info = try reporter.createNoMatchingImplementationError(
        "test_function",
        &arg_types,
        call_site,
        &available_impls,
    );
    defer reporter.freeNoMatchingImplementationError(&error_info);

    try testing.expectEqualStrings("test_function", error_info.signature_name);
    try testing.expectEqual(@as(usize, 1), error_info.argument_types.len);
    try testing.expectEqual(int_type, error_info.argument_types[0]);
    try testing.expectEqual(@as(usize, 1), error_info.available_implementations.len);
    try testing.expect(error_info.rejection_analysis.len > 0);
    try testing.expect(error_info.suggested_fixes.len > 0);
}

test "DispatchErrorReporter specificity analysis" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const animal_type = try type_registry.registerType("Animal", .table_open, &.{});
    const dog_type = try type_registry.registerType("Dog", .table_open, &[_]TypeId{animal_type});

    var reporter = DispatchErrorReporter.init(allocator, &type_registry);

    const impl1 = ImplementationRef{
        .id = 1,
        .param_types = &[_]TypeId{animal_type},
        .source_location = .{ .file = "test.janus", .line = 10, .column = 5 },
        .specificity_score = 50,
    };

    const impl2 = ImplementationRef{
        .id = 2,
        .param_types = &[_]TypeId{dog_type},
        .source_location = .{ .file = "test.janus", .line = 20, .column = 5 },
        .specificity_score = 100,
    };

    const analysis = try reporter.analyzeSpecificity(impl1, impl2);
    defer allocator.free(analysis.parameter_analysis);

    try testing.expectEqual(AmbiguousDispatchError.SpecificityComparison.ComparisonResult.impl2_more_specific, analysis.comparison_result);
    try testing.expectEqual(@as(usize, 1), analysis.parameter_analysis.len);
    try testing.expectEqual(AmbiguousDispatchError.SpecificityComparison.ParameterComparison.TypeRelationship.type2_subtype_of_type1, analysis.parameter_analysis[0].relationship);
}

test "DispatchErrorReporter rejection analysis" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});
    const float_type = try type_registry.registerType("float", .primitive, &.{});

    var reporter = DispatchErrorReporter.init(allocator, &type_registry);

    const impl = ImplementationRef{
        .id = 1,
        .param_types = &[_]TypeId{float_type},
        .source_location = .{ .file = "test.janus", .line = 10, .column = 5 },
        .specificity_score = 100,
    };

    const arg_types = [_]TypeId{int_type};

    const rejection = try reporter.analyzeRejection(impl, &arg_types);
    defer if (rejection.additional_info) |info| allocator.free(info);

    try testing.expectEqual(RejectionReason.type_mismatch, rejection.reason);
    try testing.expectEqual(@as(u32, 0), rejection.parameter_index.?);
    try testing.expectEqual(float_type, rejection.expected_type.?);
    try testing.expectEqual(int_type, rejection.actual_type.?);
}

test "DispatchErrorReporter error formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    const int_type = try type_registry.registerType("int", .primitive, &.{});

    var reporter = DispatchErrorReporter.init(allocator, &type_registry);

    const impl1 = ImplementationRef{
        .id = 1,
        .param_types = &[_]TypeId{int_type},
        .source_location = .{ .file = "test.janus", .line = 10, .column = 5 },
        .specificity_score = 100,
    };

    const impl2 = ImplementationRef{
        .id = 2,
        .param_types = &[_]TypeId{int_type},
        .source_location = .{ .file = "test.janus", .line = 20, .column = 5 },
        .specificity_score = 100,
    };

    const conflicting_impls = [_]ImplementationRef{ impl1, impl2 };
    const arg_types = [_]TypeId{int_type};
    const call_site = SourceLocation{ .file = "main.janus", .line = 5, .column = 10 };

    var error_info = try reporter.createAmbiguousDispatchError(
        "test_function",
        &arg_types,
        call_site,
        &conflicting_impls,
    );
    defer reporter.freeAmbiguousDispatchError(&error_info);

    // Test that error can be formatted without crashing
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{error_info});
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Ambiguous dispatch") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "test_function") != null);
}
