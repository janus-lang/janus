// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const query = @import("query.zig");

// ASTDB Query Language Parser - Parse query expressions from CLI/LSP
// Task 6: CLI Tooling - Query language syntax and parsing
// Requirements: Support predicates and combinators from SPEC-astdb-query.md

const Predicate = query.Predicate;
const CompareOp = query.CompareOp;
const DeclKind = query.DeclKind;
const NodeKind = query.NodeKind; // Re-exported from astdb_core.AstNode.NodeKind

pub const QueryParseError = error{
    UnexpectedToken,
    UnexpectedEOF,
    InvalidNodeKind,
    InvalidDeclKind,
    InvalidOperator,
    InvalidNumber,
    MissingOperand,
    UnbalancedParentheses,
    OutOfMemory,
};

pub const QueryParser = struct {
    tokens: []const Token,
    pos: usize,
    allocator: std.mem.Allocator,

    const Token = struct {
        kind: TokenType,
        text: []const u8,

        const TokenType = enum {
            // Literals
            identifier,
            string_literal,
            number,

            // Keywords
            kw_func,
            kw_var,
            kw_const,
            kw_struct,
            kw_enum,
            kw_where,
            kw_and,
            kw_or,
            kw_not,
            kw_has,
            kw_contains,
            kw_requires,
            kw_effects,
            kw_capabilities,
            kw_profile,

            // Operators
            eq, // ==
            ne, // !=
            lt, // <
            le, // <=
            gt, // >
            ge, // >=
            dot, // .

            // Delimiters
            lparen, // (
            rparen, // )
            comma, // ,

            // Special
            eof,
        };
    };

    pub fn init(allocator: std.mem.Allocator, input: []const u8) !QueryParser {
        const tokens = try tokenize(allocator, input);
        return QueryParser{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *QueryParser) void {
        self.allocator.free(self.tokens);
    }

    /// Parse a complete query expression
    /// Grammar: query := predicate
    pub fn parseQuery(self: *QueryParser) (QueryParseError || std.mem.Allocator.Error)!Predicate {
        const predicate = try self.parseOrExpression();
        if (!self.isAtEnd()) {
            return QueryParseError.UnexpectedToken;
        }
        return predicate;
    }

    /// Parse OR expression (lowest precedence)
    /// Grammar: or_expr := and_expr ('or' and_expr)*
    fn parseOrExpression(self: *QueryParser) (QueryParseError || std.mem.Allocator.Error)!Predicate {
        var left = try self.parseAndExpression();

        while (self.match(.kw_or)) {
            const right = try self.parseAndExpression();

            // Allocate predicate on heap (in real implementation, use arena)
            const left_ptr = try self.allocator.create(Predicate);
            const right_ptr = try self.allocator.create(Predicate);
            left_ptr.* = left;
            right_ptr.* = right;

            left = Predicate{ .or_ = .{ .left = left_ptr, .right = right_ptr } };
        }

        return left;
    }

    /// Parse AND expression
    /// Grammar: and_expr := not_expr ('and' not_expr)*
    fn parseAndExpression(self: *QueryParser) (QueryParseError || std.mem.Allocator.Error)!Predicate {
        var left = try self.parseNotExpression();

        while (self.match(.kw_and)) {
            const right = try self.parseNotExpression();

            const left_ptr = try self.allocator.create(Predicate);
            const right_ptr = try self.allocator.create(Predicate);
            left_ptr.* = left;
            right_ptr.* = right;

            left = Predicate{ .and_ = .{ .left = left_ptr, .right = right_ptr } };
        }

        return left;
    }

    /// Parse NOT expression
    /// Grammar: not_expr := 'not' primary | primary
    fn parseNotExpression(self: *QueryParser) (QueryParseError || std.mem.Allocator.Error)!Predicate {
        if (self.match(.kw_not)) {
            const inner = try self.parsePrimary();
            const inner_ptr = try self.allocator.create(Predicate);
            inner_ptr.* = inner;
            return Predicate{ .not_ = inner_ptr };
        }

        return self.parsePrimary();
    }

    /// Parse primary expression
    /// Grammar: primary := '(' or_expr ')' | node_predicate | decl_predicate | effect_predicate
    fn parsePrimary(self: *QueryParser) (QueryParseError || std.mem.Allocator.Error)!Predicate {
        if (self.match(.lparen)) {
            const expr = try self.parseOrExpression();
            if (!self.match(.rparen)) {
                return QueryParseError.UnbalancedParentheses;
            }
            return expr;
        }

        // Try to parse different predicate types
        if (self.check(.kw_func) or self.check(.kw_var) or self.check(.kw_const) or
            self.check(.kw_struct) or self.check(.kw_enum))
        {
            return self.parseNodeKindPredicate();
        }

        if (self.check(.identifier)) {
            _ = self.peek(); // Get token but don't use it yet

            // Look ahead to determine predicate type
            if (self.pos + 1 < self.tokens.len) {
                const next_token = self.tokens[self.pos + 1];

                if (next_token.kind == .dot) {
                    return self.parsePropertyPredicate();
                } else if (isComparisonOperator(next_token.kind)) {
                    return self.parseComparisonPredicate();
                }
            }

            // Default to identifier predicate
            return self.parseIdentifierPredicate();
        }

        return QueryParseError.UnexpectedToken;
    }

    /// Parse node kind predicate (func, var, const, struct, enum)
    fn parseNodeKindPredicate(self: *QueryParser) QueryParseError!Predicate {
        const token = self.advance();
        const node_kind = switch (token.kind) {
            .kw_func => NodeKind.func_decl,
            .kw_var => NodeKind.var_stmt,
            .kw_const => NodeKind.const_stmt,
            .kw_struct => NodeKind.struct_decl,
            .kw_enum => NodeKind.enum_decl,
            else => return QueryParseError.InvalidNodeKind,
        };

        return Predicate{ .node_kind = node_kind };
    }

    /// Parse property predicate (identifier.property)
    fn parsePropertyPredicate(self: *QueryParser) QueryParseError!Predicate {
        const subject = self.advance(); // identifier
        _ = self.advance(); // dot
        const property = self.advance(); // property name

        if (std.mem.eql(u8, property.text, "effects")) {
            if (self.match(.dot) and self.match(.identifier)) {
                const method = self.previous();
                if (std.mem.eql(u8, method.text, "contains")) {
                    if (self.match(.lparen) and self.match(.string_literal)) {
                        const effect_name = self.previous();
                        if (self.match(.rparen)) {
                            return Predicate{ .effect_contains = effect_name.text };
                        }
                    }
                }
            }
            return Predicate{ .has_effect = subject.text };
        }

        if (std.mem.eql(u8, property.text, "capabilities")) {
            return Predicate{ .requires_capability = subject.text };
        }

        // Default property access
        return QueryParseError.UnexpectedToken;
    }

    /// Parse comparison predicate (identifier op value)
    fn parseComparisonPredicate(self: *QueryParser) QueryParseError!Predicate {
        const identifier = self.advance();
        const op_token = self.advance();
        const value_token = self.advance();

        const op: CompareOp = switch (op_token.kind) {
            .eq => .eq,
            .ne => .ne,
            .lt => .lt,
            .le => .le,
            .gt => .gt,
            .ge => .ge,
            else => return QueryParseError.InvalidOperator,
        };

        if (std.mem.eql(u8, identifier.text, "child_count")) {
            const value = std.fmt.parseInt(u32, value_token.text, 10) catch {
                return QueryParseError.InvalidNumber;
            };
            return Predicate{ .node_child_count = .{ .op = op, .value = value } };
        }

        return QueryParseError.UnexpectedToken;
    }

    /// Parse simple identifier predicate
    fn parseIdentifierPredicate(self: *QueryParser) QueryParseError!Predicate {
        const token = self.advance();

        // Try to match against known declaration kinds
        if (std.mem.eql(u8, token.text, "function")) {
            return Predicate{ .decl_kind = .function };
        } else if (std.mem.eql(u8, token.text, "variable")) {
            return Predicate{ .decl_kind = .variable };
        } else if (std.mem.eql(u8, token.text, "constant")) {
            return Predicate{ .decl_kind = .constant };
        }

        // Default to name-based predicate (would need string interning in real implementation)
        return QueryParseError.UnexpectedToken;
    }

    // Token manipulation helpers

    fn match(self: *QueryParser, kind: Token.TokenType) bool {
        if (self.check(kind)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn check(self: *QueryParser, kind: Token.TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().kind == kind;
    }

    fn advance(self: *QueryParser) Token {
        if (!self.isAtEnd()) self.pos += 1;
        return self.previous();
    }

    fn isAtEnd(self: *QueryParser) bool {
        return self.peek().kind == .eof;
    }

    fn peek(self: *QueryParser) Token {
        return self.tokens[self.pos];
    }

    fn previous(self: *QueryParser) Token {
        return self.tokens[self.pos - 1];
    }

    fn isComparisonOperator(kind: Token.TokenType) bool {
        return switch (kind) {
            .eq, .ne, .lt, .le, .gt, .ge => true,
            else => false,
        };
    }
};

/// Tokenize query string into tokens
fn tokenize(allocator: std.mem.Allocator, input: []const u8) ![]QueryParser.Token {
    var tokens = std.ArrayList(QueryParser.Token){};
    defer tokens.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        const c = input[i];

        // Skip whitespace
        if (std.ascii.isWhitespace(c)) {
            i += 1;
            continue;
        }

        // Single character tokens
        switch (c) {
            '(' => {
                try tokens.append(allocator, .{ .kind = .lparen, .text = input[i .. i + 1] });
                i += 1;
                continue;
            },
            ')' => {
                try tokens.append(allocator, .{ .kind = .rparen, .text = input[i .. i + 1] });
                i += 1;
                continue;
            },
            ',' => {
                try tokens.append(allocator, .{ .kind = .comma, .text = input[i .. i + 1] });
                i += 1;
                continue;
            },
            '.' => {
                try tokens.append(allocator, .{ .kind = .dot, .text = input[i .. i + 1] });
                i += 1;
                continue;
            },
            '<' => {
                if (i + 1 < input.len and input[i + 1] == '=') {
                    try tokens.append(allocator, .{ .kind = .le, .text = input[i .. i + 2] });
                    i += 2;
                } else {
                    try tokens.append(allocator, .{ .kind = .lt, .text = input[i .. i + 1] });
                    i += 1;
                }
                continue;
            },
            '>' => {
                if (i + 1 < input.len and input[i + 1] == '=') {
                    try tokens.append(allocator, .{ .kind = .ge, .text = input[i .. i + 2] });
                    i += 2;
                } else {
                    try tokens.append(allocator, .{ .kind = .gt, .text = input[i .. i + 1] });
                    i += 1;
                }
                continue;
            },
            '=' => {
                if (i + 1 < input.len and input[i + 1] == '=') {
                    try tokens.append(allocator, .{ .kind = .eq, .text = input[i .. i + 2] });
                    i += 2;
                } else {
                    i += 1; // Skip single =
                }
                continue;
            },
            '!' => {
                if (i + 1 < input.len and input[i + 1] == '=') {
                    try tokens.append(allocator, .{ .kind = .ne, .text = input[i .. i + 2] });
                    i += 2;
                } else {
                    i += 1; // Skip single !
                }
                continue;
            },
            else => {},
        }

        // String literals
        if (c == '"') {
            const start = i;
            i += 1; // Skip opening quote
            while (i < input.len and input[i] != '"') {
                i += 1;
            }
            if (i < input.len) {
                i += 1; // Skip closing quote
            }
            try tokens.append(allocator, .{ .kind = .string_literal, .text = input[start..i] });
            continue;
        }

        // Numbers
        if (std.ascii.isDigit(c)) {
            const start = i;
            while (i < input.len and std.ascii.isDigit(input[i])) {
                i += 1;
            }
            try tokens.append(allocator, .{ .kind = .number, .text = input[start..i] });
            continue;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            const start = i;
            while (i < input.len and (std.ascii.isAlphanumeric(input[i]) or input[i] == '_')) {
                i += 1;
            }

            const text = input[start..i];
            const kind = getKeywordType(text);
            try tokens.append(allocator, .{ .kind = kind, .text = text });
            continue;
        }

        // Unknown character - skip
        i += 1;
    }

    // Add EOF token
    try tokens.append(allocator, .{ .kind = .eof, .text = "" });

    return tokens.toOwnedSlice(allocator);
}

fn getKeywordType(text: []const u8) QueryParser.Token.TokenType {
    // Use inline switch for keyword matching (Zig 0.15+ compatible)
    const hash = blk: {
        var h: u32 = 0;
        for (text) |c| {
            h = h *% 31 +% c;
        }
        break :blk h;
    };
    _ = hash; // Used for potential optimization

    // Simple sequential matching (safe fallback)
    if (std.mem.eql(u8, text, "func")) return .kw_func;
    if (std.mem.eql(u8, text, "var")) return .kw_var;
    if (std.mem.eql(u8, text, "const")) return .kw_const;
    if (std.mem.eql(u8, text, "struct")) return .kw_struct;
    if (std.mem.eql(u8, text, "enum")) return .kw_enum;
    if (std.mem.eql(u8, text, "where")) return .kw_where;
    if (std.mem.eql(u8, text, "and")) return .kw_and;
    if (std.mem.eql(u8, text, "or")) return .kw_or;
    if (std.mem.eql(u8, text, "not")) return .kw_not;
    if (std.mem.eql(u8, text, "has")) return .kw_has;
    if (std.mem.eql(u8, text, "contains")) return .kw_contains;
    if (std.mem.eql(u8, text, "requires")) return .kw_requires;
    if (std.mem.eql(u8, text, "effects")) return .kw_effects;
    if (std.mem.eql(u8, text, "capabilities")) return .kw_capabilities;
    if (std.mem.eql(u8, text, "profile")) return .kw_profile;

    return .identifier;
}

test "QueryParser basic parsing" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test simple node kind predicate
    {
        var parser = try QueryParser.init(allocator, "func");
        defer parser.deinit();

        const predicate = try parser.parseQuery();
        try testing.expectEqual(Predicate.node_kind, std.meta.activeTag(predicate));
        try testing.expectEqual(NodeKind.func_decl, predicate.node_kind);
    }

    // Test AND combination
    {
        var parser = try QueryParser.init(allocator, "func and var");
        defer parser.deinit();

        const predicate = try parser.parseQuery();
        try testing.expectEqual(Predicate.and_, std.meta.activeTag(predicate));
    }

    // Test parentheses
    {
        var parser = try QueryParser.init(allocator, "(func or var) and struct");
        defer parser.deinit();

        const predicate = try parser.parseQuery();
        try testing.expectEqual(Predicate.and_, std.meta.activeTag(predicate));
    }

    std.log.info("✅ QueryParser basic parsing test passed", .{});
}

test "QueryParser tokenization" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const tokens = try tokenize(allocator, "func and child_count >= 2");
    defer allocator.free(tokens);

    try testing.expectEqual(@as(usize, 6), tokens.len); // func, and, child_count, >=, 2, eof
    try testing.expectEqual(QueryParser.Token.TokenType.kw_func, tokens[0].kind);
    try testing.expectEqual(QueryParser.Token.TokenType.kw_and, tokens[1].kind);
    try testing.expectEqual(QueryParser.Token.TokenType.identifier, tokens[2].kind);
    try testing.expectEqual(QueryParser.Token.TokenType.ge, tokens[3].kind);
    try testing.expectEqual(QueryParser.Token.TokenType.number, tokens[4].kind);
    try testing.expectEqual(QueryParser.Token.TokenType.eof, tokens[5].kind);

    std.log.info("✅ QueryParser tokenization test passed", .{});
}
