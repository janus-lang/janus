// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Semantic Analysis Module - Complete Semantic Infrastructure
//!
//! This module provides the complete semantic analysis infrastructure for Janus,
//! including symbol resolution, type system, validation engine, and arena allocation.

// Core semantic components
// Core semantic components
pub const SymbolTable = @import("symbol_table.zig").SymbolTable;
pub const SymbolResolver = @import("symbol_resolver.zig").SymbolResolver;
pub const TypeSystem = @import("type_system.zig").TypeSystem;
pub const TypeId = @import("type_system.zig").TypeId;
pub const PrimitiveType = @import("type_system.zig").PrimitiveType;
pub const TypeChecker = @import("type_checker.zig").TypeChecker;
pub const TypeInference = @import("type_inference.zig").TypeInference;
pub const TypeInferenceDiagnostics = @import("type_inference_diagnostics.zig").TypeInferenceDiagnostics;
pub const ValidationEngine = @import("validation_engine.zig").ValidationEngine;
pub const ValidationResult = @import("validation_engine.zig").ValidationResult;
pub const ProfileManager = @import("profile_manager.zig").ProfileManager;

// Profile-specific validators
pub const CoreProfileValidator = @import("core_profile_validator.zig").CoreProfileValidator;
pub const CoreValidationResult = @import("core_profile_validator.zig").CoreValidationResult;
pub const CoreProfileType = @import("core_profile_validator.zig").CoreProfileType;

// Semantic Validator (full validation engine with :service profile support)
pub const SemanticValidator = @import("semantic_validator.zig").SemanticValidator;
pub const ValidationError = @import("semantic_validator.zig").ValidationError;

// Arena allocation components
pub const ArenaValidationContext = @import("validation_engine_arena.zig").ArenaValidationContext;
pub const ArenaValidation = @import("validation_engine_arena.zig").ArenaValidation;
pub const ZeroLeakValidator = @import("validation_engine_arena.zig").ZeroLeakValidator;
pub const MemoryTracker = @import("validation_engine_arena.zig").MemoryTracker;
pub const MemoryStats = @import("validation_engine_arena.zig").MemoryStats;

// Arena integration components
pub const ArenaIntegratedValidationEngine = @import("validation_engine_arena_integration.zig").ArenaIntegratedValidationEngine;
pub const ValidationEngineFactory = @import("validation_engine_arena_integration.zig").ValidationEngineFactory;
pub const UnifiedValidationEngine = @import("validation_engine_arena_integration.zig").UnifiedValidationEngine;
pub const ValidationMode = @import("validation_engine_arena_integration.zig").ValidationMode;

// Error management
pub const ErrorManager = @import("error_manager.zig").ErrorManager;
pub const InferenceContext = @import("error_manager.zig").InferenceContext;
pub const ControlFlowValidator = @import("control_flow_validator.zig").ControlFlowValidator;
pub const ControlFlowAnalyzer = @import("control_flow.zig").ControlFlowAnalyzer;
pub const ControlFlowResult = @import("control_flow.zig").ControlFlowResult;

// Utility modules
pub const source_span_utils = @import("source_span_utils.zig");
pub const type_canonical_hash = @import("type_canonical_hash.zig");
pub const module_visibility = @import("module_visibility.zig");

// Re-export commonly used types
pub const SemanticError = @import("validation_engine.zig").SemanticError;
pub const SemanticWarning = @import("validation_engine.zig").SemanticWarning;
pub const ErrorCode = @import("validation_engine.zig").ErrorCode;
pub const WarningCode = @import("validation_engine.zig").WarningCode;

// Include live-fire integration tests
test {
    _ = @import("semantic_live_fire_test.zig");
}
