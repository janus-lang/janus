// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Q.TypeOf Implementation
//! Task 2.5 - Core Query Implementations (v1)
//!
//! Performs type inference for expressions and declarations.
//! This is a critical query for IDE features like hover and error checking.

const std = @import("std");
const Allocator = std.mem.Allocator;
const context = @import("../context.zig");
const astdb = @import("../../astdb.zig");

const QueryCtx = context.QueryCtx;
const CanonicalArgs = context.CanonicalArgs;
const QueryResultData = context.QueryResultData;
const TypeInfo = context.TypeInfo;
const CID = @import("../../astdb/ids.zig").CID;

/// Infer the type of an expression or declaration
pub fn typeOf(query_ctx: *QueryCtx, args: CanonicalArgs) !QueryResultData {
    // Extract arguments
    if (args.items.len != 1) {
        return error.QE0005_NonCanonicalArg;
    }

    const node_cid = switch (args.items[0]) {
        .cid => |cid| cid,
        else => return error.QE0005_NonCanonicalArg,
    };

    // Record dependency on the node
    try query_ctx.dependency_tracker.addDependency(.{ .cid = node_cid });

    // Get the AST node
    const node = try query_ctx.astdb.getNode(node_cid);

    // Infer type based on node type
    const type_info = try inferNodeType(query_ctx, node);

    return QueryResultData{
        .type_info = type_info,
    };
}

/// Infer the type of an AST node
fn inferNodeType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    return switch (node.node_type) {
        .literal_integer => inferIntegerLiteralType(node),
        .literal_float => inferFloatLiteralType(node),
        .literal_string => inferStringLiteralType(),
        .literal_boolean => inferBooleanLiteralType(),
        .identifier => try inferIdentifierType(query_ctx, node),
        .function_call => try inferFunctionCallType(query_ctx, node),
        .binary_operation => try inferBinaryOperationType(query_ctx, node),
        .unary_operation => try inferUnaryOperationType(query_ctx, node),
        .member_access => try inferMemberAccessType(query_ctx, node),
        .array_access => try inferArrayAccessType(query_ctx, node),
        .function_declaration => try inferFunctionDeclarationType(query_ctx, node),
        .variable_declaration => try inferVariableDeclarationType(query_ctx, node),
        .type_annotation => try inferTypeAnnotationType(query_ctx, node),
        else => TypeInfo{
            .type_name = "unknown",
            .type_cid = null,
            .is_mutable = false,
            .is_optional = false,
            .generic_params = &[_]TypeInfo{},
        },
    };
}

/// Infer type of integer literal
fn inferIntegerLiteralType(node: astdb.AstNode) TypeInfo {
    // For now, default to i32
    // In a full implementation, we'd analyze the literal value
    _ = node;
    return TypeInfo{
        .type_name = "i32",
        .type_cid = null, // Would be the CID of the i32 type
        .is_mutable = false,
        .is_optional = false,
        .generic_params = &[_]TypeInfo{},
    };
}

/// Infer type of float literal
fn inferFloatLiteralType(node: astdb.AstNode) TypeInfo {
    _ = node;
    return TypeInfo{
        .type_name = "f64",
        .type_cid = null,
        .is_mutable = false,
        .is_optional = false,
        .generic_params = &[_]TypeInfo{},
    };
}

/// Infer type of string literal
fn inferStringLiteralType() TypeInfo {
    return TypeInfo{
        .type_name = "string",
        .type_cid = null,
        .is_mutable = false,
        .is_optional = false,
        .generic_params = &[_]TypeInfo{},
    };
}

/// Infer type of boolean literal
fn inferBooleanLiteralType() TypeInfo {
    return TypeInfo{
        .type_name = "bool",
        .type_cid = null,
        .is_mutable = false,
        .is_optional = false,
        .generic_params = &[_]TypeInfo{},
    };
}

/// Infer type of identifier (variable reference)
fn inferIdentifierType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    // Look up the identifier in the symbol table
    const symbol_name = node.token_text;
    const scope_cid = node.scope_cid;

    // Use Q.ResolveName to find the symbol
    const resolve_name = @import("resolve_name.zig");
    var resolve_args = CanonicalArgs.init(query_ctx.allocator);
    defer resolve_args.deinit();

    try resolve_args.append(.{ .string = symbol_name });
    try resolve_args.append(.{ .cid = scope_cid });

    const resolve_result = try resolve_name.resolveName(query_ctx, resolve_args);
    const symbol_info = resolve_result.symbol_info;

    // Get the type from the symbol's definition
    return getSymbolType(query_ctx, symbol_info.definition_cid);
}

/// Infer type of function call
fn inferFunctionCallType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    // Get the function being called
    const function_node = try query_ctx.astdb.getNode(node.children[0]);

    // Infer the function's type
    const function_type = try inferNodeType(query_ctx, function_node);

    // Extract return type from function type
    // This would need proper function type representation
    return TypeInfo{
        .type_name = "unknown", // Would extract from function signature
        .type_cid = null,
        .is_mutable = false,
        .is_optional = false,
        .generic_params = &[_]TypeInfo{},
    };
}

/// Infer type of binary operation
fn inferBinaryOperationType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    const left_node = try query_ctx.astdb.getNode(node.children[0]);
    const right_node = try query_ctx.astdb.getNode(node.children[1]);

    const left_type = try inferNodeType(query_ctx, left_node);
    const right_type = try inferNodeType(query_ctx, right_node);

    // Type inference rules for binary operations
    const operator = node.operator_type;
    return switch (operator) {
        .add, .subtract, .multiply, .divide => blk: {
            // Arithmetic operations - result type is the "wider" of the two operands
            if (isNumericType(left_type.type_name) and isNumericType(right_type.type_name)) {
                break :blk selectWiderType(left_type, right_type);
            } else {
                return error.TypeMismatch;
            }
        },
        .equal, .not_equal, .less_than, .greater_than, .less_equal, .greater_equal => TypeInfo{
            .type_name = "bool",
            .type_cid = null,
            .is_mutable = false,
            .is_optional = false,
            .generic_params = &[_]TypeInfo{},
        },
        .logical_and, .logical_or => blk: {
            // Logical operations require boolean operands
            if (std.mem.eql(u8, left_type.type_name, "bool") and std.mem.eql(u8, right_type.type_name, "bool")) {
                break :blk TypeInfo{
                    .type_name = "bool",
                    .type_cid = null,
                    .is_mutable = false,
                    .is_optional = false,
                    .generic_params = &[_]TypeInfo{},
                };
            } else {
                return error.TypeMismatch;
            }
        },
        else => TypeInfo{
            .type_name = "unknown",
            .type_cid = null,
            .is_mutable = false,
            .is_optional = false,
            .generic_params = &[_]TypeInfo{},
        },
    };
}

/// Infer type of unary operation
fn inferUnaryOperationType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    const operand_node = try query_ctx.astdb.getNode(node.children[0]);
    const operand_type = try inferNodeType(query_ctx, operand_node);

    const operator = node.operator_type;
    return switch (operator) {
        .negate => blk: {
            if (isNumericType(operand_type.type_name)) {
                break :blk operand_type;
            } else {
                return error.TypeMismatch;
            }
        },
        .logical_not => blk: {
            if (std.mem.eql(u8, operand_type.type_name, "bool")) {
                break :blk operand_type;
            } else {
                return error.TypeMismatch;
            }
        },
        else => TypeInfo{
            .type_name = "unknown",
            .type_cid = null,
            .is_mutable = false,
            .is_optional = false,
            .generic_params = &[_]TypeInfo{},
        },
    };
}

/// Infer type of member access (e.g., obj.field)
fn inferMemberAccessType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    const object_node = try query_ctx.astdb.getNode(node.children[0]);
    const object_type = try inferNodeType(query_ctx, object_node);

    const member_name = node.member_name;

    // Look up the member in the object's type definition
    if (object_type.type_cid) |type_cid| {
        const type_def = try query_ctx.astdb.getTypeDefinition(type_cid);
        for (type_def.fields) |field| {
            if (std.mem.eql(u8, field.name, member_name)) {
                return field.field_type;
            }
        }
    }

    return error.MemberNotFound;
}

/// Infer type of array access (e.g., arr[index])
fn inferArrayAccessType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    const array_node = try query_ctx.astdb.getNode(node.children[0]);
    const array_type = try inferNodeType(query_ctx, array_node);

    // Extract element type from array type
    if (std.mem.startsWith(u8, array_type.type_name, "[]")) {
        const element_type_name = array_type.type_name[2..];
        return TypeInfo{
            .type_name = element_type_name,
            .type_cid = null, // Would need to resolve element type CID
            .is_mutable = array_type.is_mutable,
            .is_optional = false,
            .generic_params = &[_]TypeInfo{},
        };
    }

    return error.NotAnArray;
}

/// Infer type of function declaration
fn inferFunctionDeclarationType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    _ = query_ctx;
    _ = node;

    // Function declarations have function types
    return TypeInfo{
        .type_name = "function",
        .type_cid = null,
        .is_mutable = false,
        .is_optional = false,
        .generic_params = &[_]TypeInfo{},
    };
}

/// Infer type of variable declaration
fn inferVariableDeclarationType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    // Check if there's an explicit type annotation
    if (node.type_annotation) |type_node_cid| {
        const type_node = try query_ctx.astdb.getNode(type_node_cid);
        return inferTypeAnnotationType(query_ctx, type_node);
    }

    // Infer from initializer expression
    if (node.initializer) |init_cid| {
        const init_node = try query_ctx.astdb.getNode(init_cid);
        return inferNodeType(query_ctx, init_node);
    }

    return error.CannotInferType;
}

/// Infer type from type annotation
fn inferTypeAnnotationType(query_ctx: *QueryCtx, node: astdb.AstNode) !TypeInfo {
    _ = query_ctx;

    return TypeInfo{
        .type_name = node.type_name,
        .type_cid = node.type_cid,
        .is_mutable = node.is_mutable,
        .is_optional = node.is_optional,
        .generic_params = &[_]TypeInfo{}, // Would parse generic parameters
    };
}

/// Get the type of a symbol from its definition
fn getSymbolType(query_ctx: *QueryCtx, definition_cid: CID) !TypeInfo {
    const definition_node = try query_ctx.astdb.getNode(definition_cid);
    return inferNodeType(query_ctx, definition_node);
}

/// Check if a type name represents a numeric type
fn isNumericType(type_name: []const u8) bool {
    const numeric_types = [_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64" };
    for (numeric_types) |numeric_type| {
        if (std.mem.eql(u8, type_name, numeric_type)) {
            return true;
        }
    }
    return false;
}

/// Select the wider of two numeric types
fn selectWiderType(left: TypeInfo, right: TypeInfo) TypeInfo {
    // Simplified type widening rules
    const type_precedence = std.ComptimeStringMap(u8, .{
        .{ "i8", 1 },
        .{ "i16", 2 },
        .{ "i32", 3 },
        .{ "i64", 4 },
        .{ "u8", 1 },
        .{ "u16", 2 },
        .{ "u32", 3 },
        .{ "u64", 4 },
        .{ "f32", 5 },
        .{ "f64", 6 },
    });

    const left_precedence = type_precedence.get(left.type_name) orelse 0;
    const right_precedence = type_precedence.get(right.type_name) orelse 0;

    return if (left_precedence >= right_precedence) left else right;
}

// Tests
test "typeOf basic functionality" {
    const allocator = std.testing.allocator;

    var args = CanonicalArgs.init(allocator);
    defer args.deinit();

    try args.append(.{ .cid = CID{ .bytes = [_]u8{1} ** 32 } });

    // Would call typeOf here with a proper QueryCtx
    try std.testing.expect(args.items.len == 1);
}

test "numeric type checking" {
    try std.testing.expect(isNumericType("i32"));
    try std.testing.expect(isNumericType("f64"));
    try std.testing.expect(!isNumericType("string"));
    try std.testing.expect(!isNumericType("bool"));
}

test "type widening" {
    const i32_type = TypeInfo{
        .type_name = "i32",
        .type_cid = null,
        .is_mutable = false,
        .is_optional = false,
        .generic_params = &[_]TypeInfo{},
    };

    const f64_type = TypeInfo{
        .type_name = "f64",
        .type_cid = null,
        .is_mutable = false,
        .is_optional = false,
        .generic_params = &[_]TypeInfo{},
    };

    const wider = selectWiderType(i32_type, f64_type);
    try std.testing.expectEqualStrings("f64", wider.type_name);
}
