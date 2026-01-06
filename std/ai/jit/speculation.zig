// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Speculative Forging - Phase 2 of Prophetic JIT
// Purpose: Apply speculative optimizations with deoptimization guards
// Doctrine: Bounded Speculation - All speculation has capability limits

const std = @import("std");
const semantic = @import("semantic.zig");

const SemanticProfile = semantic.SemanticProfile;
const OptimizationHint = semantic.OptimizationHint;

/// Speculation confidence levels
pub const SpeculationLevel = enum {
    /// No speculation - conservative compilation
    None,
    /// Low speculation - type stability only
    Low,
    /// Medium speculation - inlining + type stability
    Medium,
    /// High speculation - aggressive optimizations
    High,
    /// Maximum speculation - all optimizations enabled
    Maximum,

    pub fn toString(self: SpeculationLevel) []const u8 {
        return switch (self) {
            .None => "none",
            .Low => "low",
            .Medium => "medium",
            .High => "high",
            .Maximum => "maximum",
        };
    }
};

/// Deoptimization guard - triggers fallback to interpreter
pub const DeoptGuard = struct {
    /// Guard identifier for tracking
    id: u32,
    /// Condition that triggers deoptimization
    condition: GuardCondition,
    /// Fallback location in bytecode/IR
    fallback_offset: u32,

    pub const GuardCondition = enum {
        /// Type changed from expected
        TypeMismatch,
        /// Array bounds exceeded
        BoundsCheck,
        /// Inline cache miss
        InlineCacheMiss,
        /// Stack overflow
        StackOverflow,
        /// Capability revoked at runtime
        CapabilityRevoked,
    };
};

/// Complete speculation strategy for a module
pub const SpeculationStrategy = struct {
    /// Overall speculation level
    level: SpeculationLevel,

    /// Deoptimization guards to insert
    guards: []const DeoptGuard,

    /// Specific optimizations to apply
    optimizations: OptimizationSet,

    /// PAYJIT threshold after speculation
    adjusted_threshold: u32,

    pub const OptimizationSet = struct {
        /// Inline small functions
        inline_calls: bool = false,
        /// Eliminate dead code paths
        dead_code_elimination: bool = true,
        /// Fold constant expressions
        constant_folding: bool = true,
        /// Vectorize loop operations
        loop_vectorization: bool = false,
        /// Fuse tensor operations
        tensor_fusion: bool = false,
        /// Optimize tail recursion to loops
        tail_call_optimization: bool = false,
    };

    /// Create default conservative strategy
    pub fn conservative() SpeculationStrategy {
        return SpeculationStrategy{
            .level = .None,
            .guards = &.{},
            .optimizations = .{},
            .adjusted_threshold = 1000,
        };
    }

    /// Create aggressive strategy for hot paths
    pub fn aggressive() SpeculationStrategy {
        return SpeculationStrategy{
            .level = .High,
            .guards = &.{},
            .optimizations = .{
                .inline_calls = true,
                .dead_code_elimination = true,
                .constant_folding = true,
                .loop_vectorization = true,
                .tensor_fusion = true,
                .tail_call_optimization = true,
            },
            .adjusted_threshold = 50,
        };
    }
};

/// Create speculation strategy based on semantic profile
pub fn createStrategy(
    profile: SemanticProfile,
    thresholds: anytype,
    learning_enabled: bool,
) SpeculationStrategy {
    var strategy = SpeculationStrategy.conservative();

    // Determine speculation level based on hints
    if (profile.hasHint(.HotPath)) {
        strategy.level = .High;
        strategy.optimizations.inline_calls = true;
        strategy.optimizations.loop_vectorization = true;
    } else if (profile.hasHint(.Pure)) {
        strategy.level = .Medium;
        strategy.optimizations.constant_folding = true;
    }

    // Enable tensor fusion for NPU-bound operations
    if (profile.hasHint(.TensorOp) or profile.hasHint(.SSMOp)) {
        strategy.optimizations.tensor_fusion = true;
    }

    // Learning-enabled = more aggressive speculation
    if (learning_enabled) {
        if (strategy.level == .None) {
            strategy.level = .Low;
        } else if (strategy.level == .Medium) {
            strategy.level = .High;
        }
    }

    // Calculate adjusted threshold
    const base = thresholds.base_threshold;
    const complexity_factor = profile.complexity.complexityFactor();
    strategy.adjusted_threshold = @intFromFloat(@as(f32, @floatFromInt(base)) * complexity_factor);

    return strategy;
}

// =============================================================================
// Tests
// =============================================================================

test "SpeculationStrategy: Conservative default" {
    const strategy = SpeculationStrategy.conservative();

    try std.testing.expectEqual(SpeculationLevel.None, strategy.level);
    try std.testing.expect(!strategy.optimizations.inline_calls);
    try std.testing.expect(strategy.optimizations.dead_code_elimination);
}

test "SpeculationStrategy: Aggressive for hot paths" {
    const strategy = SpeculationStrategy.aggressive();

    try std.testing.expectEqual(SpeculationLevel.High, strategy.level);
    try std.testing.expect(strategy.optimizations.inline_calls);
    try std.testing.expect(strategy.optimizations.tensor_fusion);
}

test "createStrategy: Respects semantic hints" {
    const allocator = std.testing.allocator;

    var profile = SemanticProfile.init(allocator);
    defer profile.deinit();

    try profile.addHint(.HotPath);

    const thresholds = struct {
        base_threshold: u32 = 100,
    }{};

    const strategy = createStrategy(profile, thresholds, false);

    try std.testing.expectEqual(SpeculationLevel.High, strategy.level);
    try std.testing.expect(strategy.optimizations.inline_calls);
}
