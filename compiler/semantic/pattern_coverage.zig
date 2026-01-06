// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Pattern Coverage Analysis - The Exhaustiveness Enforcer
//!
//! This module implements exhaustiveness checking for match expressions,
//! ensuring that all possible values of a scrutinee type are covered by
//! at least one pattern. This is the **Elm Guarantee** for Janus.
//!
//! Key Features:
//! - Wildcard detection (`_`, `else`)
//! - Boolean exhaustiveness (true, false)
//! - Numeric type handling (requires wildcard)
//! - Future: Enum variant coverage
//! - Future: Option<T> coverage (Some, None)
//!
//! Philosophy:
//! Non-exhaustive matches are **compile errors**, not warnings.
//! The compiler is the executioner, not a suggestion box.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const type_system = @import("type_system.zig");
const TypeSystem = type_system.TypeSystem;
const TypeId = type_system.TypeId;

/// Literal value in a pattern
pub const LiteralValue = union(enum) {
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
};

/// Pattern representation for exhaustiveness checking
pub const Pattern = union(enum) {
    /// Wildcard pattern: `_` or `else` (matches everything)
    wildcard,

    /// Literal pattern: `42`, `true`, `"hello"`
    literal: LiteralValue,

    /// Identifier pattern: `x` (binds value, matches everything)
    identifier: []const u8,

    /// Variant pattern: `.Some`, `.None`, `.Click` (for enums/ADTs)
    variant: []const u8,

    /// Tuple pattern: `(x, y)` (destructures tuples)
    tuple: []Pattern,

    /// Struct pattern: `{ x, y }` (destructures structs)
    struct_pattern: StructPattern,

    pub fn deinit(self: *Pattern, allocator: Allocator) void {
        switch (self.*) {
            .identifier => |name| allocator.free(name),
            .variant => |name| allocator.free(name),
            .literal => |lit| {
                if (lit == .string) allocator.free(lit.string);
            },
            .tuple => |patterns| {
                for (patterns) |*p| p.deinit(allocator);
                allocator.free(patterns);
            },
            .struct_pattern => |*sp| sp.deinit(allocator),
            else => {},
        }
    }
};

/// Struct pattern field
pub const StructPatternField = struct {
    name: []const u8,
    pattern: Pattern,

    pub fn deinit(self: *StructPatternField, allocator: Allocator) void {
        allocator.free(self.name);
        self.pattern.deinit(allocator);
    }
};

/// Struct pattern: `{ x, y: z }`
pub const StructPattern = struct {
    fields: []StructPatternField,

    pub fn deinit(self: *StructPattern, allocator: Allocator) void {
        for (self.fields) |*field| field.deinit(allocator);
        allocator.free(self.fields);
    }
};

/// Result of exhaustiveness checking
pub const ExhaustivenessResult = struct {
    /// Whether the match is exhaustive
    is_exhaustive: bool,

    /// Missing patterns (empty if exhaustive)
    missing_patterns: []Pattern,

    pub fn deinit(self: *ExhaustivenessResult, allocator: Allocator) void {
        for (self.missing_patterns) |*pattern| {
            pattern.deinit(allocator);
        }
        allocator.free(self.missing_patterns);
    }
};

/// Pattern coverage analyzer
pub const PatternCoverage = struct {
    allocator: Allocator,
    type_system: *TypeSystem,

    pub fn init(allocator: Allocator, type_sys: *TypeSystem) PatternCoverage {
        return PatternCoverage{
            .allocator = allocator,
            .type_system = type_sys,
        };
    }

    pub fn deinit(self: *PatternCoverage) void {
        _ = self;
        // No owned resources currently
    }

    /// Check if match arms cover all possible values of scrutinee type
    ///
    /// This is the **Elm Guarantee**: The compiler FORCES you to handle
    /// all cases. Non-exhaustive matches are compile errors, not warnings.
    pub fn checkExhaustiveness(
        self: *PatternCoverage,
        scrutinee_type: TypeId,
        patterns: []const Pattern,
    ) !ExhaustivenessResult {
        // 1. Check for wildcard or identifier (always exhaustive)
        for (patterns) |pattern| {
            switch (pattern) {
                .wildcard => {
                    return ExhaustivenessResult{
                        .is_exhaustive = true,
                        .missing_patterns = &[_]Pattern{},
                    };
                },
                .identifier => {
                    // Identifier patterns bind the value, matching everything
                    return ExhaustivenessResult{
                        .is_exhaustive = true,
                        .missing_patterns = &[_]Pattern{},
                    };
                },
                else => {},
            }
        }

        // 2. Type-specific exhaustiveness checking
        const type_info = self.type_system.getTypeInfo(scrutinee_type);

        switch (type_info.kind) {
            .primitive => |prim| {
                switch (prim) {
                    .bool => return try self.checkBoolExhaustiveness(patterns),
                    .i32, .i64, .f32, .f64 => {
                        // Numeric types have infinite domain: wildcard required
                        return try self.createNonExhaustiveResult(&[_]Pattern{.{ .wildcard = {} }});
                    },
                    .string => {
                        // Strings have infinite domain: wildcard required
                        return try self.createNonExhaustiveResult(&[_]Pattern{.{ .wildcard = {} }});
                    },
                    else => {
                        // Unknown primitive: require wildcard
                        return try self.createNonExhaustiveResult(&[_]Pattern{.{ .wildcard = {} }});
                    },
                }
            },
            // Future: .enum_type => return try self.checkEnumExhaustiveness(scrutinee_type, patterns),
            // Future: .option_type => return try self.checkOptionExhaustiveness(patterns),
            else => {
                // Unknown type: require wildcard for safety
                return try self.createNonExhaustiveResult(&[_]Pattern{.{ .wildcard = {} }});
            },
        }
    }

    /// Check exhaustiveness for boolean type
    ///
    /// A bool match is exhaustive if:
    /// - It has patterns for both `true` and `false`, OR
    /// - It has a wildcard/identifier pattern
    fn checkBoolExhaustiveness(
        self: *PatternCoverage,
        patterns: []const Pattern,
    ) !ExhaustivenessResult {
        var has_true = false;
        var has_false = false;

        for (patterns) |pattern| {
            switch (pattern) {
                .literal => |lit| {
                    if (lit == .bool) {
                        if (lit.bool) {
                            has_true = true;
                        } else {
                            has_false = true;
                        }
                    }
                },
                .wildcard, .identifier => {
                    // Already handled in main function, but double-check
                    return ExhaustivenessResult{
                        .is_exhaustive = true,
                        .missing_patterns = &[_]Pattern{},
                    };
                },
                else => {
                    // Other patterns don't match bool
                },
            }
        }

        // Check if both true and false are covered
        if (has_true and has_false) {
            return ExhaustivenessResult{
                .is_exhaustive = true,
                .missing_patterns = &[_]Pattern{},
            };
        }

        // Build list of missing patterns
        var missing = try ArrayList(Pattern).initCapacity(self.allocator, 0);
        errdefer missing.deinit(self.allocator);

        if (!has_true) {
            try missing.append(self.allocator, .{ .literal = .{ .bool = true } });
        }
        if (!has_false) {
            try missing.append(self.allocator, .{ .literal = .{ .bool = false } });
        }

        return ExhaustivenessResult{
            .is_exhaustive = false,
            .missing_patterns = try missing.toOwnedSlice(self.allocator),
        };
    }

    /// Helper: Create non-exhaustive result with given missing patterns
    fn createNonExhaustiveResult(
        self: *PatternCoverage,
        missing: []const Pattern,
    ) !ExhaustivenessResult {
        const owned_missing = try self.allocator.alloc(Pattern, missing.len);
        @memcpy(owned_missing, missing);

        return ExhaustivenessResult{
            .is_exhaustive = false,
            .missing_patterns = owned_missing,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "wildcard pattern is always exhaustive" {
    const allocator = std.testing.allocator;

    var type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    var coverage = PatternCoverage.init(allocator, &type_sys);
    defer coverage.deinit();

    const bool_type = type_sys.getPrimitiveType(.bool);
    const patterns = [_]Pattern{.{ .wildcard = {} }};

    var result = try coverage.checkExhaustiveness(bool_type, &patterns);
    defer result.deinit(allocator);

    try std.testing.expect(result.is_exhaustive);
    try std.testing.expectEqual(@as(usize, 0), result.missing_patterns.len);
}

test "identifier pattern is always exhaustive" {
    const allocator = std.testing.allocator;

    var type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    var coverage = PatternCoverage.init(allocator, &type_sys);
    defer coverage.deinit();

    const bool_type = type_sys.getPrimitiveType(.bool);
    const name = try allocator.dupe(u8, "x");
    defer allocator.free(name);

    var patterns = [_]Pattern{.{ .identifier = name }};

    var result = try coverage.checkExhaustiveness(bool_type, &patterns);
    defer result.deinit(allocator);

    try std.testing.expect(result.is_exhaustive);
    try std.testing.expectEqual(@as(usize, 0), result.missing_patterns.len);
}

test "bool match with true and false is exhaustive" {
    const allocator = std.testing.allocator;

    var type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    var coverage = PatternCoverage.init(allocator, &type_sys);
    defer coverage.deinit();

    const bool_type = type_sys.getPrimitiveType(.bool);
    const patterns = [_]Pattern{
        .{ .literal = .{ .bool = true } },
        .{ .literal = .{ .bool = false } },
    };

    var result = try coverage.checkExhaustiveness(bool_type, &patterns);
    defer result.deinit(allocator);

    try std.testing.expect(result.is_exhaustive);
    try std.testing.expectEqual(@as(usize, 0), result.missing_patterns.len);
}

test "bool match with only true is non-exhaustive" {
    const allocator = std.testing.allocator;

    var type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    var coverage = PatternCoverage.init(allocator, &type_sys);
    defer coverage.deinit();

    const bool_type = type_sys.getPrimitiveType(.bool);
    const patterns = [_]Pattern{
        .{ .literal = .{ .bool = true } },
    };

    var result = try coverage.checkExhaustiveness(bool_type, &patterns);
    defer result.deinit(allocator);

    try std.testing.expect(!result.is_exhaustive);
    try std.testing.expectEqual(@as(usize, 1), result.missing_patterns.len);
    try std.testing.expect(result.missing_patterns[0] == .literal);
    try std.testing.expect(result.missing_patterns[0].literal == .bool);
    try std.testing.expect(result.missing_patterns[0].literal.bool == false);
}

test "numeric types require wildcard" {
    const allocator = std.testing.allocator;

    var type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    var coverage = PatternCoverage.init(allocator, &type_sys);
    defer coverage.deinit();

    const i32_type = type_sys.getPrimitiveType(.i32);
    const patterns = [_]Pattern{
        .{ .literal = .{ .integer = 0 } },
        .{ .literal = .{ .integer = 1 } },
    };

    var result = try coverage.checkExhaustiveness(i32_type, &patterns);
    defer result.deinit(allocator);

    try std.testing.expect(!result.is_exhaustive);
    try std.testing.expectEqual(@as(usize, 1), result.missing_patterns.len);
    try std.testing.expect(result.missing_patterns[0] == .wildcard);
}
