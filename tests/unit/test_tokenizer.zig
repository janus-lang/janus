// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// test_tokenizer.zig
// Quick test runner for the tokenizer

const std = @import("std");
const tokenizer = @import("compiler/libjanus/tokenizer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test basic Janus :min program
    const source =
        \\func main() do
        \\    let message = "Hello, Janus!"
        \\    let x = 42
        \\    let y = 3.14
        \\
        \\    if x > 0 do
        \\        return true
        \\    else
        \\        return false
        \\    end
        \\end
    ;


    var tok = tokenizer.Tokenizer.init(allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);


    for (tokens, 0..) |token, i| {
            i,
            @tagName(token.type),
            token.lexeme,
            token.span.start.line,
            token.span.start.column,
        });
    }

}
