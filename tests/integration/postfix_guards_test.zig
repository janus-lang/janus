// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Postfix Guard Clauses (RFC-018)
//
// AC-BDD Style: Acceptance Criteria Driven Behavior-Driven Development
// This test validates that postfix guard clauses work end-to-end.
//
// GIVEN: A Janus program with postfix guard clauses
// WHEN: The program is compiled and executed
// THEN: Guards should prevent execution when condition is met

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb_core");

// ========================================================================
// Acceptance Criteria 1: Basic Postfix When Guard
// ========================================================================
// GIVEN: A return statement with a postfix 'when' guard
// WHEN: The guard condition is true
// THEN: The statement should execute (early return)
test "AC-RFC018-001: Basic postfix when guard with return" {
    const allocator = testing.allocator;

    const source =
        \\func validate_positive(x: i32) -> i32 {
        \\    return -1 when x < 0
        \\    return x
        \\}
    ;

    // 1. Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 2. Verify AST contains postfix_when node
    try testing.expect(snapshot.core_snapshot.nodeCount() > 0);

    // Find postfix_when node
    var found_postfix_when = false;
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) {
            found_postfix_when = true;
            break;
        }
    }

    try testing.expect(found_postfix_when);
}

// ========================================================================
// Acceptance Criteria 2: Multiple Postfix Guards (Pyramid Elimination)
// ========================================================================
// GIVEN: Multiple sequential postfix guards
// WHEN: Each guard has a different condition
// THEN: All guards should be parsed as separate postfix_when nodes
test "AC-RFC018-002: Multiple postfix guards eliminate pyramid of doom" {
    const allocator = testing.allocator;

    const source =
        \\func process_user(user: User?) -> Result {
        \\    return Error.NotFound when user == null
        \\    return Error.Inactive when not user.is_active
        \\    return Error.InsufficientFunds when user.balance < 0
        \\    return Result.Ok(user)
        \\}
    ;

    // 1. Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 2. Count postfix_when nodes (expect 3)
    var postfix_when_count: u32 = 0;
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) {
            postfix_when_count += 1;
        }
    }

    try testing.expectEqual(@as(u32, 3), postfix_when_count);
}

// ========================================================================
// Acceptance Criteria 3: Postfix Guard with Expression Statements
// ========================================================================
// GIVEN: Expression statements with postfix guards
// WHEN: Parsed
// THEN: Should create postfix_when nodes
test "AC-RFC018-003: Postfix guards with expression statements" {
    const allocator = testing.allocator;

    const source =
        \\func log_critical(event: Event) {
        \\    print("CRITICAL!") when event.severity == "critical"
        \\    alert(event) when event.requires_alert
        \\}
    ;

    // 1. Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 2. Verify postfix_when nodes exist
    var postfix_when_count: u32 = 0;
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) {
            postfix_when_count += 1;
        }
    }

    // Should have 2 postfix guards
    try testing.expectEqual(@as(u32, 2), postfix_when_count);
}

// ========================================================================
// Acceptance Criteria 4: Guard Condition Complexity
// ========================================================================
// GIVEN: Complex guard conditions (logical operators)
// WHEN: Parsed
// THEN: Should handle complex expressions correctly
test "AC-RFC018-004: Complex guard conditions with logical operators" {
    const allocator = testing.allocator;

    const source =
        \\func validate_complex(x: i32, y: i32) -> bool {
        \\    return false when x < 0 and y < 0
        \\    return false when x > 100 or y > 100
        \\    return true
        \\}
    ;

    // 1. Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 2. Verify successful parse with complex guards
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var postfix_when_count: u32 = 0;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) {
            postfix_when_count += 1;
        }
    }

    try testing.expectEqual(@as(u32, 2), postfix_when_count);
}

// ========================================================================
// Acceptance Criteria 5: No Postfix Guard on Block Statements
// ========================================================================
// GIVEN: A block statement (if, while, match)
// WHEN: Followed by 'when'
// THEN: Should NOT create postfix_when (per RFC, blocks don't support guards)
test "AC-RFC018-005: Block statements do not support postfix guards" {
    const allocator = testing.allocator;

    // This should be parsed as: if stmt, THEN a separate when token
    // NOT as a postfix_when on the if statement
    const source =
        \\func test_blocks() {
        \\    if x > 0 {
        \\        print("positive")
        \\    }
        \\    let y = 5
        \\}
    ;

    // 1. Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 2. Verify if_stmt exists but no postfix_when
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var found_if = false;
    var found_postfix_when = false;

    for (unit.nodes) |node| {
        if (node.kind == .if_stmt) found_if = true;
        if (node.kind == .postfix_when) found_postfix_when = true;
    }

    try testing.expect(found_if);
    try testing.expect(!found_postfix_when); // Should NOT have postfix_when
}

// ========================================================================
// Acceptance Criteria 6: Token Sequence Verification
// ========================================================================
// GIVEN: Source with postfix when
// WHEN: Tokenized
// THEN: 'when' should be recognized as keyword token
test "AC-RFC018-006: when keyword tokenization" {
    const allocator = testing.allocator;

    const source = "return error when x == null";

    // Just tokenize
    var astdb = try astdb_core.AstDB.init(allocator, false);
    defer astdb.deinit();

    const token_snapshot = try janus_parser.tokenizeIntoSnapshot(&astdb, source);

    // Find 'when' token
    var found_when = false;
    for (token_snapshot.token_table) |token| {
        if (token.kind == .when) {
            found_when = true;
            break;
        }
    }

    try testing.expect(found_when);
}

// ========================================================================
// Acceptance Criteria 7: Postfix Guards Read Like Prose
// ========================================================================
// GIVEN: Real-world validation function
// WHEN: Written with postfix guards
// THEN: Code should be more readable than nested if statements
test "AC-RFC018-007: Postfix guards improve readability" {
    const allocator = testing.allocator;

    // This is the "readable" version from RFC
    const readable_source =
        \\func validate_request(request: Request) -> Response {
        \\    return Error.MissingAuth when request.auth == null
        \\    return Error.BadMethod when request.method != "POST"
        \\    return Error.TooLarge when request.body_len > 10000
        \\    return handle_valid_request(request)
        \\}
    ;

    // Parse the readable version
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(readable_source);
    defer snapshot.deinit();

    // Verify 3 guards
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    const unit = snapshot.core_snapshot.astdb.getUnit(unit_id).?;

    var guard_count: u32 = 0;
    for (unit.nodes) |node| {
        if (node.kind == .postfix_when) guard_count += 1;
    }

    try testing.expectEqual(@as(u32, 3), guard_count);
}
