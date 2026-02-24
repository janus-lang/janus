// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn main() !void {

    // Test if we can import the tokenizer
    const Tokenizer = @import("compiler/libjanus/tokenizer.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple tokenization test
    const source = "func main() do end";
    var tokenizer = Tokenizer.Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);


}
