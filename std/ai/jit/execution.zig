// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Sovereign Execution - Phase 3 of Prophetic JIT
// Purpose: Generate and manage executable code within capability bounds
// Doctrine: Temporal Honesty - Compiled code has identical semantics to interpreted

const std = @import("std");
const compat_time = @import("compat_time");
const semantic = @import("semantic.zig");
const speculation = @import("speculation.zig");

const SemanticProfile = semantic.SemanticProfile;
const SpeculationStrategy = speculation.SpeculationStrategy;

/// Compiled execution unit - the output of JIT compilation
pub const ExecutionUnit = struct {
    allocator: std.mem.Allocator,

    /// Content-addressed identifier (BLAKE3 of source)
    cid: [32]u8,

    /// Compiled machine code (or simulation bytecode)
    code: []const u8,

    /// Entry point offset within code
    entry_offset: usize,

    /// Capability validators for runtime checks
    capability_validators: []const CapabilityValidator,

    /// Audit trail for compilation history
    audit_trail: AuditTrail,

    /// Is this unit still valid? (false after deoptimization)
    valid: bool,

    /// Backend that produced this unit
    backend: CompilationBackend,

    pub const CompilationBackend = enum {
        MIR,
        Cranelift,
        LLVM_ORC,
        Simulation,
    };

    pub const CapabilityValidator = struct {
        capability: Capability,
        check_offset: usize,

        pub const Capability = enum {
            FileRead,
            FileWrite,
            NetConnect,
            NetListen,
            SysExec,
            AcceleratorUse,
        };
    };

    pub const AuditTrail = struct {
        /// When was this compiled?
        compilation_timestamp: i64,
        /// How long did compilation take?
        compilation_duration_ns: u64,
        /// Speculation level used
        speculation_level: speculation.SpeculationLevel,
        /// Module CID that was compiled
        source_cid: [32]u8,
    };

    pub fn init(allocator: std.mem.Allocator) ExecutionUnit {
        return ExecutionUnit{
            .allocator = allocator,
            .cid = std.mem.zeroes([32]u8),
            .code = &.{},
            .entry_offset = 0,
            .capability_validators = &.{},
            .audit_trail = .{
                .compilation_timestamp = 0,
                .compilation_duration_ns = 0,
                .speculation_level = .None,
                .source_cid = std.mem.zeroes([32]u8),
            },
            .valid = true,
            .backend = .Simulation,
        };
    }

    pub fn deinit(self: *ExecutionUnit) void {
        if (self.code.len > 0) {
            self.allocator.free(self.code);
        }
    }

    /// Invalidate this execution unit (deoptimization)
    pub fn invalidate(self: *ExecutionUnit) void {
        self.valid = false;
    }

    /// Check if execution unit is ready to run
    pub fn isReady(self: *const ExecutionUnit) bool {
        return self.valid and self.code.len > 0;
    }

    /// Execute the compiled code (simulation mode only for now)
    pub fn execute(self: *ExecutionUnit, args: anytype) !ExecutionResult {
        if (!self.valid) {
            return error.InvalidExecutionUnit;
        }

        switch (self.backend) {
            .Simulation => {
                // Simulation mode: Interpret the "code" as simulation bytecode
                return self.simulateExecution(args);
            },
            else => {
                // TODO: Implement native execution
                return error.NativeExecutionNotImplemented;
            },
        }
    }

    fn simulateExecution(self: *ExecutionUnit, args: anytype) !ExecutionResult {
        _ = args;
        _ = self;

        // Placeholder simulation
        return ExecutionResult{
            .success = true,
            .return_value = .{ .integer = 0 },
            .execution_time_ns = 0,
        };
    }
};

/// Result of executing a compiled unit
pub const ExecutionResult = struct {
    success: bool,
    return_value: ReturnValue,
    execution_time_ns: u64,

    pub const ReturnValue = union(enum) {
        void_val: void,
        integer: i64,
        float: f64,
        boolean: bool,
        pointer: *anyopaque,
    };
};

/// Compile module with given strategy
pub fn compile(
    allocator: std.mem.Allocator,
    module: *const anyopaque,
    profile: SemanticProfile,
    strategy: SpeculationStrategy,
    backend: anytype,
) !*ExecutionUnit {
    _ = module;

    const exec_unit = try allocator.create(ExecutionUnit);
    exec_unit.* = ExecutionUnit.init(allocator);

    // Set backend
    exec_unit.backend = switch (backend) {
        .MIR => .MIR,
        .Cranelift => .Cranelift,
        .LLVM_ORC => .LLVM_ORC,
        .Simulation => .Simulation,
        else => @compileError("Unsupported backend"),
    };

    // Record audit trail
    exec_unit.audit_trail = .{
        .compilation_timestamp = compat_time.timestamp(),
        .compilation_duration_ns = 0, // TODO: Measure
        .speculation_level = strategy.level,
        .source_cid = profile.module_cid,
    };

    // TODO: Actual compilation based on backend
    // For now, just create a valid simulation unit

    return exec_unit;
}

// =============================================================================
// Tests
// =============================================================================

test "ExecutionUnit: Basic initialization" {
    const allocator = std.testing.allocator;

    var unit = ExecutionUnit.init(allocator);
    defer unit.deinit();

    try std.testing.expect(unit.valid);
    try std.testing.expect(!unit.isReady()); // No code yet
}

test "ExecutionUnit: Invalidation" {
    const allocator = std.testing.allocator;

    var unit = ExecutionUnit.init(allocator);
    defer unit.deinit();

    try std.testing.expect(unit.valid);

    unit.invalidate();

    try std.testing.expect(!unit.valid);
}

test "compile: Creates valid execution unit" {
    const allocator = std.testing.allocator;

    const profile = SemanticProfile.init(allocator);
    defer profile.deinit();

    const strategy = SpeculationStrategy.conservative();

    const unit = try compile(allocator, undefined, profile, strategy, ExecutionUnit.CompilationBackend.Simulation);
    defer allocator.destroy(unit);
    defer unit.deinit();

    try std.testing.expect(unit.valid);
    try std.testing.expectEqual(ExecutionUnit.CompilationBackend.Simulation, unit.backend);
}
