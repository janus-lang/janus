// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Type Checker - Semantic Analysis Phase 2
//!
//! This module implements type checking and validation for Janus.
//! It verifies that operations are performed on compatible types and
//! that function calls match their signatures.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const astdb = @import("astdb");
const symbol_table = @import("symbol_table.zig");
const SymbolTable = symbol_table.SymbolTable;
const SymbolId = symbol_table.SymbolId;
const NodeId = astdb.NodeId;
const UnitId = astdb.UnitId;
const SourceSpan = symbol_table.SourceSpan;
// PATCH: Import type_store
const type_store = @import("type_store.zig");

/// Type Checking Diagnostic
pub const TypeDiagnostic = struct {
    kind: DiagnosticKind,
    message: []const u8,
    span: SourceSpan,

    pub const DiagnosticKind = enum {
        type_mismatch, // E3001
        invalid_call, // E3002
        unknown_type, // E3003
    };
};

/// Type Checker Engine
pub const TypeChecker = struct {
    allocator: Allocator,
    astdb: *astdb.ASTDBSystem,
    symbol_table: *SymbolTable,
    type_system: *type_store.TypeSystem,
    diagnostics: ArrayList(TypeDiagnostic),
    current_unit: ?UnitId = null,

    pub fn init(allocator: Allocator, astdb_instance: *astdb.ASTDBSystem, symbol_table_instance: *SymbolTable, type_system_instance: *type_store.TypeSystem) !*TypeChecker {
        const checker = try allocator.create(TypeChecker);
        checker.* = TypeChecker{
            .allocator = allocator,
            .astdb = astdb_instance,
            .symbol_table = symbol_table_instance,
            .type_system = type_system_instance,
            .diagnostics = ArrayList(TypeDiagnostic).init(allocator),
        };
        return checker;
    }

    pub fn deinit(self: *TypeChecker) void {
        for (self.diagnostics.items) |diagnostic| {
            self.allocator.free(diagnostic.message);
        }
        self.diagnostics.deinit();
        self.allocator.destroy(self);
    }

    /// Check types in a compilation unit
    pub fn checkUnit(self: *TypeChecker, unit_id: UnitId) !void {
        self.current_unit = unit_id;
        const unit = self.astdb.getUnit(unit_id) orelse return;
        if (unit.nodes.len == 0) return;
        // Root node is typically the last node (module root)
        const root_node: NodeId = @enumFromInt(unit.nodes.len - 1);
        try self.checkNode(root_node);
    }

    /// Recursively check types for a node
    fn checkNode(self: *TypeChecker, node_id: NodeId) anyerror!void {
        const node = self.getNode(node_id);

        switch (node.kind) {
            .call_expr => try self.checkFunctionCall(node_id),
            .let_stmt, .var_stmt => try self.checkVariableDeclaration(node_id),
            else => {
                const children = self.getNodeChildren(node_id);
                for (children) |child_id| {
                    try self.checkNode(child_id);
                }
            },
        }
    }

    /// Check variable declaration for type mismatches
    fn checkVariableDeclaration(self: *TypeChecker, node_id: NodeId) anyerror!void {
        const children = self.getNodeChildren(node_id);
        if (children.len < 2) return; // No initializer

        // Get declared type (if present)
        const name_node = children[0];
        const name_text = try self.getNodeText(name_node);

        // Look up symbol to get declared type
        const symbol_id = self.symbol_table.lookup(name_text) orelse return;
        const symbol_idx = self.symbol_table.symbol_map.get(symbol_id) orelse return;
        const symbol = self.symbol_table.symbols.items[symbol_idx];

        const declared_type = symbol.type_id orelse return; // No type annotation

        // Get initializer expression (last child)
        const init_expr = children[children.len - 1];
        const init_type = try self.inferExpressionType(init_expr) orelse return;

        // Check type compatibility
        if (!self.typesCompatible(declared_type, init_type)) {
            const span = self.getNodeSpan(node_id);
            const declared_name = self.getTypeName(declared_type);
            const init_name = self.getTypeName(init_type);
            const message = try std.fmt.allocPrint(self.allocator, "Type mismatch: variable '{s}' declared as {s}, but initialized with {s}", .{ name_text, declared_name, init_name });
            try self.reportError(.type_mismatch, message, span);
        }

        // Recursively check children
        for (children) |child_id| {
            try self.checkNode(child_id);
        }
    }

    /// Check assignment statement for type mismatches
    fn checkAssignment(self: *TypeChecker, node_id: NodeId) !void {
        const children = self.getNodeChildren(node_id);
        if (children.len < 2) return;

        const lhs = children[0];
        const rhs = children[1];

        const lhs_type = try self.inferExpressionType(lhs) orelse return;
        const rhs_type = try self.inferExpressionType(rhs) orelse return;

        if (!self.typesCompatible(lhs_type, rhs_type)) {
            const span = self.getNodeSpan(node_id);
            const lhs_name = self.getTypeName(lhs_type);
            const rhs_name = self.getTypeName(rhs_type);
            const message = try std.fmt.allocPrint(self.allocator, "Type mismatch in assignment: cannot assign {s} to {s}", .{ rhs_name, lhs_name });
            try self.reportError(.type_mismatch, message, span);
        }

        // Recursively check children
        try self.checkNode(lhs);
        try self.checkNode(rhs);
    }

    /// Check function call expression
    fn checkFunctionCall(self: *TypeChecker, node_id: NodeId) anyerror!void {
        const children = self.getNodeChildren(node_id);
        if (children.len == 0) return;

        // First child is the function expression (usually identifier)
        const func_expr_id = children[0];
        const func_expr = self.getNode(func_expr_id);

        if (func_expr.kind == .identifier) {
            const func_name = try self.getNodeText(func_expr_id);
            if (self.symbol_table.lookup(func_name)) |symbol_id| {
                // Get the actual symbol
                const symbol_idx = self.symbol_table.symbol_map.get(symbol_id) orelse return;
                const symbol = self.symbol_table.symbols.items[symbol_idx];

                // Verify argument count
                // Arguments are children[1..]
                const args = children[1..];

                // Get function declaration node to check params
                const decl_node_id = symbol.declaration_node;
                const decl_children = self.getNodeChildren(decl_node_id);

                // Count parameters in declaration
                var param_count: usize = 0;
                // Skip name (first child)
                var decl_idx: usize = 1;
                while (decl_idx < decl_children.len) {
                    const child = self.getNode(decl_children[decl_idx]);
                    if (child.kind == .parameter) {
                        param_count += 1;
                        decl_idx += 1;
                    } else {
                        break;
                    }
                }

                if (args.len != param_count) {
                    const span = self.getNodeSpan(node_id);
                    const message = try std.fmt.allocPrint(self.allocator, "Function '{s}' expects {} arguments, but got {}", .{ func_name, param_count, args.len });
                    try self.reportError(.invalid_call, message, span);
                }

                // TODO: Check argument types against parameter types
            }
        }
    }

    /// Report type error
    fn reportError(self: *TypeChecker, kind: TypeDiagnostic.DiagnosticKind, message: []const u8, span: SourceSpan) !void {
        const diagnostic = TypeDiagnostic{
            .kind = kind,
            .message = message,
            .span = span,
        };
        try self.diagnostics.append(diagnostic);
    }

    /// Infer the type of an expression
    pub fn inferExpressionType(self: *TypeChecker, node_id: NodeId) anyerror!?type_store.TypeId {
        const node = self.getNode(node_id);
        const TypeSystem = type_store.TypeSystem;

        return switch (node.kind) {
            .integer_literal => TypeSystem.getPrimitiveType(self.type_system, .i64),
            .float_literal => TypeSystem.getPrimitiveType(self.type_system, .f64),
            .bool_literal => TypeSystem.getPrimitiveType(self.type_system, .bool),
            .string_literal => TypeSystem.getPrimitiveType(self.type_system, .string),
            .identifier => blk: {
                const name = try self.getNodeText(node_id);
                if (self.symbol_table.lookup(name)) |sym_id| {
                    if (self.symbol_table.symbol_map.get(sym_id)) |idx| {
                        break :blk self.symbol_table.symbols.items[idx].type_id;
                    }
                }
                break :blk null;
            },
            else => null,
        };
    }

    /// Check if two types are compatible
    fn typesCompatible(self: *TypeChecker, expected: type_store.TypeId, actual: type_store.TypeId) bool {
        _ = self;
        // Use TypeId.eql for comparison
        return expected.eql(actual);
    }

    /// Get human-readable type name
    pub fn getTypeName(self: *TypeChecker, type_id: type_store.TypeId) []const u8 {
        const info = self.type_system.getTypeInfo(type_id);
        return switch (info.kind) {
            .primitive => |p| @tagName(p),
            .structure => |s| s.name,
            .enumeration => |e| e.name,
            else => "(unknown)",
        };
    }

    // Helpers (duplicated from SymbolResolver for now, should be shared)

    fn getNode(self: *TypeChecker, node_id: NodeId) astdb.AstNode {
        const unit = self.astdb.getUnit(self.current_unit.?) orelse @panic("Unit not found");
        return unit.nodes[@intFromEnum(node_id)];
    }

    fn getNodeChildren(self: *TypeChecker, node_id: NodeId) []const NodeId {
        const unit = self.astdb.getUnit(self.current_unit.?) orelse return &.{};
        const node = unit.nodes[@intFromEnum(node_id)];
        if (node.child_lo >= node.child_hi) return &.{};
        return unit.edges[node.child_lo..node.child_hi];
    }

    fn getNodeText(self: *TypeChecker, node_id: NodeId) ![]const u8 {
        const unit = self.astdb.getUnit(self.current_unit.?) orelse return error.UnitNotFound;
        const node = unit.nodes[@intFromEnum(node_id)];
        const token = unit.tokens[@intFromEnum(node.first_token)];
        if (token.str) |str_id| {
            return self.astdb.str_interner.getString(str_id);
        }
        return "";
    }

    fn getNodeSpan(self: *TypeChecker, node_id: NodeId) SourceSpan {
        const unit = self.astdb.getUnit(self.current_unit.?) orelse return SourceSpan{ .start = 0, .end = 0, .line = 0, .column = 0 };
        const node = unit.nodes[@intFromEnum(node_id)];
        const start_token = unit.tokens[@intFromEnum(node.first_token)];
        const end_token = unit.tokens[@intFromEnum(node.last_token)];

        return SourceSpan{
            .start = start_token.span.start,
            .end = end_token.span.end,
            .line = start_token.span.line,
            .column = start_token.span.column,
        };
    }
};
