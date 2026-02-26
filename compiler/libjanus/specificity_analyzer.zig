// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;

/// SpecificityAnalyzer - Determines the most specific implementation for dispatch
///
/// This analyzer implements the core dispatch resolution algorithm that selects
/// the most specific implementation based on subtype relationships. It detects
/// ambiguities at compile time and provides detailed diagnostics for resolution.
pub const SpecificityAnalyzer = struct {
    /// Result of specificity analysis
    pub const SpecificityResult = union(enum) {
        unique: *const SignatureAnalyzer.Implementation,
        ambiguous: AmbiguousMatch,
        no_match: NoMatch,

        pub const AmbiguousMatch = struct {
            conflicting_implementations: []const *const SignatureAnalyzer.Implementation,
            call_arg_types: []const TypeRegistry.TypeId,

            pub fn deinit(self: *AmbiguousMatch, allocator: std.mem.Allocator) void {
                allocator.free(self.conflicting_implementations);
                allocator.free(self.call_arg_types);
            }
        };

        pub const NoMatch = struct {
            available_implementations: []const *const SignatureAnalyzer.Implementation,
            call_arg_types: []const TypeRegistry.TypeId,
            rejection_reasons: []const RejectionReason,

            pub const RejectionReason = struct {
                implementation: *const SignatureAnalyzer.Implementation,
                reason: []const u8,
                parameter_index: ?u32, // Which parameter caused the rejection
            };

            pub fn deinit(self: *NoMatch, allocator: std.mem.Allocator) void {
                allocator.free(self.available_implementations);
                allocator.free(self.call_arg_types);
                for (self.rejection_reasons) |reason| {
                    allocator.free(reason.reason);
                }
                allocator.free(self.rejection_reasons);
            }
        };

        pub fn deinit(self: *SpecificityResult, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .unique => {}, // No cleanup needed
                .ambiguous => |*amb| amb.deinit(allocator),
                .no_match => |*no_match| no_match.deinit(allocator),
            }
        }
    };

    /// Detailed specificity comparison result
    pub const SpecificityComparison = struct {
        is_more_specific: bool,
        has_strict_subtype: bool,
        distance_difference: i32, // Positive if first is more specific
        explanation: []const u8,

        pub fn deinit(self: *SpecificityComparison, allocator: std.mem.Allocator) void {
            allocator.free(self.explanation);
        }
    };

    type_registry: *const TypeRegistry,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, type_registry: *const TypeRegistry) SpecificityAnalyzer {
        return SpecificityAnalyzer{
            .type_registry = type_registry,
            .allocator = allocator,
        };
    }

    /// Find the most specific implementation for the given argument types
    pub fn findMostSpecific(
        self: *SpecificityAnalyzer,
        implementations: []const SignatureAnalyzer.Implementation,
        call_arg_types: []const TypeRegistry.TypeId,
    ) !SpecificityResult {
        // Filter implementations that match the call signature
        var candidates: std.ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer candidates.deinit();

        var rejection_reasons: std.ArrayList(SpecificityResult.NoMatch.RejectionReason) = .empty;
        defer {
            for (rejection_reasons.items) |reason| {
                self.allocator.free(reason.reason);
            }
            rejection_reasons.deinit();
        }

        for (implementations) |*impl| {
            const match_result = self.checkMatch(impl, call_arg_types);
            if (match_result.matches) {
                try candidates.append(impl);
            } else {
                try rejection_reasons.append(SpecificityResult.NoMatch.RejectionReason{
                    .implementation = impl,
                    .reason = try self.allocator.dupe(u8, match_result.reason),
                    .parameter_index = match_result.parameter_index,
                });
            }
        }

        if (candidates.items.len == 0) {
            // No matching implementations
            const owned_call_args = try self.allocator.dupe(TypeRegistry.TypeId, call_arg_types);
            // Convert to pointers for storage
            var available_ptrs = try self.allocator.alloc(*const SignatureAnalyzer.Implementation, implementations.len);
            for (implementations, 0..) |*impl, i| {
                available_ptrs[i] = impl;
            }
            const owned_available = available_ptrs;
            const owned_reasons = try rejection_reasons.toOwnedSlice();

            return SpecificityResult{
                .no_match = SpecificityResult.NoMatch{
                    .available_implementations = owned_available,
                    .call_arg_types = owned_call_args,
                    .rejection_reasons = owned_reasons,
                },
            };
        }

        if (candidates.items.len == 1) {
            return SpecificityResult{ .unique = candidates.items[0] };
        }

        // Find most specific among candidates using partial ordering
        const most_specific = try self.selectMostSpecific(candidates.items, call_arg_types);
        return most_specific;
    }

    /// Compare specificity of two implementations for given argument types
    pub fn compareSpecificity(
        self: *SpecificityAnalyzer,
        impl_a: *const SignatureAnalyzer.Implementation,
        impl_b: *const SignatureAnalyzer.Implementation,
        call_arg_types: []const TypeRegistry.TypeId,
    ) !SpecificityComparison {
        var explanation: std.ArrayList(u8) = .empty;
        defer explanation.deinit();

        var has_strict_subtype = false;
        var total_distance_diff: i32 = 0;
        var all_params_more_specific = true;

        try explanation.appendSlice("Specificity comparison:\n");

        for (impl_a.param_type_ids, impl_b.param_type_ids, call_arg_types, 0..) |type_a, type_b, call_type, i| {
            const distance_a = self.type_registry.calculateSpecificityDistance(call_type, type_a);
            const distance_b = self.type_registry.calculateSpecificityDistance(call_type, type_b);

            try explanation.writer().print("  Param {d}: call={s} -> A={s}(dist={d}), B={s}(dist={d})\n", .{
                i,
                self.getTypeName(call_type),
                self.getTypeName(type_a),
                distance_a,
                self.getTypeName(type_b),
                distance_b,
            });

            if (distance_a < distance_b) {
                // A is more specific for this parameter
                total_distance_diff += @as(i32, @intCast(distance_b - distance_a));
                if (distance_a < distance_b) has_strict_subtype = true;
            } else if (distance_a > distance_b) {
                // B is more specific for this parameter
                total_distance_diff -= @as(i32, @intCast(distance_a - distance_b));
                all_params_more_specific = false;
            } else {
                // Equal specificity for this parameter
                all_params_more_specific = all_params_more_specific and (distance_a == 0); // Only if exact match
            }
        }

        const is_more_specific = all_params_more_specific and has_strict_subtype;

        try explanation.writer().print("Result: A is {s} specific than B (distance_diff={d})\n", .{
            if (is_more_specific) "more" else "not more",
            total_distance_diff,
        });

        return SpecificityComparison{
            .is_more_specific = is_more_specific,
            .has_strict_subtype = has_strict_subtype,
            .distance_difference = total_distance_diff,
            .explanation = try explanation.toOwnedSlice(),
        };
    }

    /// Check if an implementation matches the call signature
    fn checkMatch(
        self: *SpecificityAnalyzer,
        impl: *const SignatureAnalyzer.Implementation,
        call_arg_types: []const TypeRegistry.TypeId,
    ) MatchResult {
        if (impl.param_type_ids.len != call_arg_types.len) {
            return MatchResult{
                .matches = false,
                .reason = "Arity mismatch",
                .parameter_index = null,
            };
        }

        for (impl.param_type_ids, call_arg_types, 0..) |param_type, call_type, i| {
            if (!self.type_registry.isSubtype(call_type, param_type)) {
                // Use a simple static reason to avoid memory management issues
                const reason = "Type mismatch";

                return MatchResult{
                    .matches = false,
                    .reason = reason,
                    .parameter_index = @intCast(i),
                };
            }
        }

        return MatchResult{
            .matches = true,
            .reason = "Match",
            .parameter_index = null,
        };
    }

    const MatchResult = struct {
        matches: bool,
        reason: []const u8,
        parameter_index: ?u32,
    };

    /// Select most specific implementation from candidates using partial ordering
    fn selectMostSpecific(
        self: *SpecificityAnalyzer,
        candidates: []*const SignatureAnalyzer.Implementation,
        call_arg_types: []const TypeRegistry.TypeId,
    ) !SpecificityResult {
        // Find maximal elements in the partial order (not dominated by any other)
        var maximal: std.ArrayList(*const SignatureAnalyzer.Implementation) = .empty;
        defer maximal.deinit();

        for (candidates) |candidate| {
            var is_maximal = true;

            // Check if any other candidate is more specific than this one
            for (candidates) |other| {
                if (candidate == other) continue;

                const comparison = try self.compareSpecificity(other, candidate, call_arg_types);
                defer {
                    var mut_comparison = comparison;
                    mut_comparison.deinit(self.allocator);
                }

                if (comparison.is_more_specific) {
                    is_maximal = false;
                    break;
                }
            }

            if (is_maximal) {
                try maximal.append(candidate);
            }
        }

        if (maximal.items.len == 1) {
            return SpecificityResult{ .unique = maximal.items[0] };
        } else {
            // Multiple maximal elements = ambiguity
            const owned_call_args = try self.allocator.dupe(TypeRegistry.TypeId, call_arg_types);
            const owned_conflicting = try self.allocator.dupe(*const SignatureAnalyzer.Implementation, maximal.items);

            return SpecificityResult{
                .ambiguous = SpecificityResult.AmbiguousMatch{
                    .conflicting_implementations = owned_conflicting,
                    .call_arg_types = owned_call_args,
                },
            };
        }
    }

    /// Get human-readable type name for diagnostics
    fn getTypeName(self: *SpecificityAnalyzer, type_id: TypeRegistry.TypeId) []const u8 {
        if (self.type_registry.getTypeInfo(type_id)) |type_info| {
            return type_info.name;
        }
        return "<unknown>";
    }

    /// Generate detailed ambiguity report
    pub fn generateAmbiguityReport(
        self: *SpecificityAnalyzer,
        ambiguous_match: *const SpecificityResult.AmbiguousMatch,
    ) ![]u8 {
        var report: std.ArrayList(u8) = .empty;
        defer report.deinit();

        try report.appendSlice("Ambiguous dispatch detected:\n");
        try report.writer().print("Call signature: (", .{});
        for (ambiguous_match.call_arg_types, 0..) |arg_type, i| {
            if (i > 0) try report.appendSlice(", ");
            try report.appendSlice(self.getTypeName(arg_type));
        }
        try report.appendSlice(")\n\n");

        try report.appendSlice("Conflicting implementations:\n");
        for (ambiguous_match.conflicting_implementations, 0..) |impl, i| {
            try report.writer().print("  {d}. {s} from {s} at {d}:{d}\n", .{
                i + 1,
                impl.function_id.name,
                impl.function_id.module,
                impl.source_location.start_line,
                impl.source_location.start_col,
            });

            try report.appendSlice("     Parameters: (");
            for (impl.param_type_ids, 0..) |param_type, j| {
                if (j > 0) try report.appendSlice(", ");
                try report.appendSlice(self.getTypeName(param_type));
            }
            try report.appendSlice(")\n");
        }

        try report.appendSlice("\nSuggestions:\n");
        try report.appendSlice("  1. Add a more specific implementation that handles this exact case\n");
        try report.appendSlice("  2. Use explicit type annotations at the call site\n");
        try report.appendSlice("  3. Use qualified names to call a specific implementation\n");

        return try report.toOwnedSlice(alloc);
    }

    /// Generate detailed no-match report
    pub fn generateNoMatchReport(
        self: *SpecificityAnalyzer,
        no_match: *const SpecificityResult.NoMatch,
    ) ![]u8 {
        var report: std.ArrayList(u8) = .empty;
        defer report.deinit();

        try report.appendSlice("No matching implementation found:\n");
        try report.writer().print("Call signature: (", .{});
        for (no_match.call_arg_types, 0..) |arg_type, i| {
            if (i > 0) try report.appendSlice(", ");
            try report.appendSlice(self.getTypeName(arg_type));
        }
        try report.appendSlice(")\n\n");

        try report.appendSlice("Available implementations:\n");
        for (no_match.available_implementations, 0..) |impl, i| {
            try report.writer().print("  {d}. {s} from {s} at {d}:{d}\n", .{
                i + 1,
                impl.function_id.name,
                impl.function_id.module,
                impl.source_location.start_line,
                impl.source_location.start_col,
            });

            try report.appendSlice("     Parameters: (");
            for (impl.param_type_ids, 0..) |param_type, j| {
                if (j > 0) try report.appendSlice(", ");
                try report.appendSlice(self.getTypeName(param_type));
            }
            try report.appendSlice(")\n");

            // Find rejection reason for this implementation
            for (no_match.rejection_reasons) |reason| {
                if (reason.implementation == impl) {
                    try report.writer().print("     Rejected: {s}\n", .{reason.reason});
                    break;
                }
            }
        }

        try report.appendSlice("\nSuggestions:\n");
        try report.appendSlice("  1. Add an implementation that handles these argument types\n");
        try report.appendSlice("  2. Check if argument types are correct\n");
        try report.appendSlice("  3. Consider adding implicit conversions if appropriate\n");

        return try report.toOwnedSlice(alloc);
    }
};

// ===== TESTS =====

test "SpecificityAnalyzer basic resolution" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    const i32_id = type_registry.getTypeId("i32").?;
    const i64_id = type_registry.getTypeId("i64").?;

    // Create implementations: one for i32, one for i64
    const impl_i32 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "test", .id = 1 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i32_id}),
        .return_type_id = i32_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer std.testing.allocator.free(impl_i32.param_type_ids);

    const impl_i64 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "test", .id = 2 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i64_id}),
        .return_type_id = i64_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 90,
    };
    defer std.testing.allocator.free(impl_i64.param_type_ids);

    const implementations = [_]SignatureAnalyzer.Implementation{ impl_i32, impl_i64 };

    // Test call with i32 - should select i32 implementation
    var result = try analyzer.findMostSpecific(&implementations, &[_]TypeRegistry.TypeId{i32_id});
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .unique => |selected| {
            try std.testing.expectEqual(i32_id, selected.param_type_ids[0]);
        },
        else => try std.testing.expect(false),
    }
}

test "SpecificityAnalyzer subtype resolution" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    // Create type hierarchy: i32 <: i64
    const i32_id = type_registry.getTypeId("i32").?;
    const i64_id = type_registry.getTypeId("i64").?;

    var analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    // Create implementations: specific i32 and general i64
    const impl_specific = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "test", .id = 1 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i32_id}),
        .return_type_id = i32_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer std.testing.allocator.free(impl_specific.param_type_ids);

    const impl_general = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "test", .id = 2 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i64_id}),
        .return_type_id = i64_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 90,
    };
    defer std.testing.allocator.free(impl_general.param_type_ids);

    const implementations = [_]SignatureAnalyzer.Implementation{ impl_specific, impl_general };

    // Test call with i32 - should select more specific i32 implementation
    var result = try analyzer.findMostSpecific(&implementations, &[_]TypeRegistry.TypeId{i32_id});
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .unique => |selected| {
            try std.testing.expectEqual(i32_id, selected.param_type_ids[0]);
            try std.testing.expectEqual(@as(u32, 1), selected.function_id.id);
        },
        else => try std.testing.expect(false),
    }
}

test "SpecificityAnalyzer ambiguity detection" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    const i32_id = type_registry.getTypeId("i32").?;

    // Create two implementations with identical signatures
    const impl1 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "module1", .id = 1 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i32_id}),
        .return_type_id = i32_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer std.testing.allocator.free(impl1.param_type_ids);

    const impl2 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "module2", .id = 2 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i32_id}),
        .return_type_id = i32_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer std.testing.allocator.free(impl2.param_type_ids);

    const implementations = [_]SignatureAnalyzer.Implementation{ impl1, impl2 };

    // Test call with i32 - should detect ambiguity
    var result = try analyzer.findMostSpecific(&implementations, &[_]TypeRegistry.TypeId{i32_id});
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .ambiguous => |amb| {
            try std.testing.expectEqual(@as(usize, 2), amb.conflicting_implementations.len);
        },
        else => try std.testing.expect(false),
    }
}

test "SpecificityAnalyzer no match detection" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    const i32_id = type_registry.getTypeId("i32").?;
    const string_id = type_registry.getTypeId("string").?;

    // Create implementation that takes i32
    const impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "test", .id = 1 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i32_id}),
        .return_type_id = i32_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer std.testing.allocator.free(impl.param_type_ids);

    const implementations = [_]SignatureAnalyzer.Implementation{impl};

    // Test call with string - should find no match
    var result = try analyzer.findMostSpecific(&implementations, &[_]TypeRegistry.TypeId{string_id});
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .no_match => |no_match| {
            try std.testing.expectEqual(@as(usize, 1), no_match.available_implementations.len);
            try std.testing.expectEqual(@as(usize, 1), no_match.rejection_reasons.len);
        },
        else => try std.testing.expect(false),
    }
}

test "SpecificityAnalyzer comparison" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    const i32_id = type_registry.getTypeId("i32").?;
    const i64_id = type_registry.getTypeId("i64").?;

    // Create implementations
    const impl_specific = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "test", .id = 1 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i32_id}),
        .return_type_id = i32_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer std.testing.allocator.free(impl_specific.param_type_ids);

    const impl_general = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "test", .id = 2 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i64_id}),
        .return_type_id = i64_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 90,
    };
    defer std.testing.allocator.free(impl_general.param_type_ids);

    // Compare specificity for i32 call
    var comparison = try analyzer.compareSpecificity(&impl_specific, &impl_general, &[_]TypeRegistry.TypeId{i32_id});
    defer comparison.deinit(std.testing.allocator);

    try std.testing.expect(comparison.is_more_specific);
    try std.testing.expect(comparison.has_strict_subtype);
    try std.testing.expect(comparison.distance_difference > 0);
}

test "SpecificityAnalyzer report generation" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    const i32_id = type_registry.getTypeId("i32").?;

    // Create ambiguous match
    const impl1 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "module1", .id = 1 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i32_id}),
        .return_type_id = i32_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan{ .file = "test.jan", .start_line = 10, .start_col = 5, .end_line = 10, .end_col = 15 },
        .specificity_rank = 100,
    };
    defer std.testing.allocator.free(impl1.param_type_ids);

    const impl2 = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "test", .module = "module2", .id = 2 },
        .param_type_ids = try std.testing.allocator.dupe(TypeRegistry.TypeId, &[_]TypeRegistry.TypeId{i32_id}),
        .return_type_id = i32_id,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan{ .file = "test2.jan", .start_line = 20, .start_col = 10, .end_line = 20, .end_col = 20 },
        .specificity_rank = 100,
    };
    defer std.testing.allocator.free(impl2.param_type_ids);

    const conflicting = [_]*const SignatureAnalyzer.Implementation{ &impl1, &impl2 };
    const call_args = [_]TypeRegistry.TypeId{i32_id};

    const ambiguous_match = SpecificityAnalyzer.SpecificityResult.AmbiguousMatch{
        .conflicting_implementations = try std.testing.allocator.dupe(*const SignatureAnalyzer.Implementation, &conflicting),
        .call_arg_types = try std.testing.allocator.dupe(TypeRegistry.TypeId, &call_args),
    };
    defer {
        var mut_match = ambiguous_match;
        mut_match.deinit(std.testing.allocator);
    }

    const report = try analyzer.generateAmbiguityReport(&ambiguous_match);
    defer std.testing.allocator.free(report);

    try std.testing.expect(std.mem.indexOf(u8, report, "Ambiguous dispatch detected") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "module1") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "module2") != null);
}
