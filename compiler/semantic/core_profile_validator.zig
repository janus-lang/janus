// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! :core Profile Semantic Validator
//!
//! Task 3: Implements semantic validation for the :core profile subset (aliases: :min, :teaching).
//! This is the teaching subset with:
//! - Types: i64, f64, bool, String, Array, HashMap
//! - Constructs: func, let, var, if, else, for, while, return
//! - Single-threaded, deterministic execution
//!
//! References:
//! - SPEC-semantics.md [SEM-04, SEM-05, SEM-06]
//! - SPEC-profiles.md [PROF-04]

const std = @import("std");
const Allocator = std.mem.Allocator;

// Core semantic infrastructure
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const TypeSystem = @import("type_system.zig").TypeSystem;
const TypeId = @import("type_system.zig").TypeId;
const PrimitiveType = @import("type_system.zig").PrimitiveType;
const ProfileManager = @import("profile_manager.zig").ProfileManager;
const LanguageProfile = @import("profile_manager.zig").LanguageProfile;
const ValidationEngine = @import("validation_engine.zig");
const SemanticError = ValidationEngine.SemanticError;
const SemanticWarning = ValidationEngine.SemanticWarning;
const ErrorCode = ValidationEngine.ErrorCode;
const SourceSpan = ValidationEngine.SourceSpan;

// ASTDB types
const astdb = @import("astdb");
const NodeId = astdb.NodeId;
const AstNode = astdb.AstNode;
const NodeKind = astdb.AstNode.NodeKind;
const Token = astdb.Token;
const TokenKind = astdb.Token.TokenKind;
const StrId = astdb.StrId;

/// :core profile type categories
pub const CoreProfileType = enum {
    i64_type,
    f64_type,
    bool_type,
    string_type,
    array_type,
    hashmap_type,
    void_type,
    unknown,

    /// Map from PrimitiveType to CoreProfileType
    pub fn fromPrimitive(prim: PrimitiveType) CoreProfileType {
        return switch (prim) {
            .i32, .i64 => .i64_type, // :core uses i64 as the integer type
            .f32, .f64 => .f64_type,
            .bool => .bool_type,
            .string => .string_type,
            .void => .void_type,
            .never => .void_type,
        };
    }

    /// Check if this type is allowed in :min profile
    pub fn isCoreProfileType(self: CoreProfileType) bool {
        return switch (self) {
            .i64_type, .f64_type, .bool_type, .string_type, .array_type, .hashmap_type, .void_type => true,
            .unknown => false,
        };
    }
};

/// Validation result for :core profile
pub const CoreValidationResult = struct {
    allocator: Allocator,
    is_valid: bool,
    errors: std.ArrayList(SemanticError),
    warnings: std.ArrayList(SemanticWarning),
    symbol_table: *SymbolTable,
    type_annotations: std.AutoHashMap(u32, TypeId), // NodeId -> TypeId

    pub fn init(allocator: Allocator) !CoreValidationResult {
        return CoreValidationResult{
            .allocator = allocator,
            .is_valid = true,
            .errors = std.ArrayList(SemanticError){},
            .warnings = std.ArrayList(SemanticWarning){},
            .symbol_table = try SymbolTable.init(allocator),
            .type_annotations = std.AutoHashMap(u32, TypeId).init(allocator),
        };
    }

    pub fn deinit(self: *CoreValidationResult) void {
        self.errors.deinit(self.allocator);
        self.warnings.deinit(self.allocator);
        self.symbol_table.deinit();
        self.type_annotations.deinit();
    }

    pub fn addError(self: *CoreValidationResult, err: SemanticError) !void {
        try self.errors.append(self.allocator, err);
        self.is_valid = false;
    }

    pub fn addWarning(self: *CoreValidationResult, warning: SemanticWarning) !void {
        try self.warnings.append(self.allocator, warning);
    }

    pub fn annotateType(self: *CoreValidationResult, node_id: NodeId, type_id: TypeId) !void {
        try self.type_annotations.put(@intFromEnum(node_id), type_id);
    }

    pub fn getTypeAnnotation(self: *CoreValidationResult, node_id: NodeId) ?TypeId {
        return self.type_annotations.get(@intFromEnum(node_id));
    }
};

/// :core Profile Semantic Validator
/// Implements the three validation passes:
/// 1. Symbol Resolution - Build symbol table from AST
/// 2. Type Inference - Infer types for untyped declarations
/// 3. Type Checking - Validate type compatibility
pub const CoreProfileValidator = struct {
    allocator: Allocator,
    type_system: *TypeSystem,
    profile_manager: *ProfileManager,

    // Cached type IDs for :min types
    i64_type_id: ?TypeId = null,
    f64_type_id: ?TypeId = null,
    bool_type_id: ?TypeId = null,
    string_type_id: ?TypeId = null,
    void_type_id: ?TypeId = null,

    pub fn init(allocator: Allocator) !CoreProfileValidator {
        const type_system = try allocator.create(TypeSystem);
        errdefer allocator.destroy(type_system);
        type_system.* = try TypeSystem.init(allocator);

        const profile_manager = try allocator.create(ProfileManager);
        errdefer allocator.destroy(profile_manager);
        profile_manager.* = try ProfileManager.init(allocator, .core);

        var validator = CoreProfileValidator{
            .allocator = allocator,
            .type_system = type_system,
            .profile_manager = profile_manager,
        };

        // Cache primitive type IDs
        validator.i64_type_id = try type_system.getOrCreatePrimitive(.i64);
        validator.f64_type_id = try type_system.getOrCreatePrimitive(.f64);
        validator.bool_type_id = try type_system.getOrCreatePrimitive(.bool);
        validator.string_type_id = try type_system.getOrCreatePrimitive(.string);
        validator.void_type_id = try type_system.getOrCreatePrimitive(.void);

        return validator;
    }

    pub fn deinit(self: *CoreProfileValidator) void {
        self.type_system.deinit();
        self.allocator.destroy(self.type_system);
        self.profile_manager.deinit();
        self.allocator.destroy(self.profile_manager);
    }

    /// Validate a complete program for :core profile compliance
    pub fn validateProgram(self: *CoreProfileValidator, db: *astdb.AstDB, unit_id: astdb.UnitId) !CoreValidationResult {
        var result = try CoreValidationResult.init(self.allocator);
        errdefer result.deinit();

        const unit = db.getUnit(unit_id) orelse {
            try result.addError(.{
                .kind = .invalid_operation,
                .message = "Invalid compilation unit",
                .node_id = 0,
                .span = .{ .start_line = 0, .start_column = 0, .end_line = 0, .end_column = 0 },
            });
            return result;
        };

        // Pass 1: Symbol Resolution
        try self.resolveSymbols(db, unit, &result);

        // Pass 2: Type Inference
        try self.inferTypes(db, unit, &result);

        // Pass 3: Type Checking
        try self.checkTypes(db, unit, &result);

        // Pass 4: Profile Compliance
        try self.checkProfileCompliance(db, unit, &result);

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PASS 1: SYMBOL RESOLUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Build symbol table from parsed AST
    fn resolveSymbols(self: *CoreProfileValidator, db: *astdb.AstDB, unit: *const astdb.CompilationUnit, result: *CoreValidationResult) !void {
        // Scan all nodes for declarations
        for (unit.nodes, 0..) |node, i| {
            const node_id: NodeId = @enumFromInt(i);

            switch (node.kind) {
                .func_decl => {
                    try self.registerFunctionDecl(db, unit, node_id, node, result);
                },
                .let_stmt, .var_stmt, .const_stmt => {
                    try self.registerVariableDecl(db, unit, node_id, node, result);
                },
                else => {},
            }
        }
    }

    /// Register a function declaration in the symbol table
    fn registerFunctionDecl(
        self: *CoreProfileValidator,
        db: *astdb.AstDB,
        unit: *const astdb.CompilationUnit,
        node_id: NodeId,
        node: astdb.AstNode,
        result: *CoreValidationResult,
    ) !void {
        _ = self;
        _ = db;

        // Extract function name from tokens
        const first_tok_idx = @intFromEnum(node.first_token);
        if (first_tok_idx + 1 >= unit.tokens.len) return;

        const name_token = unit.tokens[first_tok_idx + 1]; // func <name>
        if (name_token.kind != .identifier) return;

        const name_str_id = name_token.str orelse return;

        // Check for duplicate definition
        if (result.symbol_table.lookupLocal(name_str_id)) |_| {
            try result.addError(.{
                .kind = .duplicate_definition,
                .message = "Function already defined in this scope",
                .node_id = @intFromEnum(node_id),
                .span = tokenSpanToSourceSpan(name_token.span),
            });
            return;
        }

        // Register function symbol
        _ = try result.symbol_table.define(name_str_id, .{
            .id = undefined, // Will be assigned by SymbolTable
            .name = name_str_id,
            .kind = .function,
            .type_id = null, // Will be set during type inference
            .declaration_node = node_id,
            .declaration_span = tokenSpanToSourceSpan(name_token.span),
            .visibility = .public,
            .scope_id = result.symbol_table.currentScope(),
        });
    }

    /// Register a variable declaration in the symbol table
    fn registerVariableDecl(
        self: *CoreProfileValidator,
        db: *astdb.AstDB,
        unit: *const astdb.CompilationUnit,
        node_id: NodeId,
        node: astdb.AstNode,
        result: *CoreValidationResult,
    ) !void {
        _ = self;
        _ = db;

        // Extract variable name from tokens (let/var <name> ...)
        const first_tok_idx = @intFromEnum(node.first_token);
        if (first_tok_idx + 1 >= unit.tokens.len) return;

        const name_token = unit.tokens[first_tok_idx + 1];
        if (name_token.kind != .identifier) return;

        const name_str_id = name_token.str orelse return;

        // Check for duplicate definition
        if (result.symbol_table.lookupLocal(name_str_id)) |_| {
            try result.addError(.{
                .kind = .duplicate_definition,
                .message = "Variable already defined in this scope",
                .node_id = @intFromEnum(node_id),
                .span = tokenSpanToSourceSpan(name_token.span),
            });
            return;
        }

        // Register variable symbol
        _ = try result.symbol_table.define(name_str_id, .{
            .id = undefined,
            .name = name_str_id,
            .kind = .variable,
            .type_id = null, // Will be set during type inference
            .declaration_node = node_id,
            .declaration_span = tokenSpanToSourceSpan(name_token.span),
            .visibility = .private,
            .scope_id = result.symbol_table.currentScope(),
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PASS 2: TYPE INFERENCE
    // ═══════════════════════════════════════════════════════════════════════════

    /// Infer types for declarations without explicit type annotations
    fn inferTypes(self: *CoreProfileValidator, db: *astdb.AstDB, unit: *const astdb.CompilationUnit, result: *CoreValidationResult) !void {
        _ = db;

        // Scan for declarations and infer their types
        for (unit.nodes, 0..) |node, i| {
            const node_id: NodeId = @enumFromInt(i);

            switch (node.kind) {
                .let_stmt, .var_stmt, .const_stmt => {
                    // Find the initialization expression and infer its type
                    const inferred_type = try self.inferExpressionType(unit, node, result);
                    try result.annotateType(node_id, inferred_type);
                },
                .integer_literal => {
                    try result.annotateType(node_id, self.i64_type_id.?);
                },
                .float_literal => {
                    try result.annotateType(node_id, self.f64_type_id.?);
                },
                .bool_literal => {
                    try result.annotateType(node_id, self.bool_type_id.?);
                },
                .string_literal => {
                    try result.annotateType(node_id, self.string_type_id.?);
                },
                else => {},
            }
        }
    }

    /// Infer the type of an expression
    fn inferExpressionType(self: *CoreProfileValidator, unit: *const astdb.CompilationUnit, node: astdb.AstNode, result: *CoreValidationResult) !TypeId {
        _ = result;

        // For variable declarations, look at the initializer
        // The initializer is typically the last child of the declaration
        if (node.child_hi > node.child_lo) {
            // Has children - check the last child (initializer)
            // For now, default to i64 if we can't determine
            return self.i64_type_id.?;
        }

        // Look at tokens to guess type
        const first_tok_idx = @intFromEnum(node.first_token);
        const last_tok_idx = @intFromEnum(node.last_token);

        // Scan tokens for literals
        var idx = first_tok_idx;
        while (idx <= last_tok_idx and idx < unit.tokens.len) : (idx += 1) {
            const tok = unit.tokens[idx];
            switch (tok.kind) {
                .integer_literal => return self.i64_type_id.?,
                .float_literal => return self.f64_type_id.?,
                .string_literal => return self.string_type_id.?,
                .bool_literal => return self.bool_type_id.?,
                else => {},
            }
        }

        // Default to i64 for now
        return self.i64_type_id.?;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PASS 3: TYPE CHECKING
    // ═══════════════════════════════════════════════════════════════════════════

    /// Validate type compatibility across all expressions
    fn checkTypes(self: *CoreProfileValidator, db: *astdb.AstDB, unit: *const astdb.CompilationUnit, result: *CoreValidationResult) !void {
        _ = db;

        for (unit.nodes, 0..) |node, i| {
            const node_id: NodeId = @enumFromInt(i);

            switch (node.kind) {
                .binary_expr => {
                    try self.checkBinaryExpr(unit, node_id, node, result);
                },
                .call_expr => {
                    try self.checkCallExpr(unit, node_id, node, result);
                },
                .if_stmt, .while_stmt => {
                    try self.checkConditionIsBool(unit, node_id, node, result);
                },
                .return_stmt => {
                    try self.checkReturnType(unit, node_id, node, result);
                },
                else => {},
            }
        }
    }

    /// Check binary expression operand types
    fn checkBinaryExpr(self: *CoreProfileValidator, unit: *const astdb.CompilationUnit, node_id: NodeId, node: astdb.AstNode, result: *CoreValidationResult) !void {
        _ = self;
        _ = unit;
        _ = node;
        _ = node_id;
        _ = result;
        // TODO: Implement binary expression type checking
        // - Arithmetic ops require numeric operands
        // - Comparison ops return bool
        // - Logical ops require bool operands
    }

    /// Check function call argument types
    fn checkCallExpr(self: *CoreProfileValidator, unit: *const astdb.CompilationUnit, node_id: NodeId, node: astdb.AstNode, result: *CoreValidationResult) !void {
        _ = self;
        _ = unit;
        _ = node;
        _ = node_id;
        _ = result;
        // TODO: Implement function call type checking
        // - Look up function signature in symbol table
        // - Match argument types to parameter types
    }

    /// Check that condition expressions are boolean
    fn checkConditionIsBool(self: *CoreProfileValidator, unit: *const astdb.CompilationUnit, node_id: NodeId, node: astdb.AstNode, result: *CoreValidationResult) !void {
        _ = unit;
        _ = node;

        // Get the condition expression type
        // For if/while, the condition is typically the first child
        const condition_type = result.getTypeAnnotation(node_id);

        if (condition_type) |ctype| {
            if (!ctype.eql(self.bool_type_id.?)) {
                try result.addError(.{
                    .kind = .type_mismatch,
                    .message = "Condition must be boolean",
                    .node_id = @intFromEnum(node_id),
                    .span = .{ .start_line = 0, .start_column = 0, .end_line = 0, .end_column = 0 },
                });
            }
        }
    }

    /// Check return statement type matches function signature
    fn checkReturnType(self: *CoreProfileValidator, unit: *const astdb.CompilationUnit, node_id: NodeId, node: astdb.AstNode, result: *CoreValidationResult) !void {
        _ = self;
        _ = unit;
        _ = node;
        _ = node_id;
        _ = result;
        // TODO: Implement return type checking
        // - Find enclosing function
        // - Match return value type to declared return type
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PASS 4: PROFILE COMPLIANCE
    // ═══════════════════════════════════════════════════════════════════════════

    /// Check that only :core profile features are used
    fn checkProfileCompliance(self: *CoreProfileValidator, db: *astdb.AstDB, unit: *const astdb.CompilationUnit, result: *CoreValidationResult) !void {
        _ = db;

        for (unit.nodes, 0..) |node, i| {
            const node_id: NodeId = @enumFromInt(i);

            // Check for features NOT allowed in :min profile
            const is_forbidden = switch (node.kind) {
                // Actor/concurrency (cluster profile)
                .trait_decl, .impl_decl => true,

                // Match expressions (not in basic :core)
                .match_stmt, .match_arm => true,

                // Advanced features
                .using_decl => true,

                // Postfix guards (advanced)
                .postfix_when, .postfix_unless => true,

                // All other node kinds are allowed in :core
                else => false,
            };

            if (is_forbidden) {
                const feature_name = self.getFeatureName(node.kind);
                try result.addError(.{
                    .kind = .scope_violation,
                    .message = feature_name,
                    .node_id = @intFromEnum(node_id),
                    .span = .{ .start_line = 0, .start_column = 0, .end_line = 0, .end_column = 0 },
                });
            }
        }
    }

    /// Get human-readable feature name for error messages
    fn getFeatureName(self: *CoreProfileValidator, kind: NodeKind) []const u8 {
        _ = self;
        return switch (kind) {
            .trait_decl => "Traits are not available in :core profile (upgrade to :service)",
            .impl_decl => "Impl blocks are not available in :core profile (upgrade to :service)",
            .match_stmt => "Match expressions are not available in :core profile (use if/else)",
            .match_arm => "Match arms are not available in :core profile",
            .using_decl => "Using declarations are not available in :core profile",
            .postfix_when => "Postfix 'when' guards are not available in :core profile",
            .postfix_unless => "Postfix 'unless' guards are not available in :core profile",
            else => "Feature not available in :core profile",
        };
    }
};

/// Convert ASTDB SourceSpan to ValidationEngine SourceSpan
fn tokenSpanToSourceSpan(span: astdb.SourceSpan) SourceSpan {
    return .{
        .start_line = span.line,
        .start_column = span.column,
        .end_line = span.line,
        .end_column = span.column + (span.end - span.start),
    };
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "CoreProfileValidator initialization" {
    const allocator = std.testing.allocator;

    var validator = try CoreProfileValidator.init(allocator);
    defer validator.deinit();

    // Verify cached type IDs
    try std.testing.expect(validator.i64_type_id != null);
    try std.testing.expect(validator.bool_type_id != null);
    try std.testing.expect(validator.string_type_id != null);
}

test "CoreProfileType allowed types" {
    try std.testing.expect(CoreProfileType.i64_type.isCoreProfileType());
    try std.testing.expect(CoreProfileType.f64_type.isCoreProfileType());
    try std.testing.expect(CoreProfileType.bool_type.isCoreProfileType());
    try std.testing.expect(CoreProfileType.string_type.isCoreProfileType());
    try std.testing.expect(CoreProfileType.array_type.isCoreProfileType());
    try std.testing.expect(CoreProfileType.void_type.isCoreProfileType());
    try std.testing.expect(!CoreProfileType.unknown.isCoreProfileType());
}
