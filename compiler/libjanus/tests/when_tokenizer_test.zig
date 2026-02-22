// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! When Keyword Tokenizer Tests
//!
//! Comprehensive test suite for when keyword tokenization in Janus.
//! Validates proper recognition, precedence, and edge case handling.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const tokenizer = @import("../janus_tokenizer.zig");
const TokenType = tokenizer.TokenType;
const Tokenizer = tokenizer.Tokenizer;

test "when keyword recognition" {
    const allocator = testing.allocator;

    const source = "when";
    var tok = try Tokenizer.init(allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    try testing.expect(tokens.len == 2); // when + eof
    try testing.expect(tokens[0].type == .when);
    try testing.expectEqualStrings("when", tokens[0].lexeme);
}

test "when in match guard context" {
    const allocator = testing.allocator;

    const source =
        \\match x do
        \\  n when n > 0 => "positive"
        \\end
    ;

    var tok = try Tokenizer.init(allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Find the when token
    var when_found = false;
    for (tokens) |token| {
        if (token.type == .when) {
            when_found = true;
            try testing.expectEqualStrings("when", token.lexeme);
            break;
        }
    }
    try testing.expect(when_found);
}

test "when in postfix conditional context" {
    const allocator = testing.allocator;

    const source = "return error when x == null";

    var tok = try Tokenizer.init(allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Verify token sequence: return, identifier, when, identifier, ==, null
    try testing.expect(tokens.len >= 6);

    var token_index: usize = 0;
    try testing.expect(tokens[token_index].type == .@"return");
    token_index += 1;

    try testing.expect(tokens[token_index].type == .identifier);
    try testing.expectEqualStrings("error", tokens[token_index].lexeme);
    token_index += 1;

    try testing.expect(tokens[token_index].type == .when);
    try testing.expectEqualStrings("when", tokens[token_index].lexeme);
    token_index += 1;

    try testing.expect(tokens[token_index].type == .identifier);
    try testing.expectEqualStrings("x", tokens[token_index].lexeme);
}

test "when vs identifier disambiguation" {
    const allocator = testing.allocator;

    // Test that "when" is recognized as keyword
    const when_source = "when condition";
    var when_tok = try Tokenizer.init(allocator, when_source);
    defer when_tok.deinit();

    const when_tokens = try when_tok.tokenize();
    defer allocator.free(when_tokens);

    try testing.expect(when_tokens[0].type == .when);

    // Test that "whenSomething" is recognized as identifier
    const ident_source = "whenSomething";
    var ident_tok = try Tokenizer.init(allocator, ident_source);
    defer ident_tok.deinit();

    const ident_tokens = try ident_tok.tokenize();
    defer allocator.free(ident_tokens);

    try testing.expect(ident_tokens[0].type == .identifier);
    try testing.expectEqualStrings("whenSomething", ident_tokens[0].lexeme);
}

test "when with whitespace variations" {
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{
        "when",
        " when ",
        "\\twhen\\t",
        "\\nwhen\\n",
        "when\\n",
        " when",
    };

    for (test_cases) |source| {
        var tok = try Tokenizer.init(allocator, source);
        defer tok.deinit();

        const tokens = try tok.tokenize();
        defer allocator.free(tokens);

        // Find the when token (skip whitespace tokens)
        var when_found = false;
        for (tokens) |token| {
            if (token.type == .when) {
                when_found = true;
                try testing.expectEqualStrings("when", token.lexeme);
                break;
            }
        }
        try testing.expect(when_found);
    }
}

test "when in complex expressions" {
    const allocator = testing.allocator;

    const source =
        \\match request do
        \\  GetUser(id) when id > 0 and id < 1000000 => fetch_user(id)
        \\  CreateUser(data) when data.email.contains("@") => create_user(data)
        \\  _ => reject_request("invalid")
        \\end
    ;

    var tok = try Tokenizer.init(allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Count when tokens (should be 2)
    var when_count: u32 = 0;
    for (tokens) |token| {
        if (token.type == .when) {
            when_count += 1;
            try testing.expectEqualStrings("when", token.lexeme);
        }
    }
    try testing.expect(when_count == 2);
}

test "when precedence with operators" {
    const allocator = testing.allocator;

    const source = "return value + 1 when flag and condition";

    var tok = try Tokenizer.init(allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Verify token sequence includes when in correct position
    var when_position: ?usize = null;
    for (tokens, 0..) |token, i| {
        if (token.type == .when) {
            when_position = i;
            break;
        }
    }

    try testing.expect(when_position != null);

    // Verify when comes after the expression "value + 1"
    const when_idx = when_position.?;
    try testing.expect(when_idx > 3); // return, value, +, 1, when...

    // Verify tokens before when
    try testing.expect(tokens[when_idx - 1].type == .number);
    try testing.expectEqualStrings("1", tokens[when_idx - 1].lexeme);
}

test "when with string literals" {
    const allocator = testing.allocator;

    const source = "log.info \"success\" when flag";

    var tok = try Tokenizer.init(allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Find when token and verify it's after string literal
    var string_found = false;
    var when_found = false;

    for (tokens) |token| {
        if (token.type == .string) {
            string_found = true;
            try testing.expectEqualStrings("\"success\"", token.lexeme);
        } else if (token.type == .when and string_found) {
            when_found = true;
            try testing.expectEqualStrings("when", token.lexeme);
        }
    }

    try testing.expect(string_found);
    try testing.expect(when_found);
}

test "when error cases" {
    const allocator = testing.allocator;

    // Test incomplete when (should still tokenize the when part)
    const incomplete_source = "when";
    var incomplete_tok = try Tokenizer.init(allocator, incomplete_source);
    defer incomplete_tok.deinit();

    const incomplete_tokens = try incomplete_tok.tokenize();
    defer allocator.free(incomplete_tokens);

    try testing.expect(incomplete_tokens[0].type == .when);

    // Test when followed by invalid characters (tokenizer should handle gracefully)
    const invalid_source = "when @#$";
    var invalid_tok = try Tokenizer.init(allocator, invalid_source);
    defer invalid_tok.deinit();

    const invalid_tokens = try invalid_tok.tokenize();
    defer allocator.free(invalid_tokens);

    try testing.expect(invalid_tokens[0].type == .when);
    // Subsequent tokens may be invalid, but when should be recognized
}

test "when position tracking" {
    const allocator = testing.allocator;

    const source =
        \\let x = 5
        \\return x when x > 0
    ;

    var tok = try Tokenizer.init(allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Find when token and verify position information
    for (tokens) |token| {
        if (token.type == .when) {
            try testing.expect(token.span.start.line == 2); // Second line (1-indexed)
            try testing.expect(token.span.start.column > 0); // Not at start of line
            try testing.expectEqualStrings("when", token.lexeme);
            break;
        }
    }
}

test "when performance with large input" {
    const allocator = testing.allocator;

    // Generate large source with many when keywords
    var large_source: std.ArrayList(u8) = .empty;
    defer large_source.deinit();

    try large_source.appendSlice("match value do\\n");

    for (0..1000) |i| {
        try large_source.writer().print("  {} when {} > 0 => process_{}()\\n", .{ i, i, i });
    }

    try large_source.appendSlice("  _ => default()\\nend");

    const start_time = std.time.nanoTimestamp();

    var tok = try Tokenizer.init(allocator, large_source.items);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    const end_time = std.time.nanoTimestamp();
    const tokenize_time_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Should complete tokenization in reasonable time (< 100ms for 1000 when keywords)
    try testing.expect(tokenize_time_ms < 100.0);

    // Count when tokens
    var when_count: u32 = 0;
    for (tokens) |token| {
        if (token.type == .when) {
            when_count += 1;
        }
    }

    try testing.expect(when_count == 1000);
}

test "when with UTF-8 content" {
    const allocator = testing.allocator;

    const source = "return \"ошибка\" when пользователь == null";

    var tok = try Tokenizer.init(allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Find when token in UTF-8 context
    var when_found = false;
    for (tokens) |token| {
        if (token.type == .when) {
            when_found = true;
            try testing.expectEqualStrings("when", token.lexeme);
            break;
        }
    }
    try testing.expect(when_found);
}
