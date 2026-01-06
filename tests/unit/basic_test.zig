// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello from basic test!\n", .{});

    // Test if we can import the tokenizer
    const Tokenizer = @import("compiler/libjanus/tokenizer.zig");
    std.debug.print("Tokenizer imported successfully!\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple tokenization test
    const source = "func main() do end";
    var tokenizer = Tokenizer.Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    std.debug.print("Tokenized {} tokens from: {s}\n", .{ tokens.len, source });

    std.debug.print("SUCCESS: Core tokenizer is working!\n", .{});
}
