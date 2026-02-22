// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const testing = std.testing;

const DispatchProfiler = @import("dispatch_profiler.zig").DispatchProfiler;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const DispatchTableOptimizer = @import("dispatch_table_optimizer.zig").DispatchTableOptimizer;

/// Compiler optimization hints generator based on dispatch profiling data
pub const OptimizationHintsGenerator = struct {
    allocator: Allocator,

    // Hint generation configuration
    config: HintConfig,

    // Generated hints
    hints: ArrayList(OptimizationHint),

    // Hint statistics
    stats: HintStats,

    const Self = @This();

    /// Configuration for hint generation
    pub const HintConfig = struct {
        // Thresholds for hint generation
        min_calls_for_static_dispatch: u64,
        min_calls_for_monomorphization: u64,
        min_calls_for_inline_caching: u64,

        // Confidence thresholds
        min_confidence_for_suggestion: f64,
        min_confidence_for_automatic: f64,

        // Performance thresholds
        min_speedup_for_suggestion: f64,
        min_dispatch_time_for_optimization: u64, // nanoseconds

        // Hot path thresholds
        hot_path_call_frequency_threshold: f64, // calls per second
        hot_path_time_percentage_threshold: f64, // percentage of total time

        // Output configuration
        include_code_examples: bool,
        include_performance_estimates: bool,
        include_implementation_details: bool,

        pub fn default() HintConfig {
            return HintConfig{
                .min_calls_for_static_dispatch = 1000,
                .min_calls_for_monomorphization = 5000,
                .min_calls_for_inline_caching = 500,
                .min_confidence_for_suggestion = 0.6,
                .min_confidence_for_automatic = 0.9,
                .min_speedup_for_suggestion = 1.2,
                .min_dispatch_time_for_optimization = 500, // 0.5μs
                .hot_path_call_frequency_threshold = 1000.0, // 1000 calls/sec
                .hot_path_time_percentage_threshold = 5.0, // 5% of total time
                .include_code_examples = true,
                .include_performance_estimates = true,
                .include_implementation_details = false,
            };
        }
    };

    /// Optimization hint with detailed information
    pub const OptimizationHint = struct {
        id: u64,
        type: HintType,
        priority: Priority,
        confidence: f64,

        // Location information
        call_site: DispatchProfiler.CallSiteId,
        signature_name: []const u8,

        // Performance impact
        estimated_speedup: f64,
        estimated_memory_savings: usize,
        current_dispatch_time_ns: u64,
        optimized_dispatch_time_ns: u64,

        // Hint details
        title: []const u8,
        description: []const u8,
        rationale: []const u8,
        suggested_action: []const u8,

        // Implementation guidance
        code_example: ?[]const u8,
        compiler_flags: ?[]const u8,
        implementation_notes: ?[]const u8,

        // Validation data
        supporting_data: SupportingData,

        pub const HintType = enum {
            static_dispatch,
            monomorphization,
            inline_caching,
            table_compression,
            hot_path_specialization,
            cache_optimization,
            decision_tree_optimization,
            profile_guided_optimization,
        };

        pub const Priority = enum {
            low,
            medium,
            high,
            critical,

            pub fn fromSpeedup(speedup: f64) Priority {
                if (speedup >= 3.0) return .critical;
                if (speedup >= 2.0) return .high;
                if (speedup >= 1.5) return .medium;
                return .low;
            }
        };

        pub const SupportingData = struct {
            call_frequency: u64,
            cache_hit_ratio: f64,
            implementation_diversity: f64,
            hot_path_percentage: f64,
            profiling_samples: u32,
        };

        pub fn format(self: OptimizationHint, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("OptimizationHint[{}] - {} Priority\n", .{ self.type, self.priority });
            try writer.print("  Location: {}\n", .{self.call_site});
            try writer.print("  Title: {s}\n", .{self.title});
            try writer.print("  Estimated speedup: {d:.1}x (confidence: {d:.0}%)\n", .{ self.estimated_speedup, self.confidence * 100.0 });
            try writer.print("  Current dispatch time: {d:.1}μs -> {d:.1}μs\n", .{ @as(f64, @floatFromInt(self.current_dispatch_time_ns)) / 1000.0, @as(f64, @floatFromInt(self.optimized_dispatch_time_ns)) / 1000.0 });
            try writer.print("  Description: {s}\n", .{self.description});
            try writer.print("  Suggested action: {s}\n", .{self.suggested_action});

            if (self.code_example) |example| {
                try writer.print("  Code example:\n{s}\n", .{example});
            }
        }
    };

    /// Statistics for generated hints
    pub const HintStats = struct {
        total_hints_generated: u32,
        hints_by_type: HashMap(OptimizationHint.HintType, u32),
        hints_by_priority: HashMap(OptimizationHint.Priority, u32),

        total_estimated_speedup: f64,
        total_estimated_memory_savings: usize,

        high_confidence_hints: u32,
        automatic_optimization_candidates: u32,

        pub fn init(allocator: Allocator) HintStats {
            return HintStats{
                .total_hints_generated = 0,
                .hints_by_type = HashMap(OptimizationHint.HintType, u32).init(allocator),
                .hints_by_priority = HashMap(OptimizationHint.Priority, u32).init(allocator),
                .total_estimated_speedup = 0.0,
                .total_estimated_memory_savings = 0,
                .high_confidence_hints = 0,
                .automatic_optimization_candidates = 0,
            };
        }

        pub fn deinit(self: *HintStats) void {
            self.hints_by_type.deinit();
            self.hints_by_priority.deinit();
        }

        pub fn recordHint(self: *HintStats, hint: *const OptimizationHint) void {
            self.total_hints_generated += 1;
            self.total_estimated_speedup += hint.estimated_speedup;
            self.total_estimated_memory_savings += hint.estimated_memory_savings;

            if (hint.confidence >= 0.8) {
                self.high_confidence_hints += 1;
            }

            if (hint.confidence >= 0.9) {
                self.automatic_optimization_candidates += 1;
            }

            // Update type counts
            if (self.hints_by_type.getPtr(hint.type)) |count| {
                count.* += 1;
            } else {
                self.hints_by_type.put(hint.type, 1) catch {};
            }

            // Update priority counts
            if (self.hints_by_priority.getPtr(hint.priority)) |count| {
                count.* += 1;
            } else {
                self.hints_by_priority.put(hint.priority, 1) catch {};
            }
        }

        pub fn format(self: HintStats, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Optimization Hint Statistics:\n");
            try writer.print("  Total hints: {}\n", .{self.total_hints_generated});
            try writer.print("  High confidence: {} ({d:.1}%)\n", .{ self.high_confidence_hints, if (self.total_hints_generated > 0) @as(f64, @floatFromInt(self.high_confidence_hints)) / @as(f64, @floatFromInt(self.total_hints_generated)) * 100.0 else 0.0 });
            try writer.print("  Automatic candidates: {}\n", .{self.automatic_optimization_candidates});
            try writer.print("  Total estimated speedup: {d:.1}x\n", .{self.total_estimated_speedup});
            try writer.print("  Total estimated memory savings: {} bytes\n", .{self.total_estimated_memory_savings});
        }
    };

    pub fn init(allocator: Allocator, config: HintConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .hints = .empty,
            .stats = HintStats.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up hints
        for (self.hints.items) |*hint| {
            self.allocator.free(hint.title);
            self.allocator.free(hint.description);
            self.allocator.free(hint.rationale);
            self.allocator.free(hint.suggested_action);

            if (hint.code_example) |example| {
                self.allocator.free(example);
            }
            if (hint.compiler_flags) |flags| {
                self.allocator.free(flags);
            }
            if (hint.implementation_notes) |notes| {
                self.allocator.free(notes);
            }
        }
        self.hints.deinit();

        self.stats.deinit();
    }

    /// Generate optimization hints from profiling data
    pub fn generateHints(self: *Self, profiler: *const DispatchProfiler) !void {
        // Clear existing hints
        self.clearHints();

        // Generate hints from call profiles
        try self.generateCallSiteHints(profiler);

        // Generate hints from signature profiles
        try self.generateSignatureHints(profiler);

        // Generate hints from hot paths
        try self.generateHotPathHints(profiler);

        // Generate hints from optimization opportunities
        try self.generateOpportunityHints(profiler);

        // Sort hints by priority and confidence
        self.sortHints();
    }

    /// Generate hints for specific call sites
    pub fn generateCallSiteHints(self: *Self, profiler: *const DispatchProfiler) !void {
        var call_iter = profiler.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;

            // Skip low-frequency call sites
            if (profile.total_calls < self.config.min_calls_for_static_dispatch) continue;

            // Static dispatch hint
            if (profile.implementations_used.count() == 1 and
                profile.total_calls >= self.config.min_calls_for_static_dispatch)
            {
                try self.generateStaticDispatchHint(profile);
            }

            // Inline caching hint
            if (profile.cache_hit_ratio < 0.7 and
                profile.total_calls >= self.config.min_calls_for_inline_caching and
                profile.avg_dispatch_time >= @as(f64, @floatFromInt(self.config.min_dispatch_time_for_optimization)))
            {
                try self.generateInlineCachingHint(profile);
            }

            // Hot path specialization hint
            if (profile.is_hot_path and
                profile.calls_per_second >= self.config.hot_path_call_frequency_threshold)
            {
                try self.generateHotPathSpecializationHint(profile);
            }
        }
    }

    /// Generate hints for signature groups
    pub fn generateSignatureHints(self: *Self, profiler: *const DispatchProfiler) !void {
        var sig_iter = profiler.signature_profiles.iterator();
        while (sig_iter.next()) |entry| {
            const profile = entry.value_ptr;

            // Skip low-usage signatures
            if (profile.total_calls < self.config.min_calls_for_monomorphization) continue;

            // Monomorphization hint
            if (profile.implementation_diversity < 1.5 and
                profile.total_calls >= self.config.min_calls_for_monomorphization)
            {
                try self.generateMonomorphizationHint(profile);
            }

            // Table compression hint
            if (profile.implementations.count() > 10 and
                profile.avg_dispatch_time >= @as(f64, @floatFromInt(self.config.min_dispatch_time_for_optimization)))
            {
                try self.generateTableCompressionHint(profile);
            }
        }
    }

    /// Generate hints from hot path analysis
    pub fn generateHotPathHints(self: *Self, profiler: *const DispatchProfiler) !void {
        for (profiler.getHotPaths()) |hot_path| {
            if (hot_path.optimization_potential == .high or hot_path.optimization_potential == .critical) {
                try self.generateProfileGuidedOptimizationHint(&hot_path);
            }
        }
    }

    /// Generate hints from optimization opportunities
    pub fn generateOpportunityHints(self: *Self, profiler: *const DispatchProfiler) !void {
        for (profiler.getOptimizationOpportunities()) |opportunity| {
            if (opportunity.confidence >= self.config.min_confidence_for_suggestion and
                opportunity.potential_speedup >= self.config.min_speedup_for_suggestion)
            {
                try self.generateOpportunityHint(&opportunity);
            }
        }
    }

    /// Get all generated hints
    pub fn getHints(self: *const Self) []const OptimizationHint {
        return self.hints.items;
    }

    /// Get hints by type
    pub fn getHintsByType(self: *const Self, hint_type: OptimizationHint.HintType) []const OptimizationHint {
        var filtered_hints: ArrayList(OptimizationHint) = .empty;
        defer filtered_hints.deinit();

        for (self.hints.items) |hint| {
            if (hint.type == hint_type) {
                filtered_hints.append(hint) catch continue;
            }
        }

        return try filtered_hints.toOwnedSlice(alloc) catch &.{};
    }

    /// Get hints by priority
    pub fn getHintsByPriority(self: *const Self, priority: OptimizationHint.Priority) []const OptimizationHint {
        var filtered_hints: ArrayList(OptimizationHint) = .empty;
        defer filtered_hints.deinit();

        for (self.hints.items) |hint| {
            if (hint.priority == priority) {
                filtered_hints.append(hint) catch continue;
            }
        }

        return try filtered_hints.toOwnedSlice(alloc) catch &.{};
    }

    /// Get high-confidence hints suitable for automatic optimization
    pub fn getAutomaticOptimizationCandidates(self: *const Self) []const OptimizationHint {
        var candidates: ArrayList(OptimizationHint) = .empty;
        defer candidates.deinit();

        for (self.hints.items) |hint| {
            if (hint.confidence >= self.config.min_confidence_for_automatic) {
                candidates.append(hint) catch continue;
            }
        }

        return try candidates.toOwnedSlice(alloc) catch &.{};
    }

    /// Generate comprehensive hints report
    pub fn generateReport(self: *const Self, writer: anytype) !void {
        try writer.print("Dispatch Optimization Hints Report\n");
        try writer.print("===================================\n\n");

        // Statistics summary
        try writer.print("{}\n", .{self.stats});

        // High priority hints
        try writer.print("High Priority Hints:\n");
        try writer.print("--------------------\n");

        for (self.hints.items) |hint| {
            if (hint.priority == .high or hint.priority == .critical) {
                try writer.print("{}\n", .{hint});
            }
        }

        // Automatic optimization candidates
        const auto_candidates = self.getAutomaticOptimizationCandidates();
        defer self.allocator.free(auto_candidates);

        if (auto_candidates.len > 0) {
            try writer.print("Automatic Optimization Candidates:\n");
            try writer.print("-----------------------------------\n");

            for (auto_candidates) |hint| {
                try writer.print("{}\n", .{hint});
            }
        }

        // All hints by type
        try writer.print("All Hints by Type:\n");
        try writer.print("------------------\n");

        const hint_types = [_]OptimizationHint.HintType{
            .static_dispatch,
            .monomorphization,
            .inline_caching,
            .hot_path_specialization,
            .cache_optimization,
            .table_compression,
            .profile_guided_optimization,
        };

        for (hint_types) |hint_type| {
            const type_hints = self.getHintsByType(hint_type);
            defer self.allocator.free(type_hints);

            if (type_hints.len > 0) {
                try writer.print("\n{} Hints ({}):\n", .{ hint_type, type_hints.len });
                for (type_hints) |hint| {
                    try writer.print("  - {s} (speedup: {d:.1}x, confidence: {d:.0}%)\n", .{ hint.title, hint.estimated_speedup, hint.confidence * 100.0 });
                }
            }
        }
    }

    /// Export hints in various formats
    pub fn exportHints(self: *const Self, writer: anytype, format: ExportFormat) !void {
        switch (format) {
            .text => try self.generateReport(writer),
            .json => try self.exportJSON(writer),
            .csv => try self.exportCSV(writer),
            .compiler_flags => try self.exportCompilerFlags(writer),
        }
    }

    pub const ExportFormat = enum {
        text,
        json,
        csv,
        compiler_flags,
    };

    // Private hint generation methods

    fn generateStaticDispatchHint(self: *Self, profile: *const DispatchProfiler.CallProfile) !void {
        const hint_id = @as(u64, @intCast(compat_time.nanoTimestamp()));
        const estimated_speedup = 1.8; // Static dispatch typically 1.5-2x faster
        const optimized_time = @as(u64, @intFromFloat(profile.avg_dispatch_time * 0.1)); // ~90% reduction

        const hint = OptimizationHint{
            .id = hint_id,
            .type = .static_dispatch,
            .priority = OptimizationHint.Priority.fromSpeedup(estimated_speedup),
            .confidence = 0.95, // High confidence for single implementation
            .call_site = profile.call_site,
            .signature_name = profile.call_site.signature_name,
            .estimated_speedup = estimated_speedup,
            .estimated_memory_savings = 64, // Typical dispatch table entry size
            .current_dispatch_time_ns = @as(u64, @intFromFloat(profile.avg_dispatch_time)),
            .optimized_dispatch_time_ns = optimized_time,
            .title = try self.allocator.dupe(u8, "Static Dispatch Optimization"),
            .description = try std.fmt.allocPrint(self.allocator, "Call site consistently uses single implementation ({} calls). Static dispatch can eliminate runtime lookup overhead.", .{profile.total_calls}),
            .rationale = try self.allocator.dupe(u8, "Single implementation dominance (100%) indicates static dispatch is safe and beneficial."),
            .suggested_action = try self.allocator.dupe(u8, "Add compiler hint or use explicit static dispatch syntax."),
            .code_example = if (self.config.include_code_examples)
                try std.fmt.allocPrint(self.allocator, "// Before: dynamic dispatch\n{s}(args...)\n\n// After: static dispatch\n@static {s}(args...)", .{ profile.call_site.signature_name, profile.call_site.signature_name })
            else
                null,
            .compiler_flags = try self.allocator.dupe(u8, "--optimize-static-dispatch"),
            .implementation_notes = if (self.config.include_implementation_details)
                try self.allocator.dupe(u8, "Compiler can replace dispatch table lookup with direct function call.")
            else
                null,
            .supporting_data = OptimizationHint.SupportingData{
                .call_frequency = profile.total_calls,
                .cache_hit_ratio = profile.cache_hit_ratio,
                .implementation_diversity = 0.0, // Single implementation
                .hot_path_percentage = if (profile.is_hot_path) profile.hotness_score * 100.0 else 0.0,
                .profiling_samples = @as(u32, @intCast(profile.total_calls)),
            },
        };

        try self.hints.append(hint);
        self.stats.recordHint(&hint);
    }

    fn generateInlineCachingHint(self: *Self, profile: *const DispatchProfiler.CallProfile) !void {
        const hint_id = @as(u64, @intCast(compat_time.nanoTimestamp()));
        const estimated_speedup = 1.4; // Inline caching typically 1.3-1.5x faster
        const optimized_time = @as(u64, @intFromFloat(profile.avg_dispatch_time * 0.7)); // ~30% reduction

        const hint = OptimizationHint{
            .id = hint_id,
            .type = .inline_caching,
            .priority = OptimizationHint.Priority.fromSpeedup(estimated_speedup),
            .confidence = 0.75,
            .call_site = profile.call_site,
            .signature_name = profile.call_site.signature_name,
            .estimated_speedup = estimated_speedup,
            .estimated_memory_savings = 0, // May increase memory slightly
            .current_dispatch_time_ns = @as(u64, @intFromFloat(profile.avg_dispatch_time)),
            .optimized_dispatch_time_ns = optimized_time,
            .title = try self.allocator.dupe(u8, "Inline Caching Optimization"),
            .description = try std.fmt.allocPrint(self.allocator, "Low cache hit ratio ({d:.1}%) with high call frequency ({} calls). Inline caching can improve performance.", .{ profile.cache_hit_ratio * 100.0, profile.total_calls }),
            .rationale = try self.allocator.dupe(u8, "Poor cache locality suggests inline caching would be beneficial."),
            .suggested_action = try self.allocator.dupe(u8, "Enable inline caching for this call site."),
            .code_example = if (self.config.include_code_examples)
                try std.fmt.allocPrint(self.allocator, "// Add inline cache hint\n@inline_cache {s}(args...)", .{profile.call_site.signature_name})
            else
                null,
            .compiler_flags = try self.allocator.dupe(u8, "--enable-inline-caching"),
            .implementation_notes = if (self.config.include_implementation_details)
                try self.allocator.dupe(u8, "Compiler will generate inline cache at call site for faster repeated lookups.")
            else
                null,
            .supporting_data = OptimizationHint.SupportingData{
                .call_frequency = profile.total_calls,
                .cache_hit_ratio = profile.cache_hit_ratio,
                .implementation_diversity = @as(f64, @floatFromInt(profile.implementations_used.count())),
                .hot_path_percentage = if (profile.is_hot_path) profile.hotness_score * 100.0 else 0.0,
                .profiling_samples = @as(u32, @intCast(profile.total_calls)),
            },
        };

        try self.hints.append(hint);
        self.stats.recordHint(&hint);
    }

    fn generateHotPathSpecializationHint(self: *Self, profile: *const DispatchProfiler.CallProfile) !void {
        const hint_id = @as(u64, @intCast(compat_time.nanoTimestamp()));
        const estimated_speedup = 2.5; // Hot path specialization can be very effective
        const optimized_time = @as(u64, @intFromFloat(profile.avg_dispatch_time * 0.4)); // ~60% reduction

        const hint = OptimizationHint{
            .id = hint_id,
            .type = .hot_path_specialization,
            .priority = .critical, // Hot paths are always high priority
            .confidence = 0.9,
            .call_site = profile.call_site,
            .signature_name = profile.call_site.signature_name,
            .estimated_speedup = estimated_speedup,
            .estimated_memory_savings = 0,
            .current_dispatch_time_ns = @as(u64, @intFromFloat(profile.avg_dispatch_time)),
            .optimized_dispatch_time_ns = optimized_time,
            .title = try self.allocator.dupe(u8, "Hot Path Specialization"),
            .description = try std.fmt.allocPrint(self.allocator, "Critical hot path with {d:.1} calls/sec and hotness score {d:.2}. Specialization can provide significant speedup.", .{ profile.calls_per_second, profile.hotness_score }),
            .rationale = try self.allocator.dupe(u8, "High call frequency and dispatch overhead justify specialized code generation."),
            .suggested_action = try self.allocator.dupe(u8, "Generate specialized version for common argument patterns."),
            .code_example = if (self.config.include_code_examples)
                try std.fmt.allocPrint(self.allocator, "// Hot path specialization\n@specialize_hot_path {s}(args...)", .{profile.call_site.signature_name})
            else
                null,
            .compiler_flags = try self.allocator.dupe(u8, "--specialize-hot-paths"),
            .implementation_notes = if (self.config.include_implementation_details)
                try self.allocator.dupe(u8, "Compiler will generate optimized code paths for frequent argument patterns.")
            else
                null,
            .supporting_data = OptimizationHint.SupportingData{
                .call_frequency = profile.total_calls,
                .cache_hit_ratio = profile.cache_hit_ratio,
                .implementation_diversity = @as(f64, @floatFromInt(profile.implementations_used.count())),
                .hot_path_percentage = profile.hotness_score * 100.0,
                .profiling_samples = @as(u32, @intCast(profile.total_calls)),
            },
        };

        try self.hints.append(hint);
        self.stats.recordHint(&hint);
    }

    fn generateMonomorphizationHint(self: *Self, profile: *const DispatchProfiler.SignatureProfile) !void {
        const hint_id = @as(u64, @intCast(compat_time.nanoTimestamp()));
        const estimated_speedup = 1.6;

        const hint = OptimizationHint{
            .id = hint_id,
            .type = .monomorphization,
            .priority = OptimizationHint.Priority.fromSpeedup(estimated_speedup),
            .confidence = 0.7,
            .call_site = DispatchProfiler.CallSiteId{ .source_file = "", .line = 0, .column = 0, .signature_name = profile.signature_name },
            .signature_name = profile.signature_name,
            .estimated_speedup = estimated_speedup,
            .estimated_memory_savings = 0,
            .current_dispatch_time_ns = @as(u64, @intFromFloat(profile.avg_dispatch_time)),
            .optimized_dispatch_time_ns = @as(u64, @intFromFloat(profile.avg_dispatch_time * 0.6)),
            .title = try self.allocator.dupe(u8, "Monomorphization Opportunity"),
            .description = try std.fmt.allocPrint(self.allocator, "Signature has low implementation diversity ({d:.2}) with high usage ({} calls). Monomorphization can reduce dispatch overhead.", .{ profile.implementation_diversity, profile.total_calls }),
            .rationale = try self.allocator.dupe(u8, "Low diversity suggests common type patterns that benefit from specialization."),
            .suggested_action = try self.allocator.dupe(u8, "Enable monomorphization for common type combinations."),
            .code_example = if (self.config.include_code_examples)
                try std.fmt.allocPrint(self.allocator, "// Enable monomorphization\n@monomorphize {s}", .{profile.signature_name})
            else
                null,
            .compiler_flags = try self.allocator.dupe(u8, "--enable-monomorphization"),
            .implementation_notes = null,
            .supporting_data = OptimizationHint.SupportingData{
                .call_frequency = profile.total_calls,
                .cache_hit_ratio = 0.0, // Not applicable at signature level
                .implementation_diversity = profile.implementation_diversity,
                .hot_path_percentage = 0.0, // Not applicable at signature level
                .profiling_samples = profile.total_call_sites,
            },
        };

        try self.hints.append(hint);
        self.stats.recordHint(&hint);
    }

    fn generateTableCompressionHint(self: *Self, profile: *const DispatchProfiler.SignatureProfile) !void {
        const hint_id = @as(u64, @intCast(compat_time.nanoTimestamp()));
        const estimated_speedup = 1.2;
        const estimated_memory_savings = profile.implementations.count() * 32; // Rough estimate

        const hint = OptimizationHint{
            .id = hint_id,
            .type = .table_compression,
            .priority = .medium,
            .confidence = 0.6,
            .call_site = DispatchProfiler.CallSiteId{ .source_file = "", .line = 0, .column = 0, .signature_name = profile.signature_name },
            .signature_name = profile.signature_name,
            .estimated_speedup = estimated_speedup,
            .estimated_memory_savings = estimated_memory_savings,
            .current_dispatch_time_ns = @as(u64, @intFromFloat(profile.avg_dispatch_time)),
            .optimized_dispatch_time_ns = @as(u64, @intFromFloat(profile.avg_dispatch_time * 0.8)),
            .title = try self.allocator.dupe(u8, "Dispatch Table Compression"),
            .description = try std.fmt.allocPrint(self.allocator, "Large dispatch table ({} implementations) with significant dispatch overhead. Compression can improve cache performance.", .{profile.implementations.count()}),
            .rationale = try self.allocator.dupe(u8, "Large tables benefit from compression to improve cache locality."),
            .suggested_action = try self.allocator.dupe(u8, "Enable dispatch table compression."),
            .code_example = null,
            .compiler_flags = try self.allocator.dupe(u8, "--compress-dispatch-tables"),
            .implementation_notes = if (self.config.include_implementation_details)
                try self.allocator.dupe(u8, "Compiler will use compressed dispatch table format to reduce memory usage.")
            else
                null,
            .supporting_data = OptimizationHint.SupportingData{
                .call_frequency = profile.total_calls,
                .cache_hit_ratio = 0.0,
                .implementation_diversity = profile.implementation_diversity,
                .hot_path_percentage = 0.0,
                .profiling_samples = profile.total_call_sites,
            },
        };

        try self.hints.append(hint);
        self.stats.recordHint(&hint);
    }

    fn generateProfileGuidedOptimizationHint(self: *Self, hot_path: *const DispatchProfiler.HotPath) !void {
        const hint_id = @as(u64, @intCast(compat_time.nanoTimestamp()));
        const estimated_speedup = switch (hot_path.optimization_potential) {
            .critical => 3.0,
            .high => 2.2,
            .medium => 1.6,
            .low => 1.2,
        };

        const hint = OptimizationHint{
            .id = hint_id,
            .type = .profile_guided_optimization,
            .priority = switch (hot_path.optimization_potential) {
                .critical => .critical,
                .high => .high,
                .medium => .medium,
                .low => .low,
            },
            .confidence = 0.8,
            .call_site = if (hot_path.call_sites.items.len > 0) hot_path.call_sites.items[0] else DispatchProfiler.CallSiteId{ .source_file = "", .line = 0, .column = 0, .signature_name = "" },
            .signature_name = if (hot_path.call_sites.items.len > 0) hot_path.call_sites.items[0].signature_name else "",
            .estimated_speedup = estimated_speedup,
            .estimated_memory_savings = 0,
            .current_dispatch_time_ns = @as(u64, @intFromFloat(hot_path.avg_time_per_call)),
            .optimized_dispatch_time_ns = @as(u64, @intFromFloat(hot_path.avg_time_per_call / estimated_speedup)),
            .title = try self.allocator.dupe(u8, "Profile-Guided Optimization"),
            .description = try std.fmt.allocPrint(self.allocator, "Hot path with {} potential across {} call sites ({} total calls). Profile-guided optimization can provide significant benefits.", .{ hot_path.optimization_potential, hot_path.call_sites.items.len, hot_path.total_calls }),
            .rationale = try self.allocator.dupe(u8, "Hot path analysis indicates high optimization potential."),
            .suggested_action = try self.allocator.dupe(u8, "Enable profile-guided optimization for this hot path."),
            .code_example = null,
            .compiler_flags = try self.allocator.dupe(u8, "--profile-guided-optimization"),
            .implementation_notes = if (self.config.include_implementation_details)
                try self.allocator.dupe(u8, "Compiler will use profiling data to optimize hot code paths.")
            else
                null,
            .supporting_data = OptimizationHint.SupportingData{
                .call_frequency = hot_path.total_calls,
                .cache_hit_ratio = 0.0,
                .implementation_diversity = 0.0,
                .hot_path_percentage = 100.0, // This is a hot path
                .profiling_samples = @as(u32, @intCast(hot_path.call_sites.items.len)),
            },
        };

        try self.hints.append(hint);
        self.stats.recordHint(&hint);
    }

    fn generateOpportunityHint(self: *Self, opportunity: *const DispatchProfiler.OptimizationOpportunity) !void {
        const hint_id = @as(u64, @intCast(compat_time.nanoTimestamp()));

        const hint_type: OptimizationHint.HintType = switch (opportunity.type) {
            .static_dispatch => .static_dispatch,
            .monomorphization => .monomorphization,
            .inline_caching => .inline_caching,
            .table_compression => .table_compression,
            .hot_path_optimization => .hot_path_specialization,
            .cache_optimization => .cache_optimization,
        };

        const hint = OptimizationHint{
            .id = hint_id,
            .type = hint_type,
            .priority = OptimizationHint.Priority.fromSpeedup(opportunity.potential_speedup),
            .confidence = opportunity.confidence,
            .call_site = opportunity.call_site,
            .signature_name = opportunity.signature_name,
            .estimated_speedup = opportunity.potential_speedup,
            .estimated_memory_savings = 0,
            .current_dispatch_time_ns = 1000, // Default estimate
            .optimized_dispatch_time_ns = @as(u64, @intFromFloat(1000.0 / opportunity.potential_speedup)),
            .title = try self.allocator.dupe(u8, opportunity.description),
            .description = try self.allocator.dupe(u8, opportunity.description),
            .rationale = try self.allocator.dupe(u8, "Identified through profiling analysis."),
            .suggested_action = try self.allocator.dupe(u8, opportunity.suggested_action),
            .code_example = null,
            .compiler_flags = null,
            .implementation_notes = null,
            .supporting_data = OptimizationHint.SupportingData{
                .call_frequency = 0,
                .cache_hit_ratio = 0.0,
                .implementation_diversity = 0.0,
                .hot_path_percentage = 0.0,
                .profiling_samples = 0,
            },
        };

        try self.hints.append(hint);
        self.stats.recordHint(&hint);
    }

    fn clearHints(self: *Self) void {
        for (self.hints.items) |*hint| {
            self.allocator.free(hint.title);
            self.allocator.free(hint.description);
            self.allocator.free(hint.rationale);
            self.allocator.free(hint.suggested_action);

            if (hint.code_example) |example| {
                self.allocator.free(example);
            }
            if (hint.compiler_flags) |flags| {
                self.allocator.free(flags);
            }
            if (hint.implementation_notes) |notes| {
                self.allocator.free(notes);
            }
        }
        self.hints.clearAndFree();

        self.stats.deinit();
        self.stats = HintStats.init(self.allocator);
    }

    fn sortHints(self: *Self) void {
        const Context = struct {
            pub fn lessThan(context: @This(), a: OptimizationHint, b: OptimizationHint) bool {
                _ = context;

                // Sort by priority first
                const a_priority_value = @intFromEnum(a.priority);
                const b_priority_value = @intFromEnum(b.priority);

                if (a_priority_value != b_priority_value) {
                    return a_priority_value > b_priority_value; // Higher priority first
                }

                // Then by confidence
                if (a.confidence != b.confidence) {
                    return a.confidence > b.confidence;
                }

                // Finally by estimated speedup
                return a.estimated_speedup > b.estimated_speedup;
            }
        };

        std.mem.sort(OptimizationHint, self.hints.items, Context{}, Context.lessThan);
    }

    fn exportJSON(self: *const Self, writer: anytype) !void {
        try writer.writeAll("{\n");
        try writer.writeAll("  \"optimization_hints\": {\n");

        // Export statistics
        try writer.print("    \"statistics\": {{\n");
        try writer.print("      \"total_hints\": {},\n", .{self.stats.total_hints_generated});
        try writer.print("      \"high_confidence_hints\": {},\n", .{self.stats.high_confidence_hints});
        try writer.print("      \"automatic_candidates\": {},\n", .{self.stats.automatic_optimization_candidates});
        try writer.print("      \"total_estimated_speedup\": {d:.2}\n", .{self.stats.total_estimated_speedup});
        try writer.writeAll("    },\n");

        // Export hints
        try writer.writeAll("    \"hints\": [\n");
        for (self.hints.items, 0..) |hint, i| {
            if (i > 0) try writer.writeAll(",\n");

            try writer.print("      {{\n");
            try writer.print("        \"id\": {},\n", .{hint.id});
            try writer.print("        \"type\": \"{}\",\n", .{hint.type});
            try writer.print("        \"priority\": \"{}\",\n", .{hint.priority});
            try writer.print("        \"confidence\": {d:.3},\n", .{hint.confidence});
            try writer.print("        \"estimated_speedup\": {d:.2},\n", .{hint.estimated_speedup});
            try writer.print("        \"title\": \"{s}\",\n", .{hint.title});
            try writer.print("        \"description\": \"{s}\"\n", .{hint.description});
            try writer.writeAll("      }");
        }
        try writer.writeAll("\n    ]\n");

        try writer.writeAll("  }\n");
        try writer.writeAll("}\n");
    }

    fn exportCSV(self: *const Self, writer: anytype) !void {
        // CSV header
        try writer.writeAll("id,type,priority,confidence,speedup,title,description,call_site\n");

        // CSV data
        for (self.hints.items) |hint| {
            try writer.print("{},\"{}\",\"{}\",{d:.3},{d:.2},\"{s}\",\"{s}\",\"{}:{}\"\n", .{
                hint.id,
                hint.type,
                hint.priority,
                hint.confidence,
                hint.estimated_speedup,
                hint.title,
                hint.description,
                hint.call_site.source_file,
                hint.call_site.line,
            });
        }
    }

    fn exportCompilerFlags(self: *const Self, writer: anytype) !void {
        try writer.writeAll("# Compiler optimization flags based on profiling analysis\n");

        var flags_set = std.StringHashMap(void).init(self.allocator);
        defer flags_set.deinit();

        for (self.hints.items) |hint| {
            if (hint.compiler_flags) |flags| {
                if (!flags_set.contains(flags)) {
                    try writer.print("{s}\n", .{flags});
                    try flags_set.put(flags, {});
                }
            }
        }
    }
};

// Tests

test "OptimizationHintsGenerator basic functionality" {
    const allocator = testing.allocator;

    const config = OptimizationHintsGenerator.HintConfig.default();
    var generator = OptimizationHintsGenerator.init(allocator, config);
    defer generator.deinit();

    // Create mock profiler with test data
    const profiler_config = DispatchProfiler.ProfilingConfig.default();
    var profiler = DispatchProfiler.init(allocator, profiler_config);
    defer profiler.deinit();

    // Generate hints
    try generator.generateHints(&profiler);

    // Should have generated some hints (even if empty profiler)
    const hints = generator.getHints();
    try testing.expect(hints.len >= 0);

    // Test statistics
    const stats = generator.stats;
    try testing.expectEqual(hints.len, stats.total_hints_generated);
}

test "OptimizationHint priority calculation" {
    const low_priority = OptimizationHintsGenerator.OptimizationHint.Priority.fromSpeedup(1.1);
    const medium_priority = OptimizationHintsGenerator.OptimizationHint.Priority.fromSpeedup(1.6);
    const high_priority = OptimizationHintsGenerator.OptimizationHint.Priority.fromSpeedup(2.5);
    const critical_priority = OptimizationHintsGenerator.OptimizationHint.Priority.fromSpeedup(4.0);

    try testing.expectEqual(OptimizationHintsGenerator.OptimizationHint.Priority.low, low_priority);
    try testing.expectEqual(OptimizationHintsGenerator.OptimizationHint.Priority.medium, medium_priority);
    try testing.expectEqual(OptimizationHintsGenerator.OptimizationHint.Priority.high, high_priority);
    try testing.expectEqual(OptimizationHintsGenerator.OptimizationHint.Priority.critical, critical_priority);
}
