// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Type Inference Engine - The Brain of Semantic Understanding
//!
//! This module implements constraint-based type inference with unification
//! for automatic type deduction. It analyzes expressions, function calls,
//! and variable usage to infer types without explicit annotations.
//!
//! Key Features:
//! - Constraint-based inference with unification algorithm
//! - Expression type inference for all AST nodes
//! - Function parameter and return type inference
//! - Bidirectional type checking for improved accuracy
//! - Ambiguity detection and error reporting

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;

const libjanus = @import("astdb");
const astdb = libjanus.astdb;
const accessors = astdb.accessors; // Layer 2 accessor API
const symbol_table = @import("symbol_table.zig");
const type_system = @import("type_system.zig");
const pattern_coverage = @import("pattern_coverage.zig");

const NodeId = astdb.NodeId;
const SymbolId = symbol_table.SymbolId;
const TypeId = type_system.TypeId;
const TypeSystem = type_system.TypeSystem;
const SymbolTable = symbol_table.SymbolTable;
// Unique identifier for inference variables
pub const InferenceId = enum(u32) { _ };

/// Type constraint for inference solving
/// Function call constraint payload
pub const FunctionCallConstraint = struct { func: TypeId, args: []TypeId, result: TypeId };
/// Array access constraint payload
pub const ArrayAccessConstraint = struct { array: TypeId, index: TypeId, element: TypeId };
/// Field access constraint payload
pub const FieldAccessConstraint = struct { struct_type: TypeId, field_name: []const u8, field_type: TypeId };
/// Iterable constraint payload
pub const IterableConstraint = struct { collection: TypeId, element: TypeId };

/// Type constraint for inference solving
pub const TypeConstraint = union(enum) {
    /// T = U (equality constraint)
    equality: struct { left: TypeId, right: TypeId },
    /// T <: U (subtype constraint - T is assignable to U)
    subtype: struct { sub: TypeId, super: TypeId },
    /// T(args) -> R (function call constraint)
    function_call: FunctionCallConstraint,
    /// T[index] -> R (array access constraint)
    array_access: ArrayAccessConstraint,
    /// T.field -> R (field access constraint)
    field_access: FieldAccessConstraint,
    /// T is numeric (for arithmetic operations)
    numeric: TypeId,
    /// T is comparable (for comparison operations)
    comparable: TypeId,
    /// T is iterable (for loop constructs)
    iterable: IterableConstraint,
};

/// Inference statistics for performance monitoring
pub const InferenceStats = struct {
    constraints_generated: u32 = 0,
    constraints_solved: u32 = 0,
    inference_vars_created: u32 = 0,
    unification_steps: u32 = 0,
    ambiguous_inferences: u32 = 0,
};

/// Type Inference Engine with constraint solving
pub const TypeInference = struct {
    allocator: Allocator,
    type_system: *TypeSystem,
    symbol_table: *SymbolTable,
    astdb: *astdb.AstDB,
    unit_id: astdb.UnitId,

    /// Collected type constraints
    constraints: ArrayList(TypeConstraint),

    /// Inference variables and their resolved types
    inference_vars: std.AutoHashMap(InferenceId, TypeId),

    /// Node to inferred type mapping
    node_types: std.AutoHashMap(NodeId, TypeId),

    /// Next inference variable ID
    next_inference_id: u32 = 0,

    /// Inference statistics
    stats: InferenceStats = .{},

    pub fn init(allocator: Allocator, type_sys: *TypeSystem, symbol_tbl: *SymbolTable, astdb_instance: *astdb.AstDB, unit: astdb.UnitId) !*TypeInference {
        const inference = try allocator.create(TypeInference);
        inference.* = TypeInference{
            .allocator = allocator,
            .type_system = type_sys,
            .symbol_table = symbol_tbl,
            .astdb = astdb_instance,
            .unit_id = unit,
            .constraints = .empty,
            .inference_vars = std.AutoHashMap(InferenceId, TypeId).init(allocator),
            .node_types = std.AutoHashMap(NodeId, TypeId).init(allocator),
        };
        return inference;
    }

    pub fn deinit(self: *TypeInference) void {
        // Clean up constraint data
        for (self.constraints.items) |constraint| {
            switch (constraint) {
                .function_call => |call| self.allocator.free(call.args),
                .field_access => |field| self.allocator.free(field.field_name),
                else => {},
            }
        }
        self.constraints.deinit();

        self.inference_vars.deinit();
        self.node_types.deinit();

        self.allocator.destroy(self);
    }

    /// Create a new inference variable
    pub fn createInferenceVar(self: *TypeInference) !InferenceId {
        const inference_id: InferenceId = @enumFromInt(self.next_inference_id);
        self.next_inference_id += 1;
        self.stats.inference_vars_created += 1;
        return inference_id;
    }

    /// Infer types for an entire compilation unit
    pub fn inferUnit(self: *TypeInference, unit_id: astdb.UnitId) !void {
        _ = unit_id; // TODO: Use unit_id when getUnitRoot is implemented
        // TODO: Implement getUnitRoot in ASTDBSystem
        const root_node = @as(astdb.NodeId, @enumFromInt(0));

        // Phase 1: Generate constraints from AST
        try self.generateConstraints(root_node);

        // Phase 2: Solve constraints through unification
        try self.solveConstraints();

        // Phase 3: Assign resolved types to nodes
        try self.assignResolvedTypes();
    }

    fn getNode(self: *TypeInference, node_id: NodeId) ?*const astdb.AstNode {
        return self.astdb.getNode(self.unit_id, node_id);
    }

    /// Generate type constraints from AST node
    pub fn generateConstraints(self: *TypeInference, node_id: NodeId) anyerror!void {
        const node = self.getNode(node_id) orelse return;

        switch (node.kind) {
            .integer_literal => try self.inferLiteralInt(node_id),
            .float_literal => try self.inferLiteralFloat(node_id),
            .string_literal => try self.inferLiteralString(node_id),
            .bool_literal => try self.inferLiteralBool(node_id),
            .identifier => try self.inferIdentifier(node_id),
            .binary_expr => try self.inferBinaryOp(node_id),
            .unary_expr => try self.inferUnaryOp(node_id),
            .call_expr => try self.inferFunctionCall(node_id),
            .index_expr => try self.inferArrayAccess(node_id),
            .field_expr => try self.inferFieldAccess(node_id),
            .array_lit, .array_literal => try self.inferArrayLiteral(node_id),
            .let_stmt, .var_stmt => try self.inferVariableDeclaration(node_id),
            .func_decl => try self.inferFunctionDeclaration(node_id),
            .async_func_decl => try self.inferFunctionDeclaration(node_id), // :service profile
            .return_stmt => try self.inferReturnStatement(node_id),
            .match_stmt => try self.inferMatchStatement(node_id),
            .postfix_when => try self.inferPostfixWhen(node_id),
            .postfix_unless => try self.inferPostfixWhen(node_id), // Same logic as when
            else => {
                // Recurse into child nodes
                const children = self.astdb.getChildren(self.unit_id, node_id);
                for (children) |child_id| {
                    try self.generateConstraints(child_id);
                }
            },
        }
    }

    /// Infer type for integer literal
    fn inferLiteralInt(self: *TypeInference, node_id: NodeId) !void {
        // Default to i32 for integer literals
        try self.setNodeType(node_id, self.type_system.getPrimitiveType(.i32));
    }

    /// Infer type for float literal
    fn inferLiteralFloat(self: *TypeInference, node_id: NodeId) !void {
        // Default to f64 for float literals
        try self.setNodeType(node_id, self.type_system.getPrimitiveType(.f64));
    }

    /// Infer type for string literal
    fn inferLiteralString(self: *TypeInference, node_id: NodeId) !void {
        try self.setNodeType(node_id, self.type_system.getPrimitiveType(.string));
    }

    /// Infer type for boolean literal
    fn inferLiteralBool(self: *TypeInference, node_id: NodeId) !void {
        try self.setNodeType(node_id, self.type_system.getPrimitiveType(.bool));
    }

    /// Infer type for array literal - homogeneous type checking
    fn inferArrayLiteral(self: *TypeInference, node_id: NodeId) !void {
        const elements = accessors.getArrayLiteralElements(self.astdb, self.unit_id, node_id);

        if (elements.len == 0) {
            // Empty array literal: type is `[0]T` where T is an inference variable
            const element_var = try self.createInferenceVar();
            const element_type = try self.createInferredType(element_var);
            const array_type = try self.type_system.createArrayType(element_type, 0);
            try self.setNodeType(node_id, array_type);
            return;
        }

        // Infer types of all elements
        var element_types: ArrayList(TypeId) = .empty;
        defer element_types.deinit();

        for (elements) |element_node| {
            try self.generateConstraints(element_node);
            try element_types.append(self.getNodeType(element_node));
        }

        // Create an inference variable for the common element type
        // This allows subtyping (e.g., [i32, i32] -> matches [numeric])
        const common_element_var = try self.createInferenceVar();
        const common_element_type = try self.createInferredType(common_element_var);

        for (element_types.items) |elem_type| {
            try self.addConstraint(.{ .subtype = .{ .sub = elem_type, .super = common_element_type } });
        }

        // The array literal's type is `[N]T`
        const array_type = try self.type_system.createArrayType(common_element_type, @as(u32, @intCast(elements.len)));
        try self.setNodeType(node_id, array_type);
    }

    /// Infer type for identifier reference
    fn inferIdentifier(self: *TypeInference, node_id: NodeId) !void {
        const node = self.getNode(node_id) orelse return;

        // Get identifier name from token
        const token = self.astdb.getToken(self.unit_id, node.first_token) orelse return;
        const name_bytes = if (token.str) |str_id| (self.astdb.str_interner.get(str_id) orelse "") else "";

        // Intern the string to get StringId
        const name_id = try self.symbol_table.symbol_interner.intern(name_bytes);

        // Look up symbol in current scope
        const symbol_id = self.symbol_table.resolveIdentifier(name_id, null) orelse {
            // Undefined symbol - will be caught by symbol resolver
            // For now, assign an error type or skip
            return;
        };

        // Get symbol and its type
        const symbol = self.symbol_table.getSymbol(symbol_id) orelse return;

        if (symbol.type_id) |type_id| {
            // Symbol has a known type, use it
            try self.setNodeType(node_id, type_id);
        } else {
            // Symbol doesn't have a type yet - create inference variable
            const infer_var = try self.createInferenceVar();
            const type_id = try self.createInferredType(infer_var);
            try self.setNodeType(node_id, type_id);

            // Add constraint that this identifier's type equals the symbol's type
            // (will be resolved when symbol's type is determined)
            // Note: We need to store this relationship.
            // Ideally we'd add a constraint: .equality = { .left = infer_var, .right = symbol_type_placeholder }
            // But we don't have a symbol placeholder type.
            // For now, we'll just leave it as an inference variable.
            // The symbol's type will be inferred when its declaration is processed.
            // We should link them if possible.

            // Actually, we should probably set the symbol's type to this inference variable if it's null!
            // But symbols are shared. One inference variable per usage?
            // If we set symbol.type_id = infer_var, then all usages get the same inference var.
            // That's what we want!

            // However, getSymbol returns a pointer to const Symbol or mutable?
            // In SymbolTable.getSymbol it returns `?*Symbol`. So it is mutable.
            // But I accessed it as `const symbol`.
            var mutable_symbol = self.symbol_table.getSymbol(symbol_id) orelse return;
            mutable_symbol.type_id = type_id;
        }
    }

    /// Infer type for binary operation
    fn inferBinaryOp(self: *TypeInference, node_id: NodeId) !void {
        const left_child = accessors.getBinaryOpLeft(self.astdb, self.unit_id, node_id) orelse return;
        const right_child = accessors.getBinaryOpRight(self.astdb, self.unit_id, node_id) orelse return;
        const operator_id = accessors.getBinaryOpOperator(self.astdb, self.unit_id, node_id) orelse return;
        const operator_token = self.astdb.getToken(self.unit_id, operator_id) orelse return;

        // Recursively infer operand types
        try self.generateConstraints(left_child);
        try self.generateConstraints(right_child);

        const left_type = self.getNodeType(left_child);
        const right_type = self.getNodeType(right_child);

        switch (operator_token.kind) {
            .plus, .minus, .star, .slash => {
                // Arithmetic operations: operands must be numeric
                try self.addConstraint(.{ .numeric = left_type });
                try self.addConstraint(.{ .numeric = right_type });

                // Result type is the "larger" of the two operand types
                const result_type = try self.promoteArithmeticTypes(left_type, right_type);
                try self.setNodeType(node_id, result_type);

                // Add equality constraints for type promotion
                try self.addConstraint(.{ .subtype = .{ .sub = left_type, .super = result_type } });
                try self.addConstraint(.{ .subtype = .{ .sub = right_type, .super = result_type } });
            },
            .equal_equal, .not_equal, .less, .less_equal, .greater, .greater_equal => {
                // Comparison operations: operands must be comparable
                try self.addConstraint(.{ .comparable = left_type });
                try self.addConstraint(.{ .comparable = right_type });

                // Operands must be compatible for comparison
                try self.addConstraint(.{ .equality = .{ .left = left_type, .right = right_type } });

                // Result is always boolean
                try self.setNodeType(node_id, self.type_system.getPrimitiveType(.bool));
            },
            .logical_and, .logical_or => {
                // Logical operations: operands must be boolean
                try self.addConstraint(.{ .equality = .{ .left = left_type, .right = self.type_system.getPrimitiveType(.bool) } });
                try self.addConstraint(.{ .equality = .{ .left = right_type, .right = self.type_system.getPrimitiveType(.bool) } });

                // Result is boolean
                try self.setNodeType(node_id, self.type_system.getPrimitiveType(.bool));
            },
            .range_inclusive, .range_exclusive => {
                // Range operations: operands must be numeric and same type
                try self.addConstraint(.{ .numeric = left_type });
                try self.addConstraint(.{ .numeric = right_type });
                try self.addConstraint(.{ .equality = .{ .left = left_type, .right = right_type } });

                // Result is Range[T] where T is the operand type
                const is_inclusive = operator_token.kind == .range_inclusive;
                const range_type = try self.type_system.createRangeType(left_type, is_inclusive);
                try self.setNodeType(node_id, range_type);
            },
            else => return error.InvalidOperator,
        }
    }

    /// Infer type for unary operation
    fn inferUnaryOp(self: *TypeInference, node_id: NodeId) !void {
        const operand = accessors.getUnaryOpOperand(self.astdb, self.unit_id, node_id) orelse return;
        const operator_id = accessors.getUnaryOpOperator(self.astdb, self.unit_id, node_id) orelse return;
        const operator_token = self.astdb.getToken(self.unit_id, operator_id) orelse return;

        try self.generateConstraints(operand);
        const operand_type = self.getNodeType(operand);

        switch (operator_token.kind) {
            .minus => {
                // Numeric negation: operand must be numeric, result same type
                try self.addConstraint(.{ .numeric = operand_type });
                try self.setNodeType(node_id, operand_type);
            },
            .logical_not, .exclamation => {
                // Logical not: operand must be boolean, result boolean
                try self.addConstraint(.{ .equality = .{ .left = operand_type, .right = self.type_system.getPrimitiveType(.bool) } });
                try self.setNodeType(node_id, self.type_system.getPrimitiveType(.bool));
            },
            .ampersand => {
                // Address-of: create pointer type to operand
                const pointer_type = try self.type_system.createPointerType(operand_type, false);
                try self.setNodeType(node_id, pointer_type);
            },
            .star => {
                // Dereference: operand must be pointer, result is pointee type
                const pointee_type = try self.createInferenceVar();
                const pointee_type_id = try self.createInferredType(pointee_type);
                // Assume mutable pointer for now, or check if we need to distinguish
                const expected_pointer = try self.type_system.createPointerType(pointee_type_id, true);

                try self.addConstraint(.{ .equality = .{ .left = operand_type, .right = expected_pointer } });
                try self.setNodeType(node_id, pointee_type_id);
            },
            else => return error.InvalidOperator,
        }
    }

    /// Infer type for function call
    fn inferFunctionCall(self: *TypeInference, node_id: NodeId) !void {
        const func_expr = accessors.getFunctionCallExpression(self.astdb, self.unit_id, node_id) orelse return;
        const args = accessors.getFunctionCallArguments(self.astdb, self.unit_id, node_id);

        // Infer function expression type
        try self.generateConstraints(func_expr);
        const func_type = self.getNodeType(func_expr);

        // Infer argument types
        var arg_types: ArrayList(TypeId) = .empty;
        defer arg_types.deinit();

        for (args) |arg_node| {
            try self.generateConstraints(arg_node);
            try arg_types.append(self.getNodeType(arg_node));
        }

        // Create inference variable for result type
        const result_var = try self.createInferenceVar();
        const result_type = try self.createInferredType(result_var);

        // Add function call constraint
        const owned_args = try self.allocator.dupe(TypeId, arg_types.items);
        try self.addConstraint(.{ .function_call = .{ .func = func_type, .args = owned_args, .result = result_type } });

        try self.setNodeType(node_id, result_type);
    }

    /// Infer type for array access
    fn inferArrayAccess(self: *TypeInference, node_id: NodeId) !void {
        const array_expr = accessors.getArrayAccessExpression(self.astdb, self.unit_id, node_id) orelse return;
        const index_expr = accessors.getArrayAccessIndex(self.astdb, self.unit_id, node_id) orelse return;

        try self.generateConstraints(array_expr);
        try self.generateConstraints(index_expr);

        const array_type = self.getNodeType(array_expr);
        const index_type = self.getNodeType(index_expr);

        // Index must be integer
        try self.addConstraint(.{ .subtype = .{ .sub = index_type, .super = self.type_system.getPrimitiveType(.i32) } });

        // Create inference variable for element type
        const element_var = try self.createInferenceVar();
        const element_type = try self.createInferredType(element_var);

        // Add array access constraint
        try self.addConstraint(.{ .array_access = .{ .array = array_type, .index = index_type, .element = element_type } });

        try self.setNodeType(node_id, element_type);
    }

    /// Infer type for field access
    fn inferFieldAccess(self: *TypeInference, node_id: NodeId) !void {
        const struct_expr = accessors.getFieldAccessExpression(self.astdb, self.unit_id, node_id) orelse return;
        const field_name = accessors.getFieldAccessName(self.astdb, self.unit_id, node_id) orelse return;

        try self.generateConstraints(struct_expr);
        const struct_type = self.getNodeType(struct_expr);

        // Create inference variable for field type
        const field_var = try self.createInferenceVar();
        const field_type = try self.createInferredType(field_var);

        // Add field access constraint
        const field_token = self.astdb.getToken(self.unit_id, field_name) orelse return;
        const field_str = if (field_token.str) |str_id| (self.astdb.str_interner.get(str_id) orelse "") else "";
        const owned_field_name = try self.allocator.dupe(u8, field_str);
        try self.addConstraint(.{ .field_access = .{ .struct_type = struct_type, .field_name = owned_field_name, .field_type = field_type } });

        try self.setNodeType(node_id, field_type);
    }

    /// Infer type for variable declaration
    fn inferVariableDeclaration(self: *TypeInference, node_id: NodeId) !void {
        const initializer = accessors.getVariableInitializer(self.astdb, self.unit_id, node_id);
        const type_annotation = accessors.getVariableTypeAnnotation(self.astdb, self.unit_id, node_id);

        if (type_annotation) |type_node| {
            // Explicit type annotation
            const declared_type = try self.resolveTypeAnnotation(type_node);
            try self.setNodeType(node_id, declared_type);

            if (initializer) |init_node| {
                // Check initializer compatibility
                try self.generateConstraints(init_node);
                const init_type = self.getNodeType(init_node);
                try self.addConstraint(.{ .subtype = .{ .sub = init_type, .super = declared_type } });
            }
        } else if (initializer) |init_node| {
            // Infer from initializer
            try self.generateConstraints(init_node);
            const init_type = self.getNodeType(init_node);
            try self.setNodeType(node_id, init_type);
        } else {
            // No type annotation or initializer - error
            return error.CannotInferType;
        }
    }

    /// Infer type for function declaration
    fn inferFunctionDeclaration(self: *TypeInference, node_id: NodeId) !void {
        const params = accessors.getFunctionParameters(self.astdb, self.unit_id, node_id);
        const return_annotation = accessors.getFunctionReturnType(self.astdb, self.unit_id, node_id);
        const body = accessors.getFunctionBody(self.astdb, self.unit_id, node_id);

        // Collect parameter types
        var param_types: ArrayList(TypeId) = .empty;
        defer param_types.deinit();

        if (params) |param_list| {
            const param_nodes = self.astdb.getChildren(self.unit_id, param_list);
            for (param_nodes) |param_node| {
                const param_type_annotation = accessors.getParameterTypeAnnotation(self.astdb, self.unit_id, param_node);
                if (param_type_annotation) |type_node| {
                    const param_type = try self.resolveTypeAnnotation(type_node);
                    try param_types.append(param_type);
                } else {
                    // Create inference variable for parameter
                    const param_var = try self.createInferenceVar();
                    const param_type = try self.createInferredType(param_var);
                    try param_types.append(param_type);
                }
            }
        }

        // Determine return type
        const return_type = if (return_annotation) |ret_node|
            try self.resolveTypeAnnotation(ret_node)
        else blk: {
            // Infer return type from function body
            const ret_var = try self.createInferenceVar();
            break :blk try self.createInferredType(ret_var);
        };

        // Create function type
        const owned_params = try self.allocator.dupe(TypeId, param_types.items);
        // Check if this is an async function (:service profile)
        const node = self.astdb.getNode(self.unit_id, node_id) orelse return error.InvalidNode;
        const is_async = (node.kind == .async_func_decl);
        const func_type = try self.type_system.createFunctionType(owned_params, return_type, .janus_call, is_async);
        try self.setNodeType(node_id, func_type);

        // Infer function body if present
        if (body) |body_node| {
            try self.generateConstraints(body_node);
        }
    }

    /// Infer type for return statement
    fn inferReturnStatement(self: *TypeInference, node_id: NodeId) !void {
        // Get the return expression if present
        const return_expr = accessors.getReturnExpression(self.astdb, self.unit_id, node_id);

        if (return_expr) |expr_node| {
            // Infer type of return expression
            try self.generateConstraints(expr_node);
            const expr_type = self.getNodeType(expr_node);

            // Set the return statement's type to the expression type
            try self.setNodeType(node_id, expr_type);

            // TODO: Add constraint that this matches the enclosing function's return type
        } else {
            // Empty return statement - type is void
            try self.setNodeType(node_id, self.type_system.getPrimitiveType(.void));
        }
    }

    /// Solve all collected constraints through unification
    pub fn solveConstraints(self: *TypeInference) !void {
        var changed = true;

        while (changed) {
            changed = false;

            // Iterate backwards so we can swapRemove without skipping elements
            // But wait, order might matter for inference variable propagation?
            // Actually, we should iterate forward. If we remove, we decr index.
            // Also, new constraints might be appended to the end.

            var i: usize = 0;
            while (i < self.constraints.items.len) {
                const constraint = self.constraints.items[i];
                const solved = try self.solveConstraint(constraint);

                if (solved) {
                    // Constraint is satisfied and can be removed
                    // Or it has been transformed into simpler constraints
                    _ = self.constraints.swapRemove(i);
                    changed = true;
                    self.stats.constraints_solved += 1;
                    // Don't increment i, as we pulled a new element into this slot
                } else {
                    // Not solved yet (maybe waiting for inference var)
                    i += 1;
                }

                self.stats.unification_steps += 1;
            }
        }
    }

    /// Solve a single constraint
    fn solveConstraint(self: *TypeInference, constraint: TypeConstraint) !bool {
        return switch (constraint) {
            .equality => |eq| try self.unifyTypes(eq.left, eq.right),
            .subtype => |sub| try self.checkSubtype(sub.sub, sub.super),
            .function_call => |call| try self.solveFunctionCall(call),
            .array_access => |access| try self.solveArrayAccess(access),
            .field_access => |field| try self.solveFieldAccess(field),
            .numeric => |type_id| try self.checkNumeric(type_id),
            .comparable => |type_id| try self.checkComparable(type_id),
            .iterable => |iter| try self.checkIterable(iter),
        };
    }

    /// Unify two types (make them equal)
    fn unifyTypes(self: *TypeInference, type1: TypeId, type2: TypeId) !bool {
        if (type1.eql(type2)) return true; // Already unified (satisfied)

        // Handle inference variables
        if (self.isInferenceVariable(type1)) {
            try self.bindInferenceVariable(type1, type2);
            return true;
        }

        if (self.isInferenceVariable(type2)) {
            try self.bindInferenceVariable(type2, type1);
            return true;
        }

        // Check if types are compatible
        if (self.type_system.isAssignable(type1, type2) or self.type_system.isAssignable(type2, type1)) {
            return false; // Compatible but not unified
        }

        return error.TypeMismatch;
    }

    /// Helper methods for constraint solving
    fn checkSubtype(self: *TypeInference, sub: TypeId, super: TypeId) !bool {
        return self.type_system.isAssignable(sub, super);
    }

    fn solveFunctionCall(self: *TypeInference, call: FunctionCallConstraint) !bool {
        // Solve function call constraint: func_type(args) -> result

        // If function type is an inference variable, we can't solve yet
        if (self.isInferenceVariable(call.func)) {
            return false; // Need more information
        }

        const func_info = self.type_system.getTypeInfo(call.func);

        if (func_info.kind == .function) {
            const func_def = func_info.kind.function;

            // Unify result type with function return type
            _ = try self.unifyTypes(call.result, func_def.return_type);

            // Check argument compatibility (simplified for now)
            // Ideally we would constraints for each arg against param type
            if (call.args.len == func_def.parameter_types.len) {
                for (call.args, 0..) |arg_type, i| {
                    const param_type = func_def.parameter_types[i];
                    // We generate subtype constraint: arg <: param
                    try self.addConstraint(.{ .subtype = .{ .sub = arg_type, .super = param_type } });
                }
            } else {
                return error.ArgumentCountMismatch;
            }

            return true;
        }

        return error.NotAFunction;
    }

    fn solveArrayAccess(self: *TypeInference, access: ArrayAccessConstraint) !bool {
        // Solve array access constraint: array[index] -> element

        // If array is an inference variable, we can't solve yet
        if (self.isInferenceVariable(access.array)) {
            return false;
        }

        const array_info = self.type_system.getTypeInfo(access.array);

        switch (array_info.kind) {
            .array => |arr| {
                _ = try self.unifyTypes(access.element, arr.element_type);
                return true;
            },
            .slice => |slice| {
                _ = try self.unifyTypes(access.element, slice.element_type);
                return true;
            },
            .tensor => |tensor| {
                _ = try self.unifyTypes(access.element, tensor.element_type);
                return true;
            },
            else => return error.NotIndexable,
        }
    }

    fn solveFieldAccess(self: *TypeInference, field: FieldAccessConstraint) !bool {
        // Solve field access constraint: struct.field -> field_type

        // If struct type is an inference variable, we can't solve yet
        if (self.isInferenceVariable(field.struct_type)) {
            return false;
        }

        const type_info = self.type_system.getTypeInfo(field.struct_type);
        switch (type_info.kind) {
            .structure => |s| {
                for (s.fields) |f| {
                    if (std.mem.eql(u8, f.name, field.field_name)) {
                        // Found the field, unify its type
                        _ = try self.unifyTypes(field.field_type, f.type_id);
                        return true;
                    }
                }
                return error.FieldNotFound;
            },
            else => return error.TypeNotStruct,
        }
    }

    fn checkNumeric(self: *TypeInference, type_id: TypeId) !bool {
        // Check if type is a numeric type (integers or floats)
        if (type_id.eql(self.type_system.getPrimitiveType(.i32)) or
            type_id.eql(self.type_system.getPrimitiveType(.i64)) or
            type_id.eql(self.type_system.getPrimitiveType(.f32)) or
            type_id.eql(self.type_system.getPrimitiveType(.f64)))
        {
            return true; // Already numeric, constraint satisfied
        }

        // If it's an inference variable, we could bind it to a numeric constraint
        if (self.isInferenceVariable(type_id)) {
            // For now, bind to i32 as default numeric type
            try self.bindInferenceVariable(type_id, self.type_system.getPrimitiveType(.i32));
            return true;
        }

        return error.TypeIsNotNumeric;
    }

    fn checkComparable(self: *TypeInference, type_id: TypeId) !bool {
        // Check if type is comparable (primitives are comparable)
        if (type_id.eql(self.type_system.getPrimitiveType(.i32)) or
            type_id.eql(self.type_system.getPrimitiveType(.i64)) or
            type_id.eql(self.type_system.getPrimitiveType(.f32)) or
            type_id.eql(self.type_system.getPrimitiveType(.f64)) or
            type_id.eql(self.type_system.getPrimitiveType(.bool)) or
            type_id.eql(self.type_system.getPrimitiveType(.string)))
        {
            return true; // Already comparable, constraint satisfied
        }

        // Inference variables can be bound to comparable types
        if (self.isInferenceVariable(type_id)) {
            // Default to i32 for comparable constraint
            try self.bindInferenceVariable(type_id, self.type_system.getPrimitiveType(.i32));
            return true;
        }

        return error.TypeIsNotComparable;
    }

    fn checkIterable(self: *TypeInference, iter: IterableConstraint) !bool {
        // Check if collection type is iterable (arrays, slices)
        if (self.isInferenceVariable(iter.collection)) {
            return false;
        }

        const type_info = self.type_system.getTypeInfo(iter.collection);
        switch (type_info.kind) {
            .array => |arr| {
                _ = try self.unifyTypes(iter.element, arr.element_type);
                return true;
            },
            .slice => |slice| {
                _ = try self.unifyTypes(iter.element, slice.element_type);
                return true;
            },
            .primitive => |prim| {
                if (prim == .string) {
                    // Strings iterate over characters (assume i32 codepoints for now if u8 missing)
                    // TODO: Verify string iteration type
                    _ = try self.unifyTypes(iter.element, self.type_system.getPrimitiveType(.i32));
                    return true;
                }
                return error.TypeNotIterable;
            },
            else => return error.TypeNotIterable,
        }
    }

    /// Helper methods
    fn setNodeType(self: *TypeInference, node_id: NodeId, type_id: TypeId) !void {
        try self.node_types.put(node_id, type_id);
    }

    pub fn getNodeType(self: *TypeInference, node_id: NodeId) TypeId {
        return self.node_types.get(node_id) orelse self.type_system.getPrimitiveType(.void);
    }

    fn addConstraint(self: *TypeInference, constraint: TypeConstraint) !void {
        try self.constraints.append(constraint);
        self.stats.constraints_generated += 1;
    }

    fn createInferredType(self: *TypeInference, inference_id: InferenceId) !TypeId {
        // Create an inference variable type in the type system
        const type_id = try self.type_system.createInferenceType(@intFromEnum(inference_id));

        // Store the inference variable with unknown type initially
        // We use void as the temporary "unresolved" concrete type
        try self.inference_vars.put(inference_id, self.type_system.getPrimitiveType(.void));

        return type_id;
    }

    fn resolveTypeAnnotation(self: *TypeInference, type_node: NodeId) !TypeId {
        // Resolve type annotation node to concrete TypeId
        const node = self.getNode(type_node) orelse return self.type_system.getPrimitiveType(.void);

        switch (node.kind) {
            .primitive_type => {
                // Get type name from token and map to primitive
                const type_name = try self.getNodeText(type_node);
                if (std.mem.eql(u8, type_name, "i32")) return self.type_system.getPrimitiveType(.i32);
                if (std.mem.eql(u8, type_name, "i64")) return self.type_system.getPrimitiveType(.i64);
                if (std.mem.eql(u8, type_name, "f32")) return self.type_system.getPrimitiveType(.f32);
                if (std.mem.eql(u8, type_name, "f64")) return self.type_system.getPrimitiveType(.f64);
                if (std.mem.eql(u8, type_name, "bool")) return self.type_system.getPrimitiveType(.bool);
                if (std.mem.eql(u8, type_name, "string")) return self.type_system.getPrimitiveType(.string);
                if (std.mem.eql(u8, type_name, "void")) return self.type_system.getPrimitiveType(.void);
                return self.type_system.getPrimitiveType(.void);
            },
            .array_type => {
                // TODO: Resolve array element type and create array type
                return self.type_system.getPrimitiveType(.void);
            },
            .pointer_type => {
                // TODO: Resolve pointer base type and create pointer type
                return self.type_system.getPrimitiveType(.void);
            },
            else => return self.type_system.getPrimitiveType(.void),
        }
    }

    fn getNodeText(self: *TypeInference, node_id: NodeId) ![]const u8 {
        const node = self.getNode(node_id) orelse return error.NodeNotFound;
        const token = self.astdb.getToken(self.unit_id, node.first_token) orelse return error.TokenNotFound;
        if (token.str) |str_id| {
            return self.astdb.str_interner.get(str_id) orelse error.StringNotFound;
        }
        return "";
    }

    fn promoteArithmeticTypes(self: *TypeInference, type1: TypeId, type2: TypeId) !TypeId {
        // TODO: Implement arithmetic type promotion
        // For now, return i32 but use the parameters to avoid warnings
        return if (type1.eql(type2))
            type1
        else
            self.type_system.getPrimitiveType(.i32);
    }

    fn isInferenceVariable(self: *TypeInference, type_id: TypeId) bool {
        const info = self.type_system.getTypeInfo(type_id);
        return info.kind == .inference_var;
    }

    fn bindInferenceVariable(self: *TypeInference, var_type: TypeId, concrete_type: TypeId) !void {
        // Bind an inference variable to a concrete type
        const info = self.type_system.getTypeInfo(var_type);
        if (info.kind == .inference_var) {
            const id: InferenceId = @enumFromInt(info.kind.inference_var);
            try self.inference_vars.put(id, concrete_type);
        }
    }

    pub fn assignResolvedTypes(self: *TypeInference) !void {
        // Assign resolved types back to AST nodes
        // Iterate through all node types and resolve any inference variables
        var it = self.node_types.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.* = try self.resolveType(entry.value_ptr.*);
        }

        // Update symbol table with resolved types
        for (self.symbol_table.symbols.items) |*symbol| {
            if (symbol.type_id) |type_id| {
                const resolved = try self.resolveType(type_id);
                // Only update if changed and likely concrete
                if (!resolved.eql(type_id)) {
                    symbol.type_id = resolved;
                }
            }
        }
    }

    fn resolveType(self: *TypeInference, type_id: TypeId) !TypeId {
        // Recursively resolve inference variables
        if (self.isInferenceVariable(type_id)) {
            const info = self.type_system.getTypeInfo(type_id);
            const id: InferenceId = @enumFromInt(info.kind.inference_var);

            if (self.inference_vars.get(id)) |resolved| {
                // Check if we hit a void/unresolved chain end
                // Or if we found a concrete type (or another inference var)
                // If resolved is void, it means unresolved.
                if (resolved.eql(self.type_system.getPrimitiveType(.void))) {
                    return type_id;
                }

                // Recurse to resolve chains
                return self.resolveType(resolved);
            }
        }
        return type_id;
    }

    /// Infer type for match statement
    fn inferMatchStatement(self: *TypeInference, node_id: NodeId) !void {
        const children = self.astdb.getChildren(self.unit_id, node_id);
        if (children.len == 0) return;

        // 1. Infer expression type
        const expr_node = children[0];
        try self.generateConstraints(expr_node);
        const expr_type = self.getNodeType(expr_node);

        // 2. Collect patterns for exhaustiveness checking
        var patterns = try std.ArrayList(pattern_coverage.Pattern).initCapacity(self.allocator, 0);
        defer {
            for (patterns.items) |*pattern| {
                pattern.deinit(self.allocator);
            }
            patterns.deinit(self.allocator);
        }

        // 3. Iterate through children to find match arms
        var first_arm_type: ?TypeId = null;

        // Skip the first child (expression)
        for (children[1..]) |child_id| {
            const child_node = self.getNode(child_id) orelse continue;

            if (child_node.kind == .match_arm) {
                // Found a match arm
                const arm_children = self.astdb.getChildren(self.unit_id, child_id);
                if (arm_children.len < 3) continue; // Should have at least pattern, guard, body

                const pattern_node = arm_children[0];
                const guard_node = arm_children[1];
                const body_node = arm_children[arm_children.len - 1];

                // 2a. Extract pattern for exhaustiveness checking
                const pattern = try self.extractPattern(pattern_node);
                try patterns.append(self.allocator, pattern);

                // 2b. Infer pattern type
                // Pattern must match expression type
                try self.generateConstraints(pattern_node);
                const pattern_type = self.getNodeType(pattern_node);
                try self.addConstraint(.{ .equality = .{ .left = expr_type, .right = pattern_type } });

                // 2c. Infer guard type (if present)
                const guard_node_obj = self.getNode(guard_node);
                if (guard_node_obj != null and guard_node_obj.?.kind != .null_literal) {
                    try self.generateConstraints(guard_node);
                    const guard_type = self.getNodeType(guard_node);
                    try self.addConstraint(.{ .equality = .{ .left = guard_type, .right = self.type_system.getPrimitiveType(.bool) } });
                }

                // 2d. Infer body type
                try self.generateConstraints(body_node);
                const body_type = self.getNodeType(body_node);

                // 2e. Ensure all arm bodies have same type
                if (first_arm_type) |expected_type| {
                    try self.addConstraint(.{ .equality = .{ .left = expected_type, .right = body_type } });
                } else {
                    first_arm_type = body_type;
                }
            }
        }

        // 4. **THE ELM GUARANTEE: Exhaustiveness Checking**
        var coverage = pattern_coverage.PatternCoverage.init(self.allocator, self.type_system);
        defer coverage.deinit();

        var result = try coverage.checkExhaustiveness(expr_type, patterns.items);
        defer result.deinit(self.allocator);

        if (!result.is_exhaustive) {
            // **COMPILER AS EXECUTIONER: Non-exhaustive match is a COMPILE ERROR**
            try self.reportNonExhaustiveMatch(node_id, result.missing_patterns);
        }

        // 5. Set match statement type to arm body type
        if (first_arm_type) |result_type| {
            try self.setNodeType(node_id, result_type);
        } else {
            // Empty match? Should be void.
            try self.setNodeType(node_id, self.type_system.getPrimitiveType(.void));
        }
    }

    /// Extract pattern from AST node for exhaustiveness checking
    fn extractPattern(self: *TypeInference, pattern_node: NodeId) !pattern_coverage.Pattern {
        const node = self.getNode(pattern_node) orelse return error.InvalidPattern;

        switch (node.kind) {
            .identifier => {
                const token = self.astdb.getToken(self.unit_id, node.first_token) orelse return error.InvalidPattern;
                const name_bytes = if (token.str) |str_id| (self.astdb.str_interner.get(str_id) orelse "_") else "_";

                // Check if it's a wildcard
                if (std.mem.eql(u8, name_bytes, "_") or std.mem.eql(u8, name_bytes, "else")) {
                    return pattern_coverage.Pattern{ .wildcard = {} };
                }

                // Regular identifier (binds value, matches everything)
                const owned_name = try self.allocator.dupe(u8, name_bytes);
                return pattern_coverage.Pattern{ .identifier = owned_name };
            },
            .integer_literal => {
                // Extract integer value
                const token = self.astdb.getToken(self.unit_id, node.first_token) orelse return error.InvalidPattern;
                const value_bytes = if (token.str) |str_id| (self.astdb.str_interner.get(str_id) orelse "0") else "0";
                const value = std.fmt.parseInt(i64, value_bytes, 10) catch 0;
                return pattern_coverage.Pattern{ .literal = .{ .integer = value } };
            },
            .bool_literal => {
                // Extract boolean value
                const token = self.astdb.getToken(self.unit_id, node.first_token) orelse return error.InvalidPattern;
                const value_bytes = if (token.str) |str_id| (self.astdb.str_interner.get(str_id) orelse "false") else "false";
                const value = std.mem.eql(u8, value_bytes, "true");
                return pattern_coverage.Pattern{ .literal = .{ .bool = value } };
            },
            .string_literal => {
                // Extract string value
                const token = self.astdb.getToken(self.unit_id, node.first_token) orelse return error.InvalidPattern;
                const value_bytes = if (token.str) |str_id| (self.astdb.str_interner.get(str_id) orelse "") else "";
                const owned_value = try self.allocator.dupe(u8, value_bytes);
                return pattern_coverage.Pattern{ .literal = .{ .string = owned_value } };
            },
            // TODO: Add support for variant patterns (.Some, .None)
            // TODO: Add support for tuple patterns (x, y)
            // TODO: Add support for struct patterns { x, y }
            else => {
                // Unsupported pattern type - treat as wildcard for now
                std.log.warn("Unsupported pattern type: {s}, treating as wildcard", .{@tagName(node.kind)});
                return pattern_coverage.Pattern{ .wildcard = {} };
            },
        }
    }

    /// Report non-exhaustive match error
    fn reportNonExhaustiveMatch(
        self: *TypeInference,
        match_node: NodeId,
        missing_patterns: []const pattern_coverage.Pattern,
    ) !void {
        // Format missing patterns for error message
        var msg_buf = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer msg_buf.deinit(self.allocator);

        try msg_buf.appendSlice(self.allocator, "Match is not exhaustive. Missing patterns:\n");
        for (missing_patterns) |pattern| {
            try msg_buf.appendSlice(self.allocator, "  - ");
            try self.formatPattern(&msg_buf, pattern);
            try msg_buf.append(self.allocator, '\n');
        }
        try msg_buf.appendSlice(self.allocator, "\nHint: Add a wildcard `_` arm or handle all missing cases.");

        // Emit diagnostic
        // TODO: Integrate with proper diagnostic system
        std.log.err("Non-exhaustive match at node {}: {s}", .{ match_node, msg_buf.items });

        // For now, this is a compile error
        return error.NonExhaustiveMatch;
    }

    /// Format pattern for display in error messages
    fn formatPattern(self: *TypeInference, buf: *std.ArrayList(u8), pattern: pattern_coverage.Pattern) !void {
        switch (pattern) {
            .wildcard => try buf.appendSlice(self.allocator, "_"),
            .literal => |lit| {
                switch (lit) {
                    .bool => |b| try buf.appendSlice(self.allocator, if (b) "true" else "false"),
                    .integer => |i| {
                        var num_buf: [32]u8 = undefined;
                        const num_str = try std.fmt.bufPrint(&num_buf, "{}", .{i});
                        try buf.appendSlice(self.allocator, num_str);
                    },
                    .float => |f| {
                        var num_buf: [32]u8 = undefined;
                        const num_str = try std.fmt.bufPrint(&num_buf, "{d}", .{f});
                        try buf.appendSlice(self.allocator, num_str);
                    },
                    .string => |s| {
                        try buf.append(self.allocator, '"');
                        try buf.appendSlice(self.allocator, s);
                        try buf.append(self.allocator, '"');
                    },
                }
            },
            .identifier => |name| try buf.appendSlice(self.allocator, name),
            .variant => |name| {
                try buf.append(self.allocator, '.');
                try buf.appendSlice(self.allocator, name);
            },
            .tuple => |patterns| {
                try buf.append(self.allocator, '(');
                for (patterns, 0..) |p, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, ", ");
                    try self.formatPattern(buf, p);
                }
                try buf.append(self.allocator, ')');
            },
            .struct_pattern => |sp| {
                try buf.appendSlice(self.allocator, "{ ");
                for (sp.fields, 0..) |field, i| {
                    if (i > 0) try buf.appendSlice(self.allocator, ", ");
                    try buf.appendSlice(self.allocator, field.name);
                    try buf.appendSlice(self.allocator, ": ");
                    try self.formatPattern(buf, field.pattern);
                }
                try buf.appendSlice(self.allocator, " }");
            },
        }
    }

    /// Infer type for postfix when statement
    fn inferPostfixWhen(self: *TypeInference, node_id: NodeId) !void {
        const node = self.getNode(node_id) orelse return;
        const cond_id: NodeId = @enumFromInt(node.child_lo);
        const stmt_id: NodeId = @enumFromInt(node.child_hi);

        // 1. Infer condition type
        try self.generateConstraints(cond_id);
        const cond_type = self.getNodeType(cond_id);

        // 2. Enforce boolean condition
        try self.addConstraint(.{ .equality = .{ .left = cond_type, .right = self.type_system.getPrimitiveType(.bool) } });

        // 3. Infer statement type
        try self.generateConstraints(stmt_id);

        // 4. Result type is void (statements don't return values in this context)
        try self.setNodeType(node_id, self.type_system.getPrimitiveType(.void));
    }

    /// Get inference statistics
    pub fn getStatistics(self: *TypeInference) InferenceStats {
        return self.stats;
    }
};
