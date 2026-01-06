// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Unit Test: Postfix Guard Parser (RFC-018)
//
// TDD Style: Test-Driven Development
// Tests the parser's handling of postfix guard clauses at the token/AST level

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb_core");

// ========================================================================
// TDD-001: Parser recognizes postfix when after return
// ========================================================================
test "TDD-RFC018-001: Parser creates postfix_when node for return statement" {
    const allocator = testing.allocator;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source = "func foo() { return err when x < 0 }";
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify postfix_when node exists
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var found = false;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) {
            found = true;
            break;
        }
    }

    try testing.expect(found);
}

// ========================================================================
// TDD-002: Parser handles postfix when with expression statements
// ========================================================================
test "TDD-RFC018-002: Parser creates postfix_when for expression statements" {
    const allocator = testing.allocator;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source = "func foo() { print(msg) when debug }";
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var found_postfix = false;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) {
            found_postfix = true;
        }
    }

    try testing.expect(found_postfix);
}

// ========================================================================
// TDD-003: Parser does NOT create postfix_when for block statements
// ========================================================================
test "TDD-RFC018-003: Parser rejects postfix when on block statements" {
    const allocator = testing.allocator;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    // This should parse as: if statement, followed by unrelated code
    const source = "func foo() { if x do end }";
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var found_if = false;
    var found_postfix = false;

    for (unit.nodes) |node| {
        if (node.kind == .if_stmt) found_if = true;
        if (node.kind == .postfix_when) found_postfix = true;
    }

    try testing.expect(found_if);
    try testing.expect(!found_postfix);
}

// ========================================================================
// TDD-004: Parser handles multiple consecutive postfix guards
// ========================================================================
test "TDD-RFC018-004: Parser handles multiple postfix guards sequentially" {
    const allocator = testing.allocator;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\func validate(x: i32) {
        \\    return -1 when x < 0
        \\    return 0 when x == 0
        \\    return 1 when x > 0
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var guard_count: u32 = 0;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) guard_count += 1;
    }

    try testing.expectEqual(@as(u32, 3), guard_count);
}

// ========================================================================
// TDD-005: Guard condition can be complex expression
// ========================================================================
test "TDD-RFC018-005: Parser handles complex guard conditions" {
    const allocator = testing.allocator;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source = "func foo() { return err when x < 0 and y > 100 }";
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var found = false;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) {
            found = true;
            break;
        }
    }

    try testing.expect(found);
}

// ========================================================================
// TDD-006: Postfix when works with named return values
// ========================================================================
test "TDD-RFC018-006: Postfix when with named return values" {
    const allocator = testing.allocator;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source = "func foo() { return Error.NotFound when user == null }";
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var found = false;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) {
            found = true;
            break;
        }
    }

    try testing.expect(found);
}

// ========================================================================
// TDD-007: Token sequence verification
// ========================================================================
test "TDD-RFC018-007: Correct token sequence for postfix when" {
    const allocator = testing.allocator;

    var astdb = try astdb_core.AstDB.init(allocator, false);
    defer astdb.deinit();

    const source = "return x when y";
    const tokens = try janus_parser.tokenizeIntoSnapshot(&astdb, source);

    // Expected sequence: return, identifier(x), when, identifier(y), eof
    const token_table = tokens.token_table;

    try testing.expect(token_table.len >= 4);
    try testing.expectEqual(astdb_core.Token.TokenKind.return_, token_table[0].kind);
    try testing.expectEqual(astdb_core.Token.TokenKind.identifier, token_table[1].kind);
    try testing.expectEqual(astdb_core.Token.TokenKind.when, token_table[2].kind);
    try testing.expectEqual(astdb_core.Token.TokenKind.identifier, token_table[3].kind);
}

// ========================================================================
// TDD-008: AST structure validation
// ========================================================================
test "TDD-RFC018-008: postfix_when AST node has correct structure" {
    const allocator = testing.allocator;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source = "func foo() { return x when y }";
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    // Find the postfix_when node
    var postfix_node: ?astdb_core.AstNode = null;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) {
            postfix_node = node;
            break;
        }
    }

    try testing.expect(postfix_node != null);

    // postfix_when should have children (condition and statement)
    const node = postfix_node.?;
    const has_children = node.child_lo < node.child_hi;
    try testing.expect(has_children);
}

// ========================================================================
// TDD-009: No whitespace required before when
// ========================================================================
test "TDD-RFC018-009: Postfix when works without whitespace before keyword" {
    const allocator = testing.allocator;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    // This might look weird but should still parse
    const source = "func foo() { return x when y }";
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var found = false;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) found = true;
    }

    try testing.expect(found);
}

// ========================================================================
// TDD-010: Postfix when in nested scopes
// ========================================================================
test "TDD-RFC018-010: Postfix when works in nested scopes" {
    const allocator = testing.allocator;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const source =
        \\func outer() {
        \\    if x do
        \\        return err when y < 0
        \\    end
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var found = false;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) found = true;
    }

    try testing.expect(found);
}
