// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Arena Integration for Validation Engine
//!
//! Provides integrated arena-based validation engine that combines
//! semantic validation with zero-leak memory management.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import validation components
const ValidationEngine = @import("validation_engine.zig").ValidationEngine;
const ArenaValidationContext = @import("validation_engine_arena.zig").ArenaValidationContext;
const ArenaValidation = @import("validation_engine_arena.zig").ArenaValidation;
const ZeroLeakValidator = @import("validation_engine_arena.zig").ZeroLeakValidator;
const MemoryStats = @import("validation_engine_arena.zig").MemoryStats;

/// Validation modes for different use cases
pub const ValidationMode = enum {
    strict, // Full validation with all checks
    fast, // Optimized validation for performance
    debug, // Debug mode with extensive logging
    production, // Production mode with minimal overhead
};

/// Arena-integrated validation engine
pub const ArenaIntegratedValidationEngine = struct {
    base_engine: ValidationEngine,
    arena_context: ArenaValidationContext,
    arena_validation: ArenaValidation,
    leak_validator: ZeroLeakValidator,
    mode: ValidationMode,

    pub fn init(allocator: Allocator, mode: ValidationMode) !ArenaIntegratedValidationEngine {
        var arena_context = ArenaValidationContext.init(allocator);
        const arena_validation = ArenaValidation.init(&arena_context);
        const leak_validator = ZeroLeakValidator.init(allocator);

        // Initialize base validation engine with arena allocator
        const base_engine = try ValidationEngine.init(arena_context.allocator());

        return ArenaIntegratedValidationEngine{
            .base_engine = base_engine,
            .arena_context = arena_context,
            .arena_validation = arena_validation,
            .leak_validator = leak_validator,
            .mode = mode,
        };
    }

    pub fn deinit(self: *ArenaIntegratedValidationEngine) void {
        self.leak_validator.deinit();
        self.base_engine.deinit();
        self.arena_context.deinit();
    }

    /// Validate with arena memory management
    pub fn validateWithArena(self: *ArenaIntegratedValidationEngine, ast_node: anytype) !bool {
        // Track allocation for validation
        try self.arena_validation.validateAllocation(@sizeOf(@TypeOf(ast_node)));

        // Perform validation using base engine
        const result = try self.base_engine.validate(ast_node);

        // Validate zero leaks
        if (!self.leak_validator.validateZeroLeaks()) {
            return error.MemoryLeak;
        }

        return result;
    }

    /// Reset arena for next validation cycle
    pub fn resetArena(self: *ArenaIntegratedValidationEngine) void {
        self.arena_context.reset();
    }

    /// Get memory statistics
    pub fn getMemoryStats(self: *const ArenaIntegratedValidationEngine) MemoryStats {
        return self.arena_context.stats;
    }
};

/// Factory for creating validation engines
pub const ValidationEngineFactory = struct {
    base_allocator: Allocator,

    pub fn init(allocator: Allocator) ValidationEngineFactory {
        return ValidationEngineFactory{
            .base_allocator = allocator,
        };
    }

    /// Create arena-integrated validation engine
    pub fn createArenaEngine(self: *ValidationEngineFactory, mode: ValidationMode) !ArenaIntegratedValidationEngine {
        return ArenaIntegratedValidationEngine.init(self.base_allocator, mode);
    }

    /// Create standard validation engine
    pub fn createStandardEngine(self: *ValidationEngineFactory) !ValidationEngine {
        return ValidationEngine.init(self.base_allocator);
    }
};

/// Unified validation engine that can switch between modes
pub const UnifiedValidationEngine = struct {
    factory: ValidationEngineFactory,
    current_mode: ValidationMode,
    arena_engine: ?ArenaIntegratedValidationEngine,
    standard_engine: ?ValidationEngine,

    pub fn init(allocator: Allocator, initial_mode: ValidationMode) UnifiedValidationEngine {
        return UnifiedValidationEngine{
            .factory = ValidationEngineFactory.init(allocator),
            .current_mode = initial_mode,
            .arena_engine = null,
            .standard_engine = null,
        };
    }

    pub fn deinit(self: *UnifiedValidationEngine) void {
        if (self.arena_engine) |*engine| {
            engine.deinit();
        }
        if (self.standard_engine) |*engine| {
            engine.deinit();
        }
    }

    /// Switch validation mode
    pub fn switchMode(self: *UnifiedValidationEngine, new_mode: ValidationMode) !void {
        if (self.current_mode == new_mode) return;

        // Clean up current engine
        if (self.arena_engine) |*engine| {
            engine.deinit();
            self.arena_engine = null;
        }
        if (self.standard_engine) |*engine| {
            engine.deinit();
            self.standard_engine = null;
        }

        self.current_mode = new_mode;
    }

    /// Get or create appropriate engine for current mode
    pub fn getEngine(self: *UnifiedValidationEngine) !*ArenaIntegratedValidationEngine {
        if (self.arena_engine == null) {
            self.arena_engine = try self.factory.createArenaEngine(self.current_mode);
        }
        return &self.arena_engine.?;
    }

    /// Validate using current engine
    pub fn validate(self: *UnifiedValidationEngine, ast_node: anytype) !bool {
        var engine = try self.getEngine();
        return engine.validateWithArena(ast_node);
    }
};

// Tests
test "arena integrated validation engine" {
    _ = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try ArenaIntegratedValidationEngine.init(allocator, .debug);
    defer engine.deinit();

    // Mock AST node for testing
    const mock_node = struct { value: i32 = 42 };
    const node = mock_node{};

    const result = try engine.validateWithArena(node);
    try std.testing.expect(result == true); // Assuming validation passes
}

test "validation engine factory" {
    _ = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var factory = ValidationEngineFactory.init(allocator);

    var arena_engine = try factory.createArenaEngine(.fast);
    defer arena_engine.deinit();

    var standard_engine = try factory.createStandardEngine();
    defer standard_engine.deinit();
}

test "unified validation engine" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var unified = UnifiedValidationEngine.init(allocator, .production);
    defer unified.deinit();

    try unified.switchMode(.debug);
    try testing.expect(unified.current_mode == .debug);
}
