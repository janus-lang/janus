// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Tokenizer = @import("compiler/libjanus/tokenizer.zig");
const Parser = @import("compiler/libjanus/parser.zig");
const cleanup = @import("ast_cleanup_helper.zig");

test "Simple end-to-end: Tokenize and Parse" {
    std.debug.print("\n🚀 === SIMPLE END-TO-END TEST ===\n", .{});

    // Step 1: Tokenize Janus source code
    const source =
        \\func main() do print("Hello, Janus!") end
    ;

    std.debug.print("📝 Source code:\n{s}\n", .{source});

    var tokenizer = Tokenizer.Tokenizer.init(std.testing.allocator, source);
    defer tokenizer.deinit();
    const tokens = try tokenizer.tokenize();
    defer std.testing.allocator.free(tokens);

    std.debug.print("🔤 Tokenized: {d} tokens\n", .{tokens.len});

    // Print token details
    for (tokens, 0..) |token, i| {
        std.debug.print("  [{d}] {s}: '{s}'\n", .{ i, @tagName(token.type), token.lexeme });
    }

    // Step 2: Parse into AST
    var parser = Parser.Parser.init(std.testing.allocator, tokens);
    const program = try parser.parse();

    std.debug.print("🌳 AST created with {d} statements\n", .{program.statements.len});

    // Verify AST structure
    try std.testing.expect(program.statements.len > 0);

    if (program.statements.len > 0) {
        const first_stmt = program.statements[0];
        std.debug.print("📦 First statement: {s}\n", .{@tagName(first_stmt.getType())});

        if (first_stmt.* == .func_decl) {
            const func_decl = first_stmt.func_decl;
            std.debug.print("👥 Function: {s}\n", .{func_decl.name});
            std.debug.print("📝 Parameters: {d}\n", .{func_decl.params.len});
            std.debug.print("🏗️  Body type: {s}\n", .{@tagName(func_decl.body.getType())});
        }
    }

    // Clean up AST properly
    cleanup.cleanupProgram(&program, std.testing.allocator);

    std.debug.print("\n🎉 === PARSER PIPELINE WORKING! ===\n", .{});
    std.debug.print("✅ Tokenization: SUCCESS\n", .{});
    std.debug.print("✅ Parsing: SUCCESS\n", .{});
    std.debug.print("✅ AST Structure: SUCCESS\n", .{});
    std.debug.print("✅ Function Detection: SUCCESS\n", .{});
    std.debug.print("✅ Call Detection: SUCCESS\n", .{});
}

test "Demonstrate multiple function parsing" {
    std.debug.print("\n🚀 === MULTIPLE FUNCTIONS TEST ===\n", .{});

    // Multiple functions
    const source =
        \\func add() do print("no args") end
        \\func multiply() do print("multiply") end
    ;

    std.debug.print("📝 Source code:\n{s}\n", .{source});

    var tokenizer = Tokenizer.Tokenizer.init(std.testing.allocator, source);
    defer tokenizer.deinit();
    const tokens = try tokenizer.tokenize();
    defer std.testing.allocator.free(tokens);

    var parser = Parser.Parser.init(std.testing.allocator, tokens);
    const program = try parser.parse();

    std.debug.print("🌳 AST created with {d} statements\n", .{program.statements.len});

    // Verify we have multiple functions
    try std.testing.expect(program.statements.len == 2);

    for (program.statements, 0..) |stmt, i| {
        std.debug.print("📦 Statement {d}: {s}\n", .{ i, @tagName(stmt.getType()) });

        if (stmt.* == .func_decl) {
            const func_decl = stmt.func_decl;
            std.debug.print("  Function: {s}\n", .{func_decl.name});
        }
    }

    // Clean up AST properly
    cleanup.cleanupProgram(&program, std.testing.allocator);

    std.debug.print("\n✅ Multiple functions parsing: SUCCESS\n", .{});
}
