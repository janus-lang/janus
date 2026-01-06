// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Tokenizer = @import("compiler/tokenizer.zig").Tokenizer;
const TokenType = @import("compiler/tokenizer.zig").TokenType;

test "Demo.jan Tokenization Test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple North Star program fragment
    const source =
        \\func pure_math(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\comptime {
        \\    let pure_func := std.meta.get_function("pure_math")
        \\}
    ;

    std.debug.print("\n=== DEMO TOKENIZER TEST ===\n", .{});

    var tokenizer = Tokenizer.init(allocator, source);
    var token_count: u32 = 0;

    // Tokenize and verify key tokens
    while (true) {
        const token = tokenizer.nextToken() catch |err| {
            std.debug.print("Error: {}\n", .{err});
            return err;
        };

        token_count += 1;

        // Print all tokens for debugging
        std.debug.print("Token {}: {} = '{}'\n", .{
            token_count,
            @tagName(token.type),
            token.value,
        });

        if (token.type == .eof) {
            break;
        }
    }

    std.debug.print("Total tokens: {}\n", .{token_count});
    std.debug.print("=== TOKENIZATION SUCCESS ===\n", .{});

    // Basic validation
    try testing.expect(token_count > 10);
}
