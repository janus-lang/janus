// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Inline minimal tokenizer to test the logic
const TokenType = enum { Identifier, Eof, Illegal };

const Token = struct {
    token_type: TokenType,
    literal: []const u8,
};

const SimpleTokenizer = struct {
    source: []const u8,
    current_pos: u32,

    fn init(source: []const u8) SimpleTokenizer {
        return SimpleTokenizer{
            .source = source,
            .current_pos = 0,
        };
    }

    fn isAtEnd(self: *SimpleTokenizer) bool {
        return self.current_pos >= self.source.len;
    }

    fn advance(self: *SimpleTokenizer) u8 {
        const char = self.source[self.current_pos];
        self.current_pos += 1;
        return char;
    }

    fn peek(self: *SimpleTokenizer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current_pos];
    }

    fn nextToken(self: *SimpleTokenizer) Token {
        if (self.isAtEnd()) {
            return Token{
                .token_type = TokenType.Eof,
                .literal = "",
            };
        }

        const start_pos = self.current_pos;
        const c = self.advance();

        if (std.ascii.isAlphabetic(c)) {
            // This is the suspected problematic loop
            var count: u32 = 0;
            while (!self.isAtEnd() and std.ascii.isAlphanumeric(self.peek()) and count < 100) {
                _ = self.advance();
                count += 1;
            }

            if (count >= 100) {
                std.debug.print("ERROR: Loop exceeded safety limit!\n", .{});
                return Token{ .token_type = TokenType.Illegal, .literal = "LOOP_ERROR" };
            }

            return Token{
                .token_type = TokenType.Identifier,
                .literal = self.source[start_pos..self.current_pos],
            };
        }

        return Token{
            .token_type = TokenType.Illegal,
            .literal = self.source[start_pos..self.current_pos],
        };
    }
};

pub fn main() !void {
    const test_input = "hello";

    std.debug.print("Testing with: '{s}'\n", .{test_input});

    var tokenizer = SimpleTokenizer.init(test_input);

    var count: u32 = 0;
    while (count < 10) {
        const token = tokenizer.nextToken();
        std.debug.print("Token {}: {} = '{s}'\n", .{ count, token.token_type, token.literal });

        if (token.token_type == TokenType.Eof) {
            break;
        }
        count += 1;
    }

    std.debug.print("Test completed successfully!\n", .{});
}
