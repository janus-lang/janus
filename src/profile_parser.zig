// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// M3: Profile-Aware Parser Integration
// Demonstrates how the compiler pipeline integrates with the profile system

const std = @import("std");
const compat_fs = @import("compat_fs");
const profiles = @import("profiles.zig");
const profile_diagnostics = @import("profile_diagnostics.zig");

/// Profile-aware parser that validates syntax against current profile
pub const ProfileParser = struct {
    profile_config: profiles.ProfileConfig,
    error_reporter: profile_diagnostics.ErrorReporter,
    allocator: std.mem.Allocator,

    pub fn init(profile_config: profiles.ProfileConfig, allocator: std.mem.Allocator) ProfileParser {
        return ProfileParser{
            .profile_config = profile_config,
            .error_reporter = profile_diagnostics.ErrorReporter.init(profile_config, allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProfileParser) void {
        self.error_reporter.deinit();
    }

    /// Parse source code with profile-aware validation
    pub fn parseSource(self: *ProfileParser, source: []const u8, filename: []const u8) !ParseResult {
        std.debug.print("Parsing {s} with profile: {s}\n", .{ filename, self.profile_config.profile.toString() });

        var result = ParseResult{
            .ast = undefined, // Would be actual AST in real implementation
            .features_used = .{},
            .profile_violations = .{},
            .allocator = self.allocator,
        };

        // Simple syntax analysis (in real implementation, would use full lexer/parser)
        try self.analyzeProfileFeatures(source, filename, &result);

        return result;
    }

    /// Analyze source for profile-specific features and violations
    fn analyzeProfileFeatures(self: *ProfileParser, source: []const u8, filename: []const u8, result: *ParseResult) !void {
        var line_number: u32 = 1;
        var column: u32 = 1;
        var i: usize = 0;

        while (i < source.len) {
            // Track line/column for error reporting
            if (source[i] == '\n') {
                line_number += 1;
                column = 1;
            } else {
                column += 1;
            }

            // Check for Go-style syntax
            if (i + 2 < source.len and std.mem.startsWith(u8, source[i..], "go ")) {
                try self.checkFeatureUsage(.goroutines, "go statement", filename, line_number, column, result);
                i += 3;
                continue;
            }

            if (i + 4 < source.len and std.mem.startsWith(u8, source[i..], "chan")) {
                try self.checkFeatureUsage(.channels, "channel declaration", filename, line_number, column, result);
                i += 4;
                continue;
            }

            if (i + 6 < source.len and std.mem.startsWith(u8, source[i..], "select")) {
                try self.checkFeatureUsage(.channels, "select statement", filename, line_number, column, result);
                i += 6;
                continue;
            }

            // Check for context usage
            if (i + 3 < source.len and std.mem.startsWith(u8, source[i..], "ctx")) {
                try self.checkFeatureUsage(.context, "context parameter", filename, line_number, column, result);
                i += 3;
                continue;
            }

            // Check for full-profile features
            if (i + 6 < source.len and std.mem.startsWith(u8, source[i..], "effect")) {
                try self.checkFeatureUsage(.effects, "effect annotation", filename, line_number, column, result);
                i += 6;
                continue;
            }

            if (i + 10 < source.len and std.mem.startsWith(u8, source[i..], "capability")) {
                try self.checkFeatureUsage(.capabilities, "capability parameter", filename, line_number, column, result);
                i += 10;
                continue;
            }

            if (i + 5 < source.len and std.mem.startsWith(u8, source[i..], "actor")) {
                try self.checkFeatureUsage(.actors, "actor declaration", filename, line_number, column, result);
                i += 5;
                continue;
            }

            // Check for standard library tri-signature usage
            if (i + 7 < source.len and std.mem.startsWith(u8, source[i..], "std.go.")) {
                try self.checkFeatureUsage(.context, "std.go.* function", filename, line_number, column, result);
                i += 7;
                continue;
            }

            if (i + 9 < source.len and std.mem.startsWith(u8, source[i..], "std.full.")) {
                try self.checkFeatureUsage(.capabilities, "std.full.* function", filename, line_number, column, result);
                i += 9;
                continue;
            }

            i += 1;
        }
    }

    /// Check if a feature is available in current profile and record usage/violations
    fn checkFeatureUsage(self: *ProfileParser, feature: profiles.Feature, syntax: []const u8, filename: []const u8, line: u32, column: u32, result: *ParseResult) !void {
        // Record feature usage
        for (result.features_used.items) |used_feature| {
            if (used_feature == feature) return; // Already recorded
        }
        try result.features_used.append(result.allocator, feature);

        // Check if feature is available in current profile
        if (!self.profile_config.isFeatureAvailable(feature)) {
            // Record violation
            const violation = ProfileViolation{
                .feature = feature,
                .syntax = try self.allocator.dupe(u8, syntax),
                .filename = try self.allocator.dupe(u8, filename),
                .line = line,
                .column = column,
                .required_profile = feature.requiredProfile(),
            };
            try result.profile_violations.append(result.allocator, violation);

            // Report error
            const context = profile_diagnostics.ErrorContext{
                .feature = feature,
                .syntax = syntax,
                .source_file = filename,
                .line = line,
                .column = column,
            };
            try self.error_reporter.reportError(.feature_not_available, context);
        }
    }

    /// Get error reporter for displaying results
    pub fn getErrorReporter(self: *ProfileParser) *const profile_diagnostics.ErrorReporter {
        return &self.error_reporter;
    }
};

/// Result of profile-aware parsing
pub const ParseResult = struct {
    ast: void, // Would be actual AST in real implementation
    features_used: std.ArrayList(profiles.Feature),
    profile_violations: std.ArrayList(ProfileViolation),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParseResult) void {
        self.features_used.deinit(self.allocator);
        for (self.profile_violations.items) |*violation| {
            violation.deinit(self.allocator);
        }
        self.profile_violations.deinit(self.allocator);
    }

    /// Display parsing results
    pub fn displayResults(self: *const ParseResult, profile: profiles.Profile) void {
        std.debug.print("\n📊 Profile Analysis Results:\n", .{});
        std.debug.print("Current profile: {s}\n", .{profile.toString()});
        std.debug.print("Features detected: {}\n", .{self.features_used.items.len});
        std.debug.print("Profile violations: {}\n", .{self.profile_violations.items.len});

        if (self.features_used.items.len > 0) {
            std.debug.print("\n✅ Features used:\n", .{});
            for (self.features_used.items) |feature| {
                std.debug.print("  - {s}\n", .{@tagName(feature)});
            }
        }

        if (self.profile_violations.items.len > 0) {
            std.debug.print("\n⚠️  Profile violations:\n", .{});
            for (self.profile_violations.items) |violation| {
                std.debug.print("  - {s} at {s}:{}:{} (requires {s})\n", .{
                    violation.syntax,
                    violation.filename,
                    violation.line,
                    violation.column,
                    violation.required_profile.toString(),
                });
            }
        }
    }

    /// Check if parsing was successful (no violations)
    pub fn isSuccessful(self: *const ParseResult) bool {
        return self.profile_violations.items.len == 0;
    }

    /// Get upgrade suggestions based on violations
    pub fn getUpgradeSuggestions(self: *const ParseResult, allocator: std.mem.Allocator) ![][]const u8 {
        var suggestions = std.ArrayList([]const u8){};

        // Find the minimum profile that would resolve all violations
        var max_required_profile = profiles.Profile.min;
        for (self.profile_violations.items) |violation| {
            if (@intFromEnum(violation.required_profile) > @intFromEnum(max_required_profile)) {
                max_required_profile = violation.required_profile;
            }
        }

        if (max_required_profile != .min) {
            try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Upgrade to profile '{s}' to resolve all violations", .{max_required_profile.toString()}));

            try suggestions.append(allocator, try std.fmt.allocPrint(allocator, "Command: janus --profile={s} build your_file.jan", .{max_required_profile.toString()}));
        }

        return suggestions.toOwnedSlice(allocator);
    }
};

/// Profile violation information
pub const ProfileViolation = struct {
    feature: profiles.Feature,
    syntax: []const u8,
    filename: []const u8,
    line: u32,
    column: u32,
    required_profile: profiles.Profile,

    pub fn deinit(self: *ProfileViolation, allocator: std.mem.Allocator) void {
        allocator.free(self.syntax);
        allocator.free(self.filename);
    }
};

/// Profile-aware compilation pipeline
pub const ProfileCompiler = struct {
    profile_config: profiles.ProfileConfig,
    parser: ProfileParser,
    allocator: std.mem.Allocator,

    pub fn init(profile_config: profiles.ProfileConfig, allocator: std.mem.Allocator) ProfileCompiler {
        return ProfileCompiler{
            .profile_config = profile_config,
            .parser = ProfileParser.init(profile_config, allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProfileCompiler) void {
        self.parser.deinit();
    }

    /// Compile source with profile awareness
    pub fn compile(self: *ProfileCompiler, source: []const u8, filename: []const u8, output_path: []const u8) !CompilationResult {
        std.debug.print("🎯 Profile-Aware Compilation Pipeline\n", .{});
        std.debug.print("Profile: {s}\n", .{self.profile_config.profile.toString()});
        std.debug.print("Input: {s}\n", .{filename});
        std.debug.print("Output: {s}\n", .{output_path});

        // Phase 1: Profile-aware parsing
        std.debug.print("\n📝 Phase 1: Profile-aware parsing...\n", .{});
        var parse_result = try self.parser.parseSource(source, filename);
        defer parse_result.deinit();

        // Phase 2: Display parsing results
        parse_result.displayResults(self.profile_config.profile);

        // Phase 3: Check for violations
        if (!parse_result.isSuccessful()) {
            std.debug.print("\n🚨 Compilation failed due to profile violations\n", .{});
            self.parser.getErrorReporter().displayErrors();

            // Provide upgrade suggestions
            const suggestions = try parse_result.getUpgradeSuggestions(self.allocator);
            defer {
                for (suggestions) |suggestion| {
                    self.allocator.free(suggestion);
                }
                self.allocator.free(suggestions);
            }

            if (suggestions.len > 0) {
                std.debug.print("\n💡 Upgrade suggestions:\n", .{});
                for (suggestions, 0..) |suggestion, i| {
                    std.debug.print("  {}. {s}\n", .{ i + 1, suggestion });
                }
            }

            return CompilationResult{
                .success = false,
                .profile_used = self.profile_config.profile,
                .features_used = try self.allocator.dupe(profiles.Feature, parse_result.features_used.items),
                .violations_count = @intCast(parse_result.profile_violations.items.len),
                .output_path = try self.allocator.dupe(u8, output_path),
                .allocator = self.allocator,
            };
        }

        // Phase 4: Generate profile-aware code
        std.debug.print("\n🔧 Phase 2: Generating profile-aware code...\n", .{});
        try self.generateProfileAwareCode(source, output_path, &parse_result);

        std.debug.print("✅ Compilation successful!\n", .{});

        return CompilationResult{
            .success = true,
            .profile_used = self.profile_config.profile,
            .features_used = try self.allocator.dupe(profiles.Feature, parse_result.features_used.items),
            .violations_count = 0,
            .output_path = try self.allocator.dupe(u8, output_path),
            .allocator = self.allocator,
        };
    }

    /// Generate profile-aware executable code
    fn generateProfileAwareCode(self: *ProfileCompiler, source: []const u8, output_path: []const u8, parse_result: *const ParseResult) !void {
        _ = source; // TODO: Use actual source analysis

        // Generate profile-specific executable
        const features_list = blk: {
            var list = std.ArrayList(u8){};
            defer list.deinit(self.allocator);

            for (parse_result.features_used.items, 0..) |feature, i| {
                if (i > 0) try list.appendSlice(self.allocator, ", ");
                try list.appendSlice(self.allocator, @tagName(feature));
            }

            break :blk try list.toOwnedSlice(self.allocator);
        };
        defer self.allocator.free(features_list);

        const profile_info = switch (self.profile_config.profile) {
            .min => "Minimal feature set - simple and fast",
            .go => "Go-style patterns with structured concurrency",
            .full => "Complete Janus with capability security",
        };

        const executable_content = try std.fmt.allocPrint(self.allocator,
            \\#!/bin/bash
            \\echo "🎯 JANUS PROFILE-AWARE EXECUTABLE"
            \\echo "Profile: {s}"
            \\echo "Description: {s}"
            \\echo "Features used: {s}"
            \\echo ""
            \\echo "🚀 This executable was generated with profile-aware compilation!"
            \\echo "📦 Standard library functions automatically adapted to your profile"
            \\echo "🔧 Tri-signature pattern integration complete"
            \\echo ""
            \\echo "💡 Try different profiles to see how the same code adapts:"
            \\echo "   janus --profile=min build source.jan"
            \\echo "   janus --profile=go build source.jan"
            \\echo "   janus --profile=full build source.jan"
        , .{ self.profile_config.profile.toString(), profile_info, features_list });
        defer self.allocator.free(executable_content);

        // Write executable
        try compat_fs.writeFile(.{ .sub_path = output_path, .data = executable_content });

        // Make executable
        const file = try std.fs.cwd().openFile(output_path, .{});
        defer file.close();

        if (std.builtin.os.tag != .windows) {
            try file.chmod(0o755);
        }
    }
};

/// Result of profile-aware compilation
pub const CompilationResult = struct {
    success: bool,
    profile_used: profiles.Profile,
    features_used: []profiles.Feature,
    violations_count: u32,
    output_path: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CompilationResult) void {
        self.allocator.free(self.features_used);
        self.allocator.free(self.output_path);
    }

    pub fn displaySummary(self: *const CompilationResult) void {
        std.debug.print("\n📊 Compilation Summary:\n", .{});
        std.debug.print("Success: {}\n", .{self.success});
        std.debug.print("Profile: {s}\n", .{self.profile_used.toString()});
        std.debug.print("Features used: {}\n", .{self.features_used.len});
        std.debug.print("Violations: {}\n", .{self.violations_count});
        std.debug.print("Output: {s}\n", .{self.output_path});

        if (self.features_used.len > 0) {
            std.debug.print("Feature list: ", .{});
            for (self.features_used, 0..) |feature, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{@tagName(feature)});
            }
            std.debug.print("\n", .{});
        }
    }
};

// =============================================================================
// TESTS: Profile-aware parser and compiler
// =============================================================================

test "profile parser feature detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const profile_config = profiles.ProfileConfig.init(.min);
    var parser = ProfileParser.init(profile_config, allocator);
    defer parser.deinit();

    const source =
        \\func main() {
        \\    go doWork()
        \\    ch := make(chan int)
        \\    std.go.readFile("/test.txt", ctx, allocator)
        \\}
    ;

    var result = try parser.parseSource(source, "test.jan");
    defer result.deinit();

    // Should detect goroutines and channels
    try testing.expect(result.features_used.items.len >= 2);
    try testing.expect(result.profile_violations.items.len >= 2); // Both require higher profiles
}

test "profile compiler integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test with go profile
    const profile_config = profiles.ProfileConfig.init(.go);
    var compiler = ProfileCompiler.init(profile_config, allocator);
    defer compiler.deinit();

    const source =
        \\func main() {
        \\    go doWork()
        \\    std.go.readFile("/test.txt", ctx, allocator)
        \\}
    ;

    var result = try compiler.compile(source, "test.jan", "test_output");
    defer result.deinit();

    try testing.expect(result.success); // Should succeed in go profile
    try testing.expect(result.violations_count == 0);
    try testing.expect(result.features_used.len > 0);

    // Clean up test output
    compat_fs.deleteFile("test_output") catch {};
}

test "profile upgrade suggestions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const profile_config = profiles.ProfileConfig.init(.min);
    var parser = ProfileParser.init(profile_config, allocator);
    defer parser.deinit();

    const source = "capability fs_cap = FileSystem.init()";

    var result = try parser.parseSource(source, "test.jan");
    defer result.deinit();

    const suggestions = try result.getUpgradeSuggestions(allocator);
    defer {
        for (suggestions) |suggestion| {
            allocator.free(suggestion);
        }
        allocator.free(suggestions);
    }

    try testing.expect(suggestions.len > 0);
    try testing.expect(std.mem.indexOf(u8, suggestions[0], "full") != null);
}
