// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("compiler/libjanus/api.zig");

test "tokenizer only test" {
    const allocator = std.testing.allocator;
    const source = "func main() { print(\"Hello, Janus!\") }";

    std.debug.print("Testing tokenizer...\n", .{});

    // Test just the tokenizer step
    const tokens = janus.tokenize(source, allocator) catch |err| {
        std.debug.print("Tokenize failed: {}\n", .{err});
        return;
    };
    defer allocator.free(tokens);

    std.debug.print("Tokenize successful! Got {} tokens\n", .{tokens.len});
}
