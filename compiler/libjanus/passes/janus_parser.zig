// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Janus Parser - Revolutionary ASTDB Architecture
//!
//! This parser implements the true ASTDB columnar architecture:
//! - Immutable batch commits to columnar storage
//! - Content-addressed nodes with CIDs
//! - Query-optimized semantic database
//! - Profile-aware parsing (:min, :go, :elixir, :full)
//!
//! Built under the Atomic Forge Protocol - every function has a failing test first.

const std = @import("std");
const astdb_core = @import("astdb_core");
const tokenizer = @import("janus_tokenizer.zig");
const bootstrap_s0 = @import("bootstrap_s0");

pub fn setS0Gate(enable: bool) void {
    bootstrap_s0.set(enable);
}

pub fn isS0GateEnabled() bool {
    return bootstrap_s0.isEnabled();
}

pub const ScopedS0Gate = struct {
    guard: bootstrap_s0.Gate.Scoped,

    pub fn init(enable: bool) ScopedS0Gate {
        return .{ .guard = bootstrap_s0.scoped(enable) };
    }

    pub fn deinit(self: *ScopedS0Gate) void {
        self.guard.deinit();
    }
};

// ASTDB types - PUBLIC API
pub const AstDB = astdb_core.AstDB;
pub const ASTDBSystem = astdb_core.AstDB; // Alias for compatibility
pub const CoreSnapshot = astdb_core.Snapshot;
pub const Token = astdb_core.Token;
pub const TokenKind = astdb_core.Token.TokenKind;
pub const NodeKind = astdb_core.AstNode.NodeKind;
pub const StrId = astdb_core.StrId;
pub const Tokenizer = tokenizer.Tokenizer;
pub const NodeId = astdb_core.NodeId;
pub const ParseError = error{UnexpectedToken};

/// Public Snapshot interface for API compatibility - wrapper that manages ASTDB lifecycle
pub const Snapshot = struct {
    core_snapshot: CoreSnapshot,
    astdb_system: *AstDB, // Owned reference to keep ASTDB alive
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Snapshot) void {
        const allocator = self.allocator;
        self.astdb_system.deinit();
        allocator.destroy(self.astdb_system);
        allocator.destroy(self);
    }

    // Delegate methods to core snapshot
    pub fn nodeCount(self: *const Snapshot) u32 {
        return self.core_snapshot.nodeCount();
    }

    pub fn getNode(self: *const Snapshot, node_id: astdb_core.NodeId) ?*const astdb_core.AstNode {
        return self.core_snapshot.getNode(node_id);
    }
};

/// Public Node interface for API compatibility
pub const Node = struct {
    // Legacy node structure for compatibility
    // TODO: Remove when all legacy code is updated to use ASTDB

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Revolutionary ASTDB tokenization result
pub const TokenizationSnapshot = struct {
    token_count: u32,
    token_table: []const Token,

    pub fn deinit(self: *const TokenizationSnapshot) void {
        _ = self; // Tokens are owned by ASTDB unit arena
    }
};

/// Parser struct for API compatibility
pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokens: []const tokenizer.Token,

    pub fn init(allocator: std.mem.Allocator, tokens: []const tokenizer.Token) Parser {
        return Parser{
            .allocator = allocator,
            .tokens = tokens,
        };
    }

    pub fn deinit(self: *Parser) void {
        _ = self; // Nothing to clean up for now
    }

    pub fn enableS0(self: *Parser, enable: bool) void {
        _ = self;
        setS0Gate(enable);
    }

    pub fn parse(self: *Parser) !*Snapshot {
        // Create ASTDB system for parsing - allocate on heap so it persists
        const astdb_system = try self.allocator.create(AstDB);
        errdefer {
            astdb_system.deinit();
            self.allocator.destroy(astdb_system);
        }
        astdb_system.* = try AstDB.init(self.allocator, true);

        // Use placeholder for now - will be replaced by parseWithSource
        const source = "func main() {}"; // TODO: Remove when parseWithSource is used

        // Tokenize into ASTDB format
        const tokenization_result = try tokenizeIntoSnapshot(astdb_system, source);
        _ = tokenization_result;

        // Parse tokens into nodes
        try parseTokensIntoNodes(astdb_system);

        // Create and return snapshot wrapper
        const snapshot = try self.allocator.create(Snapshot);
        snapshot.* = Snapshot{
            .core_snapshot = try astdb_system.createSnapshot(),
            .astdb_system = astdb_system,
            .allocator = self.allocator,
        };

        return snapshot;
    }

    pub fn parseWithSource(self: *Parser, original_source: []const u8) !*Snapshot {
        // Create ASTDB system for parsing - allocate on heap so it persists
        const astdb_system = try self.allocator.create(AstDB);
        errdefer {
            astdb_system.deinit();
            self.allocator.destroy(astdb_system);
        }
        astdb_system.* = try AstDB.init(self.allocator, true);

        // Use the original source instead of placeholder
        const source = original_source;

        // Tokenize into ASTDB format
        const tokenization_result = try tokenizeIntoSnapshot(astdb_system, source);
        _ = tokenization_result;

        // Parse tokens into nodes
        try parseTokensIntoNodes(astdb_system);

        // Create and return snapshot wrapper
        const snapshot = try self.allocator.create(Snapshot);
        snapshot.* = Snapshot{
            .core_snapshot = try astdb_system.createSnapshot(),
            .astdb_system = astdb_system,
            .allocator = self.allocator,
        };

        return snapshot;
    }

    pub fn parseIntoSnapshot(self: *Parser, snapshot: anytype) !void {
        _ = self;
        _ = snapshot;
        // Legacy compatibility method - for now just return success
        // TODO: Implement proper snapshot integration
    }

    pub fn parseIntoAstDB(self: *Parser, astdb_system: *AstDB, filename: []const u8) !Snapshot {
        // Create a compilation unit for this parsing session
        const unit_id = try astdb_system.addUnit(filename, ""); // Empty source for now
        const unit = astdb_system.getUnit(unit_id) orelse return error.UnitCreationFailed;

        // Convert the old tokenizer tokens to ASTDB format
        var astdb_tokens = std.ArrayList(astdb_core.Token).init(unit.arenaAllocator());

        // Handle empty input gracefully
        if (self.tokens.len == 0) {
            // Create an empty token list and empty node list
            unit.tokens = try astdb_tokens.toOwnedSlice(unit.arenaAllocator());
            unit.nodes = &[_]astdb_core.AstNode{};
            const core_snapshot = try astdb_system.createSnapshot();
            return Snapshot{
                .core_snapshot = core_snapshot,
                .astdb_system = astdb_system,
                .allocator = unit.arenaAllocator(),
            };
        }

        for (self.tokens) |old_token| {
            // Special handling for walrus operator := - split into : and =
            if (old_token.type == .colon_equal) {
                // Create colon token
                const colon_token = astdb_core.Token{
                    .kind = .colon,
                    .str = null,
                    .span = astdb_core.SourceSpan{
                        .start = @intCast(old_token.span.start.byte_offset),
                        .end = @intCast(old_token.span.start.byte_offset + 1),
                        .line = old_token.span.start.line,
                        .column = old_token.span.start.column,
                    },
                    .trivia_lo = 0,
                    .trivia_hi = 0,
                };
                try astdb_tokens.append(colon_token);

                // Create assign token
                const assign_token = astdb_core.Token{
                    .kind = .assign,
                    .str = null,
                    .span = astdb_core.SourceSpan{
                        .start = @intCast(old_token.span.start.byte_offset + 1),
                        .end = @intCast(old_token.span.end.byte_offset),
                        .line = old_token.span.start.line,
                        .column = old_token.span.start.column + 1,
                    },
                    .trivia_lo = 0,
                    .trivia_hi = 0,
                };
                try astdb_tokens.append(assign_token);
                continue;
            }

            // Convert token type from old tokenizer to ASTDB format
            const astdb_token_kind = convertOldTokenType(old_token.type);

            // Intern string if it's an identifier or literal
            var str_id: ?astdb_core.StrId = null;
            if (old_token.type == .identifier or old_token.type == .number or old_token.type == .string) {
                str_id = try astdb_system.str_interner.intern(old_token.lexeme);
            }

            // Create ASTDB token
            const astdb_token = astdb_core.Token{
                .kind = astdb_token_kind,
                .str = str_id,
                .span = astdb_core.SourceSpan{
                    .start = @intCast(old_token.span.start.byte_offset),
                    .end = @intCast(old_token.span.end.byte_offset),
                    .line = old_token.span.start.line,
                    .column = old_token.span.start.column,
                },
                .trivia_lo = 0,
                .trivia_hi = 0,
            };

            try astdb_tokens.append(astdb_token);
        }

        // Store tokens in unit
        unit.tokens = astdb_tokens.toOwnedSlice(unit.arenaAllocator());

        // Parse tokens into nodes using the new parser
        var parser_state = ParserState{
            .tokens = unit.tokens,
            .current = 0,
            .unit = unit,
            .allocator = unit.arenaAllocator(),
        };

        try parseCompilationUnit(&parser_state);

        // Create and return snapshot
        const core_snapshot = try astdb_system.createSnapshot();
        return Snapshot{
            .core_snapshot = core_snapshot,
            .astdb_system = astdb_system,
            .allocator = unit.arenaAllocator(),
        };
    }
};

/// Revolutionary ASTDB tokenizer - converts source to columnar token storage
/// This is the steel poured into the mold defined by the test
pub fn tokenizeIntoSnapshot(astdb_system: *AstDB, source: []const u8) !TokenizationSnapshot {
    // Step 1: Create a compilation unit for this source
    const unit_id = try astdb_system.addUnit("temp.jan", source);
    const unit = astdb_system.getUnit(unit_id) orelse return error.UnitCreationFailed;

    // Step 2: Use the existing Janus tokenizer to get tokens
    var janus_tokenizer = tokenizer.Tokenizer.init(unit.arenaAllocator(), source);
    defer janus_tokenizer.deinit();

    const janus_tokens = try janus_tokenizer.tokenize();

    // Step 3: Convert Janus tokens to ASTDB columnar format
    var astdb_tokens = std.ArrayList(Token).init(unit.arenaAllocator());

    for (janus_tokens) |janus_token| {
        // Special handling for walrus operator := - split into : and =
        if (janus_token.type == .colon_equal) {
            // Create colon token
            const colon_token = Token{
                .kind = .colon,
                .str = null,
                .span = astdb_core.SourceSpan{
                    .start = @intCast(janus_token.span.start.byte_offset),
                    .end = @intCast(janus_token.span.start.byte_offset + 1),
                    .line = janus_token.span.start.line,
                    .column = janus_token.span.start.column,
                },
                .trivia_lo = 0,
                .trivia_hi = 0,
            };
            try astdb_tokens.append(colon_token);

            // Create assign token
            const assign_token = Token{
                .kind = .assign,
                .str = null,
                .span = astdb_core.SourceSpan{
                    .start = @intCast(janus_token.span.start.byte_offset + 1),
                    .end = @intCast(janus_token.span.end.byte_offset),
                    .line = janus_token.span.start.line,
                    .column = janus_token.span.start.column + 1,
                },
                .trivia_lo = 0,
                .trivia_hi = 0,
            };
            try astdb_tokens.append(assign_token);
        } else {
            // Convert token type from Janus to ASTDB format
            const astdb_token_kind = convertTokenType(janus_token.type);

            // Intern string if it's an identifier
            var str_id: ?StrId = null;
            if (janus_token.type == .identifier) {
                str_id = try astdb_system.str_interner.intern(janus_token.lexeme);
            }

            // Create ASTDB token with columnar storage
            const astdb_token = Token{
                .kind = astdb_token_kind,
                .str = str_id,
                .span = astdb_core.SourceSpan{
                    .start = @intCast(janus_token.span.start.byte_offset),
                    .end = @intCast(janus_token.span.end.byte_offset),
                    .line = janus_token.span.start.line,
                    .column = janus_token.span.start.column,
                },
                .trivia_lo = 0, // TODO: Implement trivia handling
                .trivia_hi = 0,
            };

            try astdb_tokens.append(astdb_token);
        }
    }

    // Step 4: Store tokens in unit's columnar storage
    unit.tokens = astdb_tokens.toOwnedSlice(unit.arenaAllocator());

    // Step 5: Return snapshot interface
    return TokenizationSnapshot{
        .token_count = @intCast(unit.tokens.len),
        .token_table = unit.tokens,
    };
}

/// Convert old tokenizer token type to ASTDB token kind
fn convertOldTokenType(old_type: tokenizer.TokenType) TokenKind {
    return switch (old_type) {
        .func => .func,
        .let => .let,
        .@"return" => .return_,
        .identifier => .identifier,
        .equal => .assign,
        .equal_equal => .equal_equal,
        .number => .integer_literal,
        .plus => .plus,
        .minus => .minus,
        .star => .star,
        .slash => .slash,
        .left_paren => .left_paren,
        .right_paren => .right_paren,
        .left_brace => .left_brace,
        .right_brace => .right_brace,
        .semicolon => .semicolon,
        .comma => .comma,
        .colon => .colon,
        .string => .string_literal,
        .true => .true_,
        .false => .false_,
        .null => .null_,
        .newline => .newline,
        .eof => .eof,
        else => .invalid,
    };
}

/// Convert Janus tokenizer token type to ASTDB token kind
fn convertTokenType(janus_type: tokenizer.TokenType) TokenKind {
    return switch (janus_type) {
        // Keywords - :min profile (only what exists in janus_tokenizer)
        .func => .func,
        .let => .let,
        .@"var" => .var_,
        .@"if" => .if_,
        .@"else" => .else_,
        .@"for" => .for_,
        .do => .do_,
        .end => .end,
        .@"return" => .return_,
        .@"defer" => .defer_,
        .when => .when,
        .@"and" => .and_,
        .@"or" => .or_,
        .not => .not_,
        .use => .use_,

        // New keywords added to tokenizer
        .@"while" => .while_,
        .match => .match,
        .@"break" => .break_,
        .@"continue" => .continue_,

        // Literals
        .identifier => .identifier,
        .number => .integer_literal,
        .string => .string_literal,
        .true => .true_,
        .false => .false_,
        .null => .null_,

        // Operators
        .plus => .plus,
        .minus => .minus,
        .star => .star,
        .slash => .slash,
        .percent => .percent,
        .equal => .assign, // Use assign for consistency with walrus operator
        .equal_equal => .equal_equal,
        .bang_equal => .not_equal,
        .less => .less,
        .less_equal => .less_equal,
        .greater => .greater,
        .greater_equal => .greater_equal,

        // New operators added to tokenizer
        .match_arrow => .arrow, // Use arrow for now, TODO: add match_arrow to core_astdb
        .pipe => .bitwise_or, // Use bitwise_or for |
        .dot_dot => .range_inclusive, // Use range_inclusive for ..
        .ampersand => .bitwise_and, // Address-of operator (&)
        .question => .question, // Question mark for optional types (i32?)
        .optional_chain => .optional_chain,
        .null_coalesce => .null_coalesce,
        // .bitwise_or token is not generated by tokenizer, pipe maps to bitwise_or in convertTokenType
        .underscore => .identifier, // Treat underscore as identifier for now

        // Punctuation
        .left_paren => .left_paren,
        .right_paren => .right_paren,
        .left_brace => .left_brace,
        .right_brace => .right_brace,
        .left_bracket => .left_bracket,
        .right_bracket => .right_bracket,
        .semicolon => .semicolon,
        .comma => .comma,
        .dot => .dot,
        .colon => .colon,
        .arrow => .arrow,

        // Extended tokens
        .kw_in => .in_,
        .struct_kw => .struct_,
        .type_kw => .type_,

        // Special
        .newline => .newline,
        .eof => .eof,
        .invalid => .invalid,

        // Fallback for unmapped tokens
        else => .invalid,
    };
}

/// Revolutionary ASTDB parser - converts tokens into AST nodes
/// This is the next steel to be poured into the mold
pub fn parseTokensIntoNodes(astdb_system: *AstDB) !void {
    // Get the most recent compilation unit (the one we just tokenized)
    if (astdb_system.units.items.len == 0) return error.NoUnitsToparse;

    const unit_count = astdb_system.units.items.len;
    const unit = astdb_system.units.items[unit_count - 1];

    if (isS0GateEnabled()) {
        try validateS0Tokens(unit);
    }

    // Simple recursive descent parser for :min profile
    var parser_state = ParserState{
        .tokens = unit.tokens,
        .current = 0,
        .unit = unit,
        .allocator = unit.arenaAllocator(),
    };

    // Parse the token stream into nodes
    try parseCompilationUnit(&parser_state);
}

/// Parser state for recursive descent parsing
const ParserState = struct {
    tokens: []const Token,
    current: usize,
    unit: *astdb_core.CompilationUnit,
    allocator: std.mem.Allocator,

    fn peek(self: *ParserState) ?Token {
        if (self.current >= self.tokens.len) return null;
        return self.tokens[self.current];
    }

    fn advance(self: *ParserState) ?Token {
        if (self.current >= self.tokens.len) return null;
        const token = self.tokens[self.current];
        self.current += 1;
        return token;
    }

    fn match(self: *ParserState, kind: TokenKind) bool {
        if (self.peek()) |token| {
            return token.kind == kind;
        }
        return false;
    }

    fn consume(self: *ParserState, kind: TokenKind) !Token {
        if (self.peek()) |token| {
            if (token.kind == kind) {
                return self.advance().?;
            }
        }
        return error.UnexpectedToken;
    }
};

fn validateS0Tokens(unit: *astdb_core.CompilationUnit) !void {
    for (unit.tokens) |token| {
        if (!isTokenAllowedInS0(token.kind)) {
            std.log.err("S0 bootstrap: token kind '{s}' not allowed", .{@tagName(token.kind)});
            return error.S0FeatureNotAllowed;
        }
    }
}

fn isTokenAllowedInS0(kind: TokenKind) bool {
    return switch (kind) {
        .func, .return_, .identifier, .integer_literal, .string_literal, .left_paren, .right_paren, .left_brace, .right_brace, .semicolon, .comma, .newline, .eof => true,
        else => false,
    };
}

/// Parse a compilation unit (top-level)
fn parseCompilationUnit(parser: *ParserState) !void {
    var nodes = std.ArrayList(astdb_core.AstNode).init(parser.allocator);

    // Skip whitespace and newlines
    while (parser.match(.newline)) {
        _ = parser.advance();
    }

    // Track indices of top-level declarations for source_file children
    var top_level_declarations = std.ArrayList(u32).init(parser.allocator);
    defer top_level_declarations.deinit();

    // Parse top-level declarations (these will be children of source_file)
    while (parser.peek() != null and !parser.match(.eof)) {
        if (parser.match(.use_)) {
            const use_node = try parseUseStatement(parser, &nodes);
            const use_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(use_node);
            try top_level_declarations.append(use_index);
        } else if (parser.match(.struct_kw)) {
            const struct_node = try parseStructDeclaration(parser, &nodes);
            const struct_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(struct_node);
            try top_level_declarations.append(struct_index);
        } else if (parser.match(.async_)) {
            // :service profile - async function declaration
            const func_node = try parseFunctionDeclaration(parser, &nodes, true);
            const func_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(func_node);
            try top_level_declarations.append(func_index);
        } else if (parser.match(.func)) {
            const func_node = try parseFunctionDeclaration(parser, &nodes, false);
            const func_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(func_node);
            try top_level_declarations.append(func_index);
        } else if (parser.match(.let)) {
            const let_node = try parseLetStatement(parser, &nodes);
            const let_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(let_node);
            try top_level_declarations.append(let_index);
        } else if (parser.match(.var_)) {
            const var_node = try parseVarStatement(parser, &nodes);
            const var_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(var_node);
            try top_level_declarations.append(var_index);
        } else {
            // Skip unknown tokens for now
            _ = parser.advance();
        }

        // Skip trailing whitespace
        while (parser.match(.newline)) {
            _ = parser.advance();
        }
    }

    // Calculate child indices for source_file node
    // The children should be only the top-level declarations, not their sub-nodes
    const child_lo = if (top_level_declarations.items.len > 0) top_level_declarations.items[0] else @as(u32, @intCast(nodes.items.len));
    const child_hi = @as(u32, @intCast(nodes.items.len));

    // Create source_file node that contains all declarations as children
    const source_file_node = astdb_core.AstNode{
        .kind = .source_file,
        .first_token = @enumFromInt(0),
        .last_token = @enumFromInt(0),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };

    // Add the source_file node as the root (last node)
    try nodes.append(source_file_node);

    // Create edges array for child relationships
    var edges = std.ArrayList(astdb_core.NodeId).init(parser.allocator);

    // Add all nodes as potential children (edges are just node indices)
    for (0..nodes.items.len) |i| {
        try edges.append(@enumFromInt(i));
    }

    // Store nodes and edges in the compilation unit
    parser.unit.nodes = nodes.toOwnedSlice(parser.allocator);
    parser.unit.edges = edges.toOwnedSlice(parser.allocator);
}

fn parseStructDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const struct_start_token = parser.current;
    var used_do_end = false;

    // Consume 'struct' keyword
    _ = try parser.consume(.struct_kw);

    // Parse struct name (identifier)
    _ = try parser.consume(.identifier);
    const name_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    try nodes.append(name_node);

    // Check if this is do/end form or brace form
    if (parser.match(.do_)) {
        _ = try parser.consume(.do_);
        used_do_end = true;
        try parseBlockStatements(parser, nodes);
    } else {
        _ = try parser.consume(.left_brace);
        try parseBlockStatements(parser, nodes);
        _ = try parser.consume(.right_brace);
    }

    // Parse fields: identifier : type ,?
    const fields_start = nodes.items.len;
    while (!parser.match(.right_brace) and parser.peek() != null) {
        // Parse field name (identifier)
        if (parser.match(.identifier)) {
            const field_name_node = astdb_core.AstNode{
                .kind = .identifier,
                .first_token = @enumFromInt(parser.current - 1),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = 0,
                .child_hi = 0,
            };
            try nodes.append(field_name_node);

            // Consume ':'
            _ = try parser.consume(.colon);

            // Parse type (identifier for primitive like string/i32) or []T array type
            if (parser.match(.left_bracket)) {
                // Parse []T
                _ = try parser.consume(.left_bracket);
                _ = try parser.consume(.right_bracket);
                _ = try parser.consume(.identifier);
                const inner_type = astdb_core.AstNode{
                    .kind = .primitive_type,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                const arr_child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(inner_type);
                const arr_child_hi = @as(u32, @intCast(nodes.items.len));
                const array_type = astdb_core.AstNode{
                    .kind = .array_type,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = arr_child_lo,
                    .child_hi = arr_child_hi,
                };
                try nodes.append(array_type);
            } else {
                _ = try parser.consume(.identifier);
                const type_node = astdb_core.AstNode{
                    .kind = .primitive_type,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(type_node);
            }

            // Optional comma
            if (parser.match(.comma)) {
                _ = parser.advance(); // consume comma
            }
        } else {
            // Skip unexpected tokens in field parsing
            _ = parser.advance();
        }
    }

    // Consume '}'
    _ = try parser.consume(.right_brace);

    // Create struct declaration node
    const struct_node = astdb_core.AstNode{
        .kind = .struct_decl,
        .first_token = @enumFromInt(struct_start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = @intCast(fields_start),
        .child_hi = @intCast(nodes.items.len),
    };

    return struct_node;
}

/// Parse use statement: use module.path
fn parseUseStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    _ = try parser.consume(.use_);

    // Parse module path: identifier ( . identifier )*
    var path_nodes = std.ArrayList(astdb_core.AstNode).init(parser.allocator);
    defer path_nodes.deinit();

    // Parse first identifier
    if (parser.peek()) |token| {
        if (token.kind == .identifier) {
            const id_node = astdb_core.AstNode{
                .kind = .identifier,
                .first_token = @enumFromInt(parser.current),
                .last_token = @enumFromInt(parser.current),
                .child_lo = 0,
                .child_hi = 0,
            };
            try path_nodes.append(id_node);
            try nodes.append(id_node);
            _ = parser.advance();
        }
    }

    // Parse additional identifiers after dot
    while (parser.peek()) |token| {
        if (token.kind == .dot) {
            _ = parser.advance(); // consume dot
            if (parser.peek()) |next_token| {
                if (next_token.kind == .identifier) {
                    const id_node = astdb_core.AstNode{
                        .kind = .identifier,
                        .first_token = @enumFromInt(parser.current),
                        .last_token = @enumFromInt(parser.current),
                        .child_lo = 0,
                        .child_hi = 0,
                    };
                    try path_nodes.append(id_node);
                    try nodes.append(id_node);
                    _ = parser.advance();
                }
                break;
            }
        }
        break;
    }

    // Create use statement node
    const use_node = astdb_core.AstNode{
        .kind = .use_stmt,
        .first_token = @enumFromInt(parser.current - path_nodes.items.len * 2 - 1), // Approximate - 'use' + identifiers + dots
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = @intCast(nodes.items.len - path_nodes.items.len),
        .child_hi = @intCast(nodes.items.len),
    };

    return use_node;
}

/// Parse statements inside a block (between { and })
fn parseBlockStatements(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !void {
    // Parse statements until we hit the closing brace
    while (parser.peek() != null and
        !parser.match(.right_brace) and
        !parser.match(.end) and
        !parser.match(.else_) and
        !parser.match(.eof))
    {
        if (parser.match(.return_)) {
            const return_stmt = try parseReturnStatement(parser, nodes);
            try nodes.append(return_stmt);
        } else if (parser.match(.defer_)) {
            const defer_stmt = try parseDeferStatement(parser, nodes);
            try nodes.append(defer_stmt);
        } else if (parser.match(.let)) {
            const let_stmt = try parseLetStatement(parser, nodes);
            try nodes.append(let_stmt);
        } else if (parser.match(.var_)) {
            const var_stmt = try parseVarStatement(parser, nodes);
            try nodes.append(var_stmt);
        } else if (parser.match(.for_)) {
            const for_stmt = try parseForStatement(parser, nodes);
            try nodes.append(for_stmt);
        } else if (parser.match(.identifier)) {
            // Parse full expression starting with identifier (handles method calls, assignments, etc.)
            const expr = try parseExpression(parser, nodes, .none);
            const expr_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(expr);
            const expr_stmt = astdb_core.AstNode{
                .kind = .expr_stmt,
                .first_token = expr.first_token,
                .last_token = expr.last_token,
                .child_lo = expr_index,
                .child_hi = expr_index + 1,
            };
            try nodes.append(expr_stmt);
        } else if (parser.match(.if_)) {
            // Handle if statements
            const if_stmt = try parseIfStatement(parser, nodes);
            try nodes.append(if_stmt);
        } else if (parser.match(.while_)) {
            // Handle while statements in do/end form
            const while_stmt = try parseWhileStatement(parser, nodes);
            try nodes.append(while_stmt);
        } else {
            // Skip unknown tokens for now
            _ = parser.advance();
        }

        // Skip trailing whitespace
        while (parser.match(.newline)) {
            _ = parser.advance();
        }
    }
}

/// Parse a for loop: for x in collection do ... end
fn parseForStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.for_);

    // loop variable
    _ = try parser.consume(.identifier);
    const var_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    try nodes.append(var_node);

    // 'in' expression
    _ = try parser.consume(.in_);
    const iterable = try parseExpression(parser, nodes, .none);
    try nodes.append(iterable);

    // do/end body
    _ = try parser.consume(.do_);
    const body_start = @as(u32, @intCast(nodes.items.len));
    try parseBlockStatements(parser, nodes);
    const body_end = @as(u32, @intCast(nodes.items.len));
    _ = try parser.consume(.end);

    // Build a block node for body
    const block_node = astdb_core.AstNode{
        .kind = .block_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = body_start,
        .child_hi = body_end,
    };
    try nodes.append(block_node);

    return astdb_core.AstNode{
        .kind = .for_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = @intCast(nodes.items.len - 3), // var, iterable, body block appended just now
        .child_hi = @intCast(nodes.items.len),
    };
}

/// Parse anonymous function literal: func(args) -> ret { ... }
fn parseFunctionLiteral(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.func);
    // Parameters
    _ = try parser.consume(.left_paren);
    var params = std.ArrayList(astdb_core.AstNode).init(parser.allocator);
    defer params.deinit();
    while (!parser.match(.right_paren) and parser.peek() != null) {
        if (parser.match(.identifier)) {
            _ = parser.advance();
            const param_node = astdb_core.AstNode{
                .kind = .parameter,
                .first_token = @enumFromInt(parser.current - 1),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = 0,
                .child_hi = 0,
            };
            try nodes.append(param_node);
            if (parser.match(.comma)) _ = parser.advance();
        } else break;
    }
    _ = try parser.consume(.right_paren);
    // Optional return type: '->' type (skip for now)
    if (parser.match(.arrow)) {
        _ = parser.advance();
        _ = try parser.consume(.identifier);
    }
    // Body: brace or do/end
    var used_do_end = false;
    if (parser.match(.left_brace)) {
        // Check if this is do/end form or brace form
        if (parser.match(.do_)) {
            _ = try parser.consume(.do_);
            used_do_end = true;
            try parseBlockStatements(parser, nodes);
        } else {
            _ = try parser.consume(.left_brace);
            try parseBlockStatements(parser, nodes);
            _ = try parser.consume(.right_brace);
        }
    } else {
        _ = try parser.consume(.do_);
        try parseBlockStatements(parser, nodes);
        _ = try parser.consume(.end);
    }
    return astdb_core.AstNode{
        .kind = .func_decl,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = @intCast(nodes.items.len),
    };
}

/// Parse block function literal: { |arg| ... }
fn parseBlockFunctionLiteral(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    var used_do_end = false;
    // Check if this is do/end form or brace form
    if (parser.match(.do_)) {
        _ = try parser.consume(.do_);
        used_do_end = true;
        try parseBlockStatements(parser, nodes);
    } else {
        _ = try parser.consume(.left_brace);
        try parseBlockStatements(parser, nodes);
        _ = try parser.consume(.right_brace);
    }
    // Optional parameters
    if (parser.match(.pipe)) {
        _ = try parser.consume(.pipe);
        while (!parser.match(.pipe)) {
            _ = try parser.consume(.identifier);
            const param_node = astdb_core.AstNode{
                .kind = .parameter,
                .first_token = @enumFromInt(parser.current - 1),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = 0,
                .child_hi = 0,
            };
            try nodes.append(param_node);
            if (parser.match(.comma)) _ = parser.advance();
        }
        _ = try parser.consume(.pipe);
    }
    try parseBlockStatements(parser, nodes);
    _ = try parser.consume(.right_brace);
    return astdb_core.AstNode{
        .kind = .func_decl,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = @intCast(nodes.items.len),
    };
}

/// Parse do-end function literal: do |arg| ... end
fn parseDoFunctionLiteral(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.do_);
    if (parser.match(.pipe)) {
        _ = try parser.consume(.pipe);
        while (!parser.match(.pipe)) {
            _ = try parser.consume(.identifier);
            const param_node = astdb_core.AstNode{
                .kind = .parameter,
                .first_token = @enumFromInt(parser.current - 1),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = 0,
                .child_hi = 0,
            };
            try nodes.append(param_node);
            if (parser.match(.comma)) _ = parser.advance();
        }
        _ = try parser.consume(.pipe);
    }
    try parseBlockStatements(parser, nodes);
    _ = try parser.consume(.end);
    return astdb_core.AstNode{
        .kind = .func_decl,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = @intCast(nodes.items.len),
    };
}

/// Parse a while statement: while (cond) { ... } OR while cond do ... end
fn parseWhileStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.while_);

    var used_do_end = false;

    // Parse condition and body for both forms
    if (parser.match(.left_paren)) {
        _ = try parser.consume(.left_paren);
        const cond = try parseExpression(parser, nodes, .none);
        try nodes.append(cond);
        _ = try parser.consume(.right_paren);
        // Check if this is do/end form or brace form
        if (parser.match(.do_)) {
            _ = try parser.consume(.do_);
            used_do_end = true;
            try parseBlockStatements(parser, nodes);
        } else {
            _ = try parser.consume(.left_brace);
            try parseBlockStatements(parser, nodes);
            _ = try parser.consume(.right_brace);
        }
    } else {
        const cond = try parseExpression(parser, nodes, .none);
        try nodes.append(cond);
        _ = try parser.consume(.do_);
        used_do_end = true;
        try parseBlockStatements(parser, nodes);
        _ = try parser.consume(.end);
    }

    return astdb_core.AstNode{
        .kind = .while_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = @intCast(nodes.items.len - 2), // cond + body
        .child_hi = @intCast(nodes.items.len),
    };
}

/// Parse a function call expression: identifier(arguments)
fn parseCallExpression(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const call_start_token = parser.current;

    // Consume callee identifier
    _ = try parser.consume(.identifier);
    const callee_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    try nodes.append(callee_node);

    // '('
    _ = try parser.consume(.left_paren);

    const child_lo = @as(u32, @intCast(nodes.items.len));

    // Parse comma-separated arguments until ')'
    while (parser.current < parser.tokens.len and parser.tokens[parser.current].kind != .right_paren) {
        // Named argument: identifier ':' expr
        if (parser.match(.identifier)) {
            // Lookahead for ':'
            const save = parser.current;
            _ = parser.advance();
            if (parser.match(.colon)) {
                // Append name identifier node
                const name_node = astdb_core.AstNode{
                    .kind = .identifier,
                    .first_token = @enumFromInt(save),
                    .last_token = @enumFromInt(save),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(name_node);
                _ = parser.advance(); // consume ':'
                // Parse value expression (allow literals/identifier)
                const value_expr = try parsePrimary(parser, nodes);
                try nodes.append(value_expr);
            } else {
                // Positional identifier argument
                const id_node = astdb_core.AstNode{
                    .kind = .identifier,
                    .first_token = @enumFromInt(save),
                    .last_token = @enumFromInt(save),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(id_node);
            }
        } else if (parser.match(.string_literal) or parser.match(.integer_literal) or parser.match(.bool_literal) or parser.match(.true_) or parser.match(.false_)) {
            // Append literal as node with its kind
            const tok = parser.tokens[parser.current];
            _ = parser.advance();
            const lit_kind: astdb_core.AstNode.NodeKind = switch (tok.kind) {
                .string_literal => .string_literal,
                .integer_literal => .integer_literal,
                .true_, .false_, .bool_literal => .bool_literal,
                else => .string_literal,
            };
            const lit_node = astdb_core.AstNode{
                .kind = lit_kind,
                .first_token = @enumFromInt(parser.current - 1),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = 0,
                .child_hi = 0,
            };
            try nodes.append(lit_node);
        } else {
            // Fallback: try parse an expression (e.g., array literal)
            const expr = try parseExpression(parser, nodes, .none);
            try nodes.append(expr);
        }

        if (parser.match(.comma)) {
            _ = parser.advance();
        } else if (parser.tokens[parser.current].kind != .right_paren) {
            // If not a comma or right paren, break to avoid infinite loop
            break;
        }
    }

    // ')'
    _ = try parser.consume(.right_paren);

    const child_hi = @as(u32, @intCast(nodes.items.len));

    return astdb_core.AstNode{
        .kind = .call_expr,
        .first_token = @enumFromInt(call_start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a return statement: return expression;
fn parseReturnStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    // Consume 'return' keyword
    _ = try parser.consume(.return_);

    // Parse the return expression (for now, just handle simple literals)
    const expr_start = @as(u32, @intCast(nodes.items.len));

    if (parser.match(.integer_literal)) {
        _ = parser.advance();
        const literal_node = astdb_core.AstNode{
            .kind = .integer_literal,
            .first_token = @enumFromInt(parser.current - 1),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = 0,
            .child_hi = 0,
        };
        try nodes.append(literal_node);
    }

    const expr_end = @as(u32, @intCast(nodes.items.len));

    // Create return statement node
    const return_node = astdb_core.AstNode{
        .kind = .return_stmt,
        .first_token = @enumFromInt(parser.current - 2), // return token
        .last_token = @enumFromInt(parser.current - 1), // expression token
        .child_lo = expr_start,
        .child_hi = expr_end,
    };

    return return_node;
}

/// Parse a defer statement: defer statement;
/// The deferred statement will be executed at scope exit
fn parseDeferStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const defer_token = parser.current;

    // Consume 'defer' keyword
    _ = try parser.consume(.defer_);

    // Parse the deferred statement (typically a function call)
    const stmt_start = @as(u32, @intCast(nodes.items.len));

    // Parse the statement to defer (usually a call expression)
    if (parser.match(.identifier)) {
        // Check if it's a function call
        const save_pos = parser.current;
        _ = parser.advance(); // consume identifier

        if (parser.match(.left_paren)) {
            // It's a function call - parse it
            parser.current = save_pos; // reset to identifier
            const call_expr = try parseCallExpression(parser, nodes);
            try nodes.append(call_expr);
        } else {
            // Just an identifier expression
            parser.current = save_pos; // reset
            const id_node = astdb_core.AstNode{
                .kind = .identifier,
                .first_token = @enumFromInt(parser.current),
                .last_token = @enumFromInt(parser.current),
                .child_lo = 0,
                .child_hi = 0,
            };
            _ = parser.advance();
            try nodes.append(id_node);
        }
    }

    const stmt_end = @as(u32, @intCast(nodes.items.len));

    // Create defer statement node
    const defer_node = astdb_core.AstNode{
        .kind = .defer_stmt,
        .first_token = @enumFromInt(defer_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = stmt_start,
        .child_hi = stmt_end,
    };

    return defer_node;
}

/// Parse a function declaration: func name() { }
fn parseFunctionDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode), is_async: bool) !astdb_core.AstNode {
    // Consume 'func' keyword (async already consumed if is_async is true)
    var used_do_end = false;
    _ = try parser.consume(.func);

    // Optional function name (allow anonymous functions)
    var has_name = false;
    var name_token_index: usize = 0;
    if (parser.match(.identifier)) {
        _ = try parser.consume(.identifier);
        name_token_index = parser.current - 1;
        has_name = true;
    }

    // Consume '('
    _ = try parser.consume(.left_paren);

    // Parse parameters and collect them
    var parameters = std.ArrayList(astdb_core.AstNode).init(parser.allocator);
    defer parameters.deinit();

    // Parse parameter list
    while (parser.current < parser.tokens.len and
        parser.tokens[parser.current].kind != .right_paren)
    {

        // Parse parameter: name : type
        if (parser.tokens[parser.current].kind == .identifier) {
            // Create parameter node
            const param_node = astdb_core.AstNode{
                .kind = .parameter,
                .first_token = @enumFromInt(parser.current),
                .last_token = @enumFromInt(parser.current),
                .child_lo = 0,
                .child_hi = 0,
            };
            try parameters.append(param_node);

            // Consume parameter name
            _ = parser.advance();

            // Consume ':' if present
            if (parser.current < parser.tokens.len and
                parser.tokens[parser.current].kind == .colon)
            {
                _ = parser.advance();

                // Skip type tokens until comma or right paren
                while (parser.current < parser.tokens.len and
                    parser.tokens[parser.current].kind != .comma and
                    parser.tokens[parser.current].kind != .right_paren)
                {
                    _ = parser.advance();
                }
            }

            // Consume comma if present
            if (parser.current < parser.tokens.len and
                parser.tokens[parser.current].kind == .comma)
            {
                _ = parser.advance();
            }
        } else {
            // Skip unexpected tokens
            _ = parser.advance();
        }
    }

    // Consume ')'
    _ = try parser.consume(.right_paren);

    // Skip return type annotation if present (-> type)
    if (parser.current < parser.tokens.len and
        parser.tokens[parser.current].kind == .arrow)
    {
        parser.current += 1; // skip ->
        // Skip the return type
        while (parser.current < parser.tokens.len and
            parser.tokens[parser.current].kind != .do_ and
            parser.tokens[parser.current].kind != .left_brace)
        {
            parser.current += 1;
        }
    }

    // Handle both 'do' and '{' for function body start
    if (parser.current < parser.tokens.len and
        parser.tokens[parser.current].kind == .do_)
    {
        _ = try parser.consume(.do_);
        used_do_end = true;
        try parseBlockStatements(parser, nodes);
        _ = try parser.consume(.end);
    } else {
        _ = try parser.consume(.left_brace);
        try parseBlockStatements(parser, nodes);
        _ = try parser.consume(.right_brace);
    }

    // Calculate child indices - include name + parameters (body block was appended already)
    const child_lo = @as(u32, @intCast(nodes.items.len));

    // Add name node first for semantic resolution (if present)
    if (has_name) {
        const func_name_node = astdb_core.AstNode{
            .kind = .identifier,
            .first_token = @enumFromInt(name_token_index),
            .last_token = @enumFromInt(name_token_index),
            .child_lo = 0,
            .child_hi = 0,
        };
        try nodes.append(func_name_node);
    }

    // Add parameter nodes
    for (parameters.items) |param_node| {
        try nodes.append(param_node);
    }

    const child_hi = @as(u32, @intCast(nodes.items.len));

    // Create function declaration node with proper child indices
    const func_node = astdb_core.AstNode{
        .kind = if (is_async) .async_func_decl else .func_decl,
        .first_token = @enumFromInt(if (has_name) name_token_index else 0),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };

    return func_node;
}

/// Operator precedence levels for Pratt parser
const Precedence = enum(u8) {
    none = 0,
    assignment = 1, // =
    logical_or = 2, // or
    null_coalesce = 3, // ??
    logical_and = 4, // and
    equality = 5, // == !=
    comparison = 6, // < > <= >=
    range = 7, // .. ..<
    term = 8, // + -
    factor = 9, // * /
    unary = 10, // ! -
    call = 11, // . ()
    primary = 12,
};

/// Get precedence for a token kind
fn getTokenPrecedence(kind: TokenKind) Precedence {
    return switch (kind) {
        .assign, .equal => .assignment,
        .or_ => .logical_or,
        .null_coalesce => .null_coalesce,
        // .bitwise_or token is not generated by tokenizer, pipe maps to bitwise_or in convertTokenType
        .and_ => .logical_and,
        .equal_equal, .not_equal => .equality,
        .greater, .greater_equal, .less, .less_equal => .comparison,
        .range_inclusive, .range_exclusive => .range,
        .plus, .minus => .term,
        .star, .slash => .factor,
        else => .none,
    };
}

/// Parse an expression using Pratt parsing
fn parseExpression(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode), precedence: Precedence) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    // Parse left side (primary expression)
    var left = try parsePrimary(parser, nodes);

    // Handle postfix operators: call, field access, index
    while (parser.peek()) |tok| {
        switch (tok.kind) {
            .left_paren => {
                // Function call: left(args)
                _ = parser.advance(); // consume '('
                const child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(left);

                // Zero or more comma-separated arguments, allow named args: ident ':' expr
                while (parser.peek() != null and !parser.match(.right_paren)) {
                    // Skip newlines between args
                    while (parser.match(.newline)) _ = parser.advance();
                    if (parser.match(.right_paren)) break;
                    // Named argument pattern
                    if (parser.match(.identifier)) {
                        const save = parser.current;
                        _ = parser.advance();
                        if (parser.match(.colon)) {
                            // name
                            const name_node = astdb_core.AstNode{
                                .kind = .identifier,
                                .first_token = @enumFromInt(save),
                                .last_token = @enumFromInt(save),
                                .child_lo = 0,
                                .child_hi = 0,
                            };
                            try nodes.append(name_node);
                            _ = parser.advance(); // consume ':'
                            // value
                            const value_expr = try parseExpression(parser, nodes, .none);
                            try nodes.append(value_expr);
                        } else {
                            // Positional identifier argument
                            const id_node = astdb_core.AstNode{
                                .kind = .identifier,
                                .first_token = @enumFromInt(save),
                                .last_token = @enumFromInt(save),
                                .child_lo = 0,
                                .child_hi = 0,
                            };
                            try nodes.append(id_node);
                        }
                    } else {
                        const arg = try parseExpression(parser, nodes, .none);
                        try nodes.append(arg);
                    }

                    // Optional comma (and allow newlines after comma)
                    if (parser.match(.comma)) {
                        _ = parser.advance();
                        while (parser.match(.newline)) _ = parser.advance();
                    } else if (!parser.match(.right_paren)) {
                        break;
                    }
                }
                // Allow trailing newlines before ')'
                while (parser.match(.newline)) _ = parser.advance();
                if (parser.match(.right_paren)) {
                    _ = parser.advance();
                } else {
                    // Recover: skip until ')' or a token that likely starts next construct
                    while (parser.peek()) |t| {
                        if (t.kind == .right_paren) {
                            _ = parser.advance();
                            break;
                        }
                        if (t.kind == .do_ or t.kind == .left_brace or t.kind == .end or t.kind == .eof) break;
                        _ = parser.advance();
                    }
                }
                const child_hi = @as(u32, @intCast(nodes.items.len));
                left = astdb_core.AstNode{
                    .kind = .call_expr,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            .dot, .optional_chain => {
                // Field access or optional chaining: left.identifier
                // Capture operator token index to preserve '.' vs '?.'
                const op_tok_index = parser.current;
                _ = parser.advance(); // consume '.' or '?.'
                _ = try parser.consume(.identifier);
                const ident_node = astdb_core.AstNode{
                    .kind = .identifier,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                const child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(left);
                try nodes.append(ident_node);
                const child_hi = @as(u32, @intCast(nodes.items.len));
                left = astdb_core.AstNode{
                    .kind = .field_expr,
                    .first_token = @enumFromInt(op_tok_index),
                    .last_token = @enumFromInt(op_tok_index),
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            .left_bracket => {
                // Indexing: left[expr] OR left[range_expr]
                _ = parser.advance(); // consume '['

                // Check if this is a range/slice expression (contains .. or ':')
                var is_range = false;
                var is_slice_colon = false;
                var look_ahead = parser.current;
                while (look_ahead < parser.tokens.len) {
                    const lookahead_tok = parser.tokens[look_ahead];
                    if (lookahead_tok.kind == .range_inclusive or lookahead_tok.kind == .range_exclusive) {
                        is_range = true;
                        break;
                    } else if (lookahead_tok.kind == .colon) {
                        is_slice_colon = true;
                        break;
                    }
                    if (lookahead_tok.kind == .right_bracket) break;
                    look_ahead += 1;
                }

                if (is_range or is_slice_colon) {
                    // Parse range expression: start..end or start.. or ..end
                    const range_start = @as(u32, @intCast(nodes.items.len));
                    try nodes.append(left);

                    // Parse optional start expression (e.g., 0 in 0..3)
                    // Use a higher precedence to avoid consuming the range operator
                    var start_expr: ?astdb_core.AstNode = null;
                    if (parser.peek() != null and
                        !parser.match(.right_bracket))
                    {
                        start_expr = try parseExpression(parser, nodes, .range);
                        try nodes.append(start_expr.?);
                    }

                    // Parse range operator - '..' or ':' slice
                    const current_token = parser.peek() orelse return error.UnexpectedToken;
                    if (current_token.kind == .range_inclusive or current_token.kind == .range_exclusive) {
                        _ = parser.advance(); // consume '..' or '..<'
                    } else if (current_token.kind == .colon) {
                        _ = parser.advance(); // consume ':' slice delimiter
                    } else {
                        return error.UnexpectedToken;
                    }

                    // Parse optional end expression (e.g., 3 in 0..3)
                    var end_expr: ?astdb_core.AstNode = null;
                    if (!parser.match(.right_bracket)) {
                        end_expr = try parseExpression(parser, nodes, .none);
                        try nodes.append(end_expr.?);
                    }

                    _ = try parser.consume(.right_bracket);

                    const range_end = @as(u32, @intCast(nodes.items.len));
                    return astdb_core.AstNode{
                        .kind = .index_expr, // Use index_expr for slice operations
                        .first_token = @enumFromInt(parser.current - 1),
                        .last_token = @enumFromInt(parser.current - 1),
                        .child_lo = range_start,
                        .child_hi = range_end,
                    };
                } else {
                    // Regular indexing: left[expr]
                    const index_expr = try parseExpression(parser, nodes, .none);
                    _ = try parser.consume(.right_bracket);
                    const child_lo = @as(u32, @intCast(nodes.items.len));
                    try nodes.append(left);
                    try nodes.append(index_expr);
                    const child_hi = @as(u32, @intCast(nodes.items.len));
                    left = astdb_core.AstNode{
                        .kind = .index_expr,
                        .first_token = @enumFromInt(parser.current - 1),
                        .last_token = @enumFromInt(parser.current - 1),
                        .child_lo = child_lo,
                        .child_hi = child_hi,
                    };
                }
            },
            else => break,
        }
    }

    // Parse binary operators with precedence
    while (true) {
        const token_opt = parser.peek() orelse break;
        const token = token_opt;
        const token_prec = getTokenPrecedence(token.kind);
        if (@intFromEnum(token_prec) <= @intFromEnum(precedence)) break;

        // Error-handling special form: `expr or do |err| ... end`
        if (token.kind == .or_) {
            var look = parser.current + 1;
            while (look < parser.tokens.len and parser.tokens[look].kind == .newline) look += 1;
            if (look < parser.tokens.len and parser.tokens[look].kind == .do_) {
                // consume 'or'
                _ = parser.advance();
                // skip newlines and consume 'do'
                while (parser.match(.newline)) _ = parser.advance();
                _ = parser.advance(); // 'do'

                // optional parameter |ident|
                if (parser.match(.pipe)) {
                    _ = parser.advance(); // '|'
                    if (parser.match(.identifier)) {
                        const param_ident = astdb_core.AstNode{
                            .kind = .identifier,
                            .first_token = @enumFromInt(parser.current),
                            .last_token = @enumFromInt(parser.current),
                            .child_lo = 0,
                            .child_hi = 0,
                        };
                        _ = parser.advance();
                        try nodes.append(param_ident);
                    }
                    if (parser.match(.pipe)) _ = parser.advance();
                }

                // parse handler body until 'end'
                const handler_lo = @as(u32, @intCast(nodes.items.len));
                try parseBlockStatements(parser, nodes);
                const handler_hi = @as(u32, @intCast(nodes.items.len));
                if (parser.match(.end)) _ = parser.advance();

                const handler_block = astdb_core.AstNode{
                    .kind = .block_stmt,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = handler_lo,
                    .child_hi = handler_hi,
                };

                const child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(left);
                try nodes.append(handler_block);
                const child_hi = @as(u32, @intCast(nodes.items.len));

                left = astdb_core.AstNode{
                    .kind = .binary_expr, // placeholder kind for handler construct
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
                // continue without consuming another operator
                continue;
            }
        }

        // Handle range operators
        if (token.kind == .range_inclusive or token.kind == .range_exclusive) {
            const op_pos = parser.current;
            _ = parser.advance(); // consume range operator
            const right = try parseExpression(parser, nodes, token_prec);

            // Create range expression node
            const child_lo = @as(u32, @intCast(nodes.items.len));
            try nodes.append(left);
            try nodes.append(right);
            const child_hi = @as(u32, @intCast(nodes.items.len));

            left = astdb_core.AstNode{
                .kind = .binary_expr,
                .first_token = @enumFromInt(op_pos),
                .last_token = @enumFromInt(op_pos),
                .child_lo = child_lo,
                .child_hi = child_hi,
            };
            continue;
        }

        const op_pos = parser.current;
        _ = parser.advance(); // consume operator
        const right = try parseExpression(parser, nodes, token_prec);

        // Create binary expression node
        const child_lo = @as(u32, @intCast(nodes.items.len));
        try nodes.append(left);
        try nodes.append(right);
        const child_hi = @as(u32, @intCast(nodes.items.len));

        left = astdb_core.AstNode{
            .kind = .binary_expr,
            .first_token = @enumFromInt(op_pos),
            .last_token = @enumFromInt(op_pos),
            .child_lo = child_lo,
            .child_hi = child_hi,
        };
    }

    return left;
}

fn parseArrayLiteral(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const array_start = parser.current;

    // Consume '['
    _ = try parser.consume(.left_bracket);

    const child_lo = @as(u32, @intCast(nodes.items.len));

    // Parse elements
    while (!parser.match(.right_bracket) and parser.peek() != null) {
        const elem = try parseExpression(parser, nodes, .none);
        try nodes.append(elem);

        // Optional comma
        if (parser.match(.comma)) {
            _ = parser.advance();
        }
    }

    // Consume ']'
    _ = try parser.consume(.right_bracket);

    const child_hi = @as(u32, @intCast(nodes.items.len));

    return astdb_core.AstNode{
        .kind = .array_lit,
        .first_token = @enumFromInt(array_start),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a primary expression (literals, identifiers, parentheses, arrays)
fn parsePrimary(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    if (parser.peek()) |token| {
        // DEBUG: Print token info for troubleshooting
        std.debug.print("DEBUG parsePrimary: processing token kind={s} at position {}\n", .{ @tagName(token.kind), parser.current });

        switch (token.kind) {
            .await_ => {
                // :service profile - await expression
                const await_token = parser.current;
                _ = parser.advance(); // consume 'await'
                const awaited_expr = try parseExpression(parser, nodes, .prefix);

                // Store awaited expression as child
                const child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(awaited_expr);
                const child_hi = @as(u32, @intCast(nodes.items.len));

                return astdb_core.AstNode{
                    .kind = .await_expr,
                    .first_token = @enumFromInt(await_token),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            .func => {
                return try parseFunctionLiteral(parser, nodes);
            },
            .left_brace => {
                return try parseBlockFunctionLiteral(parser, nodes);
            },
            .do_ => {
                return try parseDoFunctionLiteral(parser, nodes);
            },
            .integer_literal => {
                _ = parser.advance();
                return astdb_core.AstNode{
                    .kind = .integer_literal,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
            },
            .string_literal => {
                _ = parser.advance();
                return astdb_core.AstNode{
                    .kind = .string_literal,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
            },
            .true_, .false_ => {
                _ = parser.advance();
                return astdb_core.AstNode{
                    .kind = .bool_literal,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
            },
            .bool_literal => {
                _ = parser.advance();
                return astdb_core.AstNode{
                    .kind = .bool_literal,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
            },
            .null_ => {
                _ = parser.advance();
                return astdb_core.AstNode{
                    .kind = .null_literal,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
            },
            .null_literal => {
                _ = parser.advance();
                return astdb_core.AstNode{
                    .kind = .null_literal,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
            },
            .identifier => {
                // Lookahead for struct literal: Identifier '{'
                const id_index = parser.current;
                var used_do_end = false;
                _ = parser.advance();
                if (parser.match(.left_brace)) {
                    // Consume '{' and parse fields
                    // Check if this is do/end form or brace form
                    if (parser.match(.do_)) {
                        _ = try parser.consume(.do_);
                        used_do_end = true;
                        try parseBlockStatements(parser, nodes);
                    } else {
                        _ = try parser.consume(.left_brace);
                        try parseBlockStatements(parser, nodes);
                        _ = try parser.consume(.right_brace);
                    }
                    const child_lo = @as(u32, @intCast(nodes.items.len));
                    // First child: type identifier
                    const type_ident = astdb_core.AstNode{
                        .kind = .identifier,
                        .first_token = @enumFromInt(id_index),
                        .last_token = @enumFromInt(id_index),
                        .child_lo = 0,
                        .child_hi = 0,
                    };
                    try nodes.append(type_ident);

                    // Parse field initializers: name ':' expr (comma-separated)
                    while (!parser.match(.right_brace) and parser.peek() != null) {
                        _ = try parser.consume(.identifier);
                        const field_name = astdb_core.AstNode{
                            .kind = .identifier,
                            .first_token = @enumFromInt(parser.current - 1),
                            .last_token = @enumFromInt(parser.current - 1),
                            .child_lo = 0,
                            .child_hi = 0,
                        };
                        try nodes.append(field_name);
                        _ = try parser.consume(.colon);
                        const value_expr = try parseExpression(parser, nodes, .none);
                        try nodes.append(value_expr);
                        if (parser.match(.comma)) _ = parser.advance();
                    }
                    _ = try parser.consume(.right_brace);
                    const child_hi = @as(u32, @intCast(nodes.items.len));
                    return astdb_core.AstNode{
                        .kind = .struct_literal,
                        .first_token = @enumFromInt(id_index),
                        .last_token = @enumFromInt(parser.current - 1),
                        .child_lo = child_lo,
                        .child_hi = child_hi,
                    };
                } else {
                    return astdb_core.AstNode{
                        .kind = .identifier,
                        .first_token = @enumFromInt(id_index),
                        .last_token = @enumFromInt(id_index),
                        .child_lo = 0,
                        .child_hi = 0,
                    };
                }
            },
            .left_paren => {
                _ = parser.advance(); // consume '('
                const expr = try parseExpression(parser, nodes, .none);
                _ = try parser.consume(.right_paren);
                return expr;
            },
            .left_bracket => {
                return try parseArrayLiteral(parser, nodes);
            },
            .bitwise_and => {
                // Address-of operator: &expr (more flexible)
                _ = parser.advance(); // consume '&'
                const expr = try parsePrimary(parser, nodes);
                const child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(expr);
                const child_hi = @as(u32, @intCast(nodes.items.len));

                return astdb_core.AstNode{
                    .kind = .unary_expr, // Using unary_expr for address-of
                    .first_token = @enumFromInt(parser.current - 2), // & token
                    .last_token = expr.last_token,
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            .bitwise_or => {
                // Pipe operator: |expr (more flexible)
                _ = parser.advance(); // consume '|'
                const expr = try parsePrimary(parser, nodes);
                const child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(expr);
                const child_hi = @as(u32, @intCast(nodes.items.len));

                return astdb_core.AstNode{
                    .kind = .unary_expr, // Using unary_expr for pipe
                    .first_token = @enumFromInt(parser.current - 2), // | token
                    .last_token = expr.last_token,
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            .invalid => {
                // Tolerate unknown tokens in :min profile
                _ = parser.advance();
                return try parsePrimary(parser, nodes);
            },
            .question => {
                // Question mark for optional types (T?) - parse as unary operator
                _ = parser.advance(); // consume '?'
                const base_type = try parsePrimary(parser, nodes);
                const child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(base_type);
                const child_hi = @as(u32, @intCast(nodes.items.len));

                return astdb_core.AstNode{
                    .kind = .unary_expr, // Using unary_expr for optional type
                    .first_token = @enumFromInt(parser.current - 2), // ? token
                    .last_token = base_type.last_token,
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            .assign => {
                // Assignment operator (=) - should not appear in primary expressions
                // This indicates we're in a statement context, not expression context
                return error.UnexpectedToken;
            },
            else => return error.UnexpectedToken,
        }
    }
    return error.UnexpectedToken;
}

/// Parse a let statement: let name: type = value;
fn parseLetStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    // Consume 'let' keyword
    _ = try parser.consume(.let);

    // Parse identifier (variable name)
    _ = try parser.consume(.identifier);
    const identifier_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };

    // Parse optional type annotation: : type OR walrus operator :=
    var type_node: ?astdb_core.AstNode = null;
    if (parser.match(.colon)) {
        _ = parser.advance(); // consume ':'

        // Check if this is walrus operator (:=) or type annotation (: type)
        if (parser.match(.assign)) {
            // This is walrus operator (:=) - no type annotation
            // The equal will be consumed below
        } else {
            // This is type annotation (: type)
            _ = try parser.consume(.identifier); // For now, treat type as identifier (i32, etc.)
            type_node = astdb_core.AstNode{
                .kind = .primitive_type,
                .first_token = @enumFromInt(parser.current - 1),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = 0,
                .child_hi = 0,
            };
        }
    }

    // Parse initializer: = expression (handles both = and := cases)
    _ = try parser.consume(.assign);
    const expr_node = try parseExpression(parser, nodes, .none);

    // Consume optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    // Calculate child indices - children are added before the let statement node
    const child_lo = @as(u32, @intCast(nodes.items.len));

    // Add child nodes to the nodes list
    try nodes.append(identifier_node);
    if (type_node) |type_n| {
        try nodes.append(type_n);
    }
    try nodes.append(expr_node);

    const child_hi = @as(u32, @intCast(nodes.items.len));

    // Create let statement node with proper child indices
    const let_node = astdb_core.AstNode{
        .kind = .let_stmt,
        .first_token = @enumFromInt(0), // TODO: Track token positions properly
        .last_token = @enumFromInt(0),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };

    return let_node;
}

/// Parse a var statement: var name: type (= value)?
fn parseVarStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    // Consume 'var' keyword
    _ = try parser.consume(.var_);

    // name
    _ = try parser.consume(.identifier);
    const identifier_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };

    // optional ': type'
    var type_node: ?astdb_core.AstNode = null;
    if (parser.match(.colon)) {
        _ = parser.advance();
        _ = try parser.consume(.identifier);
        type_node = astdb_core.AstNode{
            .kind = .primitive_type,
            .first_token = @enumFromInt(parser.current - 1),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = 0,
            .child_hi = 0,
        };
    }

    // optional initializer
    var has_initializer = false;
    var init_node: ?astdb_core.AstNode = null;
    if (parser.match(.assign)) {
        _ = parser.advance();
        init_node = try parseExpression(parser, nodes, .none);
        has_initializer = true;
    }

    // optional semicolon
    if (parser.match(.semicolon)) _ = parser.advance();

    const child_lo = @as(u32, @intCast(nodes.items.len));
    try nodes.append(identifier_node);
    if (type_node) |t| try nodes.append(t);
    if (has_initializer) {
        if (init_node) |e| try nodes.append(e);
    }
    const child_hi = @as(u32, @intCast(nodes.items.len));

    return astdb_core.AstNode{
        .kind = .var_stmt,
        .first_token = @enumFromInt(0),
        .last_token = @enumFromInt(0),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse an if statement: if (condition) { ... } else { ... }
fn parseIfStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const if_start_token = parser.current;

    // Consume 'if' keyword
    _ = try parser.consume(.if_);

    // Two forms supported: (cond) { ... }  OR  cond do ... [else do ...] end
    var condition_node: astdb_core.AstNode = undefined;
    var used_do_end = false;
    if (parser.match(.left_paren)) {
        _ = try parser.consume(.left_paren);
        condition_node = try parseExpression(parser, nodes, .none);
        try nodes.append(condition_node);
        _ = try parser.consume(.right_paren);
        // Check if this is do/end form or brace form
        if (parser.match(.do_)) {
            _ = try parser.consume(.do_);
            used_do_end = true;
            try parseBlockStatements(parser, nodes);
        } else {
            _ = try parser.consume(.left_brace);
            try parseBlockStatements(parser, nodes);
            _ = try parser.consume(.right_brace);
        }
    } else {
        // Parse expression until we hit 'do'
        condition_node = try parseExpression(parser, nodes, .none);
        try nodes.append(condition_node);
        while (parser.match(.newline)) _ = parser.advance();
        if (parser.match(.do_)) {
            _ = parser.advance();
        } // permissive: allow missing 'do' in :min formatting
        used_do_end = true;
        try parseBlockStatements(parser, nodes);
    }

    // Check for else / else if clauses in either form
    var has_else = false;
    if (used_do_end) {
        // Handle chained else if ... do ... segments and optional final else do ...
        while (parser.current < parser.tokens.len and parser.tokens[parser.current].kind == .else_) {
            has_else = true; // we will attach additional bodies
            _ = parser.advance(); // consume 'else'

            if (parser.current < parser.tokens.len and parser.tokens[parser.current].kind == .if_) {
                // else if ... do ...
                _ = parser.consume(.if_) catch return error.UnexpectedToken;
                // Parse condition up to 'do'
                const elseif_cond = try parseExpression(parser, nodes, .none);
                try nodes.append(elseif_cond);
                while (parser.match(.newline)) _ = parser.advance();
                if (parser.match(.do_)) {
                    _ = parser.advance();
                }
                try parseBlockStatements(parser, nodes);
                // Loop continues; no 'end' consumed here
                continue;
            } else {
                // else do ...
                while (parser.match(.newline)) _ = parser.advance();
                if (parser.match(.do_)) {
                    _ = parser.advance();
                }
                try parseBlockStatements(parser, nodes);
                break; // Final else; exit the loop
            }
        }
    } else {
        // Brace form single else { ... }
        if (parser.current < parser.tokens.len and parser.tokens[parser.current].kind == .else_) {
            has_else = true;
            _ = parser.advance();
            // Check if this is do/end form or brace form
            if (parser.match(.do_)) {
                _ = try parser.consume(.do_);
                used_do_end = true;
                try parseBlockStatements(parser, nodes);
            } else {
                _ = try parser.consume(.left_brace);
                try parseBlockStatements(parser, nodes);
                _ = try parser.consume(.right_brace);
            }
        }
    }

    // Finalize block termination for do/end form
    if (used_do_end) {
        _ = try parser.consume(.end);
    }

    // Create if statement node
    const total_children: u32 = @intCast(nodes.items.len);
    const needed: u32 = if (has_else) 3 else 2;
    const child_lo_calc: u32 = if (total_children > needed) total_children - needed else 0;
    const if_node = astdb_core.AstNode{
        .kind = .if_stmt,
        .first_token = @enumFromInt(if_start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo_calc, // approximate: condition + if_body + optional else_body
        .child_hi = total_children,
    };

    return if_node;
}
