// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! DEBUG: Live-Fire Exercise Analysis
//! Let's see what's actually being parsed

const std = @import("std");
const testing = std.testing;

const libjanus = @import("libjanus");
const parser = libjanus.parser;
const ASTDBSystem = libjanus.ASTDBSystem;

test "DEBUG: Let statement parsing analysis" {
    const allocator = testing.allocator;

    const janus_source = "let x := 42";

    var astdb_system = try ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    const tokenization_result = try parser.tokenizeIntoSnapshot(&astdb_system, janus_source);

    // Let's see what tokens were created
    if (astdb_system.snapshots.items.len > 0) {
        const snapshot = &astdb_system.snapshots.items[0];

        for (snapshot.tokens, 0..) |token, i| {
        }
    }

    try parser.parseTokensIntoNodes(&astdb_system);


    if (astdb_system.units.items.len > 0) {
        const unit = astdb_system.units.items[0];

        for (unit.nodes, 0..) |node, i| {
        }
    }
}
