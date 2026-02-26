// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Tokenizer = @import("compiler/libjanus/tokenizer.zig");
const Parser = @import("compiler/libjanus/parser.zig");
const cleanup = @import("ast_cleanup_helper.zig");

test "Simple end-to-end: Tokenize and Parse" {

    // Step 1: Tokenize Janus source code
    const source =
        \\func main() do print("Hello, Janus!") end
    ;


    var tokenizer = Tokenizer.Tokenizer.init(std.testing.allocator, source);
    defer tokenizer.deinit();
    const tokens = try tokenizer.tokenize();
    defer std.testing.allocator.free(tokens);


    // Print token details
    for (tokens, 0..) |token, i| {
    }

    // Step 2: Parse into AST
    var parser = Parser.Parser.init(std.testing.allocator, tokens);
    const program = try parser.parse();


    // Verify AST structure
    try std.testing.expect(program.statements.len > 0);

    if (program.statements.len > 0) {
        const first_stmt = program.statements[0];

        if (first_stmt.* == .func_decl) {
            const func_decl = first_stmt.func_decl;
        }
    }

    // Clean up AST properly
    cleanup.cleanupProgram(&program, std.testing.allocator);

}

test "Demonstrate multiple function parsing" {

    // Multiple functions
    const source =
        \\func add() do print("no args") end
        \\func multiply() do print("multiply") end
    ;


    var tokenizer = Tokenizer.Tokenizer.init(std.testing.allocator, source);
    defer tokenizer.deinit();
    const tokens = try tokenizer.tokenize();
    defer std.testing.allocator.free(tokens);

    var parser = Parser.Parser.init(std.testing.allocator, tokens);
    const program = try parser.parse();


    // Verify we have multiple functions
    try std.testing.expect(program.statements.len == 2);

    for (program.statements, 0..) |stmt, i| {

        if (stmt.* == .func_decl) {
            const func_decl = stmt.func_decl;
        }
    }

    // Clean up AST properly
    cleanup.cleanupProgram(&program, std.testing.allocator);

}
