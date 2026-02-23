// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const TokenType = @import("tokenizer.zig").TokenType;

const astdb = @import("libjanus/astdb.zig");
const Snapshot = astdb.Snapshot;
const NodeKind = astdb.NodeKind;
const TokenKind = astdb.TokenKind;
const Span = astdb.Span;
const NodeId = astdb.NodeId;
const TokenId = astdb.TokenId;
const StrId = astdb.StrId;
const interner = @import("libjanus/astdb/granite_interner.zig");

// Tokenizer → ASTDB Bridge - Direct tokenization into granite-solid columnar storage
// Task: Critical Path Integration - Bypass parser complexity, go direct to ASTDB
// Requirements: End-to-end source text → structured semantic truth pipeline

/// Simplified bridge that tokenizes source directly into ASTDB Snapshot tables
pub const ParserASTDBBridge = struct {
    allocator: std.mem.Allocator,
    str_interner: *interner.StrInterner,
    snapshot: *Snapshot,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, str_interner: *interner.StrInterner) !Self {
        const snapshot = try Snapshot.init(allocator, str_interner);

        return Self{
            .allocator = allocator,
            .str_interner = str_interner,
            .snapshot = snapshot,
        };
    }

    pub fn deinit(self: *Self) void {
        self.snapshot.deinit();
    }

    /// Parse source text and populate ASTDB Snapshot tables
    pub fn parseToSnapshot(self: *Self, source: []const u8) !NodeId {
        // Initialize tokenizer
        var tokenizer = Tokenizer.init(self.allocator, source);

        // Create root node
        const root_span = Span{
            .start_byte = 0,
            .end_byte = @as(u32, @intCast(source.len)),
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = @as(u32, @intCast(source.len)),
        };

        const root_str_id = try self.str_interner.get("program");
        const root_token = try self.snapshot.addToken(.identifier, root_str_id, root_span);

        // Parse tokens and create nodes
        var children: std.ArrayList(NodeId) = .empty;
        defer children.deinit();

        try self.parseTokensToNodes(&tokenizer, &children);

        // Create root node with all children
        return try self.snapshot.addNode(.root, root_token, root_token, children.items);
    }

    /// Parse tokens into ASTDB nodes using simple pattern matching
    fn parseTokensToNodes(self: *Self, tokenizer: *Tokenizer, children: *std.ArrayList(NodeId)) !void {
        while (true) {
            const token = tokenizer.nextToken() catch break;
            if (token.type == .eof) break;

            // Skip newlines and invalid tokens
            if (token.type == .newline or token.type == .invalid) continue;

            // Handle package declaration
            if (token.type == .package) {
                const package_node = try self.parsePackageDeclaration(tokenizer, token);
                try children.append(package_node);
                continue;
            }

            // Handle const declaration
            if (token.type == .@"const") {
                const const_node = try self.parseConstDeclaration(tokenizer, token);
                try children.append(const_node);
                continue;
            }

            // Handle function declarations specially
            if (token.type == .func) {
                const func_node = try self.parseFunctionDeclaration(tokenizer, token);
                try children.append(func_node);
            } else {
                // Skip other tokens for now - we only care about top-level constructs
                continue;
            }
        }
    }

    /// Get the populated snapshot (for testing and analysis)
    pub fn getSnapshot(self: *const Self) *const Snapshot {
        return self.snapshot;
    }

    /// Parse a complete function declaration
    fn parseFunctionDeclaration(self: *Self, tokenizer: *Tokenizer, func_token: Token) !NodeId {
        // Look for function name
        const name_token = tokenizer.nextToken() catch return error.UnexpectedEOF;
        if (name_token.type != .identifier) return error.ExpectedFunctionName;

        // Create function node with proper span
        const span = Span{
            .start_byte = @as(u32, @intCast(func_token.location.offset)),
            .end_byte = @as(u32, @intCast(name_token.location.offset + name_token.value.len)),
            .start_line = @as(u32, @intCast(func_token.location.line)),
            .start_col = @as(u32, @intCast(func_token.location.column)),
            .end_line = @as(u32, @intCast(name_token.location.line)),
            .end_col = @as(u32, @intCast(name_token.location.column + name_token.value.len)),
        };

        const str_id = try self.str_interner.get(name_token.value);
        const astdb_token = try self.snapshot.addToken(.identifier, str_id, span);

        // Parse function parameters and body (simplified)
        var func_children: std.ArrayList(NodeId) = .empty;
        defer func_children.deinit();

        // Skip to function body and parse parameters/return statements
        var paren_count: i32 = 0;
        var brace_count: i32 = 0;
        var in_params = false;
        var in_body = false;
        var expecting_param_name = true; // Track parameter parsing state

        while (true) {
            const token = tokenizer.nextToken() catch break;
            if (token.type == .eof) break;

            if (token.type == .lparen) {
                paren_count += 1;
                in_params = true;
                expecting_param_name = true; // First token after ( should be param name
            } else if (token.type == .rparen) {
                paren_count -= 1;
                if (paren_count == 0) {
                    in_params = false;
                    expecting_param_name = false;
                }
            } else if (token.type == .lbrace) {
                brace_count += 1;
                in_body = true;
            } else if (token.type == .rbrace) {
                brace_count -= 1;
                if (brace_count <= 0) break;
            } else if (in_params and token.type == .identifier and expecting_param_name) {
                // This identifier should be a parameter name
                const param_node = try self.createParameterNode(token);
                try func_children.append(param_node);
                expecting_param_name = false; // Next identifier will be type name
            } else if (in_params and token.type == .colon) {
                // After colon, next identifier will be type name (skip it)
                expecting_param_name = false;
            } else if (in_params and token.type == .comma) {
                // After comma, next identifier will be parameter name
                expecting_param_name = true;
            } else if (in_body) {
                // Handle body statements
                if (token.type == .return_kw) {
                    // Create return statement node
                    const return_node = try self.createReturnNode(tokenizer, token);
                    try func_children.append(return_node);
                } else if (token.type == .@"defer") {
                    // Parse defer statement
                    const defer_node = try self.parseDeferStmt(tokenizer, token);
                    try func_children.append(defer_node);
                } else if (token.type == .go) {
                    // Parse go statement
                    const go_node = try self.parseGoStmt(tokenizer, token);
                    try func_children.append(go_node);
                } else {
                    // Skip other tokens in body for now
                    continue;
                }
            }
        }

        return try self.snapshot.addNode(.func_decl, astdb_token, astdb_token, func_children.items);
    }

    /// Parse package declaration: package main
    fn parsePackageDeclaration(self: *Self, tokenizer: *Tokenizer, package_token: Token) !NodeId {
        const name_token = tokenizer.nextToken() catch return error.UnexpectedEOF;
        if (name_token.type != .identifier) return error.ExpectedPackageName;

        // Create module node
        const span = Span{
            .start_byte = @as(u32, @intCast(package_token.location.offset)),
            .end_byte = @as(u32, @intCast(name_token.location.offset + name_token.value.len)),
            .start_line = @as(u32, @intCast(package_token.location.line)),
            .start_col = @as(u32, @intCast(package_token.location.column)),
            .end_line = @as(u32, @intCast(name_token.location.line)),
            .end_col = @as(u32, @intCast(name_token.location.column + name_token.value.len)),
        };

        const str_id = try self.str_interner.get(name_token.value);
        const astdb_token = try self.snapshot.addToken(.identifier, str_id, span);

        // For now, no children
        var children = [_]NodeId{};
        return try self.snapshot.addNode(.module_decl, astdb_token, astdb_token, &children);
    }

    /// Parse const declaration: const ID := expr
    fn parseConstDeclaration(self: *Self, tokenizer: *Tokenizer, const_token: Token) !NodeId {
        const name_token = tokenizer.nextToken() catch return error.UnexpectedEOF;
        if (name_token.type != .identifier) return error.ExpectedConstName;

        // Skip to := and check
        const assign_token = tokenizer.nextToken() catch return error.ExpectedAssign;
        if (assign_token.type != .colon_equal) return error.ExpectedAssign;

        // Parse expr (simplified, assume literal or ident)
        const expr_token = tokenizer.nextToken() catch return error.UnexpectedEOF;
        const expr_node = try self.createNodeFromToken(expr_token);

        // Create const node
        const span = Span{
            .start_byte = @as(u32, @intCast(const_token.location.offset)),
            .end_byte = @as(u32, @intCast(expr_token.location.offset + expr_token.value.len)),
            .start_line = @as(u32, @intCast(const_token.location.line)),
            .start_col = @as(u32, @intCast(const_token.location.column)),
            .end_line = @as(u32, @intCast(expr_token.location.line)),
            .end_col = @as(u32, @intCast(expr_token.location.column + expr_token.value.len)),
        };

        const str_id = try self.str_interner.get(name_token.value);
        const astdb_token = try self.snapshot.addToken(.identifier, str_id, span);

        var children = [_]NodeId{expr_node};
        return try self.snapshot.addNode(.var_decl, astdb_token, astdb_token, &children); // Use var_decl for const
    }

    /// Parse defer statement: defer expr
    fn parseDeferStmt(self: *Self, tokenizer: *Tokenizer, defer_token: Token) !NodeId {
        // Parse expr after defer
        const expr_token = tokenizer.nextToken() catch return error.UnexpectedEOF;
        const expr_node = try self.createNodeFromToken(expr_token);

        // Create defer node
        const span = Span{
            .start_byte = @as(u32, @intCast(defer_token.location.offset)),
            .end_byte = @as(u32, @intCast(expr_token.location.offset + expr_token.value.len)),
            .start_line = @as(u32, @intCast(defer_token.location.line)),
            .start_col = @as(u32, @intCast(defer_token.location.column)),
            .end_line = @as(u32, @intCast(expr_token.location.line)),
            .end_col = @as(u32, @intCast(expr_token.location.column + expr_token.value.len)),
        };

        const str_id = try self.str_interner.get("defer");
        const astdb_token = try self.snapshot.addToken(.kw_defer, str_id, span);

        var children = [_]NodeId{expr_node};
        return try self.snapshot.addNode(.defer_stmt, astdb_token, astdb_token, &children);
    }

    /// Parse go statement: go expr
    fn parseGoStmt(self: *Self, tokenizer: *Tokenizer, go_token: Token) !NodeId {
        // Parse expr after go
        const expr_token = tokenizer.nextToken() catch return error.UnexpectedEOF;
        const expr_node = try self.createNodeFromToken(expr_token);

        // Create go node
        const span = Span{
            .start_byte = @as(u32, @intCast(go_token.location.offset)),
            .end_byte = @as(u32, @intCast(expr_token.location.offset + expr_token.value.len)),
            .start_line = @as(u32, @intCast(go_token.location.line)),
            .start_col = @as(u32, @intCast(go_token.location.column)),
            .end_line = @as(u32, @intCast(expr_token.location.line)),
            .end_col = @as(u32, @intCast(expr_token.location.column + expr_token.value.len)),
        };

        const str_id = try self.str_interner.get("go");
        const astdb_token = try self.snapshot.addToken(.kw_go, str_id, span);

        var children = [_]NodeId{expr_node};
        return try self.snapshot.addNode(.go_stmt, astdb_token, astdb_token, &children);
    }

    /// Create a parameter declaration node
    fn createParameterNode(self: *Self, param_token: Token) !NodeId {
        const span = Span{
            .start_byte = @as(u32, @intCast(param_token.location.offset)),
            .end_byte = @as(u32, @intCast(param_token.location.offset + param_token.value.len)),
            .start_line = @as(u32, @intCast(param_token.location.line)),
            .start_col = @as(u32, @intCast(param_token.location.column)),
            .end_line = @as(u32, @intCast(param_token.location.line)),
            .end_col = @as(u32, @intCast(param_token.location.column + param_token.value.len)),
        };

        const str_id = try self.str_interner.get(param_token.value);
        const astdb_token = try self.snapshot.addToken(.identifier, str_id, span);

        return try self.snapshot.addNode(.var_decl, astdb_token, astdb_token, &[_]NodeId{});
    }

    /// Create a return statement node
    fn createReturnNode(self: *Self, tokenizer: *Tokenizer, return_token: Token) !NodeId {
        const span = Span{
            .start_byte = @as(u32, @intCast(return_token.location.offset)),
            .end_byte = @as(u32, @intCast(return_token.location.offset + return_token.value.len)),
            .start_line = @as(u32, @intCast(return_token.location.line)),
            .start_col = @as(u32, @intCast(return_token.location.column)),
            .end_line = @as(u32, @intCast(return_token.location.line)),
            .end_col = @as(u32, @intCast(return_token.location.column + return_token.value.len)),
        };

        const str_id = try self.str_interner.get("return");
        const astdb_token = try self.snapshot.addToken(.kw_return, str_id, span);

        // Look for return value
        var children: std.ArrayList(NodeId) = .empty;
        defer children.deinit();

        // Check next token for return value
        const next_token = tokenizer.nextToken() catch {
            return try self.snapshot.addNode(.return_stmt, astdb_token, astdb_token, &[_]NodeId{});
        };

        if (next_token.type == .integer) {
            const value_node = try self.createNodeFromToken(next_token);
            try children.append(value_node);
        }

        return try self.snapshot.addNode(.return_stmt, astdb_token, astdb_token, children.items);
    }

    /// Create ASTDB node from a single token
    fn createNodeFromToken(self: *Self, token: Token) !NodeId {
        const span = Span{
            .start_byte = @as(u32, @intCast(token.location.offset)),
            .end_byte = @as(u32, @intCast(token.location.offset + token.value.len)),
            .start_line = @as(u32, @intCast(token.location.line)),
            .start_col = @as(u32, @intCast(token.location.column)),
            .end_line = @as(u32, @intCast(token.location.line)),
            .end_col = @as(u32, @intCast(token.location.column + token.value.len)),
        };

        // Intern the token value
        const str_id = try self.str_interner.get(token.value);

        // Map token type to ASTDB token kind
        const token_kind = self.mapTokenType(token.type);
        const astdb_token = try self.snapshot.addToken(token_kind, str_id, span);

        // Map token type to ASTDB node kind
        const node_kind = self.mapTokenToNodeKind(token.type);

        // Create node with no children (leaf node)
        return try self.snapshot.addNode(node_kind, astdb_token, astdb_token, &[_]NodeId{});
    }

    /// Map tokenizer token type to ASTDB token kind
    fn mapTokenType(self: *Self, token_type: TokenType) TokenKind {
        _ = self;
        return switch (token_type) {
            .integer => .int_literal,
            .float => .float_literal,
            .string => .string_literal,
            .identifier => .identifier,
            .func => .kw_func,
            .var_kw => .kw_var,
            .let => .kw_const,
            .if_kw => .kw_if,
            .else_kw => .kw_else,
            .return_kw => .kw_return,
            .struct_kw => .kw_struct,
            .const_kw => .kw_const,
            .package => .kw_package,
            .@"const" => .kw_const,
            .kw_nil => .kw_nil,
            .@"switch" => .kw_switch,
            .kw_case => .kw_case,
            .kw_default => .kw_default,
            .@"defer" => .kw_defer,
            .go => .kw_go,
            .kw_where => .kw_where,
            .comptime_kw => .identifier, // No direct mapping, use identifier
            .with => .identifier,
            .do => .identifier,
            .end => .identifier,
            else => .identifier, // Default fallback
        };
    }

    /// Map token type to appropriate ASTDB node kind
    fn mapTokenToNodeKind(self: *Self, token_type: TokenType) NodeKind {
        _ = self;
        return switch (token_type) {
            .integer => .int_literal,
            .float => .float_literal,
            .string => .string_literal,
            .identifier => .identifier,
            .func => .func_decl,
            .struct_kw => .struct_decl,
            .return_kw => .return_stmt,
            .var_kw, .let, .const_kw => .var_decl,
            .if_kw => .if_stmt,
            .comptime_kw => .block_stmt,
            else => .identifier,
        };
    }
};
