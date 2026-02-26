// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus_parser = @import("janus_parser.zig");
const tokenizer = @import("janus_tokenizer.zig");
const api = @import("api.zig");
const astdb_core = api.astdb;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "parse call expression with named arguments" {
    const allocator = std.testing.allocator;
    const source = "func_call(name: \"value\", another: 123)";

    var janus_tokenizer = tokenizer.Tokenizer.init(allocator, source);
    defer janus_tokenizer.deinit();

    const tokens = try janus_tokenizer.tokenize();

    var astdb_system = try allocator.create(astdb_core.AstDB);
    astdb_system.* = try astdb_core.AstDB.init(allocator, true);
    defer astdb_system.deinit();

    var parser = janus_parser.Parser.init(allocator, tokens);
    defer parser.deinit();

    // Manually set up a compilation unit and tokens for the parser
    const unit_id = try astdb_system.addUnit("test.jan", source);
    const unit = astdb_system.getUnit(unit_id) orelse unreachable;

    var astdb_tokens: std.ArrayList(astdb_core.Token) = .empty);
    for (tokens) |old_token| {
        const astdb_token_kind = janus_parser.convertTokenType(old_token.type);
        var str_id: ?astdb_core.StrId = null;
        if (old_token.type == .identifier or old_token.type == .number or old_token.type == .string) {
            str_id = try astdb_system.str_interner.intern(old_token.lexeme);
        }
        try astdb_tokens.append(astdb_core.Token{
            .kind = astdb_token_kind,
            .str = str_id,
            .span = astdb_core.SourceSpan{
                .start = @intCast(old_token.span.start.byte_offset),
                .end = @intCast(old_token.span.end.byte_offset),
                .line = old_token.span.start.line,
                .column = old_token.span.start.column,
            },
            .trivia_lo = 0,
            .trivia_hi = 0,
        });
    }
    unit.tokens = try astdb_tokens.toOwnedSlice();

    var parser_state = janus_parser.ParserState{
        .tokens = unit.tokens,
        .current = 0,
        .unit = unit,
        .allocator = unit.arenaAllocator(),
    };

    // Simulate parsing the function name before calling parseCallExpression
    _ = parser_state.advance(); // Consume 'func_call' identifier

    var nodes: std.ArrayList(astdb_core.AstNode) = .empty;
    defer nodes.deinit();

    const call_expr_node = try janus_parser.parseCallExpression(&parser_state, &nodes);

    try expectEqual(call_expr_node.kind, astdb_core.AstNode.NodeKind.call_expr);
    try expectEqual(nodes.items.len, 4); // func_call, name, value, another, 123
    // TODO: Add more specific checks for named arguments once implemented
}
