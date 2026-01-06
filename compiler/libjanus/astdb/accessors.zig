// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! ASTDB Accessor Layer - Schema/View Abstraction
//!
//! This module defines the **semantic schema** of how language constructs
//! map to the columnar ASTDB storage. It provides pure, defensive accessor
//! functions that encapsulate layout knowledge.
//!
//! **Architectural Role:**
//! - Layer 2 of the three-layer ASTDB architecture
//! - Isolates schema changes from semantic analysis consumers
//! - Enables future query memoization
//!
//! **Design Principles:**
//! - Pure functions (no state, no side effects)
//! - Defensive (validate kinds, return optional)
//! - Documented (schema comments for each accessor)
//! - Single source of truth for AST layout

const std = @import("std");
const core = @import("astdb_core");

pub const AstDB = core.AstDB;
pub const NodeId = core.NodeId;
pub const UnitId = core.UnitId;
pub const TokenId = core.TokenId;
pub const NodeKind = core.NodeKind;

// =============================================================================
// Binary Expressions
// =============================================================================

/// Get the left operand of a binary expression
/// Schema: children = [left_expr, right_expr]
pub fn getBinaryOpLeft(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .binary_expr) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get the right operand of a binary expression
/// Schema: children = [left_expr, right_expr]
pub fn getBinaryOpRight(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .binary_expr) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 2) children[1] else null;
}

/// Get the operator token of a binary expression
/// Returns the token between left and right operands
pub fn getBinaryOpOperator(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?TokenId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .binary_expr) return null;

    // Operator is between first and last token
    // For now, return first_token + 1 (heuristic)
    const left = getBinaryOpLeft(db, unit_id, node_id) orelse return null;
    const left_node = db.getNode(unit_id, left) orelse return null;

    return @enumFromInt(@intFromEnum(left_node.last_token) + 1);
}

// =============================================================================
// Unary Expressions
// =============================================================================

/// Get the operand of a unary expression
/// Schema: children = [operand_expr]
pub fn getUnaryOpOperand(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .unary_expr) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get the operator token of a unary expression
pub fn getUnaryOpOperator(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?TokenId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .unary_expr) return null;

    return node.first_token;
}

// =============================================================================
// Function Calls
// =============================================================================

/// Get the expression being called in a call expression
/// Schema: children = [callee_expr, arg1, arg2, ...]
pub fn getFunctionCallExpression(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .call_expr) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get all arguments to a function call
/// Schema: children = [callee_expr, arg1, arg2, ...]
/// Returns: slice of argument nodes (excludes callee)
pub fn getFunctionCallArguments(db: *const AstDB, unit_id: UnitId, node_id: NodeId) []const NodeId {
    const node = db.getNode(unit_id, node_id) orelse return &.{};
    if (node.kind != .call_expr) return &.{};

    const children = db.getChildren(unit_id, node_id);
    return if (children.len > 1) children[1..] else &.{};
}

// =============================================================================
// Array/Index Access
// =============================================================================

/// Get the expression being indexed
/// Schema: children = [array_expr, index_expr]
pub fn getArrayAccessExpression(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .index_expr) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get the index expression
/// Schema: children = [array_expr, index_expr]
pub fn getArrayAccessIndex(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .index_expr) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 2) children[1] else null;
}

// =============================================================================
// Array Literals
// =============================================================================

/// Get all elements of an array literal
/// Schema: children = [element1, element2, ...]
pub fn getArrayLiteralElements(db: *const AstDB, unit_id: UnitId, node_id: NodeId) []const NodeId {
    const node = db.getNode(unit_id, node_id) orelse return &.{};
    if (node.kind != .array_lit and node.kind != .array_literal) return &.{};

    return db.getChildren(unit_id, node_id);
}

// =============================================================================
// Field Access
// =============================================================================

/// Get the expression whose field is being accessed
/// Schema: children = [object_expr]
pub fn getFieldAccessExpression(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .field_expr) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get the field name token
/// The field name is stored as a token after the dot operator
pub fn getFieldAccessName(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?TokenId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .field_expr) return null;

    return node.last_token; // Field name is last token
}

// =============================================================================
// Variable Declarations (let/var)
// =============================================================================

/// Get the name identifier of a variable declaration
/// Schema: children = [name_node, type_annotation?, initializer?]
pub fn getVariableName(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .let_stmt and node.kind != .var_stmt) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get the type annotation of a variable declaration (if present)
/// Schema: children = [name_node, type_annotation?, initializer?]
pub fn getVariableTypeAnnotation(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .let_stmt and node.kind != .var_stmt) return null;

    const children = db.getChildren(unit_id, node_id);

    // Heuristic: if we have 3 children, middle is type annotation
    // if we have 2 children, check if second is a type node
    if (children.len == 3) return children[1];

    // TODO: Need better heuristic or metadata to distinguish type from initializer
    return null;
}

/// Get the initializer expression of a variable declaration (if present)
/// Schema: children = [name_node, type_annotation?, initializer?]
pub fn getVariableInitializer(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .let_stmt and node.kind != .var_stmt) return null;

    const children = db.getChildren(unit_id, node_id);

    // Last child is typically the initializer
    if (children.len == 3) return children[2]; // [name, type, init]
    if (children.len == 2) return children[1]; // [name, init]
    return null;
}

// =============================================================================
// Function Declarations
// =============================================================================

/// Get the name identifier of a function declaration
/// Schema: children = [name_node, param_list_node, return_type?, body_block]
pub fn getFunctionName(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .func_decl) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get the parameter list node of a function declaration
/// Schema: children = [name_node, param_list_node, return_type?, body_block]
pub fn getFunctionParameters(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .func_decl) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 2) children[1] else null;
}

/// Get the return type annotation of a function declaration (if present)
/// Schema: children = [name_node, param_list_node, return_type?, body_block]
pub fn getFunctionReturnType(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .func_decl) return null;

    const children = db.getChildren(unit_id, node_id);

    // Heuristic: if 4 children, [2] is return type
    if (children.len == 4) return children[2];
    return null;
}

/// Get the body block of a function declaration
/// Schema: children = [name_node, param_list_node, return_type?, body_block]
pub fn getFunctionBody(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .func_decl) return null;

    const children = db.getChildren(unit_id, node_id);

    // Last child is always the body
    if (children.len >= 3) return children[children.len - 1];
    return null;
}

// =============================================================================
// Parameter Declarations
// =============================================================================

/// Get the name of a parameter
/// Schema: children = [name_node, type_annotation]
pub fn getParameterName(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .param_decl) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get the type annotation of a parameter
/// Schema: children = [name_node, type_annotation]
pub fn getParameterTypeAnnotation(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .parameter) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 2) children[1] else null;
}

// =============================================================================
// Return Statements
// =============================================================================

/// Get the expression being returned (if any)
/// Schema: children = [return_expr?]
pub fn getReturnExpression(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .return_stmt) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

// =============================================================================
// Assignment Statements
// =============================================================================

/// Get the left-hand side of an assignment
/// Schema: children = [lhs_expr, rhs_expr]
pub fn getAssignmentLHS(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .assign_stmt) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get the right-hand side of an assignment
/// Schema: children = [lhs_expr, rhs_expr]
pub fn getAssignmentRHS(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .assign_stmt) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 2) children[1] else null;
}

// =============================================================================
// Block Statements
// =============================================================================

/// Get all statements in a block
/// Schema: children = [stmt1, stmt2, ...]
pub fn getBlockStatements(db: *const AstDB, unit_id: UnitId, node_id: NodeId) []const NodeId {
    const node = db.getNode(unit_id, node_id) orelse return &.{};
    if (node.kind != .block_stmt) return &.{};

    return db.getChildren(unit_id, node_id);
}

// =============================================================================
// Struct/Enum Declarations
// =============================================================================

/// Get the name of a struct/enum declaration
/// Schema: children = [name_node, body_node]
pub fn getStructName(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .struct_decl and node.kind != .enum_decl) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 1) children[0] else null;
}

/// Get the body of a struct/enum declaration
/// Schema: children = [name_node, body_node]
pub fn getStructBody(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .struct_decl and node.kind != .enum_decl) return null;

    const children = db.getChildren(unit_id, node_id);
    return if (children.len >= 2) children[1] else null;
}
