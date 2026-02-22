// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Tokenizer - Task 1.1
//!
//! UTF-8 aware tokenizer for Janus :min profile
//! Implements the foundation for all language processing and ASTDB integration
//! Requirements: E-1, E-4, Lexical Analysis
//!
//! GRANITE-SOLID TOKENIZATION - ZERO-COPY STRING PROCESSING

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Token types for Janus :min profile
pub const TokenType = enum {
    // Literals
    number,
    string,
    identifier,

    // Keywords (:min profile only)
    let,
    @"var",
    func,
    @"if",
    @"else",
    @"for",
    kw_in,
    @"while",
    match,
    @"break",
    @"continue",
    do,
    end,
    @"return",
    use,
    true,
    false,
    null,
    @"and",
    @"or",
    not,
    exclaim,
    when,

    // :go profile keywords
    package,
    @"const",
    kw_nil,
    @"switch",
    kw_case,
    kw_default,
    @"defer",
    go,
    kw_where,

    // Operators
    plus, // +
    minus, // -
    star, // *
    slash, // /
    percent, // %
    equal_equal, // ==
    bang_equal, // !=
    less, // <
    greater, // >
    less_equal, // <=
    greater_equal, // >=
    equal, // =
    match_arrow, // =>
    pipe, // |
    dot_dot, // ..
    ampersand, // &
    // Optional chaining and null coalesce operators
    optional_chain, // ?.
    null_coalesce, // ??
    question, // ?
    underscore, // _

    // Delimiters
    left_paren, // (
    right_paren, // )
    left_brace, // {
    right_brace, // }
    left_bracket, // [
    right_bracket, // ]
    comma, // ,
    dot, // .
    semicolon, // ;
    colon, // :
    colon_equal, // :=
    arrow, // ->
    // Types/Structs (extended)
    struct_kw,
    type_kw,

    // Special
    newline,
    eof,
    invalid,
};

/// Source position for error reporting and IDE features
pub const SourcePos = struct {
    line: u32,
    column: u32,
    byte_offset: u32,

    pub fn init(line: u32, column: u32, byte_offset: u32) SourcePos {
        return SourcePos{
            .line = line,
            .column = column,
            .byte_offset = byte_offset,
        };
    }
};

/// Source span for tokens
pub const SourceSpan = struct {
    start: SourcePos,
    end: SourcePos,

    pub fn init(start: SourcePos, end: SourcePos) SourceSpan {
        return SourceSpan{
            .start = start,
            .end = end,
        };
    }

    pub fn single(pos: SourcePos) SourceSpan {
        return SourceSpan{
            .start = pos,
            .end = pos,
        };
    }
};

/// A token with type, lexeme, and source location
pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    span: SourceSpan,

    pub fn init(token_type: TokenType, lexeme: []const u8, span: SourceSpan) Token {
        return Token{
            .type = token_type,
            .lexeme = lexeme,
            .span = span,
        };
    }
};

/// Tokenizer state and methods
pub const Tokenizer = struct {
    source: []const u8,
    current: u32,
    line: u32,
    column: u32,
    tokens: std.ArrayList(Token),
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, source: []const u8) Self {
        return Self{
            .source = source,
            .current = 0,
            .line = 1,
            .column = 1,
            .tokens = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    /// Tokenize the entire source and return tokens
    pub fn tokenize(self: *Self) ![]Token {
        while (!self.isAtEnd()) {
            self.scanToken() catch |err| {
                // Add error recovery here if needed
                return err;
            };
        }

        // Add EOF token
        const eof_pos = self.currentPos();
        try self.addToken(.eof, "", SourceSpan.single(eof_pos));

        return self.tokens.toOwnedSlice();
    }

    fn scanToken(self: *Self) !void {
        const start_pos = self.currentPos();
        const c = self.advance();

        switch (c) {
            // Whitespace (skip, but track position)
            ' ', '\r', '\t' => {},

            // Newlines (significant in some contexts)
            '\n' => {
                const end_pos = self.currentPos();
                try self.addToken(.newline, "\n", SourceSpan.init(start_pos, end_pos));
                self.line += 1;
                self.column = 1;
            },

            // Single-character tokens
            '(' => try self.addToken(.left_paren, "(", SourceSpan.single(start_pos)),
            ')' => try self.addToken(.right_paren, ")", SourceSpan.single(start_pos)),
            '{' => try self.addToken(.left_brace, "{", SourceSpan.single(start_pos)),
            '}' => try self.addToken(.right_brace, "}", SourceSpan.single(start_pos)),
            '[' => try self.addToken(.left_bracket, "[", SourceSpan.single(start_pos)),
            ']' => try self.addToken(.right_bracket, "]", SourceSpan.single(start_pos)),
            ',' => try self.addToken(.comma, ",", SourceSpan.single(start_pos)),
            '.' => {
                if (self.match('.')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.dot_dot, "..", SourceSpan.init(start_pos, end_pos));
                } else {
                    try self.addToken(.dot, ".", SourceSpan.single(start_pos));
                }
            },
            '?' => {
                if (self.match('?')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.null_coalesce, "??", SourceSpan.init(start_pos, end_pos));
                } else if (self.match('.')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.optional_chain, "?.", SourceSpan.init(start_pos, end_pos));
                } else {
                    // Lone '?' - use question token for optional types like i32?
                    try self.addToken(.question, "?", SourceSpan.single(start_pos));
                }
            },
            ';' => try self.addToken(.semicolon, ";", SourceSpan.single(start_pos)),
            ':' => {
                if (self.match('=')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.colon_equal, ":=", SourceSpan.init(start_pos, end_pos));
                } else {
                    try self.addToken(.colon, ":", SourceSpan.single(start_pos));
                }
            },
            '+' => try self.addToken(.plus, "+", SourceSpan.single(start_pos)),
            '*' => try self.addToken(.star, "*", SourceSpan.single(start_pos)),
            '/' => {
                if (self.match('/')) {
                    // Line comment: // ... to end of line (do not emit tokens)
                    while (self.peek() != '\n' and !self.isAtEnd()) {
                        _ = self.advance();
                    }
                } else if (self.match('*')) {
                    // Block comment: /* ... */ possibly multi-line
                    while (!self.isAtEnd()) {
                        if (self.peek() == '\n') {
                            self.line += 1;
                            self.column = 1;
                            _ = self.advance();
                            continue;
                        }
                        if (self.peek() == '*' and self.peekNext() == '/') {
                            _ = self.advance(); // '*'
                            _ = self.advance(); // '/'
                            break;
                        }
                        _ = self.advance();
                    }
                } else {
                    try self.addToken(.slash, "/", SourceSpan.single(start_pos));
                }
            },
            '%' => try self.addToken(.percent, "%", SourceSpan.single(start_pos)),

            // Two-character tokens
            '=' => {
                if (self.match('=')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.equal_equal, "==", SourceSpan.init(start_pos, end_pos));
                } else if (self.match('>')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.match_arrow, "=>", SourceSpan.init(start_pos, end_pos));
                } else {
                    try self.addToken(.equal, "=", SourceSpan.single(start_pos));
                }
            },
            '!' => {
                if (self.match('=')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.bang_equal, "!=", SourceSpan.init(start_pos, end_pos));
                } else {
                    try self.addToken(.exclaim, "!", SourceSpan.single(start_pos));
                }
            },
            '<' => {
                if (self.match('=')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.less_equal, "<=", SourceSpan.init(start_pos, end_pos));
                } else {
                    try self.addToken(.less, "<", SourceSpan.single(start_pos));
                }
            },
            '>' => {
                if (self.match('=')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.greater_equal, ">=", SourceSpan.init(start_pos, end_pos));
                } else {
                    try self.addToken(.greater, ">", SourceSpan.single(start_pos));
                }
            },
            '-' => {
                if (self.match('>')) {
                    const end_pos = self.currentPos();
                    try self.addToken(.arrow, "->", SourceSpan.init(start_pos, end_pos));
                } else {
                    try self.addToken(.minus, "-", SourceSpan.single(start_pos));
                }
            },

            // String literals
            '"' => try self.string(start_pos),

            // Numbers
            '0'...'9' => try self.number(start_pos),

            // Pipe operator
            '|' => try self.addToken(.pipe, "|", SourceSpan.single(start_pos)),

            // Underscore (can be standalone wildcard or start of identifier)
            '_' => {
                // Check if it's followed by alphanumeric (identifier) or standalone (wildcard)
                if (self.isAlphaNumeric(self.peek())) {
                    try self.identifier(start_pos);
                } else {
                    try self.addToken(.underscore, "_", SourceSpan.single(start_pos));
                }
            },

            // Identifiers and keywords
            'a'...'z', 'A'...'Z' => try self.identifier(start_pos),

            // Address-of operator
            '&' => try self.addToken(.ampersand, "&", SourceSpan.single(start_pos)),

            else => {
                // Handle UTF-8 characters or invalid characters
                if (self.isAlphaUTF8(c)) {
                    try self.identifier(start_pos);
                } else {
                    const lexeme = self.source[start_pos.byte_offset..self.current];
                    try self.addToken(.invalid, lexeme, SourceSpan.init(start_pos, self.currentPos()));
                }
            },
        }
    }

    fn string(self: *Self, start_pos: SourcePos) !void {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            _ = self.advance();
        }

        if (self.isAtEnd()) {
            // Unterminated string - add as invalid token
            const lexeme = self.source[start_pos.byte_offset..self.current];
            try self.addToken(.invalid, lexeme, SourceSpan.init(start_pos, self.currentPos()));
            return;
        }

        // Consume closing "
        _ = self.advance();

        const end_pos = self.currentPos();
        const lexeme = self.source[start_pos.byte_offset..self.current];
        try self.addToken(.string, lexeme, SourceSpan.init(start_pos, end_pos));
    }

    fn number(self: *Self, start_pos: SourcePos) !void {
        while (self.isDigit(self.peek())) {
            _ = self.advance();
        }

        // Look for decimal part
        if (self.peek() == '.' and self.isDigit(self.peekNext())) {
            // Consume the '.'
            _ = self.advance();

            while (self.isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        const end_pos = self.currentPos();
        const lexeme = self.source[start_pos.byte_offset..self.current];
        try self.addToken(.number, lexeme, SourceSpan.init(start_pos, end_pos));
    }

    fn identifier(self: *Self, start_pos: SourcePos) !void {
        while (self.isAlphaNumeric(self.peek()) or self.isAlphaNumericUTF8(self.peek())) {
            _ = self.advance();
        }

        const end_pos = self.currentPos();
        const lexeme = self.source[start_pos.byte_offset..self.current];
        const token_type = self.getKeywordType(lexeme);
        try self.addToken(token_type, lexeme, SourceSpan.init(start_pos, end_pos));
    }

    fn getKeywordType(self: *Self, text: []const u8) TokenType {
        _ = self; // unused

        // Keywords for :min profile
        const keywords = std.StaticStringMap(TokenType).initComptime(.{
            .{ "let", .let },
            .{ "var", .@"var" },
            .{ "func", .func },
            .{ "if", .@"if" },
            .{ "else", .@"else" },
            .{ "for", .@"for" },
            .{ "in", .kw_in },
            .{ "while", .@"while" },
            .{ "match", .match },
            .{ "break", .@"break" },
            .{ "continue", .@"continue" },
            .{ "do", .do },
            .{ "end", .end },
            .{ "return", .@"return" },
            .{ "use", .use },
            .{ "true", .true },
            .{ "false", .false },
            .{ "null", .null },
            .{ "and", .@"and" },
            .{ "or", .@"or" },
            .{ "not", .not },
            .{ "when", .when },
            .{ "struct", .struct_kw },
            .{ "type", .type_kw },
            .{ "package", .package },
            .{ "const", .@"const" },
            .{ "nil", .kw_nil },
            .{ "switch", .@"switch" },
            .{ "case", .kw_case },
            .{ "default", .kw_default },
            .{ "defer", .@"defer" },
            .{ "go", .go },
            .{ "where", .kw_where },
        });

        return keywords.get(text) orelse .identifier;
    }

    // Helper methods
    fn isAtEnd(self: *Self) bool {
        return self.current >= self.source.len;
    }

    fn advance(self: *Self) u8 {
        if (self.isAtEnd()) return 0;

        const c = self.source[self.current];
        self.current += 1;
        self.column += 1;
        return c;
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;

        self.current += 1;
        self.column += 1;
        return true;
    }

    fn peek(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *Self) u8 {
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }

    fn isDigit(self: *Self, c: u8) bool {
        _ = self; // unused
        return c >= '0' and c <= '9';
    }

    fn isAlpha(self: *Self, c: u8) bool {
        _ = self; // unused
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            c == '_';
    }

    fn isAlphaNumeric(self: *Self, c: u8) bool {
        return self.isAlpha(c) or self.isDigit(c);
    }

    // UTF-8 support (basic implementation)
    fn isAlphaUTF8(self: *Self, c: u8) bool {
        _ = self; // unused
        // For now, just handle ASCII
        // TODO: Add proper UTF-8 identifier support
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            c == '_';
    }

    fn isAlphaNumericUTF8(self: *Self, c: u8) bool {
        return self.isAlphaUTF8(c) or self.isDigit(c);
    }

    fn currentPos(self: *Self) SourcePos {
        return SourcePos.init(self.line, self.column, self.current);
    }

    fn addToken(self: *Self, token_type: TokenType, lexeme: []const u8, span: SourceSpan) !void {
        const token = Token.init(token_type, lexeme, span);
        try self.tokens.append(token);
    }
};

// Tests
test "tokenizer basic functionality" {
    const allocator = std.testing.allocator;

    const source = "let x = 42";
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len == 5); // let, x, =, 42, eof
    try std.testing.expect(tokens[0].type == .let);
    try std.testing.expect(tokens[1].type == .identifier);
    try std.testing.expect(tokens[2].type == .equal);
    try std.testing.expect(tokens[3].type == .number);
    try std.testing.expect(tokens[4].type == .eof);
}

test "tokenizer string literals" {
    const allocator = std.testing.allocator;

    const source = "\"Hello, Janus!\"";
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len == 2); // string, eof
    try std.testing.expect(tokens[0].type == .string);
    try std.testing.expectEqualStrings(tokens[0].lexeme, "\"Hello, Janus!\"");
}

test "tokenizer keywords" {
    const allocator = std.testing.allocator;

    const source = "func main() do return end";
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expect(tokens[0].type == .func);
    try std.testing.expect(tokens[1].type == .identifier); // main
    try std.testing.expect(tokens[2].type == .left_paren);
    try std.testing.expect(tokens[3].type == .right_paren);
    try std.testing.expect(tokens[4].type == .do);
    try std.testing.expect(tokens[5].type == .@"return");
    try std.testing.expect(tokens[6].type == .end);
}

test "tokenizer new keywords" {
    const allocator = std.testing.allocator;

    const source = "match while break continue";
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expect(tokens[0].type == .match);
    try std.testing.expect(tokens[1].type == .@"while");
    try std.testing.expect(tokens[2].type == .@"break");
    try std.testing.expect(tokens[3].type == .@"continue");
    try std.testing.expect(tokens[4].type == .eof);
}

test "tokenizer match arrow and range" {
    const allocator = std.testing.allocator;

    const source = "x => y .. z";
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expect(tokens[0].type == .identifier); // x
    try std.testing.expect(tokens[1].type == .match_arrow); // =>
    try std.testing.expect(tokens[2].type == .identifier); // y
    try std.testing.expect(tokens[3].type == .dot_dot); // ..
    try std.testing.expect(tokens[4].type == .identifier); // z
    try std.testing.expect(tokens[5].type == .eof);
}

test "tokenizer underscore wildcard vs identifier" {
    const allocator = std.testing.allocator;

    const source = "_ _var";
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expect(tokens[0].type == .underscore); // standalone _
    try std.testing.expect(tokens[1].type == .identifier); // _var
    try std.testing.expect(tokens[2].type == .eof);
}

test "tokenizer operators" {
    const allocator = std.testing.allocator;

    const source = "== != <= >= -> + - * / % => | .. _";
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    const expected = [_]TokenType{ .equal_equal, .bang_equal, .less_equal, .greater_equal, .arrow, .plus, .minus, .star, .slash, .percent, .match_arrow, .pipe, .dot_dot, .underscore, .eof };

    for (expected, 0..) |expected_type, i| {
        try std.testing.expect(tokens[i].type == expected_type);
    }
}

test "tokenizer source positions" {
    const allocator = std.testing.allocator;

    const source = "let\nx = 42";
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    // Check that line numbers are tracked correctly
    try std.testing.expect(tokens[0].span.start.line == 1); // let
    try std.testing.expect(tokens[1].span.start.line == 1); // newline
    try std.testing.expect(tokens[2].span.start.line == 2); // x
    try std.testing.expect(tokens[3].span.start.line == 2); // =
    try std.testing.expect(tokens[4].span.start.line == 2); // 42
}

test "when keyword recognition" {
    const allocator = std.testing.allocator;

    const source = "when";
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len == 2); // when + eof
    try std.testing.expect(tokens[0].type == .when);
    try std.testing.expectEqualStrings("when", tokens[0].lexeme);
}

test "when in match guard context" {
    const allocator = std.testing.allocator;

    const source =
        \\match x do
        \\  n when n > 0 => "positive"
        \\end
    ;

    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    // Find the when token
    var when_found = false;
    for (tokens) |token| {
        if (token.type == .when) {
            when_found = true;
            try std.testing.expectEqualStrings("when", token.lexeme);
            break;
        }
    }
    try std.testing.expect(when_found);
}

test "when in postfix conditional context" {
    const allocator = std.testing.allocator;

    const source = "return error when x == null";

    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    // Verify token sequence includes when
    var when_found = false;
    var return_found = false;

    for (tokens) |token| {
        if (token.type == .@"return") {
            return_found = true;
        } else if (token.type == .when) {
            when_found = true;
            try std.testing.expectEqualStrings("when", token.lexeme);
        }
    }

    try std.testing.expect(return_found);
    try std.testing.expect(when_found);
}

test "when vs identifier disambiguation" {
    const allocator = std.testing.allocator;

    // Test that "when" is recognized as keyword
    const when_source = "when condition";
    var when_tokenizer = Tokenizer.init(allocator, when_source);
    defer when_tokenizer.deinit();

    const when_tokens = try when_tokenizer.tokenize();
    defer allocator.free(when_tokens);

    try std.testing.expect(when_tokens[0].type == .when);

    // Test that "whenSomething" is recognized as identifier
    const ident_source = "whenSomething";
    var ident_tokenizer = Tokenizer.init(allocator, ident_source);
    defer ident_tokenizer.deinit();

    const ident_tokens = try ident_tokenizer.tokenize();
    defer allocator.free(ident_tokens);

    try std.testing.expect(ident_tokens[0].type == .identifier);
    try std.testing.expectEqualStrings("whenSomething", ident_tokens[0].lexeme);
}
