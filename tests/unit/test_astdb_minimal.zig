// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("compiler/astdb/astdb.zig");
const cid = @import("compiler/astdb/cid.zig");

test "ASTDB minimal integration test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🔥 Testing ASTDB minimal integration", .{});

    // Initialize ASTDB system
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    std.log.info("✅ ASTDB system initialized", .{});

    // Test string interning
    const hello_id = try db.str_interner.intern("hello");
    const world_id = try db.str_interner.intern("world");
    const hello_id2 = try db.str_interner.intern("hello"); // Should deduplicate

    try testing.expectEqual(hello_id, hello_id2);
    try testing.expect(!std.meta.eql(hello_id, world_id));

    // Test retrieval
    const hello_str = db.str_interner.get(hello_id).?;
    const world_str = db.str_interner.get(world_id).?;
    try testing.expectEqualStrings("hello", hello_str);
    try testing.expectEqualStrings("world", world_str);

    std.log.info("✅ String interning works correctly", .{});

    // Test compilation unit creation
    const unit_id = try db.addUnit("test.jan", "func main() {}");
    defer _ = db.removeUnit(unit_id) catch {};

    const unit = db.getUnit(unit_id);
    try testing.expect(unit != null);
    std.log.info("✅ Compilation unit creation works correctly", .{});

    std.log.info("🎉 ASTDB minimal integration - ALL TESTS PASSED!", .{});
}
