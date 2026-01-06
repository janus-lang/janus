// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Test for tokenizeIntoSnapshot function
//! This test verifies the ASTDB tokenization pipeline

const std = @import("std");
const testing = std.testing;
const astdb_core = @import("astdb_core");
const parser = @import("libjanus").parser;

test "tokenizeIntoSnapshot basic functionality" {
    const allocator = testing.allocator;

    // Create ASTDB system
    var astdb_system = try astdb_core.AstDB.init(allocator, true);
    defer astdb_system.deinit();

    // Test source code
    const source = "func main() {}";

    // Call tokenizeIntoSnapshot
    const result = try parser.tokenizeIntoSnapshot(&astdb_system, source);

    // Verify result
    try testing.expect(result.token_count > 0);
    try testing.expect(result.token_table.len > 0);

    // Verify we have expected tokens: func, main, (, ), {, }, eof
    try testing.expect(result.token_count >= 6);

    // Check first token is 'func'
    try testing.expectEqual(astdb_core.Token.TokenKind.func, result.token_table[0].kind);
}

test "tokenizeIntoSnapshot with walrus operator" {
    const allocator = testing.allocator;

    // Create ASTDB system
    var astdb_system = try astdb_core.AstDB.init(allocator, true);
    defer astdb_system.deinit();

    // Test source with walrus operator
    const source = "let x := 42";

    // Call tokenizeIntoSnapshot
    const result = try parser.tokenizeIntoSnapshot(&astdb_system, source);

    // Verify walrus operator is split into : and =
    try testing.expect(result.token_count >= 5); // let, x, :, =, 42, eof

    // Find colon and assign tokens
    var found_colon = false;
    var found_assign = false;

    for (result.token_table) |token| {
        if (token.kind == .colon) found_colon = true;
        if (token.kind == .assign) found_assign = true;
    }

    try testing.expect(found_colon);
    try testing.expect(found_assign);
}
