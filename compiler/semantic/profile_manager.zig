// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Profile Management System
//!
//! This module provides comprehensive language profile management for Janus's
//! progressive disclosure model, enforcing feature constraints and providing
//! profile-aware validation capabilities.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;

const TypeSystem = @import("type_system.zig").TypeSystem;
const TypeId = @import("type_system.zig").TypeId;
const PrimitiveType = @import("type_system.zig").PrimitiveType;
const source_span_utils = @import("source_span_utils.zig");
const SourceSpan = source_span_utils.SourceSpan;

/// Language profiles for progressive disclosure
pub const LanguageProfile = enum {
    core, // Foundational subset (formerly :min)
    service, // HTTP, crypto, IO (formerly :go)
    cluster, // Distributed systems (formerly :elixir)
    compute, // HPC, tensors, NPU
    sovereign, // Full capability (formerly :full)

    /// Get human-readable profile name
    pub fn getName(self: LanguageProfile) []const u8 {
        return switch (self) {
            .core => "Core",
            .service => "Service",
            .cluster => "Cluster",
            .compute => "Compute",
            .sovereign => "Sovereign",
        };
    }

    /// Resolve an alias or name to a canonical profile
    pub fn resolve(name: []const u8) ?LanguageProfile {
        if (std.mem.eql(u8, name, "core") or std.mem.eql(u8, name, "min")) return .core;
        if (std.mem.eql(u8, name, "service") or std.mem.eql(u8, name, "go")) return .service;
        if (std.mem.eql(u8, name, "cluster") or std.mem.eql(u8, name, "elixir") or std.mem.eql(u8, name, "actor")) return .cluster;
        if (std.mem.eql(u8, name, "compute") or std.mem.eql(u8, name, "npu") or std.mem.eql(u8, name, "tensor")) return .compute;
        if (std.mem.eql(u8, name, "sovereign") or std.mem.eql(u8, name, "full")) return .sovereign;
        return null;
    }

    /// Get profile description
    pub fn getDescription(self: LanguageProfile) []const u8 {
        return switch (self) {
            .core => "Foundational subset with basic types and deterministic control flow",
            .service => "Service-oriented features with I/O, error-as-values, and networking",
            .cluster => "Distributed systems with actors, pattern matching, and supervision",
            .compute => "High-performance computing with tensor operations and NPU acceleration",
            .sovereign => "Complete language feature set with full effect tracking and sovereign control",
        };
    }

    /// Check if this profile is a subset of another
    pub fn isSubsetOf(self: LanguageProfile, other: LanguageProfile) bool {
        const self_level = @intFromEnum(self);
        const other_level = @intFromEnum(other);
        return self_level <= other_level;
    }
};

/// Language features with detailed categorization
pub const LanguageFeature = enum {
    // Core features (available in all profiles)
    basic_types,
    functions,
    variables,
    control_flow,

    // Go-style features
    error_handling,
    simple_concurrency,
    interfaces,

    // Elixir-style features
    pattern_matching,
    actor_model,
    supervision_trees,
    message_passing,

    // Full features
    effects_system,
    advanced_metaprogramming,
    comptime_execution,
    capability_system,

    /// Get feature category
    pub fn getCategory(self: LanguageFeature) FeatureCategory {
        return switch (self) {
            .basic_types, .functions, .variables, .control_flow => .core,
            .error_handling, .simple_concurrency, .interfaces => .service_style,
            .pattern_matching, .actor_model, .supervision_trees, .message_passing => .cluster_style,
            .effects_system, .advanced_metaprogramming, .comptime_execution, .capability_system => .sovereign_featured,
        };
    }

    /// Get minimum profile required for this feature
    pub fn getMinimumProfile(self: LanguageFeature) LanguageProfile {
        return switch (self.getCategory()) {
            .core => .core,
            .service_style => .service,
            .cluster_style => .cluster,
            .sovereign_featured => .sovereign,
        };
    }
};

/// Feature categories for organization
pub const FeatureCategory = enum {
    core,
    service_style,
    cluster_style,
    sovereign_featured,
};

/// Operator categories with profile restrictions
pub const OperatorCategory = enum {
    arithmetic, // +, -, *, /, %
    comparison, // ==, !=, <, >, <=, >=
    logical, // &&, ||, !
    bitwise, // &, |, ^, <<, >>
    assignment, // =, +=, -=, etc.
    pattern_match, // match operator (elixir+ only)
    effect, // effect operators (full only)

    /// Get minimum profile for operator category
    pub fn getMinimumProfile(self: OperatorCategory) LanguageProfile {
        return switch (self) {
            .arithmetic, .comparison, .logical, .assignment => .core,
            .bitwise => .service,
            .pattern_match => .cluster,
            .effect => .sovereign,
        };
    }
};

/// Type restrictions by profile
pub const TypeRestriction = struct {
    allowed_primitives: []const PrimitiveType,
    max_function_parameters: u32,
    allows_generics: bool,
    allows_effects: bool,
    allows_actors: bool,

    /// Get type restrictions for a profile
    pub fn forProfile(profile: LanguageProfile) TypeRestriction {
        return switch (profile) {
            .core => TypeRestriction{
                .allowed_primitives = &[_]PrimitiveType{ .i32, .f64, .bool, .string, .void, .never },
                .max_function_parameters = 4,
                .allows_generics = false,
                .allows_effects = false,
                .allows_actors = false,
            },
            .service => TypeRestriction{
                .allowed_primitives = &[_]PrimitiveType{ .i32, .i64, .f32, .f64, .bool, .string, .void, .never },
                .max_function_parameters = 8,
                .allows_generics = true,
                .allows_effects = false,
                .allows_actors = false,
            },
            .cluster => TypeRestriction{
                .allowed_primitives = &[_]PrimitiveType{ .i32, .i64, .f32, .f64, .bool, .string, .void, .never },
                .max_function_parameters = 12,
                .allows_generics = true,
                .allows_effects = false,
                .allows_actors = true,
            },
            .compute => TypeRestriction{
                .allowed_primitives = &[_]PrimitiveType{ .i32, .i64, .f32, .f64, .bool, .string, .void, .never },
                .max_function_parameters = 14,
                .allows_generics = true,
                .allows_effects = false,
                .allows_actors = false,
            },
            .sovereign => TypeRestriction{
                .allowed_primitives = &[_]PrimitiveType{ .i32, .i64, .f32, .f64, .bool, .string, .void, .never },
                .max_function_parameters = 16,
                .allows_generics = true,
                .allows_effects = true,
                .allows_actors = true,
            },
        };
    }
};

/// Profile violation information
pub const ProfileViolation = struct {
    feature: LanguageFeature,
    current_profile: LanguageProfile,
    required_profile: LanguageProfile,
    span: SourceSpan,
    message: []const u8,

    pub fn deinit(self: *ProfileViolation, allocator: Allocator) void {
        allocator.free(self.message);
    }
};

/// Feature matrix for efficient profile checking
pub const FeatureMatrix = struct {
    features: HashMap(LanguageFeature, LanguageProfile, FeatureContext, std.hash_map.default_max_load_percentage),

    const FeatureContext = struct {
        pub fn hash(self: @This(), key: LanguageFeature) u64 {
            _ = self;
            return @intFromEnum(key);
        }

        pub fn eql(self: @This(), a: LanguageFeature, b: LanguageFeature) bool {
            _ = self;
            return a == b;
        }
    };

    pub fn init(allocator: Allocator) FeatureMatrix {
        var matrix = FeatureMatrix{
            .features = HashMap(LanguageFeature, LanguageProfile, FeatureContext, std.hash_map.default_max_load_percentage).init(allocator),
        };

        // Initialize feature matrix
        matrix.initializeFeatures() catch {};

        return matrix;
    }

    pub fn deinit(self: *FeatureMatrix) void {
        self.features.deinit();
    }

    fn initializeFeatures(self: *FeatureMatrix) !void {
        const all_features = [_]LanguageFeature{
            .basic_types,              .functions,          .variables,         .control_flow,
            .error_handling,           .simple_concurrency, .interfaces,        .pattern_matching,
            .actor_model,              .supervision_trees,  .message_passing,   .effects_system,
            .advanced_metaprogramming, .comptime_execution, .capability_system,
        };

        for (all_features) |feature| {
            try self.features.put(feature, feature.getMinimumProfile());
        }
    }

    /// Check if feature is allowed in profile
    pub fn isFeatureAllowed(self: *FeatureMatrix, feature: LanguageFeature, profile: LanguageProfile) bool {
        if (self.features.get(feature)) |required_profile| {
            return @intFromEnum(profile) >= @intFromEnum(required_profile);
        }
        return false; // Unknown feature, deny by default
    }
};

/// Comprehensive profile manager
pub const ProfileManager = struct {
    allocator: Allocator,
    current_profile: LanguageProfile,
    npu_enabled: bool, // orthogonal :npu gate (AI/ML features)
    feature_matrix: FeatureMatrix,
    type_restrictions: TypeRestriction,
    violations: ArrayList(ProfileViolation),

    pub fn init(allocator: Allocator, profile: LanguageProfile) ProfileManager {
        return ProfileManager{
            .allocator = allocator,
            .current_profile = profile,
            .npu_enabled = false,
            .feature_matrix = FeatureMatrix.init(allocator),
            .type_restrictions = TypeRestriction.forProfile(profile),
            .violations = ArrayList(ProfileViolation).init(allocator),
        };
    }

    pub fn deinit(self: *ProfileManager) void {
        for (self.violations.items) |*violation| {
            violation.deinit(self.allocator);
        }
        self.violations.deinit();
        self.feature_matrix.deinit();
    }

    /// Change the current profile
    pub fn setProfile(self: *ProfileManager, profile: LanguageProfile) void {
        self.current_profile = profile;
        self.type_restrictions = TypeRestriction.forProfile(profile);
    }

    /// Toggle :npu orthogonal profile (AI/ML features)
    pub fn setNpuEnabled(self: *ProfileManager, enabled: bool) void {
        self.npu_enabled = enabled;
    }

    pub fn isNpuEnabled(self: *const ProfileManager) bool {
        return self.npu_enabled;
    }

    /// Validate feature usage against current profile
    pub fn validateFeature(self: *ProfileManager, feature: LanguageFeature, span: SourceSpan) !bool {
        if (self.feature_matrix.isFeatureAllowed(feature, self.current_profile)) {
            return true;
        }

        // Feature not allowed, create violation
        const required_profile = feature.getMinimumProfile();
        const message = try std.fmt.allocPrint(self.allocator, "Feature '{s}' requires profile '{s}' or higher, but current profile is '{s}'", .{ @tagName(feature), required_profile.getName(), self.current_profile.getName() });

        const violation = ProfileViolation{
            .feature = feature,
            .current_profile = self.current_profile,
            .required_profile = required_profile,
            .span = span,
            .message = message,
        };

        try self.violations.append(violation);
        return false;
    }

    /// Validate that an NPU-native feature is allowed (requires :npu gate)
    pub fn validateNpuFeature(self: *ProfileManager, feature_name: []const u8, span: SourceSpan) !bool {
        if (self.npu_enabled) return true;

        const message = try std.fmt.allocPrint(self.allocator, "NPU-native feature '{s}' requires :npu profile to be enabled", .{feature_name});
        const violation = ProfileViolation{
            .feature = .basic_types, // placeholder category; tracked via message
            .current_profile = self.current_profile,
            .required_profile = self.current_profile, // not applicable; orthogonal gate
            .span = span,
            .message = message,
        };
        try self.violations.append(violation);
        return false;
    }

    /// Get available primitive types for current profile
    pub fn getAvailableTypes(self: *ProfileManager) []const PrimitiveType {
        return self.type_restrictions.allowed_primitives;
    }

    /// Check if a primitive type is allowed
    pub fn isPrimitiveTypeAllowed(self: *ProfileManager, primitive: PrimitiveType) bool {
        for (self.type_restrictions.allowed_primitives) |allowed| {
            if (allowed == primitive) return true;
        }
        return false;
    }

    /// Check if an operator is allowed in current profile
    pub fn isOperatorAllowed(self: *ProfileManager, operator: OperatorCategory) bool {
        const required_profile = operator.getMinimumProfile();
        return @intFromEnum(self.current_profile) >= @intFromEnum(required_profile);
    }

    /// Validate function signature against profile constraints
    pub fn validateFunctionSignature(self: *ProfileManager, parameter_count: u32, span: SourceSpan) !bool {
        if (parameter_count <= self.type_restrictions.max_function_parameters) {
            return true;
        }

        const message = try std.fmt.allocPrint(self.allocator, "Function has {} parameters, but profile '{s}' allows maximum {}", .{ parameter_count, self.current_profile.getName(), self.type_restrictions.max_function_parameters });

        const violation = ProfileViolation{
            .feature = .functions,
            .current_profile = self.current_profile,
            .required_profile = .sovereign, // Assume sovereign profile for large signatures
            .span = span,
            .message = message,
        };

        try self.violations.append(violation);
        return false;
    }

    /// Check if generics are allowed
    pub fn allowsGenerics(self: *ProfileManager) bool {
        return self.type_restrictions.allows_generics;
    }

    /// Check if effects are allowed
    pub fn allowsEffects(self: *ProfileManager) bool {
        return self.type_restrictions.allows_effects;
    }

    /// Check if actors are allowed
    pub fn allowsActors(self: *ProfileManager) bool {
        return self.type_restrictions.allows_actors;
    }

    /// Get all profile violations
    pub fn getViolations(self: *ProfileManager) []const ProfileViolation {
        return self.violations.items;
    }

    /// Clear all violations
    pub fn clearViolations(self: *ProfileManager) void {
        for (self.violations.items) |*violation| {
            violation.deinit(self.allocator);
        }
        self.violations.clearRetainingCapacity();
    }

    /// Get profile upgrade suggestion
    pub fn suggestProfileUpgrade(self: *ProfileManager, required_features: []const LanguageFeature) ?LanguageProfile {
        var max_required_profile = self.current_profile;

        for (required_features) |feature| {
            const required_profile = feature.getMinimumProfile();
            if (@intFromEnum(required_profile) > @intFromEnum(max_required_profile)) {
                max_required_profile = required_profile;
            }
        }

        if (@intFromEnum(max_required_profile) > @intFromEnum(self.current_profile)) {
            return max_required_profile;
        }

        return null;
    }

    /// Generate profile compatibility report
    pub fn generateCompatibilityReport(self: *ProfileManager, allocator: Allocator) ![]const u8 {
        var report: ArrayList(u8) = .empty;
        const writer = report.writer();

        try writer.print("Profile Compatibility Report\n", .{});
        try writer.print("Current Profile: {s}\n", .{self.current_profile.getName()});
        try writer.print("Description: {s}\n\n", .{self.current_profile.getDescription()});

        try writer.print("Available Features:\n", .{});
        const all_features = [_]LanguageFeature{
            .basic_types,              .functions,          .variables,         .control_flow,
            .error_handling,           .simple_concurrency, .interfaces,        .pattern_matching,
            .actor_model,              .supervision_trees,  .message_passing,   .effects_system,
            .advanced_metaprogramming, .comptime_execution, .capability_system,
        };

        for (all_features) |feature| {
            const allowed = self.feature_matrix.isFeatureAllowed(feature, self.current_profile);
            const status = if (allowed) "✓" else "✗";
            try writer.print("  {s} {s}\n", .{ status, @tagName(feature) });
        }

        try writer.print("\nType Restrictions:\n", .{});
        try writer.print("  Allowed primitives: ", .{});
        for (self.type_restrictions.allowed_primitives, 0..) |prim, i| {
            if (i > 0) try writer.print(", ", .{});
            try writer.print("{s}", .{@tagName(prim)});
        }
        try writer.print("\n", .{});
        try writer.print("  Max function parameters: {}\n", .{self.type_restrictions.max_function_parameters});
        try writer.print("  Generics: {s}\n", .{if (self.type_restrictions.allows_generics) "Yes" else "No"});
        try writer.print("  Effects: {s}\n", .{if (self.type_restrictions.allows_effects) "Yes" else "No"});
        try writer.print("  Actors: {s}\n", .{if (self.type_restrictions.allows_actors) "Yes" else "No"});

        if (self.violations.items.len > 0) {
            try writer.print("\nProfile Violations:\n", .{});
            for (self.violations.items) |violation| {
                try writer.print("  - {s} ({}:{})\n", .{ violation.message, violation.span.start.line, violation.span.start.column });
            }
        }

        return try report.toOwnedSlice(allocator);
    }
};

// Comprehensive test suite
test "language profile feature validation" {
    // Test profile hierarchy
    try std.testing.expect(LanguageProfile.core.isSubsetOf(.service));
    try std.testing.expect(LanguageProfile.service.isSubsetOf(.cluster));
    try std.testing.expect(LanguageProfile.cluster.isSubsetOf(.sovereign));
    try std.testing.expect(!LanguageProfile.sovereign.isSubsetOf(.core));

    // Test profile names and descriptions
    try std.testing.expectEqualStrings("Core", LanguageProfile.core.getName());
    try std.testing.expectEqualStrings("Sovereign", LanguageProfile.sovereign.getName());

    const core_desc = LanguageProfile.core.getDescription();
    try std.testing.expect(std.mem.indexOf(u8, core_desc, "Foundational") != null);
}

test "language feature categorization" {
    // Test feature categories
    try std.testing.expect(LanguageFeature.basic_types.getCategory() == .core);
    try std.testing.expect(LanguageFeature.error_handling.getCategory() == .service_style);
    try std.testing.expect(LanguageFeature.pattern_matching.getCategory() == .cluster_style);
    try std.testing.expect(LanguageFeature.effects_system.getCategory() == .sovereign_featured);

    // Test minimum profile requirements
    try std.testing.expect(LanguageFeature.basic_types.getMinimumProfile() == .core);
    try std.testing.expect(LanguageFeature.error_handling.getMinimumProfile() == .service);
    try std.testing.expect(LanguageFeature.actor_model.getMinimumProfile() == .cluster);
    try std.testing.expect(LanguageFeature.effects_system.getMinimumProfile() == .sovereign);
}

test "type restrictions by profile" {
    const core_restrictions = TypeRestriction.forProfile(.core);
    const sov_restrictions = TypeRestriction.forProfile(.sovereign);

    // Core profile has fewer allowed types
    try std.testing.expect(core_restrictions.allowed_primitives.len == 6);
    try std.testing.expect(sov_restrictions.allowed_primitives.len == 8);

    // Core profile has stricter parameter limits
    try std.testing.expect(core_restrictions.max_function_parameters == 4);
    try std.testing.expect(sov_restrictions.max_function_parameters == 16);

    // Core profile doesn't allow advanced features
    try std.testing.expect(!core_restrictions.allows_generics);
    try std.testing.expect(!core_restrictions.allows_effects);
    try std.testing.expect(!core_restrictions.allows_actors);

    // Sovereign profile allows everything
    try std.testing.expect(sov_restrictions.allows_generics);
    try std.testing.expect(sov_restrictions.allows_effects);
    try std.testing.expect(sov_restrictions.allows_actors);
}

test "feature matrix functionality" {
    const allocator = std.testing.allocator;

    var matrix = FeatureMatrix.init(allocator);
    defer matrix.deinit();

    // Test feature allowance
    try std.testing.expect(matrix.isFeatureAllowed(.basic_types, .core));
    try std.testing.expect(matrix.isFeatureAllowed(.basic_types, .sovereign));

    try std.testing.expect(!matrix.isFeatureAllowed(.error_handling, .core));
    try std.testing.expect(matrix.isFeatureAllowed(.error_handling, .service));

    try std.testing.expect(!matrix.isFeatureAllowed(.actor_model, .service));
    try std.testing.expect(matrix.isFeatureAllowed(.actor_model, .cluster));

    try std.testing.expect(!matrix.isFeatureAllowed(.effects_system, .cluster));
    try std.testing.expect(matrix.isFeatureAllowed(.effects_system, .sovereign));
}

test "profile manager initialization and basic operations" {
    const allocator = std.testing.allocator;

    var manager = ProfileManager.init(allocator, .service);
    defer manager.deinit();

    // Test initial state
    try std.testing.expect(manager.current_profile == .service);
    try std.testing.expect(manager.violations.items.len == 0);

    // Test profile change
    manager.setProfile(.sovereign);
    try std.testing.expect(manager.current_profile == .sovereign);
    try std.testing.expect(manager.allowsEffects());

    // Test type checking
    try std.testing.expect(manager.isPrimitiveTypeAllowed(.i32));
    try std.testing.expect(manager.isPrimitiveTypeAllowed(.f64));

    // :npu gate defaults to disabled
    try std.testing.expect(!manager.isNpuEnabled());
    manager.setNpuEnabled(true);
    try std.testing.expect(manager.isNpuEnabled());
}

test "profile violation detection and reporting" {
    const allocator = std.testing.allocator;

    var manager = ProfileManager.init(allocator, .core);
    defer manager.deinit();

    const test_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = source_span_utils.SourcePosition{ .line = 1, .column = 10, .offset = 9 },
        .file_path = "test.jan",
    };

    // Test allowed feature
    const basic_allowed = try manager.validateFeature(.basic_types, test_span);
    try std.testing.expect(basic_allowed);
    try std.testing.expect(manager.violations.items.len == 0);

    // Test disallowed feature
    const effects_allowed = try manager.validateFeature(.effects_system, test_span);
    try std.testing.expect(!effects_allowed);
    try std.testing.expect(manager.violations.items.len == 1);

    const violation = &manager.violations.items[0];
    try std.testing.expect(violation.feature == .effects_system);
    try std.testing.expect(violation.current_profile == .core);
    try std.testing.expect(violation.required_profile == .sovereign);
    try std.testing.expect(std.mem.indexOf(u8, violation.message, "effects_system") != null);

    // NPU feature should be rejected when :npu is disabled
    const test_span2 = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 2, .column = 1, .offset = 10 },
        .end = source_span_utils.SourcePosition{ .line = 2, .column = 12, .offset = 21 },
        .file_path = "test.jan",
    };
    const npu_ok = try manager.validateNpuFeature("tensor", test_span2);
    try std.testing.expect(!npu_ok);
}

test "function signature validation" {
    const allocator = std.testing.allocator;

    var manager = ProfileManager.init(allocator, .core);
    defer manager.deinit();

    const test_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = source_span_utils.SourcePosition{ .line = 1, .column = 20, .offset = 19 },
        .file_path = "test.jan",
    };

    // Test allowed parameter count
    const small_func_ok = try manager.validateFunctionSignature(3, test_span);
    try std.testing.expect(small_func_ok);
    try std.testing.expect(manager.violations.items.len == 0);

    // Test excessive parameter count
    const large_func_ok = try manager.validateFunctionSignature(10, test_span);
    try std.testing.expect(!large_func_ok);
    try std.testing.expect(manager.violations.items.len == 1);

    const violation = &manager.violations.items[0];
    try std.testing.expect(std.mem.indexOf(u8, violation.message, "10 parameters") != null);
    try std.testing.expect(std.mem.indexOf(u8, violation.message, "maximum 4") != null);
}

test "operator category validation" {
    const allocator = std.testing.allocator;

    var manager = ProfileManager.init(allocator, .service);
    defer manager.deinit();

    // Test allowed operators
    try std.testing.expect(manager.isOperatorAllowed(.arithmetic));
    try std.testing.expect(manager.isOperatorAllowed(.comparison));
    try std.testing.expect(manager.isOperatorAllowed(.logical));
    try std.testing.expect(manager.isOperatorAllowed(.bitwise));

    // Test restricted operators
    try std.testing.expect(!manager.isOperatorAllowed(.pattern_match)); // Requires cluster
    try std.testing.expect(!manager.isOperatorAllowed(.effect)); // Requires sovereign

    // Test with higher profile
    manager.setProfile(.sovereign);
    try std.testing.expect(manager.isOperatorAllowed(.pattern_match));
    try std.testing.expect(manager.isOperatorAllowed(.effect));
}

test "profile upgrade suggestions" {
    const allocator = std.testing.allocator;

    var manager = ProfileManager.init(allocator, .core);
    defer manager.deinit();

    // Test no upgrade needed
    const basic_features = [_]LanguageFeature{ .basic_types, .functions };
    const no_upgrade = manager.suggestProfileUpgrade(&basic_features);
    try std.testing.expect(no_upgrade == null);

    // Test upgrade needed
    const advanced_features = [_]LanguageFeature{ .basic_types, .error_handling, .actor_model };
    const upgrade_suggestion = manager.suggestProfileUpgrade(&advanced_features);
    try std.testing.expect(upgrade_suggestion != null);
    try std.testing.expect(upgrade_suggestion.? == .cluster); // Highest required profile
}

test "compatibility report generation" {
    const allocator = std.testing.allocator;

    var manager = ProfileManager.init(allocator, .service);
    defer manager.deinit();

    const report = try manager.generateCompatibilityReport(allocator);
    defer allocator.free(report);

    // Check report contains expected information
    try std.testing.expect(std.mem.indexOf(u8, report, "Profile Compatibility Report") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Service") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Available Features") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Type Restrictions") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "✓ basic_types") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "✗ effects_system") != null);
}

test "profile alias resolution" {
    try std.testing.expectEqual(LanguageProfile.core, LanguageProfile.resolve("core").?);
    try std.testing.expectEqual(LanguageProfile.core, LanguageProfile.resolve("min").?);
    try std.testing.expectEqual(LanguageProfile.service, LanguageProfile.resolve("service").?);
    try std.testing.expectEqual(LanguageProfile.service, LanguageProfile.resolve("go").?);
    try std.testing.expectEqual(LanguageProfile.cluster, LanguageProfile.resolve("cluster").?);
    try std.testing.expectEqual(LanguageProfile.cluster, LanguageProfile.resolve("elixir").?);
    try std.testing.expectEqual(LanguageProfile.compute, LanguageProfile.resolve("compute").?);
    try std.testing.expectEqual(LanguageProfile.compute, LanguageProfile.resolve("npu").?);
    try std.testing.expectEqual(LanguageProfile.sovereign, LanguageProfile.resolve("sovereign").?);
    try std.testing.expectEqual(LanguageProfile.sovereign, LanguageProfile.resolve("full").?);
    try std.testing.expect(LanguageProfile.resolve("unknown") == null);
}
