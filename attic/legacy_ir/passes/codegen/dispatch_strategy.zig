// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Dispatch Strategy Selection - The Intelligence Behind the Voice
//!
//! This module contains the sophisticated logic that determines how the compiler
//! should emit code for each call site. It analyzes call patterns, frequency,
//! and complexity to choose the optimal dispatch strategy.
//!
//! M6: Forge the Executable Artifact - Intelligence in Code Generation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

// Import shared codegen types directly to avoid module cycles
const types = @import("types.zig");
const CallSite = types.CallSite;
const Strategy = types.Strategy;
const FamilyId = types.FamilyId;

/// Performance characteristics for strategy selection
pub const PerformanceProfile = struct {
    call_frequency: f64,
    argument_count: u32,
    return_complexity: f64,
    branch_factor: u32,
    cache_locality: f64,

    pub fn fromCallSite(site: CallSite) PerformanceProfile {
        return PerformanceProfile{
            .call_frequency = @as(f64, site.hotness),
            .argument_count = @intCast(site.arg_types.len),
            .return_complexity = 1.0, // TODO: Calculate based on return type
            .branch_factor = 1, // TODO: Calculate based on call patterns
            .cache_locality = 0.8, // TODO: Analyze based on call prns
        };
    }

    /// Calculate the optimization potential score
    pub fn optimizationPotential(self: PerformanceProfile) f64 {
        // Higher frequency calls benefit more from optimization
        const frequency_weight = @min(self.call_frequency / 1000.0, 10.0);

        // Simpler calls are easier to optimize
        const complexity_penalty = @as(f64, @floatFromInt(self.argument_count)) * 0.1;

        // Better cache locality improves optimization effectiveness
        const locality_bonus = self.cache_locality * 2.0;

        return frequency_weight + locality_bonus - complexity_penalty;
    }
};

/// Strategy effectiveness metrics for learning and adaptation
pub const StrategyEffectiveness = struct {
    strategy: Strategy,
    performance_gain: f64,
    code_size_impact: f64,
    compilation_time: f64,
    success_rate: f64,

    // Enhanced profiling data
    execution_time_ns: u64,
    cache_miss_rate: f64,
    branch_misprediction_rate: f64,
    instruction_count: u64,

    // Failure tracking
    failure_count: u32,
    fallback_triggered: bool,
    error_details: ?[]const u8,

    pub fn calculateScore(self: StrategyEffectiveness) f64 {
        // Enhanced weighted score considering multiple factors
        const perf_weight = 0.4;
        const size_weight = 0.15;
        const compile_weight = 0.1;
        const success_weight = 0.25;
        const cache_weight = 0.1;

        // Penalize failures heavily
        const failure_penalty = @as(f64, @floatFromInt(self.failure_count)) * 2.0;
        const fallback_penalty = if (self.fallback_triggered) @as(f64, 1.0) else @as(f64, 0.0);

        const base_score = (self.performance_gain * perf_weight) +
            (1.0 / (1.0 + self.code_size_impact) * size_weight) +
            (1.0 / (1.0 + self.compilation_time) * compile_weight) +
            (self.success_rate * success_weight) +
            ((1.0 - self.cache_miss_rate) * cache_weight);

        return @max(0.0, base_score - failure_penalty - fallback_penalty);
    }

    /// Create effectiveness metrics from profiling data
    pub fn fromProfilingData(strategy: Strategy, execution_time_ns: u64, instruction_count: u64, cache_miss_rate: f64, branch_misprediction_rate: f64, code_size_bytes: u64, compilation_time_ms: f64, success: bool, fallback_used: bool, error_msg: ?[]const u8) StrategyEffectiveness {
        // Calculate performance gain relative to baseline (naive dispatch)
        const baseline_time_ns: u64 = 1000; // Assume 1μs baseline
        const performance_gain = if (execution_time_ns > 0)
            @as(f64, @floatFromInt(baseline_time_ns)) / @as(f64, @floatFromInt(execution_time_ns))
        else
            1.0;

        return StrategyEffectiveness{
            .strategy = strategy,
            .performance_gain = performance_gain,
            .code_size_impact = @as(f64, @floatFromInt(code_size_bytes)) / 1024.0, // KB
            .compilation_time = compilation_time_ms,
            .success_rate = if (success) 1.0 else 0.0,
            .execution_time_ns = execution_time_ns,
            .cache_miss_rate = cache_miss_rate,
            .branch_misprediction_rate = branch_misprediction_rate,
            .instruction_count = instruction_count,
            .failure_count = if (success) 0 else 1,
            .fallback_triggered = fallback_used,
            .error_details = error_msg,
        };
    }
};

/// Context for Strategy HashMap operations
const StrategyContext = struct {
    pub fn hash(self: @This(), strategy: Strategy) u64 {
        _ = self;
        return switch (strategy) {
            .Static => 1,
            .SwitchTable => 2,
            .PerfectHash => 3,
            .InlineCache => 4,
        };
    }

    pub fn eql(self: @This(), a: Strategy, b: Strategy) bool {
        _ = self;
        return std.meta.eql(a, b);
    }
};

/// Advanced strategy selector with machine learning-inspired heuristics
pub const AdvancedStrategySelector = struct {
    allocator: Allocator,
    strategy_history: ArrayList(StrategyDecision),
    effectiveness_data: ArrayList(StrategyEffectiveness),

    // Strategy selection thresholds (tunable)
    direct_call_threshold: f64 = 1000.0,
    switch_threshold_args: u32 = 4,
    jump_table_density_threshold: f64 = 0.6,
    perfect_hash_collision_threshold: f64 = 0.1,

    pub const StrategyDecision = struct {
        site: CallSite,
        profile: PerformanceProfile,
        selected_strategy: Strategy,
        alternatives_considered: []Strategy,
        selection_rationale: []const u8,
        confidence_score: f64,
        timestamp: i64,

        // Enhanced AI-auditable data
        decision_factors: DecisionFactors,
        fallback_chain: []Strategy,
        risk_assessment: RiskAssessment,
        expected_performance: PerformanceProjection,
    };

    /// Detailed factors that influenced the strategy decision
    pub const DecisionFactors = struct {
        frequency_weight: f64,
        complexity_weight: f64,
        cache_locality_weight: f64,
        code_size_constraint: f64,
        compilation_time_constraint: f64,
        historical_success_rate: f64,

        pub fn toRationale(self: DecisionFactors, allocator: Allocator) ![]const u8 {
            return std.fmt.allocPrint(allocator, "Decision factors: freq={d:.2}, complexity={d:.2}, locality={d:.2}, " ++
                "size_constraint={d:.2}, compile_time={d:.2}, success_rate={d:.2}", .{ self.frequency_weight, self.complexity_weight, self.cache_locality_weight, self.code_size_constraint, self.compilation_time_constraint, self.historical_success_rate });
        }
    };

    /// Risk assessment for the selected strategy
    pub const RiskAssessment = struct {
        compilation_failure_risk: f64, // 0.0 = no risk, 1.0 = certain failure
        runtime_performance_risk: f64,
        code_size_explosion_risk: f64,
        maintenance_complexity_risk: f64,

        pub fn overallRisk(self: RiskAssessment) f64 {
            return (self.compilation_failure_risk + self.runtime_performance_risk +
                self.code_size_explosion_risk + self.maintenance_complexity_risk) / 4.0;
        }
    };

    /// Performance projections for the selected strategy
    pub const PerformanceProjection = struct {
        expected_speedup: f64,
        expected_code_size_ratio: f64,
        expected_compilation_time_ms: f64,
        confidence_interval: f64, // ±percentage
    };

    pub fn init(allocator: Allocator) AdvancedStrategySelector {
        return AdvancedStrategySelector{
            .allocator = allocator,
            .strategy_history = .empty,
            .effectiveness_data = .empty,
        };
    }

    pub fn deinit(self: *AdvancedStrategySelector) void {
        for (self.strategy_history.items) |decision| {
            self.allocator.free(decision.alternatives_considered);
            self.allocator.free(decision.selection_rationale);
        }
        self.strategy_history.deinit();
        self.effectiveness_data.deinit();
    }

    /// Select the optimal strategy for a call site using advanced heuristics with fallback
    pub fn selectOptimalStrategy(self: *AdvancedStrategySelector, site: CallSite) !Strategy {
        return self.selectOptimalStrategyWithFallback(site, null);
    }

    /// Select strategy with explicit fallback chain for failure recovery
    pub fn selectOptimalStrategyWithFallback(self: *AdvancedStrategySelector, site: CallSite, excluded_strategies: ?[]const Strategy) !Strategy {
        const profile = PerformanceProfile.fromCallSite(site);
        const optimization_potential = profile.optimizationPotential();

        // Build exclusion set for fallback scenarios
        var excluded_set = std.HashMap(Strategy, void, StrategyContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer excluded_set.deinit();

        if (excluded_strategies) |excluded| {
            for (excluded) |strategy| {
                try excluded_set.put(strategy, {});
            }
        }

        // Analyze alternatives and select the best one
        var alternatives: ArrayList(Strategy) = .empty;
        defer alternatives.deinit();

        var fallback_chain: ArrayList(Strategy) = .empty;
        defer fallback_chain.deinit();

        var best_strategy: Strategy = undefined;
        var best_score: f64 = -1.0;
        var rationale: []const u8 = undefined;
        // Note: decision_factors and risk_assessment are computed only when
        // advanced telemetry is enabled. Remove unused locals for now to keep
        // zls clean.

        // Evaluate direct call strategy
        if (profile.call_frequency >= self.direct_call_threshold) {
            const strategy = Strategy.Static;

            const score = self.evaluateDirectCallStrategy(profile);
            try alternatives.append(strategy);

            if (score > best_score) {
                best_score = score;
                best_strategy = strategy;
                rationale = "Direct call selected for high-frequency optimization";
            }
        }

        // Evaluate switch dispatch strategy
        if (profile.argument_count <= self.switch_threshold_args) {
            const strategy = Strategy.SwitchTable;

            const score = self.evaluateSwitchStrategy(profile);
            try alternatives.append(strategy);

            if (score > best_score) {
                best_score = score;
                best_strategy = strategy;
                rationale = "Switch dispatch selected for manageable complexity";
            }
        }

        // Evaluate jump table strategy
        if (profile.branch_factor >= 4 and profile.cache_locality >= self.jump_table_density_threshold) {
            const strategy = Strategy.SwitchTable;

            const score = self.evaluateJumpTableStrategy(profile);
            try alternatives.append(strategy);

            if (score > best_score) {
                best_score = score;
                best_strategy = strategy;
                rationale = "Jump table selected for complex dispatch with good locality";
            }
        }

        // Evaluate perfect hash strategy (for sparse but predictable dispatch)
        if (profile.branch_factor >= 8 and optimization_potential > 5.0) {
            const strategy = Strategy.PerfectHash;

            const score = self.evaluatePerfectHashStrategy(profile);
            try alternatives.append(strategy);

            if (score > best_score) {
                best_score = score;
                best_strategy = strategy;
                rationale = "Perfect hash selected for large, optimizable dispatch space";
            }
        }

        // Fallback to inline cache for complex cases
        if (best_score < 0.0) {
            best_strategy = Strategy.InlineCache;
            rationale = "Inline cache selected as robust fallback strategy";
            best_score = 3.0; // Reasonable baseline score
        }

        // Record the decision for learning and auditability
        const decision = StrategyDecision{
            .site = site,
            .profile = profile,
            .selected_strategy = best_strategy,
            .alternatives_considered = try alternatives.toOwnedSlice(),
            .selection_rationale = try self.allocator.dupe(u8, rationale),
            .confidence_score = best_score,
            .timestamp = std.time.timestamp(),
            .decision_factors = .{
                .frequency_weight = 1.0,
                .complexity_weight = 1.0,
                .cache_locality_weight = 1.0,
                .code_size_constraint = 1.0,
                .compilation_time_constraint = 1.0,
                .historical_success_rate = 0.8,
            },
            .fallback_chain = &.{},
            .risk_assessment = .{
                .compilation_failure_risk = 0.1,
                .runtime_performance_risk = 0.1,
                .code_size_explosion_risk = 0.1,
                .maintenance_complexity_risk = 0.1,
            },
            .expected_performance = .{
                .expected_speedup = 1.0,
                .expected_code_size_ratio = 1.0,
                .expected_compilation_time_ms = 1.0,
                .confidence_interval = 0.1,
            },
        };

        try self.strategy_history.append(decision);

        return best_strategy;
    }

    /// Evaluate the effectiveness of a direct call strategy
    fn evaluateDirectCallStrategy(self: *AdvancedStrategySelector, profile: PerformanceProfile) f64 {
        _ = self;

        // Direct calls are most effective for high-frequency, simple calls
        const frequency_factor = @min(profile.call_frequency / 1000.0, 5.0);
        const simplicity_factor = 1.0 / (1.0 + @as(f64, @floatFromInt(profile.argument_count)) * 0.2);

        return frequency_factor * simplicity_factor * 2.0;
    }

    /// Evaluate the effectiveness of a switch dispatch strategy
    fn evaluateSwitchStrategy(self: *AdvancedStrategySelector, profile: PerformanceProfile) f64 {
        _ = self;

        // Switch dispatch works well for moderate complexity with good branch prediction
        const complexity_factor = 1.0 / (1.0 + @as(f64, @floatFromInt(profile.argument_count)) * 0.3);
        const frequency_factor = @min(profile.call_frequency / 500.0, 3.0);

        return complexity_factor * frequency_factor * 1.5;
    }

    /// Evaluate the effectiveness of a jump table strategy
    fn evaluateJumpTableStrategy(self: *AdvancedStrategySelector, profile: PerformanceProfile) f64 {
        _ = self;

        // Jump tables excel with high branch factors and good cache locality
        const branch_factor = @as(f64, @floatFromInt(profile.branch_factor));
        const locality_bonus = profile.cache_locality * 2.0;
        const density_factor = @min(branch_factor / 8.0, 2.0);

        return density_factor * locality_bonus * 1.8;
    }

    /// Evaluate the effectiveness of a perfect hash strategy
    fn evaluatePerfectHashStrategy(self: *AdvancedStrategySelector, profile: PerformanceProfile) f64 {
        _ = self;

        // Perfect hash is best for large, sparse dispatch spaces with high optimization potential
        const optimization_factor = profile.optimizationPotential() / 10.0;
        const sparsity_factor = @as(f64, @floatFromInt(profile.branch_factor)) / 16.0;

        return optimization_factor * sparsity_factor * 2.2;
    }

    /// Learn from strategy effectiveness feedback
    pub fn recordEffectiveness(self: *AdvancedStrategySelector, strategy: Strategy, effectiveness: StrategyEffectiveness) !void {
        // Currently, 'strategy' is only used for potential future analytics.
        // Silence unused parameter warning while keeping API stable.
        _ = strategy;
        try self.effectiveness_data.append(effectiveness);

        // Adapt thresholds based on effectiveness data
        try self.adaptThresholds();
    }

    /// Get historical success rate for a specific strategy
    pub fn getHistoricalSuccessRate(self: *AdvancedStrategySelector, strategy: Strategy) f64 {
        var total_count: u32 = 0;
        var success_count: u32 = 0;

        for (self.effectiveness_data.items) |data| {
            if (std.meta.eql(data.strategy, strategy)) {
                total_count += 1;
                if (data.success_rate > 0.5) { // Consider >50% success rate as successful
                    success_count += 1;
                }
            }
        }

        return if (total_count > 0)
            @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(total_count))
        else
            0.8; // Default optimistic success rate for new strategies
    }

    /// Create a fallback strategy when primary strategy fails
    pub fn createFallbackStrategy(self: *AdvancedStrategySelector, failed_strategy: Strategy, site: CallSite) !Strategy {
        _ = self;
        _ = site;
        // Fallback hierarchy: Complex -> Simple -> Most Reliable
        return switch (failed_strategy) {
            .PerfectHash => .SwitchTable, // Perfect hash failed -> try switch table
            .SwitchTable => .Static, // Switch table failed -> try direct call
            .InlineCache => .SwitchTable, // Inline cache failed -> try switch table
            .Static => .InlineCache, // Direct call failed -> try inline cache as last resort
        };
    }

    /// Record a strategy failure and trigger fallback
    pub fn recordFailureAndFallback(self: *AdvancedStrategySelector, failed_strategy: Strategy, site: CallSite, error_msg: []const u8) !Strategy {
        // Record the failure
        const failure_effectiveness = StrategyEffectiveness.fromProfilingData(failed_strategy, 0, // No execution time due to failure
            0, // No instructions executed
            1.0, // Assume worst-case cache performance
            1.0, // Assume worst-case branch prediction
            0, // No code generated
            1000.0, // High compilation time due to failure
            false, // Failed
            true, // Fallback triggered
            error_msg);

        try self.recordEffectiveness(failed_strategy, failure_effectiveness);

        // Select fallback strategy
        const fallback_strategy = try self.createFallbackStrategy(failed_strategy, site);

        std.log.warn("Strategy {} failed for family {}, falling back to {}", .{ failed_strategy, site.family, fallback_strategy });

        return fallback_strategy;
    }

    /// Adapt selection thresholds based on historical effectiveness
    fn adaptThresholds(self: *AdvancedStrategySelector) !void {
        if (self.effectiveness_data.items.len < 10) return; // Need sufficient data

        // Analyze effectiveness patterns and adjust thresholds
        var direct_call_successes: f64 = 0;
        var direct_call_count: f64 = 0;

        for (self.effectiveness_data.items) |data| {
            switch (data.strategy) {
                .Static => {
                    direct_call_count += 1;
                    if (data.calculateScore() > 4.0) {
                        direct_call_successes += 1;
                    }
                },
                else => {},
            }
        }

        // Adjust direct call threshold based on success rate
        if (direct_call_count > 0) {
            const success_rate = direct_call_successes / direct_call_count;
            if (success_rate > 0.8) {
                self.direct_call_threshold *= 0.9; // Lower threshold for successful strategy
            } else if (success_rate < 0.6) {
                self.direct_call_threshold *= 1.1; // Raise threshold for less successful strategy
            }
        }
    }

    /// Get strategy selection statistics for analysis
    pub fn getSelectionStatistics(self: *AdvancedStrategySelector) StrategyStatistics {
        var stats = StrategyStatistics{};

        for (self.strategy_history.items) |decision| {
            stats.total_decisions += 1;
            stats.average_confidence += decision.confidence_score;

            switch (decision.selected_strategy) {
                .Static => stats.direct_call_count += 1,
                .SwitchTable => stats.switch_dispatch_count += 1,
                .PerfectHash => stats.perfect_hash_count += 1,
                .InlineCache => stats.inline_cache_count += 1,
            }
        }

        if (stats.total_decisions > 0) {
            stats.average_confidence /= @as(f64, @floatFromInt(stats.total_decisions));
        }

        return stats;
    }

    pub const StrategyStatistics = struct {
        total_decisions: u32 = 0,
        direct_call_count: u32 = 0,
        switch_dispatch_count: u32 = 0,
        jump_table_count: u32 = 0,
        perfect_hash_count: u32 = 0,
        inline_cache_count: u32 = 0,
        average_confidence: f64 = 0.0,

        pub fn print(self: StrategyStatistics) void {
            std.debug.print("Strategy Selection Statistics:\n", .{});
            std.debug.print("  Total Decisions: {}\n", .{self.total_decisions});
            std.debug.print("  Direct Calls: {} ({d:.1}%)\n", .{ self.direct_call_count, @as(f64, @floatFromInt(self.direct_call_count)) / @as(f64, @floatFromInt(self.total_decisions)) * 100.0 });
            std.debug.print("  Switch Dispatch: {} ({d:.1}%)\n", .{ self.switch_dispatch_count, @as(f64, @floatFromInt(self.switch_dispatch_count)) / @as(f64, @floatFromInt(self.total_decisions)) * 100.0 });
            std.debug.print("  Jump Tables: {} ({d:.1}%)\n", .{ self.jump_table_count, @as(f64, @floatFromInt(self.jump_table_count)) / @as(f64, @floatFromInt(self.total_decisions)) * 100.0 });
            std.debug.print("  Perfect Hash: {} ({d:.1}%)\n", .{ self.perfect_hash_count, @as(f64, @floatFromInt(self.perfect_hash_count)) / @as(f64, @floatFromInt(self.total_decisions)) * 100.0 });
            std.debug.print("  Inline Cache: {} ({d:.1}%)\n", .{ self.inline_cache_count, @as(f64, @floatFromInt(self.inline_cache_count)) / @as(f64, @floatFromInt(self.total_decisions)) * 100.0 });
            std.debug.print("  Average Confidence: {d:.2}\n", .{self.average_confidence});
        }
    };
};

/// Family-based strategy optimization for related call sites
pub const FamilyOptimizer = struct {
    allocator: Allocator,
    families: std.HashMap(FamilyId, FamilyData, std.HashMap.DefaultContext(FamilyId), std.HashMap.default_max_load_percentage),

    const FamilyData = struct {
        call_sites: ArrayList(CallSite),
        collective_frequency: f64,
        optimization_strategy: ?Strategy,
        effectiveness_score: f64,
    };

    pub fn init(allocator: Allocator) FamilyOptimizer {
        return FamilyOptimizer{
            .allocator = allocator,
            .families = std.HashMap(FamilyId, FamilyData, std.HashMap.DefaultContext(FamilyId), std.HashMap.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *FamilyOptimizer) void {
        var iterator = self.families.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.call_sites.deinit();
        }
        self.families.deinit();
    }

    /// Add a call site to a family for collective optimization
    pub fn addToFamily(self: *FamilyOptimizer, family_id: FamilyId, site: CallSite) !void {
        const result = try self.families.getOrPut(family_id);
        if (!result.found_existing) {
            result.value_ptr.* = FamilyData{
                .call_sites = .empty,
                .collective_frequency = 0.0,
                .optimization_strategy = null,
                .effectiveness_score = 0.0,
            };
        }

        try result.value_ptr.call_sites.append(site);
        result.value_ptr.collective_frequency += @as(f64, site.hotness);
    }

    /// Optimize strategy selection for an entire family
    pub fn optimizeFamily(self: *FamilyOptimizer, family_id: FamilyId) !?Strategy {
        const family_data = self.families.get(family_id) orelse return null;

        // Analyze family characteristics
        const total_frequency = family_data.collective_frequency;
        const member_count = family_data.call_sites.items.len;

        if (member_count == 0) return null;

        // Calculate average complexity
        var total_args: u32 = 0;
        for (family_data.call_sites.items) |site| {
            total_args += @intCast(site.arg_types.len);
        }
        const avg_args = @as(f64, @floatFromInt(total_args)) / @as(f64, @floatFromInt(member_count));

        // Select family-wide optimization strategy
        if (total_frequency > 5000.0 and member_count <= 8) {
            // High-frequency, small family -> specialized dispatch table
            return Strategy{
                .jump_table = .{
                    .table_size = @intCast(member_count * 2),
                    .density = 0.8,
                    .rationale = "High-frequency family optimized with specialized dispatch table",
                },
            };
        } else if (avg_args <= 3.0 and member_count <= 16) {
            // Simple calls, moderate family -> switch-based family dispatch
            return Strategy{
                .switch_dispatch = .{
                    .case_count = @intCast(member_count),
                    .default_target = null,
                    .rationale = "Simple call family optimized with switch-based dispatch",
                },
            };
        } else if (member_count > 16) {
            // Large family -> perfect hash dispatch
            return Strategy{
                .perfect_hash = .{
                    .hash_function = try std.fmt.allocPrint(self.allocator, "family_{}_hash", .{family_id}),
                    .collision_rate = 0.1,
                    .rationale = "Large call family optimized with perfect hash dispatch",
                },
            };
        }

        // Fallback to inline cache for complex families
        return Strategy{
            .inline_cache = .{
                .cache_size = @min(member_count, 8),
                .hit_rate = 0.75,
                .rationale = "Complex call family using adaptive inline cache",
            },
        };
    }
};

// Tests for the advanced strategy selection
test "PerformanceProfile calculation" {
    const testing = std.testing;

    const high_freq_site = CallSite{
        .unit_id = 1,
        .loc = .{ .file_id = 1, .start_line = 10, .start_col = 5, .end_line = 10, .end_col = 6 },
        .family = 42,
        .arg_types = &[_]u32{ 1, 2 },
        .hotness = 5000.0,
    };

    const profile = PerformanceProfile.fromCallSite(high_freq_site);
    try testing.expect(profile.call_frequency == 5000.0);
    try testing.expect(profile.argument_count == 2);

    const potential = profile.optimizationPotential();
    try testing.expect(potential > 5.0); // High optimization potential
}

test "AdvancedStrategySelector selection logic" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var selector = AdvancedStrategySelector.init(allocator);
    defer selector.deinit();

    // Test high-frequency call -> direct call
    const high_freq_site = CallSite{
        .unit_id = 1,
        .loc = .{ .file_id = 1, .start_line = 10, .start_col = 5, .end_line = 10, .end_col = 6 },
        .family = 7,
        .arg_types = &[_]u32{1},
        .hotness = 2000.0,
    };

    const strategy = try selector.selectOptimalStrategy(high_freq_site);
    try testing.expect(strategy == .direct_call);

    // Verify decision was recorded
    try testing.expect(selector.strategy_history.items.len == 1);
    try testing.expect(selector.strategy_history.items[0].confidence_score > 0.0);
}

test "FamilyOptimizer collective optimization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var optimizer = FamilyOptimizer.init(allocator);
    defer optimizer.deinit();

    const family_id: FamilyId = 100;

    // Add multiple call sites to family
    const sites = [_]CallSite{
        .{
            .unit_id = 1,
            .loc = .{ .file_id = 1, .start_line = 10, .start_col = 5, .end_line = 10, .end_col = 6 },
            .family = 100,
            .arg_types = &[_]u32{1},
            .hotness = 1000.0,
        },
        .{
            .unit_id = 1,
            .loc = .{ .file_id = 1, .start_line = 20, .start_col = 8, .end_line = 20, .end_col = 9 },
            .family = 100,
            .arg_types = &[_]u32{ 1, 2 },
            .hotness = 2000.0,
        },
    };

    for (sites) |site| {
        try optimizer.addToFamily(family_id, site);
    }

    const family_strategy = try optimizer.optimizeFamily(family_id);
    try testing.expect(family_strategy != null);

    // Should select jump table for high-frequency small family
    try testing.expect(family_strategy.? == .jump_table);
}
