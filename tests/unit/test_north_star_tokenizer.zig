// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Tokenizer = @import("compiler/tokenizer.zig").Tokenizer;
const TokenType = @import("compiler/tokenizer.zig").TokenType;

// Test tokenizer with actual North Star program
test "North Star Program Tokenization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read the actual demo.jan file
    const source = @embedFile("demo.jan");


    var tokenizer = Tokenizer.init(allocator, source);
    var token_count: u32 = 0;

    // Tokenize the entire program
    while (true) {
        const token = tokenizer.nextToken() catch |err| {
            return err;
        };

        token_count += 1;

        // Print first 20 tokens for verification
        if (token_count <= 20) {
                token_count,
                @tagName(token.type),
                token.value,
                token.location.line,
                token.location.column,
            });
        }

        if (token.type == .eof) {
            break;
        }
    }


    // Verify we got a reasonable number of tokens
    try testing.expect(token_count > 50); // Should have many tokens for the full program
}
