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


    // Only const declarations - no functions or expressions
    const test_source = "const PI = 3.14159\nconst SIZE = 1024";


    // Test with comptime VM integration
    var parser = try EnhancedASTDBParser.initWithComptimeVM(allocator, test_source, &astdb_system, &comptime_vm);
    defer parser.deinit();

    const root_node = try parser.parseProgram();
    const snapshot = parser.getSnapshot();


    // Check if constants were registered
    const pi_name = try astdb_system.str_interner.get("PI");
    const pi_result = comptime_vm.getConstantValue(pi_name);

    if (pi_result) |_| {
    } else {
        return error.TestFailed;
    }

    const size_name = try astdb_system.str_interner.get("SIZE");
    const size_result = comptime_vm.getConstantValue(size_name);

    if (size_result) |_| {
    } else {
        return error.TestFailed;
    }

    const stats = comptime_vm.getEvaluationStats();

    if (stats.total_evaluations >= 2) {
    } else {
        return error.TestFailed;
    }

    _ = root_node;
}
