// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Semantic Prophecy - Phase 1 of Prophetic JIT
// Purpose: ASTDB-guided semantic analysis for JIT optimization
// Doctrine: Query-first optimization - Semantics inform speculation

const std = @import("std");

/// Effect categories for capability validation
pub const EffectSet = struct {
    /// Accesses filesystem (read/write)
    has_fs_access: bool = false,
    /// Accesses network (sockets, HTTP)
    has_net_access: bool = false,
    /// Makes system calls
    has_sys_calls: bool = false,
    /// Uses hardware accelerators (NPU/GPU)
    has_accelerator_use: bool = false,
    /// Allocates memory dynamically
    has_dynamic_alloc: bool = false,
    /// Performs I/O operations
    has_io_operations: bool = false,
    /// Contains loops (optimization target)
    has_loops: bool = false,
    /// Contains recursion (stack-sensitive)
    has_recursion: bool = false,
};

/// Optimization hints from semantic analysis
pub const OptimizationHint = enum {
    /// Function is pure - can be memoized
    Pure,
    /// Hot path - prioritize optimization
    HotPath,
    /// Cold path - deprioritize optimization
    ColdPath,
    /// Loop candidate for vectorization
    Vectorizable,
    /// Tail-recursive - can be optimized to loop
    TailRecursive,
    /// Tensor operation - NPU candidate
    TensorOp,
    /// Quantum operation - QPU candidate
    QuantumOp,
    /// SSM operation - NPU candidate (Mamba-style)
    SSMOp,
};

/// Complexity metrics for threshold calculation
pub const ComplexityMetrics = struct {
    /// Cyclomatic complexity (branch count)
    cyclomatic: u32 = 1,
    /// AST node count
    node_count: u32 = 0,
    /// Maximum nesting depth
    max_depth: u32 = 0,
    /// Number of function calls
    call_count: u32 = 0,
    /// Estimated instruction count
    estimated_instructions: u32 = 0,

    /// Calculate complexity factor for PAYJIT thresholds
    pub fn complexityFactor(self: ComplexityMetrics) f32 {
        // Higher complexity = higher threshold (delay compilation)
        const base: f32 = 1.0;
        const cyclo_weight: f32 = 0.1;
        const depth_weight: f32 = 0.2;

        return base +
            (@as(f32, @floatFromInt(self.cyclomatic)) * cyclo_weight) +
            (@as(f32, @floatFromInt(self.max_depth)) * depth_weight);
    }
};

/// Complete semantic profile from ASTDB analysis
pub const SemanticProfile = struct {
    allocator: std.mem.Allocator,

    /// Effect analysis for capability validation
    effects: EffectSet,

    /// Optimization hints from semantic queries
    hints: std.ArrayList(OptimizationHint),

    /// Complexity metrics for threshold calculation
    complexity: ComplexityMetrics,

    /// Content-addressed hash of analyzed module
    module_cid: [32]u8,

    pub fn init(allocator: std.mem.Allocator) SemanticProfile {
        return SemanticProfile{
            .allocator = allocator,
            .effects = .{},
            .hints = std.ArrayList(OptimizationHint){},
            .complexity = .{},
            .module_cid = std.mem.zeroes([32]u8),
        };
    }

    pub fn deinit(self: *const SemanticProfile) void {
        // Use mutable copy for deinit
        var hints = self.hints;
        hints.deinit(self.allocator);
    }

    /// Add optimization hint
    pub fn addHint(self: *SemanticProfile, hint: OptimizationHint) !void {
        try self.hints.append(self.allocator, hint);
    }

    /// Check if module has specific hint
    pub fn hasHint(self: *const SemanticProfile, hint: OptimizationHint) bool {
        for (self.hints.items) |h| {
            if (h == hint) return true;
        }
        return false;
    }
};

/// Analyze module for semantic properties
/// Queries ASTDB for effect profile and optimization hints
pub fn analyzeModule(module: *const anyopaque, allocator: std.mem.Allocator) !SemanticProfile {
    _ = module; // TODO: Integrate with actual QTJIR/ASTDB

    var profile = SemanticProfile.init(allocator);

    // Placeholder: In production, this queries ASTDB for:
    // 1. Effect analysis (what capabilities does this code need?)
    // 2. Optimization hints (hot paths, vectorizable loops, etc.)
    // 3. Complexity metrics (for PAYJIT threshold calculation)

    // Default conservative profile
    profile.effects = .{
        .has_dynamic_alloc = true,
    };

    profile.complexity = .{
        .cyclomatic = 1,
        .node_count = 10,
        .max_depth = 2,
    };

    return profile;
}

// =============================================================================
// Tests
// =============================================================================

test "SemanticProfile: Basic initialization" {
    const allocator = std.testing.allocator;

    var profile = SemanticProfile.init(allocator);
    defer profile.deinit();

    try std.testing.expect(!profile.effects.has_fs_access);
    try std.testing.expectEqual(@as(u32, 1), profile.complexity.cyclomatic);
}

test "SemanticProfile: Add and check hints" {
    const allocator = std.testing.allocator;

    var profile = SemanticProfile.init(allocator);
    defer profile.deinit();

    try profile.addHint(.Pure);
    try profile.addHint(.TensorOp);

    try std.testing.expect(profile.hasHint(.Pure));
    try std.testing.expect(profile.hasHint(.TensorOp));
    try std.testing.expect(!profile.hasHint(.HotPath));
}

test "ComplexityMetrics: Factor calculation" {
    const metrics = ComplexityMetrics{
        .cyclomatic = 5,
        .max_depth = 3,
    };

    const factor = metrics.complexityFactor();
    // 1.0 + (5 * 0.1) + (3 * 0.2) = 1.0 + 0.5 + 0.6 = 2.1
    try std.testing.expectApproxEqAbs(@as(f32, 2.1), factor, 0.01);
}
