// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Golden tests for profile detection and feature gating
const std = @import("std");
const testing = std.testing;
const profiles = @import("../../src/profiles.zig");

test "profile detection from command line arguments" {
    // Test --profile=min
    {
        const args = [_][]const u8{ "janus", "--profile=min", "build", "test.jan" };
        const detected = profiles.ProfileDetector.detectProfile(&args);
        try testing.expect(detected == .core);
    }

    // Test --profile go (space separated)
    {
        const args = [_][]const u8{ "janus", "--profile", "go", "build", "test.jan" };
        const detected = profiles.ProfileDetector.detectProfile(&args);
        try testing.expect(detected == .service);
    }

    // Test --profile=full
    {
        const args = [_][]const u8{ "janus", "--profile=full", "build", "test.jan" };
        const detected = profiles.ProfileDetector.detectProfile(&args);
        try testing.expect(detected == .sovereign);
    }

    // Test default (no profile specified)
    {
        const args = [_][]const u8{ "janus", "build", "test.jan" };
        const detected = profiles.ProfileDetector.detectProfile(&args);
        try testing.expect(detected == .core);
    }

    // Test invalid profile (should default to min)
    {
        const args = [_][]const u8{ "janus", "--profile=invalid", "build", "test.jan" };
        const detected = profiles.ProfileDetector.detectProfile(&args);
        try testing.expect(detected == .core);
    }
}

test "feature availability by profile" {
    // Test :min profile features
    {
        const config = profiles.ProfileConfig.init(.core);

        // Basic features should be available
        try testing.expect(config.isFeatureAvailable(.basic_types));
        try testing.expect(config.isFeatureAvailable(.functions));
        try testing.expect(config.isFeatureAvailable(.control_flow));

        // Advanced features should not be available
        try testing.expect(!config.isFeatureAvailable(.serviceroutines));
        try testing.expect(!config.isFeatureAvailable(.channels));
        try testing.expect(!config.isFeatureAvailable(.effects));
        try testing.expect(!config.isFeatureAvailable(.actors));
    }

    // Test :go profile features
    {
        const config = profiles.ProfileConfig.init(.service);

        // Basic features should be available
        try testing.expect(config.isFeatureAvailable(.basic_types));
        try testing.expect(config.isFeatureAvailable(.functions));
        try testing.expect(config.isFeatureAvailable(.control_flow));

        // Go-style features should be available
        try testing.expect(config.isFeatureAvailable(.serviceroutines));
        try testing.expect(config.isFeatureAvailable(.channels));
        try testing.expect(config.isFeatureAvailable(.context));
        try testing.expect(config.isFeatureAvailable(.error_handling));

        // Full features should not be available
        try testing.expect(!config.isFeatureAvailable(.effects));
        try testing.expect(!config.isFeatureAvailable(.actors));
        try testing.expect(!config.isFeatureAvailable(.comptime));
    }

    // Test :full profile features
    {
        const config = profiles.ProfileConfig.init(.sovereign);

        // All features should be available
        try testing.expect(config.isFeatureAvailable(.basic_types));
        try testing.expect(config.isFeatureAvailable(.functions));
        try testing.expect(config.isFeatureAvailable(.serviceroutines));
        try testing.expect(config.isFeatureAvailable(.effects));
        try testing.expect(config.isFeatureAvailable(.actors));
        try testing.expect(config.isFeatureAvailable(.comptime));
        try testing.expect(config.isFeatureAvailable(.multiple_dispatch));
    }
}

test "upgrade hints for unavailable features" {
    // Test :min profile upgrade hints
    {
        const config = profiles.ProfileConfig.init(.core);

        // Should get hint for goroutines
        const hint = config.getUpgradeHint(.serviceroutines);
        try testing.expect(hint != null);
        try testing.expect(std.mem.indexOf(u8, hint.?, "go") != null);

        // Should get hint for effects
        const effects_hint = config.getUpgradeHint(.effects);
        try testing.expect(effects_hint != null);
        try testing.expect(std.mem.indexOf(u8, effects_hint.?, "full") != null);

        // Should not get hint for available features
        const basic_hint = config.getUpgradeHint(.basic_types);
        try testing.expect(basic_hint == null);
    }

    // Test :go profile upgrade hints
    {
        const config = profiles.ProfileConfig.init(.service);

        // Should not get hint for available features
        const goroutines_hint = config.getUpgradeHint(.serviceroutines);
        try testing.expect(goroutines_hint == null);

        // Should get hint for full-only features
        const effects_hint = config.getUpgradeHint(.effects);
        try testing.expect(effects_hint != null);
        try testing.expect(std.mem.indexOf(u8, effects_hint.?, "full") != null);
    }
}

test "profile error handling" {
    const config = profiles.ProfileConfig.init(.core);

    // Should succeed for available features
    try config.checkFeature(.basic_types);

    // Should fail for unavailable features
    try testing.expectError(profiles.ProfileError.FeatureNotAvailable, config.checkFeature(.serviceroutines));
    try testing.expectError(profiles.ProfileError.FeatureNotAvailable, config.checkFeature(.effects));
}

test "profile string conversion" {
    // Test toString
    try testing.expectEqualStrings("min", profiles.Profile.core.toString());
    try testing.expectEqualStrings("go", profiles.Profile.service.toString());
    try testing.expectEqualStrings("full", profiles.Profile.sovereign.toString());

    // Test fromString
    try testing.expect(profiles.Profile.fromString("min") == .core);
    try testing.expect(profiles.Profile.fromString("go") == .service);
    try testing.expect(profiles.Profile.fromString("full") == .sovereign);
    try testing.expect(profiles.Profile.fromString("invalid") == null);
}

test "profile descriptions" {
    // Test that descriptions are non-empty and contain key terms
    const min_desc = profiles.Profile.core.description();
    try testing.expect(min_desc.len > 0);
    try testing.expect(std.mem.indexOf(u8, min_desc, "6 types") != null);

    const go_desc = profiles.Profile.service.description();
    try testing.expect(go_desc.len > 0);
    try testing.expect(std.mem.indexOf(u8, go_desc, "Go") != null);

    const full_desc = profiles.Profile.sovereign.description();
    try testing.expect(full_desc.len > 0);
    try testing.expect(std.mem.indexOf(u8, full_desc, "Complete") != null);
}
