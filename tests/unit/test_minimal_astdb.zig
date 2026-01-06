// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

test "Minimal ASTDB Import Test" {
    // Just try to import ASTDB
    const astdb = @import("compiler/libjanus/astdb.zig");
    _ = astdb;

    std.debug.print("✅ ASTDB import successful\n", .{});
}
