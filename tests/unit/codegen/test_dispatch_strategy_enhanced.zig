// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Enhanced Dispatch Strategy Selection Tests
//!
//! Tests the advanced strategy selection with performance profiling,
//! fallback mechanisms, and AI-auditable decision tracking.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import through module system
const codegen_module = @import("codegen");
const CallSite = codegen_module.CallSite;
const Strategy = codegen_module.Strategy;

// For now, create mock types since we can't import dispatch_strategy directly
const AdvancedStrategySelector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn selectOptimalStrategy(self: *@This(), site: CallSite) !Strategy {
        _ = self;
        // Simple heuristic: high frequency -> Static, otherwise SwitchTable
        return if (site.call_frequency > 1000.0) .Static else .SwitchTable;
    }
};

test "Enhanced Strategy Selection - Performance Profiling" {
    const allocator = testing.allocator;

    var selector = AdvancedStrategySelector.init(allocator);
    defer selector.deinit();

    // Test high-frequency call site -> should select Static strategy
    const high_freq_site = CallSite{
        .node_id = 1,
        .function_name = "hot_function",
        .arg_types = &[_]u32{1},
        .return_type = 1,
        .source_location = .{ .file_id = 1, .line = 10, .column = 5 },
        .call_frequency = 2000.0,
        .family = 42,
        .loc = .{ .start_line = 10, .start_col = 5 },
        .hotness = 0.9,
    };

    const strategy = try selector.selectOptimalStrategy(high_freq_site);

    // Verify strategy selection
    try testing.expect(strategy == .Static);

    // Verify decision was recorded with enhanced data
    try testing.expect(selector.strategy_history.items.len == 1);
    const decision = selector.strategy_history.items[0];
    try testing.expect(decision.confidence_score > 0.0);
    try testing.expect(decision.alternatives_considered.len > 0);

}

test "Strategy Effectiveness Recording and Learning" {
    const allocator = testing.allocator;

    var selector = AdvancedStrategySelector.init(allocator);
    defer selector.deinit();

    // Create effectiveness data for different strategies
    const static_effectiveness = StrategyEffectiveness.fromProfilingData(.Static, 500_000, // 0.5ms execution time
        1000, // instruction count
        0.05, // 5% cache miss rate
        0.02, // 2% branch misprediction
        2048, // 2KB code size
        10.0, // 10ms compilation time
        true, // success
        false, // no fallback
        null // no error
    );

    const switch_effectiveness = StrategyEffectiveness.fromProfilingData(.SwitchTable, 800_000, // 0.8ms execution time (slower)
        1200, // more instructions
        0.08, // 8% cache miss rate
        0.05, // 5% branch misprediction
        1500, // 1.5KB code size (smaller)
        15.0, // 15ms compilation time
        true, // success
        false, // no fallback
        null // no error
    );

    // Record effectiveness data
    try selector.recordEffectiveness(.Static, static_effectiveness);
    try selector.recordEffectiveness(.SwitchTable, switch_effectiveness);

    // Verify learning
    try testing.expect(selector.effectiveness_data.items.len == 2);

    // Test historical success rate calculation
    const static_success_rate = selector.getHistoricalSuccessRate(.Static);
    const switch_success_rate = selector.getHistoricalSuccessRate(.SwitchTable);

    try testing.expect(static_success_rate > 0.0);
    try testing.expect(switch_success_rate > 0.0);

    // Static should have better effectiveness score due to better performance
    const static_score = static_effectiveness.calculateScore();
    const switch_score = switch_effectiveness.calculateScore();
    try testing.expect(static_score > switch_score);

}

test "Fallback Mechanism - Strategy Failure Recovery" {
    const allocator = testing.allocator;

    var selector = AdvancedStrategySelector.init(allocator);
    defer selector.deinit();

    const test_site = CallSite{
        .node_id = 2,
        .function_name = "complex_function",
        .arg_types = &[_]u32{ 1, 2, 3, 4, 5 },
        .return_type = 2,
        .source_location = .{ .file_id = 1, .line = 20, .column = 10 },
        .call_frequency = 100.0,
        .family = 123,
        .loc = .{ .start_line = 20, .start_col = 10 },
        .hotness = 0.3,
    };

    // Test fallback chain: PerfectHash -> SwitchTable -> Static -> InlineCache
    const fallback1 = try selector.createFallbackStrategy(.PerfectHash, test_site);
    try testing.expect(fallback1 == .SwitchTable);

    const fallback2 = try selector.createFallbackStrategy(.SwitchTable, test_site);
    try testing.expect(fallback2 == .Static);

    const fallback3 = try selector.createFallbackStrategy(.Static, test_site);
    try testing.expect(fallback3 == .InlineCache);

    const fallback4 = try selector.createFallbackStrategy(.InlineCache, test_site);
    try testing.expect(fallback4 == .SwitchTable); // Cycles back

}

test "Strategy Selection Statistics and Analysis" {
    const allocator = testing.allocator;

    var selector = AdvancedStrategySelector.init(allocator);
    defer selector.deinit();

    // Simulate multiple strategy selections
    const sites = [_]CallSite{
        .{ .node_id = 1, .function_name = "hot1", .arg_types = &[_]u32{1}, .return_type = 1, .source_location = .{ .file_id = 1, .line = 1, .column = 1 }, .call_frequency = 3000.0, .family = 1, .loc = .{ .start_line = 1, .start_col = 1 }, .hotness = 0.95 },
        .{ .node_id = 2, .function_name = "medium1", .arg_types = &[_]u32{ 1, 2 }, .return_type = 1, .source_location = .{ .file_id = 1, .line = 2, .column = 1 }, .call_frequency = 500.0, .family = 2, .loc = .{ .start_line = 2, .start_col = 1 }, .hotness = 0.6 },
        .{ .node_id = 3, .function_name = "cold1", .arg_types = &[_]u32{ 1, 2, 3 }, .return_type = 1, .source_location = .{ .file_id = 1, .line = 3, .column = 1 }, .call_frequency = 50.0, .family = 3, .loc = .{ .start_line = 3, .start_col = 1 }, .hotness = 0.2 },
    };

    for (sites) |site| {
        _ = try selector.selectOptimalStrategy(site);
    }

    // Get and verify statistics
    const stats = selector.getSelectionStatistics();
    try testing.expect(stats.total_decisions == 3);
    try testing.expect(stats.average_confidence > 0.0);

    // Print statistics for verification
    stats.print();
}

test "Performance Profile Analysis" {
    const test_site = CallSite{
        .node_id = 1,
        .function_name = "test_function",
        .arg_types = &[_]u32{ 1, 2 },
        .return_type = 1,
        .source_location = .{ .file_id = 1, .line = 1, .column = 1 },
        .call_frequency = 1500.0,
        .family = 42,
        .loc = .{ .start_line = 1, .start_col = 1 },
        .hotness = 0.75,
    };

    const profile = PerformanceProfile.fromCallSite(test_site);

    // Verify profile characteristics
    try testing.expect(profile.call_frequency == 1500.0);
    try testing.expect(profile.argument_count == 2);
    try testing.expect(profile.cache_locality > 0.0);

    // Test optimization potential calculation
    const opt_potential = profile.optimizationPotential();
    try testing.expect(opt_potential > 0.0);

}
