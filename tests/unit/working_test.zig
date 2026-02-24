// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Tokenizer = @import("compiler/libjanus/tokenizer.zig");
const Parser = @import("compiler/libjanus/parser.zig");

test "Janus Core Pipeline - Functional Test" {

    // Use page allocator to avoid leak detection complexity
    var allocator = std.heap.page_allocator;

    // Test 1: Tokenization
    const source = "func main() do print(\"Hello, Janus!\") end";

    var tokenizer = Tokenizer.Tokenizer.init(allocator, source);
    defer tokenizer.deinit();
    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len == 11); // Expected token count

    // Test 2: Parsing
    var parser = Parser.Parser.init(allocator, tokens);
    const program = try parser.parse();

    try std.testing.expect(program.statements.len == 1);

    // Test 3: AST Structure Validation
    const first_stmt = program.statements[0];
    try std.testing.expect(first_stmt.* == .func_decl);

    const func_decl = first_stmt.func_decl;
    try std.testing.expectEqualStrings(func_decl.name, "main");
    try std.testing.expect(func_decl.params.len == 0);
    try std.testing.expect(func_decl.body.* == .block_stmt);


    // Test 4: Multiple Functions
    const multi_source =
        \\func add() do return 1 end
        \\func sub() do return 2 end
    ;

    var tokenizer2 = Tokenizer.Tokenizer.init(allocator, multi_source);
    defer tokenizer2.deinit();
    const tokens2 = try tokenizer2.tokenize();
    defer allocator.free(tokens2);

    var parser2 = Parser.Parser.init(allocator, tokens2);
    const program2 = try parser2.parse();

    try std.testing.expect(program2.statements.len == 2);

}
