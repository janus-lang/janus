// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// Test minimal ASTDB functionality
test "Minimal ASTDB Test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Just test that we can import and create basic structures
    const astdb = @import("compiler/libjanus/astdb.zig");

    // Create a simple ASTDB system
    var astdb_system = astdb.ASTDBSystem.init(allocator);
    defer astdb_system.deinit();

    // Create a snapshot
    var snapshot = astdb_system.createSnapshot();
    defer snapshot.deinit();

    std.debug.print("✅ ASTDB system created successfully\n", .{});

    // Test basic functionality
    const stats = astdb_system.getStats();
    std.debug.print("📊 ASTDB Stats: interned_strings={}, cached_cids={}\n", .{ stats.interned_strings, stats.cached_cids });
}
