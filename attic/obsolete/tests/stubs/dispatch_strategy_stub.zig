// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Minimal stub for dispatch strategy to keep golden integration decoupled

const std = @import("std");
const CallSite = @import("codegen").CallSite;
const Strategy = @import("codegen").Strategy;

pub const StrategyEffectiveness = struct {
    pub fn calculateScore(self: @This()) f64 {
        _ = self;
        return 1.0;
    }
};

pub const StrategyDecision = struct {
    confidence_score: f64 = 1.0,
    alternatives_considered: []Strategy = &.{},
};

pub const AdvancedStrategySelector = struct {
    allocator: std.mem.Allocator,
    strategy_history: std.ArrayList(StrategyDecision),

    pub fn init(allocator: std.mem.Allocator) AdvancedStrategySelector {
        return .{ .allocator = allocator, .strategy_history = .empty };
    }

    pub fn deinit(self: *AdvancedStrategySelector) void {
        for (self.strategy_history.items) |d| {
            _ = d;
        }
        self.strategy_history.deinit();
    }

    pub fn selectOptimalStrategy(self: *AdvancedStrategySelector, site: CallSite) !Strategy {
        // Simple heuristic: high hotness => Static else SwitchTable
        _ = self;
        return if (site.hotness > 1000.0) .Static else .SwitchTable;
    }

    pub fn recordEffectiveness(self: *AdvancedStrategySelector, strategy: Strategy, eff: StrategyEffectiveness) !void {
        _ = strategy;
        _ = eff;
        // no-op
    }

    pub fn getHistoricalSuccessRate(self: *AdvancedStrategySelector, strategy: Strategy) f64 {
        _ = self;
        _ = strategy;
        return 1.0;
    }

    pub fn createFallbackStrategy(self: *AdvancedStrategySelector, failed_strategy: Strategy, site: CallSite) !Strategy {
        _ = self;
        _ = site;
        return switch (failed_strategy) {
            .PerfectHash => .SwitchTable,
            .SwitchTable => .Static,
            .InlineCache => .SwitchTable,
            .Static => .InlineCache,
        };
    }

    pub fn recordFailureAndFallback(self: *AdvancedStrategySelector, failed_strategy: Strategy, site: CallSite, msg: []const u8) !Strategy {
        _ = msg;
        return self.createFallbackStrategy(failed_strategy, site);
    }

    pub const StrategyStatistics = struct { total_decisions: u32 = 0 };
    pub fn getSelectionStatistics(self: *AdvancedStrategySelector) StrategyStatistics {
        _ = self;
        return .{ .total_decisions = 0 };
    }
};
