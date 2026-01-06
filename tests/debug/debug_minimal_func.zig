// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Tokenizer = @import("compiler/libjanus/tokenizer.zig");
const Parser = @import("compiler/libjanus/parser.zig");

test "debug minimal function" {
    const allocator = std.testing.allocator;
    const source = "func main() {}"; // Empty function body

    std.debug.print("Testing minimal function: {s}\n", .{source});

    var tokenizer = Tokenizer.Tokenizer.init(allocator, source);
    defer tokenizer.deinit();
    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    std.debug.print("Tokens:\n", .{});
    for (tokens, 0..) |token, i| {
        std.debug.print("  {}: {} '{s}'\n", .{ i, token.type, token.lexeme });
    }

    var parser = Parser.Parser.init(allocator, tokens);
    defer parser.deinit();

    const snapshot = parser.parse() catch |err| {
        std.debug.print("Parse failed with error: {}\n", .{err});
        return;
    };
    defer snapshot.deinit();

    std.debug.print("Parse successful!\n", .{});
}
