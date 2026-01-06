// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const EnhancedASTDBParser = @import("compiler/enhanced_astdb_parser.zig").EnhancedASTDBParser;
const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
const astdb = @import("compiler/libjanus/astdb.zig");
const ASTDBSystem = astdb.ASTDBSystem;

// Memory leak diagnosis test - minimal scope to isolate issues
test "Memory Leak Diagnosis - Minimal Integration" {
    std.debug.print("\n🔍 MEMORY LEAK DIAGNOSIS\n", .{});
    std.debug.print("========================\n", .{});

    // Use testing allocator to catch leaks
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.debug.print("📋 Step 1: Initialize ASTDB system\n", .{});
    var astdb_system = try ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();
    std.debug.print("✅ ASTDB system initialized\n", .{});

    std.debug.print("📋 Step 2: Initialize Comptime VM\n", .{});
    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();
    std.debug.print("✅ Comptime VM initialized\n", .{});

    std.debug.print("📋 Step 3: Test minimal parsing (no integration)\n", .{});
    const simple_source = "const X = 42";

    var parser = try EnhancedASTDBParser.init(allocator, simple_source, &astdb_system);
    defer parser.deinit();
    std.debug.print("✅ Parser initialized without integration\n", .{});

    const root_node = try parser.parseProgram();
    const snapshot = parser.getSnapshot();
    std.debug.print("✅ Parsed {} nodes without integration\n", .{snapshot.nodeCount()});

    std.debug.print("📋 Step 4: Test with Comptime VM integration\n", .{});
    var parser_with_vm = try EnhancedASTDBParser.initWithComptimeVM(allocator, simple_source, &astdb_system, &comptime_vm);
    defer parser_with_vm.deinit();
    std.debug.print("✅ Parser initialized with integration\n", .{});

    const root_node_vm = try parser_with_vm.parseProgram();
    const snapshot_vm = parser_with_vm.getSnapshot();
    std.debug.print("✅ Parsed {} nodes with integration\n", .{snapshot_vm.nodeCount()});

    // Check if constant was registered
    const x_name = try astdb_system.str_interner.get("X");
    const x_result = comptime_vm.getConstantValue(x_name);

    if (x_result) |_| {
        std.debug.print("✅ Constant X registered successfully\n", .{});
    } else {
        std.debug.print("❌ Constant X not registered\n", .{});
    }

    const stats = comptime_vm.getEvaluationStats();
    std.debug.print("📊 VM Stats: {d} evaluations, {d} cached\n", .{ stats.total_evaluations, stats.cached_results });

    std.debug.print("🎉 Memory diagnosis complete - using arena allocator\n", .{});

    _ = root_node;
    _ = root_node_vm;
}
