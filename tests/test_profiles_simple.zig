// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const profiles = @import("src/profiles.zig");

pub fn main() !void {
    std.debug.print("Testing Janus Profile System...\n", .{});

    // Test profile detection
    const args = [_][]const u8{ "janus", "--profile=go", "build", "test.jan" };
    const detected = profiles.ProfileDetector.detectProfile(&args);
    std.debug.print("Detected profile: {s}\n", .{detected.toString()});

    // Test feature availability
    const config = profiles.ProfileConfig.init(.service);
    std.debug.print("Go profile has goroutines: {}\n", .{config.isFeatureAvailable(.serviceroutines)});
    std.debug.print("Go profile has effects: {}\n", .{config.isFeatureAvailable(.effects)});

    // Test upgrade hints
    const min_config = profiles.ProfileConfig.init(.core);
    if (min_config.getUpgradeHint(.serviceroutines)) |hint| {
        std.debug.print("Upgrade hint for goroutines: {s}\n", .{hint});
    }

    std.debug.print("Profile system test complete!\n", .{});
}
