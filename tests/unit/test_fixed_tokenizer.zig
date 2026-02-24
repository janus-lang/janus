// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const tokenizer = @import("compiler/libjanus/tokenizer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const north_star_source =
        \\// demo.jan - The North Star MVP Program
        \\func pure_math(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\comptime {
        \\    let pure_func := std.meta.get_function("pure_math")
        \\    assert(pure_func.effects.is_pure())
        \\}
        \\
        \\func main() {
        \\    print("MVP analysis complete.")
        \\}
    ;


    const tokens = tokenizer.tokenize(allocator, north_star_source) catch |err| {
        return;
    };
    defer allocator.free(tokens);


    // Show key tokens for North Star features
    var comptime_found = false;
    var assert_found = false;
    var func_count: u32 = 0;

    for (tokens, 0..) |token, i| {

        switch (token.token_type) {
            .Func => func_count += 1,
            .Comptime => comptime_found = true,
            .Assert => assert_found = true,
            else => {},
        }
    }


    if (func_count >= 2 and comptime_found and assert_found) {
    } else {
    }
}
