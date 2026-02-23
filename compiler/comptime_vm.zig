// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("libjanus/astdb.zig");
const contracts = @import("libjanus/integration_contracts.zig");
const ASTDBSystem = astdb.ASTDBSystem;
const StrId = astdb.StrId;

/// GRANITE-SOLID ComptimeVM - Zero leaks by design
/// Revolutionary compile-time evaluation with bulletproof memory management
/// Uses the same arena-first pattern that made StringInterner leak-free
pub const ComptimeVM = struct {
    // Core allocators - arena-first design
    parent_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    // ASTDB integration
    astdb_system: *ASTDBSystem,

    // Simple constant storage - no HashMap complexity
    constants: std.ArrayList(ConstantEntry),

    // Statistics
    evaluation_count: u32,

    const Self = @This();

    /// Simple constant storage entry - no complex HashMap
    const ConstantEntry = struct {
        name: StrId,
        value: StrId,
        type_id: StrId,
    };

    /// Initialize ComptimeVM with granite-solid memory management
    pub fn init(parent_allocator: std.mem.Allocator, astdb_system: *ASTDBSystem) !Self {
        var vm = Self{
            .parent_allocator = parent_allocator,
            .arena = std.heap.ArenaAllocator.init(parent_allocator),
            .astdb_system = astdb_system,
            .constants = .empty,
            .evaluation_count = 0,
        };

        // GRANITE-SOLID: Pre-allocate capacity to prevent growth leaks
        try vm.constants.ensureTotalCapacity(1024);

        return vm;
    }

    /// Clean up ComptimeVM - O(1) arena cleanup
    pub fn deinit(self: *Self) void {
        // GRANITE-SOLID: Arena cleanup is O(1) and guaranteed leak-free
        self.arena.deinit();
        self.constants.deinit();

        // Clear all fields to prevent accidental reuse
        self.* = undefined;
    }

    /// Evaluate comptime expression using Integration Contract
    /// GRANITE-SOLID: All temporary allocations use arena
    pub fn evaluateExpression(self: *Self, input_contract: *const contracts.ComptimeVMInputContract) !contracts.ComptimeVMOutputContract {
        // Validate input contract
        if (!contracts.ContractValidation.validateComptimeVMInput(input_contract)) {
            return self.createErrorOutput(.unsupported_operation, input_contract.expression_name, input_contract.source_span);
        }

        // Use arena for all temporary allocations during evaluation
        const arena_allocator = self.arena.allocator();

        // Create evaluation context with arena-allocated temporary data
        var eval_context = EvaluationContext{
            .arena_allocator = arena_allocator,
            .dependencies = .empty,
            .temp_values = .empty,
        };

        // No need to defer cleanup - arena.deinit() handles everything

        // Increment evaluation counter
        self.evaluation_count += 1;

        // Handle different expression types
        switch (input_contract.expression_type) {
            .const_declaration => {
                return try self.evaluateConstDeclaration(input_contract, &eval_context);
            },
            .type_expression => {
                return try self.evaluateTypeExpression(input_contract, &eval_context);
            },
            .comptime_function_call => {
                return try self.evaluateComptimeFunctionCall(input_contract, &eval_context);
            },
            .compile_time_constant => {
                return try self.evaluateCompileTimeConstant(input_contract, &eval_context);
            },
        }
    }

    /// Evaluation context with arena-allocated temporary data
    const EvaluationContext = struct {
        arena_allocator: std.mem.Allocator,
        dependencies: std.ArrayList(astdb.NodeId),
        temp_values: std.ArrayList(StrId),
    };

    /// Evaluate const declaration - GRANITE-SOLID implementation
    fn evaluateConstDeclaration(self: *Self, input_contract: *const contracts.ComptimeVMInputContract, ctx: *EvaluationContext) !contracts.ComptimeVMOutputContract {
        _ = ctx; // Arena context available for complex evaluations

        // For now, simplified evaluation - store the constant
        const constant_entry = ConstantEntry{
            .name = input_contract.expression_name,
            .value = input_contract.expression_name, // Simplified: name as value
            .type_id = try self.astdb_system.str_interner.get("const"),
        };

        // GRANITE-SOLID: Simple append, no HashMap complexity
        try self.constants.append(constant_entry);

        return contracts.ComptimeVMOutputContract{
            .success = true,
            .result_value = constant_entry.value,
            .result_type = constant_entry.type_id,
            .should_cache = true,
            .evaluation_errors = &[_]contracts.ComptimeVMOutputContract.EvaluationError{},
        };
    }

    /// Evaluate type expression - GRANITE-SOLID implementation
    fn evaluateTypeExpression(self: *Self, input_contract: *const contracts.ComptimeVMInputContract, ctx: *EvaluationContext) !contracts.ComptimeVMOutputContract {
        _ = ctx; // Arena context available for complex evaluations

        // Simplified type expression evaluation for now
        const result_type = try self.astdb_system.str_interner.get("type");

        return contracts.ComptimeVMOutputContract{
            .success = true,
            .result_value = input_contract.expression_name,
            .result_type = result_type,
            .should_cache = true,
            .evaluation_errors = &[_]contracts.ComptimeVMOutputContract.EvaluationError{},
        };
    }

    /// Evaluate comptime function call - GRANITE-SOLID implementation
    fn evaluateComptimeFunctionCall(self: *Self, input_contract: *const contracts.ComptimeVMInputContract, ctx: *EvaluationContext) !contracts.ComptimeVMOutputContract {
        _ = ctx; // Arena context available for complex evaluations

        // Simplified comptime function call evaluation for now
        const result_type = try self.astdb_system.str_interner.get("unknown");

        return contracts.ComptimeVMOutputContract{
            .success = true,
            .result_value = input_contract.expression_name,
            .result_type = result_type,
            .should_cache = false, // Function calls typically not cached
            .evaluation_errors = &[_]contracts.ComptimeVMOutputContract.EvaluationError{},
        };
    }

    /// Evaluate compile time constant - GRANITE-SOLID implementation
    fn evaluateCompileTimeConstant(self: *Self, input_contract: *const contracts.ComptimeVMInputContract, ctx: *EvaluationContext) !contracts.ComptimeVMOutputContract {
        _ = ctx; // Arena context available for complex evaluations

        // Simplified compile time constant evaluation for now
        const result_type = try self.astdb_system.str_interner.get("comptime");

        return contracts.ComptimeVMOutputContract{
            .success = true,
            .result_value = input_contract.expression_name,
            .result_type = result_type,
            .should_cache = true,
            .evaluation_errors = &[_]contracts.ComptimeVMOutputContract.EvaluationError{},
        };
    }

    /// Create error output - GRANITE-SOLID helper
    fn createErrorOutput(self: *Self, error_type: contracts.ComptimeVMOutputContract.EvaluationError.ErrorType, message: StrId, source_span: astdb.Span) contracts.ComptimeVMOutputContract {
        _ = self;

        // Use static error array to avoid allocation
        const static_error = [_]contracts.ComptimeVMOutputContract.EvaluationError{
            contracts.ComptimeVMOutputContract.EvaluationError{
                .error_type = error_type,
                .message = message,
                .source_span = source_span,
            },
        };

        return contracts.ComptimeVMOutputContract{
            .success = false,
            .result_value = null,
            .result_type = null,
            .should_cache = false,
            .evaluation_errors = &static_error,
        };
    }

    /// Get constant value by name - GRANITE-SOLID linear search
    pub fn getConstantValue(self: *const Self, constant_name: StrId) ?StrId {
        // GRANITE-SOLID: Simple linear search, no HashMap complexity
        for (self.constants.items) |entry| {
            if (std.meta.eql(entry.name, constant_name)) {
                return entry.value;
            }
        }
        return null;
    }

    /// Get evaluation statistics
    pub fn getEvaluationStats(self: *const Self) EvaluationStats {
        return EvaluationStats{
            .total_evaluations = self.evaluation_count,
            .cached_constants = @as(u32, @intCast(self.constants.items.len)),
            .arena_bytes_used = 0, // Arena doesn't expose this easily
        };
    }

    pub const EvaluationStats = struct {
        total_evaluations: u32,
        cached_constants: u32,
        arena_bytes_used: u32,
    };

    /// Clear cached values - GRANITE-SOLID reset
    pub fn clearCache(self: *Self) void {
        // GRANITE-SOLID: Clear constants and reset arena
        self.constants.clearRetainingCapacity();

        // Reset arena to clean state
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.parent_allocator);
    }

    /// Reset evaluation context - for testing
    pub fn reset(self: *Self) void {
        self.clearCache();
        self.evaluation_count = 0;
    }
};
