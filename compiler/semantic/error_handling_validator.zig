// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Error Handling Semantic Validator
//!
//! Validates error handling semantics for Janus :core profile:
//! - S5001: Functions with `fail` must have error union return types
//! - S5002: `?` operator only valid on error unions, must propagate compatible errors
//! - S5003: `catch` expression type safety and error variable binding

const std = @import("std");
const Allocator = std.mem.Allocator;

const astdb = @import("astdb");
const NodeId = astdb.NodeId;
const NodeKind = astdb.NodeKind;

const type_system = @import("type_system.zig");
const TypeId = type_system.TypeId;
const TypeSystem = type_system.TypeSystem;

const symbol_table = @import("symbol_table.zig");
const SymbolTable = symbol_table.SymbolTable;
const SourceSpan = symbol_table.SourceSpan;

/// Error codes for error handling validation
pub const ErrorCode = enum {
    /// S5001: Function with `fail` must have error union return type
    missing_error_return_type,

    /// S5002: `?` operator requires error union expression
    invalid_error_propagation,

    /// S5003: `catch` expression type mismatch
    catch_type_mismatch,
};

/// Validation error with diagnostic information
pub const ValidationError = struct {
    code: ErrorCode,
    message: []const u8,
    span: SourceSpan,
    fix_suggestion: ?[]const u8,
};

/// Error Handling Validator
pub const ErrorHandlingValidator = struct {
    allocator: Allocator,
    astdb_snapshot: *astdb.Snapshot,
    type_system: *TypeSystem,
    symbol_table: *SymbolTable,
    errors: std.ArrayList(ValidationError),

    /// Current function's return type (for propagation checking)
    current_function_return_type: ?TypeId,

    pub fn init(
        allocator: Allocator,
        astdb_snapshot: *astdb.Snapshot,
        type_system_ptr: *TypeSystem,
        symbol_table_ptr: *SymbolTable,
    ) ErrorHandlingValidator {
        return ErrorHandlingValidator{
            .allocator = allocator,
            .astdb_snapshot = astdb_snapshot,
            .type_system = type_system_ptr,
            .symbol_table = symbol_table_ptr,
            .errors = .empty,
            .current_function_return_type = null,
        };
    }

    pub fn deinit(self: *ErrorHandlingValidator) void {
        self.errors.deinit();
    }

    /// Validate a function declaration for error handling
    pub fn validateFunctionDecl(self: *ErrorHandlingValidator, func_node_id: NodeId) !void {
        const func_node = self.astdb_snapshot.getNode(func_node_id) orelse return;

        if (func_node.kind != .func_decl) return;

        // Extract return type from function signature
        // This is simplified - real implementation needs to parse function signature
        self.current_function_return_type = null; // TODO: extract from AST

        // Check function body for fail statements
        const has_fail = try self.hasFails(func_node_id);

        if (has_fail) {
            // Rule S5001: Function with fail must have error union return type
            if (self.current_function_return_type) |ret_type| {
                if (!self.type_system.isErrorUnion(ret_type)) {
                    try self.addError(.{
                        .code = .missing_error_return_type,
                        .message = "Function contains 'fail' but return type is not an error union",
                        .span = self.getNodeSpan(func_node_id),
                        .fix_suggestion = "Add error union to return type: func_name() -> T ! ErrorType",
                    });
                }
            } else {
                // Function has no return type but contains fail
                try self.addError(.{
                    .code = .missing_error_return_type,
                    .message = "Function contains 'fail' but has no return type",
                    .span = self.getNodeSpan(func_node_id),
                    .fix_suggestion = "Add error union return type: -> T ! ErrorType",
                });
            }
        }

        // Reset function context
        self.current_function_return_type = null;
    }

    /// Validate try expression (expr?)
    pub fn validateTryExpr(self: *ErrorHandlingValidator, try_node_id: NodeId) !void {
        const try_node = self.astdb_snapshot.getNode(try_node_id) orelse return;

        if (try_node.kind != .try_expr) return;

        // Rule S5002: Expression must be an error union
        // TODO: Get expression type from child node
        const expr_type: ?TypeId = null; // Placeholder

        if (expr_type) |et| {
            if (!self.type_system.isErrorUnion(et)) {
                try self.addError(.{
                    .code = .invalid_error_propagation,
                    .message = "Try operator '?' requires an error union expression",
                    .span = self.getNodeSpan(try_node_id),
                    .fix_suggestion = "Expression must return an error union type (T ! E)",
                });
                return;
            }

            // Check that containing function returns error union
            if (self.current_function_return_type) |func_ret| {
                if (!self.type_system.isErrorUnion(func_ret)) {
                    try self.addError(.{
                        .code = .invalid_error_propagation,
                        .message = "Try operator '?' can only be used in functions that return error unions",
                        .span = self.getNodeSpan(try_node_id),
                        .fix_suggestion = "Change function return type to include error: -> T ! ErrorType",
                    });
                    return;
                }

                // Check error compatibility
                const expr_error = self.type_system.getErrorUnionError(et);
                const func_error = self.type_system.getErrorUnionError(func_ret);

                if (expr_error != null and func_error != null) {
                    // TODO: Check if errors are compatible (same type or subset)
                }
            }
        }
    }

    /// Validate catch expression
    pub fn validateCatchExpr(self: *ErrorHandlingValidator, catch_node_id: NodeId) !void {
        const catch_node = self.astdb_snapshot.getNode(catch_node_id) orelse return;

        if (catch_node.kind != .catch_expr) return;

        // Rule S5003: Expression must be an error union
        // TODO: Get expression type from child node
        const expr_type: ?TypeId = null; // Placeholder

        if (expr_type) |et| {
            if (!self.type_system.isErrorUnion(et)) {
                try self.addError(.{
                    .code = .catch_type_mismatch,
                    .message = "Catch expression requires an error union",
                    .span = self.getNodeSpan(catch_node_id),
                    .fix_suggestion = "Expression must return an error union type (T ! E)",
                });
            }
        }

        // TODO: Validate error variable binding in catch block
        // TODO: Validate catch block type matches payload type
    }

    /// Check if a node or its descendants contain fail statements
    fn hasFails(self: *ErrorHandlingValidator, node_id: NodeId) !bool {
        const node = self.astdb_snapshot.getNode(node_id) orelse return false;

        if (node.kind == .fail_stmt) return true;

        // Recursively check children
        // TODO: Implement proper child iteration using ASTDB
        return false;
    }

    /// Get source span for a node
    fn getNodeSpan(self: *ErrorHandlingValidator, node_id: NodeId) SourceSpan {
        _ = self;
        _ = node_id;
        // TODO: Extract actual span from ASTDB
        return SourceSpan{
            .start = 0,
            .end = 0,
            .line = 0,
            .column = 0,
        };
    }

    /// Add validation error to the list
    fn addError(self: *ErrorHandlingValidator, err: ValidationError) !void {
        try self.errors.append(err);
    }

    /// Get all validation errors
    pub fn getErrors(self: *ErrorHandlingValidator) []const ValidationError {
        return self.errors.items;
    }
};

/// Validate error handling for an entire compilation unit
pub fn validateUnit(
    allocator: Allocator,
    astdb_snapshot: *astdb.Snapshot,
    type_system_ptr: *TypeSystem,
    symbol_table_ptr: *SymbolTable,
    root_node_id: NodeId,
) ![]ValidationError {
    var validator = ErrorHandlingValidator.init(
        allocator,
        astdb_snapshot,
        type_system_ptr,
        symbol_table_ptr,
    );
    defer validator.deinit();

    // Walk AST and validate error handling constructs
    try validateNode(&validator, root_node_id);

    // Return collected errors (caller owns memory)
    const errors = try allocator.dupe(ValidationError, validator.getErrors());
    return errors;
}

/// Recursively validate a node and its children
fn validateNode(validator: *ErrorHandlingValidator, node_id: NodeId) !void {
    const node = validator.astdb_snapshot.getNode(node_id) orelse return;

    // Validate based on node kind
    switch (node.kind) {
        .func_decl => try validator.validateFunctionDecl(node_id),
        .try_expr => try validator.validateTryExpr(node_id),
        .catch_expr => try validator.validateCatchExpr(node_id),
        else => {},
    }

    // TODO: Recursively validate children
}
