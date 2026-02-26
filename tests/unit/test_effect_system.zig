// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    // Import effect system
    const EffectSystem = @import("compiler/effect_system.zig");
    const EffectType = EffectSystem.EffectType;
    const CapabilityType = EffectSystem.CapabilityType;


    // Test effect types
    const pure_effect = EffectType.fromString("pure");
    const fs_read_effect = EffectType.fromString("io.fs.read");


    // Test capability types
    const fs_read_cap = CapabilityType.fromString("CapFsRead");
    const net_write_cap = CapabilityType.fromString("CapNetWrite");


    // Test capability requirements
    if (fs_read_cap) |cap| {
        if (fs_read_effect) |effect| {
            const required = cap.isRequiredFor(effect);
        }
    }

    // Test effect sets
    var effect_set = EffectSystem.EffectSet.init(allocator);
    defer effect_set.deinit();

    try effect_set.addEffect(.io_fs_read);
    try effect_set.addEffect(.io_stdout);

    const has_fs_read = effect_set.hasEffect(.io_fs_read);
    const is_pure = effect_set.isPure();


    // Test capability sets
    var cap_set = EffectSystem.CapabilitySet.init(allocator);
    defer cap_set.deinit();

    try cap_set.addCapability(.cap_fs_read);
    try cap_set.addCapability(.cap_stdout);

    const has_fs_cap = cap_set.hasCapability(.cap_fs_read);
    const satisfies = cap_set.satisfiesEffects(&effect_set);




}
