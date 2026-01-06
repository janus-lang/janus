// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

test "ComptimeVM Minimal Memory Fix Test" {
    const allocator = std.testing.allocator;
    const astdb = @import("compiler/libjanus/astdb.zig");
    const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;

    std.debug.print("\n🔧 MINIMAL COMPTIME VM MEMORY FIX TEST\n", .{});

    // Test that ComptimeVM can be created and destroyed without leaks
    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();

    // Test basic functionality
    const stats = comptime_vm.getEvaluationStats();
    try testing.expectEqual(@as(u32, 0), stats.total_evaluations);

    std.debug.print("✅ ComptimeVM memory fix test passed\n", .{});
}
