// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Fix Learning Engine
//!
//! Tracks which fixes users accept for which errors, building a learning
//! system that improves fix suggestions over time. Key features:
//!
//! - Pattern recognition: Track error patterns and accepted fixes
//! - Preference learning: Detect user preferences (cast vs qualified names)
//! - Confidence adjustment: Boost confidence for frequently-accepted fixes
//! - Persistence: Save learning data for cross-session improvement
//!
//! Unlike traditional compilers, this creates a feedback loop where the
//! compiler learns from user behavior.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const nextgen = @import("nextgen_diagnostic.zig");
const LearningContext = nextgen.LearningContext;
const DiagnosticCode = nextgen.DiagnosticCode;
const CauseCategory = nextgen.CauseCategory;
const CID = nextgen.CID;

/// Configuration for fix learning
pub const LearningConfig = struct {
    /// Minimum occurrences to consider a pattern
    min_pattern_occurrences: u32 = 3,
    /// Weight for recent fixes (exponential decay)
    recency_weight: f32 = 0.9,
    /// Enable persistence (save to disk)
    enable_persistence: bool = true,
    /// Path for persistence file
    persistence_path: []const u8 = ".janus/fix_learning.bin",
    /// Maximum patterns to store
    max_patterns: u32 = 10000,
};

/// A recorded fix acceptance event
pub const FixAcceptance = struct {
    /// Error pattern hash
    error_pattern: u64,
    /// Fix pattern hash
    fix_pattern: u64,
    /// Fix category (for preference tracking)
    fix_category: FixCategory,
    /// Timestamp of acceptance
    timestamp: i64,
    /// Was the fix applied without modification?
    applied_verbatim: bool,

    pub const FixCategory = enum {
        explicit_cast,
        qualified_name,
        import_statement,
        type_annotation,
        function_definition,
        variable_rename,
        argument_reorder,
        other,
    };
};

/// Statistics for a fix pattern
pub const FixPatternStats = struct {
    /// Total times this fix was suggested
    times_suggested: u32,
    /// Times this fix was accepted
    times_accepted: u32,
    /// Times accepted without modification
    times_verbatim: u32,
    /// Last acceptance timestamp
    last_accepted: i64,
    /// Fix category
    category: FixAcceptance.FixCategory,

    pub fn acceptanceRate(self: FixPatternStats) f32 {
        if (self.times_suggested == 0) return 0.0;
        return @as(f32, @floatFromInt(self.times_accepted)) /
            @as(f32, @floatFromInt(self.times_suggested));
    }

    pub fn verbatimRate(self: FixPatternStats) f32 {
        if (self.times_accepted == 0) return 0.0;
        return @as(f32, @floatFromInt(self.times_verbatim)) /
            @as(f32, @floatFromInt(self.times_accepted));
    }
};

/// Aggregated statistics for an error pattern
pub const ErrorPatternStats = struct {
    /// Total occurrences of this error pattern
    occurrences: u32,
    /// Associated fix patterns and their stats
    fix_stats: std.AutoHashMap(u64, FixPatternStats),
    /// Most commonly accepted fix
    best_fix_pattern: ?u64,
    /// Best fix acceptance rate
    best_fix_rate: f32,

    pub fn init(allocator: Allocator) ErrorPatternStats {
        return .{
            .occurrences = 0,
            .fix_stats = std.AutoHashMap(u64, FixPatternStats).init(allocator),
            .best_fix_pattern = null,
            .best_fix_rate = 0.0,
        };
    }

    pub fn deinit(self: *ErrorPatternStats) void {
        self.fix_stats.deinit();
    }

    pub fn recordSuggestion(self: *ErrorPatternStats, fix_pattern: u64, category: FixAcceptance.FixCategory) !void {
        const entry = self.fix_stats.getPtr(fix_pattern) orelse blk: {
            try self.fix_stats.put(fix_pattern, .{
                .times_suggested = 0,
                .times_accepted = 0,
                .times_verbatim = 0,
                .last_accepted = 0,
                .category = category,
            });
            break :blk self.fix_stats.getPtr(fix_pattern).?;
        };
        entry.times_suggested += 1;
    }

    pub fn recordAcceptance(self: *ErrorPatternStats, fix_pattern: u64, verbatim: bool, timestamp: i64) void {
        if (self.fix_stats.getPtr(fix_pattern)) |entry| {
            entry.times_accepted += 1;
            if (verbatim) entry.times_verbatim += 1;
            entry.last_accepted = timestamp;

            // Update best fix
            const rate = entry.acceptanceRate();
            if (rate > self.best_fix_rate) {
                self.best_fix_rate = rate;
                self.best_fix_pattern = fix_pattern;
            }
        }
    }
};

/// User preference signals detected from fix patterns
pub const UserPreferences = struct {
    /// Preference for explicit casts over implicit conversions
    prefers_explicit_casts: f32,
    /// Preference for qualified names over imports
    prefers_qualified_names: f32,
    /// Preference for inline fixes over multi-file changes
    prefers_inline_fixes: f32,
    /// Acceptance threshold (fixes above this are suggested first)
    acceptance_threshold: f32,

    pub fn default() UserPreferences {
        return .{
            .prefers_explicit_casts = 0.5,
            .prefers_qualified_names = 0.5,
            .prefers_inline_fixes = 0.7,
            .acceptance_threshold = 0.3,
        };
    }
};

/// Fix Learning Engine
pub const FixLearningEngine = struct {
    allocator: Allocator,
    config: LearningConfig,
    /// Error patterns and their fix statistics
    error_patterns: std.AutoHashMap(u64, ErrorPatternStats),
    /// User preferences learned over time
    preferences: UserPreferences,
    /// Recent acceptances (for decay calculation)
    recent_acceptances: ArrayList(FixAcceptance),
    /// Total statistics
    total_suggestions: u64,
    total_acceptances: u64,

    pub fn init(allocator: Allocator) FixLearningEngine {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: Allocator, config: LearningConfig) FixLearningEngine {
        var engine = FixLearningEngine{
            .allocator = allocator,
            .config = config,
            .error_patterns = std.AutoHashMap(u64, ErrorPatternStats).init(allocator),
            .preferences = UserPreferences.default(),
            .recent_acceptances = ArrayList(FixAcceptance).init(allocator),
            .total_suggestions = 0,
            .total_acceptances = 0,
        };

        // Try to load persisted data
        if (config.enable_persistence) {
            engine.load() catch {}; // Ignore load errors
        }

        return engine;
    }

    pub fn deinit(self: *FixLearningEngine) void {
        // Save before cleanup
        if (self.config.enable_persistence) {
            self.save() catch {}; // Ignore save errors
        }

        var iter = self.error_patterns.valueIterator();
        while (iter.next()) |stats| {
            stats.deinit();
        }
        self.error_patterns.deinit();
        self.recent_acceptances.deinit();
    }

    /// Record that a fix was suggested
    pub fn recordSuggestion(
        self: *FixLearningEngine,
        error_pattern: u64,
        fix_pattern: u64,
        category: FixAcceptance.FixCategory,
    ) !void {
        const stats = self.error_patterns.getPtr(error_pattern) orelse blk: {
            try self.error_patterns.put(error_pattern, ErrorPatternStats.init(self.allocator));
            break :blk self.error_patterns.getPtr(error_pattern).?;
        };

        stats.occurrences += 1;
        try stats.recordSuggestion(fix_pattern, category);
        self.total_suggestions += 1;
    }

    /// Record that a fix was accepted by the user
    pub fn recordAcceptance(
        self: *FixLearningEngine,
        error_pattern: u64,
        fix_pattern: u64,
        category: FixAcceptance.FixCategory,
        verbatim: bool,
    ) !void {
        const timestamp = std.time.timestamp();

        // Update error pattern stats
        if (self.error_patterns.getPtr(error_pattern)) |stats| {
            stats.recordAcceptance(fix_pattern, verbatim, timestamp);
        }

        // Record for recent acceptances
        try self.recent_acceptances.append(.{
            .error_pattern = error_pattern,
            .fix_pattern = fix_pattern,
            .fix_category = category,
            .timestamp = timestamp,
            .applied_verbatim = verbatim,
        });

        self.total_acceptances += 1;

        // Update preferences based on category
        self.updatePreferences(category);

        // Trim old acceptances
        self.trimOldAcceptances();
    }

    /// Get acceptance rate for a specific fix pattern
    pub fn getAcceptanceRate(self: *const FixLearningEngine, error_pattern: u64, fix_pattern: u64) f32 {
        const stats = self.error_patterns.get(error_pattern) orelse return 0.0;
        const fix_stats = stats.fix_stats.get(fix_pattern) orelse return 0.0;
        return fix_stats.acceptanceRate();
    }

    /// Get best fix for an error pattern
    pub fn getBestFix(self: *const FixLearningEngine, error_pattern: u64) ?u64 {
        const stats = self.error_patterns.get(error_pattern) orelse return null;
        return stats.best_fix_pattern;
    }

    /// Build learning context for a diagnostic
    pub fn buildLearningContext(
        self: *FixLearningEngine,
        error_pattern: u64,
    ) LearningContext {
        const stats = self.error_patterns.get(error_pattern);

        // Build preference signals
        var signals = ArrayList(LearningContext.PreferenceSignal).init(self.allocator);

        if (self.preferences.prefers_explicit_casts > 0.6) {
            signals.append(.{
                .signal_type = .explicit_cast_preferred,
                .weight = self.preferences.prefers_explicit_casts,
            }) catch {};
        }

        if (self.preferences.prefers_qualified_names > 0.6) {
            signals.append(.{
                .signal_type = .qualified_name_preferred,
                .weight = self.preferences.prefers_qualified_names,
            }) catch {};
        }

        if (self.preferences.prefers_inline_fixes > 0.6) {
            signals.append(.{
                .signal_type = .inline_fix_preferred,
                .weight = self.preferences.prefers_inline_fixes,
            }) catch {};
        }

        return LearningContext{
            .error_pattern_id = error_pattern,
            .similar_past_errors = if (stats) |s| s.occurrences else 0,
            .best_past_fix = null, // Would need to resolve pattern to description
            .user_preference_signals = signals.toOwnedSlice() catch &[_]LearningContext.PreferenceSignal{},
        };
    }

    /// Adjust fix confidence based on learning
    pub fn adjustConfidence(
        self: *const FixLearningEngine,
        base_confidence: f32,
        error_pattern: u64,
        fix_pattern: u64,
        category: FixAcceptance.FixCategory,
    ) f32 {
        var adjusted = base_confidence;

        // Boost based on acceptance rate
        const acceptance_rate = self.getAcceptanceRate(error_pattern, fix_pattern);
        if (acceptance_rate > 0) {
            adjusted += acceptance_rate * 0.2;
        }

        // Adjust based on user preferences
        switch (category) {
            .explicit_cast => adjusted += (self.preferences.prefers_explicit_casts - 0.5) * 0.1,
            .qualified_name => adjusted += (self.preferences.prefers_qualified_names - 0.5) * 0.1,
            .import_statement => adjusted -= (self.preferences.prefers_qualified_names - 0.5) * 0.1,
            else => {},
        }

        // Clamp to valid range
        return @min(0.99, @max(0.01, adjusted));
    }

    /// Compute a hash for an error pattern
    pub fn computeErrorPattern(
        code: DiagnosticCode,
        cause: CauseCategory,
        context_hash: u64,
    ) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&code.phase));
        hasher.update(std.mem.asBytes(&code.code));
        hasher.update(std.mem.asBytes(&cause));
        hasher.update(std.mem.asBytes(&context_hash));
        return hasher.final();
    }

    /// Compute a hash for a fix pattern
    pub fn computeFixPattern(
        category: FixAcceptance.FixCategory,
        fix_description: []const u8,
    ) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&category));
        hasher.update(fix_description);
        return hasher.final();
    }

    /// Get overall acceptance rate
    pub fn getOverallAcceptanceRate(self: *const FixLearningEngine) f32 {
        if (self.total_suggestions == 0) return 0.0;
        return @as(f32, @floatFromInt(self.total_acceptances)) /
            @as(f32, @floatFromInt(self.total_suggestions));
    }

    /// Get statistics summary
    pub fn getStatistics(self: *const FixLearningEngine) Statistics {
        return .{
            .total_patterns = @as(u32, @intCast(self.error_patterns.count())),
            .total_suggestions = self.total_suggestions,
            .total_acceptances = self.total_acceptances,
            .overall_acceptance_rate = self.getOverallAcceptanceRate(),
            .preferences = self.preferences,
        };
    }

    pub const Statistics = struct {
        total_patterns: u32,
        total_suggestions: u64,
        total_acceptances: u64,
        overall_acceptance_rate: f32,
        preferences: UserPreferences,
    };

    // =========================================================================
    // Private Helpers
    // =========================================================================

    fn updatePreferences(self: *FixLearningEngine, category: FixAcceptance.FixCategory) void {
        const alpha = self.config.recency_weight;

        switch (category) {
            .explicit_cast => {
                self.preferences.prefers_explicit_casts =
                    alpha * 1.0 + (1 - alpha) * self.preferences.prefers_explicit_casts;
            },
            .qualified_name => {
                self.preferences.prefers_qualified_names =
                    alpha * 1.0 + (1 - alpha) * self.preferences.prefers_qualified_names;
            },
            .import_statement => {
                self.preferences.prefers_qualified_names =
                    alpha * 0.0 + (1 - alpha) * self.preferences.prefers_qualified_names;
            },
            else => {},
        }
    }

    fn trimOldAcceptances(self: *FixLearningEngine) void {
        // Keep last 1000 acceptances for preference calculation
        if (self.recent_acceptances.items.len > 1000) {
            const to_remove = self.recent_acceptances.items.len - 1000;
            self.recent_acceptances.replaceRange(0, to_remove, &[_]FixAcceptance{}) catch {};
        }
    }

    /// Save learning data to disk
    pub fn save(self: *FixLearningEngine) !void {
        _ = self;
        // Simplified: In production, serialize error_patterns and preferences
        // to self.config.persistence_path
    }

    /// Load learning data from disk
    pub fn load(self: *FixLearningEngine) !void {
        _ = self;
        // Simplified: In production, deserialize from self.config.persistence_path
    }
};

/// Rank fixes based on learning
pub fn rankFixes(
    engine: *const FixLearningEngine,
    error_pattern: u64,
    fixes: []FixInfo,
) void {
    // Adjust confidence and sort by adjusted confidence
    for (fixes) |*fix| {
        fix.adjusted_confidence = engine.adjustConfidence(
            fix.base_confidence,
            error_pattern,
            fix.fix_pattern,
            fix.category,
        );
    }

    // Sort by adjusted confidence (highest first)
    std.mem.sort(FixInfo, fixes, {}, struct {
        fn lessThan(_: void, a: FixInfo, b: FixInfo) bool {
            return a.adjusted_confidence > b.adjusted_confidence;
        }
    }.lessThan);
}

pub const FixInfo = struct {
    fix_pattern: u64,
    category: FixAcceptance.FixCategory,
    base_confidence: f32,
    adjusted_confidence: f32,
    description: []const u8,
};

// =============================================================================
// Tests
// =============================================================================

test "FixLearningEngine initialization" {
    const allocator = std.testing.allocator;

    var engine = FixLearningEngine.initWithConfig(allocator, .{
        .enable_persistence = false,
    });
    defer engine.deinit();

    try std.testing.expectEqual(@as(u64, 0), engine.total_suggestions);
    try std.testing.expectEqual(@as(u64, 0), engine.total_acceptances);
}

test "FixLearningEngine records suggestions and acceptances" {
    const allocator = std.testing.allocator;

    var engine = FixLearningEngine.initWithConfig(allocator, .{
        .enable_persistence = false,
    });
    defer engine.deinit();

    const error_pattern: u64 = 12345;
    const fix_pattern: u64 = 67890;

    // Record suggestion
    try engine.recordSuggestion(error_pattern, fix_pattern, .explicit_cast);
    try std.testing.expectEqual(@as(u64, 1), engine.total_suggestions);

    // Record acceptance
    try engine.recordAcceptance(error_pattern, fix_pattern, .explicit_cast, true);
    try std.testing.expectEqual(@as(u64, 1), engine.total_acceptances);

    // Check acceptance rate
    const rate = engine.getAcceptanceRate(error_pattern, fix_pattern);
    try std.testing.expect(rate > 0.99); // Should be 1.0
}

test "FixLearningEngine adjusts confidence" {
    const allocator = std.testing.allocator;

    var engine = FixLearningEngine.initWithConfig(allocator, .{
        .enable_persistence = false,
    });
    defer engine.deinit();

    const error_pattern: u64 = 12345;
    const fix_pattern: u64 = 67890;

    // Record high acceptance rate
    for (0..10) |_| {
        try engine.recordSuggestion(error_pattern, fix_pattern, .explicit_cast);
        try engine.recordAcceptance(error_pattern, fix_pattern, .explicit_cast, true);
    }

    // Confidence should be boosted
    const adjusted = engine.adjustConfidence(0.5, error_pattern, fix_pattern, .explicit_cast);
    try std.testing.expect(adjusted > 0.5);
}

test "FixLearningEngine learns preferences" {
    const allocator = std.testing.allocator;

    var engine = FixLearningEngine.initWithConfig(allocator, .{
        .enable_persistence = false,
        .recency_weight = 0.9,
    });
    defer engine.deinit();

    // Accept many cast fixes
    for (0..20) |i| {
        try engine.recordAcceptance(@as(u64, i), @as(u64, i) + 1000, .explicit_cast, true);
    }

    // Preference for casts should increase
    try std.testing.expect(engine.preferences.prefers_explicit_casts > 0.5);
}

test "computeErrorPattern produces consistent hashes" {
    const hash1 = FixLearningEngine.computeErrorPattern(
        DiagnosticCode.semantic(.dispatch_ambiguous),
        .ambiguous_dispatch,
        12345,
    );

    const hash2 = FixLearningEngine.computeErrorPattern(
        DiagnosticCode.semantic(.dispatch_ambiguous),
        .ambiguous_dispatch,
        12345,
    );

    try std.testing.expectEqual(hash1, hash2);

    // Different inputs should produce different hashes
    const hash3 = FixLearningEngine.computeErrorPattern(
        DiagnosticCode.semantic(.type_mismatch),
        .type_mismatch,
        12345,
    );

    try std.testing.expect(hash1 != hash3);
}

test "rankFixes orders by adjusted confidence" {
    const allocator = std.testing.allocator;

    var engine = FixLearningEngine.initWithConfig(allocator, .{
        .enable_persistence = false,
    });
    defer engine.deinit();

    // Record high acceptance for fix 1 (multiple times to build history)
    for (0..5) |_| {
        try engine.recordSuggestion(100, 1, .explicit_cast);
        try engine.recordAcceptance(100, 1, .explicit_cast, true);
    }

    var fixes = [_]FixInfo{
        // Fix 2 has higher base but no acceptance history
        .{ .fix_pattern = 2, .category = .import_statement, .base_confidence = 0.6, .adjusted_confidence = 0, .description = "fix2" },
        // Fix 1 has lower base but strong acceptance history (100% acceptance rate)
        .{ .fix_pattern = 1, .category = .explicit_cast, .base_confidence = 0.5, .adjusted_confidence = 0, .description = "fix1" },
    };

    rankFixes(&engine, 100, &fixes);

    // Fix 1 should be first because acceptance boost (0.5 + 1.0*0.2 = 0.7) beats fix 2 (0.6)
    try std.testing.expectEqual(@as(u64, 1), fixes[0].fix_pattern);
}
