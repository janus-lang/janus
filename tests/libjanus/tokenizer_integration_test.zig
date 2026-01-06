// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const tokenizer = @import("../../compiler/libjanus/tokenizer.zig");

test "tokenize hello world subset" {
    const allocator = &std.heap.page_allocator;
    const src = "func main() {\\n    print(\"Hello, Janus!\")\\n}\\n";

    const tokens = try tokenizer.tokenize(src, allocator);

    try testing.expect(tokens.len >= 11);

    // Expected sequence (kinds only)
    const expect_kinds = [_]tokenizer.TokenKind{
        .KeywordFunc, // func
        .Identifier, // main
        .LParen,
        .RParen,
        .LBrace,
        .Identifier, // print
        .LParen,
        .StringLiteral,
        .RParen,
        .RBrace,
        .EOF,
    };

    // compare head of tokens with expect_kinds
    var i: usize = 0;
    while (i < expect_kinds.len) : (i += 1) {
        try testing.expectEqual(expect_kinds[i], tokens[i].kind);
    }

    // verify identifier text for main and print
    try testing.expect(std.mem.eql(u8, tokens[1].text, "main"));
    try testing.expect(std.mem.eql(u8, tokens[5].text, "print"));
}
