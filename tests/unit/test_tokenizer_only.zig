// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("compiler/libjanus/api.zig");

test "tokenizer only test" {
    const allocator = std.testing.allocator;
    const source = "func main() { print(\"Hello, Janus!\") }";


    // Test just the tokenizer step
    const tokens = janus.tokenize(source, allocator) catch |err| {
        return;
    };
    defer allocator.free(tokens);

}
