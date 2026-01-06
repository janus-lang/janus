// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("compiler/libjanus/astdb.zig");

test "debug snapshot creation only" {
    const allocator = std.testing.allocator;

    std.debug.print("Creating string interner...\n", .{});
    var str_interner = astdb.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    std.debug.print("Creating snapshot...\n", .{});
    const snapshot = astdb.Snapshot.init(allocator, &str_interner) catch |err| {
        std.debug.print("Snapshot creation failed: {}\n", .{err});
        return;
    };
    defer snapshot.deinit();

    std.debug.print("Snapshot created successfully!\n", .{});
}
