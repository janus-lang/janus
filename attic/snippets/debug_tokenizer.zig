// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("compiler/libjanus/api.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\func main() {
        \\    let x := 42
        \\    print(x)
        \\}
    ;

    std.debug.print("Source code:\n{s}\n\n", .{source});

    // Tokenize
    var tokenizer = janus.tokenizer.Tokenizer.init(allocator, source);
    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    std.debug.print("Tokens:\n");
    for (tokens, 0..) |token, i| {
        std.debug.print("{d}: {s} '{s}' at {}:{}\n", .{ i, @tagName(token.type), token.lexeme, token.span.start.line, token.span.start.column });
    }
}
