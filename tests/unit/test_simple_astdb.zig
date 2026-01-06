// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

test "Simple ASTDB import test" {
    std.log.info("Testing simple ASTDB import", .{});

    // Try to import ASTDB
    const astdb = @import("compiler/libjanus/astdb.zig");
    _ = astdb;

    std.log.info("✅ ASTDB import successful", .{});
}
