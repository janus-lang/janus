// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Parser = @import("janus_parser.zig");
const astdb = @import("libjanus_astdb");
const astdb_core = @import("astdb_core");

// Revolutionary semantic analysis with ASTDB integration and standard library resolution.
// Performs name resolution, type checking, and capability inference using the AST-as-Database architecture.

// Type system with standard library integration
pub const Type = union(enum) {
    // Scalars
    Void,
    Bool,
    Int,
    Float,
    String,
    // Aggregates
    Array: *const Type, // []T
    Struct: u64, // canonical id or hash of name (avoid slices in union for hashability)
    Optional: *const Type, // T?
    Function, // simplified function type
    // Capabilities / effects placeholders
    IoError,
    StdoutWriteCapability,
    StderrWriteCapability,
    // Unknown
    Unknown,

    pub fn toString(self: Type) []const u8 {
        return switch (self) {
            .Void => "void",
            .Bool => "bool",
            .Int => "i32",
            .Float => "f64",
            .String => "string",
            .Array => "[]",
            .Struct => "struct",
            .Optional => "optional",
            .Function => "function",
            .IoError => "IoError",
            .StdoutWriteCapability => "StdoutWriteCapability",
            .StderrWriteCapability => "StderrWriteCapability",
            .Unknown => "unknown",
        };
    }
};

// Symbol table entry with capability tracking
pub const Symbol = struct {
    name: []const u8,
    type: Type,
    kind: SymbolKind,
    module_path: ?[]const u8, // e.g., "std.io" for standard library functions
    required_capabilities: []const Type, // Capabilities required to call this function

    pub const SymbolKind = enum {
        Function,
        Builtin,
        StdLibFunction, // Standard library function requiring capabilities
        CapabilityType, // Capability type definition
    };
};

// Revolutionary semantic graph with ASTDB integration and capability tracking
pub const SemanticGraph = struct {
    symbols: std.ArrayList(Symbol),
    required_capabilities: std.ArrayList(Type), // Capabilities needed by this compilation unit
    astdb_system: *astdb.ASTDBSystem, // Reference to the ASTDB system
    snapshot: astdb.Snapshot, // Current ASTDB snapshot
    allocator: std.mem.Allocator,
    /// Normalized call arguments: maps call_expr node id -> positional args (NodeId slice)
    call_args: std.HashMap(
        astdb_core.NodeId,
        []astdb_core.NodeId,
        std.hash_map.AutoContext(astdb_core.NodeId),
        std.hash_map.default_max_load_percentage,
    ),
    /// Registry of function parameters: func_decl node id surrogate -> parameter node ids
    func_params: std.HashMap(
        astdb_core.NodeId,
        []astdb_core.NodeId,
        std.hash_map.AutoContext(astdb_core.NodeId),
        std.hash_map.default_max_load_percentage,
    ),
    /// Registry of function parameter names (interned): func_decl surrogate -> [StrId]
    func_param_names: std.HashMap(
        astdb_core.NodeId,
        []astdb.StrId,
        std.hash_map.AutoContext(astdb_core.NodeId),
        std.hash_map.default_max_load_percentage,
    ),
    /// Registry of struct fields (names): struct_decl node id surrogate -> field name node ids
    struct_fields: std.HashMap(
        astdb_core.NodeId,
        []astdb_core.NodeId,
        std.hash_map.AutoContext(astdb_core.NodeId),
        std.hash_map.default_max_load_percentage,
    ),
    /// Map function name (StrId) -> func_decl surrogate node id
    func_by_name: std.HashMap(
        astdb.StrId,
        astdb_core.NodeId,
        std.hash_map.AutoContext(astdb.StrId),
        std.hash_map.default_max_load_percentage,
    ),
    /// Map struct name (StrId) -> struct_decl surrogate node id
    struct_by_name: std.HashMap(
        astdb.StrId,
        astdb_core.NodeId,
        std.hash_map.AutoContext(astdb.StrId),
        std.hash_map.default_max_load_percentage,
    ),
    /// Inferred types per node id
    type_of: std.HashMap(
        astdb_core.NodeId,
        Type,
        std.hash_map.AutoContext(astdb_core.NodeId),
        std.hash_map.default_max_load_percentage,
    ),
    /// Struct field type registry keyed by (struct_name, field_name)
    struct_field_types: std.HashMap(
        FieldKey,
        Type,
        std.hash_map.AutoContext(FieldKey),
        std.hash_map.default_max_load_percentage,
    ),
    /// Tracked variable types by name (StrId)
    var_types: std.HashMap(
        astdb.StrId,
        Type,
        std.hash_map.AutoContext(astdb.StrId),
        std.hash_map.default_max_load_percentage,
    ),

    pub fn init(allocator: std.mem.Allocator, astdb_system: *astdb.ASTDBSystem) !SemanticGraph {
        const snapshot = try astdb_system.createSnapshot();
        return SemanticGraph{
            .symbols = .empty,
            .required_capabilities = .empty,
            .astdb_system = astdb_system,
            .snapshot = snapshot,
            .allocator = allocator,
            .call_args = std.HashMap(
                astdb_core.NodeId,
                []astdb_core.NodeId,
                std.hash_map.AutoContext(astdb_core.NodeId),
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
            .func_params = std.HashMap(
                astdb_core.NodeId,
                []astdb_core.NodeId,
                std.hash_map.AutoContext(astdb_core.NodeId),
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
            .func_param_names = std.HashMap(
                astdb_core.NodeId,
                []astdb.StrId,
                std.hash_map.AutoContext(astdb_core.NodeId),
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
            .struct_fields = std.HashMap(
                astdb_core.NodeId,
                []astdb_core.NodeId,
                std.hash_map.AutoContext(astdb_core.NodeId),
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
            .func_by_name = std.HashMap(
                astdb.StrId,
                astdb_core.NodeId,
                std.hash_map.AutoContext(astdb.StrId),
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
            .struct_by_name = std.HashMap(
                astdb.StrId,
                astdb_core.NodeId,
                std.hash_map.AutoContext(astdb.StrId),
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
            .type_of = std.HashMap(
                astdb_core.NodeId,
                Type,
                std.hash_map.AutoContext(astdb_core.NodeId),
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
            .struct_field_types = std.HashMap(
                FieldKey,
                Type,
                std.hash_map.AutoContext(FieldKey),
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
            .var_types = std.HashMap(
                astdb.StrId,
                Type,
                std.hash_map.AutoContext(astdb.StrId),
                std.hash_map.default_max_load_percentage,
            ).init(allocator),
        };
    }

    pub fn deinit(self: *SemanticGraph) void {
        // Free normalized arg slices
        var it = self.call_args.valueIterator();
        while (it.next()) |slice_ptr| {
            self.allocator.free(slice_ptr.*);
        }
        self.call_args.deinit();
        var it2 = self.func_params.valueIterator();
        while (it2.next()) |slice_ptr| self.allocator.free(slice_ptr.*);
        self.func_params.deinit();
        var it2n = self.func_param_names.valueIterator();
        while (it2n.next()) |slice_ptr| self.allocator.free(slice_ptr.*);
        self.func_param_names.deinit();
        var it3 = self.struct_fields.valueIterator();
        while (it3.next()) |slice_ptr| self.allocator.free(slice_ptr.*);
        self.struct_fields.deinit();
        self.func_by_name.deinit();
        self.struct_by_name.deinit();
        self.type_of.deinit();
        self.struct_field_types.deinit();
        self.var_types.deinit();
        self.symbols.deinit();
        self.required_capabilities.deinit();
        self.snapshot.deinit();
    }

    const FieldKey = struct { struct_name: astdb.StrId, field_name: astdb.StrId };

    pub fn addSymbol(self: *SemanticGraph, symbol: Symbol) !void {
        try self.symbols.append(symbol);
    }

    pub fn findSymbol(self: *SemanticGraph, name: []const u8) ?*Symbol {
        for (self.symbols.items) |*symbol| {
            if (std.mem.eql(u8, symbol.name, name)) {
                return symbol;
            }
        }
        return null;
    }

    pub fn requireCapability(self: *SemanticGraph, capability_type: Type) !void {
        // Append blindly for now; deduplication is optional with union(enum)
        try self.required_capabilities.append(capability_type);
    }

    pub fn getRequiredCapabilities(self: *const SemanticGraph) []const Type {
        return self.required_capabilities.items;
    }

    /// Get normalized positional arguments for a call_expr node id, if available
    pub fn getCallArgs(self: *SemanticGraph, node_id: astdb_core.NodeId) ?[]astdb_core.NodeId {
        return self.call_args.get(node_id);
    }

    // ASTDB integration methods
    pub fn addNodeToASTDB(self: *SemanticGraph, kind: astdb.NodeKind, token_id: astdb.TokenId, children: []const astdb.NodeId) !astdb.NodeId {
        return self.snapshot.addNode(kind, token_id, token_id, children);
    }

    pub fn addTokenToASTDB(self: *SemanticGraph, kind: astdb.TokenKind, str_id: astdb.StrId, span: astdb.Span) !astdb.TokenId {
        return self.snapshot.addToken(kind, str_id, span);
    }

    pub fn internString(self: *SemanticGraph, str: []const u8) !astdb.StrId {
        return self.astdb_system.str_interner.get(str);
    }

    pub fn computeCID(self: *SemanticGraph, unit_id: astdb.UnitId, node_id: astdb.NodeId) !?[32]u8 {
        return self.astdb_system.getCID(unit_id, node_id);
    }
};

// Revolutionary semantic analyzer with ASTDB integration
const Analyzer = struct {
    graph: *SemanticGraph,
    errors: std.ArrayList(SemanticError),
    allocator: std.mem.Allocator,

    const SemanticError = struct {
        message: []const u8,
        node_id: ?astdb.NodeId, // ASTDB node reference instead of old AST
        cid: ?[32]u8, // Content ID for precise error location
    };

    pub fn init(graph: *SemanticGraph, allocator: std.mem.Allocator) Analyzer {
        return Analyzer{
            .graph = graph,
            .errors = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Analyzer) void {
        self.errors.deinit();
    }

    fn addError(self: *Analyzer, message: []const u8, node_id: ?astdb.NodeId) !void {
        // For now, skip CID computation to simplify integration
        try self.errors.append(SemanticError{
            .message = message,
            .node_id = node_id,
            .cid = null,
        });
    }

    fn analyzeNode(self: *Analyzer, node: *Parser.Node) anyerror!Type {
        // This is a legacy compatibility method
        // For now, just return a placeholder type
        _ = node;
        _ = self;
        return Type.Unknown;
    }

    // Legacy compatibility methods - simplified for new ASTDB integration
    fn analyzeRoot(self: *Analyzer, node: *Parser.Node) anyerror!Type {
        _ = node;
        _ = self;
        return Type.Void;
    }

    fn analyzeFunction(self: *Analyzer, node: *Parser.Node) anyerror!Type {
        _ = node;
        _ = self;
        return Type.Function;
    }

    fn analyzeCall(self: *Analyzer, node: *Parser.Node) anyerror!Type {
        _ = node;
        _ = self;
        return Type.Unknown;
    }

    fn analyzeIdentifier(self: *Analyzer, node: *Parser.Node) anyerror!Type {
        _ = node;
        _ = self;
        return Type.Unknown;
    }
};

// Revolutionary analysis entry point with ASTDB and standard library integration
pub fn analyzeWithASTDB(astdb_system: *astdb.ASTDBSystem, allocator: std.mem.Allocator) !SemanticGraph {
    var graph = try SemanticGraph.init(allocator, astdb_system);
    errdefer graph.deinit();

    // Register standard library symbols
    try registerStandardLibrary(&graph, allocator);

    // Perform semantic analysis on ASTDB units
    try collectSymbolTables(&graph, allocator);
    try analyzeASTDBUnits(&graph, allocator);

    return graph;
}

// Analyze all compilation units in the ASTDB system
fn analyzeASTDBUnits(graph: *SemanticGraph, allocator: std.mem.Allocator) !void {
    var analyzer = Analyzer.init(graph, allocator);
    defer analyzer.deinit();

    // Iterate through all compilation units in ASTDB
    for (graph.astdb_system.units.items) |unit| {
        try analyzeCompilationUnit(&analyzer, unit);
    }

    // Check for semantic errors
    if (analyzer.errors.items.len > 0) {
        // For now, just return the first error
        return error.SemanticError;
    }
}

// Analyze a single compilation unit from ASTDB
fn analyzeCompilationUnit(analyzer: *Analyzer, unit: *astdb_core.CompilationUnit) !void {
    // Analyze all nodes in the compilation unit with their node ids
    var idx: usize = 0;
    while (idx < unit.nodes.len) : (idx += 1) {
        const node = unit.nodes[idx];
        const node_id: astdb_core.NodeId = @enumFromInt(idx);
        try analyzeASTDBNode(analyzer, node_id, node, unit);
    }
}

/// First pass: collect function parameters and struct field names
fn collectSymbolTables(graph: *SemanticGraph, allocator: std.mem.Allocator) !void {
    _ = allocator;
    for (graph.astdb_system.units.items) |unit| {
        // Walk all nodes to find func_decl and struct_decl
        var idx: usize = 0;
        while (idx < unit.nodes.len) : (idx += 1) {
            const n = unit.nodes[idx];
            const children = unit.edges[n.child_lo..n.child_hi];
            const surrogate: astdb_core.NodeId = @enumFromInt(n.child_lo);
            switch (n.kind) {
                .func_decl => {
                    var params: std.ArrayList(astdb_core.NodeId) = .empty;
                    defer params.deinit();
                    var param_names: std.ArrayList(astdb.StrId) = .empty;
                    defer param_names.deinit();
                    var func_name_sid: ?astdb.StrId = null;
                    for (children) |cid| {
                        const cnode = unit.nodes[@intFromEnum(cid)];
                        if (cnode.kind == .identifier and func_name_sid == null) {
                            func_name_sid = getIdentifierStrId(unit, cnode);
                        } else if (cnode.kind == .parameter) {
                            try params.append(cid);
                            if (getIdentifierStrId(unit, cnode)) |sid| {
                                try param_names.append(sid);
                            }
                        }
                    }
                    if (params.items.len > 0) {
                        const owned = try graph.allocator.dupe(astdb_core.NodeId, params.items);
                        _ = try graph.func_params.put(surrogate, owned);
                        const owned_names = try graph.allocator.dupe(astdb.StrId, param_names.items);
                        _ = try graph.func_param_names.put(surrogate, owned_names);
                    }
                    if (func_name_sid) |sid| {
                        _ = try graph.func_by_name.put(sid, surrogate);
                    }
                },
                .struct_decl => {
                    var fields: std.ArrayList(astdb_core.NodeId) = .empty;
                    defer fields.deinit();
                    // First identifier child is struct name; subsequent identifiers are fields
                    var saw_name = false;
                    var struct_name_sid: ?astdb.StrId = null;
                    var i: usize = 0;
                    while (i < children.len) : (i += 1) {
                        const cid = children[i];
                        const cnode = unit.nodes[@intFromEnum(cid)];
                        if (cnode.kind == .identifier) {
                            if (!saw_name) {
                                saw_name = true;
                                struct_name_sid = getIdentifierStrId(unit, cnode);
                            } else {
                                try fields.append(cid);
                                // Attempt to read a following type node for this field
                                if (i + 1 < children.len) {
                                    const tid = children[i + 1];
                                    const tnode = unit.nodes[@intFromEnum(tid)];
                                    if (tnode.kind == .primitive_type or tnode.kind == .array_type) {
                                        if (struct_name_sid) |ss| {
                                            if (getIdentifierStrId(unit, cnode)) |fname| {
                                                if (resolveTypeFromNode(graph, unit, tnode)) |fty| {
                                                    _ = try graph.struct_field_types.put(SemanticGraph.FieldKey{ .struct_name = ss, .field_name = fname }, fty);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if (fields.items.len > 0) {
                        const owned = try graph.allocator.dupe(astdb_core.NodeId, fields.items);
                        _ = try graph.struct_fields.put(surrogate, owned);
                    }
                    if (struct_name_sid) |sid| {
                        _ = try graph.struct_by_name.put(sid, surrogate);
                    }
                },
                else => {},
            }
        }
    }
}

// Analyze an ASTDB node
fn analyzeASTDBNode(analyzer: *Analyzer, node_id: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    switch (node.kind) {
        .func_decl => try analyzeFunctionDecl(analyzer, node_id, node, unit),
        .call_expr => try analyzeCallExpr(analyzer, node_id, node, unit),
        .identifier => try analyzeIdentifierNode(analyzer, node_id, node, unit),
        .let_stmt => try analyzeLetStmt(analyzer, node_id, node, unit),
        .var_stmt => try analyzeVarStmt(analyzer, node_id, node, unit),
        .string_literal => {
            _ = try setType(analyzer, node_id, Type{ .String = {} });
        },
        .integer_literal => {
            _ = try setType(analyzer, node_id, Type{ .Int = {} });
        },
        .float_literal => {
            _ = try setType(analyzer, node_id, Type{ .Float = {} });
        },
        .bool_literal => {
            _ = try setType(analyzer, node_id, Type{ .Bool = {} });
        },
        .for_stmt => try analyzeForStmt(analyzer, node_id, node, unit),
        .field_expr => try analyzeFieldExpr(analyzer, node_id, node, unit),
        .index_expr => try analyzeIndexExpr(analyzer, node_id, node, unit),
        .struct_literal => try analyzeStructLiteral(analyzer, node_id, node, unit),
        .binary_expr => try analyzeBinaryExpr(analyzer, node_id, node, unit),
        else => {}, // Skip other node types for now
    }
}

// Analyze function declaration from ASTDB
fn analyzeFunctionDecl(analyzer: *Analyzer, node_id: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    // Get function name from tokens
    const func_name = getFunctionName(node, unit) orelse "unknown";

    // Register function in symbol table
    const func_symbol = Symbol{
        .name = func_name,
        .type = Type.Function,
        .kind = .Function,
        .module_path = null,
        .required_capabilities = &[_]Type{},
    };
    try analyzer.graph.addSymbol(func_symbol);
    _ = node_id; // will be used to map param names later
}

// Analyze call expression from ASTDB
fn analyzeCallExpr(analyzer: *Analyzer, node_id: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    const callee_name = getCalleeNameFromNode(node, unit) orelse "unknown";

    // Normalize named arguments into positional order and store in graph
    try normalizeAndStoreCallArgs(analyzer, node_id, node, unit);

    // Capability inference for known stdlib calls
    if (std.mem.eql(u8, callee_name, "print")) {
        try analyzer.graph.requireCapability(Type.StdoutWriteCapability);
    } else if (std.mem.eql(u8, callee_name, "eprint")) {
        try analyzer.graph.requireCapability(Type.StderrWriteCapability);
    } else {
        // Tolerate unknown functions during initial :min bring-up.
    }
}

// Analyze identifier node from ASTDB
fn analyzeIdentifierNode(analyzer: *Analyzer, node_id: astdb_core.NodeId, id_node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    // Bind identifier type from var_types if available
    const sid = getIdentifierStrId(unit, id_node) orelse return;
    if (analyzer.graph.var_types.get(sid)) |ty| {
        _ = try setType(analyzer, node_id, ty);
    }
}

fn setType(analyzer: *Analyzer, node_id: astdb_core.NodeId, ty: Type) !void {
    _ = try analyzer.graph.type_of.put(node_id, ty);
}

fn getType(analyzer: *Analyzer, node_id: astdb_core.NodeId) ?Type {
    return analyzer.graph.type_of.get(node_id);
}

fn analyzeStructLiteral(analyzer: *Analyzer, node_id: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    const children = unit.edges[node.child_lo..node.child_hi];
    if (children.len == 0) return; // malformed
    const type_ident_id = children[0];
    const type_ident = unit.nodes[@intFromEnum(type_ident_id)];
    if (type_ident.kind != .identifier) return;
    if (getIdentifierStrId(unit, type_ident)) |sid| {
        const name_id: u64 = @intCast(@intFromEnum(sid));
        // Optionally validate fields using struct_fields registry
        _ = try setType(analyzer, node_id, Type{ .Struct = name_id });
    }
}

fn analyzeFieldExpr(analyzer: *Analyzer, node_id: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    const children = unit.edges[node.child_lo..node.child_hi];
    if (children.len < 2) return;
    const lhs_id = children[0];
    var lhs_ty = getType(analyzer, lhs_id) orelse Type{ .Unknown = {} };
    switch (lhs_ty) {
        .Unknown => {
            const lhs_node = unit.nodes[@intFromEnum(lhs_id)];
            if (lhs_node.kind == .identifier) {
                if (getIdentifierStrId(unit, lhs_node)) |sid| {
                    if (analyzer.graph.var_types.get(sid)) |vty| {
                        lhs_ty = vty;
                    }
                }
            }
        },
        else => {},
    }
    // Detect optional chaining operator '?.'
    var force_optional = false;
    const op_tok_idx = @intFromEnum(node.first_token);
    if (op_tok_idx < unit.tokens.len) {
        const op_tok = unit.tokens[op_tok_idx];
        if (op_tok.kind == .optional_chain) force_optional = true;
    }
    const field_id = children[1];
    const field_node = unit.nodes[@intFromEnum(field_id)];
    if (field_node.kind != .identifier) {
        _ = try setType(analyzer, node_id, Type{ .Unknown = {} });
        return;
    }
    const f_sid = getIdentifierStrId(unit, field_node) orelse return;
    var base = lhs_ty;
    var wrap_optional = false;
    switch (lhs_ty) {
        .Optional => |inner| {
            base = inner.*;
            wrap_optional = true;
        },
        else => {},
    }
    var out_ty: Type = Type{ .Unknown = {} };
    switch (base) {
        .Struct => |name_id| {
            const s_sid: astdb.StrId = @enumFromInt(@as(u32, @intCast(name_id)));
            const key = SemanticGraph.FieldKey{ .struct_name = s_sid, .field_name = f_sid };
            if (analyzer.graph.struct_field_types.get(key)) |fty| {
                out_ty = fty;
            }
        },
        else => {},
    }
    if (wrap_optional or force_optional) {
        const boxed = try analyzer.allocator.create(Type);
        boxed.* = out_ty;
        _ = try setType(analyzer, node_id, Type{ .Optional = boxed });
    } else {
        _ = try setType(analyzer, node_id, out_ty);
    }
}

fn analyzeLetStmt(analyzer: *Analyzer, _: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    const children = unit.edges[node.child_lo..node.child_hi];
    if (children.len == 0) return;
    // Expect identifier first, possibly type node, then expression
    const id_node = unit.nodes[@intFromEnum(children[0])];
    const name_sid = getIdentifierStrId(unit, id_node) orelse return;
    var expr_id_opt: ?astdb_core.NodeId = null;
    if (children.len >= 2) expr_id_opt = children[children.len - 1];
    var ty: Type = Type{ .Unknown = {} };
    if (expr_id_opt) |eid| {
        if (getType(analyzer, eid)) |found| {
            ty = found;
        } else {
            // Attempt quick literal inference
            ty = inferExprType(analyzer, unit.nodes[@intFromEnum(eid)]);
        }
    }
    _ = try analyzer.graph.var_types.put(name_sid, ty);
    // Also set type_of for the identifier occurrence node
    _ = try setType(analyzer, children[0], ty);
}

fn analyzeVarStmt(analyzer: *Analyzer, _: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    // Same handling as let for now
    try analyzeLetStmt(analyzer, undefined, node, unit);
}

fn analyzeIndexExpr(analyzer: *Analyzer, node_id: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    const children = unit.edges[node.child_lo..node.child_hi];
    if (children.len < 2) return;
    const arr_id = children[0];
    var arr_ty = getType(analyzer, arr_id) orelse Type{ .Unknown = {} };
    switch (arr_ty) {
        .Unknown => {
            // If lhs is identifier, try var_types directly
            const lhs_node = unit.nodes[@intFromEnum(arr_id)];
            if (lhs_node.kind == .identifier) {
                if (getIdentifierStrId(unit, lhs_node)) |sid| {
                    if (analyzer.graph.var_types.get(sid)) |vty| {
                        arr_ty = vty;
                    }
                }
            }
        },
        else => {},
    }
    switch (arr_ty) {
        .Array => |elem_ptr| {
            _ = try setType(analyzer, node_id, elem_ptr.*);
        },
        else => {},
    }
}

fn analyzeBinaryExpr(analyzer: *Analyzer, node_id: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    // Detect ?? via operator token
    const tok_idx = @intFromEnum(node.first_token);
    if (tok_idx < unit.tokens.len) {
        const tok = unit.tokens[tok_idx];
        if (tok.kind == .assign) {
            // Handle assignment: lhs = rhs -> bind var type
            const children = unit.edges[node.child_lo..node.child_hi];
            if (children.len == 2) {
                const lhs_id = children[0];
                const rhs_id = children[1];
                const lhs_node = unit.nodes[@intFromEnum(lhs_id)];
                const rhs_ty = getType(analyzer, rhs_id) orelse inferExprType(analyzer, unit.nodes[@intFromEnum(rhs_id)]);
                if (lhs_node.kind == .identifier) {
                    if (getIdentifierStrId(unit, lhs_node)) |sid| {
                        _ = try analyzer.graph.var_types.put(sid, rhs_ty);
                        _ = try setType(analyzer, lhs_id, rhs_ty);
                    }
                }
                // Optionally set result type
                _ = try setType(analyzer, node_id, rhs_ty);
            }
            return;
        }
        if (tok.kind == .null_coalesce) {
            const children = unit.edges[node.child_lo..node.child_hi];
            if (children.len == 2) {
                const lhs_ty = getType(analyzer, children[0]) orelse Type{ .Unknown = {} };
                const rhs_ty = getType(analyzer, children[1]) orelse Type{ .Unknown = {} };
                // If lhs Optional(T) and rhs T, result is T
                switch (lhs_ty) {
                    .Optional => |inner| {
                        // naive match: if rhs equals inner -> set inner
                        _ = rhs_ty; // future: compare types
                        _ = try setType(analyzer, node_id, inner.*);
                    },
                    else => {},
                }
            }
        }
    }
}

fn analyzeForStmt(analyzer: *Analyzer, _: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    const children = unit.edges[node.child_lo..node.child_hi];
    if (children.len < 2) return;
    const var_id = children[0];
    const iter_id = children[1];
    const iter_ty = getType(analyzer, iter_id) orelse Type{ .Unknown = {} };
    switch (iter_ty) {
        .Array => |elem_ptr| {
            // Bind loop variable type
            const var_node = unit.nodes[@intFromEnum(var_id)];
            const sid = getIdentifierStrId(unit, var_node) orelse return;
            _ = try analyzer.graph.var_types.put(sid, elem_ptr.*);
        },
        else => {},
    }
}

// Helper functions to extract information from ASTDB nodes
fn getFunctionName(node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) ?[]const u8 {
    _ = node;
    _ = unit;
    // TODO: Implement proper token-to-string resolution
    return "main"; // Placeholder
}

fn getCalleeNameFromNode(node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) ?[]const u8 {
    const children = unit.edges[node.child_lo..node.child_hi];
    if (children.len == 0) return null;
    const callee_id = children[0];
    const callee = unit.nodes[@intFromEnum(callee_id)];
    if (callee.kind != .identifier) return null;
    if (getIdentifierStrId(unit, callee)) |sid| {
        // Convert StrId to bytes using the astdb_system interner on the graph later if needed
        // Return null here to prefer using StrId-based lookup
        _ = sid;
        return null;
    }
    return null;
}

/// Build normalized positional argument list for a call_expr and store it in graph.call_args
fn normalizeAndStoreCallArgs(analyzer: *Analyzer, call_id: astdb_core.NodeId, node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) !void {
    // child layout: [callee_expr, arg0, arg1, ...]
    const edges = unit.edges[node.child_lo..node.child_hi];
    if (edges.len == 0) return; // malformed

    var args_buf: std.ArrayList(astdb_core.NodeId) = .empty;
    defer args_buf.deinit();
    var names_buf: std.ArrayList(?astdb.StrId) = .empty;
    defer names_buf.deinit();

    var i: usize = 1; // skip callee
    while (i < edges.len) : (i += 1) {
        const arg_id = edges[i];
        const arg_node = unit.nodes[@intFromEnum(arg_id)];
        if (arg_node.kind == .identifier and i + 1 < edges.len) {
            // Treat as named arg: identifier ':' value; we keep the value only
            const value_id = edges[i + 1];
            try args_buf.append(value_id);
            if (getIdentifierStrId(unit, arg_node)) |sid| {
                try names_buf.append(sid);
            } else try names_buf.append(null);
            i += 1; // consume extra
        } else {
            try args_buf.append(arg_id);
            try names_buf.append(null);
        }
    }

    const owned = try analyzer.graph.allocator.dupe(astdb_core.NodeId, args_buf.items);
    _ = try analyzer.graph.call_args.put(call_id, owned);

    // If we can resolve callee, and have param names, reorder
    const sid = blk: {
        // Prefer direct StrId from callee identifier
        const children = unit.edges[node.child_lo..node.child_hi];
        if (children.len > 0) {
            const callee_id = children[0];
            const callee = unit.nodes[@intFromEnum(callee_id)];
            if (callee.kind == .identifier) {
                if (getIdentifierStrId(unit, callee)) |csid| break :blk csid;
            }
        }
        break :blk null;
    } orelse return;
    const func_id = analyzer.graph.func_by_name.get(sid) orelse return;
    const param_names = analyzer.graph.func_param_names.get(func_id) orelse return;

    // Build reordered values array according to param order
    var reordered: std.ArrayList(astdb_core.NodeId) = .empty;
    defer reordered.deinit();
    // Track which provided args were consumed (for unnamed fallbacks)
    var used = try analyzer.allocator.alloc(bool, names_buf.items.len);
    defer analyzer.allocator.free(used);
    @memset(used, false);

    // First, place named args by matching names
    const pnames_slice = param_names; // []StrId
    var pi: usize = 0;
    while (pi < pnames_slice.len) : (pi += 1) {
        const pname = pnames_slice[pi];
        var placed = false;
        var j: usize = 0;
        while (j < names_buf.items.len) : (j += 1) {
            if (used[j]) continue;
            const opt = names_buf.items[j];
            if (opt) |aname| {
                if (aname == pname) {
                    try reordered.append(owned[j]);
                    used[j] = true;
                    placed = true;
                    break;
                }
            }
        }
        if (!placed) {
            // Will be filled by positional pass below
            try reordered.append(@as(astdb_core.NodeId, @enumFromInt(0))); // placeholder; will overwrite
        }
    }

    // Fill remaining unplaced params with next unnamed or unused args in order
    var cursor: usize = 0;
    var k: usize = 0;
    while (k < reordered.items.len) : (k += 1) {
        if (reordered.items[k] != (@as(astdb_core.NodeId, @enumFromInt(0)))) continue;
        // find next unused arg (preferring unnamed)
        var j: usize = cursor;
        while (j < names_buf.items.len and used[j]) : (j += 1) {}
        if (j >= names_buf.items.len) break;
        // Prefer unnamed; if named but unmatched, still use in order
        _ = reordered.replaceRangeAssumeCapacity(k, 1, &[_]astdb_core.NodeId{owned[j]});
        used[j] = true;
        cursor = j + 1;
    }

    // Replace stored call_args with reordered slice
    const final_owned = try analyzer.graph.allocator.dupe(astdb_core.NodeId, reordered.items);
    // Free previous owned slice
    if (analyzer.graph.call_args.getPtr(call_id)) |ptr| analyzer.graph.allocator.free(ptr.*);
    _ = try analyzer.graph.call_args.put(call_id, final_owned);
}

fn getIdentifierName(node: astdb_core.AstNode, unit: *astdb_core.CompilationUnit) ?[]const u8 {
    _ = node;
    _ = unit;
    // TODO: Implement proper token-to-string resolution
    return "main"; // Placeholder
}

/// Get identifier StrId from a node (expects identifier/parameter nodes)
fn getIdentifierStrId(unit: *astdb_core.CompilationUnit, node: astdb_core.AstNode) ?astdb.StrId {
    // Use first_token; parameters are backed by identifier tokens
    const tok_idx = @intFromEnum(node.first_token);
    if (tok_idx >= unit.tokens.len) return null;
    const tok = unit.tokens[tok_idx];
    return tok.str;
}

fn resolveTypeFromNode(graph: *SemanticGraph, unit: *astdb_core.CompilationUnit, node: astdb_core.AstNode) ?Type {
    // primitive_type nodes point to an identifier token spelling the type name
    const tok_idx = @intFromEnum(node.first_token);
    if (tok_idx >= unit.tokens.len) return null;
    const tok = unit.tokens[tok_idx];
    if (node.kind == .array_type) {
        // Children contain inner type node
        const children = unit.edges[node.child_lo..node.child_hi];
        if (children.len == 1) {
            const inner = unit.nodes[@intFromEnum(children[0])];
            if (resolveTypeFromNode(graph, unit, inner)) |inner_ty| {
                // Box inner type
                const boxed = graph.allocator.create(Type) catch return null;
                boxed.* = inner_ty;
                return Type{ .Array = boxed };
            }
        }
        return null;
    }
    if (tok.str) |sid| {
        const name = graph.astdb_system.str_interner.getString(sid);
        if (std.mem.eql(u8, name, "string")) return Type{ .String = {} };
        if (std.mem.eql(u8, name, "i32") or std.mem.eql(u8, name, "int")) return Type{ .Int = {} };
        if (std.mem.eql(u8, name, "bool")) return Type{ .Bool = {} };
        if (std.mem.eql(u8, name, "f64") or std.mem.eql(u8, name, "float")) return Type{ .Float = {} };
        // Treat any other identifier as a struct name; use existing sid
        const name_id: u64 = @intCast(@intFromEnum(sid));
        return Type{ .Struct = name_id };
    }
    return null;
}

// Minimal expression type inference for :min (placeholder)
fn inferExprType(_: *Analyzer, node: astdb_core.AstNode) Type {
    return switch (node.kind) {
        .string_literal => Type{ .String = {} },
        .integer_literal => Type{ .Int = {} },
        .float_literal => Type{ .Float = {} },
        .bool_literal => Type{ .Bool = {} },
        else => Type{ .Unknown = {} },
    };
}

// Transitional analysis entry point - bridges old AST to ASTDB
pub fn analyze(root: *Parser.Node, allocator: std.mem.Allocator) !SemanticGraph {
    // Create a temporary ASTDB system for the analysis
    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var graph = try SemanticGraph.init(allocator, &astdb_system);
    errdefer graph.deinit();

    // Register standard library symbols
    try registerStandardLibrary(&graph, allocator);

    // Convert old AST to ASTDB and analyze
    var analyzer = Analyzer.init(&graph, allocator);
    defer analyzer.deinit();

    _ = try analyzer.analyzeNode(root);

    // Check for semantic errors
    if (analyzer.errors.items.len > 0) {
        // For now, just return the first error
        return error.SemanticError;
    }

    return graph;
}

// Register standard library symbols and their capability requirements
fn registerStandardLibrary(graph: *SemanticGraph, allocator: std.mem.Allocator) !void {
    // Use static capability arrays to avoid memory leaks - Allocator Sovereignty doctrine
    const stdout_caps = [_]Type{Type.StdoutWriteCapability};
    const stderr_caps = [_]Type{Type.StderrWriteCapability};
    const no_caps = [_]Type{};

    // Register std.io.print function
    try graph.addSymbol(Symbol{
        .name = "print",
        .type = Type.Function,
        .kind = .StdLibFunction,
        .module_path = "std.io",
        .required_capabilities = &stdout_caps,
    });

    // Register std.io.eprint function
    try graph.addSymbol(Symbol{
        .name = "eprint",
        .type = Type.Function,
        .kind = .StdLibFunction,
        .module_path = "std.io",
        .required_capabilities = &stderr_caps,
    });

    // Register capability types
    try graph.addSymbol(Symbol{
        .name = "StdoutWriteCapability",
        .type = Type.StdoutWriteCapability,
        .kind = .CapabilityType,
        .module_path = "std.io",
        .required_capabilities = &no_caps,
    });

    try graph.addSymbol(Symbol{
        .name = "StderrWriteCapability",
        .type = Type.StderrWriteCapability,
        .kind = .CapabilityType,
        .module_path = "std.io",
        .required_capabilities = &no_caps,
    });

    _ = allocator; // Suppress unused parameter warning
}

// Legacy compatibility function (no-op version)
pub fn analyzeLegacy(_root: *Parser.Node) !void {
    // placeholder: currently does nothing; kept for compatibility
    _ = _root;
    return;
}
