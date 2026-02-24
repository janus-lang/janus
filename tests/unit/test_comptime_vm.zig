// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    // Import ASTDB system
    const astdb = @import("compiler/libjanus/astdb.zig");

    // Initialize ASTDB system
    var astdb_system = try astdb.ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();


    // Create snapshot
    var snapshot = try astdb_system.createSnapshot();
    defer snapshot.deinit();


    // Import effect system
    const EffectSystem = @import("compiler/effect_system.zig");

    // Initialize effect system
    var effect_system = EffectSystem.EffectCapabilitySystem.init(allocator, &astdb_system);
    defer effect_system.deinit();


    // Import comptime VM
    const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
    const ComptimeValue = @import("compiler/comptime_vm.zig").ComptimeValue;

    // Initialize comptime VM
    var comptime_vm = ComptimeVM.init(allocator, &astdb_system, snapshot, &effect_system);
    defer comptime_vm.deinit();


    // Test comptime variable storage
    const var_name = try astdb_system.str_interner.get("test_var");
    const value = ComptimeValue{ .integer = 42 };

    try comptime_vm.context.setVariable(var_name, value, true);

    const retrieved = comptime_vm.context.getVariable(var_name);
    if (retrieved != null and retrieved.?.value.integer == 42) {
    } else {
    }

    // Test North Star MVP simulation

    // Register functions in effect system
    const pure_func_str = try astdb_system.str_interner.get("pure_math");
    const file_func_str = try astdb_system.str_interner.get("read_a_file");

    const pure_func_node: astdb.NodeId = @enumFromInt(1);
    const file_func_node: astdb.NodeId = @enumFromInt(2);

    try effect_system.registerFunction(pure_func_node, pure_func_str);
    try effect_system.registerFunction(file_func_node, file_func_str);

    try effect_system.addFunctionEffect(pure_func_node, .pure);
    try effect_system.addFunctionEffect(file_func_node, .io_fs_read);
    try effect_system.addFunctionCapability(file_func_node, .cap_fs_read);


    // Simulate comptime variables: let pure_func := std.meta.get_function("pure_math")
    const pure_func_var = try astdb_system.str_interner.get("pure_func");
    const pure_func_ref = ComptimeValue{
        .function_ref = .{
            .node_id = pure_func_node,
            .name = pure_func_str,
            .effects = &[_]EffectSystem.EffectType{.pure},
            .capabilities = &[_]EffectSystem.CapabilityType{},
        },
    };

    try comptime_vm.context.setVariable(pure_func_var, pure_func_ref, true);

    // Simulate: let file_func := std.meta.get_function("read_a_file")
    const file_func_var = try astdb_system.str_interner.get("file_func");
    const file_func_ref = ComptimeValue{
        .function_ref = .{
            .node_id = file_func_node,
            .name = file_func_str,
            .effects = &[_]EffectSystem.EffectType{.io_fs_read},
            .capabilities = &[_]EffectSystem.CapabilityType{.cap_fs_read},
        },
    };

    try comptime_vm.context.setVariable(file_func_var, file_func_ref, true);

    // Verify comptime analysis capabilities
    const pure_var = comptime_vm.context.getVariable(pure_func_var).?;
    const file_var = comptime_vm.context.getVariable(file_func_var).?;


    // Test effect queries (simulating comptime assertions)
    const pure_effects = ComptimeValue.EffectSet{ .effects = pure_var.value.function_ref.effects };
    const file_effects = ComptimeValue.EffectSet{ .effects = file_var.value.function_ref.effects };

    const pure_is_pure = pure_effects.isPure();
    const file_is_pure = file_effects.isPure();
    const file_has_fs_read = file_effects.hasEffect(.io_fs_read);


    // Get comptime VM statistics
    const stats = comptime_vm.getStats();



}
