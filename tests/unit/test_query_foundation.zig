// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Quick test of query foundation
const std = @import("std");
const context = @import("compiler/libjanus/query/context.zig");

test "basic query context" {
    const testing = std.testing;

    // Test CID type
    const test_cid: context.CID = [_]u8{1} ** 32;
    _ = test_cid;

    // Test MemoKey
    const key = context.MemoKey{ .hash = [_]u8{2} ** 32 };
    const key2 = context.MemoKey{ .hash = [_]u8{2} ** 32 };

    try testing.expect(key.eql(key2));

    std.debug.print("Query foundation test passed!\n", .{});
}
