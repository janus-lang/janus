// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const testing = std.testing;

const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;

/// Comprehensive dispatch profiling system for performance analysis and optimization
pub const DispatchProfiler = struct {
    allocator: Allocator,

    // Profiling configuration
    config: ProfilingConfig,

    // Runtime profiling data
    call_profiles: HashMap(CallSiteId, CallProfile),
    signature_profiles: HashMap([]const u8, SignatureProfile),

    // Hot path analysis
    hot_paths: ArrayList(HotPath),
    optimization_opportunities: ArrayList(OptimizationOpportunity),

    // Performance counters
    counters: PerformanceCounters,

    // Profiling session management
    current_session: ?ProfilingSession,

    const Self = @This();

    /// Unique identifier for a dispatch call site
    pub const CallSiteId = struct {
        source_file: []const u8,
        line: u32,
        column: u32,
        signature_name: []const u8,

        pub fn hash(self: CallSiteId) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(self.source_file);
            hasher.update(std.mem.asBytes(&self.line));
            hasher.update(std.mem.asBytes(&self.column));
            hasher.update(self.signature_name);
            return hasher.final();
        }

        pub fn eql(self: CallSiteId, other: CallSiteId) bool {
            return std.mem.eql(u8, self.source_file, other.source_file) and
                self.line == other.line and
                self.column == other.column and
                std.mem.eql(u8, self.signature_name, other.signature_name);
        }

        pub fn format(self: CallSiteId, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{}:{}:{} ({})", .{ self.source_file, self.line, self.column, self.signature_name });
        }
    };

    /// Profiling data for a specific call site
    pub const CallProfile = struct {
        call_site: CallSiteId,

        // Call frequency data
        total_calls: u64,
        calls_per_second: f64,

        // Timing data (in nanoseconds)
        total_dispatch_time: u64,
        min_dispatch_time: u64,
        max_dispatch_time: u64,
        avg_dispatch_time: f64,

        // Implementation distribution
        implementations_used: HashMap(*const SignatureAnalyzer.Implementation, ImplementationStats),

        // Cache performance
        cache_hits: u64,
        cache_misses: u64,
        cache_hit_ratio: f64,

        // Hot path classification
        is_hot_path: bool,
        hotness_score: f64,

        pub const ImplementationStats = struct {
            calls: u64,
            total_time: u64,
            avg_time: f64,
            percentage: f64,
        };

        pub fn init(allocator: Allocator, call_site: CallSiteId) CallProfile {
            return CallProfile{
                .call_site = call_site,
                .total_calls = 0,
                .calls_per_second = 0.0,
                .total_dispatch_time = 0,
                .min_dispatch_time = std.math.maxInt(u64),
                .max_dispatch_time = 0,
                .avg_dispatch_time = 0.0,
                .implementations_used = HashMap(*const SignatureAnalyzer.Implementation, ImplementationStats).init(allocator),
                .cache_hits = 0,
                .cache_misses = 0,
                .cache_hit_ratio = 0.0,
                .is_hot_path = false,
                .hotness_score = 0.0,
            };
        }

        pub fn deinit(self: *CallProfile) void {
            self.implementations_used.deinit();
        }

        pub fn recordCall(self: *CallProfile, dispatch_time_ns: u64, implementation: *const SignatureAnalyzer.Implementation, was_cache_hit: bool) void {
            // Update call frequency
            self.total_calls += 1;

            // Update timing statistics
            self.total_dispatch_time += dispatch_time_ns;
            self.min_dispatch_time = @min(self.min_dispatch_time, dispatch_time_ns);
            self.max_dispatch_time = @max(self.max_dispatch_time, dispatch_time_ns);
            self.avg_dispatch_time = @as(f64, @floatFromInt(self.total_dispatch_time)) / @as(f64, @floatFromInt(self.total_calls));

            // Update implementation statistics
            if (self.implementations_used.getPtr(implementation)) |stats| {
                stats.calls += 1;
                stats.total_time += dispatch_time_ns;
                stats.avg_time = @as(f64, @floatFromInt(stats.total_time)) / @as(f64, @floatFromInt(stats.calls));
            } else {
                const stats = ImplementationStats{
                    .calls = 1,
                    .total_time = dispatch_time_ns,
                    .avg_time = @as(f64, @floatFromInt(dispatch_time_ns)),
                    .percentage = 0.0, // Will be calculated later
                };
                self.implementations_used.put(implementation, stats) catch {};
            }

            // Update cache statistics
            if (was_cache_hit) {
                self.cache_hits += 1;
            } else {
                self.cache_misses += 1;
            }
            self.cache_hit_ratio = @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(self.total_calls));

            // Update implementation percentages
            self.updateImplementationPercentages();
        }

        pub fn calculateHotnessScore(self: *CallProfile, session_duration_ns: u64) void {
            if (session_duration_ns == 0) return;

            // Calculate calls per second
            const session_duration_s = @as(f64, @floatFromInt(session_duration_ns)) / 1_000_000_000.0;
            self.calls_per_second = @as(f64, @floatFromInt(self.total_calls)) / session_duration_s;

            // Hotness score combines frequency and dispatch cost
            const frequency_factor = @min(self.calls_per_second / 1000.0, 1.0); // Normalize to 1000 calls/sec
            const cost_factor = @min(self.avg_dispatch_time / 1000.0, 1.0); // Normalize to 1μs
            const cache_penalty = 1.0 - self.cache_hit_ratio; // Penalty for cache misses

            self.hotness_score = (frequency_factor * 0.5) + (cost_factor * 0.3) + (cache_penalty * 0.2);
            self.is_hot_path = self.hotness_score > 0.7; // Threshold for hot path classification
        }

        fn updateImplementationPercentages(self: *CallProfile) void {
            if (self.total_calls == 0) return;

            var iter = self.implementations_used.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.percentage = @as(f64, @floatFromInt(entry.value_ptr.calls)) / @as(f64, @floatFromInt(self.total_calls)) * 100.0;
            }
        }

        pub fn format(self: CallProfile, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("CallProfile[{}]:\n", .{self.call_site});
            try writer.print("  Calls: {} ({d:.1}/sec)\n", .{ self.total_calls, self.calls_per_second });
            try writer.print("  Dispatch time: {d:.1}μs avg ({d:.1}-{d:.1}μs range)\n", .{ self.avg_dispatch_time / 1000.0, @as(f64, @floatFromInt(self.min_dispatch_time)) / 1000.0, @as(f64, @floatFromInt(self.max_dispatch_time)) / 1000.0 });
            try writer.print("  Cache hit ratio: {d:.1}%\n", .{self.cache_hit_ratio * 100.0});
            try writer.print("  Hotness score: {d:.2} {s}\n", .{ self.hotness_score, if (self.is_hot_path) "(HOT)" else "" });
            try writer.print("  Implementations used: {}\n", .{self.implementations_used.count()});
        }
    };

    /// Profiling data for an entire signature group
    pub const SignatureProfile = struct {
        signature_name: []const u8,

        // Aggregate statistics
        total_calls: u64,
        total_call_sites: u32,
        avg_calls_per_site: f64,

        // Performance characteristics
        total_dispatch_time: u64,
        avg_dispatch_time: f64,
        dispatch_overhead_percentage: f64,

        // Implementation distribution
        implementations: HashMap(*const SignatureAnalyzer.Implementation, u64),
        most_used_implementation: ?*const SignatureAnalyzer.Implementation,
        implementation_diversity: f64, // Shannon entropy

        // Optimization potential
        static_dispatch_opportunities: u32,
        monomorphization_candidates: u32,

        pub fn init(allocator: Allocator, signature_name: []const u8) SignatureProfile {
            return SignatureProfile{
                .signature_name = signature_name,
                .total_calls = 0,
                .total_call_sites = 0,
                .avg_calls_per_site = 0.0,
                .total_dispatch_time = 0,
                .avg_dispatch_time = 0.0,
                .dispatch_overhead_percentage = 0.0,
                .implementations = HashMap(*const SignatureAnalyzer.Implementation, u64).init(allocator),
                .most_used_implementation = null,
                .implementation_diversity = 0.0,
                .static_dispatch_opportunities = 0,
                .monomorphization_candidates = 0,
            };
        }

        pub fn deinit(self: *SignatureProfile) void {
            self.implementations.deinit();
        }

        pub fn updateFromCallProfile(self: *SignatureProfile, call_profile: *const CallProfile) void {
            self.total_calls += call_profile.total_calls;
            self.total_call_sites += 1;
            self.total_dispatch_time += call_profile.total_dispatch_time;

            // Update implementation usage
            var impl_iter = call_profile.implementations_used.iterator();
            while (impl_iter.next()) |entry| {
                const impl = entry.key_ptr.*;
                const stats = entry.value_ptr.*;

                if (self.implementations.getPtr(impl)) |count| {
                    count.* += stats.calls;
                } else {
                    self.implementations.put(impl, stats.calls) catch {};
                }
            }

            // Recalculate derived statistics
            self.calculateDerivedStats();
        }

        fn calculateDerivedStats(self: *SignatureProfile) void {
            if (self.total_call_sites > 0) {
                self.avg_calls_per_site = @as(f64, @floatFromInt(self.total_calls)) / @as(f64, @floatFromInt(self.total_call_sites));
            }

            if (self.total_calls > 0) {
                self.avg_dispatch_time = @as(f64, @floatFromInt(self.total_dispatch_time)) / @as(f64, @floatFromInt(self.total_calls));
            }

            // Find most used implementation
            var max_usage: u64 = 0;
            var impl_iter = self.implementations.iterator();
            while (impl_iter.next()) |entry| {
                if (entry.value_ptr.* > max_usage) {
                    max_usage = entry.value_ptr.*;
                    self.most_used_implementation = entry.key_ptr.*;
                }
            }

            // Calculate implementation diversity (Shannon entropy)
            self.implementation_diversity = self.calculateShannonEntropy();

            // Identify optimization opportunities
            self.identifyOptimizationOpportunities();
        }

        fn calculateShannonEntropy(self: *SignatureProfile) f64 {
            if (self.total_calls == 0) return 0.0;

            var entropy: f64 = 0.0;
            var impl_iter = self.implementations.iterator();
            while (impl_iter.next()) |entry| {
                const probability = @as(f64, @floatFromInt(entry.value_ptr.*)) / @as(f64, @floatFromInt(self.total_calls));
                if (probability > 0.0) {
                    entropy -= probability * @log(probability) / @log(2.0);
                }
            }

            return entropy;
        }

        fn identifyOptimizationOpportunities(self: *SignatureProfile) void {
            // Static dispatch opportunities: single implementation dominates
            if (self.most_used_implementation != null) {
                const most_used_count = self.implementations.get(self.most_used_implementation.?).?;
                const dominance_ratio = @as(f64, @floatFromInt(most_used_count)) / @as(f64, @floatFromInt(self.total_calls));

                if (dominance_ratio > 0.95) {
                    self.static_dispatch_opportunities += 1;
                }
            }

            // Monomorphization candidates: low diversity, high usage
            if (self.implementation_diversity < 1.0 and self.total_calls > 1000) {
                self.monomorphization_candidates += 1;
            }
        }

        pub fn format(self: SignatureProfile, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("SignatureProfile[{}]:\n", .{self.signature_name});
            try writer.print("  Total calls: {} across {} call sites ({d:.1} avg/site)\n", .{ self.total_calls, self.total_call_sites, self.avg_calls_per_site });
            try writer.print("  Avg dispatch time: {d:.1}μs\n", .{self.avg_dispatch_time / 1000.0});
            try writer.print("  Implementations: {} (diversity: {d:.2})\n", .{ self.implementations.count(), self.implementation_diversity });
            try writer.print("  Optimization opportunities: {} static, {} monomorphization\n", .{ self.static_dispatch_opportunities, self.monomorphization_candidates });
        }
    };
    /// Hot path identification and analysis
    pub const HotPath = struct {
        call_sites: ArrayList(CallSiteId),
        total_calls: u64,
        total_time: u64,
        avg_time_per_call: f64,
        optimization_potential: OptimizationPotential,

        pub const OptimizationPotential = enum {
            low,
            medium,
            high,
            critical,
        };

        pub fn calculateOptimizationPotential(self: *HotPath) void {
            const calls_per_ms = @as(f64, @floatFromInt(self.total_calls)) / (@as(f64, @floatFromInt(self.total_time)) / 1_000_000.0);

            if (calls_per_ms > 10000) {
                self.optimization_potential = .critical;
            } else if (calls_per_ms > 1000) {
                self.optimization_potential = .high;
            } else if (calls_per_ms > 100) {
                self.optimization_potential = .medium;
            } else {
                self.optimization_potential = .low;
            }
        }

        pub fn format(self: HotPath, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("HotPath ({} potential):\n", .{self.optimization_potential});
            try writer.print("  Call sites: {}\n", .{self.call_sites.items.len});
            try writer.print("  Total calls: {} ({d:.1}μs avg)\n", .{ self.total_calls, self.avg_time_per_call / 1000.0 });
        }
    };

    /// Optimization opportunity identification
    pub const OptimizationOpportunity = struct {
        type: OpportunityType,
        call_site: CallSiteId,
        signature_name: []const u8,
        potential_speedup: f64,
        confidence: f64,
        description: []const u8,
        suggested_action: []const u8,

        pub const OpportunityType = enum {
            static_dispatch,
            monomorphization,
            inline_caching,
            table_compression,
            hot_path_optimization,
            cache_optimization,
        };

        pub fn format(self: OptimizationOpportunity, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("OptimizationOpportunity[{}]:\n", .{self.type});
            try writer.print("  Location: {}\n", .{self.call_site});
            try writer.print("  Potential speedup: {d:.1}x (confidence: {d:.0}%)\n", .{ self.potential_speedup, self.confidence * 100.0 });
            try writer.print("  Description: {s}\n", .{self.description});
            try writer.print("  Suggested action: {s}\n", .{self.suggested_action});
        }
    };

    /// Profiling configuration
    pub const ProfilingConfig = struct {
        enabled: bool,
        sample_rate: f64, // 0.0 to 1.0
        hot_path_threshold: f64,
        min_calls_for_analysis: u64,
        max_call_sites: u32,
        enable_timing: bool,
        enable_cache_tracking: bool,
        enable_implementation_tracking: bool,
        output_format: OutputFormat,

        pub const OutputFormat = enum {
            text,
            json,
            csv,
            flamegraph,
        };

        pub fn default() ProfilingConfig {
            return ProfilingConfig{
                .enabled = true,
                .sample_rate = 1.0,
                .hot_path_threshold = 0.7,
                .min_calls_for_analysis = 100,
                .max_call_sites = 10000,
                .enable_timing = true,
                .enable_cache_tracking = true,
                .enable_implementation_tracking = true,
                .output_format = .text,
            };
        }
    };

    /// Performance counters for system-wide metrics
    pub const PerformanceCounters = struct {
        total_dispatch_calls: u64,
        total_dispatch_time: u64,
        cache_hits: u64,
        cache_misses: u64,
        static_dispatches: u64,
        dynamic_dispatches: u64,

        // Timing breakdown
        lookup_time: u64,
        resolution_time: u64,
        call_time: u64,

        pub fn reset(self: *PerformanceCounters) void {
            self.* = std.mem.zeroes(PerformanceCounters);
        }

        pub fn getCacheHitRatio(self: *const PerformanceCounters) f64 {
            const total_lookups = self.cache_hits + self.cache_misses;
            if (total_lookups == 0) return 0.0;
            return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total_lookups));
        }

        pub fn getStaticDispatchRatio(self: *const PerformanceCounters) f64 {
            const total_dispatches = self.static_dispatches + self.dynamic_dispatches;
            if (total_dispatches == 0) return 0.0;
            return @as(f64, @floatFromInt(self.static_dispatches)) / @as(f64, @floatFromInt(total_dispatches));
        }

        pub fn format(self: PerformanceCounters, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("Performance Counters:\n");
            try writer.print("  Total dispatch calls: {}\n", .{self.total_dispatch_calls});
            try writer.print("  Total dispatch time: {d:.1}ms\n", .{@as(f64, @floatFromInt(self.total_dispatch_time)) / 1_000_000.0});
            try writer.print("  Cache hit ratio: {d:.1}%\n", .{self.getCacheHitRatio() * 100.0});
            try writer.print("  Static dispatch ratio: {d:.1}%\n", .{self.getStaticDispatchRatio() * 100.0});
            try writer.print("  Timing breakdown: {d:.1}% lookup, {d:.1}% resolution, {d:.1}% call\n", .{
                @as(f64, @floatFromInt(self.lookup_time)) / @as(f64, @floatFromInt(self.total_dispatch_time)) * 100.0,
                @as(f64, @floatFromInt(self.resolution_time)) / @as(f64, @floatFromInt(self.total_dispatch_time)) * 100.0,
                @as(f64, @floatFromInt(self.call_time)) / @as(f64, @floatFromInt(self.total_dispatch_time)) * 100.0,
            });
        }
    };

    /// Profiling session management
    pub const ProfilingSession = struct {
        session_id: u64,
        start_time: u64,
        end_time: u64,
        duration: u64,

        // Session configuration
        config: ProfilingConfig,

        // Session statistics
        calls_profiled: u64,
        calls_sampled: u64,
        sampling_ratio: f64,

        pub fn init(config: ProfilingConfig) ProfilingSession {
            const start_time = @as(u64, @intCast(std.time.nanoTimestamp()));
            return ProfilingSession{
                .session_id = start_time,
                .start_time = start_time,
                .end_time = 0,
                .duration = 0,
                .config = config,
                .calls_profiled = 0,
                .calls_sampled = 0,
                .sampling_ratio = 0.0,
            };
        }

        pub fn end(self: *ProfilingSession) void {
            self.end_time = @as(u64, @intCast(std.time.nanoTimestamp()));
            self.duration = self.end_time - self.start_time;

            if (self.calls_profiled > 0) {
                self.sampling_ratio = @as(f64, @floatFromInt(self.calls_sampled)) / @as(f64, @floatFromInt(self.calls_profiled));
            }
        }

        pub fn shouldSample(self: *ProfilingSession) bool {
            self.calls_profiled += 1;

            // Simple random sampling based on sample rate
            const random_value = @as(f64, @floatFromInt(@as(u32, @truncate(std.time.nanoTimestamp())))) / @as(f64, @floatFromInt(std.math.maxInt(u32)));

            if (random_value < self.config.sample_rate) {
                self.calls_sampled += 1;
                return true;
            }

            return false;
        }

        pub fn format(self: ProfilingSession, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("ProfilingSession[{}]:\n", .{self.session_id});
            try writer.print("  Duration: {d:.1}s\n", .{@as(f64, @floatFromInt(self.duration)) / 1_000_000_000.0});
            try writer.print("  Calls: {} profiled, {} sampled ({d:.1}% rate)\n", .{ self.calls_profiled, self.calls_sampled, self.sampling_ratio * 100.0 });
        }
    };

    pub fn init(allocator: Allocator, config: ProfilingConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .call_profiles = HashMap(CallSiteId, CallProfile).init(allocator),
            .signature_profiles = HashMap([]const u8, SignatureProfile).init(allocator),
            .hot_paths = ArrayList(HotPath).init(allocator),
            .optimization_opportunities = ArrayList(OptimizationOpportunity).init(allocator),
            .counters = std.mem.zeroes(PerformanceCounters),
            .current_session = null,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up call profiles
        var call_iter = self.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.call_profiles.deinit();

        // Clean up signature profiles
        var sig_iter = self.signature_profiles.iterator();
        while (sig_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.signature_profiles.deinit();

        // Clean up hot paths
        for (self.hot_paths.items) |*hot_path| {
            hot_path.call_sites.deinit();
        }
        self.hot_paths.deinit();

        self.optimization_opportunities.deinit();
    }

    /// Start a profiling session
    pub fn startSession(self: *Self, config: ?ProfilingConfig) void {
        const session_config = config orelse self.config;
        self.current_session = ProfilingSession.init(session_config);
        self.counters.reset();
    }

    /// End the current profiling session
    pub fn endSession(self: *Self) void {
        if (self.current_session) |*session| {
            session.end();

            // Analyze collected data
            self.analyzeProfilingData();

            self.current_session = null;
        }
    }

    /// Record a dispatch call for profiling
    pub fn recordDispatchCall(self: *Self, call_site: CallSiteId, dispatch_time_ns: u64, implementation: *const SignatureAnalyzer.Implementation, was_cache_hit: bool) void {
        if (!self.config.enabled) return;

        // Check if we should sample this call
        if (self.current_session) |*session| {
            if (!session.shouldSample()) return;
        }

        // Update global counters
        self.counters.total_dispatch_calls += 1;
        self.counters.total_dispatch_time += dispatch_time_ns;

        if (was_cache_hit) {
            self.counters.cache_hits += 1;
        } else {
            self.counters.cache_misses += 1;
        }

        // Update call site profile
        if (self.call_profiles.getPtr(call_site)) |profile| {
            profile.recordCall(dispatch_time_ns, implementation, was_cache_hit);
        } else {
            var new_profile = CallProfile.init(self.allocator, call_site);
            new_profile.recordCall(dispatch_time_ns, implementation, was_cache_hit);
            self.call_profiles.put(call_site, new_profile) catch return;
        }

        // Update signature profile
        if (self.signature_profiles.getPtr(call_site.signature_name)) |sig_profile| {
            if (self.call_profiles.get(call_site)) |call_profile| {
                sig_profile.updateFromCallProfile(&call_profile);
            }
        } else {
            var new_sig_profile = SignatureProfile.init(self.allocator, call_site.signature_name);
            if (self.call_profiles.get(call_site)) |call_profile| {
                new_sig_profile.updateFromCallProfile(&call_profile);
            }
            self.signature_profiles.put(call_site.signature_name, new_sig_profile) catch return;
        }
    }

    /// Get profiling statistics for a specific call site
    pub fn getCallSiteProfile(self: *Self, call_site: CallSiteId) ?*const CallProfile {
        return self.call_profiles.getPtr(call_site);
    }

    /// Get profiling statistics for a signature
    pub fn getSignatureProfile(self: *Self, signature_name: []const u8) ?*const SignatureProfile {
        return self.signature_profiles.getPtr(signature_name);
    }

    /// Get identified hot paths
    pub fn getHotPaths(self: *Self) []const HotPath {
        return self.hot_paths.items;
    }

    /// Get optimization opportunities
    pub fn getOptimizationOpportunities(self: *Self) []const OptimizationOpportunity {
        return self.optimization_opportunities.items;
    }
    /// Generate comprehensive profiling report
    pub fn generateReport(self: *Self, writer: anytype) !void {
        try writer.print("Dispatch Profiling Report\n");
        try writer.print("=========================\n\n");

        // Session information
        if (self.current_session) |session| {
            try writer.print("{}\n", .{session});
        }

        // Global performance counters
        try writer.print("{}\n", .{self.counters});

        // Top hot call sites
        try writer.print("Hot Call Sites:\n");
        try writer.print("---------------\n");

        var hot_call_sites = ArrayList(*CallProfile).init(self.allocator);
        defer hot_call_sites.deinit();

        var call_iter = self.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            if (entry.value_ptr.is_hot_path) {
                try hot_call_sites.append(entry.value_ptr);
            }
        }

        // Sort by hotness score
        const Context = struct {
            pub fn lessThan(context: @This(), a: *CallProfile, b: *CallProfile) bool {
                _ = context;
                return a.hotness_score > b.hotness_score;
            }
        };

        std.mem.sort(*CallProfile, hot_call_sites.items, Context{}, Context.lessThan);

        for (hot_call_sites.items[0..@min(10, hot_call_sites.items.len)]) |profile| {
            try writer.print("{}\n", .{profile.*});
        }

        // Signature analysis
        try writer.print("Signature Analysis:\n");
        try writer.print("-------------------\n");

        var sig_iter = self.signature_profiles.iterator();
        while (sig_iter.next()) |entry| {
            if (entry.value_ptr.total_calls >= self.config.min_calls_for_analysis) {
                try writer.print("{}\n", .{entry.value_ptr.*});
            }
        }

        // Optimization opportunities
        try writer.print("Optimization Opportunities:\n");
        try writer.print("---------------------------\n");

        for (self.optimization_opportunities.items) |opportunity| {
            try writer.print("{}\n", .{opportunity});
        }

        // Hot paths
        try writer.print("Hot Paths:\n");
        try writer.print("----------\n");

        for (self.hot_paths.items) |hot_path| {
            try writer.print("{}\n", .{hot_path});
        }
    }

    /// Export profiling data in various formats
    pub fn exportData(self: *Self, writer: anytype, format: ProfilingConfig.OutputFormat) !void {
        switch (format) {
            .text => try self.generateReport(writer),
            .json => try self.exportJSON(writer),
            .csv => try self.exportCSV(writer),
            .flamegraph => try self.exportFlamegraph(writer),
        }
    }

    /// Reset all profiling data
    pub fn reset(self: *Self) void {
        // Clear call profiles
        var call_iter = self.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.call_profiles.clearAndFree();

        // Clear signature profiles
        var sig_iter = self.signature_profiles.iterator();
        while (sig_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.signature_profiles.clearAndFree();

        // Clear hot paths
        for (self.hot_paths.items) |*hot_path| {
            hot_path.call_sites.deinit();
        }
        self.hot_paths.clearAndFree();

        self.optimization_opportunities.clearAndFree();
        self.counters.reset();
    }

    // Private analysis methods

    fn analyzeProfilingData(self: *Self) void {
        if (self.current_session) |session| {
            // Calculate hes for all call profiles
            var call_iter = self.call_profiles.iterator();
            while (call_iter.next()) |entry| {
                entry.value_ptr.calculateHotnessScore(session.duration);
            }

            // Identify hot paths
            self.identifyHotPaths() catch {};

            // Find optimization opportunities
            self.findOptimizationOpportunities() catch {};
        }
    }

    fn identifyHotPaths(self: *Self) !void {
        self.hot_paths.clearAndFree();

        // Group hot call sites by signature
        var signature_groups = HashMap([]const u8, ArrayList(CallSiteId)).init(self.allocator);
        defer {
            var iter = signature_groups.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            signature_groups.deinit();
        }

        var call_iter = self.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            if (entry.value_ptr.is_hot_path) {
                const signature = entry.key_ptr.signature_name;

                if (signature_groups.getPtr(signature)) |group| {
                    try group.append(entry.key_ptr.*);
                } else {
                    var new_group = ArrayList(CallSiteId).init(self.allocator);
                    try new_group.append(entry.key_ptr.*);
                    try signature_groups.put(signature, new_group);
                }
            }
        }

        // Create hot paths from groups
        var group_iter = signature_groups.iterator();
        while (group_iter.next()) |entry| {
            var total_calls: u64 = 0;
            var total_time: u64 = 0;

            for (entry.value_ptr.items) |call_site| {
                if (self.call_profiles.get(call_site)) |profile| {
                    total_calls += profile.total_calls;
                    total_time += profile.total_dispatch_time;
                }
            }

            var hot_path = HotPath{
                .call_sites = try entry.value_ptr.clone(),
                .total_calls = total_calls,
                .total_time = total_time,
                .avg_time_per_call = if (total_calls > 0) @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(total_calls)) else 0.0,
                .optimization_potential = .low,
            };

            hot_path.calculateOptimizationPotential();
            try self.hot_paths.append(hot_path);
        }
    }

    fn findOptimizationOpportunities(self: *Self) !void {
        self.optimization_opportunities.clearAndFree();

        // Analyze call profiles for opportunities
        var call_iter = self.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;

            // Static dispatch opportunity
            if (profile.implementations_used.count() == 1 and profile.total_calls > 1000) {
                const opportunity = OptimizationOpportunity{
                    .type = .static_dispatch,
                    .call_site = profile.call_site,
                    .signature_name = profile.call_site.signature_name,
                    .potential_speedup = 1.5,
                    .confidence = 0.9,
                    .description = "Single implementation used consistently",
                    .suggested_action = "Consider static dispatch optimization",
                };
                try self.optimization_opportunities.append(opportunity);
            }

            // Cache optimization opportunity
            if (profile.cache_hit_ratio < 0.5 and profile.total_calls > 500) {
                const opportunity = OptimizationOpportunity{
                    .type = .cache_optimization,
                    .call_site = profile.call_site,
                    .signature_name = profile.call_site.signature_name,
                    .potential_speedup = 1.3,
                    .confidence = 0.7,
                    .description = "Low cache hit ratio",
                    .suggested_action = "Improve cache locality or increase cache size",
                };
                try self.optimization_opportunities.append(opportunity);
            }

            // Hot path optimization opportunity
            if (profile.is_hot_path and profile.avg_dispatch_time > 1000) { // > 1μs
                const opportunity = OptimizationOpportunity{
                    .type = .hot_path_optimization,
                    .call_site = profile.call_site,
                    .signature_name = profile.call_site.signature_name,
                    .potential_speedup = 2.0,
                    .confidence = 0.8,
                    .description = "Hot path with high dispatch overhead",
                    .suggested_action = "Consider inline caching or specialization",
                };
                try self.optimization_opportunities.append(opportunity);
            }
        }

        // Analyze signature profiles for opportunities
        var sig_iter = self.signature_profiles.iterator();
        while (sig_iter.next()) |entry| {
            const profile = entry.value_ptr;

            // Monomorphization opportunity
            if (profile.monomorphization_candidates > 0) {
                const opportunity = OptimizationOpportunity{
                    .type = .monomorphization,
                    .call_site = CallSiteId{ .source_file = "", .line = 0, .column = 0, .signature_name = profile.signature_name },
                    .signature_name = profile.signature_name,
                    .potential_speedup = 1.8,
                    .confidence = 0.6,
                    .description = "Low implementation diversity with high usage",
                    .suggested_action = "Consider monomorphization for common type patterns",
                };
                try self.optimization_opportunities.append(opportunity);
            }
        }
    }

    fn exportJSON(self: *Self, writer: anytype) !void {
        try writer.writeAll("{\n");
        try writer.writeAll("  \"profiling_data\": {\n");

        // Export counters
        try writer.print("    \"counters\": {{\n");
        try writer.print("      \"total_dispatch_calls\": {},\n", .{self.counters.total_dispatch_calls});
        try writer.print("      \"total_dispatch_time\": {},\n", .{self.counters.total_dispatch_time});
        try writer.print("      \"cache_hit_ratio\": {d:.3}\n", .{self.counters.getCacheHitRatio()});
        try writer.writeAll("    },\n");

        // Export call profiles (simplified)
        try writer.writeAll("    \"call_profiles\": [\n");
        var call_iter = self.call_profiles.iterator();
        var first = true;
        while (call_iter.next()) |entry| {
            if (!first) try writer.writeAll(",\n");
            first = false;

            const profile = entry.value_ptr;
            try writer.print("      {{\n");
            try writer.print("        \"call_site\": \"{}:{}\",\n", .{ profile.call_site.source_file, profile.cae });
            try writer.print("        \"signature\": \"{s}\",\n", .{profile.call_site.signature_name});
            try writer.print("        \"total_calls\": {},\n", .{profile.total_calls});
            try writer.print("        \"avg_dispatch_time\": {d:.1},\n", .{profile.avg_dispatch_time});
            try writer.print("        \"hotness_score\": {d:.3}\n", .{profile.hotness_score});
            try writer.writeAll("      }");
        }
        try writer.writeAll("\n    ]\n");

        try writer.writeAll("  }\n");
        try writer.writeAll("}\n");
    }

    fn exportCSV(self: *Self, writer: anytype) !void {
        // CSV header
        try writer.writeAll("call_site,signature,total_calls,avg_dispatch_time_ns,cache_hit_ratio,hotness_score,is_hot_path\n");

        // CSV data
        var call_iter = self.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;
            try writer.print("\"{}:{}\",\"{s}\",{},{d:.1},{d:.3},{d:.3},{}\n", .{
                profile.call_site.source_file,
                profile.call_site.line,
                profile.call_site.signature_name,
                profile.total_calls,
                profile.avg_dispatch_time,
                profile.cache_hit_ratio,
                profile.hotness_score,
                profile.is_hot_path,
            });
        }
    }

    fn exportFlamegraph(self: *Self, writer: anytype) !void {
        // Simplified flamegraph format (stack traces with call counts)
        var call_iter = self.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;
            try writer.print("{s};{}:{} {}\n", .{
                profile.call_site.signature_name,
                profile.call_site.source_file,
                profile.call_site.line,
                profile.total_calls,
            });
        }
    }
};

// Tests

test "DispatchProfiler basic functionality" {
    const allocator = testing.allocator;

    const config = DispatchProfiler.ProfilingConfig.default();
    var profiler = DispatchProfiler.init(allocator, config);
    defer profiler.deinit();

    // Start profiling session
    profiler.startSession(null);

    // Create test call site
    const call_site = DispatchProfiler.CallSiteId{
        .source_file = "test.jan",
        .line = 42,
        .column = 10,
        .signature_name = "test_func",
    };

    // Create test implementation
    const impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "test_func",
            .module = "test",
            .id = 1,
        },
        .param_type_ids = &.{},
        .return_type_id = 0,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };

    // Record some dispatch calls
    for (0..1000) |i| {
        const dispatch_time = 1000 + (i % 500); // 1-1.5μs
        const cache_hit = (i % 3) == 0; // 33% cache hit rate
        profiler.recordDispatchCall(call_site, dispatch_time, &impl, cache_hit);
    }

    // End session
    profiler.endSession();

    // Verify profiling data
    const call_profile = profiler.getCallSiteProfile(call_site);
    try testing.expect(call_profile != null);
    try testing.expectEqual(@as(u64, 1000), call_profile.?.total_calls);
    try testing.expect(call_profile.?.avg_dispatch_time > 1000);
    try testing.expect(call_profile.?.cache_hit_ratio > 0.3);

    // Check counters
    try testing.expectEqual(@as(u64, 1000), profiler.counters.total_dispatch_calls);
    try testing.expect(profiler.counters.total_dispatch_time > 1000000);
}

test "CallProfile hotness calculation" {
    const allocator = testing.allocator;

    const call_site = DispatchProfiler.CallSiteId{
        .source_file = "test.jan",
        .line = 1,
        .column = 1,
        .signature_name = "hot_func",
    };

    var profile = DispatchProfiler.CallProfile.init(allocator, call_site);
    defer profile.deinit();

    const impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "hot_func",
            .module = "test",
            .id = 1,
        },
        .param_type_ids = &.{},
        .return_type_id = 0,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };

    // Record many calls with high dispatch time and low cache hit rate
    for (0..10000) |i| {
        const dispatch_time = 2000; // 2μs - high dispatch time
        const cache_hit = (i % 10) == 0; // 10% cache hit rate - poor
        profile.recordCall(dispatch_time, &impl, cache_hit);
    }

    // Calculate hotness for 1 second session
    profile.calculateHotnessScore(1_000_000_000);

    // Should be classified as hot path
    try testing.expect(profile.is_hot_path);
    try testing.expect(profile.hotness_score > 0.7);
    try testing.expectEqual(@as(f64, 10000.0), profile.calls_per_second);
}

test "OptimizationOpportunity identification" {
    const allocator = testing.allocator;

    const config = DispatchProfiler.ProfilingConfig.default();
    var profiler = DispatchProfiler.init(allocator, config);
    defer profiler.deinit();

    profiler.startSession(null);

    // Create call site with single implementation (static dispatch opportunity)
    const call_site = DispatchProfiler.CallSiteId{
        .source_file = "test.jan",
        .line = 1,
        .column = 1,
        .signature_name = "static_candidate",
    };

    const impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{
            .name = "static_candidate",
            .module = "test",
            .id = 1,
        },
        .param_type_ids = &.{},
        .return_type_id = 0,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };

    // Record many calls to same implementation
    for (0..2000) |_| {
        profiler.recordDispatchCall(call_site, 1000, &impl, true);
    }

    profiler.endSession();

    // Should identify static dispatch opportunity
    const opportunities = profiler.getOptimizationOpportunities();
    try testing.expect(opportunities.len > 0);

    var found_static_dispatch = false;
    for (opportunities) |opp| {
        if (opp.type == .static_dispatch) {
            found_static_dispatch = true;
            break;
        }
    }
    try testing.expect(found_static_dispatch);
}
