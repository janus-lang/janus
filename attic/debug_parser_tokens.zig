// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const tokenizer = @import("compiler/libjanus/janus_tokenizer.zig");
const parser = @import("compiler/libjanus/janus_parser.zig");
const astdb_core = @import("compiler/astdb/core_astdb.zig");

pub fn main() !void {
    const source = "func main() -> i32 { return 0 }";
    var tok = tokenizer.Tokenizer.init(std.heap.page_allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer std.heap.page_allocator.free(tokens);

    std.debug.print("Original tokens for: {s}\n", .{source});
    for (tokens, 0..) |token, i| {
        std.debug.print("  {d}: {s} -> {s}\n", .{ i, @tagName(token.type), token.lexeme });
    }

    // Test token conversion
    std.debug.print("\nConverted tokens:\n", .{});
    for (tokens, 0..) |token, i| {
        const converted = parser.convertTokenType(token.type);
        std.debug.print("  {d}: {s} -> {s}\n", .{ i, @tagName(token.type), @tagName(converted) });
    }
}
