// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const Allocator = std.mem.Allocator;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const Type = @import("type_registry.zig").Type;
const TypeId = @import("type_registry.zig").TypeId;
const ConversionRegistry = @import("conversion_registry.zig").ConversionRegistry;
const Conversion = @import("conversion_registry.zig").Conversion;
const ConversionPath = @import("conversion_registry.zig").ConversionPath;
const ScopedConversionPath = @import("scoped_conversion_path.zig").ScopedConversionPath;
const ConversionArena = @import("scoped_conversion_path.zig").ConversionArena;
const ScopeManager = @import("scope_manager.zig").ScopeManager;
const CandidateCollector = @import("candidate_collector.zig").CandidateCollector;
const CandidateSet = @import("candidate_collector.zig").CandidateSet;
const Candidate = @import("candidate_collector.zig").Candidate;
const FunctionDecl = @import("scope_manager.zig").FunctionDecl;

/// Call site information for resolution
pub const CallSite = struct {
    function_name: []const u8,
    argument_types: []const TypeId,
    source_location: SourceLocation,

    pub const SourceLocation = struct {
        file: []const u8,
        line: u32,
        column: u32,
        start_byte: u32,
        end_byte: u32,
    };
};

/// Match quality assessment for candidates
pub const MatchQuality = enum {
    exact, // Perfect type match, no conversions
    convertible, // Requires explicit conversions
    incompatible, // Cannot be made to work

    pub fn getScore(self: MatchQuality) u32 {
        return switch (self) {
            .exact => 1000,
            .convertible => 500,
            .incompatible => 0,
        };
    }
};

/// Compatible candidate with conversion information
pub const CompatibleCandidate = struct {
    candidate: Candidate,
    conversion_path: ScopedConversionPath,
    match_quality: MatchQuality,
    total_score: u32,

    pub fn deinit(self: *CompatibleCandidate) void {
        self.conversion_path.deinit();
    }

    pub fn calculateScore(self: *CompatibleCandidate) void {
        const quality_score = self.match_quality.getScore();
        const conversion_penalty = self.conversion_path.get().total_cost;
        self.total_score = if (quality_score > conversion_penalty)
            quality_score - conversion_penalty
        else
            0;
    }
};

/// Resolution result types
pub const ResolveResult = union(enum) {
    success: ResolvedCall,
    ambiguous: AmbiguityInfo,
    no_matches: NoMatchInfo,
    error_occurred: ResolutionError,

    pub const ResolvedCall = struct {
        target_function: *FunctionDecl,
        conversion_path: ScopedConversionPath,
        call_site: CallSite,
        resolution_metadata: ResolutionMetadata,

        pub fn deinit(self: *ResolvedCall) void {
            self.conversion_path.deinit();
        }
    };

    pub const AmbiguityInfo = struct {
        candidates: []CompatibleCandidate,
        reason: AmbiguityReason,
        call_site: CallSite,

        pub const AmbiguityReason = enum {
            multiple_exact_matches,
            equal_conversion_cost,
            equal_specificity,
        };

        pub fn deinit(self: *AmbiguityInfo, allocator: Allocator) void {
            for (self.candidates) |*candidate| {
                candidate.deinit();
            }
            allocator.free(self.candidates);
        }
    };

    pub const NoMatchInfo = struct {
        function_name: []const u8,
        argument_types: []const TypeId,
        available_functions: [][]const u8,
        call_site: CallSite,

        pub fn deinit(self: *NoMatchInfo, allocator: Allocator) void {
            for (self.available_functions) |name| {
                allocator.free(name);
            }
            allocator.free(self.available_functions);
        }
    };

    pub const ResolutionError = struct {
        message: []const u8,
        error_type: ErrorType,
        call_site: CallSite,

        pub const ErrorType = enum {
            internal_error,
            type_system_error,
            scope_error,
        };
    };

    pub const ResolutionMetadata = struct {
        candidates_considered: u32,
        resolution_time_ns: u64,
        disambiguation_method: []const u8,
    };

    pub fn deinit(self: *ResolveResult, allocator: Allocator) void {
        switch (self.*) {
            .success => |*success| success.deinit(),
            .ambiguous => |*ambiguous| ambiguous.deinit(allocator),
            .no_matches => |*no_matches| no_matches.deinit(allocator),
            .error_occurred => {}, // No cleanup needed for error messages (they're usually string literals)
        }
    }
};

/// Compatibility analyzer for type matching and conversion
pub const CompatibilityAnalyzer = struct {
    conversion_registry: *ConversionRegistry,
    type_registry: *TypeRegistry,
    allocator: Allocator,
    conversion_arena: ConversionArena,

    pub fn init(allocator: Allocator, type_registry: *TypeRegistry, conversion_registry: *ConversionRegistry) CompatibilityAnalyzer {
        return CompatibilityAnalyzer{
            .conversion_registry = conversion_registry,
            .type_registry = type_registry,
            .allocator = allocator,
            .conversion_arena = ConversionArena.init(allocator),
        };
    }

    pub fn deinit(self: *CompatibilityAnalyzer) void {
        self.conversion_arena.deinit();
    }

    pub fn analyze(self: *CompatibilityAnalyzer, candidates: CandidateSet, argument_types: []const TypeId) ![]CompatibleCandidate {
        var compatible: std.ArrayList(CompatibleCandidate) = .empty;

        for (candidates.viable_candidates) |candidate| {
            // Parse parameter types (simplified for now)
            const param_types = try self.parseParameterTypes(candidate.function.parameter_types);
            defer self.allocator.free(param_types);

            if (param_types.len != argument_types.len) continue;

            // Find conversion path using main allocator (we'll manage cleanup properly)
            var temp_path = try self.conversion_registry.findConversionPath(argument_types, param_types, self.allocator) orelse continue;
            defer temp_path.deinit();

            // Create owned scoped path for the candidate
            const scoped_path = try ScopedConversionPath.fromPath(temp_path).clone(self.allocator);

            const match_quality = self.assessMatchQuality(argument_types, param_types);

            var compatible_candidate = CompatibleCandidate{
                .candidate = candidate,
                .conversion_path = scoped_path,
                .match_quality = match_quality,
                .total_score = 0,
            };

            compatible_candidate.calculateScore();
            try compatible.append(compatible_candidate);
        }

        return try compatible.toOwnedSlice(alloc);
    }

    fn parseParameterTypes(self: *CompatibilityAnalyzer, param_str: []const u8) ![]TypeId {
        if (param_str.len == 0) return &[_]TypeId{};

        var types: std.ArrayList(TypeId) = .empty;
        var iterator = std.mem.splitScalar(u8, param_str, ',');

        while (iterator.next()) |type_name| {
            const trimmed = std.mem.trim(u8, type_name, " ");
            const type_obj = self.type_registry.getTypeByName(trimmed) orelse {
                // Unknown type, use invalid ID
                try types.append(TypeId.INVALID);
                continue;
            };
            try types.append(type_obj.id);
        }

        return try types.toOwnedSlice(alloc);
    }

    fn assessMatchQuality(self: *CompatibilityAnalyzer, arg_types: []const TypeId, param_types: []const TypeId) MatchQuality {
        _ = self;

        var exact_matches: u32 = 0;
        var convertible_matches: u32 = 0;

        for (arg_types, param_types) |arg_type, param_type| {
            if (arg_type.equals(param_type)) {
                exact_matches += 1;
            } else {
                convertible_matches += 1;
            }
        }

        if (exact_matches == arg_types.len) return .exact;
        if (convertible_matches > 0) return .convertible;
        return .incompatible;
    }
};

/// Disambiguation engine for selecting the best candidate
pub const DisambiguationEngine = struct {
    type_registry: *TypeRegistry,
    allocator: Allocator,

    pub fn init(allocator: Allocator, type_registry: *TypeRegistry) DisambiguationEngine {
        return DisambiguationEngine{
            .type_registry = type_registry,
            .allocator = allocator,
        };
    }

    pub fn select(self: *DisambiguationEngine, candidates: []CompatibleCandidate) !ResolveResult {
        if (candidates.len == 0) {
            return ResolveResult{ .no_matches = ResolveResult.NoMatchInfo{
                .function_name = "unknown",
                .argument_types = &[_]TypeId{},
                .available_functions = &[_][]const u8{},
                .call_site = undefined,
            } };
        }

        if (candidates.len == 1) {
            const cloned_path = try candidates[0].conversion_path.clone(self.allocator);
            return ResolveResult{ .success = ResolveResult.ResolvedCall{
                .target_function = candidates[0].candidate.function,
                .conversion_path = cloned_path,
                .call_site = undefined,
                .resolution_metadata = ResolveResult.ResolutionMetadata{
                    .candidates_considered = 1,
                    .resolution_time_ns = 0,
                    .disambiguation_method = "single_candidate",
                },
            } };
        }

        // Sort by total score (higher is better)
        const sorted_candidates = try self.allocator.dupe(CompatibleCandidate, candidates);
        defer self.allocator.free(sorted_candidates);
        std.sort.pdq(CompatibleCandidate, sorted_candidates, {}, compareByScore);

        const best_score = sorted_candidates[0].total_score;
        const best_candidates = self.filterByScore(sorted_candidates, best_score);

        if (best_candidates.len == 1) {
            const cloned_path = try best_candidates[0].conversion_path.clone(self.allocator);
            return ResolveResult{ .success = ResolveResult.ResolvedCall{
                .target_function = best_candidates[0].candidate.function,
                .conversion_path = cloned_path,
                .call_site = undefined,
                .resolution_metadata = ResolveResult.ResolutionMetadata{
                    .candidates_considered = @intCast(candidates.len),
                    .resolution_time_ns = 0,
                    .disambiguation_method = "score_based",
                },
            } };
        }

        // Apply specificity rules
        const most_specific = try self.applySpecificityRules(best_candidates);

        if (most_specific.len == 1) {
            const cloned_path = try most_specific[0].conversion_path.clone(self.allocator);
            return ResolveResult{ .success = ResolveResult.ResolvedCall{
                .target_function = most_specific[0].candidate.function,
                .conversion_path = cloned_path,
                .call_site = undefined,
                .resolution_metadata = ResolveResult.ResolutionMetadata{
                    .candidates_considered = @intCast(candidates.len),
                    .resolution_time_ns = 0,
                    .disambiguation_method = "specificity_rules",
                },
            } };
        }

        // Still ambiguous
        const ambiguous_candidates = try self.allocator.dupe(CompatibleCandidate, most_specific);
        return ResolveResult{ .ambiguous = ResolveResult.AmbiguityInfo{
            .candidates = ambiguous_candidates,
            .reason = .equal_specificity,
            .call_site = undefined,
        } };
    }

    fn compareByScore(context: void, a: CompatibleCandidate, b: CompatibleCandidate) bool {
        _ = context;
        return a.total_score > b.total_score;
    }

    fn filterByScore(self: *DisambiguationEngine, candidates: []CompatibleCandidate, target_score: u32) []CompatibleCandidate {
        _ = self;
        var count: usize = 0;
        for (candidates) |candidate| {
            if (candidate.total_score == target_score) {
                count += 1;
            } else {
                break; // Sorted, so we can stop here
            }
        }
        return candidates[0..count];
    }

    fn applySpecificityRules(self: *DisambiguationEngine, candidates: []CompatibleCandidate) ![]CompatibleCandidate {
        // For now, just return all candidates (specificity rules to be implemented)
        _ = self;
        return candidates;
    }
};

/// Main semantic resolver orchestrating the resolution pipeline
pub const SemanticResolver = struct {
    type_registry: *TypeRegistry,
    conversion_registry: *ConversionRegistry,
    scope_manager: *ScopeManager,
    candidate_collector: CandidateCollector,
    compatibility_analyzer: CompatibilityAnalyzer,
    disambiguation_engine: DisambiguationEngine,
    allocator: Allocator,

    pub fn init(
        allocator: Allocator,
        type_registry: *TypeRegistry,
        conversion_registry: *ConversionRegistry,
        scope_manager: *ScopeManager,
    ) SemanticResolver {
        return SemanticResolver{
            .type_registry = type_registry,
            .conversion_registry = conversion_registry,
            .scope_manager = scope_manager,
            .candidate_collector = CandidateCollector.init(allocator, scope_manager),
            .compatibility_analyzer = CompatibilityAnalyzer.init(allocator, type_registry, conversion_registry),
            .disambiguation_engine = DisambiguationEngine.init(allocator, type_registry),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SemanticResolver) void {
        self.compatibility_analyzer.deinit();
    }

    pub fn resolve(self: *SemanticResolver, call_site: CallSite) !ResolveResult {
        const start_time = compat_time.nanoTimestamp();

        // Phase 1: Collect candidates
        var candidates = self.candidate_collector.collect(call_site.function_name, @intCast(call_site.argument_types.len)) catch {
            return ResolveResult{ .error_occurred = ResolveResult.ResolutionError{
                .message = "Failed to collect candidates",
                .error_type = .scope_error,
                .call_site = call_site,
            } };
        };
        defer candidates.deinit();

        if (!candidates.hasViableCandidates()) {
            const available = try self.candidate_collector.getAvailableFunctions(self.allocator);
            return ResolveResult{ .no_matches = ResolveResult.NoMatchInfo{
                .function_name = call_site.function_name,
                .argument_types = call_site.argument_types,
                .available_functions = available,
                .call_site = call_site,
            } };
        }

        // Phase 2: Analyze compatibility
        const compatible = self.compatibility_analyzer.analyze(candidates, call_site.argument_types) catch {
            return ResolveResult{ .error_occurred = ResolveResult.ResolutionError{
                .message = "Failed to analyze compatibility",
                .error_type = .type_system_error,
                .call_site = call_site,
            } };
        };

        if (compatible.len == 0) {
            // Clean up since we're not passing ownership to ResolveResult
            for (compatible) |*candidate| {
                candidate.deinit();
            }
            self.allocator.free(compatible);
            const available = try self.candidate_collector.getAvailableFunctions(self.allocator);
            return ResolveResult{ .no_matches = ResolveResult.NoMatchInfo{
                .function_name = call_site.function_name,
                .argument_types = call_site.argument_types,
                .available_functions = available,
                .call_site = call_site,
            } };
        }

        // Phase 3: Disambiguate and select
        var result = try self.disambiguation_engine.select(compatible);

        // Clean up the original candidates since select() creates its own copies
        for (compatible) |*candidate| {
            candidate.deinit();
        }
        self.allocator.free(compatible);

        // Update timing information
        const end_time = compat_time.nanoTimestamp();
        const resolution_time = @as(u64, @intCast(end_time - start_time));

        switch (result) {
            .success => |*success| {
                success.resolution_metadata.resolution_time_ns = resolution_time;
                success.call_site = call_site;
            },
            .ambiguous => |*ambiguous| {
                ambiguous.call_site = call_site;
            },
            .no_matches => |*no_matches| {
                no_matches.call_site = call_site;
            },
            else => {},
        }

        return result;
    }

    pub fn resolveWithTypes(
        self: *SemanticResolver,
        function_name: []const u8,
        argument_types: []const TypeId,
        source_location: CallSite.SourceLocation,
    ) !ResolveResult {
        const call_site = CallSite{
            .function_name = function_name,
            .argument_types = argument_types,
            .source_location = source_location,
        };

        return self.resolve(call_site);
    }
};

// Tests
test "SemanticResolver basic resolution" {
    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    var scope_manager = try ScopeManager.init(std.testing.allocator);
    defer scope_manager.deinit();

    var resolver = SemanticResolver.init(
        std.testing.allocator,
        &type_registry,
        &conversion_registry,
        &scope_manager,
    );

    // Add a test function
    var function = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,i32",
        .return_type = "i32",
        .visibility = .public,
        .module_path = "",
        .source_location = FunctionDecl.SourceLocation{
            .file = "test.jan",
            .line = 1,
            .column = 1,
        },
    };

    try scope_manager.current_scope.addFunction(&function);

    // Test resolution
    const arg_types = [_]TypeId{ TypeId.I32, TypeId.I32 };
    const source_loc = CallSite.SourceLocation{
        .file = "test.jan",
        .line = 5,
        .column = 10,
        .start_byte = 100,
        .end_byte = 110,
    };

    var result = try resolver.resolveWithTypes("add", arg_types[0..], source_loc);
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .success => |success| {
            try std.testing.expectEqualStrings(success.target_function.name, "add");
            try std.testing.expect(success.resolution_metadata.candidates_considered == 1);
        },
        else => {
            try std.testing.expect(false); // Should have succeeded
        },
    }
}

test "SemanticResolver function not found" {
    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    var scope_manager = try ScopeManager.init(std.testing.allocator);
    defer scope_manager.deinit();

    var resolver = SemanticResolver.init(
        std.testing.allocator,
        &type_registry,
        &conversion_registry,
        &scope_manager,
    );

    const arg_types = [_]TypeId{TypeId.I32};
    const source_loc = CallSite.SourceLocation{
        .file = "test.jan",
        .line = 5,
        .column = 10,
        .start_byte = 100,
        .end_byte = 110,
    };

    var result = try resolver.resolveWithTypes("nonexistent", arg_types[0..], source_loc);
    defer switch (result) {
        .no_matches => |*no_matches| no_matches.deinit(std.testing.allocator),
        else => {},
    };

    switch (result) {
        .no_matches => |no_matches| {
            try std.testing.expectEqualStrings(no_matches.function_name, "nonexistent");
        },
        else => {
            try std.testing.expect(false); // Should have failed to find function
        },
    }
}

// TODO: Add conversion test once memory management is fixed
