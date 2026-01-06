// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Profile System - M1 Implementation
// Provides feature gating and progressive complexity management

const std = @import("std");

/// Janus language profiles - progressive complexity levels
pub const Profile = enum {
    min, // Minimal feature set - learning and simple scripts
    go, // Go-style patterns - backend development
    full, // Complete Janus - systems programming
    npu, // NPU-native ML profile (orthogonal to resilience profiles)

    pub fn fromString(str: []const u8) ?Profile {
        if (std.mem.eql(u8, str, "min")) return .min;
        if (std.mem.eql(u8, str, "go")) return .go;
        if (std.mem.eql(u8, str, "full")) return .full;
        if (std.mem.eql(u8, str, "npu")) return .npu;
        return null;
    }

    pub fn toString(self: Profile) []const u8 {
        return switch (self) {
            .min => "min",
            .go => "go",
            .full => "full",
            .npu => "npu",
        };
    }

    pub fn description(self: Profile) []const u8 {
        return switch (self) {
            .min => "Minimal feature set - 6 types, 8 constructs, 12 operators",
            .go => "Go-familiar patterns + Janus syntax power",
            .full => "Complete Janus arsenal - effects, actors, comptime magic",
            .npu => "NPU-native AI/ML features: tensors, graph IR, streams/events",
        };
    }
};

/// Feature categories that can be gated by profile
pub const Feature = enum {
    // Core language features
    basic_types, // Available in all profiles
    functions, // Available in all profiles
    control_flow, // Available in all profiles

    // Go-style features (available in :go+)
    goroutines,
    channels,
    context,
    error_handling,

    // Full features (available in :full only)
    effects,
    capabilities,
    actors,
    comptime_magic,
    multiple_dispatch,

    pub fn availableInProfile(self: Feature, profile: Profile) bool {
        return switch (self) {
            // Always available
            .basic_types, .functions, .control_flow => true,

            // Available in :go and :full
            .goroutines, .channels, .context, .error_handling => switch (profile) {
                .min => false,
                .go, .full => true,
                .npu => false,
            },

            // Available in :full only
            .effects, .capabilities, .actors, .comptime_magic, .multiple_dispatch => switch (profile) {
                .min, .go, .npu => false,
                .full => true,
            },
        };
    }

    pub fn requiredProfile(self: Feature) Profile {
        return switch (self) {
            .basic_types, .functions, .control_flow => .min,
            .goroutines, .channels, .context, .error_handling => .go,
            .effects, .capabilities, .actors, .comptime_magic, .multiple_dispatch => .full,
        };
    }
};

/// Profile configuration and feature gating
pub const ProfileConfig = struct {
    profile: Profile,

    pub fn init(profile: Profile) ProfileConfig {
        return ProfileConfig{ .profile = profile };
    }

    pub fn isFeatureAvailable(self: ProfileConfig, feature: Feature) bool {
        return feature.availableInProfile(self.profile);
    }

    pub fn checkFeature(self: ProfileConfig, feature: Feature) ProfileError!void {
        if (!self.isFeatureAvailable(feature)) {
            return ProfileError.FeatureNotAvailable;
        }
    }

    pub fn getUpgradeHint(self: ProfileConfig, feature: Feature) ?[]const u8 {
        if (self.isFeatureAvailable(feature)) return null;

        const required = feature.requiredProfile();
        return switch (required) {
            .min => null, // Should never happen
            .go => "This feature requires --profile=go or higher",
            .full => "This feature requires --profile=full",
            .npu => null, // orthogonal AI profile; not a progression hint
        };
    }
};

pub const ProfileError = error{
    FeatureNotAvailable,
    InvalidProfile,
};

/// Profile detection from CLI args and environment
pub const ProfileDetector = struct {
    pub fn detectProfile(args: [][]const u8) Profile {
        // Check for --profile flag
        for (args, 0..) |arg, i| {
            if (std.mem.startsWith(u8, arg, "--profile=")) {
                const profile_str = arg[10..];
                if (Profile.fromString(profile_str)) |profile| {
                    return profile;
                }
            } else if (std.mem.eql(u8, arg, "--profile") and i + 1 < args.len) {
                if (Profile.fromString(args[i + 1])) |profile| {
                    return profile;
                }
            }
        }

        // Check environment variable
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "JANUS_PROFILE")) |env_profile| {
            defer std.heap.page_allocator.free(env_profile);
            if (Profile.fromString(env_profile)) |profile| {
                return profile;
            }
        } else |_| {}

        // Default to min profile for safety
        return .min;
    }
};

/// Error codes for profile-aware diagnostics
pub const ProfileDiagnostic = struct {
    pub const ErrorCode = enum(u16) {
        // E20xx - :min profile errors
        E2001, // Feature requires higher profile
        E2002, // Syntax not available in min profile

        // E25xx - :go profile errors
        E2501, // Feature requires :full profile
        E2502, // Actor syntax in :go profile

        // E30xx - :full profile errors
        E3001, // Invalid capability syntax
        E3002, // Effect system violation
    };

    pub fn formatError(code: ErrorCode, feature: Feature, current_profile: Profile) []const u8 {
        _ = feature; // TODO: Use feature in error messages
        _ = current_profile; // TODO: Use current_profile in error messages
        return switch (code) {
            .E2001 => "Feature not available in current profile",
            .E2002 => "Syntax requires higher profile",
            .E2501 => "Feature requires :full profile",
            .E2502 => "Actor syntax not available in :go profile",
            .E3001 => "Invalid capability syntax",
            .E3002 => "Effect system violation",
        };
    }

    pub fn getUpgradeHint(feature: Feature, current_profile: Profile) []const u8 {
        const required = feature.requiredProfile();
        return switch (required) {
            .min => "No upgrade needed",
            .go => switch (current_profile) {
                .min => "Try: janus --profile=go build your_file.jan",
                .go, .full => "Feature should be available",
            },
            .full => switch (current_profile) {
                .min => "Try: janus --profile=full build your_file.jan",
                .go => "Try: janus --profile=full build your_file.jan",
                .full => "Feature should be available",
            },
        };
    }
};

// Tests
test "profile detection from args" {
    const testing = std.testing;

    // Test --profile=min
    const args1 = [_][]const u8{ "janus", "--profile=min", "build", "test.jan" };
    try testing.expect(ProfileDetector.detectProfile(&args1) == .min);

    // Test --profile go
    const args2 = [_][]const u8{ "janus", "--profile", "go", "build", "test.jan" };
    try testing.expect(ProfileDetector.detectProfile(&args2) == .go);

    // Test default
    const args3 = [_][]const u8{ "janus", "build", "test.jan" };
    try testing.expect(ProfileDetector.detectProfile(&args3) == .min);
}

test "feature availability" {
    const testing = std.testing;

    // Test min profile
    const min_config = ProfileConfig.init(.min);
    try testing.expect(min_config.isFeatureAvailable(.basic_types));
    try testing.expect(!min_config.isFeatureAvailable(.goroutines));
    try testing.expect(!min_config.isFeatureAvailable(.effects));

    // Test go profile
    const go_config = ProfileConfig.init(.go);
    try testing.expect(go_config.isFeatureAvailable(.basic_types));
    try testing.expect(go_config.isFeatureAvailable(.goroutines));
    try testing.expect(!go_config.isFeatureAvailable(.effects));

    // Test full profile
    const full_config = ProfileConfig.init(.full);
    try testing.expect(full_config.isFeatureAvailable(.basic_types));
    try testing.expect(full_config.isFeatureAvailable(.goroutines));
    try testing.expect(full_config.isFeatureAvailable(.effects));
}

test "upgrade hints" {
    const testing = std.testing;

    const min_config = ProfileConfig.init(.min);
    const hint = min_config.getUpgradeHint(.goroutines);
    try testing.expect(hint != null);
    try testing.expect(std.mem.indexOf(u8, hint.?, "go") != null);
}
