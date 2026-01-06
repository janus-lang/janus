// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("compiler/libjanus/api.zig");

test "debug tokens" {
    const allocator = std.testing.allocator;
    const source = "func main() { print(\"Hello, Janus!\") }";

    std.debug.print("Source: {s}\n", .{source});

    // Test just the tokenizer step
    const tokens = janus.tokenize(source, allocator) catch |err| {
        std.debug.print("Tokenize failed: {}\n", .{err});
        return;
    };
    defer allocator.free(tokens);

    std.debug.print("Got {} tokens:\n", .{tokens.len});
    for (tokens, 0..) |token, i| {
        std.debug.print("  {}: {} '{s}'\n", .{ i, token.type, token.lexeme });
    }
}
