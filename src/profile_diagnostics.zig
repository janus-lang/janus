// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// M3: Profile-Aware Diagnostic System
// Provides profile-specific error messages, upgrade hints, and feature guidance

const std = @import("std");
const profiles = @import("profiles.zig");

/// Profile-aware diagnostic engine
pub const ProfileDiagnostics = struct {
    profile_config: profiles.ProfileConfig,
    allocator: std.mem.Allocator,

    pub fn init(profile_config: profiles.ProfileConfig, allocator: std.mem.Allocator) ProfileDiagnostics {
        return ProfileDiagnostics{
            .profile_config = profile_config,
            .allocator = allocator,
        };
    }

    /// Generate profile-aware error message
    pub fn generateError(self: *ProfileDiagnostics, error_type: ErrorType, context: ErrorContext) !ProfileError {
        return ProfileError{
            .error_type = error_type,
            .context = context,
            .current_profile = self.profile_config.profile,
            .message = try self.formatErrorMessage(error_type, context),
            .upgrade_hint = self.generateUpgradeHint(error_type, context),
            .fix_suggestions = try self.generateFixSuggestions(error_type, context),
            .allocator = self.allocator,
        };
    }

    /// Format error message based on profile and context
    fn formatErrorMessage(self: *ProfileDiagnostics, error_type: ErrorType, context: ErrorContext) ![]u8 {
        return switch (error_type) {
            .feature_not_available => try std.fmt.allocPrint(self.allocator, "Feature '{s}' is not available in profile '{s}'", .{ @tagName(context.feature.?), self.profile_config.profile.toString() }),
            .syntax_not_supported => try std.fmt.allocPrint(self.allocator, "Syntax '{s}' requires profile '{s}' or higher", .{ context.syntax.?, context.feature.?.requiredProfile().toString() }),
            .capability_required => try std.fmt.allocPrint(self.allocator, "Operation requires capability '{s}' (available in :full profile)", .{context.capability_name.?}),
            .context_required => try std.fmt.allocPrint(self.allocator, "Operation requires context parameter (available in :go+ profiles)"),
            .effect_tracking_required => try std.fmt.allocPrint(self.allocator, "Effect tracking required for this operation (available in :full profile)"),
        };
    }

    /// Generate upgrade hint for the error
    fn generateUpgradeHint(self: *ProfileDiagnostics, error_type: ErrorType, context: ErrorContext) ?[]const u8 {
        return switch (error_type) {
            .feature_not_available => if (context.feature) |feature|
                self.profile_config.getUpgradeHint(feature)
            else
                null,
            .syntax_not_supported => if (context.feature) |feature|
                self.profile_config.getUpgradeHint(feature)
            else
                null,
            .capability_required => switch (self.profile_config.profile) {
                .min, .go => "Try: janus --profile=full build your_file.jan",
                .full => null,
            },
            .context_required => switch (self.profile_config.profile) {
                .min => "Try: janus --profile=go build your_file.jan",
                .go, .full => null,
            },
            .effect_tracking_required => switch (self.profile_config.profile) {
                .min, .go => "Try: janus --profile=full build your_file.jan",
                .full => null,
            },
        };
    }

    /// Generate fix suggestions for the error
    fn generateFixSuggestions(self: *ProfileDiagnostics, error_type: ErrorType, context: ErrorContext) ![][]const u8 {
        var suggestions = std.ArrayList([]const u8){};

        switch (error_type) {
            .feature_not_available => {
                if (context.feature) |feature| {
                    const required_profile = feature.requiredProfile();
                    try suggestions.append(self.allocator, try std.fmt.allocPrint(self.allocator, "Upgrade to profile '{s}' to use this feature", .{required_profile.toString()}));

                    if (required_profile == .go and self.profile_config.profile == .min) {
                        try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Add context parameter to function calls"));
                        try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Use structured concurrency patterns"));
                    } else if (required_profile == .full) {
                        try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Add capability parameters to function calls"));
                        try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Use effect annotations on functions"));
                    }
                }
            },
            .syntax_not_supported => {
                try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Use profile-compatible syntax alternatives"));
                if (context.alternative_syntax) |alt| {
                    try suggestions.append(self.allocator, try std.fmt.allocPrint(self.allocator, "Try using: {s}", .{alt}));
                }
            },
            .capability_required => {
                try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Add capability parameter to function signature"));
                try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Use std.full.* functions for capability-gated operations"));
            },
            .context_required => {
                try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Add context parameter to function signature"));
                try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Use std.go.* functions for context-aware operations"));
            },
            .effect_tracking_required => {
                try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Add effect annotations to function signature"));
                try suggestions.append(self.allocator, try self.allocator.dupe(u8, "Use capability-based I/O operations"));
            },
        }

        return suggestions.toOwnedSlice(self.allocator);
    }
};

/// Types of profile-aware errors
pub const ErrorType = enum {
    feature_not_available,
    syntax_not_supported,
    capability_required,
    context_required,
    effect_tracking_required,
};

/// Context information for error generation
pub const ErrorContext = struct {
    feature: ?profiles.Feature = null,
    syntax: ?[]const u8 = null,
    capability_name: ?[]const u8 = null,
    alternative_syntax: ?[]const u8 = null,
    line: ?u32 = null,
    column: ?u32 = null,
    source_file: ?[]const u8 = null,
};

/// Profile-aware error with upgrade hints and fix suggestions
pub const ProfileError = struct {
    error_type: ErrorType,
    context: ErrorContext,
    current_profile: profiles.Profile,
    message: []u8,
    upgrade_hint: ?[]const u8,
    fix_suggestions: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ProfileError) void {
        self.allocator.free(self.message);
        for (self.fix_suggestions) |suggestion| {
            self.allocator.free(suggestion);
        }
        self.allocator.free(self.fix_suggestions);
    }

    /// Display the error with all context and suggestions
    pub fn display(self: *const ProfileError) void {
        std.debug.print("Error: {s}\n", .{self.message});
        std.debug.print("Current profile: {s}\n", .{self.current_profile.toString()});

        if (self.context.source_file) |file| {
            if (self.context.line) |line| {
                if (self.context.column) |column| {
                    std.debug.print("Location: {s}:{}:{}\n", .{ file, line, column });
                } else {
                    std.debug.print("Location: {s}:{}\n", .{ file, line });
                }
            } else {
                std.debug.print("File: {s}\n", .{file});
            }
        }

        if (self.upgrade_hint) |hint| {
            std.debug.print("\n💡 Upgrade hint: {s}\n", .{hint});
        }

        if (self.fix_suggestions.len > 0) {
            std.debug.print("\n🔧 Fix suggestions:\n", .{});
            for (self.fix_suggestions, 0..) |suggestion, i| {
                std.debug.print("  {}. {s}\n", .{ i + 1, suggestion });
            }
        }

        // Show profile progression path
        std.debug.print("\n📈 Profile progression:\n", .{});
        std.debug.print("  :min  → Simple, familiar APIs\n", .{});
        std.debug.print("  :go   → Add structured concurrency\n", .{});
        std.debug.print("  :full → Complete capability security\n", .{});
    }

    /// Get error code for this profile error
    pub fn getErrorCode(self: *const ProfileError) u16 {
        return switch (self.error_type) {
            .feature_not_available => switch (self.current_profile) {
                .min => 2001, // E2001
                .go => 2501, // E2501
                .full => 3001, // E3001 (shouldn't happen)
            },
            .syntax_not_supported => switch (self.current_profile) {
                .min => 2002, // E2002
                .go => 2502, // E2502
                .full => 3002, // E3002
            },
            .capability_required => 3003, // E3003
            .context_required => 2503, // E2503
            .effect_tracking_required => 3004, // E3004
        };
    }
};

/// Profile-aware error reporting utilities
pub const ErrorReporter = struct {
    diagnostics: ProfileDiagnostics,
    errors: std.ArrayList(ProfileError),

    pub fn init(profile_config: profiles.ProfileConfig, allocator: std.mem.Allocator) ErrorReporter {
        return ErrorReporter{
            .diagnostics = ProfileDiagnostics.init(profile_config, allocator),
            .errors = .{},
        };
    }

    pub fn deinit(self: *ErrorReporter) void {
        for (self.errors.items) |*error_item| {
            error_item.deinit();
        }
        self.errors.deinit(self.diagnostics.allocator);
    }

    /// Report a profile-aware error
    pub fn reportError(self: *ErrorReporter, error_type: ErrorType, context: ErrorContext) !void {
        const profile_error = try self.diagnostics.generateError(error_type, context);
        try self.errors.append(self.diagnostics.allocator, profile_error);
    }

    /// Display all accumulated errors
    pub fn displayErrors(self: *const ErrorReporter) void {
        if (self.errors.items.len == 0) {
            std.debug.print("✅ No profile compatibility issues found\n", .{});
            return;
        }

        std.debug.print("🚨 Profile Compatibility Issues ({} found):\n\n", .{self.errors.items.len});

        for (self.errors.items, 0..) |*error_item, i| {
            std.debug.print("--- Error {} (E{}) ---\n", .{ i + 1, error_item.getErrorCode() });
            error_item.display();
            std.debug.print("\n", .{});
        }

        // Summary
        std.debug.print("📊 Summary:\n", .{});
        std.debug.print("  Total errors: {}\n", .{self.errors.items.len});
        std.debug.print("  Current profile: {s}\n", .{self.diagnostics.profile_config.profile.toString()});

        // Count upgrade suggestions
        var upgrade_count: u32 = 0;
        for (self.errors.items) |*error_item| {
            if (error_item.upgrade_hint != null) upgrade_count += 1;
        }

        if (upgrade_count > 0) {
            std.debug.print("  Errors fixable by profile upgrade: {}\n", .{upgrade_count});
        }
    }

    /// Check if there are any errors
    pub fn hasErrors(self: *const ErrorReporter) bool {
        return self.errors.items.len > 0;
    }

    /// Get count of errors by type
    pub fn getErrorCount(self: *const ErrorReporter, error_type: ErrorType) u32 {
        var count: u32 = 0;
        for (self.errors.items) |*error_item| {
            if (error_item.error_type == error_type) count += 1;
        }
        return count;
    }
};

// =============================================================================
// TESTS: Profile-aware diagnostic system
// =============================================================================

test "profile error generation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const profile_config = profiles.ProfileConfig.init(.min);
    var diagnostics = ProfileDiagnostics.init(profile_config, allocator);

    // Test feature not available error
    const context = ErrorContext{
        .feature = .goroutines,
        .syntax = "go func() { ... }",
        .source_file = "test.jan",
        .line = 10,
        .column = 5,
    };

    var error_item = try diagnostics.generateError(.feature_not_available, context);
    defer error_item.deinit();

    try testing.expect(std.mem.indexOf(u8, error_item.message, "goroutines") != null);
    try testing.expect(std.mem.indexOf(u8, error_item.message, "min") != null);
    try testing.expect(error_item.upgrade_hint != null);
    try testing.expect(error_item.fix_suggestions.len > 0);
}

test "error reporter functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const profile_config = profiles.ProfileConfig.init(.min);
    var reporter = ErrorReporter.init(profile_config, allocator);
    defer reporter.deinit();

    // Report multiple errors
    try reporter.reportError(.feature_not_available, ErrorContext{ .feature = .goroutines });
    try reporter.reportError(.capability_required, ErrorContext{ .capability_name = "fs.read" });

    try testing.expect(reporter.hasErrors());
    try testing.expect(reporter.errors.items.len == 2);
    try testing.expect(reporter.getErrorCount(.feature_not_available) == 1);
    try testing.expect(reporter.getErrorCount(.capability_required) == 1);
}

test "profile progression suggestions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test min profile
    {
        const profile_config = profiles.ProfileConfig.init(.min);
        var diagnostics = ProfileDiagnostics.init(profile_config, allocator);

        var error_item = try diagnostics.generateError(.feature_not_available, ErrorContext{ .feature = .goroutines });
        defer error_item.deinit();

        try testing.expect(error_item.upgrade_hint != null);
        try testing.expect(std.mem.indexOf(u8, error_item.upgrade_hint.?, "go") != null);
    }

    // Test go profile
    {
        const profile_config = profiles.ProfileConfig.init(.go);
        var diagnostics = ProfileDiagnostics.init(profile_config, allocator);

        var error_item = try diagnostics.generateError(.capability_required, ErrorContext{ .capability_name = "net.http" });
        defer error_item.deinit();

        try testing.expect(error_item.upgrade_hint != null);
        try testing.expect(std.mem.indexOf(u8, error_item.upgrade_hint.?, "full") != null);
    }
}
