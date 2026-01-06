// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;

/// StaticDispatch - Detects and optimizes static dispatch opportunities
///
/// This analyzer identifies when multiple dispatch can be resolved at compile time,
/// enabling zero-overhead static dispatch. It provides performance hints and warnings
/// about dispatch costs for performance-critical code.
pub const StaticDispatch = struct {
    /// Result of static dispatch analysis
    pub const StaticAnalysisResult = union(enum) {
        static_dispatch: StaticDispatchInfo,
        dynamic_dispatch: DynamicDispatchInfo,
        no_dispatch: NoDispatchInfo,

        pub const StaticDispatchInfo = struct {
            selected_implementation: *const SignatureAnalyzer.Implementation,
            optimization_level: OptimizationLevel,
            estimated_cost: u32, // In CPU cycles

            pub const OptimizationLevel = enum {
                direct_call, // Direct function call (0 overhead)
                inlined_call, // Function can be inlined
                specialized_call, // Specialized version generated
            };
        };

        pub const DynamicDispatchInfo = struct {
            dispatch_strategy: DispatchStrategy,
            estimated_cost: u32, // In CPU cycles
            cache_efficiency: CacheEfficiency,
            optimization_hints: []const OptimizationHint,

            pub const DispatchStrategy = enum {
                hash_table, // Hash table lookup
                decision_tree, // Decision tree traversal
                linear_search, // Linear search through candidates
                compressed_table, // Compressed multimethod table
            };

            pub const CacheEfficiency = enum {
                excellent, // < 5% cache misses expected
                good, // 5-15% cache misses
                fair, // 15-30% cache misses
                poor, // > 30% cache misses
            };

            pub const OptimizationHint = struct {
                hint_type: HintType,
                description: []const u8,
                estimated_improvement: f32, // Percentage improvement

                pub const HintType = enum {
                    seal_types,
                    reduce_implementations,
                    add_specialization,
                    use_static_types,
                };

                pub fn deinit(self: *OptimizationHint, allocator: std.mem.Allocator) void {
                    allocator.free(self.description);
                }
            };

            pub fn deinit(self: *DynamicDispatchInfo, allocator: std.mem.Allocator) void {
                for (self.optimization_hints) |hint| {
                    var mut_hint = hint;
                    mut_hint.deinit(allocator);
                }
                allocator.free(self.optimization_hints);
            }
        };

        pub const NoDispatchInfo = struct {
            reason: []const u8,
            suggestions: []const []const u8,

            pub fn deinit(self: *NoDispatchInfo, allocator: std.mem.Allocator) void {
                allocator.free(self.reason);
                for (self.suggestions) |suggestion| {
                    allocator.free(suggestion);
                }
                allocator.free(self.suggestions);
            }
        };

        pub fn deinit(self: *StaticAnalysisResult, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .static_dispatch => {}, // No cleanup needed
                .dynamic_dispatch => |*dyn| dyn.deinit(allocator),
                .no_dispatch => |*no_disp| no_disp.deinit(allocator),
            }
        }
    };

    /// Performance warning levels
    pub const PerformanceWarning = struct {
        level: Level,
        message: []const u8,
        location: SignatureAnalyzer.SourceSpan,
        estimated_overhead: u32, // In nanoseconds

        pub const Level = enum {
            info, // < 10ns overhead
            warning, // 10-100ns overhead
            err, // > 100ns overhead (renamed to avoid keyword conflict)
        };

        pub fn deinit(self: *PerformanceWarning, allocator: std.mem.Allocator) void {
            allocator.free(self.message);
        }
    };

    type_registry: *const TypeRegistry,
    signature_analyzer: *SignatureAnalyzer,
    specificity_analyzer: *SpecificityAnalyzer,
    allocator: std.mem.Allocator,

    // Performance thresholds (configurable)
    max_static_cost: u32 = 5, // cycles
    max_dynamic_cost: u32 = 50, // cycles
    warning_threshold: u32 = 20, // cycles

    pub fn init(
        allocator: std.mem.Allocator,
        type_registry: *const TypeRegistry,
        signature_analyzer: *SignatureAnalyzer,
        specificity_analyzer: *SpecificityAnalyzer,
    ) StaticDispatch {
        return StaticDispatch{
            .type_registry = type_registry,
            .signature_analyzer = signature_analyzer,
            .specificity_analyzer = specificity_analyzer,
            .allocator = allocator,
        };
    }

    /// Analyze a function call for static dispatch opportunities
    pub fn analyzeCall(
        self: *StaticDispatch,
        function_name: []const u8,
        call_arg_types: []const TypeRegistry.TypeId,
        call_location: SignatureAnalyzer.SourceSpan,
    ) !StaticAnalysisResult {
        const arity = @as(u32, @intCast(call_arg_types.len));

        // Get signature group
        const signature_group = self.signature_analyzer.getSignatureGroup(function_name, arity) orelse {
            const reason = try std.fmt.allocPrint(self.allocator, "No implementations found for function '{s}' with arity {d}", .{ function_name, arity });
            const suggestions = try self.allocator.alloc([]const u8, 1);
            suggestions[0] = try std.fmt.allocPrint(self.allocator, "Define an implementation for '{s}' with {d} parameters", .{ function_name, arity });

            return StaticAnalysisResult{
                .no_dispatch = StaticAnalysisResult.NoDispatchInfo{
                    .reason = reason,
                    .suggestions = suggestions,
                },
            };
        };

        // Check if static dispatch is possible
        if (self.canUseStaticDispatch(signature_group, call_arg_types)) {
            return try self.analyzeStaticDispatch(signature_group, call_arg_types, call_location);
        } else {
            return try self.analyzeDynamicDispatch(signature_group, call_arg_types, call_location);
        }
    }

    /// Check if static dispatch is possible for this call
    pub fn canUseStaticDispatch(
        self: *StaticDispatch,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
        call_arg_types: []const TypeRegistry.TypeId,
    ) bool {
        // Must be sealed to enable static dispatch
        if (!signature_group.is_sealed) return false;

        // All argument types must be sealed
        for (call_arg_types) |arg_type| {
            if (self.type_registry.getTypeInfo(arg_type)) |type_info| {
                if (!type_info.kind.isSealed()) return false;
            } else {
                return false; // Unknown type
            }
        }

        // Must have unambiguous resolution
        var result = self.specificity_analyzer.findMostSpecific(
            signature_group.implementations.items,
            call_arg_types,
        ) catch return false;
        defer result.deinit(self.allocator);

        return switch (result) {
            .unique => true,
            .ambiguous, .no_match => false,
        };
    }

    /// Analyze static dispatch opportunity
    fn analyzeStaticDispatch(
        self: *StaticDispatch,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
        call_arg_types: []const TypeRegistry.TypeId,
        call_location: SignatureAnalyzer.SourceSpan,
    ) !StaticAnalysisResult {
        _ = call_location; // TODO: Use for optimization hints

        var result = try self.specificity_analyzer.findMostSpecific(
            signature_group.implementations.items,
            call_arg_types,
        );
        defer result.deinit(self.allocator);

        const selected_impl = switch (result) {
            .unique => |impl| impl,
            else => unreachable, // Should not happen if canUseStaticDispatch returned true
        };

        // Determine optimization level
        const optimization_level = self.determineOptimizationLevel(selected_impl, call_arg_types);
        const estimated_cost = self.estimateStaticCost(optimization_level);

        return StaticAnalysisResult{
            .static_dispatch = StaticAnalysisResult.StaticDispatchInfo{
                .selected_implementation = selected_impl,
                .optimization_level = optimization_level,
                .estimated_cost = estimated_cost,
            },
        };
    }

    /// Analyze dynamic dispatch requirements
    fn analyzeDynamicDispatch(
        self: *StaticDispatch,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
        call_arg_types: []const TypeRegistry.TypeId,
        call_location: SignatureAnalyzer.SourceSpan,
    ) !StaticAnalysisResult {
        _ = call_location; // TODO: Use for location-specific hints

        const strategy = self.selectDispatchStrategy(signature_group, call_arg_types);
        const estimated_cost = self.estimateDynamicCost(strategy, signature_group.getImplementationCount());
        const cache_efficiency = self.estimateCacheEfficiency(strategy, signature_group.getImplementationCount());
        const hints = try self.generateOptimizationHints(signature_group, call_arg_types);

        return StaticAnalysisResult{
            .dynamic_dispatch = StaticAnalysisResult.DynamicDispatchInfo{
                .dispatch_strategy = strategy,
                .estimated_cost = estimated_cost,
                .cache_efficiency = cache_efficiency,
                .optimization_hints = hints,
            },
        };
    }

    /// Determine the best optimization level for static dispatch
    fn determineOptimizationLevel(
        self: *StaticDispatch,
        implementation: *const SignatureAnalyzer.Implementation,
        call_arg_types: []const TypeRegistry.TypeId,
    ) StaticAnalysisResult.StaticDispatchInfo.OptimizationLevel {
        _ = self;
        _ = call_arg_types;

        // Simple heuristics for now
        if (implementation.effects.isPure() and implementation.param_type_ids.len <= 2) {
            return .inlined_call;
        } else if (implementation.param_type_ids.len <= 4) {
            return .specialized_call;
        } else {
            return .direct_call;
        }
    }

    /// Estimate cost of static dispatch
    fn estimateStaticCost(
        self: *StaticDispatch,
        optimization_level: StaticAnalysisResult.StaticDispatchInfo.OptimizationLevel,
    ) u32 {
        _ = self;
        return switch (optimization_level) {
            .inlined_call => 0, // No overhead
            .specialized_call => 1, // Minimal overhead
            .direct_call => 2, // Direct call overhead
        };
    }

    /// Select the best dispatch strategy for dynamic dispatch
    fn selectDispatchStrategy(
        self: *StaticDispatch,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
        call_arg_types: []const TypeRegistry.TypeId,
    ) StaticAnalysisResult.DynamicDispatchInfo.DispatchStrategy {
        _ = self;
        _ = call_arg_types;

        const impl_count = signature_group.getImplementationCount();

        if (impl_count <= 3) {
            return .linear_search;
        } else if (impl_count <= 10) {
            return .decision_tree;
        } else if (impl_count <= 50) {
            return .hash_table;
        } else {
            return .compressed_table;
        }
    }

    /// Estimate cost of dynamic dispatch
    fn estimateDynamicCost(
        self: *StaticDispatch,
        strategy: StaticAnalysisResult.DynamicDispatchInfo.DispatchStrategy,
        impl_count: usize,
    ) u32 {
        _ = self;
        return switch (strategy) {
            .linear_search => @as(u32, @intCast(impl_count * 3)), // 3 cycles per comparison
            .decision_tree => @as(u32, @intCast(std.math.log2_int(usize, impl_count) * 5)), // 5 cycles per level
            .hash_table => 15, // Hash + lookup
            .compressed_table => 25, // Decompression + lookup
        };
    }

    /// Estimate cache efficiency
    fn estimateCacheEfficiency(
        self: *StaticDispatch,
        strategy: StaticAnalysisResult.DynamicDispatchInfo.DispatchStrategy,
        impl_count: usize,
    ) StaticAnalysisResult.DynamicDispatchInfo.CacheEfficiency {
        _ = self;
        return switch (strategy) {
            .linear_search => if (impl_count <= 3) .excellent else .fair,
            .decision_tree => if (impl_count <= 10) .good else .fair,
            .hash_table => .good,
            .compressed_table => if (impl_count > 100) .excellent else .good,
        };
    }

    /// Generate optimization hints for dynamic dispatch
    fn generateOptimizationHints(
        self: *StaticDispatch,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
        call_arg_types: []const TypeRegistry.TypeId,
    ) ![]StaticAnalysisResult.DynamicDispatchInfo.OptimizationHint {
        var hints = std.ArrayList(StaticAnalysisResult.DynamicDispatchInfo.OptimizationHint).init(self.allocator);

        // Check if types can be sealed
        var can_seal_types = true;
        for (call_arg_types) |arg_type| {
            if (self.type_registry.getTypeInfo(arg_type)) |type_info| {
                if (!type_info.kind.isSealed()) {
                    can_seal_types = false;
                    break;
                }
            }
        }

        if (can_seal_types and !signature_group.is_sealed) {
            try hints.append(StaticAnalysisResult.DynamicDispatchInfo.OptimizationHint{
                .hint_type = .seal_types,
                .description = try std.fmt.allocPrint(self.allocator, "Seal the signature group to enable static dispatch", .{}),
                .estimated_improvement = 80.0, // 80% improvement
            });
        }

        // Check for too many implementations
        const impl_count = signature_group.getImplementationCount();
        if (impl_count > 20) {
            try hints.append(StaticAnalysisResult.DynamicDispatchInfo.OptimizationHint{
                .hint_type = .reduce_implementations,
                .description = try std.fmt.allocPrint(self.allocator, "Consider reducing the number of implementations ({d}) for better performance", .{impl_count}),
                .estimated_improvement = 30.0,
            });
        }

        // Check for missing specializations
        var has_exact_match = false;
        for (signature_group.implementations.items) |impl| {
            if (impl.param_type_ids.len == call_arg_types.len) {
                var exact = true;
                for (impl.param_type_ids, call_arg_types) |param_type, call_type| {
                    if (param_type != call_type) {
                        exact = false;
                        break;
                    }
                }
                if (exact) {
                    has_exact_match = true;
                    break;
                }
            }
        }

        if (!has_exact_match) {
            try hints.append(StaticAnalysisResult.DynamicDispatchInfo.OptimizationHint{
                .hint_type = .add_specialization,
                .description = try std.fmt.allocPrint(self.allocator, "Add a specialized implementation for these exact argument types", .{}),
                .estimated_improvement = 50.0,
            });
        }

        return hints.toOwnedSlice();
    }

    /// Generate performance warnings for expensive dispatch
    pub fn generatePerformanceWarnings(
        self: *StaticDispatch,
        analysis_result: *const StaticAnalysisResult,
        call_location: SignatureAnalyzer.SourceSpan,
    ) ![]PerformanceWarning {
        var warnings = std.ArrayList(PerformanceWarning).init(self.allocator);

        switch (analysis_result.*) {
            .static_dispatch => |static_info| {
                if (static_info.estimated_cost > self.max_static_cost) {
                    try warnings.append(PerformanceWarning{
                        .level = .info,
                        .message = try std.fmt.allocPrint(self.allocator, "Static dispatch cost ({d} cycles) is higher than expected", .{static_info.estimated_cost}),
                        .location = call_location,
                        .estimated_overhead = static_info.estimated_cost,
                    });
                }
            },
            .dynamic_dispatch => |dynamic_info| {
                if (dynamic_info.estimated_cost > self.max_dynamic_cost) {
                    try warnings.append(PerformanceWarning{
                        .level = .err,
                        .message = try std.fmt.allocPrint(self.allocator, "Dynamic dispatch cost ({d} cycles) exceeds threshold", .{dynamic_info.estimated_cost}),
                        .location = call_location,
                        .estimated_overhead = dynamic_info.estimated_cost,
                    });
                } else if (dynamic_info.estimated_cost > self.warning_threshold) {
                    try warnings.append(PerformanceWarning{
                        .level = .warning,
                        .message = try std.fmt.allocPrint(self.allocator, "Dynamic dispatch cost ({d} cycles) may impact performance", .{dynamic_info.estimated_cost}),
                        .location = call_location,
                        .estimated_overhead = dynamic_info.estimated_cost,
                    });
                }

                if (dynamic_info.cache_efficiency == .poor) {
                    try warnings.append(PerformanceWarning{
                        .level = .warning,
                        .message = try std.fmt.allocPrint(self.allocator, "Poor cache efficiency expected for this dispatch pattern", .{}),
                        .location = call_location,
                        .estimated_overhead = dynamic_info.estimated_cost / 2, // Cache misses add ~50% overhead
                    });
                }
            },
            .no_dispatch => {
                try warnings.append(PerformanceWarning{
                    .level = .err,
                    .message = try std.fmt.allocPrint(self.allocator, "No dispatch possible - this will result in a compile error", .{}),
                    .location = call_location,
                    .estimated_overhead = 0,
                });
            },
        }

        return warnings.toOwnedSlice();
    }

    /// Get dispatch statistics for a signature group
    pub fn getDispatchStatistics(
        self: *StaticDispatch,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
    ) DispatchStatistics {
        var stats = DispatchStatistics{
            .total_implementations = signature_group.getImplementationCount(),
            .sealed_implementations = 0,
            .static_dispatch_eligible = 0,
            .average_specificity = 0.0,
            .max_dispatch_cost = 0,
        };

        var total_specificity: u64 = 0;

        for (signature_group.implementations.items) |impl| {
            total_specificity += impl.specificity_rank;

            // Check if implementation uses only sealed types
            var all_sealed = true;
            for (impl.param_type_ids) |param_type| {
                if (self.type_registry.getTypeInfo(param_type)) |type_info| {
                    if (!type_info.kind.isSealed()) {
                        all_sealed = false;
                        break;
                    }
                }
            }

            if (all_sealed) {
                stats.sealed_implementations += 1;
            }
        }

        if (stats.total_implementations > 0) {
            stats.average_specificity = @as(f32, @floatFromInt(total_specificity)) / @as(f32, @floatFromInt(stats.total_implementations));
        }

        // Estimate max dispatch cost
        const strategy = self.selectDispatchStrategy(signature_group, &.{}); // Empty args for estimation
        stats.max_dispatch_cost = self.estimateDynamicCost(strategy, stats.total_implementations);

        // Count static dispatch eligible calls (simplified)
        if (signature_group.is_sealed and stats.sealed_implementations == stats.total_implementations) {
            stats.static_dispatch_eligible = stats.total_implementations;
        }

        return stats;
    }

    pub const DispatchStatistics = struct {
        total_implementations: usize,
        sealed_implementations: usize,
        static_dispatch_eligible: usize,
        average_specificity: f32,
        max_dispatch_cost: u32,
    };
};

// ===== TESTS =====

test "StaticDispatch basic analysis" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var static_dispatch = StaticDispatch.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;

    // Add a simple implementation
    _ = try signature_analyzer.addImplementation(
        "test",
        "module",
        &[_]TypeRegistry.TypeId{i32_id},
        i32_id,
        SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        SignatureAnalyzer.SourceSpan.dummy(),
    );

    // Seal the signature group
    try signature_analyzer.sealSignatureGroup("test", 1);

    // Analyze the call
    var result = try static_dispatch.analyzeCall("test", &[_]TypeRegistry.TypeId{i32_id}, SignatureAnalyzer.SourceSpan.dummy());
    defer result.deinit(std.testing.allocator);

    // Should be static dispatch since all types are sealed
    switch (result) {
        .static_dispatch => |static_info| {
            try std.testing.expect(static_info.estimated_cost <= 5);
        },
        else => try std.testing.expect(false),
    }
}

test "StaticDispatch dynamic analysis" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var static_dispatch = StaticDispatch.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;

    // Add implementation but don't seal the signature group
    _ = try signature_analyzer.addImplementation(
        "test",
        "module",
        &[_]TypeRegistry.TypeId{i32_id},
        i32_id,
        SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        SignatureAnalyzer.SourceSpan.dummy(),
    );

    // Analyze the call
    var result = try static_dispatch.analyzeCall("test", &[_]TypeRegistry.TypeId{i32_id}, SignatureAnalyzer.SourceSpan.dummy());
    defer result.deinit(std.testing.allocator);

    // Should be dynamic dispatch since signature group is not sealed
    switch (result) {
        .dynamic_dispatch => |dynamic_info| {
            try std.testing.expect(dynamic_info.estimated_cost > 0);
            try std.testing.expect(dynamic_info.optimization_hints.len > 0);
        },
        else => try std.testing.expect(false),
    }
}

test "StaticDispatch no dispatch" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var static_dispatch = StaticDispatch.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;

    // Analyze call to non-existent function
    var result = try static_dispatch.analyzeCall("nonexistent", &[_]TypeRegistry.TypeId{i32_id}, SignatureAnalyzer.SourceSpan.dummy());
    defer result.deinit(std.testing.allocator);

    // Should be no dispatch
    switch (result) {
        .no_dispatch => |no_dispatch| {
            try std.testing.expect(no_dispatch.suggestions.len > 0);
        },
        else => try std.testing.expect(false),
    }
}

test "StaticDispatch performance warnings" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var static_dispatch = StaticDispatch.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    // Set low thresholds to trigger warnings
    static_dispatch.warning_threshold = 1;
    static_dispatch.max_dynamic_cost = 10;

    const i32_id = type_registry.getTypeId("i32").?;

    // Add many implementations to trigger expensive dispatch
    for (0..15) |i| {
        const module_name = try std.fmt.allocPrint(std.testing.allocator, "module{d}", .{i});
        defer std.testing.allocator.free(module_name);

        _ = try signature_analyzer.addImplementation(
            "test",
            module_name,
            &[_]TypeRegistry.TypeId{i32_id},
            i32_id,
            SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            SignatureAnalyzer.SourceSpan.dummy(),
        );
    }

    var result = try static_dispatch.analyzeCall("test", &[_]TypeRegistry.TypeId{i32_id}, SignatureAnalyzer.SourceSpan.dummy());
    defer result.deinit(std.testing.allocator);

    const warnings = try static_dispatch.generatePerformanceWarnings(&result, SignatureAnalyzer.SourceSpan.dummy());
    defer {
        for (warnings) |*warning| {
            warning.deinit(std.testing.allocator);
        }
        std.testing.allocator.free(warnings);
    }

    // Should generate performance warnings
    try std.testing.expect(warnings.len > 0);
}

test "StaticDispatch statistics" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var static_dispatch = StaticDispatch.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;
    const f64_id = type_registry.getTypeId("f64").?;

    // Add implementations
    _ = try signature_analyzer.addImplementation("test", "module1", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try signature_analyzer.addImplementation("test", "module2", &[_]TypeRegistry.TypeId{f64_id}, f64_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const signature_group = static_dispatch.signature_analyzer.getSignatureGroup("test", 1).?;
    const stats = static_dispatch.getDispatchStatistics(signature_group);

    try std.testing.expectEqual(@as(usize, 2), stats.total_implementations);
    try std.testing.expectEqual(@as(usize, 2), stats.sealed_implementations); // Primitives are sealed
    try std.testing.expect(stats.average_specificity > 0);
    try std.testing.expect(stats.max_dispatch_cost > 0);
}
