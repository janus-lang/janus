const std = @import("std");
const janus = @import("compiler/libjanus/api.zig");
const tokenizer = @import("compiler/libjanus/janus_tokenizer.zig");

pub fn main() !void {
    const source =
        \\use std.io
        \\use std.os
        \\use jfind.walker
        \\use jfind.filter
        \\use jfind.output
        \\
        \\// Configuration structure
        \\struct Config {
        \\    path: string,
        \\    max_depth: i32,
        \\    show_hidden: bool,
        \\    extensions: []string,
        \\    name_pattern: string,
        \\    ignore_case: bool,
        \\}
        \\
        \\// Parse command line arguments and initialize config
        \\func parse_cli_args() -> void {
        \\    // Parse path (first positional arg or current directory)
        \\    if (os.args.len > 1) do
        \\        config.path = os.args[1]
        \\    else do
        \\        config.path = "."
        \\    end
        \\}
        \\
        \\func main() -> i32 {
        \\    return 0
        \\}
    ;

    var tok = tokenizer.Tokenizer.init(std.heap.page_allocator, source);
    defer tok.deinit();

    const tokens = try tok.tokenize();
    defer std.heap.page_allocator.free(tokens);

    std.debug.print("Tokens for jfind:\n", .{});
    for (tokens, 0..) |token, i| {
        std.debug.print("  {d}: {s} -> {s}\n", .{ i, @tagName(token.type), token.lexeme });
    }
}
