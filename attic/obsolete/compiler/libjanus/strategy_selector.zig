// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

// Dispatch system imports
const StubStrategy = @import("ir_dispatch.zig").StubStrategy;
const CandidateIR = @import("ir_dispatch.zig").CandidateIR;
const TypeId = @import("type_registry.zig").TypeId;

/// Strategy selector for optimal dispatch performance
pub const StrategySelector = struct {
    allocator: Allocator,

    // Configuration thresholds
    config: SelectorConfig,

    // Runtime profiling data
    profiling_data: std.StringHashMap(ProfileData),

    // Selection statistics
    stats: SelectionStats,

    const SelectorConfig = struct {
        // Candidate count thresholds
        small_set_threshold: u32 = 3,
        large_set_threshold: u32 = 50,

        // Performance thresholds
        hot_path_threshold: u64 = 1000,
        cache_miss_threshold: f32 = 0.3,

        // Perfect hash feasibility
        max_perfect_hash_candidates: u32 = 10000,
        perfect_hash_timeout_ms: u64 = 100,
    };

    const ProfileData = struct {
        call_frequency: u64 = 0,
        cache_hit_rate: f32 = 0.0,
        cache_miss_rate: f32 = 0.0,
        average_lookup_time_ns: u64 = 0,
        current_strategy: StubStrategy = .switch_table,
        last_updated: u64 = 0,
    };

    const SelectionStats = struct {
        total_selections: u32 = 0,
        switch_table_selected: u32 = 0,
        perfect_hash_selected: u32 = 0,
        inline_cache_selected: u32 = 0,
        attribute_overrides: u32 = 0,
        strategy_upgrades: u32 = 0,

        pub fn reset(self: *SelectionStats) void {
            self.* = SelectionStats{};
        }
    };

    pub fn init(allocator: Allocator) StrategySelector {
        return StrategySelector{
            .allocator = allocator,
            .config = SelectorConfig{},
            .profiling_data = std.StringHashMap(ProfileData).init(allocator),
            .stats = SelectionStats{},
        };
    }

    pub fn deinit(self: *StrategySelector) void {
        self.profiling_data.deinit();
    }

    /// Select optimal dispatch strategy for a given dispatch family
    pub fn selectOptimalStrategy(
        self: *StrategySelector,
        family_name: []const u8,
        candidates: []const CandidateIR,
        attribute_override: ?StubStrategy,
    ) !StubStrategy {
        std.debug.print("🎯 Selecting strategy for {s} ({} candidates)\n", .{ family_name, candidates.len });

        self.stats.total_selections += 1;

        // Check for explicit attribute override
        if (attribute_override) |override| {
            self.stats.attribute_overrides += 1;
            std.debug.print("🔧 Using attribute override: {}\n", .{override});
            return self.recordSelection(override);
        }

        // Analyze dispatch characteristics
        const analysis = try self.analyzeDispatchCharacteristics(candidates);

        // Get profiling data if available
        const profile_data = self.profiling_data.get(family_name);

        // Apply selection heuristics
        const selected_strategy = self.applySelectionHeuristics(analysis, profile_data);

        std.debug.print("✅ Selected strategy: {} (analysis: {})\n", .{ selected_strategy, analysis });

        return self.recordSelection(selected_strategy);
    }

    /// Analyze characteristics of the dispatch candidates
    fn analyzeDispatchCharacteristics(self: *StrategySelector, candidates: []const CandidateIR) !DispatchAnalysis {
        const candidate_count = @as(u32, @intCast(candidates.len));

        // Analyze type diversity
        var unique_types = std.AutoHashMap(u32, void).init(self.allocator);
        defer unique_types.deinit();

        for (candidates) |candidate| {
            try unique_types.put(candidate.type_check_ir.target_type.id, {});
        }

        const type_diversity = @as(f32, @floatFromInt(unique_types.count())) / @as(f32, @floatFromInt(candidate_count));

        // Check perfect hash feasibility
        const perfect_hash_feasible = candidate_count <= self.config.max_perfect_hash_candidates and
            type_diversity > 0.8; // High type diversity is good for hashing

        // Analyze complexity
        const complexity = self.calculateComplexity(candidates);

        return DispatchAnalysis{
            .candidate_count = candidate_count,
            .type_diversity = type_diversity,
            .perfect_hash_feasible = perfect_hash_feasible,
            .complexity_score = complexity,
            .has_conversions = self.hasTypeConversions(candidates),
        };
    }

    /// Calculate complexity score for the dispatch
    fn calculateComplexity(self: *StrategySelector, candidates: []const CandidateIR) f32 {
        _ = self;

        var total_complexity: f32 = 0.0;

        for (candidates) |candidate| {
            // Base complexity
            var complexity: f32 = 1.0;

            // Add complexity for type conversions
            complexity += @as(f32, @floatFromInt(candidate.conversion_path.len)) * 0.5;

            // Add complexity for match score (higher score = more complex matching)
            complexity += @as(f32, @floatFromInt(candidate.match_score)) * 0.1;

            total_complexity += complexity;
        }

        return total_complexity / @as(f32, @floatFromInt(candidates.len));
    }

    /// Check if any candidates require type conversions
    fn hasTypeConversions(self: *StrategySelector, candidates: []const CandidateIR) bool {
        _ = self;

        for (candidates) |candidate| {
            if (candidate.conversion_path.len > 0) {
                return true;
            }
        }

        return false;
    }

    /// Apply selection heuristics based on analysis and profiling data
    fn applySelectionHeuristics(
        self: *StrategySelector,
        analysis: DispatchAnalysis,
        profile_data: ?ProfileData,
    ) StubStrategy {
        // Rule 1: Hot paths with good cache potential use inline cache (highest priority)
        if (profile_data) |data| {
            if (data.call_frequency >= self.config.hot_path_threshold) {
                // Check if current cache performance is poor
                if (data.current_strategy == .inline_cache and data.cache_miss_rate > self.config.cache_miss_threshold) {
                    std.debug.print("📊 Hot path with poor cache performance → perfect_hash\n", .{});
                    if (analysis.perfect_hash_feasible) {
                        return .perfect_hash;
                    }
                } else {
                    std.debug.print("🔥 Hot path detected → inline_cache\n", .{});
                    return .inline_cache;
                }
            }
        }

        // Rule 2: Small sets use switch table (simple and efficient)
        if (analysis.candidate_count <= self.config.small_set_threshold) {
            std.debug.print("📝 Small set ({} candidates) → switch_table\n", .{analysis.candidate_count});
            return .switch_table;
        }

        // Rule 3: Large sets with good hash properties use perfect hash
        if (analysis.candidate_count >= self.config.large_set_threshold and analysis.perfect_hash_feasible) {
            std.debug.print("🔍 Large set with good hash properties → perfect_hash\n", .{});
            return .perfect_hash;
        }

        // Rule 4: Complex dispatches with many conversions use switch table (predictable performance)
        if (analysis.has_conversions and analysis.complexity_score > 2.0) {
            std.debug.print("🔧 Complex dispatch with conversions → switch_table\n", .{});
            return .switch_table;
        }

        // Rule 5: Medium sets with moderate complexity use inline cache
        if (analysis.candidate_count <= 20 and analysis.complexity_score <= 2.0) {
            std.debug.print("⚡ Medium set with low complexity → inline_cache\n", .{});
            return .inline_cache;
        }

        // Default: switch table (safe fallback)
        std.debug.print("🛡️ Default fallback → switch_table\n", .{});
        return .switch_table;
    }

    /// Record strategy selection in statistics
    fn recordSelection(self: *StrategySelector, strategy: StubStrategy) StubStrategy {
        switch (strategy) {
            .switch_table => self.stats.switch_table_selected += 1,
            .perfect_hash => self.stats.perfect_hash_selected += 1,
            .inline_cache => self.stats.inline_cache_selected += 1,
        }

        return strategy;
    }

    /// Update profiling data for a dispatch family
    pub fn updateProfilingData(
        self: *StrategySelector,
        family_name: []const u8,
        call_frequency: u64,
        cache_hit_rate: f32,
        average_lookup_time_ns: u64,
        current_strategy: StubStrategy,
    ) !void {
        const timestamp = std.time.nanoTimestamp();

        const profile_data = ProfileData{
            .call_frequency = call_frequency,
            .cache_hit_rate = cache_hit_rate,
            .cache_miss_rate = 1.0 - cache_hit_rate,
            .average_lookup_time_ns = average_lookup_time_ns,
            .current_strategy = current_strategy,
            .last_updated = @intCast(timestamp),
        };

        try self.profiling_data.put(family_name, profile_data);

        std.debug.print("📊 Updated profiling data for {s}: {} calls, {d:.1}% hit rate\n", .{
            family_name,
            call_frequency,
            cache_hit_rate * 100.0,
        });
    }

    /// Check if a strategy should be upgraded based on runtime performance
    pub fn shouldUpgradeStrategy(
        self: *StrategySelector,
        family_name: []const u8,
        candidates: []const CandidateIR,
    ) ?StubStrategy {
        const profile_data = self.profiling_data.get(family_name) orelse return null;

        // Check upgrade conditions based on current strategy
        switch (profile_data.current_strategy) {
            .switch_table => {
                // Upgrade to inline cache if becoming hot
                if (profile_data.call_frequency >= self.config.hot_path_threshold) {
                    std.debug.print("🔄 Upgrading {s}: switch_table → inline_cache (hot path)\n", .{family_name});
                    self.stats.strategy_upgrades += 1;
                    return .inline_cache;
                }

                // Upgrade to perfect hash if large and feasible
                if (candidates.len >= self.config.large_set_threshold) {
                    const analysis = self.analyzeDispatchCharacteristics(candidates) catch return null;
                    if (analysis.perfect_hash_feasible) {
                        std.debug.print("🔄 Upgrading {s}: switch_table → perfect_hash (large set)\n", .{family_name});
                        self.stats.strategy_upgrades += 1;
                        return .perfect_hash;
                    }
                }
            },

            .inline_cache => {
                // Upgrade to perfect hash if cache performance is poor
                if (profile_data.cache_miss_rate > self.config.cache_miss_threshold) {
                    const analysis = self.analyzeDispatchCharacteristics(candidates) catch return null;
                    if (analysis.perfect_hash_feasible) {
                        std.debug.print("🔄 Upgrading {s}: inline_cache → perfect_hash (poor cache performance)\n", .{family_name});
                        self.stats.strategy_upgrades += 1;
                        return .perfect_hash;
                    }
                }
            },

            .perfect_hash => {
                // Perfect hash is already optimal, no upgrades needed
                return null;
            },
        }

        return null;
    }

    /// Get strategy selection statistics
    pub fn getStats(self: *const StrategySelector) SelectionStats {
        return self.stats;
    }

    /// Get profiling data for a specific family
    pub fn getProfilingData(self: *const StrategySelector, family_name: []const u8) ?ProfileData {
        return self.profiling_data.get(family_name);
    }

    /// Generate strategy selection report
    pub fn generateReport(self: *const StrategySelector, allocator: Allocator) ![]u8 {
        var report: std.ArrayList(u8) = .empty;
        defer report.deinit();

        const writer = report.writer();

        try writer.print("# Strategy Selection Report\n\n", .{});
        try writer.print("## Selection Statistics\n", .{});
        try writer.print("- Total selections: {}\n", .{self.stats.total_selections});
        try writer.print("- Switch table: {} ({d:.1}%)\n", .{
            self.stats.switch_table_selected,
            @as(f32, @floatFromInt(self.stats.switch_table_selected)) / @as(f32, @floatFromInt(self.stats.total_selections)) * 100.0,
        });
        try writer.print("- Perfect hash: {} ({d:.1}%)\n", .{
            self.stats.perfect_hash_selected,
            @as(f32, @floatFromInt(self.stats.perfect_hash_selected)) / @as(f32, @floatFromInt(self.stats.total_selections)) * 100.0,
        });
        try writer.print("- Inline cache: {} ({d:.1}%)\n", .{
            self.stats.inline_cache_selected,
            @as(f32, @floatFromInt(self.stats.inline_cache_selected)) / @as(f32, @floatFromInt(self.stats.total_selections)) * 100.0,
        });
        try writer.print("- Attribute overrides: {}\n", .{self.stats.attribute_overrides});
        try writer.print("- Strategy upgrades: {}\n", .{self.stats.strategy_upgrades});

        try writer.print("\n## Profiling Data\n", .{});
        var iterator = self.profiling_data.iterator();
        while (iterator.next()) |entry| {
            const family_name = entry.key_ptr.*;
            const data = entry.value_ptr.*;

            try writer.print("- {s}: {} calls, {d:.1}% hit rate, {} strategy\n", .{
                family_name,
                data.call_frequency,
                data.cache_hit_rate * 100.0,
                data.current_strategy,
            });
        }

        return try report.toOwnedSlice();
    }
};

/// Analysis results for dispatch characteristics
const DispatchAnalysis = struct {
    candidate_count: u32,
    type_diversity: f32,
    perfect_hash_feasible: bool,
    complexity_score: f32,
    has_conversions: bool,
};
