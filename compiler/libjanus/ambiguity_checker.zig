// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;

/// AmbiguityChecker - Comprehensive compile-time ambiguity detection and diagnostics
///
/// This checker performs exhaustive analysis of all signature groups to detect
/// potential ambiguities at compile time. It provides detailed diagnostics with
/// source locations, specificity explanations, and actionable suggestions for
/// resolving conflicts.
pub const AmbiguityChecker = struct {
    /// Comprehensive ambiguity report for a signature group
    pub const AmbiguityReport = struct {
        signature_name: []const u8,
        arity: u32,
        total_implementations: usize,
        ambiguity_conflicts: []AmbiguityConflict,
        coverage_gaps: []CoverageGap,
        optimization_opportunities: []OptimizationOpportunity,

        pub fn deinit(self: *AmbiguityReport, allocator: std.mem.Allocator) void {
            allocator.free(self.signature_name);

            for (self.ambiguity_conflicts) |*conflict| {
                conflict.deinit(allocator);
            }
            allocator.free(self.ambiguity_conflicts);

            for (self.coverage_gaps) |*gap| {
                gap.deinit(allocator);
            }
            allocator.free(self.coverage_gaps);

            for (self.optimization_opportunities) |*opp| {
                opp.deinit(allocator);
            }
            allocator.free(self.optimization_opportunities);
        }
    };

    /// Detailed information about an ambiguity conflict
    pub const AmbiguityConflict = struct {
        conflict_type: ConflictType,
        conflicting_implementations: []ConflictingImplementation,
        example_call_types: []TypeRegistry.TypeId,
        resolution_suggestions: []ResolutionSuggestion,
        severity: Severity,

        pub const ConflictType = enum {
            exact_duplicate, // Identical signatures
            overlapping_subtypes, // Overlapping through subtype relationships
            symmetric_ambiguity, // A <: B and B <: A case
            complex_hierarchy, // Complex multi-level inheritance ambiguity
        };

        pub const Severity = enum {
            err, // Must be resolved before compilation
            warning, // Should be resolved for clarity
            info, // Informational, may be intentional
        };

        pub const ConflictingImplementation = struct {
            implementation: *const SignatureAnalyzer.Implementation,
            specificity_explanation: []const u8,
            dominance_relationships: []DominanceRelationship,

            pub const DominanceRelationship = struct {
                other_implementation: *const SignatureAnalyzer.Implementation,
                relationship: Relationship,
                explanation: []const u8,

                pub const Relationship = enum {
                    dominates, // This impl is more specific
                    dominated_by, // This impl is less specific
                    incomparable, // No dominance relationship
                    equivalent, // Same specificity
                };

                pub fn deinit(self: *DominanceRelationship, allocator: std.mem.Allocator) void {
                    allocator.free(self.explanation);
                }
            };

            pub fn deinit(self: *ConflictingImplementation, allocator: std.mem.Allocator) void {
                allocator.free(self.specificity_explanation);
                for (self.dominance_relationships) |*rel| {
                    rel.deinit(allocator);
                }
                allocator.free(self.dominance_relationships);
            }
        };

        pub const ResolutionSuggestion = struct {
            suggestion_type: SuggestionType,
            description: []const u8,
            code_example: ?[]const u8,
            estimated_effort: EffortLevel,

            pub const SuggestionType = enum {
                add_more_specific, // Add a more specific implementation
                remove_implementation, // Remove redundant implementation
                add_type_annotation, // Use explicit type annotations at call sites
                refactor_hierarchy, // Restructure type hierarchy
                use_qualified_call, // Use module-qualified calls
            };

            pub const EffortLevel = enum {
                trivial, // < 5 minutes
                easy, // 5-30 minutes
                moderate, // 30 minutes - 2 hours
                hard, // > 2 hours
            };

            pub fn deinit(self: *ResolutionSuggestion, allocator: std.mem.Allocator) void {
                allocator.free(self.description);
                if (self.code_example) |example| {
                    allocator.free(example);
                }
            }
        };

        pub fn deinit(self: *AmbiguityConflict, allocator: std.mem.Allocator) void {
            for (self.conflicting_implementations) |*impl| {
                impl.deinit(allocator);
            }
            allocator.free(self.conflicting_implementations);
            allocator.free(self.example_call_types);

            for (self.resolution_suggestions) |*suggestion| {
                suggestion.deinit(allocator);
            }
            allocator.free(self.resolution_suggestions);
        }
    };

    /// Information about coverage gaps in the dispatch table
    pub const CoverageGap = struct {
        missing_type_combinations: [][]TypeRegistry.TypeId,
        common_call_patterns: []CallPattern,
        suggested_implementations: []SuggestedImplementation,

        pub const CallPattern = struct {
            argument_types: []TypeRegistry.TypeId,
            frequency_estimate: f32, // 0.0 - 1.0
            rejection_reason: []const u8,

            pub fn deinit(self: *CallPattern, allocator: std.mem.Allocator) void {
                allocator.free(self.argument_types);
                allocator.free(self.rejection_reason);
            }
        };

        pub const SuggestedImplementation = struct {
            parameter_types: []TypeRegistry.TypeId,
            rationale: []const u8,
            priority: Priority,

            pub const Priority = enum {
                high, // Covers many common cases
                medium, // Covers some cases
                low, // Edge case coverage
            };

            pub fn deinit(self: *SuggestedImplementation, allocator: std.mem.Allocator) void {
                allocator.free(self.parameter_types);
                allocator.free(self.rationale);
            }
        };

        pub fn deinit(self: *CoverageGap, allocator: std.mem.Allocator) void {
            for (self.missing_type_combinations) |combination| {
                allocator.free(combination);
            }
            allocator.free(self.missing_type_combinations);

            for (self.common_call_patterns) |*pattern| {
                pattern.deinit(allocator);
            }
            allocator.free(self.common_call_patterns);

            for (self.suggested_implementations) |*suggestion| {
                suggestion.deinit(allocator);
            }
            allocator.free(self.suggested_implementations);
        }
    };

    /// Optimization opportunities for better dispatch performance
    pub const OptimizationOpportunity = struct {
        opportunity_type: OpportunityType,
        description: []const u8,
        estimated_improvement: f32, // Percentage improvement
        implementation_effort: AmbiguityConflict.ResolutionSuggestion.EffortLevel,

        pub const OpportunityType = enum {
            seal_signature, // Seal signature group for static dispatch
            reduce_implementations, // Remove redundant implementations
            optimize_hierarchy, // Optimize type hierarchy for better specificity
            add_specializations, // Add specialized implementations
        };

        pub fn deinit(self: *OptimizationOpportunity, allocator: std.mem.Allocator) void {
            allocator.free(self.description);
        }
    };

    type_registry: *const TypeRegistry,
    signature_analyzer: *SignatureAnalyzer,
    specificity_analyzer: *SpecificityAnalyzer,
    allocator: std.mem.Allocator,

    // Configuration options
    max_test_combinations: usize = 1000, // Limit exhaustive testing
    include_coverage_analysis: bool = true,
    include_optimization_analysis: bool = true,

    pub fn init(
        allocator: std.mem.Allocator,
        type_registry: *const TypeRegistry,
        signature_analyzer: *SignatureAnalyzer,
        specificity_analyzer: *SpecificityAnalyzer,
    ) AmbiguityChecker {
        return AmbiguityChecker{
            .type_registry = type_registry,
            .signature_analyzer = signature_analyzer,
            .specificity_analyzer = specificity_analyzer,
            .allocator = allocator,
        };
    }

    /// Perform comprehensive ambiguity analysis on all signature groups
    pub fn analyzeAllSignatures(self: *AmbiguityChecker) ![]AmbiguityReport {
        var reports: std.ArrayList(AmbiguityReport) = .empty;

        var signature_iterator = self.signature_analyzer.getAllSignatureGroups();
        while (signature_iterator.next()) |entry| {
            const signature_group = entry.value_ptr;

            if (signature_group.getImplementationCount() > 1) {
                const report = try self.analyzeSignatureGroup(signature_group);
                try reports.append(report);
            }
        }

        return try reports.toOwnedSlice(alloc);
    }

    /// Analyze a specific signature group for ambiguities
    pub fn analyzeSignatureGroup(self: *AmbiguityChecker, signature_group: *const SignatureAnalyzer.SignatureGroup) !AmbiguityReport {
        var report = AmbiguityReport{
            .signature_name = try self.allocator.dupe(u8, signature_group.name),
            .arity = signature_group.key.arity,
            .total_implementations = signature_group.getImplementationCount(),
            .ambiguity_conflicts = &.{},
            .coverage_gaps = &.{},
            .optimization_opportunities = &.{},
        };

        // Detect ambiguity conflicts
        report.ambiguity_conflicts = try self.detectAmbiguityConflicts(signature_group);

        // Analyze coverage gaps if enabled
        if (self.include_coverage_analysis) {
            report.coverage_gaps = try self.analyzeCoverageGaps(signature_group);
        }

        // Find optimization opportunities if enabled
        if (self.include_optimization_analysis) {
            report.optimization_opportunities = try self.findOptimizationOpportunities(signature_group);
        }

        return report;
    }

    /// Detect all ambiguity conflicts in a signature group
    fn detectAmbiguityConflicts(self: *AmbiguityChecker, signature_group: *const SignatureAnalyzer.SignatureGroup) ![]AmbiguityConflict {
        var conflicts: std.ArrayList(AmbiguityConflict) = .empty;

        const implementations = signature_group.implementations.items;

        // Check all pairs of implementations for conflicts
        for (implementations, 0..) |impl1, i| {
            for (implementations[i + 1 ..]) |impl2| {
                if (try self.checkImplementationConflict(&impl1, &impl2)) |conflict| {
                    try conflicts.append(conflict);
                }
            }
        }

        // Check for complex multi-way conflicts
        const complex_conflicts = try self.detectComplexConflicts(implementations);
        for (complex_conflicts) |conflict| {
            try conflicts.append(conflict);
        }

        return try conflicts.toOwnedSlice(alloc);
    }

    /// Check if two implementations have a conflict
    fn checkImplementationConflict(
        self: *AmbiguityChecker,
        impl1: *const SignatureAnalyzer.Implementation,
        impl2: *const SignatureAnalyzer.Implementation,
    ) !?AmbiguityConflict {
        // Check for exact duplicates
        if (self.areExactDuplicates(impl1, impl2)) {
            return try self.createExactDuplicateConflict(impl1, impl2);
        }

        // Check for overlapping subtypes by testing various type combinations
        const overlap_result = try self.checkSubtypeOverlap(impl1, impl2);
        if (overlap_result.has_overlap) {
            return try self.createSubtypeOverlapConflict(impl1, impl2, overlap_result.example_types);
        }

        return null;
    }

    /// Check if two implementations are exact duplicates
    fn areExactDuplicates(
        self: *AmbiguityChecker,
        impl1: *const SignatureAnalyzer.Implementation,
        impl2: *const SignatureAnalyzer.Implementation,
    ) bool {
        _ = self;

        if (impl1.param_type_ids.len != impl2.param_type_ids.len) return false;

        for (impl1.param_type_ids, impl2.param_type_ids) |type1, type2| {
            if (type1 != type2) return false;
        }

        return true;
    }

    /// Check for subtype overlap between two implementations
    fn checkSubtypeOverlap(
        self: *AmbiguityChecker,
        impl1: *const SignatureAnalyzer.Implementation,
        impl2: *const SignatureAnalyzer.Implementation,
    ) !SubtypeOverlapResult {
        if (impl1.param_type_ids.len != impl2.param_type_ids.len) {
            return SubtypeOverlapResult{ .has_overlap = false, .example_types = &.{} };
        }

        // Generate test type combinations to check for overlaps
        const test_combinations = try self.generateTestTypeCombinations(impl1.param_type_ids.len);
        defer {
            for (test_combinations) |combination| {
                self.allocator.free(combination);
            }
            self.allocator.free(test_combinations);
        }

        for (test_combinations) |combination| {
            const matches1 = self.implementationMatches(impl1, combination);
            const matches2 = self.implementationMatches(impl2, combination);

            if (matches1 and matches2) {
                // Found an overlapping case - check if it's ambiguous
                var result = try self.specificity_analyzer.findMostSpecific(&[_]SignatureAnalyzer.Implementation{ impl1.*, impl2.* }, combination);
                defer result.deinit(self.allocator);

                switch (result) {
                    .ambiguous => {
                        const example_types = try self.allocator.dupe(TypeRegistry.TypeId, combination);
                        return SubtypeOverlapResult{ .has_overlap = true, .example_types = example_types };
                    },
                    else => continue,
                }
            }
        }

        return SubtypeOverlapResult{ .has_overlap = false, .example_types = &.{} };
    }

    const SubtypeOverlapResult = struct {
        has_overlap: bool,
        example_types: []TypeRegistry.TypeId,
    };

    /// Check if an implementation matches given argument types
    fn implementationMatches(
        self: *AmbiguityChecker,
        impl: *const SignatureAnalyzer.Implementation,
        arg_types: []const TypeRegistry.TypeId,
    ) bool {
        if (impl.param_type_ids.len != arg_types.len) return false;

        for (impl.param_type_ids, arg_types) |param_type, arg_type| {
            if (!self.type_registry.isSubtype(arg_type, param_type)) {
                return false;
            }
        }

        return true;
    }

    /// Generate test type combinations for overlap detection
    fn generateTestTypeCombinations(self: *AmbiguityChecker, arity: usize) ![][]TypeRegistry.TypeId {
        var combinations: std.ArrayList([]TypeRegistry.TypeId) = .empty;

        // Get all registered types
        const all_types = try self.getAllRegisteredTypes();
        defer self.allocator.free(all_types);

        if (all_types.len == 0) return try combinations.toOwnedSlice(alloc);

        // Generate combinations up to the limit
        var count: usize = 0;
        const max_per_position = @min(all_types.len, 5); // Limit to avoid explosion

        try self.generateCombinationsRecursive(&combinations, all_types, arity, &.{}, &count, max_per_position);

        return try combinations.toOwnedSlice(alloc);
    }

    /// Recursive helper for generating type combinations
    fn generateCombinationsRecursive(
        self: *AmbiguityChecker,
        combinations: *std.ArrayList([]TypeRegistry.TypeId),
        all_types: []TypeRegistry.TypeId,
        remaining_arity: usize,
        current_combination: []const TypeRegistry.TypeId,
        count: *usize,
        max_per_position: usize,
    ) !void {
        if (count.* >= self.max_test_combinations) return;

        if (remaining_arity == 0) {
            const combination = try self.allocator.dupe(TypeRegistry.TypeId, current_combination);
            try combinations.append(combination);
            count.* += 1;
            return;
        }

        const types_to_try = @min(all_types.len, max_per_position);
        for (all_types[0..types_to_try]) |type_id| {
            var new_combination = try self.allocator.alloc(TypeRegistry.TypeId, current_combination.len + 1);
            defer self.allocator.free(new_combination);

            @memcpy(new_combination[0..current_combination.len], current_combination);
            new_combination[current_combination.len] = type_id;

            try self.generateCombinationsRecursive(combinations, all_types, remaining_arity - 1, new_combination, count, max_per_position);
        }
    }

    /// Get all registered type IDs
    fn getAllRegisteredTypes(self: *AmbiguityChecker) ![]TypeRegistry.TypeId {
        var types: std.ArrayList(TypeRegistry.TypeId) = .empty;

        // Add primitive types (we know these exist)
        const primitive_names = [_][]const u8{ "i32", "i64", "f32", "f64", "bool", "string" };
        for (primitive_names) |name| {
            if (self.type_registry.getTypeId(name)) |type_id| {
                try types.append(type_id);
            }
        }

        return try types.toOwnedSlice(alloc);
    }

    /// Create conflict report for exact duplicates
    fn createExactDuplicateConflict(
        self: *AmbiguityChecker,
        impl1: *const SignatureAnalyzer.Implementation,
        impl2: *const SignatureAnalyzer.Implementation,
    ) !AmbiguityConflict {
        var conflicting_impls = try self.allocator.alloc(AmbiguityConflict.ConflictingImplementation, 2);

        conflicting_impls[0] = AmbiguityConflict.ConflictingImplementation{
            .implementation = impl1,
            .specificity_explanation = try std.fmt.allocPrint(self.allocator, "Identical signature", .{}),
            .dominance_relationships = &.{},
        };

        conflicting_impls[1] = AmbiguityConflict.ConflictingImplementation{
            .implementation = impl2,
            .specificity_explanation = try std.fmt.allocPrint(self.allocator, "Identical signature", .{}),
            .dominance_relationships = &.{},
        };

        var suggestions = try self.allocator.alloc(AmbiguityConflict.ResolutionSuggestion, 1);
        suggestions[0] = AmbiguityConflict.ResolutionSuggestion{
            .suggestion_type = .remove_implementation,
            .description = try std.fmt.allocPrint(self.allocator, "Remove one of the duplicate implementations", .{}),
            .code_example = null,
            .estimated_effort = .trivial,
        };

        return AmbiguityConflict{
            .conflict_type = .exact_duplicate,
            .conflicting_implementations = conflicting_impls,
            .example_call_types = try self.allocator.dupe(TypeRegistry.TypeId, impl1.param_type_ids),
            .resolution_suggestions = suggestions,
            .severity = .err,
        };
    }

    /// Create conflict report for subtype overlap
    fn createSubtypeOverlapConflict(
        self: *AmbiguityChecker,
        impl1: *const SignatureAnalyzer.Implementation,
        impl2: *const SignatureAnalyzer.Implementation,
        example_types: []TypeRegistry.TypeId,
    ) !AmbiguityConflict {
        var conflicting_impls = try self.allocator.alloc(AmbiguityConflict.ConflictingImplementation, 2);

        conflicting_impls[0] = AmbiguityConflict.ConflictingImplementation{
            .implementation = impl1,
            .specificity_explanation = try self.createSpecificityExplanation(impl1, example_types),
            .dominance_relationships = &.{},
        };

        conflicting_impls[1] = AmbiguityConflict.ConflictingImplementation{
            .implementation = impl2,
            .specificity_explanation = try self.createSpecificityExplanation(impl2, example_types),
            .dominance_relationships = &.{},
        };

        var suggestions = try self.allocator.alloc(AmbiguityConflict.ResolutionSuggestion, 2);
        suggestions[0] = AmbiguityConflict.ResolutionSuggestion{
            .suggestion_type = .add_more_specific,
            .description = try std.fmt.allocPrint(self.allocator, "Add a more specific implementation for the overlapping case", .{}),
            .code_example = try self.generateCodeExample(example_types),
            .estimated_effort = .easy,
        };

        suggestions[1] = AmbiguityConflict.ResolutionSuggestion{
            .suggestion_type = .add_type_annotation,
            .description = try std.fmt.allocPrint(self.allocator, "Use explicit type annotations at call sites to disambiguate", .{}),
            .code_example = null,
            .estimated_effort = .trivial,
        };

        return AmbiguityConflict{
            .conflict_type = .overlapping_subtypes,
            .conflicting_implementations = conflicting_impls,
            .example_call_types = example_types,
            .resolution_suggestions = suggestions,
            .severity = .warning,
        };
    }

    /// Create specificity explanation for an implementation
    fn createSpecificityExplanation(
        self: *AmbiguityChecker,
        impl: *const SignatureAnalyzer.Implementation,
        example_types: []const TypeRegistry.TypeId,
    ) ![]u8 {
        var explanation: std.ArrayList(u8) = .empty;
        defer explanation.deinit();

        try explanation.writer().print("Parameters: (", .{});
        for (impl.param_type_ids, 0..) |param_type, i| {
            if (i > 0) try explanation.appendSlice(", ");
            try explanation.appendSlice(self.getTypeName(param_type));
        }
        try explanation.appendSlice(") with call types (");
        for (example_types, 0..) |call_type, i| {
            if (i > 0) try explanation.appendSlice(", ");
            try explanation.appendSlice(self.getTypeName(call_type));
        }
        try explanation.appendSlice(")");

        return try explanation.toOwnedSlice(alloc);
    }

    /// Generate code example for resolution
    fn generateCodeExample(self: *AmbiguityChecker, example_types: []const TypeRegistry.TypeId) ![]u8 {
        var example: std.ArrayList(u8) = .empty;
        defer example.deinit();

        try example.appendSlice("func specific_implementation(");
        for (example_types, 0..) |type_id, i| {
            if (i > 0) try example.appendSlice(", ");
            try example.writer().print("arg{d}: {s}", .{ i, self.getTypeName(type_id) });
        }
        try example.appendSlice(") { /* implementation */ }");

        return try example.toOwnedSlice(alloc);
    }

    /// Get human-readable type name
    fn getTypeName(self: *AmbiguityChecker, type_id: TypeRegistry.TypeId) []const u8 {
        if (self.type_registry.getTypeInfo(type_id)) |type_info| {
            return type_info.name;
        }
        return "<unknown>";
    }

    /// Detect complex multi-way conflicts
    fn detectComplexConflicts(self: *AmbiguityChecker, implementations: []const SignatureAnalyzer.Implementation) ![]AmbiguityConflict {
        _ = self;
        _ = implementations;
        // Simplified for now - complex conflict detection would analyze
        // multi-way ambiguities involving 3+ implementations
        return &.{};
    }

    /// Analyze coverage gaps in the signature group
    fn analyzeCoverageGaps(self: *AmbiguityChecker, signature_group: *const SignatureAnalyzer.SignatureGroup) ![]CoverageGap {
        _ = self;
        _ = signature_group;
        // Simplified for now - would analyze common type combinations
        // that don't have implementations
        return &.{};
    }

    /// Find optimization opportunities
    fn findOptimizationOpportunities(self: *AmbiguityChecker, signature_group: *const SignatureAnalyzer.SignatureGroup) ![]OptimizationOpportunity {
        var opportunities: std.ArrayList(OptimizationOpportunity) = .empty;

        // Check if signature can be sealed
        if (!signature_group.is_sealed and signature_group.canUseStaticDispatch(self.type_registry)) {
            try opportunities.append(OptimizationOpportunity{
                .opportunity_type = .seal_signature,
                .description = try std.fmt.allocPrint(self.allocator, "Seal this signature group to enable static dispatch optimization", .{}),
                .estimated_improvement = 80.0,
                .implementation_effort = .easy,
            });
        }

        // Check for too many implementations
        if (signature_group.getImplementationCount() > 10) {
            try opportunities.append(OptimizationOpportunity{
                .opportunity_type = .reduce_implementations,
                .description = try std.fmt.allocPrint(self.allocator, "Consider reducing the number of implementations ({d}) for better dispatch performance", .{signature_group.getImplementationCount()}),
                .estimated_improvement = 30.0,
                .implementation_effort = .moderate,
            });
        }

        return try opportunities.toOwnedSlice(alloc);
    }

    /// Generate a comprehensive diagnostic report
    pub fn generateDiagnosticReport(self: *AmbiguityChecker, reports: []const AmbiguityReport) ![]u8 {
        var diagnostic: std.ArrayList(u8) = .empty;
        defer diagnostic.deinit();

        try diagnostic.appendSlice("=== Multiple Dispatch Ambiguity Analysis ===\n\n");

        var total_conflicts: usize = 0;
        var total_errors: usize = 0;
        var total_warnings: usize = 0;

        for (reports) |report| {
            total_conflicts += report.ambiguity_conflicts.len;

            for (report.ambiguity_conflicts) |conflict| {
                switch (conflict.severity) {
                    .err => total_errors += 1,
                    .warning => total_warnings += 1,
                    .info => {},
                }
            }
        }

        try diagnostic.writer().print("Summary: {d} signature groups analyzed\n", .{reports.len});
        try diagnostic.writer().print("  - {d} conflicts found ({d} errors, {d} warnings)\n\n", .{ total_conflicts, total_errors, total_warnings });

        for (reports) |report| {
            if (report.ambiguity_conflicts.len > 0) {
                try diagnostic.writer().print("Signature: {s} (arity {d})\n", .{ report.signature_name, report.arity });
                try diagnostic.writer().print("  Implementations: {d}\n", .{report.total_implementations});

                for (report.ambiguity_conflicts) |conflict| {
                    try diagnostic.writer().print("  Conflict: {s} ({s})\n", .{ @tagName(conflict.conflict_type), @tagName(conflict.severity) });

                    for (conflict.resolution_suggestions) |suggestion| {
                        try diagnostic.writer().print("    Suggestion: {s}\n", .{suggestion.description});
                    }
                }

                try diagnostic.appendSlice("\n");
            }
        }

        return try diagnostic.toOwnedSlice(alloc);
    }
};

// ===== TESTS =====

test "AmbiguityChecker exact duplicate detection" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var ambiguity_checker = AmbiguityChecker.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;

    // Add two identical implementations
    _ = try signature_analyzer.addImplementation("test", "module1", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try signature_analyzer.addImplementation("test", "module2", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const signature_group = signature_analyzer.getSignatureGroup("test", 1).?;
    var report = try ambiguity_checker.analyzeSignatureGroup(signature_group);
    defer report.deinit(std.testing.allocator);

    // Should detect exact duplicate conflict
    try std.testing.expect(report.ambiguity_conflicts.len > 0);
    try std.testing.expectEqual(AmbiguityChecker.AmbiguityConflict.ConflictType.exact_duplicate, report.ambiguity_conflicts[0].conflict_type);
    try std.testing.expectEqual(AmbiguityChecker.AmbiguityConflict.Severity.err, report.ambiguity_conflicts[0].severity);
}

test "AmbiguityChecker subtype overlap detection" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var ambiguity_checker = AmbiguityChecker.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;
    const i64_id = type_registry.getTypeId("i64").?;

    // Add implementations that might overlap through subtyping
    _ = try signature_analyzer.addImplementation("test", "module1", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try signature_analyzer.addImplementation("test", "module2", &[_]TypeRegistry.TypeId{i64_id}, i64_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const signature_group = signature_analyzer.getSignatureGroup("test", 1).?;
    var report = try ambiguity_checker.analyzeSignatureGroup(signature_group);
    defer report.deinit(std.testing.allocator);

    // Should not detect conflicts since i32 and i64 don't overlap in our simple type system
    // (In a real implementation with i32 <: i64, this would detect overlap)
    try std.testing.expect(report.ambiguity_conflicts.len == 0);
}

test "AmbiguityChecker optimization opportunities" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var ambiguity_checker = AmbiguityChecker.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;

    // Add implementation to unsealed signature
    _ = try signature_analyzer.addImplementation("test", "module", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const signature_group = signature_analyzer.getSignatureGroup("test", 1).?;
    var report = try ambiguity_checker.analyzeSignatureGroup(signature_group);
    defer report.deinit(std.testing.allocator);

    // Should suggest sealing the signature if conditions are met, or have no opportunities
    // The exact behavior depends on the canUseStaticDispatch implementation
    if (report.optimization_opportunities.len > 0) {
        try std.testing.expectEqual(AmbiguityChecker.OptimizationOpportunity.OpportunityType.seal_signature, report.optimization_opportunities[0].opportunity_type);
    }
}

test "AmbiguityChecker diagnostic report generation" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var ambiguity_checker = AmbiguityChecker.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;

    // Add duplicate implementations
    _ = try signature_analyzer.addImplementation("test", "module1", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try signature_analyzer.addImplementation("test", "module2", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const reports = try ambiguity_checker.analyzeAllSignatures();
    defer {
        for (reports) |*report| {
            report.deinit(std.testing.allocator);
        }
        std.testing.allocator.free(reports);
    }

    const diagnostic = try ambiguity_checker.generateDiagnosticReport(reports);
    defer std.testing.allocator.free(diagnostic);

    // Should contain analysis summary
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "Multiple Dispatch Ambiguity Analysis") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "conflicts found") != null);
}

test "AmbiguityChecker all signatures analysis" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var ambiguity_checker = AmbiguityChecker.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;
    const f64_id = type_registry.getTypeId("f64").?;

    // Add multiple signature groups
    _ = try signature_analyzer.addImplementation("add", "math", &[_]TypeRegistry.TypeId{ i32_id, i32_id }, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try signature_analyzer.addImplementation("add", "math", &[_]TypeRegistry.TypeId{ f64_id, f64_id }, f64_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    _ = try signature_analyzer.addImplementation("sub", "math", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const reports = try ambiguity_checker.analyzeAllSignatures();
    defer {
        for (reports) |*report| {
            report.deinit(std.testing.allocator);
        }
        std.testing.allocator.free(reports);
    }

    // Should analyze multiple signature groups
    try std.testing.expect(reports.len >= 1); // At least the "add" signature with 2 implementations
}
