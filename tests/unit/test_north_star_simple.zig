// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// Revolutionary ASTDB imports
const astdb = @import("compiler/libjanus/astdb.zig");
const ASTDBSystem = astdb.ASTDBSystem;
const Snapshot = astdb.Snapshot;
const NodeId = astdb.NodeId;

// Effect system integration
const EffectSystem = @import("compiler/effect_system.zig");
const EffectType = EffectSystem.EffectType;
const CapabilityType = EffectSystem.CapabilityType;
const EffectCapabilitySystem = EffectSystem.EffectCapabilitySystem;

// Revolutionary Comptime VM
const ComptimeVM = @import("compiler/comptime_vm.zig");

// Simple North Star MVP Test
test "North Star MVP Simple Integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🎯 North Star MVP Simple Integration Test", .{});

    // Initialize revolutionary ASTDB system
    var astdb_system = try ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    var snapshot = try astdb_system.createSnapshot();
    defer snapshot.deinit();

    // Initialize effect & capability system
    var effect_system = EffectCapabilitySystem.init(allocator, &astdb_system);
    defer effect_system.deinit();

    // Initialize revolutionary comptime VM
    var comptime_vm = ComptimeVM.ComptimeVM.init(allocator, &astdb_system, snapshot, &effect_system);
    defer comptime_vm.deinit();

    std.log.info("✅ Revolutionary systems initialized", .{});

    // Register test functions
    const pure_func_node: NodeId = @enumFromInt(1);
    const io_func_node: NodeId = @enumFromInt(2);

    const pure_func_name = try astdb_system.str_interner.get("pure_math");
    const io_func_name = try astdb_system.str_interner.get("read_a_file");

    try effect_system.registerFunction(pure_func_node, pure_func_name);
    try effect_system.addFunctionEffect(pure_func_node, .pure);

    try effect_system.registerFunction(io_func_node, io_func_name);
    try effect_system.addFunctionEffect(io_func_node, .io_fs_read);
    try effect_system.addFunctionCapability(io_func_node, .cap_fs_read);

    std.log.info("✅ Functions registered in effect system", .{});

    // Test comptime meta-programming simulation

    // Create function references with static arrays (no dynamic allocation)
    const pure_effects = [_]EffectType{.pure};
    const pure_capabilities = [_]CapabilityType{};

    const pure_func_ref = ComptimeVM.ComptimeValue{
        .function_ref = .{
            .node_id = pure_func_node,
            .name = pure_func_name,
            .effects = pure_effects[0..],
            .capabilities = pure_capabilities[0..],
        },
    };

    // Store in comptime context
    const pure_var_name = try astdb_system.str_interner.get("pure_func");
    try comptime_vm.context.setVariable(pure_var_name, pure_func_ref, true);

    // Test effect queries
    const retrieved_var = comptime_vm.context.getVariable(pure_var_name).?;
    const effect_set = ComptimeVM.ComptimeValue.EffectSet{ .effects = retrieved_var.value.function_ref.effects };

    try testing.expect(effect_set.isPure());
    try testing.expect(!effect_set.hasEffect(.io_fs_read));

    std.log.info("✅ Comptime meta-programming queries working", .{});

    // Get statistics
    const astdb_stats = astdb_system.getStats();
    const effect_stats = effect_system.getStats();
    const comptime_stats = comptime_vm.getStats();

    std.log.info("📊 North Star MVP Statistics:", .{});
    std.log.info("   - ASTDB interned strings: {}", .{astdb_stats.interned_strings});
    std.log.info("   - Effect system functions: {}", .{effect_stats.registered_functions});
    std.log.info("   - Comptime variables: {}", .{comptime_stats.variables_count});

    try testing.expect(astdb_stats.interned_strings > 0);
    try testing.expect(effect_stats.registered_functions >= 2);
    try testing.expect(comptime_stats.variables_count >= 1);

    std.log.info("🎉 NORTH STAR MVP SIMPLE INTEGRATION - SUCCESS!", .{});
}
