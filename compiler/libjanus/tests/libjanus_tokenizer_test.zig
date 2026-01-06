// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const tokenizer = @import("../tokenizer.zig");
const TokenType = tokenizer.TokenType;
const Token = tokenizer.Token;
const SourceSpan = tokenizer.SourceSpan;

test "tokenize 'func main() {}'" {
    const source = "func main() {}";
    var tokens = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const expected_tokens = [_]Token{
        Token{ .token_type = TokenType.Func, .span = SourceSpan{ .start_byte = 0, .end_byte = 4, .line = 1, .col = 1 }, .literal = "func" },
        Token{ .token_type = TokenType.Identifier, .span = SourceSpan{ .start_byte = 5, .end_byte = 9, .line = 1, .col = 6 }, .literal = "main" },
        Token{ .token_type = TokenType.LeftParen, .span = SourceSpan{ .start_byte = 9, .end_byte = 10, .line = 1, .col = 10 }, .literal = "(" },
        Token{ .token_type = TokenType.RightParen, .span = SourceSpan{ .start_byte = 10, .end_byte = 11, .line = 1, .col = 11 }, .literal = ")" },
        Token{ .token_type = TokenType.LeftBrace, .span = SourceSpan{ .start_byte = 12, .end_byte = 13, .line = 1, .col = 13 }, .literal = "{" },
        Token{ .token_type = TokenType.RightBrace, .span = SourceSpan{ .start_byte = 13, .end_byte = 14, .line = 1, .col = 14 }, .literal = "}" },
        Token{ .token_type = TokenType.Eof, .span = SourceSpan{ .start_byte = 14, .end_byte = 14, .line = 1, .col = 15 }, .literal = "" },
    };

    try std.testing.expectEqual(tokens.len, expected_tokens.len);
    for (tokens, 0..) |t, i| {
        try std.testing.expectEqual(t.token_type, expected_tokens[i].token_type);
        try std.testing.expectEqual(t.span.start_byte, expected_tokens[i].span.start_byte);
        try std.testing.expectEqual(t.span.end_byte, expected_tokens[i].span.end_byte);
        try std.testing.expectEqual(t.span.line, expected_tokens[i].span.line);
        try std.testing.expectEqual(t.span.col, expected_tokens[i].span.col);
        try std.testing.expectEqualStrings(t.literal, expected_tokens[i].literal);
    }
}
