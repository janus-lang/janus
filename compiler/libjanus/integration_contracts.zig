// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("astdb.zig");

/// Integration Contracts: Precise boundaries between compiler components
/// These contracts define immutable interfaces that prevent integration chaos.
/// Effect System Integration Contract - Input from Parser to Effect System
pub const EffectSystemInputContract = struct {
    /// Declaration ID from ASTDB for this function
    decl_id: astdb.DeclId,

    /// Function name as string ID
    function_name: astdb.StrId,

    /// AST node ID for the function declaration
    function_node: astdb.NodeId,

    /// Parameter information for effect and capability analysis
    parameters: []const ParameterInfo,

    /// Return type information (null for void functions)
    return_type: ?TypeInfo,

    /// Source span for error reporting
    source_span: astdb.Span,

    /// Parameter information for effect analysis
    pub const ParameterInfo = struct {
        /// Parameter name
        name: astdb.StrId,

        /// Type information
        type_info: TypeInfo,

        /// Whether this parameter is a capability (Cap* pattern)
        is_capability: bool,
    };

    /// Type information for effect analysis
    pub const TypeInfo = struct {
        /// Base type name
        base_type: astdb.StrId,

        /// Whether this is an error union (Type!Error)
        is_error_union: bool,

        /// Error type if this is an error union
        error_type: ?astdb.StrId,
    };
};

/// Effect System Integration Contract - Output from Effect System to Parser
pub const EffectSystemOutputContract = struct {
    /// Whether the registration was successful
    success: bool,

    /// Effects detected for this function
    detected_effects: []const astdb.StrId,

    /// Capabilities required by this function
    required_capabilities: []const astdb.StrId,

    /// Validation errors if registration failed
    validation_errors: []const ValidationError,

    /// Validation error information
    pub const ValidationError = struct {
        /// Type of validation error
        error_type: ErrorType,

        /// Error message (as string ID)
        message: astdb.StrId,

        /// Source location of the error
        source_span: astdb.Span,

        /// Types of validation errors
        pub const ErrorType = enum {
            invalid_effect,
            missing_capability,
            type_mismatch,
            unsupported_feature,
        };
    };
};

/// Comptime VM Integration Contract - Input from Parser to Comptime VM
pub const ComptimeVMInputContract = struct {
    /// Declaration ID from ASTDB for this comptime expression/function
    decl_id: astdb.DeclId,

    /// Expression name or identifier
    expression_name: astdb.StrId,

    /// AST node ID for the comptime expression
    expression_node: astdb.NodeId,

    /// Comptime expression type (const declaration, comptime function call, etc.)
    expression_type: ExpressionType,

    /// Dependencies for this comptime evaluation
    dependencies: []const astdb.NodeId,

    /// Source span for error reporting
    source_span: astdb.Span,

    /// Types of comptime expressions
    pub const ExpressionType = enum {
        const_declaration,
        comptime_function_call,
        type_expression,
        compile_time_constant,
    };
};

/// Comptime VM Integration Contract - Output from Comptime VM to Parser
pub const ComptimeVMOutputContract = struct {
    /// Whether the evaluation was successful
    success: bool,

    /// Evaluated result (as string representation for now)
    result_value: ?astdb.StrId,

    /// Result type information
    result_type: ?astdb.StrId,

    /// Whether this result should be cached
    should_cache: bool,

    /// Evaluation errors if evaluation failed
    evaluation_errors: []const EvaluationError,

    /// Evaluation error information
    pub const EvaluationError = struct {
        /// Type of evaluation error
        error_type: ErrorType,

        /// Error message (as string ID)
        message: astdb.StrId,

        /// Source location of the error
        source_span: astdb.Span,

        /// Types of evaluation errors
        pub const ErrorType = enum {
            undefined_identifier,
            type_mismatch,
            infinite_recursion,
            unsupported_operation,
            dependency_cycle,
        };
    };
};

/// Contract validation utilities
pub const ContractValidation = struct {
    /// Validate EffectSystemInputContract structure
    pub fn validateEffectSystemInput(contract: *const EffectSystemInputContract) bool {
        // Basic validation - ensure required fields are present
        if (contract.parameters.len > 100) return false; // Sanity check

        // Validate each parameter
        for (contract.parameters) |param| {
            _ = param; // Basic validation - could be expanded
        }

        return true;
    }

    /// Validate EffectSystemOutputContract structure
    pub fn validateEffectSystemOutput(contract: *const EffectSystemOutputContract) bool {
        // Basic validation
        if (!contract.success and contract.validation_errors.len == 0) {
            return false; // Failed contracts must have error information
        }

        if (contract.success and contract.validation_errors.len > 0) {
            return false; // Successful contracts should not have errors
        }

        return true;
    }

    /// Validate ComptimeVMInputContract structure
    pub fn validateComptimeVMInput(contract: *const ComptimeVMInputContract) bool {
        // Basic validation - ensure required fields are present
        if (contract.dependencies.len > 50) return false; // Sanity check for dependency cycles

        return true;
    }

    /// Validate ComptimeVMOutputContract structure
    pub fn validateComptimeVMOutput(contract: *const ComptimeVMOutputContract) bool {
        // Basic validation
        if (!contract.success and contract.evaluation_errors.len == 0) {
            return false; // Failed contracts must have error information
        }

        if (contract.success and contract.evaluation_errors.len > 0) {
            return false; // Successful contracts should not have errors
        }

        return true;
    }
};
