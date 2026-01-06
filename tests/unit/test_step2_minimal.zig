// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const EnhancedASTDBParser = @import("compiler/enhanced_astdb_parser.zig").EnhancedASTDBParser;
const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
const astdb = @import("compiler/libjanus/astdb.zig");
const ASTDBSystem = astdb.ASTDBSystem;

test "Step 2: Minimal Comptime VM Integration Test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize systems
    var astdb_system = try ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();

    std.debug.print("\n🔒 STEP 2: MINIMAL COMPTIME VM INTEGRATION TEST\n", .{});

    // Only const declarations - no functions or expressions
    const test_source = "const PI = 3.14159\nconst SIZE = 1024";

    std.debug.print("📄 Testing: {s}\n", .{test_source});

    // Test with comptime VM integration
    var parser = try EnhancedASTDBParser.initWithComptimeVM(allocator, test_source, &astdb_system, &comptime_vm);
    defer parser.deinit();

    const root_node = try parser.parseProgram();
    const snapshot = parser.getSnapshot();

    std.debug.print("✅ Parsed {} nodes\n", .{snapshot.nodeCount()});

    // Check if constants were registered
    const pi_name = try astdb_system.str_interner.get("PI");
    const pi_result = comptime_vm.getConstantValue(pi_name);

    if (pi_result) |_| {
        std.debug.print("✅ PI registered with Comptime VM\n", .{});
    } else {
        std.debug.print("❌ PI not registered\n", .{});
        return error.TestFailed;
    }

    const size_name = try astdb_system.str_interner.get("SIZE");
    const size_result = comptime_vm.getConstantValue(size_name);

    if (size_result) |_| {
        std.debug.print("✅ SIZE registered with Comptime VM\n", .{});
    } else {
        std.debug.print("❌ SIZE not registered\n", .{});
        return error.TestFailed;
    }

    const stats = comptime_vm.getEvaluationStats();
    std.debug.print("📊 Stats: {d} evaluations, {d} cached\n", .{ stats.total_evaluations, stats.cached_results });

    if (stats.total_evaluations >= 2) {
        std.debug.print("🎉 SUCCESS: Comptime VM Integration Working!\n", .{});
    } else {
        std.debug.print("❌ FAILED: Expected at least 2 evaluations\n", .{});
        return error.TestFailed;
    }

    _ = root_node;
}
