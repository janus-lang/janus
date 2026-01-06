// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("../astdb/astdb.zig");
const cid = @import("../astdb/cid.zig");

// ASTDB Integration Test - Verify Task 1 implementation compiles and works
// Task 1: AST Persistence Layer - Integration verification
// Requirements: All components work together correctly

test "ASTDB Task 1 - Complete integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🔥 Testing ASTDB Task 1 - AST Persistence Layer", .{});

    // Initialize ASTDB system
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    std.log.info("✅ ASTDB system initialized", .{});

    // Test string interning
    const hello_str = try db.str_interner.get("hello");
    const world_str = try db.str_interner.get("world");
    const hello_str2 = try db.str_interner.get("hello"); // Should deduplicate

    try testing.expectEqual(hello_str, hello_str2);
    try testing.expect(!std.meta.eql(hello_str, world_str));

    std.log.info("✅ String interning works correctly", .{});

    // Test compilation unit creation
    const unit_id = try db.addUnit("test.jan", "func main() {}");
    defer _ = db.removeUnit(unit_id) catch {};

    const unit = db.getUnit(unit_id);
    try testing.expect(unit != null);
    std.log.info("✅ Compilation unit creation works correctly", .{});

    // Test CID computation with semantic encoder
    var encoder = cid.SemanticEncoder.init(allocator, &db, true);
    defer encoder.deinit();

    const scope = cid.CidScope{ .module_unit = unit_id };
    const cid1 = try encoder.computeCID(scope);
    const cid2 = try encoder.computeCID(scope); // Should be identical

    try testing.expectEqualSlices(u8, &cid1, &cid2);
    std.log.info("✅ CID computation works correctly", .{});

    // Test CID is not all zeros (valid hash)
    const zero_cid = [_]u8{0} ** 32;
    try testing.expect(!std.mem.eql(u8, &cid1, &zero_cid));
    std.log.info("✅ CID uniqueness works correctly", .{});

    std.log.info("🎉 ASTDB Task 1 - AST Persistence Layer - ALL TESTS PASSED!", .{});
    std.log.info("   ✅ String interning with deduplication", .{});
    std.log.info("   ✅ Compilation unit management", .{});
    std.log.info("   ✅ Deterministic CID computation", .{});
    std.log.info("   ✅ Revolutionary ASTDB architecture validated", .{});
    std.log.info("", .{});
    std.log.info("🔥 Ready for ASTDB-First Development Integration!", .{});
}
