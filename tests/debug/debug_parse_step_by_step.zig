// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Tokenizer = @import("compiler/libjanus/tokenizer.zig");
const Parser = @import("compiler/libjanus/parser.zig");

test "debug parse step by step" {
    const allocator = std.testing.allocator;
    const source = "func main() { print(\"Hello, Janus!\") }";

    std.debug.print("Step 1: Tokenizing...\n", .{});

    var tokenizer = Tokenizer.Tokenizer.init(allocator, source);
    defer tokenizer.deinit();
    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    std.debug.print("Step 2: Creating parser...\n", .{});

    var parser = Parser.Parser.init(allocator, tokens);
    defer parser.deinit();

    std.debug.print("Step 3: Calling parse...\n", .{});

    const snapshot = parser.parse() catch |err| {
        std.debug.print("Parse failed with error: {}\n", .{err});
        return;
    };
    defer snapshot.deinit();

    std.debug.print("Parse successful!\n", .{});
}
