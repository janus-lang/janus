// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Test for parseTokensIntoNodes function - FAILING TEST
//! This test verifies what is NOT YET implemented in the parser

const std = @import("std");
const testing = std.testing;
const astdb_core = @import("astdb_core");
const parser = @import("libjanus").parser;

test "parseTokensIntoNodes should parse function parameters" {
    const allocator = testing.allocator;

    // Create ASTDB system
    var astdb_system = try astdb_core.AstDB.init(allocator, true);
    defer astdb_system.deinit();

    // Function with parameters - this exposes that parameter parsing isn't implemented
    const source = "func add(a: i32, b: i32) -> i32 do end";

    // First tokenize
    const tokenization_result = try parser.tokenizeIntoSnapshot(&astdb_system, source);
    try testing.expect(tokenization_result.token_count > 0);

    // Parse tokens into nodes
    try parser.parseTokensIntoNodes(&astdb_system);

    // Verify parsing created basic structure
    try testing.expect(astdb_system.units.items.len > 0);

    const unit = astdb_system.units.items[0];
    try testing.expect(unit.nodes.len > 0);

    // Function declaration should be the second-to-last node (source_file is always last)
    const func_node = unit.nodes[unit.nodes.len - 2];
    try testing.expectEqual(astdb_core.AstNode.NodeKind.func_decl, func_node.kind);

    // THIS WILL FAIL: The current parser skips parameter parsing
    // See TODO comment in parseFunctionDeclaration: "TODO: Parse parameters"
    try testing.expect(func_node.child_hi > func_node.child_lo); // Should have child nodes for parameters
}
