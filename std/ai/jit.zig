// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Prophetic JIT Forge - Sovereign Index
// Purpose: Semantic-Speculative Just-In-Time Compilation
// Doctrine: Temporal Honesty - JIT path maintains identical semantics to AOT

const std = @import("std");

// Re-export core JIT types
pub const semantic = @import("jit/semantic.zig");
pub const speculation = @import("jit/speculation.zig");
pub const execution = @import("jit/execution.zig");

// Core types
pub const SemanticProfile = semantic.SemanticProfile;
pub const SpeculationStrategy = speculation.SpeculationStrategy;
pub const ExecutionUnit = execution.ExecutionUnit;

/// The Prophetic JIT Forge Engine
/// Doctrine: Fuses semantic analysis, speculative optimization, and sovereign execution
pub const OrcJitEngine = struct {
    allocator: std.mem.Allocator,

    /// Profile-specific compilation backend
    backend: CompilationBackend,

    /// PAYJIT (Pay-As-You-JIT) threshold configuration
    thresholds: CompilationThresholds,

    /// Learning Ledger connection (for semantic speculation)
    learning_enabled: bool,

    /// Capability bounds for compilation safety
    capability_bounds: CapabilityBounds,

    /// Statistics for observability
    stats: JitStats,

    pub const CompilationBackend = enum {
        /// Minimal IR - Fast compile, reasonable runtime (:min profile)
        MIR,
        /// Cranelift - Balanced compile/runtime (:npu profile)
        Cranelift,
        /// LLVM ORC - Maximum optimization (:full profile)
        LLVM_ORC,
        /// Simulation only - No native code (testing/validation)
        Simulation,
    };

    pub const CompilationThresholds = struct {
        /// Base invocation count before JIT compilation
        base_threshold: u32 = 100,
        /// Complexity multiplier (higher complexity = higher threshold)
        complexity_factor: f32 = 1.0,
        /// Size factor (logarithmic scaling with module size)
        size_factor: f32 = 1.0,

        pub fn effectiveThreshold(self: CompilationThresholds) u32 {
            const adjusted = @as(f32, @floatFromInt(self.base_threshold)) *
                self.complexity_factor * self.size_factor;
            return @intFromFloat(@max(10.0, adjusted));
        }
    };

    pub const CapabilityBounds = struct {
        /// Can compile code that accesses filesystem
        allow_fs: bool = false,
        /// Can compile code that accesses network
        allow_net: bool = false,
        /// Can compile code with system calls
        allow_sys: bool = false,
        /// Can compile code with NPU/GPU acceleration
        allow_accelerator: bool = true,
    };

    pub const JitStats = struct {
        compilations_total: u64 = 0,
        compilations_successful: u64 = 0,
        speculations_total: u64 = 0,
        speculations_successful: u64 = 0,
        deoptimizations: u64 = 0,
        total_compile_time_ns: u64 = 0,
    };

    /// Initialize the JIT engine with profile-appropriate defaults
    pub fn init(allocator: std.mem.Allocator, backend: CompilationBackend) OrcJitEngine {
        return OrcJitEngine{
            .allocator = allocator,
            .backend = backend,
            .thresholds = .{},
            .learning_enabled = false,
            .capability_bounds = .{},
            .stats = .{},
        };
    }

    pub fn deinit(self: *OrcJitEngine) void {
        _ = self;
        // Cleanup JIT resources
    }

    /// Lazy Compilation - Core JIT Entry Point
    ///
    /// Takes a QTJIR module and compiles it on-demand.
    /// Doctrine: Temporal Honesty - Runtime semantics match AOT compilation.
    ///
    /// Returns an ExecutionUnit that can be invoked directly.
    pub fn compileLazy(
        self: *OrcJitEngine,
        module: *const Module,
    ) !*ExecutionUnit {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.stats.total_compile_time_ns += @intCast(end_time - start_time);
            self.stats.compilations_total += 1;
        }

        // Phase 1: Semantic Prophecy
        // Query ASTDB for effect profile and optimization hints
        const semantic_profile = try semantic.analyzeModule(module, self.allocator);
        defer semantic_profile.deinit();

        // Validate capability bounds
        if (!self.validateCapabilities(semantic_profile)) {
            return error.CapabilityViolation;
        }

        // Phase 2: Speculative Forging
        // Apply speculation based on profile and learning
        const speculation_strategy = speculation.createStrategy(
            semantic_profile,
            self.thresholds,
            self.learning_enabled,
        );

        // Phase 3: Sovereign Compilation
        // Generate executable code within capability bounds
        const exec_unit = try execution.compile(
            self.allocator,
            module,
            semantic_profile,
            speculation_strategy,
            self.backend,
        );

        self.stats.compilations_successful += 1;
        return exec_unit;
    }

    /// Validate that module's effect profile respects capability bounds
    fn validateCapabilities(self: *OrcJitEngine, profile: SemanticProfile) bool {
        if (profile.effects.has_fs_access and !self.capability_bounds.allow_fs) {
            return false;
        }
        if (profile.effects.has_net_access and !self.capability_bounds.allow_net) {
            return false;
        }
        if (profile.effects.has_sys_calls and !self.capability_bounds.allow_sys) {
            return false;
        }
        return true;
    }

    /// Record execution trace to Learning Ledger for future optimization
    pub fn recordLearning(self: *OrcJitEngine, trace: *const ExecutionTrace) !void {
        _ = trace; // TODO: Implement Learning Ledger storage
        if (!self.learning_enabled) return;

        // Store trace to ASTDB-backed Learning Ledger
        // This enables "prophetic" prediction for future compilations
    }

    /// Force deoptimization and fall back to interpreter
    pub fn deoptimize(self: *OrcJitEngine, exec_unit: *ExecutionUnit) void {
        self.stats.deoptimizations += 1;
        exec_unit.invalidate();
    }

    /// Get current JIT statistics
    pub fn getStats(self: *const OrcJitEngine) JitStats {
        return self.stats;
    }
};

/// Module representation for JIT compilation
/// Wraps QTJIR graph with metadata required for JIT
pub const Module = struct {
    /// Content-addressed identifier (BLAKE3)
    cid: [32]u8,

    /// Module name for debugging
    name: []const u8,

    /// QTJIR graph reference
    qtjir_graph: *const anyopaque, // TODO: Type properly when QTJIR is imported

    /// Source location for error reporting
    source_path: ?[]const u8,

    /// Invocation counter for PAYJIT
    invocation_count: u64,
};

/// Execution trace for Learning Ledger
pub const ExecutionTrace = struct {
    module_cid: [32]u8,
    execution_time_ns: u64,
    branch_frequencies: []BranchFrequency,
    speculation_outcomes: []SpeculationOutcome,

    pub const BranchFrequency = struct {
        branch_id: u32,
        taken_count: u64,
        not_taken_count: u64,
    };

    pub const SpeculationOutcome = struct {
        speculation_id: u32,
        success: bool,
    };
};

// =============================================================================
// Tests
// =============================================================================

test "OrcJitEngine: Basic initialization" {
    const allocator = std.testing.allocator;

    var engine = OrcJitEngine.init(allocator, .Simulation);
    defer engine.deinit();

    try std.testing.expectEqual(OrcJitEngine.CompilationBackend.Simulation, engine.backend);
    try std.testing.expectEqual(@as(u64, 0), engine.stats.compilations_total);
}

test "OrcJitEngine: Threshold calculation" {
    var thresholds = OrcJitEngine.CompilationThresholds{
        .base_threshold = 100,
        .complexity_factor = 2.0,
        .size_factor = 1.5,
    };

    try std.testing.expectEqual(@as(u32, 300), thresholds.effectiveThreshold());
}

test "OrcJitEngine: Capability bounds default" {
    const bounds = OrcJitEngine.CapabilityBounds{};

    // Default: restrictive except accelerator
    try std.testing.expect(!bounds.allow_fs);
    try std.testing.expect(!bounds.allow_net);
    try std.testing.expect(!bounds.allow_sys);
    try std.testing.expect(bounds.allow_accelerator);
}
