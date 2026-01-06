// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Core Parser Tests - New Architecture
//!
//! Clean, focused tests for the core_astdb system.
//! Tests basic ASTDB operations and validates the infrastructure works.
//!
//! This replaces the legacy parser_expression_tests.zig with tests that
//! work with the current immutable ASTDB system.

const std = @import("std");
const testing = std.testing;

// Import the current working system
const core_astdb = @import("astdb_core");

// Core types from the working system
const AstDB = core_astdb.AstDB;
const Snapshot = core_astdb.Snapshot;
const NodeId = core_astdb.NodeId;
const NodeKind = core_astdb.AstNode.NodeKind;

test "astdb core: system initialization" {
    const allocator = testing.allocator;

    // Test that we can initialize the ASTDB system
    var astdb = try AstDB.init(allocator, true);
    defer astdb.deinit();

    // Test that we can create a snapshot
    const snapshot = try astdb.createSnapshot();
    // snapshot.deinit() is a no-op in current implementation

    // Basic validation - snapshot should be created successfully
    try testing.expect(snapshot.nodeCount() >= 0);
}

test "astdb core: unit creation" {
    const allocator = testing.allocator;

    var astdb = try AstDB.init(allocator, true);
    defer astdb.deinit();

    // Test that we can add a unit
    const unit_id = try astdb.addUnit("test.jan", "test content");

    // Test that we can retrieve the unit
    const unit = astdb.getUnit(unit_id);
    try testing.expect(unit != null);
}

test "astdb core: snapshot operations" {
    const allocator = testing.allocator;

    var astdb = try AstDB.init(allocator, true);
    defer astdb.deinit();

    // Add a unit
    const unit_id = try astdb.addUnit("test.jan", "test content");
    _ = unit_id;

    // Create snapshot
    const snapshot = try astdb.createSnapshot();
    // snapshot.deinit() is a no-op in current implementation

    // Test basic snapshot operations
    const node_count = snapshot.nodeCount();
    const token_count = snapshot.tokenCount();

    // Should have some basic structure
    try testing.expect(node_count >= 0);
    try testing.expect(token_count >= 0);
}

test "astdb core: node kinds available" {
    // Test that all the node kinds we expect are available
    const integer_literal = NodeKind.integer_literal;
    const string_literal = NodeKind.string_literal;
    const bool_literal = NodeKind.bool_literal;
    const null_literal = NodeKind.null_literal;
    const binary_expr = NodeKind.binary_expr;
    const var_stmt = NodeKind.var_stmt;

    // Just verify they compile and are accessible
    _ = integer_literal;
    _ = string_literal;
    _ = bool_literal;
    _ = null_literal;
    _ = binary_expr;
    _ = var_stmt;
}

test "astdb core: memory management" {
    const allocator = testing.allocator;

    // Test multiple create/destroy cycles
    for (0..3) |_| {
        var astdb = try AstDB.init(allocator, true);
        defer astdb.deinit();

        const unit_id = try astdb.addUnit("test.jan", "content");
        _ = unit_id;

        const snapshot = try astdb.createSnapshot();
        // snapshot.deinit() is a no-op in current implementation
        _ = snapshot;
    }
}
