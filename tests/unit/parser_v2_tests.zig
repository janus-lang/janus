// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Parser V2 Tests - The Atomic Forge Protocol
//!
//! These tests define the exact specification for what the parser MUST implement.
//! Each test is a failing mold that defines success criteria.
//! No implementation code is written until the test exists and fails.

const std = @import("std");
const testing = std.testing;
const astdb_core = @import("astdb_core");
const parser = @import("libjanus").parser;

test "parser must create proper parameter nodes for function declarations" {
    const allocator = testing.allocator;

    // Create ASTDB system
    var astdb_system = try astdb_core.AstDB.init(allocator, true);
    defer astdb_system.deinit();

    // Function with two parameters - this is the specification
    const source = "func add(a: i32, b: i32) {}";

    // First tokenize
    const tokenization_result = try parser.tokenizeIntoSnapshot(&astdb_system, source);
    try testing.expect(tokenization_result.token_count > 0);

    // Parse tokens into nodes - this must create proper AST structure
    try parser.parseTokensIntoNodes(&astdb_system);

    // Verify parsing created the compilation unit
    try testing.expect(astdb_system.units.items.len > 0);
    const unit = astdb_system.units.items[0];
    try testing.expect(unit.nodes.len > 0);

    // Debug: Print all nodes in the unit
    std.debug.print("DEBUG: unit has {} nodes\n", .{unit.nodes.len});
    for (unit.nodes, 0..) |node, i| {
        std.debug.print("DEBUG: nodes[{}] = {s}\n", .{ i, @tagName(node.kind) });
    }

    // SPECIFICATION: Source file should be the last node (root)
    const source_file_node = unit.nodes[unit.nodes.len - 1];
    try testing.expectEqual(astdb_core.AstNode.NodeKind.source_file, source_file_node.kind);

    // SPECIFICATION: Source file should have children (the function declaration)
    try testing.expect(source_file_node.child_hi > source_file_node.child_lo);

    // SPECIFICATION: First child should be the function declaration
    const func_node = unit.nodes[source_file_node.child_lo];
    try testing.expectEqual(astdb_core.AstNode.NodeKind.func_decl, func_node.kind);

    // SPECIFICATION: Function node MUST have child nodes for parameters
    // This is the critical failure point - current parser sets child_hi = child_lo = 0
    std.debug.print("DEBUG: func_node.child_lo={}, child_hi={}\n", .{ func_node.child_lo, func_node.child_hi });
    try testing.expect(func_node.child_hi > func_node.child_lo); // WILL FAIL - no children created

    // SPECIFICATION: Must have exactly 2 parameter child nodes
    const child_count = func_node.child_hi - func_node.child_lo;
    try testing.expectEqual(@as(u32, 2), child_count); // WILL FAIL - child_count is 0

    // SPECIFICATION: First parameter must be a parameter node
    const first_param_node = unit.nodes[func_node.child_lo];
    try testing.expectEqual(astdb_core.AstNode.NodeKind.parameter, first_param_node.kind);

    // SPECIFICATION: Second parameter must be a parameter node
    const second_param_node = unit.nodes[func_node.child_lo + 1];
    try testing.expectEqual(astdb_core.AstNode.NodeKind.parameter, second_param_node.kind);
}

test "parser must parse let statement with type annotation and integer literal" {
    // THE MOLD: This test defines the exact specification for let statement parsing
    // Source: let x: i32 = 42;
    // Expected AST: let_decl node with identifier, type annotation, and integer literal children

    const allocator = testing.allocator;

    // Create ASTDB system
    var astdb_system = try astdb_core.AstDB.init(allocator, true);
    defer astdb_system.deinit();

    // SPECIFICATION: Parse a let statement with type annotation and initializer
    const source = "let x: i32 = 42;";

    // First tokenize
    const tokenization_result = try parser.tokenizeIntoSnapshot(&astdb_system, source);
    try testing.expect(tokenization_result.token_count > 0);

    // Parse tokens into nodes - this WILL FAIL until let parsing is implemented
    try parser.parseTokensIntoNodes(&astdb_system);

    // Verify parsing created the compilation unit
    try testing.expect(astdb_system.units.items.len > 0);
    const unit = astdb_system.units.items[0];
    try testing.expect(unit.nodes.len > 0);

    // Debug: Print all nodes in the unit
    std.debug.print("DEBUG: let statement unit has {} nodes\n", .{unit.nodes.len});
    for (unit.nodes, 0..) |node, i| {
        std.debug.print("DEBUG: nodes[{}] = {s}\n", .{ i, @tagName(node.kind) });
    }

    // SPECIFICATION: Must have a let_stmt node
    var found_let_stmt = false;
    var let_node: astdb_core.AstNode = undefined;
    for (unit.nodes) |node| {
        if (node.kind == astdb_core.AstNode.NodeKind.let_stmt) {
            found_let_stmt = true;
            let_node = node;
            break;
        }
    }
    try testing.expect(found_let_stmt); // WILL FAIL - no let_stmt parsing implemented

    // SPECIFICATION: let_stmt node must have child nodes (identifier, type, initializer)
    try testing.expect(let_node.child_hi > let_node.child_lo); // WILL FAIL - no children

    // SPECIFICATION: Must have exactly 3 children: identifier, type annotation, initializer
    const child_count = let_node.child_hi - let_node.child_lo;
    try testing.expectEqual(@as(u32, 3), child_count); // WILL FAIL - no children

    // SPECIFICATION: First child must be identifier node for 'x'
    const identifier_node = unit.nodes[let_node.child_lo];
    try testing.expectEqual(astdb_core.AstNode.NodeKind.identifier, identifier_node.kind);

    // SPECIFICATION: Second child must be type node for 'i32'
    const type_node = unit.nodes[let_node.child_lo + 1];
    try testing.expectEqual(astdb_core.AstNode.NodeKind.primitive_type, type_node.kind);

    // SPECIFICATION: Third child must be integer literal node for '42'
    const literal_node = unit.nodes[let_node.child_lo + 2];
    try testing.expectEqual(astdb_core.AstNode.NodeKind.integer_literal, literal_node.kind);
}
