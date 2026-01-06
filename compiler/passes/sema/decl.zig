// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Symbol Resolver - Binding Identifiers to Declarations
//!
//! This module implements the multi-pass symbol resolver that walks the ASTDB
//! and binds every identifier to its unique declaration. It operates in phases:
//! 1. Declaration Collection - Register all declarations in symbol table
//! 2. Reference Resolution - Resolve all identifier references
//! 3. Validation - Check for undefined references and semantic errors
//!
//! The resolver enforces lexical scoping, visibility rules, and generates
//! precise diagnostics for undefined or inaccessible symbols.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const AutoHashMap = std.AutoHashMap;

const astdb = @import("astdb");
const symbol_table = @import("symbol_table.zig");
const SymbolTable = symbol_table.SymbolTable;
const SymbolId = symbol_table.SymbolId;
const ScopeId = symbol_table.ScopeId;
const StringId = symbol_table.StringId;
const NodeId = astdb.NodeId;
const UnitId = astdb.UnitId;
const SourceSpan = symbol_table.SourceSpan;
// PATCH: Import type_store instead of type_system
const type_system = @import("type_store.zig");
const TypeSystem = type_system.TypeSystem;
const TypeId = type_system.TypeId;

/// Semantic diagnostic for symbol resolution errors
pub const SemanticDiagnostic = struct {
    kind: DiagnosticKind,
    message: []const u8,
    span: SourceSpan,
    suggestions: [][]const u8,

    pub const DiagnosticKind = enum {
        undefined_symbol, // E2001
        duplicate_declaration, // E2006
        inaccessible_symbol, // E2007
        shadowed_declaration, // E2008 (warning)
    };
};

/// Symbol Resolution Engine
pub const SymbolResolver = struct {
    allocator: Allocator,
    astdb: *astdb.ASTDBSystem,
    symbol_table: *SymbolTable,
    type_system: *TypeSystem,
    node_to_symbol: AutoHashMap(NodeId, SymbolId),

    /// Collected diagnostics during resolution
    diagnostics: ArrayList(SemanticDiagnostic),

    /// Current compilation unit being processed
    current_unit: ?UnitId = null,

    /// Resolution statistics
    stats: ResolutionStats = .{},

    pub const ResolutionStats = struct {
        declarations_collected: u32 = 0,
        references_resolved: u32 = 0,
        undefined_references: u32 = 0,
        duplicate_declarations: u32 = 0,
    };

    pub fn init(allocator: Allocator, astdb_instance: *astdb.ASTDBSystem) !*SymbolResolver {
        const resolver = try allocator.create(SymbolResolver);
        const symbol_table_instance = try SymbolTable.init(allocator);
        const type_system_instance = try allocator.create(TypeSystem);
        type_system_instance.* = try TypeSystem.init(allocator);

        resolver.* = SymbolResolver{
            .allocator = allocator,
            .astdb = astdb_instance,
            .symbol_table = symbol_table_instance,
            .type_system = type_system_instance,
            .node_to_symbol = AutoHashMap(NodeId, SymbolId).init(allocator),
            .diagnostics = ArrayList(SemanticDiagnostic).init(allocator),
        };
        return resolver;
    }

    /// Resolve symbols for a node (called by ValidationEngine)
    pub fn resolveNode(self: *SymbolResolver, node_id: NodeId, table: *SymbolTable) !void {
        self.symbol_table = table;
        try self.walkDeclarations(node_id);
        try self.walkReferences(node_id);
    }

    pub fn deinit(self: *SymbolResolver) void {
        // Clean up diagnostics
        for (self.diagnostics.items) |diagnostic| {
            self.allocator.free(diagnostic.message);
            for (diagnostic.suggestions) |suggestion| {
                self.allocator.free(suggestion);
            }
            self.allocator.free(diagnostic.suggestions);
        }
        self.diagnostics.deinit();

        self.node_to_symbol.deinit();

        // Clean up symbol table
        self.symbol_table.deinit();

        // Clean up type system
        self.type_system.deinit();
        self.allocator.destroy(self.type_system);

        self.allocator.destroy(self);
    }

    /// Resolve symbols for a compilation unit
    pub fn resolveUnit(self: *SymbolResolver, unit_id: UnitId) !void {
        self.current_unit = unit_id;

        // Clear previous diagnostics for this unit
        self.clearDiagnostics();

        // Phase 1: Collect all declarations
        try self.collectDeclarations(unit_id);

        // Phase 2: Resolve all references
        try self.resolveReferences(unit_id);

        // Phase 3: Validate and generate diagnostics
        try self.validateResolution(unit_id);
    }

    /// Phase 1: Walk AST and collect all declarations
    fn collectDeclarations(self: *SymbolResolver, unit_id: UnitId) !void {
        _ = unit_id; // TODO: Use unit_id when getUnitRoot is implemented
        // TODO: Implement getUnitRoot in ASTDBSystem
        // For now, create a dummy root node to allow compilation
        const root_node = @as(NodeId, @enumFromInt(0));

        // Create module scope for this unit
        const module_scope = try self.symbol_table.createScope(self.symbol_table.global_scope, .module);
        try self.symbol_table.pushScope(module_scope);

        try self.walkDeclarations(root_node);

        _ = self.symbol_table.popScope();
    }

    /// Recursively walk AST nodes and collect declarations
    fn walkDeclarations(self: *SymbolResolver, node_id: NodeId) anyerror!void {
        const node = self.getNode(node_id);

        switch (node.kind) {
            .func_decl => try self.collectFunctionDeclaration(node_id),
            .struct_decl => try self.collectStructDeclaration(node_id),
            .enum_decl => try self.collectEnumDeclaration(node_id),
            .var_stmt, .let_stmt, .const_stmt => try self.collectVariableDeclaration(node_id),
            .parameter => try self.collectParameterDeclaration(node_id),

            // Scoped constructs - create new scopes and recurse
            // Note: Function body is handled within collectFunctionDeclaration
            .block_stmt => try self.walkScopedDeclarations(node_id, .block),

            else => {
                // Recurse into child nodes
                const children = self.getNodeChildren(node_id);
                for (children) |child_id| {
                    try self.walkDeclarations(child_id);
                }
            },
        }
    }

    /// Walk declarations within a new scope
    fn walkScopedDeclarations(self: *SymbolResolver, node_id: NodeId, scope_kind: SymbolTable.Scope.ScopeKind) !void {
        const current_scope = self.symbol_table.getCurrentScope() orelse return error.NoCurrentScope;
        const new_scope = try self.symbol_table.createScope(current_scope, scope_kind);

        try self.symbol_table.pushScope(new_scope);
        defer _ = self.symbol_table.popScope();

        const children = self.getNodeChildren(node_id);
        for (children) |child_id| {
            try self.walkDeclarations(child_id);
        }
    }

    /// Collect function declaration
    fn collectFunctionDeclaration(self: *SymbolResolver, node_id: NodeId) !void {
        const children = self.getNodeChildren(node_id);
        if (children.len == 0) return;

        var child_idx: usize = 0;

        // 1. Check for Name (first child if identifier)
        // Note: Parser ensures name is first if present
        if (child_idx < children.len) {
            const first_child = self.getNode(children[child_idx]);
            if (first_child.kind == .identifier) {
                const name_text = try self.getNodeText(children[child_idx]);
                const span = self.getNodeSpan(node_id);

                _ = self.symbol_table.declareSymbol(
                    try self.symbol_table.symbol_interner.intern(name_text),
                    .function,
                    node_id,
                    span,
                    .public,
                    null,
                ) catch |err| switch (err) {
                    error.DuplicateDeclaration => {
                        try self.reportDuplicateDeclaration(try self.symbol_table.symbol_interner.intern(name_text), span);
                        return;
                    },
                    else => return err,
                };

                self.stats.declarations_collected += 1;
                child_idx += 1;
            }
        }

        // Create function scope
        const func_scope = try self.symbol_table.createScope(self.symbol_table.getCurrentScope() orelse return error.NoCurrentScope, .function);
        try self.symbol_table.pushScope(func_scope);
        defer _ = self.symbol_table.popScope();

        // 2. Process Parameters
        while (child_idx < children.len) {
            const child_id = children[child_idx];
            const child = self.getNode(child_id);
            if (child.kind == .parameter) {
                try self.collectParameterDeclaration(child_id);
                child_idx += 1;
            } else {
                break; // End of parameters
            }
        }

        // 3. Process Body (remaining children)
        while (child_idx < children.len) {
            const child_id = children[child_idx];
            try self.walkDeclarations(child_id);
            child_idx += 1;
        }
    }

    /// Collect variable declaration
    fn collectVariableDeclaration(self: *SymbolResolver, node_id: NodeId) !void {
        const children = self.getNodeChildren(node_id);
        if (children.len == 0) return;

        // First child is identifier (name)
        const name_text = try self.getNodeText(children[0]);
        const span = self.getNodeSpan(node_id);

        const symbol_id = self.symbol_table.declareSymbol(
            try self.symbol_table.symbol_interner.intern(name_text),
            .variable,
            node_id,
            span,
            .private,
            try self.resolveDeclarationType(children),
        ) catch |err| switch (err) {
            error.DuplicateDeclaration => {
                try self.reportDuplicateDeclaration(try self.symbol_table.symbol_interner.intern(name_text), span);
                return;
            },
            else => return err,
        };

        try self.node_to_symbol.put(children[0], symbol_id);

        self.stats.declarations_collected += 1;

        // Second child (if present) is initializer expression
        if (children.len > 1) {
            try self.walkDeclarations(children[1]);
        }
    }

    /// Collect struct declaration
    fn collectStructDeclaration(self: *SymbolResolver, node_id: NodeId) !void {
        const children = self.getNodeChildren(node_id);
        if (children.len == 0) return;

        // First child is name
        const name_text = try self.getNodeText(children[0]);
        const span = self.getNodeSpan(node_id);

        _ = self.symbol_table.declareSymbol(
            try self.symbol_table.symbol_interner.intern(name_text),
            .struct_type,
            node_id,
            span,
            .public,
            null,
        ) catch |err| switch (err) {
            error.DuplicateDeclaration => {
                try self.reportDuplicateDeclaration(try self.symbol_table.symbol_interner.intern(name_text), span);
                return;
            },
            else => return err,
        };

        self.stats.declarations_collected += 1;

        // Create struct scope and process body (remaining children)
        const struct_scope = try self.symbol_table.createScope(self.symbol_table.getCurrentScope() orelse return error.NoCurrentScope, .struct_body);
        try self.symbol_table.pushScope(struct_scope);
        defer _ = self.symbol_table.popScope();

        for (children[1..]) |child_id| {
            try self.walkDeclarations(child_id);
        }
    }

    /// Collect enum declaration
    fn collectEnumDeclaration(self: *SymbolResolver, node_id: NodeId) !void {
        const children = self.getNodeChildren(node_id);
        if (children.len == 0) return;

        // First child is name
        const name_text = try self.getNodeText(children[0]);
        const span = self.getNodeSpan(node_id);

        _ = self.symbol_table.declareSymbol(
            try self.symbol_table.symbol_interner.intern(name_text),
            .enum_type,
            node_id,
            span,
            .public,
            null,
        ) catch |err| switch (err) {
            error.DuplicateDeclaration => {
                try self.reportDuplicateDeclaration(try self.symbol_table.symbol_interner.intern(name_text), span);
                return;
            },
            else => return err,
        };

        self.stats.declarations_collected += 1;

        // Create enum scope and process body (remaining children)
        const enum_scope = try self.symbol_table.createScope(self.symbol_table.getCurrentScope() orelse return error.NoCurrentScope, .enum_body);
        try self.symbol_table.pushScope(enum_scope);
        defer _ = self.symbol_table.popScope();

        for (children[1..]) |child_id| {
            try self.walkDeclarations(child_id);
        }
    }

    /// Collect parameter declaration
    fn collectParameterDeclaration(self: *SymbolResolver, node_id: NodeId) !void {
        // Parameter node corresponds to the identifier token.

        const name_text = try self.getNodeText(node_id);
        const span = self.getNodeSpan(node_id);

        _ = self.symbol_table.declareSymbol(
            try self.symbol_table.symbol_interner.intern(name_text),
            .parameter,
            node_id,
            span,
            .private,
            null, // Type info lost in parser
        ) catch |err| switch (err) {
            error.DuplicateDeclaration => {
                try self.reportDuplicateDeclaration(try self.symbol_table.symbol_interner.intern(name_text), span);
                return;
            },
            else => return err,
        };

        self.stats.declarations_collected += 1;
    }

    /// Helper to resolve type from declaration children
    /// Looks for a type node in the children list (usually index 1)
    pub fn resolveDeclarationType(self: *SymbolResolver, children: []const NodeId) !?TypeId {
        if (children.len < 2) return null;

        // Check second child for type
        const possible_type_node = children[1];
        const node = self.getNode(possible_type_node);

        if (self.isTypeNode(node.kind)) {
            return self.resolveType(possible_type_node);
        } else {
            // Try to infer type from expression (initializer)
            return self.inferType(possible_type_node);
        }
    }

    fn isTypeNode(self: *SymbolResolver, kind: astdb.AstNode.NodeKind) bool {
        _ = self;
        return switch (kind) {
            .primitive_type, .pointer_type, .array_type, .slice_type, .function_type, .named_type => true,
            else => false,
        };
    }

    fn resolveType(self: *SymbolResolver, node_id: NodeId) !?TypeId {
        const node = self.getNode(node_id);
        switch (node.kind) {
            .primitive_type => {
                const text = try self.getNodeText(node_id);
                if (std.mem.eql(u8, text, "i32")) return self.type_system.getPrimitiveType(.i32);
                if (std.mem.eql(u8, text, "i64")) return self.type_system.getPrimitiveType(.i64);
                if (std.mem.eql(u8, text, "f32")) return self.type_system.getPrimitiveType(.f32);
                if (std.mem.eql(u8, text, "f64")) return self.type_system.getPrimitiveType(.f64);
                if (std.mem.eql(u8, text, "bool")) return self.type_system.getPrimitiveType(.bool);
                if (std.mem.eql(u8, text, "string")) return self.type_system.getPrimitiveType(.string);
                if (std.mem.eql(u8, text, "void")) return self.type_system.getPrimitiveType(.void);
                return null;
            },
            .pointer_type => {
                // TODO: Recurse
                return null;
            },
            .named_type => {
                // TODO: Resolve type alias
                return null;
            },
            else => return null,
        }
    }

    fn inferType(self: *SymbolResolver, node_id: NodeId) !?TypeId {
        const node = self.getNode(node_id);
        return switch (node.kind) {
            .integer_literal => self.type_system.getPrimitiveType(.i64),
            .float_literal => self.type_system.getPrimitiveType(.f64),
            .bool_literal => self.type_system.getPrimitiveType(.bool),
            .string_literal => self.type_system.getPrimitiveType(.string),
            .identifier => blk: {
                const name = try self.getNodeText(node_id);
                if (self.symbol_table.lookup(name)) |sym_id| {
                    if (self.symbol_table.symbol_map.get(sym_id)) |idx| {
                        break :blk self.symbol_table.symbols.items[idx].type_id;
                    }
                }
                break :blk null;
            },
            .paren_expr => blk: {
                const children = self.getNodeChildren(node_id);
                if (children.len > 0) break :blk self.inferType(children[0]);
                break :blk null;
            },
            else => null,
        };
    }

    /// Phase 2: Resolve all identifier references
    fn resolveReferences(self: *SymbolResolver, unit_id: UnitId) !void {
        const unit = self.astdb.getUnit(unit_id) orelse return;
        const root_node: NodeId = if (unit.nodes.len > 0)
            @enumFromInt(unit.nodes.len - 1)
        else
            @enumFromInt(0);

        // Reset scope stack to module scope
        // This assumes collectDeclarations has already set up the module scope.
        // We need to ensure the scope stack is correctly managed between phases.
        // For now, re-creating and pushing the module scope.
        // A better approach might be to pass the initial scope or reset to a known state.
        const module_scope = try self.symbol_table.createScope(self.symbol_table.global_scope, .module);
        try self.symbol_table.pushScope(module_scope);

        try self.walkReferences(root_node);

        _ = self.symbol_table.popScope();
    }

    /// Recursively walk AST and resolve identifier references
    fn walkReferences(self: *SymbolResolver, node_id: NodeId) anyerror!void {
        const node = self.getNode(node_id);

        switch (node.kind) {
            .identifier => try self.resolveIdentifierReference(node_id),
            .field_expr => try self.resolveFieldExpression(node_id),
            .call_expr => try self.resolveCallExpression(node_id),

            // Scoped constructs - manage scope stack
            .func_decl => try self.walkScopedReferences(node_id, .function),
            .struct_decl => try self.walkScopedReferences(node_id, .struct_body),
            .enum_decl => try self.walkScopedReferences(node_id, .enum_body),
            .block_stmt => try self.walkScopedReferences(node_id, .block),

            else => {
                // Recurse into child nodes
                const children = self.getNodeChildren(node_id);
                for (children) |child_id| {
                    try self.walkReferences(child_id);
                }
            },
        }
    }

    /// Walk references within a scope
    fn walkScopedReferences(self: *SymbolResolver, node_id: NodeId, scope_kind: SymbolTable.Scope.ScopeKind) !void {
        const current_scope = self.symbol_table.getCurrentScope() orelse return error.NoCurrentScope;
        const new_scope = try self.symbol_table.createScope(current_scope, scope_kind);

        try self.symbol_table.pushScope(new_scope);
        defer _ = self.symbol_table.popScope();

        const children = self.getNodeChildren(node_id);
        for (children) |child_id| {
            try self.walkReferences(child_id);
        }
    }

    /// Resolve identifier reference to symbol
    fn resolveIdentifierReference(self: *SymbolResolver, node_id: NodeId) !void {
        const name_text = try self.getNodeText(node_id);

        if (self.symbol_table.lookup(name_text)) |symbol| {
            // Successfully resolved
            self.stats.references_resolved += 1;
            try self.node_to_symbol.put(node_id, symbol);
        } else {
            // Unresolved reference - report error
            const span = self.getNodeSpan(node_id);
            try self.reportUndefinedSymbol(name_text, span);
            self.stats.undefined_references += 1;
        }
    }

    /// Resolve field expression (obj.field or obj.method)
    fn resolveFieldExpression(self: *SymbolResolver, node_id: NodeId) !void {
        const children = self.getNodeChildren(node_id);
        if (children.len < 2) return;

        // First child is the object expression
        const obj_expr = children[0];
        try self.walkReferences(obj_expr);

        // Second child is the field/method identifier
        const field_id = children[1];
        const field_name = try self.getNodeText(field_id);

        // Try to infer type of the object
        const obj_type = try self.inferType(obj_expr);

        if (obj_type) |type_id| {
            // First, try to resolve as a struct field
            const type_info = self.type_system.getTypeInfo(type_id);
            if (type_info.kind == .structure) {
                // TODO: Check if field exists in struct
                // For now, just mark as resolved if we have type info
                try self.node_to_symbol.put(field_id, @enumFromInt(0)); // Placeholder
                self.stats.references_resolved += 1;
                return;
            }

            // UFCS Fallback: Look for function where first param matches obj_type
            if (try self.findUFCSFunction(field_name, type_id)) |func_symbol| {
                try self.node_to_symbol.put(field_id, func_symbol);
                self.stats.references_resolved += 1;
                return;
            }
        }

        // Fallback: Just try to resolve the field name as identifier
        if (self.symbol_table.lookup(field_name)) |symbol| {
            try self.node_to_symbol.put(field_id, symbol);
            self.stats.references_resolved += 1;
        } else {
            const span = self.getNodeSpan(field_id);
            try self.reportUndefinedSymbol(field_name, span);
            self.stats.undefined_references += 1;
        }
    }

    /// Resolve call expression (handles both regular and UFCS calls)
    fn resolveCallExpression(self: *SymbolResolver, node_id: NodeId) !void {
        const children = self.getNodeChildren(node_id);
        if (children.len == 0) return;

        // First child is the callee (function expression)
        const callee = children[0];
        const callee_node = self.getNode(callee);

        // If callee is a field_expr, it might be UFCS
        if (callee_node.kind == .field_expr) {
            try self.resolveFieldExpression(callee);
        } else {
            try self.walkReferences(callee);
        }

        // Resolve all arguments
        for (children[1..]) |arg_id| {
            try self.walkReferences(arg_id);
        }
    }

    /// Find UFCS function: search for func(self: Type, ...) that matches
    fn findUFCSFunction(self: *SymbolResolver, func_name: []const u8, self_type: TypeId) !?SymbolId {
        // Look up function by name
        const func_name_id = self.symbol_table.symbol_interner.intern(func_name) catch return null;
        const func_symbol_id = self.symbol_table.resolveIdentifier(func_name_id, null) orelse return null;

        // Get the symbol
        const symbol_idx = self.symbol_table.symbol_map.get(func_symbol_id) orelse return null;
        const symbol = self.symbol_table.symbols.items[symbol_idx];

        // Verify it's a function
        if (symbol.kind != .function) return null;

        // TODO: Check function signature - first parameter type should match self_type
        // For now, we accept any function with matching name
        _ = self_type;

        return func_symbol_id;
    }

    /// Phase 3: Validate resolution and generate final diagnostics
    fn validateResolution(self: *SymbolResolver, _: UnitId) !void {
        _ = self;

        // Additional validation passes can be added here:
        // - Check for unused symbols
        // - Validate visibility rules
        // - Check for shadowing warnings
        // - Profile boundary validation
    }

    /// Get source span for AST node
    fn getNodeSpan(self: *SymbolResolver, node_id: NodeId) SourceSpan {
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

    /// Helper to get node from ASTDB
    fn getNode(self: *SymbolResolver, node_id: NodeId) astdb.AstNode {
        const unit = self.astdb.getUnit(self.current_unit.?) orelse @panic("Unit not found");
        return unit.nodes[@intFromEnum(node_id)];
    }

    /// Helper to get node children
    fn getNodeChildren(self: *SymbolResolver, node_id: NodeId) []const NodeId {
        const unit = self.astdb.getUnit(self.current_unit.?) orelse return &.{};
        const node = unit.nodes[@intFromEnum(node_id)];
        if (node.child_lo >= node.child_hi) return &.{};
        return unit.edges[node.child_lo..node.child_hi];
    }

    /// Helper to get node text (for identifiers)
    fn getNodeText(self: *SymbolResolver, node_id: NodeId) ![]const u8 {
        const unit = self.astdb.getUnit(self.current_unit.?) orelse return error.UnitNotFound;
        const node = unit.nodes[@intFromEnum(node_id)];
        const token = unit.tokens[@intFromEnum(node.first_token)];
        if (token.str) |str_id| {
            return self.astdb.str_interner.getString(str_id);
        }
        return "";
    }

    /// Report duplicate declaration error
    fn reportDuplicateDeclaration(self: *SymbolResolver, name: StringId, span: SourceSpan) !void {
        const name_str = self.symbol_table.symbol_interner.getString(name);
        const message = try std.fmt.allocPrint(self.allocator, "Duplicate declaration of '{s}'", .{name_str});

        const diagnostic = SemanticDiagnostic{
            .kind = .duplicate_declaration,
            .message = message,
            .span = span,
            .suggestions = &.{},
        };

        try self.diagnostics.append(diagnostic);
        self.stats.duplicate_declarations += 1;
    }

    /// Report undefined symbol error
    fn reportUndefinedSymbol(self: *SymbolResolver, name: []const u8, span: SourceSpan) !void {
        const message = try std.fmt.allocPrint(self.allocator, "Undefined symbol '{s}'", .{name});

        const diagnostic = SemanticDiagnostic{
            .kind = .undefined_symbol,
            .message = message,
            .span = span,
            .suggestions = &.{},
        };

        try self.diagnostics.append(diagnostic);
    }

    /// Clear diagnostics for new resolution
    fn clearDiagnostics(self: *SymbolResolver) void {
        for (self.diagnostics.items) |diagnostic| {
            self.allocator.free(diagnostic.message);
            for (diagnostic.suggestions) |suggestion| {
                self.allocator.free(suggestion);
            }
            self.allocator.free(diagnostic.suggestions);
        }
        self.diagnostics.clearRetainingCapacity();
    }

    /// Get collected diagnostics
    pub fn getDiagnostics(self: *SymbolResolver) []const SemanticDiagnostic {
        return self.diagnostics.items;
    }

    /// Get resolution statistics
    pub fn getStatistics(self: *SymbolResolver) ResolutionStats {
        return self.stats;
    }
};
