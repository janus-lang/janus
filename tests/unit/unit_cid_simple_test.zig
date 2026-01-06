// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("compiler/astdb/astdb.zig");
const cid = @import("compiler/astdb/cid.zig");

test "CID basic hash computation" {
    var db = astdb.AstDB.init(std.testing.allocator);
    defer db.deinit();

    var encoder = cid.SemanticEncoder.init(std.testing.allocator, &db, false);
    defer encoder.deinit();

    // Create a test unit
    const unit_id = try db.addUnit("test.jan", "func main() {}");

    // Test module unit CID computation
    const module_cid = try encoder.computeCID(.{ .module_unit = unit_id });

    // Should produce a valid 32-byte hash
    try std.testing.expectEqual(@as(usize, 32), module_cid.len);

    // Computing again should be identical
    const module_cid2 = try encoder.computeCID(.{ .module_unit = unit_id });
    try std.testing.expectEqualSlices(u8, &module_cid, &module_cid2);
}
