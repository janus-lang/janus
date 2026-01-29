// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! ASTDB Region Parser - Task 2.1 (Incremental Specialization)
//!
//! Specialized columnar ASTDB parser for incremental region-based parsing
//! Handles dirty-slice reparses for LSP and incremental compilation
//! Requirements: E-3, E-7, E-8
//!
//! GRANITE-SOLID QUERY PURITY - NO I/O IN QUERY EXECUTION

const std = @import("std");
const core = @import("astdb_core");
const ArrayList = std.array_list.Managed;
const lexer = @import("lexer");

const StrInterner = core.StrInterner;

const AstDB = core.AstDB;
const AstNode = core.AstNode;
const NodeKind = AstNode.NodeKind;
pub const Token = core.Token;
pub const TokenKind = Token.TokenKind;
const Diagnostic = core.Diagnostic;
const DiagCode = Diagnostic.DiagCode;
const Severity = Diagnostic.Severity;
const SourceSpan = core.SourceSpan;

const NodeId = core.NodeId;
const TokenId = core.TokenId;
const DiagId = core.DiagId;
const StrId = core.StrId;
pub const RegionLexer = lexer.RegionLexer;

const ParserError = std.mem.Allocator.Error || error{ParseError};

/// Region parser producing columnar ASTDB output
pub const RegionParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    // Input tokens from lexer
    tokens: []const Token,
    current: u32,

    // Output tables (columnar)
    nodes: ArrayList(AstNode),
    edges: ArrayList(NodeId),
    diagnostics: ArrayList(Diagnostic),

    // String interner for identifiers
    str_interner: *core.StrInterner,

    // Span tracking for LSP
    node_spans: ArrayList(SourceSpan),

    // S0 gating: when true, only a strict subset of constructs are allowed.
    s0_profile: bool = false,

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token, str_interner: *core.StrInterner) Self {
        return Self{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .tokens = tokens,
            .current = 0,
            .nodes = ArrayList(AstNode).init(allocator),
            .edges = ArrayList(NodeId).init(allocator),
            .diagnostics = ArrayList(Diagnostic).init(allocator),
            .str_interner = str_interner,
            .node_spans = ArrayList(SourceSpan).init(allocator),
            .s0_profile = false, // S0 bootstrap gate removed - always disabled
        };
    }

    pub fn enableS0(self: *Self, on: bool) void {
        self.s0_profile = on;
    }

    pub fn deinit(self: *Self) void {
        self.node_spans.deinit();
        self.diagnostics.deinit();
        self.edges.deinit();
        self.nodes.deinit();
        self.arena.deinit();
    }

    /// Parse tokens into ASTDB columnar format
    pub fn parse(self: *Self) ParserError!NodeId {
        return try self.parseSourceFile();
    }

    /// Create ASTDB snapshot from parsed data
    pub fn createSnapshot(self: *Self) !AstDB {
        var db = AstDB.init(self.allocator);

        // Transfer ownership to arena
        const arena_alloc = db.arena.allocator();

        db.nodes = try arena_alloc.dupe(AstNode, self.nodes.items);
        db.edges = try arena_alloc.dupe(NodeId, self.edges.items);
        db.diags = try arena_alloc.dupe(Diagnostic, self.diagnostics.items);

        // Initialize empty tables for now (will be filled by binder)
        db.scopes = &.{};
        db.decls = &.{};
        db.refs = &.{};
        db.cids = try arena_alloc.alloc([32]u8, self.nodes.items.len);

        // Copy tokens from lexer (lossless)
        db.tokens = self.tokens;
        db.trivia = &.{}; // Will be filled by lexer integration

        return db;
    }
    // === PARSING METHODS ===

    fn parseSourceFile(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();
        const child_start = @as(u32, @intCast(self.edges.items.len));

        // Parse top-level items
        while (!self.isAtEnd()) {
            if (self.match(.eof)) break;

            const item = self.parseTopLevelItem() catch |err| switch (err) {
                error.ParseError => {
                    if (self.s0_profile) return err;
                    // Error recovery: skip to next likely top-level item
                    self.synchronize();
                    continue;
                },
                else => return err,
            };

            try self.edges.append(item);
        }

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .source_file,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseTopLevelItem(self: *Self) ParserError!NodeId {
        if (self.s0_profile) {
            if (self.peek().kind != .func) {
                try self.addError(.P0001, "S0: only 'func' declarations are allowed at top level");
                return error.ParseError;
            }
            return try self.parseFuncDecl();
        }
        return switch (self.peek().kind) {
            .func => try self.parseFuncDecl(),
            .struct_ => try self.parseStructDecl(),
            .union_ => try self.parseUnionDecl(),
            .enum_ => try self.parseEnumDecl(),
            .trait => try self.parseTraitDecl(),
            .impl => try self.parseImplDecl(),
            .using => try self.parseUsingDecl(),
            else => {
                try self.addError(.P0001, "Expected top-level declaration");
                return error.ParseError;
            },
        };
    }

    fn parseFuncDecl(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.func, "Expected 'func'");

        _ = try self.consume(.identifier, "Expected function name");

        _ = try self.consume(.left_paren, "Expected '(' after function name");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        // Parse parameters
        if (!self.check(.right_paren)) {
            if (self.s0_profile) {
                try self.addError(.P0001, "S0: parameters are not allowed");
                return error.ParseError;
            }
            try self.edges.append(try self.parseParameter());
            while (self.match(.comma)) {
                try self.edges.append(try self.parseParameter());
            }
        }

        _ = try self.consume(.right_paren, "Expected ')' after parameters");

        // Optional return type
        if (self.match(.arrow)) {
            if (self.s0_profile) {
                try self.addError(.P0001, "S0: return types are not allowed");
                return error.ParseError;
            }
            try self.edges.append(try self.parseType());
        }

        // Function body
        try self.edges.append(try self.parseBlock());

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .func_decl,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseStructDecl(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.struct_, "Expected 'struct'");
        _ = try self.consume(.identifier, "Expected struct name");
        _ = try self.consume(.left_brace, "Expected '{' after struct name");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        // Parse fields
        while (!self.check(.right_brace) and !self.isAtEnd()) {
            try self.edges.append(try self.parseField());

            if (!self.match(.comma)) {
                break;
            }
        }

        _ = try self.consume(.right_brace, "Expected '}' after struct fields");

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .struct_decl,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseUnionDecl(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.union_, "Expected 'union'");
        _ = try self.consume(.identifier, "Expected union name");
        _ = try self.consume(.left_brace, "Expected '{' after union name");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        while (!self.check(.right_brace) and !self.isAtEnd()) {
            try self.edges.append(try self.parseVariant());

            if (!self.match(.comma)) {
                break;
            }
        }

        _ = try self.consume(.right_brace, "Expected '}' after union variants");

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .union_decl,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseEnumDecl(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.enum_, "Expected 'enum'");
        _ = try self.consume(.identifier, "Expected enum name");
        _ = try self.consume(.left_brace, "Expected '{' after enum name");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        while (!self.check(.right_brace) and !self.isAtEnd()) {
            try self.edges.append(try self.parseVariant());

            if (!self.match(.comma)) {
                break;
            }
        }

        _ = try self.consume(.right_brace, "Expected '}' after enum variants");

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .enum_decl,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseTraitDecl(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.trait, "Expected 'trait'");
        _ = try self.consume(.identifier, "Expected trait name");
        _ = try self.consume(.left_brace, "Expected '{' after trait name");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        // Parse trait methods (function signatures)
        while (!self.check(.right_brace) and !self.isAtEnd()) {
            try self.edges.append(try self.parseFuncDecl());
        }

        _ = try self.consume(.right_brace, "Expected '}' after trait methods");

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .trait_decl,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }
    fn parseImplDecl(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.impl, "Expected 'impl'");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        // Parse trait name
        try self.edges.append(try self.parseType());

        _ = try self.consume(.left_brace, "Expected '{' after impl declaration");

        // Parse implementation methods
        while (!self.check(.right_brace) and !self.isAtEnd()) {
            try self.edges.append(try self.parseFuncDecl());
        }

        _ = try self.consume(.right_brace, "Expected '}' after impl methods");

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .impl_decl,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseUsingDecl(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.using, "Expected 'using'");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        // Parse module path
        try self.edges.append(try self.parseExpression());

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .using_decl,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseParameter(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.identifier, "Expected parameter name");
        _ = try self.consume(.colon, "Expected ':' after parameter name");

        const child_start = @as(u32, @intCast(self.edges.items.len));
        try self.edges.append(try self.parseType());
        const child_end = @as(u32, @intCast(self.edges.items.len));

        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .parameter,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseField(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.identifier, "Expected field name");
        _ = try self.consume(.colon, "Expected ':' after field name");

        const child_start = @as(u32, @intCast(self.edges.items.len));
        try self.edges.append(try self.parseType());
        const child_end = @as(u32, @intCast(self.edges.items.len));

        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .field,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseVariant(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.identifier, "Expected variant name");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        // Optional associated data - tuple or struct payload
        if (self.match(.left_paren)) {
            // Tuple payload: Variant(Type1, Type2)
            if (!self.check(.right_paren)) {
                try self.edges.append(try self.parseType());

                while (self.match(.comma)) {
                    try self.edges.append(try self.parseType());
                }
            }

            _ = try self.consume(.right_paren, "Expected ')' after variant data");
        } else if (self.match(.left_brace)) {
            // Struct payload: Variant { field1: Type1, field2: Type2 }
            if (!self.check(.right_brace)) {
                try self.edges.append(try self.parseField());

                while (self.match(.comma)) {
                    if (self.check(.right_brace)) break; // Allow trailing comma
                    try self.edges.append(try self.parseField());
                }
            }

            _ = try self.consume(.right_brace, "Expected '}' after struct variant fields");
        }

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .variant,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }
    fn parseType(self: *Self) ParserError!NodeId {
        return switch (self.peek().kind) {
            .identifier => try self.parseNamedType(),
            .star => try self.parsePointerType(),
            .left_bracket => try self.parseArrayOrSliceType(),
            else => {
                try self.addError(.P0002, "Expected type");
                return error.ParseError;
            },
        };
    }

    fn parseNamedType(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.identifier, "Expected type name");

        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .named_type,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = 0,
            .child_hi = 0,
        });
    }

    fn parsePointerType(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.star, "Expected '*'");

        const child_start = @as(u32, @intCast(self.edges.items.len));
        try self.edges.append(try self.parseType());
        const child_end = @as(u32, @intCast(self.edges.items.len));

        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .pointer_type,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseArrayOrSliceType(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.left_bracket, "Expected '['");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        if (self.check(.right_bracket)) {
            // Slice type []T
            _ = try self.consume(.right_bracket, "Expected ']'");
            try self.edges.append(try self.parseType());

            const child_end = @as(u32, @intCast(self.edges.items.len));
            const end_token = self.previousToken();

            return try self.addNode(.{
                .kind = .slice_type,
                .first_token = start_token,
                .last_token = end_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        } else {
            // Array type [N]T
            try self.edges.append(try self.parseExpression()); // size
            _ = try self.consume(.right_bracket, "Expected ']'");
            try self.edges.append(try self.parseType()); // element type

            const child_end = @as(u32, @intCast(self.edges.items.len));
            const end_token = self.previousToken();

            return try self.addNode(.{
                .kind = .array_type,
                .first_token = start_token,
                .last_token = end_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        }
    }

    fn parseBlock(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.left_brace, "Expected '{'");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        while (!self.check(.right_brace) and !self.isAtEnd()) {
            try self.edges.append(try self.parseStatement());
        }

        _ = try self.consume(.right_brace, "Expected '}'");

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .block_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }
    fn parseStatement(self: *Self) ParserError!NodeId {
        if (self.s0_profile) {
            // S0: only return and expression statements; no nested blocks
            const kind = self.peek().kind;
            switch (kind) {
                .return_ => return try self.parseReturnStmt(),
                else => {
                    if (!isS0ExpressionStartToken(kind)) {
                        try self.s0Error(.P0001, "S0: statement using '{s}' is not allowed", .{@tagName(kind)});
                        return error.ParseError;
                    }
                    return try self.parseExprStmt();
                },
            }
        }
        return switch (self.peek().kind) {
            .let => try self.parseLetStmt(),
            .var_ => try self.parseVarStmt(),
            .const_ => try self.parseConstStmt(),
            .if_ => try self.parseIfStmt(),
            .while_ => try self.parseWhileStmt(),
            .for_ => try self.parseForStmt(),
            .return_ => try self.parseReturnStmt(),
            .break_ => try self.parseBreakStmt(),
            .continue_ => try self.parseContinueStmt(),
            .left_brace => try self.parseBlock(),
            else => try self.parseExprStmt(),
        };
    }

    fn parseLetStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.let, "Expected 'let'");
        _ = try self.consume(.identifier, "Expected variable name");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        // Handle type annotation with colon (but not walrus operator)
        if (self.peek().kind == .colon and self.peekNext().kind != .assign) {
            _ = try self.consume(.colon, "Expected ':'");
            try self.edges.append(try self.parseType());
        }

        // Handle assignment - both = and :=
        if (self.match(.assign)) {
            // Simple assignment: let x = value
            try self.edges.append(try self.parseExpression());
        } else if (self.peek().kind == .colon and self.peekNext().kind == .assign) {
            // Walrus operator: let x := value
            _ = try self.consume(.colon, "Expected ':'");
            _ = try self.consume(.assign, "Expected '=' after ':'");
            try self.edges.append(try self.parseExpression());
        }

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .let_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseVarStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.var_, "Expected 'var'");
        _ = try self.consume(.identifier, "Expected variable name");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        if (self.match(.colon)) {
            try self.edges.append(try self.parseType());
        }

        if (self.match(.assign)) {
            try self.edges.append(try self.parseExpression());
        }

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .var_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseConstStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.const_, "Expected 'const'");
        _ = try self.consume(.identifier, "Expected constant name");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        if (self.match(.colon)) {
            try self.edges.append(try self.parseType());
        }

        _ = try self.consume(.assign, "Expected '=' after constant declaration");
        try self.edges.append(try self.parseExpression());

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .const_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }
    fn parseIfStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.if_, "Expected 'if'");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        try self.edges.append(try self.parseExpression()); // condition
        try self.edges.append(try self.parseBlock()); // then block

        if (self.match(.else_)) {
            if (self.check(.if_)) {
                try self.edges.append(try self.parseIfStmt()); // else if
            } else {
                try self.edges.append(try self.parseBlock()); // else block
            }
        }

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .if_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseWhileStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.while_, "Expected 'while'");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        try self.edges.append(try self.parseExpression()); // condition
        try self.edges.append(try self.parseBlock()); // body

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .while_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseForStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.for_, "Expected 'for'");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        _ = try self.consume(.identifier, "Expected loop variable");
        try self.edges.append(try self.parseExpression()); // iterable
        try self.edges.append(try self.parseBlock()); // body

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .for_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseReturnStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.return_, "Expected 'return'");

        const child_start = @as(u32, @intCast(self.edges.items.len));

        if (!self.check(.semicolon) and !self.check(.right_brace)) {
            try self.edges.append(try self.parseExpression());
        }

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .return_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parseBreakStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.break_, "Expected 'break'");

        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .break_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = 0,
            .child_hi = 0,
        });
    }

    fn parseContinueStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.continue_, "Expected 'continue'");

        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .continue_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = 0,
            .child_hi = 0,
        });
    }

    fn parseExprStmt(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        const child_start = @as(u32, @intCast(self.edges.items.len));
        const expr_id = try self.parseExpression();

        if (self.s0_profile and !self.isS0ExprStmtAllowed(expr_id)) {
            try self.s0Error(.P0003, "S0: expression statements must be identifier references or calls", .{});
            return error.ParseError;
        }

        try self.edges.append(expr_id);
        const child_end = @as(u32, @intCast(self.edges.items.len));

        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .expr_stmt,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn isS0ExprStmtAllowed(self: *Self, node_id: NodeId) bool {
        const index = @intFromEnum(node_id);
        if (index >= self.nodes.items.len) return false;
        const node = self.nodes.items[index];
        return switch (node.kind) {
            .identifier => true,
            .call_expr => true,
            .paren_expr => blk: {
                if (node.child_lo >= node.child_hi) break :blk false;
                const child_index = @as(usize, @intCast(node.child_lo));
                if (child_index >= self.edges.items.len) break :blk false;
                const child_id = self.edges.items[child_index];
                break :blk self.isS0ExprStmtAllowed(child_id);
            },
            else => false,
        };
    }

    fn isS0ExpressionStartToken(kind: TokenKind) bool {
        return switch (kind) {
            .identifier, .left_paren => true,
            else => false,
        };
    }

    fn parseExpression(self: *Self) ParserError!NodeId {
        if (self.s0_profile) {
            // S0: restrict to primary, calls, and parenthesized expressions
            return try self.parseRestrictedExpression();
        }
        return try self.parseAssignment();
    }

    fn parseRestrictedExpression(self: *Self) ParserError!NodeId {
        var expr = try self.parsePrimaryRestricted();
        while (true) {
            if (self.match(.left_paren)) {
                expr = try self.finishCall(expr);
            } else {
                break;
            }
        }
        return expr;
    }

    fn parsePrimaryRestricted(self: *Self) ParserError!NodeId {
        return switch (self.peek().kind) {
            .integer_literal => try self.parseIntegerLiteral(),
            .string_literal => try self.parseStringLiteral(),
            .identifier => try self.parseIdentifier(),
            .left_paren => try self.parseParenExpr(),
            else => {
                const kind = self.peek().kind;
                try self.s0Error(.P0003, "S0: expression starting with '{s}' is not allowed", .{@tagName(kind)});
                return error.ParseError;
            },
        };
    }

    fn parseAssignment(self: *Self) ParserError!NodeId {
        const expr = try self.parseLogicalOr();

        if (self.match(.assign) or self.match(.plus_assign) or self.match(.minus_assign) or
            self.match(.star_assign) or self.match(.slash_assign))
        {
            const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed
            const op_token = self.previousToken();

            const child_start = @as(u32, @intCast(self.edges.items.len));
            try self.edges.append(expr);
            try self.edges.append(try self.parseAssignment());
            const child_end = @as(u32, @intCast(self.edges.items.len));

            return try self.addNode(.{
                .kind = .binary_expr,
                .first_token = start_token,
                .last_token = op_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        }

        return expr;
    }

    fn parseLogicalOr(self: *Self) ParserError!NodeId {
        var expr = try self.parseLogicalAnd();

        while (self.match(.logical_or)) {
            const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed
            const op_token = self.previousToken();

            const child_start = @as(u32, @intCast(self.edges.items.len));
            try self.edges.append(expr);
            try self.edges.append(try self.parseLogicalAnd());
            const child_end = @as(u32, @intCast(self.edges.items.len));

            expr = try self.addNode(.{
                .kind = .binary_expr,
                .first_token = start_token,
                .last_token = op_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        }

        return expr;
    }

    fn parseLogicalAnd(self: *Self) ParserError!NodeId {
        var expr = try self.parseEquality();

        while (self.match(.logical_and)) {
            const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed
            const op_token = self.previousToken();

            const child_start = @as(u32, @intCast(self.edges.items.len));
            try self.edges.append(expr);
            try self.edges.append(try self.parseEquality());
            const child_end = @as(u32, @intCast(self.edges.items.len));

            expr = try self.addNode(.{
                .kind = .binary_expr,
                .first_token = start_token,
                .last_token = op_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        }

        return expr;
    }

    fn parseEquality(self: *Self) ParserError!NodeId {
        var expr = try self.parseComparison();

        while (self.match(.equal_equal) or self.match(.not_equal)) {
            const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed
            const op_token = self.previousToken();

            const child_start = @as(u32, @intCast(self.edges.items.len));
            try self.edges.append(expr);
            try self.edges.append(try self.parseComparison());
            const child_end = @as(u32, @intCast(self.edges.items.len));

            expr = try self.addNode(.{
                .kind = .binary_expr,
                .first_token = start_token,
                .last_token = op_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        }

        return expr;
    }
    fn parseComparison(self: *Self) ParserError!NodeId {
        var expr = try self.parseTerm();

        while (self.match(.greater) or self.match(.greater_equal) or
            self.match(.less) or self.match(.less_equal))
        {
            const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed
            const op_token = self.previousToken();

            const child_start = @as(u32, @intCast(self.edges.items.len));
            try self.edges.append(expr);
            try self.edges.append(try self.parseTerm());
            const child_end = @as(u32, @intCast(self.edges.items.len));

            expr = try self.addNode(.{
                .kind = .binary_expr,
                .first_token = start_token,
                .last_token = op_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        }

        return expr;
    }

    fn parseTerm(self: *Self) ParserError!NodeId {
        var expr = try self.parseFactor();

        while (self.match(.minus) or self.match(.plus)) {
            const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed
            const op_token = self.previousToken();

            const child_start = @as(u32, @intCast(self.edges.items.len));
            try self.edges.append(expr);
            try self.edges.append(try self.parseFactor());
            const child_end = @as(u32, @intCast(self.edges.items.len));

            expr = try self.addNode(.{
                .kind = .binary_expr,
                .first_token = start_token,
                .last_token = op_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        }

        return expr;
    }

    fn parseFactor(self: *Self) ParserError!NodeId {
        var expr = try self.parseUnary();

        while (self.match(.slash) or self.match(.star) or self.match(.percent)) {
            const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed
            const op_token = self.previousToken();

            const child_start = @as(u32, @intCast(self.edges.items.len));
            try self.edges.append(expr);
            try self.edges.append(try self.parseUnary());
            const child_end = @as(u32, @intCast(self.edges.items.len));

            expr = try self.addNode(.{
                .kind = .binary_expr,
                .first_token = start_token,
                .last_token = op_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        }

        return expr;
    }

    fn parseUnary(self: *Self) ParserError!NodeId {
        if (self.match(.logical_not) or self.match(.minus) or self.match(.plus)) {
            const start_token = self.previousToken();

            const child_start = @as(u32, @intCast(self.edges.items.len));
            try self.edges.append(try self.parseUnary());
            const child_end = @as(u32, @intCast(self.edges.items.len));

            const end_token = self.previousToken();

            return try self.addNode(.{
                .kind = .unary_expr,
                .first_token = start_token,
                .last_token = end_token,
                .child_lo = child_start,
                .child_hi = child_end,
            });
        }

        return try self.parseCall();
    }

    fn parseCall(self: *Self) ParserError!NodeId {
        var expr = try self.parsePrimary();

        while (true) {
            if (self.match(.left_paren)) {
                expr = try self.finishCall(expr);
            } else if (self.match(.dot)) {
                const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed

                _ = try self.consume(.identifier, "Expected property name after '.'");

                const child_start = @as(u32, @intCast(self.edges.items.len));
                try self.edges.append(expr);
                const child_end = @as(u32, @intCast(self.edges.items.len));

                const end_token = self.previousToken();

                expr = try self.addNode(.{
                    .kind = .field_expr,
                    .first_token = start_token,
                    .last_token = end_token,
                    .child_lo = child_start,
                    .child_hi = child_end,
                });
            } else if (self.match(.left_bracket)) {
                const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed

                const child_start = @as(u32, @intCast(self.edges.items.len));
                try self.edges.append(expr);
                try self.edges.append(try self.parseExpression());
                const child_end = @as(u32, @intCast(self.edges.items.len));

                _ = try self.consume(.right_bracket, "Expected ']' after index");

                const end_token = self.previousToken();

                expr = try self.addNode(.{
                    .kind = .index_expr,
                    .first_token = start_token,
                    .last_token = end_token,
                    .child_lo = child_start,
                    .child_hi = child_end,
                });
            } else {
                break;
            }
        }

        return expr;
    }

    fn finishCall(self: *Self, callee: NodeId) !NodeId {
        const start_token = @as(TokenId, @enumFromInt(0)); // Will be fixed

        const child_start = @as(u32, @intCast(self.edges.items.len));
        try self.edges.append(callee);

        if (!self.check(.right_paren)) {
            if (self.s0_profile) {
                try self.edges.append(try self.parseRestrictedExpression());
                while (self.match(.comma)) {
                    try self.edges.append(try self.parseRestrictedExpression());
                }
            } else {
                try self.edges.append(try self.parseExpression());
                while (self.match(.comma)) {
                    try self.edges.append(try self.parseExpression());
                }
            }
        }

        if (self.s0_profile and self.check(.colon)) {
            try self.s0Error(.P0001, "S0: named arguments are not allowed", .{});
            return error.ParseError;
        }

        _ = try self.consume(.right_paren, "Expected ')' after arguments");

        const child_end = @as(u32, @intCast(self.edges.items.len));
        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .call_expr,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    fn parsePrimary(self: *Self) ParserError!NodeId {
        return switch (self.peek().kind) {
            .bool_literal => try self.parseBoolLiteral(),
            .integer_literal => try self.parseIntegerLiteral(),
            .float_literal => try self.parseFloatLiteral(),
            .string_literal => try self.parseStringLiteral(),
            .char_literal => try self.parseCharLiteral(),
            .identifier => try self.parseIdentifier(),
            .left_paren => try self.parseParenExpr(),
            else => {
                try self.addError(.P0003, "Expected expression");
                return error.ParseError;
            },
        };
    }

    fn parseBoolLiteral(self: *Self) ParserError!NodeId {
        const token = self.currentToken();

        _ = try self.consume(.bool_literal, "Expected boolean literal");

        return try self.addNode(.{
            .kind = .bool_literal,
            .first_token = token,
            .last_token = token,
            .child_lo = 0,
            .child_hi = 0,
        });
    }

    fn parseIntegerLiteral(self: *Self) ParserError!NodeId {
        const token = self.currentToken();

        _ = try self.consume(.integer_literal, "Expected integer literal");

        return try self.addNode(.{
            .kind = .integer_literal,
            .first_token = token,
            .last_token = token,
            .child_lo = 0,
            .child_hi = 0,
        });
    }

    fn parseFloatLiteral(self: *Self) ParserError!NodeId {
        const token = self.currentToken();

        _ = try self.consume(.float_literal, "Expected float literal");

        return try self.addNode(.{
            .kind = .float_literal,
            .first_token = token,
            .last_token = token,
            .child_lo = 0,
            .child_hi = 0,
        });
    }

    fn parseStringLiteral(self: *Self) ParserError!NodeId {
        const token = self.currentToken();

        _ = try self.consume(.string_literal, "Expected string literal");

        return try self.addNode(.{
            .kind = .string_literal,
            .first_token = token,
            .last_token = token,
            .child_lo = 0,
            .child_hi = 0,
        });
    }

    fn parseCharLiteral(self: *Self) ParserError!NodeId {
        const token = self.currentToken();

        _ = try self.consume(.char_literal, "Expected character literal");

        return try self.addNode(.{
            .kind = .char_literal,
            .first_token = token,
            .last_token = token,
            .child_lo = 0,
            .child_hi = 0,
        });
    }

    fn parseIdentifier(self: *Self) ParserError!NodeId {
        const token = self.currentToken();

        _ = try self.consume(.identifier, "Expected identifier");

        return try self.addNode(.{
            .kind = .identifier,
            .first_token = token,
            .last_token = token,
            .child_lo = 0,
            .child_hi = 0,
        });
    }

    fn parseParenExpr(self: *Self) ParserError!NodeId {
        const start_token = self.currentToken();

        _ = try self.consume(.left_paren, "Expected '('");

        const child_start = @as(u32, @intCast(self.edges.items.len));
        const inner_expr = if (self.s0_profile)
            try self.parseRestrictedExpression()
        else
            try self.parseExpression();
        try self.edges.append(inner_expr);
        const child_end = @as(u32, @intCast(self.edges.items.len));

        _ = try self.consume(.right_paren, "Expected ')' after expression");

        const end_token = self.previousToken();

        return try self.addNode(.{
            .kind = .paren_expr,
            .first_token = start_token,
            .last_token = end_token,
            .child_lo = child_start,
            .child_hi = child_end,
        });
    }

    // === UTILITY METHODS ===

    fn addNode(self: *Self, node: AstNode) !NodeId {
        const id = @as(NodeId, @enumFromInt(@as(u32, @intCast(self.nodes.items.len))));
        try self.nodes.append(node);

        // Track span for LSP queries
        const span = SourceSpan{
            .start = self.tokens[@intFromEnum(node.first_token)].span.start,
            .end = self.tokens[@intFromEnum(node.last_token)].span.end,
            .line = self.tokens[@intFromEnum(node.first_token)].span.line,
            .column = self.tokens[@intFromEnum(node.first_token)].span.column,
        };
        try self.node_spans.append(span);

        return id;
    }

    fn addError(self: *Self, code: DiagCode, message: []const u8) ParserError!void {
        const msg_id = try self.str_interner.intern(message);
        const span = if (self.isAtEnd())
            self.tokens[self.tokens.len - 1].span
        else
            self.tokens[self.current].span;

        try self.diagnostics.append(Diagnostic{
            .code = code,
            .severity = .err,
            .span = span,
            .message = msg_id,
            .fix = null,
        });
    }

    fn s0Error(self: *Self, code: DiagCode, comptime fmt: []const u8, args: anytype) ParserError!void {
        var buffer: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buffer, fmt, args) catch unreachable;
        try self.addError(code, msg);
    }

    fn match(self: *Self, kind: TokenKind) bool {
        if (self.check(kind)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn check(self: *Self, kind: TokenKind) bool {
        if (self.isAtEnd()) return false;
        return self.peek().kind == kind;
    }

    fn advance(self: *Self) TokenId {
        if (!self.isAtEnd()) self.current += 1;
        return self.previousToken();
    }

    fn isAtEnd(self: *Self) bool {
        return self.current >= self.tokens.len or self.peek().kind == .eof;
    }

    fn peek(self: *Self) Token {
        if (self.current >= self.tokens.len) {
            return Token{
                .kind = .eof,
                .str = null,
                .span = SourceSpan{ .start = 0, .end = 0, .line = 1, .column = 1 },
                .trivia_lo = 0,
                .trivia_hi = 0,
            };
        }
        return self.tokens[self.current];
    }

    fn peekNext(self: *Self) Token {
        if (self.current + 1 >= self.tokens.len) {
            return Token{
                .kind = .eof,
                .str = null,
                .span = SourceSpan{ .start = 0, .end = 0, .line = 1, .column = 1 },
                .trivia_lo = 0,
                .trivia_hi = 0,
            };
        }
        return self.tokens[self.current + 1];
    }

    fn previous(self: *Self) Token {
        return self.tokens[self.current - 1];
    }

    fn currentToken(self: *Self) TokenId {
        return @enumFromInt(self.current);
    }

    fn previousToken(self: *Self) TokenId {
        return @enumFromInt(if (self.current > 0) self.current - 1 else 0);
    }

    fn consume(self: *Self, kind: TokenKind, message: []const u8) !TokenId {
        if (self.check(kind)) {
            return self.advance();
        }

        try self.addError(.P0001, message);
        return error.ParseError;
    }

    fn synchronize(self: *Self) void {
        _ = self.advance();

        while (!self.isAtEnd()) {
            if (self.previous().kind == .semicolon) return;

            switch (self.peek().kind) {
                .func, .struct_, .union_, .enum_, .trait, .impl, .using, .let, .var_, .const_, .if_, .while_, .for_, .return_ => return,
                else => {},
            }

            _ = self.advance();
        }
    }
};

// Tests
test "RegionParser basic functionality" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    // Create simple tokens for testing
    const tokens = [_]Token{
        .{ .kind = .func, .str = null, .span = .{ .start = 0, .end = 4, .line = 1, .column = 1 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .identifier, .str = try str_interner.intern("main"), .span = .{ .start = 5, .end = 9, .line = 1, .column = 6 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .left_paren, .str = null, .span = .{ .start = 9, .end = 10, .line = 1, .column = 10 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .right_paren, .str = null, .span = .{ .start = 10, .end = 11, .line = 1, .column = 11 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .left_brace, .str = null, .span = .{ .start = 12, .end = 13, .line = 1, .column = 13 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .right_brace, .str = null, .span = .{ .start = 13, .end = 14, .line = 1, .column = 14 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .eof, .str = null, .span = .{ .start = 14, .end = 14, .line = 1, .column = 15 }, .trivia_lo = 0, .trivia_hi = 0 },
    };

    var parser = RegionParser.init(std.testing.allocator, &tokens, &str_interner);
    defer parser.deinit();

    const root = try parser.parse();

    // Should create a source file with one function
    try std.testing.expectEqual(NodeKind.source_file, parser.nodes.items[@intFromEnum(root)].kind);
    try std.testing.expect(parser.nodes.items.len >= 2); // source_file + func_decl + block
}

test "RegionParser error recovery" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    // Invalid tokens that should trigger error recovery
    const tokens = [_]Token{
        .{ .kind = .func, .str = null, .span = .{ .start = 0, .end = 4, .line = 1, .column = 1 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .left_brace, .str = null, .span = .{ .start = 5, .end = 6, .line = 1, .column = 6 }, .trivia_lo = 0, .trivia_hi = 0 }, // Missing name and params
        .{ .kind = .eof, .str = null, .span = .{ .start = 6, .end = 6, .line = 1, .column = 7 }, .trivia_lo = 0, .trivia_hi = 0 },
    };

    var parser = RegionParser.init(std.testing.allocator, &tokens, &str_interner);
    defer parser.deinit();

    _ = parser.parse() catch {}; // Should not crash, even with errors

    // Should have generated diagnostics
    try std.testing.expect(parser.diagnostics.items.len > 0);
}

test "RegionParser immutable snapshots" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    const tokens = [_]Token{
        .{ .kind = .eof, .str = null, .span = .{ .start = 0, .end = 0, .line = 1, .column = 1 }, .trivia_lo = 0, .trivia_hi = 0 },
    };

    var parser = RegionParser.init(std.testing.allocator, &tokens, &str_interner);
    defer parser.deinit();

    _ = try parser.parse();

    var snapshot = try parser.createSnapshot();
    defer snapshot.deinit();

    // Snapshot should be independent of parser state
    try std.testing.expect(snapshot.nodes.len > 0);

    // Modifying parser shouldn't affect snapshot
    parser.nodes.clearAndFree();
    try std.testing.expect(snapshot.nodes.len > 0); // Still has data
}

test "RegionParser enum with struct variant" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    // Test parsing: enum Message { Connected { ip: String, port: u16 } }
    const tokens = [_]Token{
        .{ .kind = .enum_, .str = null, .span = .{ .start = 0, .end = 4, .line = 1, .column = 1 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .identifier, .str = try str_interner.intern("Message"), .span = .{ .start = 5, .end = 12, .line = 1, .column = 6 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .left_brace, .str = null, .span = .{ .start = 13, .end = 14, .line = 1, .column = 14 }, .trivia_lo = 0, .trivia_hi = 0 },
        // Variant: Connected
        .{ .kind = .identifier, .str = try str_interner.intern("Connected"), .span = .{ .start = 19, .end = 28, .line = 2, .column = 5 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .left_brace, .str = null, .span = .{ .start = 29, .end = 30, .line = 2, .column = 15 }, .trivia_lo = 0, .trivia_hi = 0 },
        // Field: ip: String
        .{ .kind = .identifier, .str = try str_interner.intern("ip"), .span = .{ .start = 31, .end = 33, .line = 2, .column = 17 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .colon, .str = null, .span = .{ .start = 33, .end = 34, .line = 2, .column = 19 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .identifier, .str = try str_interner.intern("String"), .span = .{ .start = 35, .end = 41, .line = 2, .column = 21 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .comma, .str = null, .span = .{ .start = 41, .end = 42, .line = 2, .column = 27 }, .trivia_lo = 0, .trivia_hi = 0 },
        // Field: port: u16
        .{ .kind = .identifier, .str = try str_interner.intern("port"), .span = .{ .start = 43, .end = 47, .line = 2, .column = 29 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .colon, .str = null, .span = .{ .start = 47, .end = 48, .line = 2, .column = 33 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .identifier, .str = try str_interner.intern("u16"), .span = .{ .start = 49, .end = 52, .line = 2, .column = 35 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .right_brace, .str = null, .span = .{ .start = 53, .end = 54, .line = 2, .column = 39 }, .trivia_lo = 0, .trivia_hi = 0 },
        // End enum
        .{ .kind = .right_brace, .str = null, .span = .{ .start = 59, .end = 60, .line = 3, .column = 1 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .eof, .str = null, .span = .{ .start = 60, .end = 60, .line = 3, .column = 2 }, .trivia_lo = 0, .trivia_hi = 0 },
    };

    var parser = RegionParser.init(std.testing.allocator, &tokens, &str_interner);
    defer parser.deinit();

    const root = try parser.parse();

    // Verify structure
    try std.testing.expectEqual(NodeKind.source_file, parser.nodes.items[@intFromEnum(root)].kind);

    // Find the enum declaration
    const source_node = parser.nodes.items[@intFromEnum(root)];
    try std.testing.expect(source_node.child_hi > source_node.child_lo);

    const enum_id = parser.edges.items[source_node.child_lo];
    const enum_node = parser.nodes.items[@intFromEnum(enum_id)];
    try std.testing.expectEqual(NodeKind.enum_decl, enum_node.kind);

    // Find the variant
    try std.testing.expect(enum_node.child_hi > enum_node.child_lo);
    const variant_id = parser.edges.items[enum_node.child_lo];
    const variant_node = parser.nodes.items[@intFromEnum(variant_id)];
    try std.testing.expectEqual(NodeKind.variant, variant_node.kind);

    // Variant should have struct payload children (field declarations)
    try std.testing.expect(variant_node.child_hi > variant_node.child_lo);

    // Should have 2 field children (ip and port)
    const field_count = variant_node.child_hi - variant_node.child_lo;
    try std.testing.expectEqual(@as(u32, 2), field_count);
}
