// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Janus Language Lexer - Real :min Profile Token Recognition
//!
//! This lexer tokenizes authentic Janus language syntax for the :min profile.
//! It replaces string-matching mockups with proper lexical analysis that
//! integrates with the ASTDB token system.
//!
//! Supports :min profile features:
//! - Keywords: func, let, var, if, else, while, for, return
//! - Operators: +, -, *, /, ==, !=, <, >, <=, >=, =
//! - Literals: integers, strings, booleans
//! - Proper source location tracking for error reporting

const std = @import("std");
const astdb = @import("../astdb/core_astdb.zig");

pub const LexError = error{
    UnterminatedString,
    InvalidCharacter,
    InvalidNumber,
    OutOfMemory,
};

/// Janus Language Lexer for :min profile
pub const JanusLexer = struct {
    source: []const u8,
    position: usize,
    current_line: u32,
    current_column: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) JanusLexer {
        return JanusLexer{
            .source = source,
            .position = 0,
            .current_line = 1,
            .current_column = 1,
            .allocator = allocator,
        };
    }

    pub fn nextToken(self: *JanusLexer) LexError!astdb.Token {
        self.skipWhitespace();

        if (self.position >= self.source.len) {
            return self.makeToken(.eof, null);
        }

        const start_pos = self.position;
        const start_line = self.current_line;
        const start_column = self.current_column;
        const c = self.source[self.position];

        switch (c) {
            // Single character tokens
            '(' => {
                self.advance();
                return self.makeTokenWithSpan(.left_paren, null, start_pos, start_line, start_column);
            },
            ')' => {
                self.advance();
                return self.makeTokenWithSpan(.right_paren, null, start_pos, start_line, start_column);
            },
            '{' => {
                self.advance();
                return self.makeTokenWithSpan(.left_brace, null, start_pos, start_line, start_column);
            },
            '}' => {
                self.advance();
                return self.makeTokenWithSpan(.right_brace, null, start_pos, start_line, start_column);
            },
            '[' => {
                self.advance();
                return self.makeTokenWithSpan(.left_bracket, null, start_pos, start_line, start_column);
            },
            ']' => {
                self.advance();
                return self.makeTokenWithSpan(.right_bracket, null, start_pos, start_line, start_column);
            },
            ',' => {
                self.advance();
                return self.makeTokenWithSpan(.comma, null, start_pos, start_line, start_column);
            },
            ';' => {
                self.advance();
                return self.makeTokenWithSpan(.semicolon, null, start_pos, start_line, start_column);
            },
            ':' => {
                self.advance();
                return self.makeTokenWithSpan(.colon, null, start_pos, start_line, start_column);
            },
            '+' => {
                self.advance();
                return self.makeTokenWithSpan(.plus, null, start_pos, start_line, start_column);
            },
            '-' => {
                self.advance();
                if (self.peek() == '>') {
                    self.advance();
                    return self.makeTokenWithSpan(.arrow, null, start_pos, start_line, start_column);
                }
                return self.makeTokenWithSpan(.minus, null, start_pos, start_line, start_column);
            },
            '*' => {
                self.advance();
                return self.makeTokenWithSpan(.star, null, start_pos, start_line, start_column);
            },
            '/' => {
                self.advance();
                // Check for comments
                if (self.peek() == '/') {
                    return self.lineComment(start_pos, start_line, start_column);
                }
                return self.makeTokenWithSpan(.slash, null, start_pos, start_line, start_column);
            },
            '=' => {
                self.advance();
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeTokenWithSpan(.equal_equal, null, start_pos, start_line, start_column);
                }
                if (self.peek() == '>') {
                    self.advance();
                    return self.makeTokenWithSpan(.arrow_fat, null, start_pos, start_line, start_column);
                }
                return self.makeTokenWithSpan(.assign, null, start_pos, start_line, start_column);
            },
            '!' => {
                self.advance();
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeTokenWithSpan(.not_equal, null, start_pos, start_line, start_column);
                }
                return self.makeTokenWithSpan(.exclamation, null, start_pos, start_line, start_column);
            },
            '<' => {
                self.advance();
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeTokenWithSpan(.less_equal, null, start_pos, start_line, start_column);
                }
                return self.makeTokenWithSpan(.less, null, start_pos, start_line, start_column);
            },
            '>' => {
                self.advance();
                if (self.peek() == '=') {
                    self.advance();
                    return self.makeTokenWithSpan(.greater_equal, null, start_pos, start_line, start_column);
                }
                return self.makeTokenWithSpan(.greater, null, start_pos, start_line, start_column);
            },
            '"' => return self.string(start_pos, start_line, start_column),
            '\n' => {
                self.advance();
                return self.makeTokenWithSpan(.newline, null, start_pos, start_line, start_column);
            },
            else => {
                std.debug.print("\n>>> nextToken: else branch, char='{c}' (0x{x})\n", .{ c, c });
                if (std.ascii.isDigit(c)) {
                    std.debug.print(">>> Calling number() for digit '{c}'\n", .{c});
                    return self.number(start_pos, start_line, start_column);
                } else if (std.ascii.isAlphabetic(c) or c == '_') {
                    return self.identifier(start_pos, start_line, start_column);
                } else {
                    return LexError.InvalidCharacter;
                }
            },
        }
    }

    pub fn peekToken(self: *JanusLexer) LexError!astdb.Token {
        const saved_position = self.position;
        const saved_line = self.current_line;
        const saved_column = self.current_column;

        const token = try self.nextToken();

        // Restore position
        self.position = saved_position;
        self.current_line = saved_line;
        self.current_column = saved_column;

        return token;
    }

    pub fn getCurrentSpan(self: *JanusLexer) astdb.SourceSpan {
        return astdb.SourceSpan{
            .start = @intCast(self.position),
            .end = @intCast(self.position),
            .line = self.current_line,
            .column = self.current_column,
        };
    }

    // Private helper methods

    fn advance(self: *JanusLexer) void {
        if (self.position < self.source.len) {
            if (self.source[self.position] == '\n') {
                self.current_line += 1;
                self.current_column = 1;
            } else {
                self.current_column += 1;
            }
            self.position += 1;
        }
    }

    fn peek(self: *JanusLexer) u8 {
        if (self.position >= self.source.len) return 0;
        return self.source[self.position];
    }

    fn peekNext(self: *JanusLexer) u8 {
        if (self.position + 1 >= self.source.len) return 0;
        return self.source[self.position + 1];
    }

    fn skipWhitespace(self: *JanusLexer) void {
        while (self.position < self.source.len) {
            const c = self.source[self.position];
            switch (c) {
                ' ', '\t', '\r' => self.advance(),
                else => break,
            }
        }
    }

    fn makeToken(self: *JanusLexer, kind: astdb.Token.TokenKind, str_id: ?astdb.StrId) astdb.Token {
        return astdb.Token{
            .kind = kind,
            .str = str_id,
            .span = astdb.SourceSpan{
                .start = @intCast(self.position),
                .end = @intCast(self.position),
                .line = self.current_line,
                .column = self.current_column,
            },
            .trivia_lo = 0,
            .trivia_hi = 0,
        };
    }

    fn makeTokenWithSpan(
        self: *JanusLexer,
        kind: astdb.Token.TokenKind,
        str_id: ?astdb.StrId,
        start_pos: usize,
        start_line: u32,
        start_column: u32,
    ) astdb.Token {
        return astdb.Token{
            .kind = kind,
            .str = str_id,
            .span = astdb.SourceSpan{
                .start = @intCast(start_pos),
                .end = @intCast(self.position),
                .line = start_line,
                .column = start_column,
            },
            .trivia_lo = 0,
            .trivia_hi = 0,
        };
    }

    fn string(self: *JanusLexer, start_pos: usize, start_line: u32, start_column: u32) LexError!astdb.Token {
        self.advance(); // Skip opening quote

        const string_start = self.position;
        while (self.position < self.source.len and self.source[self.position] != '"') {
            if (self.source[self.position] == '\\') {
                self.advance(); // Skip escape character
                if (self.position < self.source.len) {
                    self.advance(); // Skip escaped character
                }
            } else {
                self.advance();
            }
        }

        if (self.position >= self.source.len) {
            return LexError.UnterminatedString;
        }

        const string_content = self.source[string_start..self.position];
        self.advance(); // Skip closing quote

        // For now, we'll store the string content directly
        // In a full implementation, this would use the string interner
        _ = string_content; // TODO: Intern string
        const str_id: ?astdb.StrId = null; // TODO: Use string interner

        return self.makeTokenWithSpan(.string_literal, str_id, start_pos, start_line, start_column);
    }

    fn number(self: *JanusLexer, start_pos: usize, start_line: u32, start_column: u32) LexError!astdb.Token {
        std.debug.print("\n=== LEXER TRACE: number() ===\n", .{});
        std.debug.print("  Entry position: {d}\n", .{self.position});
        std.debug.print("  Entry char: '{c}'\n", .{self.source[self.position]});
        std.debug.print("  Source length: {d}\n", .{self.source.len});

        // Consume integer digits
        var digit_count: usize = 0;
        while (self.position < self.source.len and std.ascii.isDigit(self.source[self.position])) {
            std.debug.print("  Consuming digit '{c}' at pos {d}\n", .{ self.source[self.position], self.position });
            self.advance();
            digit_count += 1;
        }
        std.debug.print("  After digit loop: position={d}, consumed {d} digits\n", .{ self.position, digit_count });

        // Check for float
        std.debug.print("  Float check:\n", .{});
        std.debug.print("    position < source.len? {} ({d} < {d})\n", .{ self.position < self.source.len, self.position, self.source.len });

        if (self.position < self.source.len) {
            std.debug.print("    char at position: '{c}' (0x{x})\n", .{ self.source[self.position], self.source[self.position] });
            std.debug.print("    is '.'? {}\n", .{self.source[self.position] == '.'});

            if (self.source[self.position] == '.') {
                std.debug.print("    Found dot! Checking next char...\n", .{});
                std.debug.print("    position + 1 < source.len? {} ({d} < {d})\n", .{ self.position + 1 < self.source.len, self.position + 1, self.source.len });

                if (self.position + 1 < self.source.len) {
                    std.debug.print("    char after dot: '{c}'\n", .{self.source[self.position + 1]});
                    std.debug.print("    is digit? {}\n", .{std.ascii.isDigit(self.source[self.position + 1])});

                    if (std.ascii.isDigit(self.source[self.position + 1])) {
                        std.debug.print("  ✓ FLOAT DETECTED! Consuming fractional part...\n", .{});
                        self.advance(); // Skip '.'
                        while (self.position < self.source.len and std.ascii.isDigit(self.source[self.position])) {
                            self.advance();
                        }
                        std.debug.print("  Returning .float_literal\n", .{});
                        std.debug.print("=== END TRACE ===\n\n", .{});
                        return self.makeTokenWithSpan(.float_literal, null, start_pos, start_line, start_column);
                    }
                }
            }
        }

        std.debug.print("  → Returning .integer_literal\n", .{});
        std.debug.print("=== END TRACE ===\n\n", .{});
        return self.makeTokenWithSpan(.integer_literal, null, start_pos, start_line, start_column);
    }

    fn identifier(self: *JanusLexer, start_pos: usize, start_line: u32, start_column: u32) LexError!astdb.Token {
        while (self.position < self.source.len) {
            const c = self.source[self.position];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.advance();
            } else {
                break;
            }
        }

        const text = self.source[start_pos..self.position];
        const token_kind = self.getKeywordType(text);

        // TODO: Use string interner for identifier names
        const str_id: ?astdb.StrId = if (token_kind == .identifier) null else null;

        return self.makeTokenWithSpan(token_kind, str_id, start_pos, start_line, start_column);
    }

    fn lineComment(self: *JanusLexer, start_pos: usize, start_line: u32, start_column: u32) LexError!astdb.Token {
        // Skip the second '/'
        self.advance();

        while (self.position < self.source.len and self.source[self.position] != '\n') {
            self.advance();
        }

        return self.makeTokenWithSpan(.line_comment, null, start_pos, start_line, start_column);
    }

    fn getKeywordType(self: *JanusLexer, text: []const u8) astdb.Token.TokenKind {
        _ = self;

        // :min profile keywords
        if (std.mem.eql(u8, text, "func")) return .func;
        if (std.mem.eql(u8, text, "let")) return .let;
        if (std.mem.eql(u8, text, "var")) return .var_;
        if (std.mem.eql(u8, text, "if")) return .if_;
        if (std.mem.eql(u8, text, "else")) return .else_;
        if (std.mem.eql(u8, text, "while")) return .while_;
        if (std.mem.eql(u8, text, "for")) return .for_;
        if (std.mem.eql(u8, text, "return")) return .return_;
        if (std.mem.eql(u8, text, "break")) return .break_;
        if (std.mem.eql(u8, text, "continue")) return .continue_;
        if (std.mem.eql(u8, text, "in")) return .in_;

        // Boolean literals
        if (std.mem.eql(u8, text, "true")) return .true_;
        if (std.mem.eql(u8, text, "false")) return .false_;

        // Type keywords for :min profile
        if (std.mem.eql(u8, text, "i32")) return .identifier; // Types are identifiers in :min
        if (std.mem.eql(u8, text, "f64")) return .identifier;
        if (std.mem.eql(u8, text, "bool")) return .identifier;
        if (std.mem.eql(u8, text, "string")) return .identifier;

        return .identifier;
    }
};

// Unit tests for the lexer
test "JanusLexer - basic tokens" {
    const allocator = std.testing.allocator;
    const source = "func main() { let x = 42; }";

    var lexer = JanusLexer.init(allocator, source);

    const token1 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.func, token1.kind);

    const token2 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.identifier, token2.kind);

    const token3 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.left_paren, token3.kind);

    const token4 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.right_paren, token4.kind);

    const token5 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.left_brace, token5.kind);

    const token6 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.let, token6.kind);

    const token7 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.identifier, token7.kind);

    const token8 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.assign, token8.kind);

    const token9 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.integer_literal, token9.kind);

    const token10 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.semicolon, token10.kind);

    const token11 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.right_brace, token11.kind);

    const token12 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.eof, token12.kind);
}

test "JanusLexer - operators" {
    const allocator = std.testing.allocator;
    const source = "+ - * / == != < > <= >=";

    var lexer = JanusLexer.init(allocator, source);

    const expected_tokens = [_]astdb.Token.TokenKind{
        .plus, .minus,   .star,       .slash,         .equal_equal, .not_equal,
        .less, .greater, .less_equal, .greater_equal, .eof,
    };

    for (expected_tokens) |expected| {
        const token = try lexer.nextToken();
        try std.testing.expectEqual(expected, token.kind);
    }
}

test "JanusLexer - string literals" {
    const allocator = std.testing.allocator;
    const source = "\"hello world\" \"escaped\\\"quote\"";

    var lexer = JanusLexer.init(allocator, source);

    const token1 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.string_literal, token1.kind);

    const token2 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.string_literal, token2.kind);

    const token3 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.eof, token3.kind);
}

test "JanusLexer - keywords vs identifiers" {
    const allocator = std.testing.allocator;
    const source = "func function let letter if ifx";

    var lexer = JanusLexer.init(allocator, source);

    const token1 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.func, token1.kind);

    const token2 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.identifier, token2.kind);

    const token3 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.let, token3.kind);

    const token4 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.identifier, token4.kind);

    const token5 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.if_, token5.kind);

    const token6 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.identifier, token6.kind);
}

test "JanusLexer - numbers" {
    const allocator = std.testing.allocator;
    const source = "42 3.14 0 999";

    var lexer = JanusLexer.init(allocator, source);

    const token1 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.integer_literal, token1.kind);

    const token2 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.float_literal, token2.kind);

    const token3 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.integer_literal, token3.kind);

    const token4 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.integer_literal, token4.kind);
}

test "JanusLexer - comments" {
    const allocator = std.testing.allocator;
    const source = "func // this is a comment\nmain";

    var lexer = JanusLexer.init(allocator, source);

    const token1 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.func, token1.kind);

    const token2 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.line_comment, token2.kind);

    const token3 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.newline, token3.kind);

    const token4 = try lexer.nextToken();
    try std.testing.expectEqual(astdb.Token.TokenKind.identifier, token4.kind);
}
