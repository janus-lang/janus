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

    // Use testing allocator to catch leaks
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var astdb_system = try ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();

    const simple_source = "const X = 42";

    var parser = try EnhancedASTDBParser.init(allocator, simple_source, &astdb_system);
    defer parser.deinit();

    const root_node = try parser.parseProgram();
    const snapshot = parser.getSnapshot();

    var parser_with_vm = try EnhancedASTDBParser.initWithComptimeVM(allocator, simple_source, &astdb_system, &comptime_vm);
    defer parser_with_vm.deinit();

    const root_node_vm = try parser_with_vm.parseProgram();
    const snapshot_vm = parser_with_vm.getSnapshot();

    // Check if constant was registered
    const x_name = try astdb_system.str_interner.get("X");
    const x_result = comptime_vm.getConstantValue(x_name);

    if (x_result) |_| {
    } else {
    }

    const stats = comptime_vm.getEvaluationStats();


    _ = root_node;
    _ = root_node_vm;
}
