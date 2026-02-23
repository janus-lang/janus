// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Parser - Revolutionary ASTDB Architecture
//! This parser implements the true ASTDB columnar architecture:
//! - Immutable batch commits to columnar storage
//! - Content-addressed nodes with CIDs
//! - Query-optimized semantic database
//! - Profile-aware parsing (:min, :go, :elixir, :npu, :full)
//
//! Built under the Atomic Forge Protocol - every function has a failing test first.

const std = @import("std");
const astdb_core = @import("astdb_core");
const tokenizer = @import("janus_tokenizer");

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
    astdb_system: *AstDB, // Reference to ASTDB
    allocator: std.mem.Allocator,
    owns_astdb: bool = false,

    pub fn deinit(self: *Snapshot) void {
        const allocator = self.allocator;
        if (self.owns_astdb) {
            self.astdb_system.deinit();
            allocator.destroy(self.astdb_system);
        }
        if (self.owns_astdb) {
            allocator.destroy(self);
        }
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

    pub fn init(allocator: std.mem.Allocator) Parser {
        return Parser{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Parser) void {
        _ = self; // Nothing to clean up for now
    }

    /// S0 bootstrap gate has been removed - this is now a no-op for backwards compatibility
    pub fn enableS0(self: *Parser, enable: bool) void {
        _ = self;
        _ = enable;
        // S0 bootstrap gate removed - profile gating now handled by SemanticValidator
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
            .owns_astdb = true,
        };

        return snapshot;
    }

    pub fn parseIntoSnapshot(self: *Parser, snapshot: anytype) !void {
        _ = self;
        _ = snapshot;
        // Legacy compatibility method - for now just return success
        // TODO: Implement proper snapshot integration
    }

    pub fn parseIntoAstDB(self: *Parser, astdb_system: *AstDB, filename: []const u8, source: []const u8) !Snapshot {
        _ = self;

        // Check if a unit already exists for this filename (from test setup)
        // If so, reuse it instead of creating a duplicate
        var unit_id: astdb_core.UnitId = undefined;
        var unit: *astdb_core.CompilationUnit = undefined;

        if (astdb_system.unit_map.get(filename)) |existing_id| {
            // Reuse existing unit
            unit_id = existing_id;
            unit = astdb_system.getUnit(unit_id) orelse return error.UnitCreationFailed;
        } else {
            // Create new unit
            unit_id = try astdb_system.addUnit(filename, source);
            unit = astdb_system.getUnit(unit_id) orelse return error.UnitCreationFailed;
        }

        // Tokenize the source directly (don't rely on self.tokens)
        var janus_tokenizer = tokenizer.Tokenizer.init(unit.arenaAllocator(), source);
        defer janus_tokenizer.deinit();
        const janus_tokens = try janus_tokenizer.tokenize();

        // Convert janus tokens to ASTDB format
        var astdb_tokens = try std.ArrayList(astdb_core.Token).initCapacity(unit.arenaAllocator(), janus_tokens.len);

        for (janus_tokens) |old_token| {
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
                try astdb_tokens.append(unit.arenaAllocator(), colon_token);

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
                try astdb_tokens.append(unit.arenaAllocator(), assign_token);
                continue;
            }

            // Convert token type from old tokenizer to ASTDB format
            const astdb_token_kind = convertTokenType(old_token.type);

            // Intern string if it's an identifier, literal, or underscore (wildcard pattern)
            var str_id: ?astdb_core.StrId = null;
            if (old_token.type == .identifier or old_token.type == .number or old_token.type == .string_literal or old_token.type == .underscore) {
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

            try astdb_tokens.append(unit.arenaAllocator(), astdb_token);
        }

        // Store tokens in unit
        unit.tokens = try astdb_tokens.toOwnedSlice(unit.arenaAllocator());

        // Parse tokens into nodes using the new parser
        var parser_state = ParserState{
            .tokens = unit.tokens,
            .current = 0,
            .unit = unit,
            .allocator = unit.arenaAllocator(),
            .nodes = try std.ArrayList(astdb_core.AstNode).initCapacity(unit.arenaAllocator(), 1024),
            .edges = try std.ArrayList(astdb_core.NodeId).initCapacity(unit.arenaAllocator(), 1024),
        };

        // QUICK FIX: Store error position on parse failure
        parseCompilationUnit(&parser_state) catch |err| {
            // Store error position for LSP (Phase 3.1 Quick Fix)
            if (parser_state.current < unit.tokens.len) {
                const error_token = unit.tokens[parser_state.current];
                // Create a minimal diagnostic with position
                const diag = astdb_core.Diagnostic{
                    .severity = .err,
                    .message = try astdb_system.str_interner.intern("Parse error"),
                    .span = error_token.span,
                    .code = .P0001, // Generic parse error
                    .fix = null,
                };
                var diags_list = try std.ArrayList(astdb_core.Diagnostic).initCapacity(unit.arenaAllocator(), 1);
                try diags_list.append(unit.arenaAllocator(), diag);
                unit.diags = try diags_list.toOwnedSlice(unit.arenaAllocator());
            }
            return err;
        };

        // Create and return snapshot
        const core_snapshot = try astdb_system.createSnapshot();
        return Snapshot{
            .core_snapshot = core_snapshot,
            .astdb_system = astdb_system,
            .allocator = unit.arenaAllocator(),
            .owns_astdb = false,
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
    var astdb_tokens = try std.ArrayList(Token).initCapacity(unit.arenaAllocator(), 0);

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
            try astdb_tokens.append(unit.arenaAllocator(), colon_token);

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
            try astdb_tokens.append(unit.arenaAllocator(), assign_token);
        } else {
            // Convert token type from Janus to ASTDB format
            const astdb_token_kind = convertTokenType(janus_token.type);

            // Intern string if it's an identifier, literal, or underscore (wildcard pattern)
            var str_id: ?StrId = null;
            switch (janus_token.type) {
                .identifier, .string_literal, .number, .true, .false, .underscore => {
                    str_id = try astdb_system.str_interner.intern(janus_token.lexeme);
                },
                else => {},
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

            try astdb_tokens.append(unit.arenaAllocator(), astdb_token);
        }
    }

    // Step 4: Store tokens in unit's columnar storage
    unit.tokens = try astdb_tokens.toOwnedSlice(unit.arenaAllocator());

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
        .float_literal => .float_literal,
        .plus => .plus,
        .minus => .minus,
        .star => .star,
        .star_star => .star_star,
        .slash => .slash,
        .left_paren => .left_paren,
        .right_paren => .right_paren,
        .left_brace => .left_brace,
        .right_brace => .right_brace,
        .semicolon => .semicolon,
        .comma => .comma,
        .colon => .colon,
        .string_literal => .string_literal,
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
        .when => .when,
        .@"and" => .and_,
        .@"or" => .or_,
        .not => .not_,
        .use => .use_,
        .import_ => .import_,
        .extern_ => .extern_,
        .zig_ => .zig_,
        .graft => .use_,
        .using => .using,

        // New keywords added to tokenizer
        .@"while" => .while_,
        .match => .match,
        .@"break" => .break_,
        .@"continue" => .continue_,
        .@"defer" => .defer_,

        // :sovereign profile
        .requires => .requires,
        .ensures => .ensures,
        .invariant => .invariant,
        .ghost => .ghost,

        // :core profile - Error handling
        .error_ => .error_,
        .fail_ => .fail_,
        .catch_ => .catch_,

        // :service profile - Async/await
        .async_ => .async_,
        .await_ => .await_,
        .nursery_ => .nursery_,
        .spawn_ => .spawn_,
        .shared_ => .shared_,
        .select_ => .select_,
        .timeout_ => .timeout_,

        // :go profile - case/default (also used in select)
        .kw_case => .case,
        .kw_default => .default_,

        // Literals
        .identifier => .identifier,
        .number => .integer_literal,
        .float_literal => .float_literal,
        .string_literal => .string_literal,
        .test_ => .test_,
        .true => .true_,
        .false => .false_,
        .null => .null_,

        // Operators
        .plus => .plus,
        .minus => .minus,
        .star => .star,
        .star_star => .star_star,
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
        .pipeline => .pipeline, // Pipeline operator |>
        .dot_dot => .range_inclusive, // Use range_inclusive for ..
        .dot_dot_less => .range_exclusive, // Use range_exclusive for ..<
        .ampersand => .bitwise_and, // Address-of operator ( & )
        .question => .question, // Question mark for optional types (i32?)
        .optional_chain => .optional_chain,
        .null_coalesce => .null_coalesce,
        .colon_equal => .colon_equal, // := walrus operator for :service profile using statements

        // Bitwise
        .bitwise_xor => .bitwise_xor,
        .bitwise_not => .bitwise_not,
        .left_shift => .left_shift,
        .right_shift => .right_shift,

        // Compound assignment
        .plus_equal => .plus_assign,
        .minus_equal => .minus_assign,
        .star_equal => .star_assign,
        .slash_equal => .slash_assign,
        .percent_equal => .percent_assign,
        .ampersand_equal => .ampersand_assign,
        .pipe_equal => .pipe_assign,
        .xor_equal => .xor_assign,
        .left_shift_equal => .left_shift_assign,
        .right_shift_equal => .right_shift_assign,

        // Character literal
        .char_literal => .char_literal,

        // Logical/unary operators
        .exclaim => .exclamation, // Logical NOT / negation pattern

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
        .enum_kw => .enum_,
        .union_kw => .union_,
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

    // Simple recursive descent parser for :min profile
    var parser_state = ParserState{
        .tokens = unit.tokens,
        .current = 0,
        .unit = unit,
        .allocator = unit.arenaAllocator(),
        .nodes = undefined,
        .edges = undefined,
    };
    parser_state.nodes = try std.ArrayList(astdb_core.AstNode).initCapacity(unit.arenaAllocator(), 0);
    parser_state.edges = try std.ArrayList(astdb_core.NodeId).initCapacity(unit.arenaAllocator(), 0);

    // Parse the token stream into nodes
    try parseCompilationUnit(&parser_state);
}

/// Parser state for recursive descent parsing
const ParserState = struct {
    tokens: []const Token,
    current: usize,
    unit: *astdb_core.CompilationUnit,
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(astdb_core.AstNode),
    edges: std.ArrayList(astdb_core.NodeId),

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

/// Parse a compilation unit (top-level)
fn parseCompilationUnit(parser: *ParserState) !void {
    var nodes = &parser.nodes;

    // Skip whitespace and newlines
    while (parser.match(.newline)) {
        _ = parser.advance();
    }

    // Track indices of top-level declarations for source_file children
    var top_level_declarations = try std.ArrayList(u32).initCapacity(parser.allocator, 0);
    defer top_level_declarations.deinit(parser.allocator);

    // Parse top-level declarations (these will be children of source_file)
    while (parser.peek() != null and !parser.match(.eof)) {
        var is_pub = false;
        if (parser.match(.pub_)) {
            _ = parser.advance();
            is_pub = true;
        }

        if (parser.match(.import_)) {
            const import_node = try parseImportStatement(parser, nodes);
            const import_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, import_node);
            try top_level_declarations.append(parser.allocator, import_index);
        } else if (parser.match(.const_)) {
            const const_node = try parseConstDeclaration(parser, nodes);
            const const_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, const_node);
            try top_level_declarations.append(parser.allocator, const_index);
        } else if (parser.match(.graft)) {
            const graft_node = try parseGraftDeclaration(parser, nodes);
            const graft_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, graft_node);
            try top_level_declarations.append(parser.allocator, graft_index);
        } else if (parser.match(.invalid)) {
            const foreign_node = try parseForeignDeclaration(parser, nodes);
            const foreign_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, foreign_node);
            try top_level_declarations.append(parser.allocator, foreign_index);
        } else if (parser.match(.use_)) {
            const use_node = try parseUseStatement(parser, nodes);
            const use_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, use_node);
            try top_level_declarations.append(parser.allocator, use_index);
        } else if (parser.match(.using)) {
            const using_node = try parseUsingStatement(parser, nodes);
            const using_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, using_node);
            try top_level_declarations.append(parser.allocator, using_index);
        } else if (parser.match(.struct_kw)) {
            const struct_node = try parseStructDeclaration(parser, nodes);
            const struct_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, struct_node);
            try top_level_declarations.append(parser.allocator, struct_index);
        } else if (parser.match(.enum_)) {
            const enum_node = try parseEnumDeclaration(parser, nodes);
            const enum_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, enum_node);
            try top_level_declarations.append(parser.allocator, enum_index);
        } else if (parser.match(.union_)) {
            const union_node = try parseUnionDeclaration(parser, nodes);
            const union_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, union_node);
            try top_level_declarations.append(parser.allocator, union_index);
        } else if (parser.match(.error_)) {
            const error_node = try parseErrorDeclaration(parser, nodes);
            const error_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, error_node);
            try top_level_declarations.append(parser.allocator, error_index);
        } else if (parser.match(.extern_)) {
            const extern_node = try parseExternFuncDeclaration(parser, nodes);
            const extern_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, extern_node);
            try top_level_declarations.append(parser.allocator, extern_index);
        } else if (parser.match(.async_)) {
            // :service profile - async function
            _ = parser.advance(); // consume 'async'
            const func_node = try parseFunctionDeclaration(parser, nodes, true);
            const func_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, func_node);
            try top_level_declarations.append(parser.allocator, func_index);
        } else if (parser.match(.func)) {
            const func_node = try parseFunctionDeclaration(parser, nodes, false);
            const func_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, func_node);
            try top_level_declarations.append(parser.allocator, func_index);
        } else if (parser.match(.let)) {
            const let_node = try parseLetStatement(parser);
            const let_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, let_node);
            try top_level_declarations.append(parser.allocator, let_index);
        } else if (parser.match(.var_)) {
            const var_node = try parseVarStatement(parser, nodes);
            const var_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, var_node);
            try top_level_declarations.append(parser.allocator, var_index);
        } else if (parser.match(.test_)) {
            // PROBATIO: Parse test declaration
            const test_node = try parseTestDeclaration(parser, nodes);
            const test_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, test_node);
            try top_level_declarations.append(parser.allocator, test_index);
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
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    for (top_level_declarations.items) |decl_idx| {
        try parser.edges.append(parser.allocator, @enumFromInt(decl_idx));
    }
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    // Create source_file node that contains all declarations as children
    const source_file_node = astdb_core.AstNode{
        .kind = .source_file,
        .first_token = @enumFromInt(0),
        .last_token = @enumFromInt(0),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };

    // Add the source_file node as the root (last node)
    try nodes.append(parser.allocator, source_file_node);

    // Store nodes and edges in the compilation unit
    parser.unit.nodes = try nodes.toOwnedSlice(parser.allocator);
    parser.unit.edges = try parser.edges.toOwnedSlice(parser.allocator);
}

fn parseStructDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const struct_start_token = parser.current;
    var used_do_end = false;

    // Consume 'struct' keyword
    _ = try parser.consume(.struct_kw);

    // Parse struct name (identifier) - Optional for anonymous structs
    if (parser.match(.identifier)) {
        _ = parser.advance();
        const name_node = astdb_core.AstNode{
            .kind = .identifier,
            .first_token = @enumFromInt(parser.current - 1),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = 0,
            .child_hi = 0,
        };
        try nodes.append(parser.allocator, name_node);
    }

    // Check if this is do/end form or brace form
    var dummy_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer dummy_stmts.deinit(parser.allocator);
    if (parser.match(.do_)) {
        _ = try parser.consume(.do_);
        used_do_end = true;
        try parseBlockStatements(parser, nodes, &dummy_stmts);
    } else {
        _ = try parser.consume(.left_brace);
        try parseBlockStatements(parser, nodes, &dummy_stmts);
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
            try nodes.append(parser.allocator, field_name_node);

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
                try nodes.append(parser.allocator, inner_type);
                const arr_child_hi = @as(u32, @intCast(nodes.items.len));
                const array_type = astdb_core.AstNode{
                    .kind = .array_type,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = arr_child_lo,
                    .child_hi = arr_child_hi,
                };
                try nodes.append(parser.allocator, array_type);
            } else {
                _ = try parser.consume(.identifier);
                const type_node = astdb_core.AstNode{
                    .kind = .primitive_type,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(parser.allocator, type_node);
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

/// Parse error declaration: error ErrorType { Variant1, Variant2, ... }
fn parseErrorDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const error_start_token = parser.current;

    // Consume 'error' keyword
    _ = try parser.consume(.error_);

    // Parse error type name (required)
    const name_token = parser.current;
    _ = try parser.consume(.identifier);
    const name_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(name_token),
        .last_token = @enumFromInt(name_token),
        .child_lo = 0,
        .child_hi = 0,
    };
    const name_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, name_node);

    // Consume '{'
    _ = try parser.consume(.left_brace);

    // Parse variants: Variant1, Variant2, ...
    const variants_start = @as(u32, @intCast(nodes.items.len));
    while (!parser.match(.right_brace) and parser.peek() != null) {
        // Skip newlines
        while (parser.match(.newline)) {
            _ = parser.advance();
        }

        // Check for closing brace after newlines
        if (parser.match(.right_brace)) break;

        // Parse variant name
        if (parser.match(.identifier)) {
            const variant_token = parser.current;
            _ = parser.advance();
            const variant_node = astdb_core.AstNode{
                .kind = .variant,
                .first_token = @enumFromInt(variant_token),
                .last_token = @enumFromInt(variant_token),
                .child_lo = 0,
                .child_hi = 0,
            };
            try nodes.append(parser.allocator, variant_node);

            // Optional comma
            if (parser.match(.comma)) {
                _ = parser.advance();
            }

            // Skip newlines after comma
            while (parser.match(.newline)) {
                _ = parser.advance();
            }
        } else {
            // Skip unexpected tokens
            _ = parser.advance();
        }
    }

    // Consume '}'
    _ = try parser.consume(.right_brace);

    // Build edges: name + variants
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.append(parser.allocator, @enumFromInt(name_idx));
    for (variants_start..@as(u32, @intCast(nodes.items.len))) |i| {
        try parser.edges.append(parser.allocator, @enumFromInt(i));
    }
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    // Create error declaration node
    const error_node = astdb_core.AstNode{
        .kind = .error_decl,
        .first_token = @enumFromInt(error_start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };

    return error_node;
}

/// Parse enum declaration: enum Color { Red, Green, Blue }
/// Supports explicit values: enum HttpStatus { Ok = 200, NotFound = 404 }
fn parseEnumDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const enum_start_token = parser.current;

    // Consume 'enum' keyword
    _ = try parser.consume(.enum_);

    // Parse enum type name (required)
    const name_token = parser.current;
    _ = try parser.consume(.identifier);
    const name_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(name_token),
        .last_token = @enumFromInt(name_token),
        .child_lo = 0,
        .child_hi = 0,
    };
    const name_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, name_node);

    // Consume '{'
    _ = try parser.consume(.left_brace);

    // Parse variants: Variant1, Variant2 = 42, ...
    const variants_start = @as(u32, @intCast(nodes.items.len));
    while (!parser.match(.right_brace) and parser.peek() != null) {
        // Skip newlines
        while (parser.match(.newline)) {
            _ = parser.advance();
        }

        // Check for closing brace after newlines
        if (parser.match(.right_brace)) break;

        // Parse variant name
        if (parser.match(.identifier)) {
            const variant_token = parser.current;
            _ = parser.advance();

            // Check for explicit value: = <integer>
            var variant_child_lo: u32 = 0;
            var variant_child_hi: u32 = 0;
            if (parser.match(.assign)) {
                _ = parser.advance(); // consume '='

                // Parse integer literal value
                if (parser.match(.integer_literal)) {
                    const value_token = parser.current;
                    _ = parser.advance();
                    const value_node = astdb_core.AstNode{
                        .kind = .integer_literal,
                        .first_token = @enumFromInt(value_token),
                        .last_token = @enumFromInt(value_token),
                        .child_lo = 0,
                        .child_hi = 0,
                    };
                    const value_idx = @as(u32, @intCast(nodes.items.len));
                    try nodes.append(parser.allocator, value_node);

                    // Create edge from variant to its value
                    variant_child_lo = @intCast(parser.edges.items.len);
                    try parser.edges.append(parser.allocator, @enumFromInt(value_idx));
                    variant_child_hi = @intCast(parser.edges.items.len);
                }
            }

            const variant_node = astdb_core.AstNode{
                .kind = .variant,
                .first_token = @enumFromInt(variant_token),
                .last_token = @enumFromInt(variant_token),
                .child_lo = variant_child_lo,
                .child_hi = variant_child_hi,
            };
            try nodes.append(parser.allocator, variant_node);

            // Optional comma
            if (parser.match(.comma)) {
                _ = parser.advance();
            }

            // Skip newlines after comma
            while (parser.match(.newline)) {
                _ = parser.advance();
            }
        } else {
            // Skip unexpected tokens
            _ = parser.advance();
        }
    }

    // Consume '}'
    _ = try parser.consume(.right_brace);

    // Build edges: name + variants
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.append(parser.allocator, @enumFromInt(name_idx));
    for (variants_start..@as(u32, @intCast(nodes.items.len))) |i| {
        // Only add variant nodes (skip integer_literal value nodes)
        if (nodes.items[i].kind == .variant) {
            try parser.edges.append(parser.allocator, @enumFromInt(i));
        }
    }
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    // Create enum declaration node
    const enum_node = astdb_core.AstNode{
        .kind = .enum_decl,
        .first_token = @enumFromInt(enum_start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };

    return enum_node;
}

/// Parse union declaration: union Option { Some { value: i32 }, None }
/// Produces .union_decl node with edges: [name, variant0, variant1, ...]
/// Variants with payloads have child edges to field (name, type) pairs
fn parseUnionDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const union_start_token = parser.current;

    // Consume 'union' keyword
    _ = try parser.consume(.union_);

    // Parse union type name (required)
    const name_token = parser.current;
    _ = try parser.consume(.identifier);
    const name_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(name_token),
        .last_token = @enumFromInt(name_token),
        .child_lo = 0,
        .child_hi = 0,
    };
    const name_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, name_node);

    // Consume '{'
    _ = try parser.consume(.left_brace);

    // Parse variants: Some { value: i32 }, None, ...
    const variants_start = @as(u32, @intCast(nodes.items.len));
    while (!parser.match(.right_brace) and parser.peek() != null) {
        // Skip newlines
        while (parser.match(.newline)) {
            _ = parser.advance();
        }

        // Check for closing brace after newlines
        if (parser.match(.right_brace)) break;

        // Parse variant name
        if (parser.match(.identifier)) {
            const variant_token = parser.current;
            _ = parser.advance();

            // Check for payload fields: { name: type, ... }
            var variant_child_lo: u32 = 0;
            var variant_child_hi: u32 = 0;
            if (parser.match(.left_brace)) {
                _ = parser.advance(); // consume '{'

                variant_child_lo = @intCast(parser.edges.items.len);

                // Parse field pairs: name: type
                while (!parser.match(.right_brace) and parser.peek() != null) {
                    while (parser.match(.newline)) _ = parser.advance();
                    if (parser.match(.right_brace)) break;

                    // Field name
                    if (!parser.match(.identifier)) return error.UnexpectedToken;
                    const field_name_token = parser.current;
                    _ = parser.advance();
                    const field_name_node = astdb_core.AstNode{
                        .kind = .identifier,
                        .first_token = @enumFromInt(field_name_token),
                        .last_token = @enumFromInt(field_name_token),
                        .child_lo = 0,
                        .child_hi = 0,
                    };
                    const field_name_idx = @as(u32, @intCast(nodes.items.len));
                    try nodes.append(parser.allocator, field_name_node);
                    try parser.edges.append(parser.allocator, @enumFromInt(field_name_idx));

                    // Colon
                    _ = try parser.consume(.colon);

                    // Field type
                    const type_node = try parseType(parser, nodes);
                    const type_idx = @as(u32, @intCast(nodes.items.len));
                    try nodes.append(parser.allocator, type_node);
                    try parser.edges.append(parser.allocator, @enumFromInt(type_idx));

                    // Optional comma
                    if (parser.match(.comma)) {
                        _ = parser.advance();
                    }
                }

                _ = try parser.consume(.right_brace);
                variant_child_hi = @intCast(parser.edges.items.len);
            }

            const variant_node = astdb_core.AstNode{
                .kind = .variant,
                .first_token = @enumFromInt(variant_token),
                .last_token = @enumFromInt(variant_token),
                .child_lo = variant_child_lo,
                .child_hi = variant_child_hi,
            };
            try nodes.append(parser.allocator, variant_node);

            // Optional comma
            if (parser.match(.comma)) {
                _ = parser.advance();
            }

            // Skip newlines after comma
            while (parser.match(.newline)) {
                _ = parser.advance();
            }
        } else {
            // Skip unexpected tokens
            _ = parser.advance();
        }
    }

    // Consume '}'
    _ = try parser.consume(.right_brace);

    // Build edges: name + variants
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.append(parser.allocator, @enumFromInt(name_idx));
    for (variants_start..@as(u32, @intCast(nodes.items.len))) |i| {
        // Only add variant nodes (skip field name/type nodes)
        if (nodes.items[i].kind == .variant) {
            try parser.edges.append(parser.allocator, @enumFromInt(i));
        }
    }
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    // Create union declaration node
    const union_node = astdb_core.AstNode{
        .kind = .union_decl,
        .first_token = @enumFromInt(union_start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };

    return union_node;
}

/// Parse import statement: import module.path;
fn parseImportStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;

    _ = try parser.consume(.import_);

    // Track start of children in edges array
    const edges_start = @as(u32, @intCast(parser.edges.items.len));

    // Parse module path (e.g., std.string)
    // For now, we'll parse it as a sequence of identifiers separated by dots
    _ = try parser.consume(.identifier);
    const first_ident = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    const first_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, first_ident);
    try parser.edges.append(parser.allocator, @enumFromInt(first_idx));

    // Parse remaining path components (e.g., .string in std.string)
    while (parser.match(.dot)) {
        _ = parser.advance(); // consume dot
        _ = try parser.consume(.identifier);
        const ident = astdb_core.AstNode{
            .kind = .identifier,
            .first_token = @enumFromInt(parser.current - 1),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = 0,
            .child_hi = 0,
        };
        const idx = @as(u32, @intCast(nodes.items.len));
        try nodes.append(parser.allocator, ident);
        try parser.edges.append(parser.allocator, @enumFromInt(idx));
    }

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    return astdb_core.AstNode{
        .kind = .import_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = edges_start,
        .child_hi = @as(u32, @intCast(parser.edges.items.len)),
    };
}

/// Parse using statement:
/// - using module.path;  (module import)
/// - using [shared] binding [: type] = open_expr do ... end  (resource management :service profile)
fn parseUsingStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{UnexpectedToken, OutOfMemory}!astdb_core.AstNode {
    const start_token = parser.current;

    _ = try parser.consume(.using);

    // Check if this is resource management form: using [shared] binding = expr do
    // vs module import form: using module.path
    const is_resource_management = blk: {
        // Look ahead: if we see [shared] identifier followed by =, :=, or : (type), it's resource management
        const save_pos = parser.current;
        
        // Skip optional 'shared' keyword
        if (parser.match(.shared_)) {
            _ = parser.advance(); // consume 'shared'
        }
        
        // Now check for identifier
        if (parser.match(.identifier)) {
            _ = parser.advance(); // consume identifier
            // Check for: =  OR  :=  OR  : (type annotation before =)
            // This handles: using file = expr, using file := expr, using file: Type = expr
            // NOTE: .equal from tokenizer is remapped to .assign in post-processing!
            const is_res = parser.match(.assign) or parser.match(.colon_equal) or parser.match(.colon);
            parser.current = save_pos; // restore position
            break :blk is_res;
        }
        
        parser.current = save_pos; // restore position
        break :blk false;
    };

    if (is_resource_management) {
        return try parseUsingResourceStatement(parser, nodes, start_token);
    }

    // Module import form: using module.path;
    const children_start = @as(u32, @intCast(nodes.items.len));

    // Parse module path (e.g., std.core)
    _ = try parser.consume(.identifier);
    const first_ident = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    try nodes.append(parser.allocator, first_ident);

    // Parse remaining path components
    while (parser.match(.dot)) {
        _ = parser.advance(); // consume dot
        _ = try parser.consume(.identifier);
        const ident = astdb_core.AstNode{
            .kind = .identifier,
            .first_token = @enumFromInt(parser.current - 1),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = 0,
            .child_hi = 0,
        };
        try nodes.append(parser.allocator, ident);
    }

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    return astdb_core.AstNode{
        .kind = .using_decl,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = children_start,
        .child_hi = @as(u32, @intCast(nodes.items.len)),
    };
}

/// Parse resource management using statement:
/// using [shared] binding [: type] = open_expr do ... end
/// :service profile feature - deterministic resource cleanup
fn parseUsingResourceStatement(
    parser: *ParserState,
    nodes: *std.ArrayList(astdb_core.AstNode),
    start_token: usize,
) !astdb_core.AstNode {
    // Nodes contain: binding, [type], open_expr, [body statements...]
    // Edges contain: indices to all children for the using statement
    const edges_start = @as(u32, @intCast(parser.edges.items.len));

    // Optional 'shared' keyword
    const is_shared = parser.match(.shared_);
    if (is_shared) {
        _ = parser.advance(); // consume 'shared'
    }

    // Parse binding name
    _ = try parser.consume(.identifier);
    const binding_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    const binding_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, binding_node);
    try parser.edges.append(parser.allocator, @enumFromInt(binding_idx));

    // Optional type annotation: : Type
    // NOTE: Check for `:=` (walrus) - tokenizer may emit : and = as separate tokens!
    if (parser.match(.colon)) {
        // Lookahead: if next is =, this is actually := (walrus), not type annotation
        const is_walrus = parser.tokens.len > parser.current + 1 and 
                          parser.tokens[parser.current + 1].kind == .assign;
        if (is_walrus) {
            // This is := walrus operator, not type annotation
            // Don't consume anything here, let the assignment parsing handle it
        } else {
            // This is actually a type annotation : Type
            _ = parser.advance(); // consume ':'
            // Parse type name (simple identifier for now)
            _ = try parser.consume(.identifier);
            const type_node = astdb_core.AstNode{
                .kind = .identifier, // Using identifier node for type name
                .first_token = @enumFromInt(parser.current - 1),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = 0,
                .child_hi = 0,
            };
            const type_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, type_node);
            try parser.edges.append(parser.allocator, @enumFromInt(type_idx));
        }
    }

    // Assignment operator: = or :=
    // NOTE: .equal from tokenizer is remapped to .assign in post-processing!
    // NOTE: `:=` may be tokenized as separate `:` and `=` tokens!
    if (parser.match(.colon_equal)) {
        _ = parser.advance(); // consume ':=', single token
    } else if (parser.match(.colon) and parser.tokens.len > parser.current + 1 and parser.tokens[parser.current + 1].kind == .assign) {
        // `:=` as two separate tokens
        _ = parser.advance(); // consume ':'
        _ = parser.advance(); // consume '='
    } else {
        _ = try parser.consume(.assign); // consume '='
    }

    // Parse open expression (the resource acquisition)
    const open_expr = try parseExpression(parser, nodes, .assignment);
    const open_expr_idx = @as(u32, @intCast(nodes.items.len - 1)); // Expression was just appended
    try parser.edges.append(parser.allocator, @enumFromInt(open_expr_idx));
    _ = open_expr;

    // Parse 'do' keyword
    _ = try parser.consume(.do_);

    // Parse block body statements - their indices are appended to parser.edges
    try parseBlockStatements(parser, nodes, &parser.edges);
    
    // Consume 'end'
    _ = try parser.consume(.end);

    const edges_end = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = if (is_shared) .using_shared_stmt else .using_resource_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = edges_start,
        .child_hi = edges_end,
    };
}

/// Parse use statement: use module.path OR use zig "path.zig" OR graft alias = origin "module"
fn parseUseStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;

    // Check if this is 'graft' or 'use'
    const is_graft = if (parser.peek()) |t| t.kind == .use_ else false;
    if (!is_graft) {
        // Handle graft keyword
        _ = try parser.consume(.use_); // graft is tokenized as use_ currently
    } else {
        _ = try parser.consume(.use_);
    }

    const children_start = @as(u32, @intCast(nodes.items.len));

    // NEW: Branch 0: use zig "path.zig" - Native Zig module import
    if (parser.match(.zig_)) {
        _ = parser.advance(); // consume 'zig'

        // Expect string literal for path
        _ = try parser.consume(.string_literal);
        const path_node = astdb_core.AstNode{
            .kind = .string_literal,
            .first_token = @enumFromInt(parser.current - 1),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = 0,
            .child_hi = 0,
        };
        try nodes.append(parser.allocator, path_node);

        // Optional semicolon
        if (parser.match(.semicolon)) {
            _ = parser.advance();
        }

        return astdb_core.AstNode{
            .kind = .use_zig,
            .first_token = @enumFromInt(start_token),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = children_start,
            .child_hi = @as(u32, @intCast(nodes.items.len)),
        };
    }

    // Branch 1: graft form - alias = origin "module" [;]
    if (parser.peek()) |t1| {
        if (t1.kind == .identifier) {
            // Lookahead for '=' assign to detect graft form
            if (parser.tokens.len > parser.current + 1 and parser.tokens[parser.current + 1].kind == .assign) {
                // This is graft with alias: graft alias = origin "module"
                const alias_node = astdb_core.AstNode{
                    .kind = .identifier,
                    .first_token = @enumFromInt(parser.current),
                    .last_token = @enumFromInt(parser.current),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(parser.allocator, alias_node);
                _ = parser.advance(); // alias

                // '='
                _ = try parser.consume(.assign);

                // origin identifier (e.g., zig, c, python)
                _ = try parser.consume(.identifier);
                const origin_node = astdb_core.AstNode{
                    .kind = .identifier,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(parser.allocator, origin_node);

                // module string literal
                _ = try parser.consume(.string_literal);
                const mod_node = astdb_core.AstNode{
                    .kind = .string_literal,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(parser.allocator, mod_node);

                // Optional semicolon
                if (parser.match(.semicolon)) {
                    _ = parser.advance();
                }

                return astdb_core.AstNode{
                    .kind = .use_stmt, // Use use_stmt for now, differentiate in semantic analysis
                    .first_token = @enumFromInt(start_token),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = children_start,
                    .child_hi = @as(u32, @intCast(nodes.items.len)),
                };
            }
        }
    }

    // Branch 2: use origin "module" [;] (also applies to graft without alias)
    // Only match this if identifier is followed by string_literal, NOT by dot (path form)
    if (parser.peek()) |t2| {
        if (t2.kind == .identifier) {
            // Lookahead: if next token after identifier is dot, this is path form, not FFI
            if (parser.tokens.len > parser.current + 1 and parser.tokens[parser.current + 1].kind == .dot) {
                // Skip Branch 2, fall through to path form
            } else {
                // origin identifier (e.g., zig, c, python)
                _ = try parser.consume(.identifier);
                const origin_node = astdb_core.AstNode{
                    .kind = .identifier,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(parser.allocator, origin_node);

                // module string literal
                if (parser.match(.string_literal)) {
                _ = parser.advance();
                const mod_node = astdb_core.AstNode{
                    .kind = .string_literal,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(parser.allocator, mod_node);

                // Optional semicolon
                if (parser.match(.semicolon)) {
                    _ = parser.advance();
                }

                return astdb_core.AstNode{
                    .kind = .use_stmt,
                    .first_token = @enumFromInt(start_token),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = children_start,
                    .child_hi = @as(u32, @intCast(nodes.items.len)),
                };
                }
            }
        }
    }

    // Fallback: path form with optional selective imports
    // use module.path OR use module.{item1, item2}
    const edges_start = @as(u32, @intCast(parser.edges.items.len));

    // Parse first identifier (module name)
    if (parser.peek()) |token| {
        if (token.kind == .identifier) {
            const id_node = astdb_core.AstNode{
                .kind = .identifier,
                .first_token = @enumFromInt(parser.current),
                .last_token = @enumFromInt(parser.current),
                .child_lo = 0,
                .child_hi = 0,
            };
            const id_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, id_node);
            try parser.edges.append(parser.allocator, @enumFromInt(id_idx));
            _ = parser.advance();
        }
    }

    // Parse remaining path components until we see .{ for selective imports
    while (parser.match(.dot)) {
        _ = parser.advance(); // consume dot

        // Check for selective import syntax: .{item1, item2}
        if (parser.match(.left_brace)) {
            _ = parser.advance(); // consume {

            // Parse list of selected identifiers
            while (true) {
                // Skip any newlines inside braces
                while (parser.match(.newline)) {
                    _ = parser.advance();
                }

                if (parser.match(.right_brace)) {
                    _ = parser.advance(); // consume }
                    break;
                }

                // Parse identifier
                if (parser.match(.identifier)) {
                    const item_node = astdb_core.AstNode{
                        .kind = .identifier,
                        .first_token = @enumFromInt(parser.current),
                        .last_token = @enumFromInt(parser.current),
                        .child_lo = 0,
                        .child_hi = 0,
                    };
                    const item_idx = @as(u32, @intCast(nodes.items.len));
                    try nodes.append(parser.allocator, item_node);
                    try parser.edges.append(parser.allocator, @enumFromInt(item_idx));
                    _ = parser.advance();
                }

                // Skip comma between items
                if (parser.match(.comma)) {
                    _ = parser.advance();
                }
            }

            // Optional semicolon
            if (parser.match(.semicolon)) {
                _ = parser.advance();
            }

            return astdb_core.AstNode{
                .kind = .use_selective,
                .first_token = @enumFromInt(start_token),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = edges_start,
                .child_hi = @as(u32, @intCast(parser.edges.items.len)),
            };
        }

        // Regular path component
        if (parser.match(.identifier)) {
            const id_node = astdb_core.AstNode{
                .kind = .identifier,
                .first_token = @enumFromInt(parser.current),
                .last_token = @enumFromInt(parser.current),
                .child_lo = 0,
                .child_hi = 0,
            };
            const id_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, id_node);
            try parser.edges.append(parser.allocator, @enumFromInt(id_idx));
            _ = parser.advance();
        } else {
            break;
        }
    }

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    return astdb_core.AstNode{
        .kind = .use_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = edges_start,
        .child_hi = @as(u32, @intCast(parser.edges.items.len)),
    };
}

/// Parse a type expression
/// Types: identifier, [N]T, []T, *T, ?T
/// Parse a type expression, including error union types (T ! E)
fn parseType(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;

    // Parse the primary type (payload type)
    const base_type_idx = @as(u32, @intCast(nodes.items.len));
    const base_type = try parseTypePrimary(parser, nodes);

    // Check for error union: T ! E
    if (parser.match(.exclamation)) {
        _ = parser.advance();

        // Append base type to nodes
        try nodes.append(parser.allocator, base_type);

        // Parse error type
        const error_type = try parseTypePrimary(parser, nodes);
        try nodes.append(parser.allocator, error_type);

        const children_end = @as(u32, @intCast(nodes.items.len));

        return astdb_core.AstNode{
            .kind = .error_union_type,
            .first_token = @enumFromInt(start_token),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = base_type_idx,
            .child_hi = children_end,
        };
    }

    return base_type;
}

/// Parse a primary type (without error union handling)
fn parseTypePrimary(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;

    // Array/Slice Type: [N]T or []T
    if (parser.match(.left_bracket)) {
        _ = parser.advance();

        const children_start = @as(u32, @intCast(nodes.items.len));
        var is_slice = false;

        // Check for size or empty (slice)
        if (parser.match(.right_bracket)) {
            // []T - Slice type (no size expression)
            is_slice = true;
        } else {
            // [N]T - Array type with size
            const size_expr = try parsePrimary(parser, nodes);
            try nodes.append(parser.allocator, size_expr);
        }
        _ = try parser.consume(.right_bracket);

        // Parse element type
        const elem_type = try parseTypePrimary(parser, nodes);
        try nodes.append(parser.allocator, elem_type);

        const children_end = @as(u32, @intCast(nodes.items.len));

        return astdb_core.AstNode{
            .kind = if (is_slice) .slice_type else .array_type,
            .first_token = @enumFromInt(start_token),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = children_start,
            .child_hi = children_end,
        };
    }

    // Pointer Type: *T
    if (parser.match(.star)) {
        _ = parser.advance();
        const children_start = @as(u32, @intCast(nodes.items.len));
        const inner_type = try parseTypePrimary(parser, nodes);
        try nodes.append(parser.allocator, inner_type);
        const children_end = @as(u32, @intCast(nodes.items.len));

        return astdb_core.AstNode{
            .kind = .pointer_type,
            .first_token = @enumFromInt(start_token),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = children_start,
            .child_hi = children_end,
        };
    }

    // Optional Type: ?T
    if (parser.match(.question)) {
        _ = parser.advance();
        const children_start = @as(u32, @intCast(nodes.items.len));
        const inner_type = try parseTypePrimary(parser, nodes);
        try nodes.append(parser.allocator, inner_type);
        const children_end = @as(u32, @intCast(nodes.items.len));

        return astdb_core.AstNode{
            .kind = .optional_type,
            .first_token = @enumFromInt(start_token),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = children_start,
            .child_hi = children_end,
        };
    }

    // Base Type: identifier
    if (parser.match(.identifier)) {
        _ = parser.advance();
        return astdb_core.AstNode{
            .kind = .identifier,
            .first_token = @enumFromInt(start_token),
            .last_token = @enumFromInt(parser.current - 1),
            .child_lo = 0,
            .child_hi = 0,
        };
    }

    return error.UnexpectedToken;
}

/// Parse graft declaration: graft alias = origin "module";
fn parseGraftDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;

    // Consume 'graft' keyword
    _ = try parser.consume(.graft);

    const children_start = @as(u32, @intCast(nodes.items.len));

    // alias identifier
    _ = try parser.consume(.identifier);
    const alias_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    try nodes.append(parser.allocator, alias_node);

    // '='
    _ = try parser.consume(.assign);

    // origin identifier (e.g., zig, c, python)
    _ = try parser.consume(.identifier);
    const origin_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    try nodes.append(parser.allocator, origin_node);

    // module string literal
    _ = try parser.consume(.string_literal);
    const mod_node = astdb_core.AstNode{
        .kind = .string_literal,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    try nodes.append(parser.allocator, mod_node);

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    return astdb_core.AstNode{
        .kind = .use_stmt, // Use use_stmt for now, differentiate in semantic analysis
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = children_start,
        .child_hi = @as(u32, @intCast(nodes.items.len)),
    };
}

/// Parse foreign declaration: foreign ident as IDENT do_block;
fn parseForeignDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;

    // Consume 'foreign' keyword
    _ = try parser.consume(.invalid);

    const children_start = @as(u32, @intCast(nodes.items.len));

    // origin identifier (e.g., python)
    _ = try parser.consume(.identifier);
    const origin_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    try nodes.append(parser.allocator, origin_node);

    // 'as' keyword
    _ = try parser.consume(.invalid); // 'as' is tokenized as use_ since 'as' conflicts with other uses

    // handle variable identifier
    _ = try parser.consume(.identifier);
    const handle_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    try nodes.append(parser.allocator, handle_node);

    // Parse foreign code block (do...end)
    const block_start = @as(u32, @intCast(nodes.items.len));
    _ = try parser.consume(.do_);

    // Parse foreign source code until 'end'
    // For foreign blocks, we collect raw tokens that represent the foreign source
    const foreign_tokens_start = parser.current;
    var brace_depth: u32 = 0;

    // Skip to matching 'end', handling nested braces if any
    while (parser.current < parser.tokens.len) {
        const tok = parser.tokens[parser.current];

        if (tok.kind == .do_ or tok.kind == .left_brace) {
            brace_depth += 1;
        } else if (tok.kind == .end and brace_depth == 0) {
            break;
        } else if (tok.kind == .right_brace and brace_depth > 0) {
            brace_depth -= 1;
        }

        parser.current += 1;
    }

    const block_end = parser.current;

    // Consume 'end'
    if (parser.current < parser.tokens.len and parser.tokens[parser.current].kind == .end) {
        _ = parser.advance();
    }

    // Create a block node representing the foreign source code
    const block_node = astdb_core.AstNode{
        .kind = .block_stmt,
        .first_token = @enumFromInt(foreign_tokens_start),
        .last_token = @enumFromInt(block_end - 1),
        .child_lo = block_start,
        .child_hi = @as(u32, @intCast(nodes.items.len)),
    };

    try nodes.append(parser.allocator, block_node);

    return astdb_core.AstNode{
        .kind = .use_stmt, // Use use_stmt for now, differentiate in semantic analysis
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = children_start,
        .child_hi = @as(u32, @intCast(nodes.items.len)),
    };
}

/// Parse statements inside a block (between { and })
fn parseBlockStatements(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode), out_children: *std.ArrayList(astdb_core.NodeId)) !void {
    // Parse statements until we hit the closing brace
    while (parser.peek() != null and
        !parser.match(.right_brace) and
        !parser.match(.end) and
        !parser.match(.else_) and
        !parser.match(.eof))
    {
        const stmt_start = nodes.items.len;
        var supports_postfix_when = false;

        if (parser.match(.return_)) {
            const return_stmt = try parseReturnStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, return_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
            supports_postfix_when = true;
        } else if (parser.match(.fail_)) {
            const fail_stmt = try parseFailStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, fail_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
            supports_postfix_when = true;
        } else if (parser.match(.requires)) {
            const req_stmt = try parseRequiresStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, req_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.ensures)) {
            const ens_stmt = try parseEnsuresStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, ens_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.invariant)) {
            const inv_stmt = try parseInvariantStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, inv_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.let)) {
            const let_stmt = try parseLetStatement(parser);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, let_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.var_)) {
            const var_stmt = try parseVarStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, var_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.defer_)) {
            const defer_stmt = try parseDeferStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, defer_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.for_)) {
            const for_stmt = try parseForStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, for_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.identifier) or parser.match(.string_literal) or parser.match(.integer_literal) or parser.match(.float_literal) or parser.match(.true_) or parser.match(.false_) or parser.match(.left_paren) or parser.match(.spawn_) or parser.match(.await_)) {
            // Parse full expression (handles method calls, assignments, pipeline chains, spawn/await, etc.)
            const expr = try parseExpression(parser, nodes, .none);
            const expr_index = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, expr);

            const child_lo = @as(u32, @intCast(parser.edges.items.len));
            try parser.edges.append(parser.allocator, @enumFromInt(expr_index));
            const child_hi = @as(u32, @intCast(parser.edges.items.len));

            const expr_stmt = astdb_core.AstNode{
                .kind = .expr_stmt,
                .first_token = expr.first_token,
                .last_token = expr.last_token,
                .child_lo = child_lo,
                .child_hi = child_hi,
            };
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, expr_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
            supports_postfix_when = true;
        } else if (parser.match(.if_)) {
            // Handle if statements
            const if_stmt = try parseIfStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, if_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.while_)) {
            // Handle while statements in do/end form
            const while_stmt = try parseWhileStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, while_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.match)) {
            // Handle match statements
            const match_stmt = try parseMatchStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, match_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.nursery_)) {
            // :service profile - Handle nursery do ... end (structured concurrency)
            const nursery_stmt = try parseNurseryStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, nursery_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.select_)) {
            // :service profile - Handle select do ... end (CSP multi-channel wait)
            const select_stmt = try parseSelectStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, select_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.using)) {
            // :service profile - Handle using [shared] resource = expr do ... end (resource management)
            const using_stmt = try parseUsingStatement(parser, nodes);
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, using_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.break_)) {
            // Handle break statement
            const break_token: astdb_core.TokenId = @enumFromInt(parser.current);
            _ = parser.advance(); // consume 'break'
            const break_stmt = astdb_core.AstNode{
                .kind = .break_stmt,
                .first_token = break_token,
                .last_token = @enumFromInt(parser.current -| 1),
                .child_lo = 0,
                .child_hi = 0,
            };
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, break_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else if (parser.match(.continue_)) {
            // Handle continue statement
            const continue_token: astdb_core.TokenId = @enumFromInt(parser.current);
            _ = parser.advance(); // consume 'continue'
            const continue_stmt = astdb_core.AstNode{
                .kind = .continue_stmt,
                .first_token = continue_token,
                .last_token = @enumFromInt(parser.current -| 1),
                .child_lo = 0,
                .child_hi = 0,
            };
            const stmt_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, continue_stmt);
            try out_children.append(parser.allocator, @enumFromInt(stmt_idx));
        } else {
            // Skip unknown tokens for now
            _ = parser.advance();
        }

        // Handle postfix 'when': stmt when expr -> if expr { stmt }
        if (supports_postfix_when and parser.match(.when)) {
            const when_token = parser.current;
            _ = parser.advance(); // consume 'when'

            // 1. Parse condition
            const cond_start = nodes.items.len;
            const cond = try parseExpression(parser, nodes, .none);
            try nodes.append(parser.allocator, cond);
            const cond_end = nodes.items.len;

            // 2. Rotate nodes: [stmt, cond] -> [cond, stmt]
            // stmt is at [stmt_start, cond_start)
            // cond is at [cond_start, cond_end)
            const rotate_amount = cond_start - stmt_start;
            std.mem.rotate(astdb_core.AstNode, nodes.items[stmt_start..cond_end], rotate_amount);

            // Now:
            // cond is at [stmt_start, stmt_start + (cond_end - cond_start))
            // stmt is at [stmt_start + (cond_end - cond_start), cond_end)

            const new_cond_end = stmt_start + (cond_end - cond_start);
            const new_stmt_end = cond_end;

            // 3. Create postfix_when node
            // cond root is at new_cond_end - 1
            // stmt root is at new_stmt_end - 1

            const cond_root_index = new_cond_end - 1;
            const stmt_root_index = new_stmt_end - 1;

            const postfix_node = astdb_core.AstNode{
                .kind = .postfix_when,
                .first_token = @enumFromInt(when_token),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = @intCast(cond_root_index),
                .child_hi = @intCast(stmt_root_index),
            };
            try nodes.append(parser.allocator, postfix_node);
        }

        // Handle postfix 'unless': stmt unless expr -> if !expr { stmt }
        // (Inverse logic of 'when')
        if (supports_postfix_when and parser.match(.unless)) {
            const unless_token = parser.current;
            _ = parser.advance(); // consume 'unless'

            // 1. Parse condition
            const cond_start = nodes.items.len;
            const cond = try parseExpression(parser, nodes, .none);
            try nodes.append(parser.allocator, cond);
            const cond_end = nodes.items.len;

            // 2. Rotate nodes: [stmt, cond] -> [cond, stmt]
            const rotate_amount = cond_start - stmt_start;
            std.mem.rotate(astdb_core.AstNode, nodes.items[stmt_start..cond_end], rotate_amount);

            const new_cond_end = stmt_start + (cond_end - cond_start);
            const new_stmt_end = cond_end;

            // 3. Create postfix_unless node
            const cond_root_index = new_cond_end - 1;
            const stmt_root_index = new_stmt_end - 1;

            const postfix_node = astdb_core.AstNode{
                .kind = .postfix_unless,
                .first_token = @enumFromInt(unless_token),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = @intCast(cond_root_index),
                .child_hi = @intCast(stmt_root_index),
            };
            try nodes.append(parser.allocator, postfix_node);
        }

        // Skip trailing whitespace
        while (parser.match(.newline)) {
            _ = parser.advance();
        }
    }
}

/// Parse requires statement: requires condition;
fn parseRequiresStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.requires);

    // Expression condition
    const expr = try parseExpression(parser, nodes, .none);
    const expr_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, expr);

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    // Record edge to expression
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.append(parser.allocator, @enumFromInt(expr_idx));
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .requires_clause,
        .first_token = @enumFromInt(start_token),
        .last_token = expr.last_token,
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse ensures statement: ensures condition;
fn parseEnsuresStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.ensures);

    // Expression condition
    const expr = try parseExpression(parser, nodes, .none);
    const expr_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, expr);

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    // Record edge to expression
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.append(parser.allocator, @enumFromInt(expr_idx));
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .ensures_clause,
        .first_token = @enumFromInt(start_token),
        .last_token = expr.last_token,
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse invariant statement: invariant condition;
fn parseInvariantStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.invariant);

    // Expression condition
    const expr = try parseExpression(parser, nodes, .none);
    const expr_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, expr);

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    // Record edge to expression
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.append(parser.allocator, @enumFromInt(expr_idx));
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .invariant_clause,
        .first_token = @enumFromInt(start_token),
        .last_token = expr.last_token,
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a variable declaration: let type name = expression;
fn parseLetStatement(parser: *ParserState) !astdb_core.AstNode {
    // std.debug.print("Parsing Let Statement\n", .{});
    const start_token = parser.current;
    _ = try parser.consume(.let);

    var let_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 2);
    defer let_edges.deinit(parser.allocator);

    // Identifier
    _ = try parser.consume(.identifier);
    const id_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };

    const id_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, id_node);
    try let_edges.append(parser.allocator, @enumFromInt(id_idx));

    // Optional Type Annotation: ': Type'
    if (parser.match(.colon)) {
        _ = parser.advance();
        const type_node = try parseType(parser, &parser.nodes);
        const type_idx = @as(u32, @intCast(parser.nodes.items.len));
        try parser.nodes.append(parser.allocator, type_node);
        try let_edges.append(parser.allocator, @enumFromInt(type_idx));
    }

    // ... = ...
    _ = try parser.consume(.assign);
    const init = try parseExpression(parser, &parser.nodes, .none);
    const init_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, init);
    try let_edges.append(parser.allocator, @enumFromInt(init_idx));

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, let_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .let_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = init.last_token,
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a for loop: for x in collection do ... end
fn parseForStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.for_);

    var for_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer for_edges.deinit(parser.allocator);

    // loop variable
    _ = try parser.consume(.identifier);
    const var_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };

    const var_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, var_node);
    try for_edges.append(parser.allocator, @enumFromInt(var_idx));

    // 'in' expression
    _ = try parser.consume(.in_);
    const iterable = try parseExpression(parser, nodes, .none);
    const iter_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, iterable);
    try for_edges.append(parser.allocator, @enumFromInt(iter_idx));

    // do/end body or { body }
    var block_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer block_stmts.deinit(parser.allocator);

    if (parser.match(.left_brace)) {
        _ = try parser.consume(.left_brace);
        try parseBlockStatements(parser, nodes, &block_stmts);
        _ = try parser.consume(.right_brace);
    } else {
        _ = try parser.consume(.do_);
        try parseBlockStatements(parser, nodes, &block_stmts);
        _ = try parser.consume(.end);
    }

    // Build a block node for body
    const block_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, block_stmts.items);
    const block_hi = @as(u32, @intCast(parser.edges.items.len));

    const block_node = astdb_core.AstNode{
        .kind = .block_stmt,
        .first_token = @enumFromInt(start_token), // Approximate
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = block_lo,
        .child_hi = block_hi,
    };
    const block_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, block_node);
    try for_edges.append(parser.allocator, @enumFromInt(block_idx));

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, for_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .for_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse anonymous function literal: func(args) -> ret { ... }
fn parseFunctionLiteral(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.func);

    // Build edge list for this closure's children (mirrors parseFunctionDeclaration)
    var func_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer func_edges.deinit(parser.allocator);

    // Parameters
    _ = try parser.consume(.left_paren);
    while (!parser.match(.right_paren) and parser.peek() != null) {
        if (parser.match(.identifier)) {
            const param_start = parser.current;
            _ = parser.advance();

            // Optional Type Annotation: ': Type'
            if (parser.match(.colon)) {
                _ = parser.advance();
                const type_node = try parseType(parser, nodes);
                try nodes.append(parser.allocator, type_node);
            }

            const param_node = astdb_core.AstNode{
                .kind = .parameter,
                .first_token = @enumFromInt(param_start),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = 0,
                .child_hi = 0,
            };
            const param_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, param_node);
            try func_edges.append(parser.allocator, @enumFromInt(param_idx));

            if (parser.match(.comma)) _ = parser.advance();
        } else break;
    }
    _ = try parser.consume(.right_paren);

    // Optional return type: '->' type
    if (parser.match(.arrow)) {
        _ = parser.advance();
        const ret_type = try parseType(parser, nodes);
        const ret_idx = @as(u32, @intCast(nodes.items.len));
        try nodes.append(parser.allocator, ret_type);
        try func_edges.append(parser.allocator, @enumFromInt(ret_idx));
    }

    // Body: brace or do/end
    var block_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer block_stmts.deinit(parser.allocator);

    if (parser.match(.left_brace)) {
        if (parser.match(.do_)) {
            _ = try parser.consume(.do_);
            try parseBlockStatements(parser, nodes, &block_stmts);
        } else {
            _ = try parser.consume(.left_brace);
            try parseBlockStatements(parser, nodes, &block_stmts);
            _ = try parser.consume(.right_brace);
        }
    } else {
        _ = try parser.consume(.do_);
        try parseBlockStatements(parser, nodes, &block_stmts);
        _ = try parser.consume(.end);
    }

    // Append block statements to func_edges
    try func_edges.appendSlice(parser.allocator, block_stmts.items);

    // Store in parser.edges and compute child_lo/child_hi
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, func_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .func_decl,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse block function literal: { |arg| ... }
fn parseBlockFunctionLiteral(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    var used_do_end = false;
    // Check if this is do/end form or brace form
    var dummy_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer dummy_stmts.deinit(parser.allocator);
    if (parser.match(.do_)) {
        _ = try parser.consume(.do_);
        used_do_end = true;
        try parseBlockStatements(parser, nodes, &dummy_stmts);
    } else {
        _ = try parser.consume(.left_brace);
        try parseBlockStatements(parser, nodes, &dummy_stmts);
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
            try nodes.append(parser.allocator, param_node);
            if (parser.match(.comma)) _ = parser.advance();
        }
        _ = try parser.consume(.pipe);
    }
    try parseBlockStatements(parser, nodes, &dummy_stmts);
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
            try nodes.append(parser.allocator, param_node);
            if (parser.match(.comma)) _ = parser.advance();
        }
        _ = try parser.consume(.pipe);
    }
    var dummy_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer dummy_stmts.deinit(parser.allocator);
    try parseBlockStatements(parser, nodes, &dummy_stmts);
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

    var while_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 2);
    defer while_edges.deinit(parser.allocator);

    // Parse condition
    if (parser.match(.left_paren)) {
        _ = parser.advance();
        const cond = try parseExpression(parser, nodes, .none);
        const cond_idx = @as(u32, @intCast(parser.nodes.items.len));
        try parser.nodes.append(parser.allocator, cond);
        try while_edges.append(parser.allocator, @enumFromInt(cond_idx));
        _ = try parser.consume(.right_paren);
    } else {
        const cond = try parseExpression(parser, nodes, .none);
        const cond_idx = @as(u32, @intCast(parser.nodes.items.len));
        try parser.nodes.append(parser.allocator, cond);
        try while_edges.append(parser.allocator, @enumFromInt(cond_idx));
    }

    // Parse body
    var block_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer block_stmts.deinit(parser.allocator);

    if (parser.match(.do_)) {
        _ = parser.advance();
        try parseBlockStatements(parser, nodes, &block_stmts);
        _ = try parser.consume(.end);
    } else if (parser.match(.left_brace)) {
        _ = parser.advance();
        try parseBlockStatements(parser, nodes, &block_stmts);
        _ = try parser.consume(.right_brace);
    } else {
        // Fallback for :min style without do/brace if allowed, or error
        // Assuming do or brace is required for now as per previous code structure
        return error.UnexpectedToken;
    }

    // Create block node for body
    const block_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, block_stmts.items);
    const block_hi = @as(u32, @intCast(parser.edges.items.len));

    const block_node = astdb_core.AstNode{
        .kind = .block_stmt,
        .first_token = @enumFromInt(start_token), // Approximate
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = block_lo,
        .child_hi = block_hi,
    };
    const block_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, block_node);
    try while_edges.append(parser.allocator, @enumFromInt(block_idx));

    // Commit edges
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, while_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .while_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a nursery statement: nursery do ... end (:service profile)
/// Nursery is the structured concurrency boundary - all spawned tasks must
/// complete before the nursery exits.
fn parseNurseryStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.nursery_);

    // Parse body
    var block_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer block_stmts.deinit(parser.allocator);

    if (parser.match(.do_)) {
        _ = parser.advance();
        try parseBlockStatements(parser, nodes, &block_stmts);
        _ = try parser.consume(.end);
    } else if (parser.match(.left_brace)) {
        _ = parser.advance();
        try parseBlockStatements(parser, nodes, &block_stmts);
        _ = try parser.consume(.right_brace);
    } else {
        return error.UnexpectedToken;
    }

    // Commit edges
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, block_stmts.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .nursery_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a select statement: select do case ... end (:service profile)
/// CSP-style multi-channel wait with support for recv, send, timeout, and default cases.
///
/// Syntax:
///   select do
///       case msg = ch.recv() do ... end
///       case ch.send(value) do ... end
///       case timeout(duration) do ... end
///       default do ... end
///   end
fn parseSelectStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.select_);

    // Expect 'do' or '{'
    if (parser.match(.do_)) {
        _ = parser.advance();
    } else if (parser.match(.left_brace)) {
        _ = parser.advance();
    } else {
        return error.UnexpectedToken;
    }

    // Parse cases
    var case_children = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 4);
    defer case_children.deinit(parser.allocator);

    while (!parser.match(.end) and !parser.match(.right_brace) and !parser.match(.eof)) {
        // Skip newlines
        if (parser.match(.newline)) {
            _ = parser.advance();
            continue;
        }
        if (parser.match(.case)) {
            // Parse case: case expr do ... end
            const case_node = try parseSelectCase(parser, nodes);
            const case_idx = @as(u32, @intCast(parser.nodes.items.len));
            try parser.nodes.append(parser.allocator, case_node);
            try case_children.append(parser.allocator, @enumFromInt(case_idx));
        } else if (parser.match(.timeout_)) {
            // Parse timeout case: timeout(duration) do ... end
            const timeout_node = try parseSelectTimeout(parser, nodes);
            const timeout_idx = @as(u32, @intCast(parser.nodes.items.len));
            try parser.nodes.append(parser.allocator, timeout_node);
            try case_children.append(parser.allocator, @enumFromInt(timeout_idx));
        } else if (parser.match(.default_)) {
            // Parse default case: default do ... end
            const default_node = try parseSelectDefault(parser, nodes);
            const default_idx = @as(u32, @intCast(parser.nodes.items.len));
            try parser.nodes.append(parser.allocator, default_node);
            try case_children.append(parser.allocator, @enumFromInt(default_idx));
        } else {
            // Unexpected token in select body
            return error.UnexpectedToken;
        }
    }

    // Consume closing 'end' or '}'
    if (parser.match(.end)) {
        _ = parser.advance();
    } else if (parser.match(.right_brace)) {
        _ = parser.advance();
    } else {
        return error.UnexpectedToken;
    }

    // Commit edges
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, case_children.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .select_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a select case: case [var =] expr do ... end
fn parseSelectCase(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.case);

    var case_children = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 2);
    defer case_children.deinit(parser.allocator);

    // Parse case condition: either "var = expr" or just "expr"
    const condition_expr = try parseExpression(parser, nodes, .none);
    const condition_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, condition_expr);
    try case_children.append(parser.allocator, @enumFromInt(condition_idx));

    // Expect 'do' or '{'
    if (parser.match(.do_)) {
        _ = parser.advance();
    } else if (parser.match(.left_brace)) {
        _ = parser.advance();
    } else {
        return error.UnexpectedToken;
    }

    // Parse body
    var body_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer body_stmts.deinit(parser.allocator);
    try parseBlockStatements(parser, nodes, &body_stmts);

    // Create body block node
    const body_child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, body_stmts.items);
    const body_child_hi = @as(u32, @intCast(parser.edges.items.len));

    const body_node = astdb_core.AstNode{
        .kind = .block_stmt,
        .first_token = condition_expr.last_token,
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = body_child_lo,
        .child_hi = body_child_hi,
    };
    const body_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, body_node);
    try case_children.append(parser.allocator, @enumFromInt(body_idx));

    // Consume closing 'end' or '}'
    if (parser.match(.end)) {
        _ = parser.advance();
    } else if (parser.match(.right_brace)) {
        _ = parser.advance();
    } else {
        return error.UnexpectedToken;
    }

    // Commit edges
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, case_children.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .select_case,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a select timeout case: timeout(duration) do ... end
fn parseSelectTimeout(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.timeout_);

    var case_children = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 2);
    defer case_children.deinit(parser.allocator);

    // Expect '('
    _ = try parser.consume(.left_paren);

    // Parse duration expression
    const duration_expr = try parseExpression(parser, nodes, .none);
    const duration_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, duration_expr);
    try case_children.append(parser.allocator, @enumFromInt(duration_idx));

    // Expect ')'
    _ = try parser.consume(.right_paren);

    // Expect 'do' or '{'
    if (parser.match(.do_)) {
        _ = parser.advance();
    } else if (parser.match(.left_brace)) {
        _ = parser.advance();
    } else {
        return error.UnexpectedToken;
    }

    // Parse body
    var body_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer body_stmts.deinit(parser.allocator);
    try parseBlockStatements(parser, nodes, &body_stmts);

    // Create body block node
    const body_child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, body_stmts.items);
    const body_child_hi = @as(u32, @intCast(parser.edges.items.len));

    const body_node = astdb_core.AstNode{
        .kind = .block_stmt,
        .first_token = duration_expr.last_token,
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = body_child_lo,
        .child_hi = body_child_hi,
    };
    const body_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, body_node);
    try case_children.append(parser.allocator, @enumFromInt(body_idx));

    // Consume closing 'end' or '}'
    if (parser.match(.end)) {
        _ = parser.advance();
    } else if (parser.match(.right_brace)) {
        _ = parser.advance();
    } else {
        return error.UnexpectedToken;
    }

    // Commit edges
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, case_children.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .select_timeout,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a select default case: default do ... end
fn parseSelectDefault(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.default_);

    var case_children = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 1);
    defer case_children.deinit(parser.allocator);

    // Expect 'do' or '{'
    if (parser.match(.do_)) {
        _ = parser.advance();
    } else if (parser.match(.left_brace)) {
        _ = parser.advance();
    } else {
        return error.UnexpectedToken;
    }

    // Parse body
    var body_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer body_stmts.deinit(parser.allocator);
    try parseBlockStatements(parser, nodes, &body_stmts);

    // Create body block node
    const body_child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, body_stmts.items);
    const body_child_hi = @as(u32, @intCast(parser.edges.items.len));

    const body_node = astdb_core.AstNode{
        .kind = .block_stmt,
        .first_token = @enumFromInt(start_token + 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = body_child_lo,
        .child_hi = body_child_hi,
    };
    const body_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, body_node);
    try case_children.append(parser.allocator, @enumFromInt(body_idx));

    // Consume closing 'end' or '}'
    if (parser.match(.end)) {
        _ = parser.advance();
    } else if (parser.match(.right_brace)) {
        _ = parser.advance();
    } else {
        return error.UnexpectedToken;
    }

    // Commit edges
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, case_children.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .select_default,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
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
    try nodes.append(parser.allocator, callee_node);

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
                try nodes.append(parser.allocator, name_node);
                _ = parser.advance(); // consume ':'
                // Parse value expression (allow literals/identifier)
                const value_expr = try parsePrimary(parser, nodes);
                try nodes.append(parser.allocator, value_expr);
            } else {
                // Positional identifier argument
                const id_node = astdb_core.AstNode{
                    .kind = .identifier,
                    .first_token = @enumFromInt(save),
                    .last_token = @enumFromInt(save),
                    .child_lo = 0,
                    .child_hi = 0,
                };
                try nodes.append(parser.allocator, id_node);
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
            try nodes.append(parser.allocator, lit_node);
        } else {
            // Fallback: try parse an expression (e.g., array literal)
            const expr = try parseExpression(parser, nodes, .none);
            try nodes.append(parser.allocator, expr);
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
fn parseDeferStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.defer_);

    // Expression to defer
    const expr = try parseExpression(parser, nodes, .none);
    const expr_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, expr);

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    // Record edge to expression
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.append(parser.allocator, @enumFromInt(expr_idx));
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .defer_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = expr.last_token,
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

fn parseReturnStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.return_);

    var return_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 1);
    defer return_edges.deinit(parser.allocator);

    // Parse expression if present (not semicolon, newline, or block end)
    if (!parser.match(.semicolon) and !parser.match(.newline) and !parser.match(.right_brace) and !parser.match(.end) and !parser.match(.eof)) {
        const expr = try parseExpression(parser, nodes, .none);
        const expr_idx = @as(u32, @intCast(nodes.items.len));
        try nodes.append(parser.allocator, expr);
        try return_edges.append(parser.allocator, @enumFromInt(expr_idx));
    }

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, return_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .return_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse fail statement: fail ErrorType.Variant
fn parseFailStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.fail_);

    // Parse error value expression (e.g., ErrorType.Variant)
    const error_expr = try parseExpression(parser, nodes, .none);
    const error_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, error_expr);

    // Optional semicolon
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.append(parser.allocator, @enumFromInt(error_idx));
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .fail_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// PROBATIO: Parse test declaration - test "name" do ... end
fn parseTestDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;

    // Consume 'test' keyword
    _ = try parser.consume(.test_);

    // Consume test name (string literal)
    const name_token_idx = parser.current;
    _ = try parser.consume(.string_literal);

    // Collect body statement node IDs
    var body_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer body_stmts.deinit(parser.allocator);

    // Consume 'do' and parse block
    _ = try parser.consume(.do_);
    try parseBlockStatements(parser, nodes, &body_stmts);
    _ = try parser.consume(.end);

    // Create name node
    const name_node = astdb_core.AstNode{
        .kind = .string_literal,
        .first_token = @enumFromInt(name_token_idx),
        .last_token = @enumFromInt(name_token_idx),
        .child_lo = 0,
        .child_hi = 0,
    };
    const name_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, name_node);

    // Build edges: name + body statements
    var test_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 1 + body_stmts.items.len);
    defer test_edges.deinit(parser.allocator);
    try test_edges.append(parser.allocator, @enumFromInt(name_idx));
    try test_edges.appendSlice(parser.allocator, body_stmts.items);

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, test_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .test_decl,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a function declaration: func name() { }
fn parseFunctionDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode), is_async: bool) !astdb_core.AstNode {
    // Consume 'func' keyword (async already consumed by caller if is_async)
    const start_token = parser.current;
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
    var parameters = try std.ArrayList(astdb_core.AstNode).initCapacity(parser.allocator, 0);
    defer parameters.deinit(parser.allocator);

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
            try parameters.append(parser.allocator, param_node);

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

    // Parse return type annotation if present (-> type)
    var return_type_node: ?astdb_core.AstNode = null;
    if (parser.current < parser.tokens.len and
        parser.tokens[parser.current].kind == .arrow)
    {
        _ = parser.advance(); // consume ->
        return_type_node = try parseType(parser, nodes);
    }

    // Calculate child indices - start with name and parameters
    var func_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer func_edges.deinit(parser.allocator);

    if (has_name) {
        const func_name_node = astdb_core.AstNode{
            .kind = .identifier,
            .first_token = @enumFromInt(name_token_index),
            .last_token = @enumFromInt(name_token_index),
            .child_lo = 0,
            .child_hi = 0,
        };
        const idx = @as(u32, @intCast(parser.nodes.items.len));
        try parser.nodes.append(parser.allocator, func_name_node);
        try func_edges.append(parser.allocator, @enumFromInt(idx));
    }

    // Add parameter nodes
    for (parameters.items) |param_node| {
        const idx = @as(u32, @intCast(parser.nodes.items.len));
        try parser.nodes.append(parser.allocator, param_node);
        try func_edges.append(parser.allocator, @enumFromInt(idx));
    }

    // Add return type node if present
    if (return_type_node) |ret_type| {
        const idx = @as(u32, @intCast(parser.nodes.items.len));
        try parser.nodes.append(parser.allocator, ret_type);
        try func_edges.append(parser.allocator, @enumFromInt(idx));
    }

    // Handle both 'do' and '{' for function body start
    var block_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer block_stmts.deinit(parser.allocator);

    if (parser.current < parser.tokens.len and
        parser.tokens[parser.current].kind == .do_)
    {
        _ = try parser.consume(.do_);
        used_do_end = true;
        try parseBlockStatements(parser, nodes, &block_stmts);
        _ = try parser.consume(.end);
    } else {
        _ = try parser.consume(.left_brace);
        try parseBlockStatements(parser, nodes, &block_stmts);
        _ = try parser.consume(.right_brace);
    }

    // Append block statements to func_edges
    try func_edges.appendSlice(parser.allocator, block_stmts.items);

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, func_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    // Create function declaration node with proper child indices
    const func_node = astdb_core.AstNode{
        .kind = if (is_async) .async_func_decl else .func_decl, // :service profile
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };

    return func_node;
}

/// Parse extern function declaration: extern func name(params) -> type
fn parseExternFuncDeclaration(parser: *ParserState, _: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;

    // Consume 'extern' keyword
    _ = try parser.consume(.extern_);

    // Consume 'func' keyword
    _ = try parser.consume(.func);

    // Function name (required for extern)
    _ = try parser.consume(.identifier);
    const name_token_index = parser.current - 1;

    // Consume '('
    _ = try parser.consume(.left_paren);

    // Parse parameters
    var parameters = try std.ArrayList(astdb_core.AstNode).initCapacity(parser.allocator, 0);
    defer parameters.deinit(parser.allocator);

    while (parser.current < parser.tokens.len and
        parser.tokens[parser.current].kind != .right_paren)
    {
        if (parser.tokens[parser.current].kind == .identifier) {
            const param_node = astdb_core.AstNode{
                .kind = .parameter,
                .first_token = @enumFromInt(parser.current),
                .last_token = @enumFromInt(parser.current),
                .child_lo = 0,
                .child_hi = 0,
            };
            try parameters.append(parser.allocator, param_node);

            _ = parser.advance();

            // Consume ':' and type if present
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
        // Skip the return type until newline or semicolon
        while (parser.current < parser.tokens.len and
            parser.tokens[parser.current].kind != .semicolon and
            parser.tokens[parser.current].kind != .func and
            parser.tokens[parser.current].kind != .extern_ and
            parser.tokens[parser.current].kind != .let and
            parser.tokens[parser.current].kind != .const_ and
            parser.tokens[parser.current].kind != .eof)
        {
            // Stop at tokens that indicate next declaration
            const kind = parser.tokens[parser.current].kind;
            if (kind == .identifier) {
                // Check if this is the start of a new declaration by peeking
                // If next token after identifier is '(' or ':', it's still part of type
                if (parser.current + 1 < parser.tokens.len) {
                    const next = parser.tokens[parser.current + 1].kind;
                    if (next != .left_paren and next != .colon and next != .left_bracket and next != .dot) {
                        break;
                    }
                }
            }
            parser.current += 1;
        }
    }

    // Build edges for function name and parameters
    var func_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer func_edges.deinit(parser.allocator);

    // Add name node
    const func_name_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(name_token_index),
        .last_token = @enumFromInt(name_token_index),
        .child_lo = 0,
        .child_hi = 0,
    };
    const name_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, func_name_node);
    try func_edges.append(parser.allocator, @enumFromInt(name_idx));

    // Add parameter nodes
    for (parameters.items) |param_node| {
        const idx = @as(u32, @intCast(parser.nodes.items.len));
        try parser.nodes.append(parser.allocator, param_node);
        try func_edges.append(parser.allocator, @enumFromInt(idx));
    }

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, func_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    // No body for extern functions
    return astdb_core.AstNode{
        .kind = .extern_func,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
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
    bitwise_or = 7, // |
    bitwise_xor = 8, // ^
    bitwise_and = 9, // &
    shift = 10, // << >>
    range = 11, // .. ..<
    term = 12, // + -
    factor = 13, // * / %
    power = 14, // ** (right-associative)
    unary = 15, // ! -
    pipeline = 16, // |>
    call = 17, // . ()
    primary = 18,
};

/// Get precedence for a token kind
fn getTokenPrecedence(kind: TokenKind) Precedence {
    const prec: Precedence = switch (kind) {
        .assign, .equal, .plus_assign, .minus_assign, .star_assign, .slash_assign, .percent_assign, .ampersand_assign, .pipe_assign, .xor_assign, .left_shift_assign, .right_shift_assign => .assignment,
        .or_, .logical_or => .logical_or,
        .null_coalesce => .null_coalesce,
        .and_, .logical_and => .logical_and,
        .equal_equal, .not_equal => .equality,
        .greater, .greater_equal, .less, .less_equal => .comparison,
        .bitwise_or => .bitwise_or,
        .bitwise_xor => .bitwise_xor,
        .bitwise_and => .bitwise_and,
        .left_shift, .right_shift => .shift,
        .range_inclusive, .range_exclusive => .range,
        .plus, .minus => .term,
        .star, .slash, .percent => .factor,
        .star_star => .power,
        .pipeline => .pipeline,
        else => .none,
    };
    return prec;
}

/// Parse an expression using Pratt parsing
fn parseExpression(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode), precedence: Precedence) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    // Parse left side (primary expression or prefix expression)
    var left: astdb_core.AstNode = blk: {
        if (parser.peek()) |token| {
            if (token.kind == .minus or token.kind == .logical_not or token.kind == .bitwise_not or token.kind == .exclamation or token.kind == .tilde or token.kind == .not_) {
                const op_idx = parser.current;
                _ = parser.advance();

                const operand = try parseExpression(parser, nodes, .unary);

                const operand_idx = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, operand);

                const edge_lo = @as(u32, @intCast(parser.edges.items.len));
                try parser.edges.append(parser.allocator, @enumFromInt(operand_idx));
                const edge_hi = @as(u32, @intCast(parser.edges.items.len));

                break :blk astdb_core.AstNode{
                    .kind = .unary_expr,
                    .first_token = @enumFromInt(op_idx),
                    .last_token = operand.last_token,
                    .child_lo = edge_lo,
                    .child_hi = edge_hi,
                };
            }
        }
        break :blk try parsePrimary(parser, nodes);
    };

    // Handle postfix operators: call, field access, index
    while (parser.peek()) |tok| {
        switch (tok.kind) {
            .left_paren => {
                // Function call: left(args)
                _ = parser.advance(); // consume '('

                // Append callee to nodes
                const callee_idx = @as(u32, @intCast(parser.nodes.items.len));
                try parser.nodes.append(parser.allocator, left);

                // Use temporary list for call edges to ensure contiguous children
                var call_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 4);
                defer call_edges.deinit(parser.allocator);

                try call_edges.append(parser.allocator, @enumFromInt(callee_idx));

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
                            const name_idx = @as(u32, @intCast(parser.nodes.items.len));
                            try parser.nodes.append(parser.allocator, name_node);
                            try call_edges.append(parser.allocator, @enumFromInt(name_idx));

                            _ = parser.advance(); // consume ':'
                            // value
                            const value_expr = try parseExpression(parser, nodes, .none);
                            const value_idx = @as(u32, @intCast(parser.nodes.items.len));
                            try parser.nodes.append(parser.allocator, value_expr);
                            try call_edges.append(parser.allocator, @enumFromInt(value_idx));
                        } else {
                            // Positional identifier argument - backtrack to parse as expression
                            parser.current = save;
                            const arg = try parseExpression(parser, nodes, .none);
                            const arg_idx = @as(u32, @intCast(parser.nodes.items.len));
                            try parser.nodes.append(parser.allocator, arg);
                            try call_edges.append(parser.allocator, @enumFromInt(arg_idx));
                        }
                    } else {
                        const arg = try parseExpression(parser, nodes, .none);
                        const arg_idx = @as(u32, @intCast(parser.nodes.items.len));
                        try parser.nodes.append(parser.allocator, arg);
                        try call_edges.append(parser.allocator, @enumFromInt(arg_idx));
                    }

                    // Optional comma (and allow newlines after comma)
                    if (parser.match(.comma)) {
                        _ = parser.advance();
                        while (parser.match(.newline)) _ = parser.advance();
                    } else if (!parser.match(.right_paren)) {
                        return error.UnexpectedToken;
                    }
                }

                _ = try parser.consume(.right_paren);

                // Commit edges
                const child_lo = @as(u32, @intCast(parser.edges.items.len));
                try parser.edges.appendSlice(parser.allocator, call_edges.items);
                const child_hi = @as(u32, @intCast(parser.edges.items.len));
                left = astdb_core.AstNode{
                    .kind = .call_expr,
                    .first_token = @enumFromInt(parser.current - 1), // Approximate
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },

            .dot, .optional_chain => {
                // Field access or optional chaining: left.identifier
                // Capture operator token index to preserve '.' vs '?.'
                // Capture operator token index to preserve '.' vs '?.'
                _ = parser.current;
                _ = parser.advance(); // consume '.' or '?.'
                _ = try parser.consume(.identifier);
                const ident_node = astdb_core.AstNode{
                    .kind = .identifier,
                    .first_token = @enumFromInt(parser.current - 1),
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = 0,
                    .child_hi = 0,
                };

                const left_idx = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, left);

                const ident_idx = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, ident_node);

                const child_lo = @as(u32, @intCast(parser.edges.items.len));
                try parser.edges.append(parser.allocator, @enumFromInt(left_idx));
                try parser.edges.append(parser.allocator, @enumFromInt(ident_idx));
                const child_hi = @as(u32, @intCast(parser.edges.items.len));

                left = astdb_core.AstNode{
                    .kind = .field_expr,
                    .first_token = left.first_token,
                    .last_token = ident_node.last_token,
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };

                // Postfix struct literal: Option.Some { value: 42 }
                // Disambiguate: { ident : ... } is struct literal, else not
                if (parser.match(.left_brace)) {
                    const brace_next = parser.current + 1;
                    var is_qualified_struct = false;
                    if (brace_next < parser.tokens.len) {
                        const peek_tok = parser.tokens[brace_next];
                        if (peek_tok.kind == .right_brace) {
                            is_qualified_struct = true; // T.V {}
                        } else if (peek_tok.kind == .identifier) {
                            const after_ident = parser.current + 2;
                            if (after_ident < parser.tokens.len) {
                                if (parser.tokens[after_ident].kind == .colon) {
                                    is_qualified_struct = true; // T.V { f: ... }
                                }
                            }
                        }
                    }

                    if (is_qualified_struct) {
                        _ = try parser.consume(.left_brace);

                        var struct_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 8);
                        defer struct_edges.deinit(parser.allocator);

                        // First child: the field_expr as type qualifier
                        const type_idx = @as(u32, @intCast(nodes.items.len));
                        try nodes.append(parser.allocator, left);
                        try struct_edges.append(parser.allocator, @enumFromInt(type_idx));

                        // Parse field initializers: name ':' expr
                        while (!parser.match(.right_brace) and parser.peek() != null) {
                            while (parser.match(.newline)) _ = parser.advance();
                            if (parser.match(.right_brace)) break;

                            // Field Name
                            if (!parser.match(.identifier)) return error.UnexpectedToken;
                            const sl_field_name_idx = parser.current;
                            _ = parser.advance();

                            const sl_field_name = astdb_core.AstNode{
                                .kind = .identifier,
                                .first_token = @enumFromInt(sl_field_name_idx),
                                .last_token = @enumFromInt(sl_field_name_idx),
                                .child_lo = 0,
                                .child_hi = 0,
                            };
                            const sl_name_node_idx = @as(u32, @intCast(nodes.items.len));
                            try nodes.append(parser.allocator, sl_field_name);
                            try struct_edges.append(parser.allocator, @enumFromInt(sl_name_node_idx));

                            // Colon
                            _ = try parser.consume(.colon);

                            // Value
                            const sl_value_expr = try parseExpression(parser, nodes, .none);
                            const sl_val_node_idx = @as(u32, @intCast(nodes.items.len));
                            try nodes.append(parser.allocator, sl_value_expr);
                            try struct_edges.append(parser.allocator, @enumFromInt(sl_val_node_idx));

                            // Comma
                            if (parser.match(.comma)) {
                                _ = parser.advance();
                            } else if (!parser.match(.right_brace)) {
                                // lenient
                            }
                        }
                        _ = try parser.consume(.right_brace);

                        const sl_child_lo = @as(u32, @intCast(parser.edges.items.len));
                        try parser.edges.appendSlice(parser.allocator, struct_edges.items);
                        const sl_child_hi = @as(u32, @intCast(parser.edges.items.len));

                        left = astdb_core.AstNode{
                            .kind = .struct_literal,
                            .first_token = left.first_token,
                            .last_token = @enumFromInt(parser.current - 1),
                            .child_lo = sl_child_lo,
                            .child_hi = sl_child_hi,
                        };
                    }
                }
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
                    // Parse slice expression: arr[start..end] or arr[start..<end]
                    // Parse start expression (e.g., 1 in arr[1..3])
                    var start_expr: ?astdb_core.AstNode = null;
                    if (parser.peek() != null and
                        !parser.match(.right_bracket) and
                        !parser.match(.range_inclusive) and
                        !parser.match(.range_exclusive) and
                        !parser.match(.colon))
                    {
                        start_expr = try parseExpression(parser, nodes, .range);
                    }

                    // Parse range operator - '..' or ':' or '..<'
                    const current_token = parser.peek() orelse return error.UnexpectedToken;
                    var is_inclusive = true;
                    if (current_token.kind == .range_inclusive) {
                        _ = parser.advance(); // consume '..'
                        is_inclusive = true;
                    } else if (current_token.kind == .range_exclusive) {
                        _ = parser.advance(); // consume '..<'
                        is_inclusive = false;
                    } else if (current_token.kind == .colon) {
                        _ = parser.advance(); // consume ':' slice delimiter (treat as exclusive)
                        is_inclusive = false;
                    } else {
                        return error.UnexpectedToken;
                    }

                    // Parse end expression (e.g., 3 in arr[1..3])
                    var end_expr: ?astdb_core.AstNode = null;
                    if (!parser.match(.right_bracket)) {
                        end_expr = try parseExpression(parser, nodes, .none);
                    }

                    _ = try parser.consume(.right_bracket);

                    // Append child nodes to nodes array and get their indices
                    const left_idx = @as(u32, @intCast(parser.nodes.items.len));
                    try parser.nodes.append(parser.allocator, left);

                    const start_idx = @as(u32, @intCast(parser.nodes.items.len));
                    if (start_expr) |se| {
                        try parser.nodes.append(parser.allocator, se);
                    } else {
                        // Default start = 0
                        try parser.nodes.append(parser.allocator, astdb_core.AstNode{
                            .kind = .integer_literal,
                            .first_token = @enumFromInt(0),
                            .last_token = @enumFromInt(0),
                            .child_lo = 0,
                            .child_hi = 0,
                        });
                    }

                    const end_idx = @as(u32, @intCast(parser.nodes.items.len));
                    if (end_expr) |ee| {
                        try parser.nodes.append(parser.allocator, ee);
                    } else {
                        // Default end - needs to be array length, for now use a placeholder
                        try parser.nodes.append(parser.allocator, astdb_core.AstNode{
                            .kind = .integer_literal,
                            .first_token = @enumFromInt(0),
                            .last_token = @enumFromInt(0),
                            .child_lo = 0,
                            .child_hi = 0,
                        });
                    }

                    // Append NodeIds to edges array (child_lo/child_hi reference edges, not nodes!)
                    const child_lo = @as(u32, @intCast(parser.edges.items.len));
                    try parser.edges.append(parser.allocator, @enumFromInt(left_idx));
                    try parser.edges.append(parser.allocator, @enumFromInt(start_idx));
                    try parser.edges.append(parser.allocator, @enumFromInt(end_idx));
                    const child_hi = @as(u32, @intCast(parser.edges.items.len));

                    const slice_kind: astdb_core.AstNode.NodeKind = if (is_inclusive) .slice_inclusive_expr else .slice_exclusive_expr;
                    return astdb_core.AstNode{
                        .kind = slice_kind,
                        .first_token = @enumFromInt(parser.current - 1),
                        .last_token = @enumFromInt(parser.current - 1),
                        .child_lo = child_lo,
                        .child_hi = child_hi,
                    };
                } else {
                    // Regular indexing: left[expr]
                    const index_expr = try parseExpression(parser, &parser.nodes, .none);
                    _ = try parser.consume(.right_bracket);

                    // Append child nodes to nodes array and get their indices
                    const left_idx = @as(u32, @intCast(parser.nodes.items.len));
                    try parser.nodes.append(parser.allocator, left);
                    const index_idx = @as(u32, @intCast(parser.nodes.items.len));
                    try parser.nodes.append(parser.allocator, index_expr);

                    // Append NodeIds to edges array (child_lo/child_hi reference edges, not nodes!)
                    const child_lo = @as(u32, @intCast(parser.edges.items.len));
                    try parser.edges.append(parser.allocator, @enumFromInt(left_idx));
                    try parser.edges.append(parser.allocator, @enumFromInt(index_idx));
                    const child_hi = @as(u32, @intCast(parser.edges.items.len));

                    left = astdb_core.AstNode{
                        .kind = .index_expr,
                        .first_token = @enumFromInt(parser.current - 1),
                        .last_token = @enumFromInt(parser.current - 1),
                        .child_lo = child_lo,
                        .child_hi = child_hi,
                    };
                }
            },
            .catch_ => {
                // Parse catch expression: expr catch err { block }
                _ = parser.advance(); // consume 'catch'

                const expr_idx = @as(u32, @intCast(parser.nodes.items.len));
                try parser.nodes.append(parser.allocator, left);

                // Error variable binding: catch err { ... }
                // The identifier is required (not optional)
                _ = try parser.consume(.identifier);

                // Parse catch block
                _ = try parser.consume(.left_brace);
                var catch_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 4);
                defer catch_stmts.deinit(parser.allocator);

                try parseBlockStatements(parser, nodes, &catch_stmts);
                _ = try parser.consume(.right_brace);

                // Build catch node
                const child_lo = @as(u32, @intCast(parser.edges.items.len));
                try parser.edges.append(parser.allocator, @enumFromInt(expr_idx));
                try parser.edges.appendSlice(parser.allocator, catch_stmts.items);
                const child_hi = @as(u32, @intCast(parser.edges.items.len));

                left = astdb_core.AstNode{
                    .kind = .catch_expr,
                    .first_token = left.first_token,
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            .question => {
                // Parse try operator: expr?
                _ = parser.advance(); // consume '?'

                const expr_idx = @as(u32, @intCast(parser.nodes.items.len));
                try parser.nodes.append(parser.allocator, left);

                const child_lo = @as(u32, @intCast(parser.edges.items.len));
                try parser.edges.append(parser.allocator, @enumFromInt(expr_idx));
                const child_hi = @as(u32, @intCast(parser.edges.items.len));

                left = astdb_core.AstNode{
                    .kind = .try_expr,
                    .first_token = left.first_token,
                    .last_token = @enumFromInt(parser.current - 1),
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            else => break,
        }
    }

    // Parse binary operators with precedence
    while (true) {
        // Skip newlines before checking for binary operator
        while (parser.match(.newline)) _ = parser.advance();

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
                        try nodes.append(parser.allocator, param_ident);
                    }
                    if (parser.match(.pipe)) _ = parser.advance();
                }

                // parse handler body until 'end'
                const handler_lo = @as(u32, @intCast(nodes.items.len));
                var dummy_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
                defer dummy_stmts.deinit(parser.allocator);
                try parseBlockStatements(parser, nodes, &dummy_stmts);
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
                try nodes.append(parser.allocator, left);
                try nodes.append(parser.allocator, handler_block);
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
            const range_kind: astdb_core.AstNode.NodeKind = if (token.kind == .range_inclusive) .range_inclusive_expr else .range_exclusive_expr;
            _ = parser.advance(); // consume range operator
            const right = try parseExpression(parser, nodes, token_prec);

            // Create range expression node
            const left_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, left);

            const right_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, right);

            const child_lo = @as(u32, @intCast(parser.edges.items.len));
            try parser.edges.append(parser.allocator, @enumFromInt(left_idx));
            try parser.edges.append(parser.allocator, @enumFromInt(right_idx));
            const child_hi = @as(u32, @intCast(parser.edges.items.len));

            left = astdb_core.AstNode{
                .kind = range_kind,
                .first_token = left.first_token,
                .last_token = right.last_token,
                .child_lo = child_lo,
                .child_hi = child_hi,
            };
            continue;
        }

        // Handle pipeline operator (|>) - Desugar to call_expr
        if (token.kind == .pipeline) {
            _ = parser.advance(); // consume |>
            // Parse RHS with .call precedence for left-associativity
            // This ensures chained pipelines are handled iteratively, not recursively
            // e.g., 1 |> inc() |> print() -> (1 |> inc()) |> print()
            const rhs = try parseExpression(parser, nodes, .call);

            // Desugar logic: LHS |> RHS -> RHS(LHS, ...)
            const child_lo = @as(u32, @intCast(parser.edges.items.len));

            if (rhs.kind == .call_expr) {
                // Copy original edges to avoid stale slice if parser.edges reallocates
                var orig_edges_buf = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, rhs.child_hi - rhs.child_lo);
                defer orig_edges_buf.deinit(parser.allocator);
                orig_edges_buf.appendSliceAssumeCapacity(parser.edges.items[rhs.child_lo..rhs.child_hi]);
                const orig_edges = orig_edges_buf.items;

                // 1. Function callee
                try parser.edges.append(parser.allocator, orig_edges[0]);

                // 2. Injected LHS as first argument
                const left_node_idx = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, left);
                try parser.edges.append(parser.allocator, @enumFromInt(left_node_idx));

                // 3. Original arguments
                if (orig_edges.len > 1) {
                    try parser.edges.appendSlice(parser.allocator, orig_edges[1..]);
                }
            } else {
                // create call: rhs(left)
                const rhs_idx = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, rhs);
                try parser.edges.append(parser.allocator, @enumFromInt(rhs_idx));

                const left_idx = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, left);
                try parser.edges.append(parser.allocator, @enumFromInt(left_idx));
            }

            const child_hi = @as(u32, @intCast(parser.edges.items.len));
            const desugared_call = astdb_core.AstNode{
                .kind = .call_expr,
                .first_token = left.first_token,
                .last_token = rhs.last_token,
                .child_lo = child_lo,
                .child_hi = child_hi,
            };

            // Add the desugared call to nodes so it can be referenced by subsequent operations
            try nodes.append(parser.allocator, desugared_call);

            // Update left to be a reference to the node we just added
            left = desugared_call;
            left.child_lo = child_lo; // Preserve the edge indices
            left.child_hi = child_hi;

            continue;
        }

        _ = parser.advance(); // consume operator
        const right = try parseExpression(parser, nodes, token_prec);

        // Append children to nodes array
        const left_idx = @as(u32, @intCast(nodes.items.len));
        try nodes.append(parser.allocator, left);

        const right_idx = @as(u32, @intCast(nodes.items.len));
        try nodes.append(parser.allocator, right);

        // Add edges
        const child_lo = @as(u32, @intCast(parser.edges.items.len));
        try parser.edges.append(parser.allocator, @enumFromInt(left_idx));
        try parser.edges.append(parser.allocator, @enumFromInt(right_idx));
        const child_hi = @as(u32, @intCast(parser.edges.items.len));

        left = astdb_core.AstNode{
            .kind = .binary_expr,
            .first_token = left.first_token,
            .last_token = right.last_token,
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

    var array_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 4);
    defer array_edges.deinit(parser.allocator);

    // Parse elements
    while (!parser.match(.right_bracket) and parser.peek() != null) {
        const elem = try parseExpression(parser, nodes, .none);
        const elem_idx = @as(u32, @intCast(nodes.items.len));
        try nodes.append(parser.allocator, elem);
        try array_edges.append(parser.allocator, @enumFromInt(elem_idx));

        // Optional comma
        if (parser.match(.comma)) {
            _ = parser.advance();
        }
    }

    // Consume ']'
    _ = try parser.consume(.right_bracket);

    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, array_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

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
        switch (token.kind) {
            .not_, .logical_not, .exclamation, .minus, .tilde, .bitwise_not => {
                const op_idx = parser.current;
                _ = parser.advance();
                // Use parseExpression to handle nested unary and compound expressions
                const expr = try parseExpression(parser, nodes, .unary);
                const child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, expr);
                const child_hi = @as(u32, @intCast(nodes.items.len));

                return astdb_core.AstNode{
                    .kind = .unary_expr,
                    .first_token = @enumFromInt(op_idx),
                    .last_token = expr.last_token,
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
            .struct_kw => {
                // Parse struct literal/definition
                return try parseStructDeclaration(parser, nodes);
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
            .float_literal => {
                _ = parser.advance();
                return astdb_core.AstNode{
                    .kind = .float_literal,
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
            .char_literal => {
                _ = parser.advance();
                return astdb_core.AstNode{
                    .kind = .char_literal,
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
            .left_bracket => {
                return try parseArrayLiteral(parser, nodes);
            },
            .match => {
                return try parseMatchStatement(parser, nodes);
            },
            .identifier => {
                // Lookahead for struct literal: Identifier '{'
                const id_index = parser.current;
                _ = parser.advance(); // consume identifier

                // Disambiguate: Struct Literal vs Block
                // Struct literal: { ident : ... } or { }
                // Block: { ident ... } or { ... }

                var is_struct_literal = false;
                if (parser.match(.left_brace)) {
                    const next_idx = parser.current + 1;
                    if (next_idx < parser.tokens.len) {
                        const next_tok = parser.tokens[next_idx];
                        if (next_tok.kind == .right_brace) {
                            is_struct_literal = true; // Empty struct: T {}
                        } else if (next_tok.kind == .identifier) {
                            const after_idx = parser.current + 2;
                            if (after_idx < parser.tokens.len) {
                                if (parser.tokens[after_idx].kind == .colon) {
                                    is_struct_literal = true; // T { f : ... }
                                }
                            }
                        }
                    }
                }

                if (is_struct_literal) {
                    // Struct Literal: Type { field: val, ... }
                    _ = try parser.consume(.left_brace);

                    var struct_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 8);
                    defer struct_edges.deinit(parser.allocator);

                    // First child: type identifier
                    const type_ident = astdb_core.AstNode{
                        .kind = .identifier,
                        .first_token = @enumFromInt(id_index),
                        .last_token = @enumFromInt(id_index),
                        .child_lo = 0, // leaf
                        .child_hi = 0,
                    };
                    const type_idx = @as(u32, @intCast(nodes.items.len));
                    try nodes.append(parser.allocator, type_ident);
                    try struct_edges.append(parser.allocator, @enumFromInt(type_idx));

                    // Parse field initializers: name ':' expr (comma-separated)
                    while (!parser.match(.right_brace) and parser.peek() != null) {
                        // Skip newlines/whitespace check is implicit in match/advance
                        while (parser.match(.newline)) _ = parser.advance();
                        if (parser.match(.right_brace)) break;

                        // Field Name
                        if (!parser.match(.identifier)) return error.UnexpectedToken;
                        const field_name_idx = parser.current;
                        _ = parser.advance();

                        const field_name = astdb_core.AstNode{
                            .kind = .identifier,
                            .first_token = @enumFromInt(field_name_idx),
                            .last_token = @enumFromInt(field_name_idx),
                            .child_lo = 0,
                            .child_hi = 0,
                        };
                        const name_node_idx = @as(u32, @intCast(nodes.items.len));
                        try nodes.append(parser.allocator, field_name);
                        try struct_edges.append(parser.allocator, @enumFromInt(name_node_idx));

                        // Colon
                        _ = try parser.consume(.colon);

                        // Value
                        const value_expr = try parseExpression(parser, nodes, .none);
                        const val_node_idx = @as(u32, @intCast(nodes.items.len));
                        try nodes.append(parser.allocator, value_expr);
                        try struct_edges.append(parser.allocator, @enumFromInt(val_node_idx));

                        // Comma
                        if (parser.match(.comma)) {
                            _ = parser.advance();
                        } else if (!parser.match(.right_brace)) {
                            // lenient
                        }
                    }
                    _ = try parser.consume(.right_brace);

                    const child_lo = @as(u32, @intCast(parser.edges.items.len));
                    try parser.edges.appendSlice(parser.allocator, struct_edges.items);
                    const child_hi = @as(u32, @intCast(parser.edges.items.len));

                    return astdb_core.AstNode{
                        .kind = .struct_literal,
                        .first_token = @enumFromInt(id_index),
                        .last_token = @enumFromInt(parser.current - 1),
                        .child_lo = child_lo,
                        .child_hi = child_hi,
                    };
                } else {
                    // Variable Identifier
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
            .bitwise_and => {
                // Address-of operator: &expr (more flexible)
                _ = parser.advance(); // consume '&'
                const expr = try parsePrimary(parser, nodes);
                const child_lo = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, expr);
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
                try nodes.append(parser.allocator, expr);
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
                try nodes.append(parser.allocator, base_type);
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
            .await_ => {
                // :service profile - await expression
                const await_token = parser.current;
                _ = parser.advance(); // consume 'await'
                const awaited_expr = try parseExpression(parser, nodes, .unary);

                // Store child node and add to edges
                const expr_idx = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, awaited_expr);

                const child_lo = @as(u32, @intCast(parser.edges.items.len));
                try parser.edges.append(parser.allocator, @enumFromInt(expr_idx));
                const child_hi = @as(u32, @intCast(parser.edges.items.len));

                return astdb_core.AstNode{
                    .kind = .await_expr,
                    .first_token = @enumFromInt(await_token),
                    .last_token = awaited_expr.last_token,
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            .spawn_ => {
                // :service profile - spawn expression
                const spawn_token = parser.current;
                _ = parser.advance(); // consume 'spawn'
                const spawned_expr = try parseExpression(parser, nodes, .unary);

                // Store child node and add to edges
                const expr_idx = @as(u32, @intCast(nodes.items.len));
                try nodes.append(parser.allocator, spawned_expr);

                const child_lo = @as(u32, @intCast(parser.edges.items.len));
                try parser.edges.append(parser.allocator, @enumFromInt(expr_idx));
                const child_hi = @as(u32, @intCast(parser.edges.items.len));

                return astdb_core.AstNode{
                    .kind = .spawn_expr,
                    .first_token = @enumFromInt(spawn_token),
                    .last_token = spawned_expr.last_token,
                    .child_lo = child_lo,
                    .child_hi = child_hi,
                };
            },
            else => return error.UnexpectedToken,
        }
    }
    return error.UnexpectedToken;
}

/// Parse a constant declaration: const name: type = value;
fn parseConstDeclaration(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) !astdb_core.AstNode {
    const start_token = parser.current;
    _ = try parser.consume(.const_);

    const children_start = @as(u32, @intCast(parser.edges.items.len));

    // Identifier
    _ = try parser.consume(.identifier);
    const ident_node = astdb_core.AstNode{
        .kind = .identifier,
        .first_token = @enumFromInt(parser.current - 1),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = 0,
        .child_hi = 0,
    };
    const ident_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, ident_node);
    try parser.edges.append(parser.allocator, @enumFromInt(ident_idx));

    // Optional type annotation
    if (parser.match(.colon)) {
        _ = parser.advance();
        // Parse type - simplified
        if (parser.match(.identifier) or parser.match(.type_)) {
            _ = parser.advance();
            // TODO: Add type node
        }
    }

    // Assignment
    if (parser.match(.equal) or parser.match(.walrus_assign)) {
        _ = parser.advance();
    }

    // Expression
    const expr = try parseExpression(parser, nodes, .none);
    const expr_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, expr);
    try parser.edges.append(parser.allocator, @enumFromInt(expr_idx));

    // Semicolon?
    if (parser.match(.semicolon)) {
        _ = parser.advance();
    }

    return astdb_core.AstNode{
        .kind = .const_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = children_start,
        .child_hi = @as(u32, @intCast(parser.edges.items.len)),
    };
}

/// Parse a let statement: let name: type = value;
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
        type_node = try parseType(parser, nodes);
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

    // Add children to nodes and record edges
    const child_lo = @as(u32, @intCast(parser.edges.items.len));

    // Identifier
    const ident_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, identifier_node);
    try parser.edges.append(parser.allocator, @enumFromInt(ident_idx));

    // Type
    if (type_node) |t| {
        const type_idx = @as(u32, @intCast(nodes.items.len));
        try nodes.append(parser.allocator, t);
        try parser.edges.append(parser.allocator, @enumFromInt(type_idx));
    }

    // Initializer
    if (has_initializer) {
        if (init_node) |e| {
            const init_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, e);
            try parser.edges.append(parser.allocator, @enumFromInt(init_idx));
        }
    }

    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .var_stmt,
        .first_token = @enumFromInt(0), // approximated
        .last_token = @enumFromInt(0),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse a match statement: match expr { pattern => body, ... } OR match expr do pattern => body end
fn parseMatchStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const match_start_token = parser.current;
    _ = try parser.consume(.match);

    // Parse expression
    const expr = try parseExpression(parser, nodes, .none);
    const expr_idx = @as(u32, @intCast(nodes.items.len));
    try nodes.append(parser.allocator, expr);

    // Parse match body - support both { } and do...end
    const use_do_end = parser.match(.do_);

    if (use_do_end) {
        _ = try parser.consume(.do_);
    } else {
        _ = try parser.consume(.left_brace);
    }

    // Track match arms in edges array
    var match_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer match_edges.deinit(parser.allocator);

    // Add scrutinee expression to edges
    try match_edges.append(parser.allocator, @enumFromInt(expr_idx));

    const end_token: TokenKind = if (use_do_end) .end else .right_brace;

    while (!parser.match(end_token) and !parser.match(.eof)) {
        while (parser.match(.newline)) _ = parser.advance();
        if (parser.match(end_token)) break; // Check again after skipping newlines

        // Parse match arm
        const arm_start = parser.current;
        var arm_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 3);
        defer arm_edges.deinit(parser.allocator);

        // Parse pattern (for now, just an expression or identifier)
        // TODO: Implement full pattern parsing
        const pattern = try parseExpression(parser, nodes, .none);
        const pattern_idx = @as(u32, @intCast(nodes.items.len));
        try nodes.append(parser.allocator, pattern);
        try arm_edges.append(parser.allocator, @enumFromInt(pattern_idx));

        // Optional guard: when expr
        if (parser.match(.when)) {
            _ = parser.advance();
            const guard = try parseExpression(parser, nodes, .none);
            const guard_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, guard);
            try arm_edges.append(parser.allocator, @enumFromInt(guard_idx));
        } else {
            // Placeholder for no guard (using null literal for now to keep child count consistent)
            const null_node = astdb_core.AstNode{
                .kind = .null_literal,
                .first_token = @enumFromInt(parser.current),
                .last_token = @enumFromInt(parser.current),
                .child_lo = 0,
                .child_hi = 0,
            };
            const null_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, null_node);
            try arm_edges.append(parser.allocator, @enumFromInt(null_idx));
        }

        _ = try parser.consume(.arrow); // => (converted from match_arrow)

        // Parse body (block or expression)
        if (parser.match(.left_brace)) {
            const block_start_token = parser.current;
            _ = try parser.consume(.left_brace);

            var body_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
            defer body_stmts.deinit(parser.allocator);
            try parseBlockStatements(parser, nodes, &body_stmts);

            _ = try parser.consume(.right_brace);

            const block_lo = @as(u32, @intCast(parser.edges.items.len));
            try parser.edges.appendSlice(parser.allocator, body_stmts.items);
            const block_hi = @as(u32, @intCast(parser.edges.items.len));

            const block_node = astdb_core.AstNode{
                .kind = .block_stmt,
                .first_token = @enumFromInt(block_start_token),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = block_lo,
                .child_hi = block_hi,
            };
            const block_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, block_node);
            try arm_edges.append(parser.allocator, @enumFromInt(block_idx));
        } else {
            const body_expr = try parseExpression(parser, nodes, .none);
            const body_idx = @as(u32, @intCast(nodes.items.len));
            try nodes.append(parser.allocator, body_expr);
            try arm_edges.append(parser.allocator, @enumFromInt(body_idx));
            // Optional comma
            if (parser.match(.comma)) _ = parser.advance();
        }

        // Create arm node with edges for pattern, guard, body
        const arm_child_lo = @as(u32, @intCast(parser.edges.items.len));
        try parser.edges.appendSlice(parser.allocator, arm_edges.items);
        const arm_child_hi = @as(u32, @intCast(parser.edges.items.len));

        const arm_end = parser.current - 1;
        const arm_node = astdb_core.AstNode{
            .kind = .match_arm,
            .first_token = @enumFromInt(arm_start),
            .last_token = @enumFromInt(arm_end),
            .child_lo = arm_child_lo,
            .child_hi = arm_child_hi,
        };
        const arm_idx = @as(u32, @intCast(nodes.items.len));
        try nodes.append(parser.allocator, arm_node);

        // Add arm to edges
        try match_edges.append(parser.allocator, @enumFromInt(arm_idx));
    }

    _ = try parser.consume(end_token);

    // Add edges to parser.edges and get range
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, match_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .match_stmt,
        .first_token = @enumFromInt(match_start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}

/// Parse an if statement: if (condition) { ... } else { ... }
fn parseIfStatement(parser: *ParserState, nodes: *std.ArrayList(astdb_core.AstNode)) error{ UnexpectedToken, OutOfMemory }!astdb_core.AstNode {
    const start_token = parser.current;

    // Consume 'if' keyword
    _ = try parser.consume(.if_);

    // Two forms supported: (cond) { ... }  OR  cond do ... [else do ...] end
    var used_do_end = false;
    var if_edges = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 3);
    defer if_edges.deinit(parser.allocator);

    // 1. Condition
    if (parser.match(.left_paren)) {
        _ = parser.advance();
        const cond = try parseExpression(parser, nodes, .none);
        const cond_idx = @as(u32, @intCast(parser.nodes.items.len));
        try parser.nodes.append(parser.allocator, cond);
        try if_edges.append(parser.allocator, @enumFromInt(cond_idx));
        _ = try parser.consume(.right_paren);
    } else {
        const cond = try parseExpression(parser, nodes, .none);
        const cond_idx = @as(u32, @intCast(parser.nodes.items.len));
        try parser.nodes.append(parser.allocator, cond);
        try if_edges.append(parser.allocator, @enumFromInt(cond_idx));
    }

    // 2. Then Block
    var then_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
    defer then_stmts.deinit(parser.allocator);

    if (parser.match(.do_)) {
        _ = parser.advance();
        used_do_end = true;
        try parseBlockStatements(parser, nodes, &then_stmts);
    } else if (parser.match(.left_brace)) {
        _ = parser.advance();
        try parseBlockStatements(parser, nodes, &then_stmts);
        _ = try parser.consume(.right_brace);
    } else {
        // :min style permissive (implicit do)
        used_do_end = true;
        try parseBlockStatements(parser, nodes, &then_stmts);
    }

    // Create Then Block Node
    const then_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, then_stmts.items);
    const then_hi = @as(u32, @intCast(parser.edges.items.len));

    const then_block = astdb_core.AstNode{
        .kind = .block_stmt,
        .first_token = @enumFromInt(start_token), // Approximate
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = then_lo,
        .child_hi = then_hi,
    };
    const then_idx = @as(u32, @intCast(parser.nodes.items.len));
    try parser.nodes.append(parser.allocator, then_block);
    try if_edges.append(parser.allocator, @enumFromInt(then_idx));

    // 3. Else Clause
    if (parser.match(.else_)) {
        _ = parser.advance();

        if (parser.match(.if_)) {
            // else if ... -> recursive call
            const else_if_node = try parseIfStatement(parser, nodes);
            const else_if_idx = @as(u32, @intCast(parser.nodes.items.len));
            try parser.nodes.append(parser.allocator, else_if_node);
            try if_edges.append(parser.allocator, @enumFromInt(else_if_idx));
        } else {
            // else ... -> parse block
            var else_stmts = try std.ArrayList(astdb_core.NodeId).initCapacity(parser.allocator, 0);
            defer else_stmts.deinit(parser.allocator);

            if (parser.match(.do_)) {
                _ = parser.advance();
                try parseBlockStatements(parser, nodes, &else_stmts);
                if (used_do_end) _ = try parser.consume(.end);
            } else if (parser.match(.left_brace)) {
                _ = parser.advance();
                try parseBlockStatements(parser, nodes, &else_stmts);
                _ = try parser.consume(.right_brace);
            } else {
                // Implicit do
                try parseBlockStatements(parser, nodes, &else_stmts);
                if (used_do_end) _ = try parser.consume(.end);
            }

            // Create Else Block Node
            const else_lo = @as(u32, @intCast(parser.edges.items.len));
            try parser.edges.appendSlice(parser.allocator, else_stmts.items);
            const else_hi = @as(u32, @intCast(parser.edges.items.len));

            const else_block = astdb_core.AstNode{
                .kind = .block_stmt,
                .first_token = @enumFromInt(parser.current - 1),
                .last_token = @enumFromInt(parser.current - 1),
                .child_lo = else_lo,
                .child_hi = else_hi,
            };
            const else_idx = @as(u32, @intCast(parser.nodes.items.len));
            try parser.nodes.append(parser.allocator, else_block);
            try if_edges.append(parser.allocator, @enumFromInt(else_idx));
        }
    } else {
        // No else
        if (used_do_end) {
            _ = try parser.consume(.end);
        }
    }

    // Commit edges
    const child_lo = @as(u32, @intCast(parser.edges.items.len));
    try parser.edges.appendSlice(parser.allocator, if_edges.items);
    const child_hi = @as(u32, @intCast(parser.edges.items.len));

    return astdb_core.AstNode{
        .kind = .if_stmt,
        .first_token = @enumFromInt(start_token),
        .last_token = @enumFromInt(parser.current - 1),
        .child_lo = child_lo,
        .child_hi = child_hi,
    };
}
