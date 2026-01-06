// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const tokenizer = @import("../compiler/libjanus/janus_tokenizer.zig");

pub fn main() !void {
    const source = "func main() -> i32 { return 0 }";
    var tok = tokenizer.Tokenizer.init(std.heap.page_allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer std.heap.page_allocator.free(tokens);

    std.debug.print("Tokens for: {s}\n", .{source});
    for (tokens, 0..) |token, i| {
        std.debug.print("  {d}: {s} -> {s}\n", .{ i, @tagName(token.type), token.lexeme });
    }
}
