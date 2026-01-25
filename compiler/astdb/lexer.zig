// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb_core = @import("astdb_core");
const ArrayList = std.array_list.Managed;

const Token = astdb_core.Token;
const TokenKind = Token.TokenKind;
const Trivia = astdb_core.Trivia;
const TriviaKind = Trivia.TriviaKind;
const SourceSpan = astdb_core.SourceSpan;
const StrId = astdb_core.StrId;
const StrInterner = astdb_core.StrInterner;

/// Region-based lexer for incremental parsing
pub const RegionLexer = struct {
    const Self = @This();

    source: []const u8,
    pos: u32,
    line: u32,
    column: u32,
    start_pos: u32, // for region lexing
    end_pos: u32, // for region lexing

    allocator: std.mem.Allocator,
    tokens: ArrayList(Token),
    trivia: ArrayList(Trivia),
    str_interner: *StrInterner,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, str_interner: *StrInterner) !Self {
        const tokens = ArrayList(Token).init(allocator);
        const trivia = ArrayList(Trivia).init(allocator);
        return Self{
            .allocator = allocator,
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .start_pos = 0,
            .end_pos = @intCast(source.len),
            .tokens = tokens,
            .trivia = trivia,
            .str_interner = str_interner,
        };
    }

    pub fn initRegion(allocator: std.mem.Allocator, source: []const u8, start: u32, end: u32, str_interner: *StrInterner) !Self {
        var lexer = try init(allocator, source, str_interner);
        lexer.start_pos = start;
        lexer.end_pos = end;
        lexer.pos = start;

        // Calculate line/column for start position
        lexer.line = 1;
        lexer.column = 1;
        for (source[0..start]) |c| {
            if (c == '\n') {
                lexer.line += 1;
                lexer.column = 1;
            } else {
                lexer.column += 1;
            }
        }

        return lexer;
    }

    pub fn deinit(self: *Self) void {
        self.trivia.deinit();
        self.tokens.deinit();
    }

    /// Tokenize the entire region
    pub fn tokenize(self: *Self) !void {
        while (self.pos < self.end_pos and self.pos < self.source.len) {
            try self.skipTrivia();

            if (self.pos >= self.end_pos or self.pos >= self.source.len) break;

            const token = try self.nextToken();
            try self.tokens.append(token);

            if (token.kind == .eof) break;
        }

        // Ensure we always end with EOF
        if (self.tokens.items.len == 0 or self.tokens.items[self.tokens.items.len - 1].kind != .eof) {
            try self.tokens.append(Token{
                .kind = .eof,
                .str = null,
                .span = self.makeSpan(self.pos, self.pos),
                .trivia_lo = @intCast(self.trivia.items.len),
                .trivia_hi = @intCast(self.trivia.items.len),
            });
        }
    }

    fn skipTrivia(self: *Self) !void {
        _ = self.trivia.items.len;

        while (self.pos < self.end_pos and self.pos < self.source.len) {
            const c = self.source[self.pos];

            switch (c) {
                ' ', '\t', '\r' => {
                    const start = self.pos;
                    while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t' or self.source[self.pos] == '\r')) {
                        self.advance();
                    }
                    try self.trivia.append(Trivia{
                        .kind = .whitespace,
                        .span = self.makeSpan(start, self.pos),
                    });
                },
                '\n' => {
                    const start = self.pos;
                    self.advance();
                    try self.trivia.append(Trivia{
                        .kind = .whitespace,
                        .span = self.makeSpan(start, self.pos),
                    });
                },
                '/' => {
                    if (self.pos + 1 < self.source.len) {
                        if (self.source[self.pos + 1] == '/') {
                            try self.skipLineComment();
                        } else if (self.source[self.pos + 1] == '*') {
                            try self.skipBlockComment();
                        } else {
                            break;
                        }
                    } else {
                        break;
                    }
                },
                else => break,
            }
        }
    }

    fn skipLineComment(self: *Self) !void {
        const start = self.pos;

        // Skip //
        self.advance();
        self.advance();

        // Check for doc comment (///)
        const is_doc = self.pos < self.source.len and self.source[self.pos] == '/';

        // Skip to end of line
        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            self.advance();
        }

        try self.trivia.append(Trivia{
            .kind = if (is_doc) .doc_comment else .line_comment,
            .span = self.makeSpan(start, self.pos),
        });
    }

    fn skipBlockComment(self: *Self) !void {
        const start = self.pos;

        // Skip /*
        self.advance();
        self.advance();

        var nesting: u32 = 1;
        while (self.pos < self.source.len and nesting > 0) {
            if (self.pos + 1 < self.source.len) {
                if (self.source[self.pos] == '/' and self.source[self.pos + 1] == '*') {
                    nesting += 1;
                    self.advance();
                    self.advance();
                    continue;
                } else if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                    nesting -= 1;
                    self.advance();
                    self.advance();
                    continue;
                }
            }
            self.advance();
        }

        try self.trivia.append(Trivia{
            .kind = .block_comment,
            .span = self.makeSpan(start, self.pos),
        });
    }

    fn nextToken(self: *Self) !Token {
        const trivia_start = @as(u32, @intCast(self.trivia.items.len));
        const start = self.pos;

        if (self.pos >= self.source.len) {
            return Token{
                .kind = .eof,
                .str = null,
                .span = self.makeSpan(start, start),
                .trivia_lo = trivia_start,
                .trivia_hi = trivia_start,
            };
        }

        const c = self.source[self.pos];

        const kind: TokenKind = switch (c) {
            'a'...'z', 'A'...'Z', '_' => return try self.readIdentifierOrKeyword(trivia_start),
            '0'...'9' => return try self.readNumber(trivia_start),
            '"' => return try self.readString(trivia_start),
            '\'' => return try self.readChar(trivia_start),

            '+' => blk: {
                self.advance();
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.advance();
                    break :blk .plus_assign;
                }
                break :blk .plus;
            },
            '-' => blk: {
                self.advance();
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.advance();
                    break :blk .minus_assign;
                }
                break :blk .minus;
            },
            '*' => blk: {
                self.advance();
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.advance();
                    break :blk .star_assign;
                }
                break :blk .star;
            },
            '/' => blk: {
                self.advance();
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.advance();
                    break :blk .slash_assign;
                }
                break :blk .slash;
            },
            '%' => blk: {
                self.advance();
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.advance();
                    break :blk .percent_assign;
                }
                break :blk .percent;
            },

            '=' => blk: {
                self.advance();
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.advance();
                    break :blk .equal;
                }
                break :blk .assign;
            },
            '!' => blk: {
                self.advance();
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.advance();
                    break :blk .not_equal;
                }
                break :blk .logical_not;
            },
            '<' => blk: {
                self.advance();
                if (self.pos < self.source.len) {
                    switch (self.source[self.pos]) {
                        '=' => {
                            self.advance();
                            break :blk .less_equal;
                        },
                        '<' => {
                            self.advance();
                            // Check for <<=
                            if (self.pos < self.source.len and self.source[self.pos] == '=') {
                                self.advance();
                                break :blk .left_shift_assign;
                            }
                            break :blk .left_shift;
                        },
                        else => {},
                    }
                }
                break :blk .less;
            },
            '>' => blk: {
                self.advance();
                if (self.pos < self.source.len) {
                    switch (self.source[self.pos]) {
                        '=' => {
                            self.advance();
                            break :blk .greater_equal;
                        },
                        '>' => {
                            self.advance();
                            // Check for >>=
                            if (self.pos < self.source.len and self.source[self.pos] == '=') {
                                self.advance();
                                break :blk .right_shift_assign;
                            }
                            break :blk .right_shift;
                        },
                        else => {},
                    }
                }
                break :blk .greater;
            },

            '&' => blk: {
                self.advance();
                if (self.pos < self.source.len) {
                    if (self.source[self.pos] == '&') {
                        self.advance();
                        break :blk .logical_and;
                    } else if (self.source[self.pos] == '=') {
                        self.advance();
                        break :blk .ampersand_assign;
                    }
                }
                break :blk .bitwise_and;
            },
            '|' => blk: {
                self.advance();
                if (self.pos < self.source.len) {
                    if (self.source[self.pos] == '|') {
                        self.advance();
                        break :blk .logical_or;
                    } else if (self.source[self.pos] == '=') {
                        self.advance();
                        break :blk .pipe_assign;
                    }
                }
                break :blk .bitwise_or;
            },
            '^' => blk: {
                self.advance();
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.advance();
                    break :blk .xor_assign;
                }
                break :blk .bitwise_xor;
            },
            '~' => blk: {
                self.advance();
                break :blk .bitwise_not;
            },

            '(' => blk: {
                self.advance();
                break :blk .left_paren;
            },
            ')' => blk: {
                self.advance();
                break :blk .right_paren;
            },
            '{' => blk: {
                self.advance();
                break :blk .left_brace;
            },
            '}' => blk: {
                self.advance();
                break :blk .right_brace;
            },
            '[' => blk: {
                self.advance();
                break :blk .left_bracket;
            },
            ']' => blk: {
                self.advance();
                break :blk .right_bracket;
            },

            ';' => blk: {
                self.advance();
                break :blk .semicolon;
            },
            ',' => blk: {
                self.advance();
                break :blk .comma;
            },
            '.' => blk: {
                self.advance();
                break :blk .dot;
            },
            ':' => blk: {
                self.advance();
                if (self.pos < self.source.len and self.source[self.pos] == ':') {
                    self.advance();
                    break :blk .double_colon;
                }
                break :blk .colon;
            },
            '?' => blk: {
                self.advance();
                break :blk .question;
            },

            else => blk: {
                std.debug.print("Lexer invalid char: '{c}' ({d})\n", .{ self.source[self.pos], self.source[self.pos] });
                self.advance();
                break :blk .invalid;
            },
        };

        return Token{
            .kind = kind,
            .str = null,
            .span = self.makeSpan(start, self.pos),
            .trivia_lo = trivia_start,
            .trivia_hi = @intCast(self.trivia.items.len),
        };
    }

    fn readIdentifierOrKeyword(self: *Self, trivia_start: u32) !Token {
        const start = self.pos;

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (!std.ascii.isAlphanumeric(c) and c != '_') break;
            self.advance();
        }

        const text = self.source[start..self.pos];
        const str_id = try self.str_interner.intern(text);

        // Check for keywords using direct string comparison (Syntactic Honesty!)
        // Allocator Contexts/Regions/Using Keywords Added
        const kind: TokenKind =
            if (std.mem.eql(u8, text, "func")) .func else if (std.mem.eql(u8, text, "let")) .let else if (std.mem.eql(u8, text, "var")) .var_ else if (std.mem.eql(u8, text, "const")) .const_ else if (std.mem.eql(u8, text, "if")) .if_ else if (std.mem.eql(u8, text, "else")) .else_ else if (std.mem.eql(u8, text, "while")) .while_ else if (std.mem.eql(u8, text, "defer")) .defer_ else if (std.mem.eql(u8, text, "for")) .for_ else if (std.mem.eql(u8, text, "return")) .return_ else if (std.mem.eql(u8, text, "break")) .break_ else if (std.mem.eql(u8, text, "continue")) .continue_ else if (std.mem.eql(u8, text, "struct")) .struct_ else if (std.mem.eql(u8, text, "union")) .union_ else if (std.mem.eql(u8, text, "enum")) .enum_ else if (std.mem.eql(u8, text, "impl")) .impl else if (std.mem.eql(u8, text, "trait")) .trait else if (std.mem.eql(u8, text, "using")) .using else if (std.mem.eql(u8, text, "region")) .region else if (std.mem.eql(u8, text, "Allocator")) .allocator else if (std.mem.eql(u8, text, "test")) .test_ else if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) .bool_literal else .identifier;

        std.debug.print("Lexer ident: '{s}' -> {s}\n", .{ text, @tagName(kind) });

        return Token{
            .kind = kind,
            .str = str_id,
            .span = self.makeSpan(start, self.pos),
            .trivia_lo = trivia_start,
            .trivia_hi = @intCast(self.trivia.items.len),
        };
    }

    fn readNumber(self: *Self, trivia_start: u32) !Token {
        const start = self.pos;
        var is_float = false;

        // Check for hex (0x), binary (0b), or octal (0o) prefix
        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len) {
            const next = self.source[self.pos + 1];
            if (next == 'x' or next == 'X') {
                // Hexadecimal literal with optional underscores
                self.advance(); // skip '0'
                self.advance(); // skip 'x'
                while (self.pos < self.source.len and (std.ascii.isHex(self.source[self.pos]) or self.source[self.pos] == '_')) {
                    self.advance();
                }
                const text = self.source[start..self.pos];
                const str_id = try self.str_interner.intern(text);
                return Token{
                    .kind = .integer_literal,
                    .str = str_id,
                    .span = self.makeSpan(start, self.pos),
                    .trivia_lo = trivia_start,
                    .trivia_hi = @intCast(self.trivia.items.len),
                };
            } else if (next == 'b' or next == 'B') {
                // Binary literal with optional underscores
                self.advance(); // skip '0'
                self.advance(); // skip 'b'
                while (self.pos < self.source.len and (self.source[self.pos] == '0' or self.source[self.pos] == '1' or self.source[self.pos] == '_')) {
                    self.advance();
                }
                const text = self.source[start..self.pos];
                const str_id = try self.str_interner.intern(text);
                return Token{
                    .kind = .integer_literal,
                    .str = str_id,
                    .span = self.makeSpan(start, self.pos),
                    .trivia_lo = trivia_start,
                    .trivia_hi = @intCast(self.trivia.items.len),
                };
            } else if (next == 'o' or next == 'O') {
                // Octal literal with optional underscores
                self.advance(); // skip '0'
                self.advance(); // skip 'o'
                while (self.pos < self.source.len and ((self.source[self.pos] >= '0' and self.source[self.pos] <= '7') or self.source[self.pos] == '_')) {
                    self.advance();
                }
                const text = self.source[start..self.pos];
                const str_id = try self.str_interner.intern(text);
                return Token{
                    .kind = .integer_literal,
                    .str = str_id,
                    .span = self.makeSpan(start, self.pos),
                    .trivia_lo = trivia_start,
                    .trivia_hi = @intCast(self.trivia.items.len),
                };
            }
        }

        // Read decimal integer part with optional underscores
        while (self.pos < self.source.len and (std.ascii.isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.advance();
        }

        // Check for decimal point
        if (self.pos < self.source.len and self.source[self.pos] == '.') {
            // Look ahead to make sure it's not a method call
            if (self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])) {
                is_float = true;
                self.advance(); // skip '.'

                // Read fractional part with optional underscores
                while (self.pos < self.source.len and (std.ascii.isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
                    self.advance();
                }
            }
        }

        // Check for exponent
        if (self.pos < self.source.len and (self.source[self.pos] == 'e' or self.source[self.pos] == 'E')) {
            is_float = true;
            self.advance();

            if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                self.advance();
            }

            while (self.pos < self.source.len and (std.ascii.isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
                self.advance();
            }
        }

        const text = self.source[start..self.pos];
        const str_id = try self.str_interner.intern(text);

        return Token{
            .kind = if (is_float) .float_literal else .integer_literal,
            .str = str_id,
            .span = self.makeSpan(start, self.pos),
            .trivia_lo = trivia_start,
            .trivia_hi = @intCast(self.trivia.items.len),
        };
    }

    fn readString(self: *Self, trivia_start: u32) !Token {
        const start = self.pos;
        self.advance(); // skip opening quote

        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\' and self.pos + 1 < self.source.len) {
                self.advance(); // skip backslash
                self.advance(); // skip escaped character
            } else {
                self.advance();
            }
        }

        if (self.pos < self.source.len) {
            self.advance(); // skip closing quote
        }

        const text = self.source[start..self.pos];
        const str_id = try self.str_interner.intern(text);

        return Token{
            .kind = .string_literal,
            .str = str_id,
            .span = self.makeSpan(start, self.pos),
            .trivia_lo = trivia_start,
            .trivia_hi = @intCast(self.trivia.items.len),
        };
    }

    fn readChar(self: *Self, trivia_start: u32) !Token {
        const start = self.pos;
        self.advance(); // skip opening quote

        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\\' and self.pos + 1 < self.source.len) {
                self.advance(); // skip backslash
                self.advance(); // skip escaped character
            } else {
                self.advance();
            }
        }

        if (self.pos < self.source.len and self.source[self.pos] == '\'') {
            self.advance(); // skip closing quote
        }

        const text = self.source[start..self.pos];
        const str_id = try self.str_interner.intern(text);

        return Token{
            .kind = .char_literal,
            .str = str_id,
            .span = self.makeSpan(start, self.pos),
            .trivia_lo = trivia_start,
            .trivia_hi = @intCast(self.trivia.items.len),
        };
    }

    fn advance(self: *Self) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }

    fn makeSpan(self: *Self, start: u32, end: u32) SourceSpan {
        // Calculate line/column for start position
        var line: u32 = 1;
        var column: u32 = 1;

        for (self.source[0..start]) |c| {
            if (c == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }

        return SourceSpan{
            .start = start,
            .end = end,
            .line = line,
            .column = column,
        };
    }

    pub fn getTokens(self: *const Self) []const Token {
        return self.tokens.items;
    }

    pub fn getTrivia(self: *const Self) []const Trivia {
        return self.trivia.items;
    }
};

// Tests
test "RegionLexer basic tokenization" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    var lexer = RegionLexer.init(std.testing.allocator, "func main() {}", &str_interner);
    defer lexer.deinit();

    try lexer.tokenize();

    const tokens = lexer.getTokens();
    try std.testing.expectEqual(@as(usize, 6), tokens.len);

    try std.testing.expectEqual(TokenKind.func, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.left_paren, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.right_paren, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.left_brace, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.right_brace, tokens[5].kind);
}

test "RegionLexer keyword recognition" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    var lexer = RegionLexer.init(std.testing.allocator, "let var const if else", &str_interner);
    defer lexer.deinit();

    try lexer.tokenize();

    const tokens = lexer.getTokens();
    try std.testing.expectEqual(@as(usize, 5), tokens.len);

    try std.testing.expectEqual(TokenKind.let, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.var_, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.const_, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.if_, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.else_, tokens[4].kind);
}

test "RegionLexer number literals" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    var lexer = RegionLexer.init(std.testing.allocator, "42 3.14 1e10", &str_interner);
    defer lexer.deinit();

    try lexer.tokenize();

    const tokens = lexer.getTokens();
    try std.testing.expectEqual(@as(usize, 3), tokens.len);

    try std.testing.expectEqual(TokenKind.integer_literal, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.float_literal, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.float_literal, tokens[2].kind);
}

test "RegionLexer string literals" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    var lexer = RegionLexer.init(std.testing.allocator, "\"hello\" 'c'", &str_interner);
    defer lexer.deinit();

    try lexer.tokenize();

    const tokens = lexer.getTokens();
    try std.testing.expectEqual(@as(usize, 2), tokens.len);

    try std.testing.expectEqual(TokenKind.string_literal, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.char_literal, tokens[1].kind);
}

test "RegionLexer trivia handling" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    var lexer = RegionLexer.init(std.testing.allocator, "func // comment\n  main", &str_interner);
    defer lexer.deinit();

    try lexer.tokenize();

    const tokens = lexer.getTokens();
    const trivia = lexer.getTrivia();

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expect(trivia.len > 0);

    try std.testing.expectEqual(TokenKind.func, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[1].kind);
}

test "RegionLexer region parsing" {
    var str_interner = StrInterner.init(std.testing.allocator);
    defer str_interner.deinit();

    const source = "func main() { let x = 42; }";

    // Parse only the function body
    var lexer = RegionLexer.initRegion(std.testing.allocator, source, 14, 25, &str_interner);
    defer lexer.deinit();

    try lexer.tokenize();

    const tokens = lexer.getTokens();
    try std.testing.expect(tokens.len >= 4); // let, x, =, 42

    try std.testing.expectEqual(TokenKind.let, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.assign, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.integer_literal, tokens[3].kind);
}
