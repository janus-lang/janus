// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Tokenizer = @import("compiler/tokenizer.zig").Tokenizer;

test "Simple Tokenizer Test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "func main() { return 42 }";

    var tokenizer = Tokenizer.init(allocator, source);

    const token1 = try tokenizer.nextToken();
    try testing.expect(token1.type == .func);

    const token2 = try tokenizer.nextToken();
    try testing.expect(token2.type == .identifier);

    std.debug.print("Tokenizer working correctly!\n", .{});
}
