// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Simple test to check if basic imports work
test "Basic Import Test" {
    std.debug.print("Testing basic imports...\n", .{});

    // Test ASTDB import
    const astdb = @import("compiler/libjanus/astdb.zig");
    _ = astdb;
    std.debug.print("✅ ASTDB import works\n", .{});

    // Test ComptimeVM import
    const ComptimeVM = @import("compiler/comptime_vm.zig");
    _ = ComptimeVM;
    std.debug.print("✅ ComptimeVM import works\n", .{});

    // Test Enhanced Parser import
    const EnhancedASTDBParser = @import("compiler/enhanced_astdb_parser.zig");
    _ = EnhancedASTDBParser;
    std.debug.print("✅ Enhanced Parser import works\n", .{});

    std.debug.print("🎉 All imports successful\n", .{});
}
