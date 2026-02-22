// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const DispatchProfiler = @import("../compiler/libjanus/dispatch_profiler.zig").DispatchProfiler;
const OptimizationHintsGenerator = @import("../compiler/libjanus/optimization_hints.zig").OptimizationHintsGenerator;
const SignatureAnalyzer = @import("../compiler/libjanus/signature_analyzer.zig").SignatureAnalyzer;

/// Comprehensive test suite for dispatch profiling and optimization hints
const ProfilingTestSuite = struct {
    allocator: Allocator,
    profiler: *DispatchProfiler,
    hints_generator: *OptimizationHintsGenerator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const profiler_config = DispatchProfiler.ProfilingConfig.default();
        var profiler = try allocator.create(DispatchProfiler);
        profiler.* = DispatchProfiler.init(allocator, profiler_config);

        const hints_config = OptimizationHintsGenerator.HintConfig.default();
        var hints_generator = try allocator.create(OptimizationHintsGenerator);
        hints_generator.* = OptimizationHintsGenerator.init(allocator, hints_config);

        return Self{
            .allocator = allocator,
            .profiler = profiler,
            .hints_generator = hints_generator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.profiler.deinit();
        self.allocator.destroy(self.profiler);

        self.hints_generator.deinit();
        self.allocator.destroy(self.hints_generator);
    }

    /// Test basic profiling functionality
    pub fn testBasicProfiling(self: *Self) !void {
        // Start profiling session
        self.profiler.startSession(null);

        // Create test call sites
        const call_sites = [_]DispatchProfiler.CallSiteId{
            DispatchProfiler.CallSiteId{
                .source_file = "main.jan",
                .line = 10,
                .column = 5,
                .signature_name = "process",
            },
            DispatchProfiler.CallSiteId{
                .source_file = "utils.jan",
                .line = 25,
                .column = 12,
                .signature_name = "transform",
            },
        };

        // Create test implementations
        const implementations = [_]SignatureAnalyzer.Implementation{
            SignatureAnalyzer.Implementation{
                .function_id = SignatureAnalyzer.FunctionId{
                    .name = "process",
                    .module = "main",
                    .id = 1,
                },
                .param_type_ids = &.{},
                .return_type_id = 0,
                .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
                .source_location = SignatureAnalyzer.SourceSpan.dummy(),
                .specificity_rank = 100,
            },
            SignatureAnalyzer.Implementation{
                .function_id = SignatureAnalyzer.FunctionId{
                    .name = "transform",
                    .module = "utils",
                    .id = 2,
                },
                .param_type_ids = &.{},
                .return_type_id = 0,
                .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
                .source_location = SignatureAnalyzer.SourceSpan.dummy(),
                .specificity_rank = 100,
            },
        };

        // Record dispatch calls with varying patterns
        for (0..1000) |i| {
            const call_site_idx = i % call_sites.len;
            const impl_idx = i % implementations.len;

            const dispatch_time = 800 + (i % 400); // 0.8-1.2μs
            const cache_hit = (i % 4) != 0; // 75% cache hit rate

            self.profiler.recordDispatchCall(call_sites[call_site_idx], dispatch_time, &implementations[impl_idx], cache_hit);
        }

        // End profiling session
        self.profiler.endSession();

        // Verify profiling data was collected
        try testing.expectEqual(@as(u64, 1000), self.profiler.counters.total_dispatch_calls);
        try testing.expect(self.profiler.counters.total_dispatch_time > 800000);
        try testing.expect(self.profiler.counters.getCacheHitRatio() > 0.7);

        // Verify call site profiles were created
        for (call_sites) |call_site| {
            const profile = self.profiler.getCallSiteProfile(call_site);
            try testing.expect(profile != null);
            try testing.expect(profile.?.total_calls > 0);
        }

        // Verify signature profiles were created
        for (call_sites) |call_site| {
            const sig_profile = self.profiler.getSignatureProfile(call_site.signature_name);
            try testing.expect(sig_profile != null);
            try testing.expect(sig_profile.?.total_calls > 0);
        }
    }

    /// Test hot path identification
    pub fn testHotPathIdentification(self: *Self) !void {
        self.profiler.reset();
        self.profiler.startSession(null);

        // Create hot call site
        const hot_call_site = DispatchProfiler.CallSiteId{
            .source_file = "hot.jan",
            .line = 1,
            .column = 1,
            .signature_name = "hot_function",
        };

        // Create cold call site
        const cold_call_site = DispatchProfiler.CallSiteId{
            .source_file = "cold.jan",
            .line = 1,
            .column = 1,
            .signature_name = "cold_function",
        };

        const impl = SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{
                .name = "test_impl",
                .module = "test",
                .id = 1,
            },
            .param_type_ids = &.{},
            .return_type_id = 0,
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 100,
        };

        // Record many calls to hot path with high dispatch time and poor cache performance
        for (0..10000) |i| {
            const dispatch_time = 2000; // 2μs - high dispatch time
            const cache_hit = (i % 10) == 0; // 10% cache hit rate - poor
            self.profiler.recordDispatchCall(hot_call_site, dispatch_time, &impl, cache_hit);
        }

        // Record few calls to cold path
        for (0..50) |i| {
            const dispatch_time = 500; // 0.5μs - low dispatch time
            const cache_hit = (i % 2) == 0; // 50% cache hit rate
            self.profiler.recordDispatchCall(cold_call_site, dispatch_time, &impl, cache_hit);
        }

        self.profiler.endSession();

        // Verify hot path was identified
        const hot_profile = self.profiler.getCallSiteProfile(hot_call_site).?;
        try testing.expect(hot_profile.is_hot_path);
        try testing.expect(hot_profile.hotness_score > 0.7);

        // Verify cold path was not identified as hot
        const cold_profile = self.profiler.getCallSiteProfile(cold_call_site).?;
        try testing.expect(!cold_profile.is_hot_path);
        try testing.expect(cold_profile.hotness_score < 0.5);

        // Verify hot paths were identified
        const hot_paths = self.profiler.getHotPaths();
        try testing.expect(hot_paths.len > 0);

        var found_hot_path = false;
        for (hot_paths) |hot_path| {
            if (hot_path.optimization_potential == .high or hot_path.optimization_potential == .critical) {
                found_hot_path = true;
                break;
            }
        }
        try testing.expect(found_hot_path);
    }

    /// Test optimization opportunity detection
    pub fn testOptimizationOpportunityDetection(self: *Self) !void {
        self.profiler.reset();
        self.profiler.startSession(null);

        // Create call site with single implementation (static dispatch opportunity)
        const static_call_site = DispatchProfiler.CallSiteId{
            .source_file = "static.jan",
            .line = 1,
            .column = 1,
            .signature_name = "static_candidate",
        };

        // Create call site with poor cache performance
        const cache_call_site = DispatchProfiler.CallSiteId{
            .source_file = "cache.jan",
            .line = 1,
            .column = 1,
            .signature_name = "cache_candidate",
        };

        const impl1 = SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{
                .name = "impl1",
                .module = "test",
                .id = 1,
            },
            .param_type_ids = &.{},
            .return_type_id = 0,
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 100,
        };

        const impl2 = SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{
                .name = "impl2",
                .module = "test",
                .id = 2,
            },
            .param_type_ids = &.{},
            .return_type_id = 0,
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 100,
        };

        // Record calls to static dispatch candidate (single implementation)
        for (0..2000) |_| {
            self.profiler.recordDispatchCall(static_call_site, 1000, &impl1, true);
        }

        // Record calls to cache optimization candidate (poor cache performance)
        for (0..1000) |i| {
            const cache_hit = (i % 5) == 0; // 20% cache hit rate - poor
            const impl = if (i % 2 == 0) &impl1 else &impl2;
            self.profiler.recordDispatchCall(cache_call_site, 1500, impl, cache_hit);
        }

        self.profiler.endSession();

        // Verify optimization opportunities were identified
        const opportunities = self.profiler.getOptimizationOpportunities();
        try testing.expect(opportunities.len > 0);

        var found_static_dispatch = false;
        var found_cache_optimization = false;

        for (opportunities) |opp| {
            switch (opp.type) {
                .static_dispatch => found_static_dispatch = true,
                .cache_optimization => found_cache_optimization = true,
                else => {},
            }
        }

        try testing.expect(found_static_dispatch);
        try testing.expect(found_cache_optimization);
    }

    /// Test optimization hints generation
    pub fn testOptimizationHintsGeneration(self: *Self) !void {
        // First generate profiling data
        try self.testOptimizationOpportunityDetection();

        // Generate optimization hints
        try self.hints_generator.generateHints(self.profiler);

        // Verify hints were generated
        const hints = self.hints_generator.getHints();
        try testing.expect(hints.len > 0);

        // Verify hint statistics
        const stats = self.hints_generator.stats;
        try testing.expectEqual(hints.len, stats.total_hints_generated);
        try testing.expect(stats.total_estimated_speedup > 0.0);

        // Verify different types of hints were generated
        var hint_types_found = std.EnumSet(OptimizationHintsGenerator.OptimizationHint.HintType){};

        for (hints) |hint| {
            hint_types_found.insert(hint.type);

            // Verify hint has required fields
            try testing.expect(hint.confidence > 0.0);
            try testing.expect(hint.estimated_speedup >= 1.0);
            try testing.expect(hint.title.len > 0);
            try testing.expect(hint.description.len > 0);
        }

        // Should have found at least static dispatch and cache optimization hints
        try testing.expect(hint_types_found.contains(.static_dispatch));
        try testing.expect(hint_types_found.contains(.cache_optimization));
    }

    /// Test hint filtering and prioritization
    pub fn testHintFilteringAndPrioritization(self: *Self) !void {
        // Generate hints first
        try self.testOptimizationHintsGeneration();

        const all_hints = self.hints_generator.getHints();

        // Test filtering by type
        const static_hints = self.hints_generator.getHintsByType(.static_dispatch);
        defer self.allocator.free(static_hints);

        for (static_hints) |hint| {
            try testing.expectEqual(OptimizationHintsGenerator.OptimizationHint.HintType.static_dispatch, hint.type);
        }

        // Test filtering by priority
        const high_priority_hints = self.hints_generator.getHintsByPriority(.high);
        defer self.allocator.free(high_priority_hints);

        for (high_priority_hints) |hint| {
            try testing.expectEqual(OptimizationHintsGenerator.OptimizationHint.Priority.high, hint.priority);
        }

        // Test automatic optimization candidates
        const auto_candidates = self.hints_generator.getAutomaticOptimizationCandidates();
        defer self.allocator.free(auto_candidates);

        for (auto_candidates) |hint| {
            try testing.expect(hint.confidence >= 0.9); // High confidence threshold
        }

        // Verify hints are sorted by priority and confidence
        if (all_hints.len > 1) {
            for (all_hints[0 .. all_hints.len - 1], all_hints[1..]) |current, next| {
                const current_priority = @intFromEnum(current.priority);
                const next_priority = @intFromEnum(next.priority);

                // Higher priority should come first, or same priority with higher confidence
                try testing.expect(current_priority >= next_priority or
                    (current_priority == next_priority and current.confidence >= next.confidence));
            }
        }
    }

    /// Test profiling session management
    pub fn testProfilingSessionManagement(self: *Self) !void {
        // Test session lifecycle
        try testing.expect(self.profiler.current_session == null);

        self.profiler.startSession(null);
        try testing.expect(self.profiler.current_session != null);

        const session = self.profiler.current_session.?;
        try testing.expect(session.start_time > 0);
        try testing.expect(session.end_time == 0);
        try testing.expect(session.duration == 0);

        // Record some calls
        const call_site = DispatchProfiler.CallSiteId{
            .source_file = "test.jan",
            .line = 1,
            .column = 1,
            .signature_name = "test_func",
        };

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

        for (0..100) |_| {
            self.profiler.recordDispatchCall(call_site, 1000, &impl, true);
        }

        // End session
        self.profiler.endSession();
        try testing.expect(self.profiler.current_session == null);

        // Verify session data was processed
        const profile = self.profiler.getCallSiteProfile(call_site);
        try testing.expect(profile != null);
        try testing.expect(profile.?.total_calls == 100);
    }

    /// Test sampling functionality
    pub fn testSampling(self: *Self) !void {
        // Test with reduced sampling rate
        var config = DispatchProfiler.ProfilingConfig.default();
        config.sample_rate = 0.1; // 10% sampling rate

        self.profiler.deinit();
        self.profiler.* = DispatchProfiler.init(self.allocator, config);

        self.profiler.startSession(null);

        const call_site = DispatchProfiler.CallSiteId{
            .source_file = "sample.jan",
            .line = 1,
            .column = 1,
            .signature_name = "sample_func",
        };

        const impl = SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{
                .name = "sample_func",
                .module = "test",
                .id = 1,
            },
            .param_type_ids = &.{},
            .return_type_id = 0,
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 100,
        };

        // Record many calls
        for (0..1000) |_| {
            self.profiler.recordDispatchCall(call_site, 1000, &impl, true);
        }

        self.profiler.endSession();

        // Should have sampled fewer calls than total
        const profile = self.profiler.getCallSiteProfile(call_site);
        if (profile) |p| {
            try testing.expect(p.total_calls < 1000);
            try testing.expect(p.total_calls > 0); // But should have sampled some
        }
    }

    /// Test export functionality
    pub fn testExportFunctionality(self: *Self) !void {
        // Generate some profiling data
        try self.testBasicProfiling();
        try self.hints_generator.generateHints(self.profiler);

        // Test profiler export formats
        var text_buffer: ArrayList(u8) = .empty;
        defer text_buffer.deinit();

        try self.profiler.exportData(text_buffer.writer(), .text);
        try testing.expect(text_buffer.items.len > 0);

        var json_buffer: ArrayList(u8) = .empty;
        defer json_buffer.deinit();

        try self.profiler.exportData(json_buffer.writer(), .json);
        try testing.expect(json_buffer.items.len > 0);
        try testing.expect(std.mem.indexOf(u8, json_buffer.items, "profiling_data") != null);

        // Test hints generator export formats
        var hints_text_buffer: ArrayList(u8) = .empty;
        defer hints_text_buffer.deinit();

        try self.hints_generator.exportHints(hints_text_buffer.writer(), .text);
        try testing.expect(hints_text_buffer.items.len > 0);

        var hints_json_buffer: ArrayList(u8) = .empty;
        defer hints_json_buffer.deinit();

        try self.hints_generator.exportHints(hints_json_buffer.writer(), .json);
        try testing.expect(hints_json_buffer.items.len > 0);
        try testing.expect(std.mem.indexOf(u8, hints_json_buffer.items, "optimization_hints") != null);
    }

    /// Test performance characteristics
    pub fn testPerformanceCharacteristics(self: *Self) !void {
        self.profiler.reset();

        // Measure profiling overhead
        const start_time = compat_time.nanoTimestamp();

        self.profiler.startSession(null);

        const call_site = DispatchProfiler.CallSiteId{
            .source_file = "perf.jan",
            .line = 1,
            .column = 1,
            .signature_name = "perf_func",
        };

        const impl = SignatureAnalyzer.Implementation{
            .function_id = SignatureAnalyzer.FunctionId{
                .name = "perf_func",
                .module = "test",
                .id = 1,
            },
            .param_type_ids = &.{},
            .return_type_id = 0,
            .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
            .source_location = SignatureAnalyzer.SourceSpan.dummy(),
            .specificity_rank = 100,
        };

        // Record many calls to test performance
        const num_calls = 100000;
        for (0..num_calls) |_| {
            self.profiler.recordDispatchCall(call_site, 1000, &impl, true);
        }

        self.profiler.endSession();

        const end_time = compat_time.nanoTimestamp();
        const total_time = end_time - start_time;
        const time_per_call = total_time / num_calls;

        // Profiling overhead should be reasonable (< 1μs per call)
        try testing.expect(time_per_call < 1000);

        // Verify all calls were recorded
        const profile = self.profiler.getCallSiteProfile(call_site).?;
        try testing.expectEqual(@as(u64, num_calls), profile.total_calls);
    }
};

// Test runner

test "Dispatch profiling and optimization hints comprehensive test suite" {
    const allocator = testing.allocator;

    var test_suite = try ProfilingTestSuite.init(allocator);
    defer test_suite.deinit();

    // Run all tests
    try test_suite.testBasicProfiling();
    try test_suite.testHotPathIdentification();
    try test_suite.testOptimizationOpportunityDetection();
    try test_suite.testOptimizationHintsGeneration();
    try test_suite.testHintFilteringAndPrioritization();
    try test_suite.testProfilingSessionManagement();
    try test_suite.testSampling();
    try test_suite.testExportFunctionality();
    try test_suite.testPerformanceCharacteristics();
}

// Individual test cases for specific functionality

test "CallSiteId hashing and equality" {
    const call_site1 = DispatchProfiler.CallSiteId{
        .source_file = "test.jan",
        .line = 42,
        .column = 10,
        .signature_name = "test_func",
    };

    const call_site2 = DispatchProfiler.CallSiteId{
        .source_file = "test.jan",
        .line = 42,
        .column = 10,
        .signature_name = "test_func",
    };

    const call_site3 = DispatchProfiler.CallSiteId{
        .source_file = "test.jan",
        .line = 43, // Different line
        .column = 10,
        .signature_name = "test_func",
    };

    // Test equality
    try testing.expect(call_site1.eql(call_site2));
    try testing.expect(!call_site1.eql(call_site3));

    // Test hash consistency
    try testing.expectEqual(call_site1.hash(), call_site2.hash());
    try testing.expect(call_site1.hash() != call_site3.hash());
}

test "PerformanceCounters calculations" {
    var counters = DispatchProfiler.PerformanceCounters{
        .total_dispatch_calls = 1000,
        .total_dispatch_time = 1000000, // 1ms total
        .cache_hits = 800,
        .cache_misses = 200,
        .static_dispatches = 600,
        .dynamic_dispatches = 400,
        .lookup_time = 300000,
        .resolution_time = 400000,
        .call_time = 300000,
    };

    // Test cache hit ratio
    try testing.expectEqual(@as(f64, 0.8), counters.getCacheHitRatio());

    // Test static dispatch ratio
    try testing.expectEqual(@as(f64, 0.6), counters.getStaticDispatchRatio());
}

test "OptimizationHint supporting data validation" {
    const supporting_data = OptimizationHintsGenerator.OptimizationHint.SupportingData{
        .call_frequency = 5000,
        .cache_hit_ratio = 0.85,
        .implementation_diversity = 1.2,
        .hot_path_percentage = 15.5,
        .profiling_samples = 5000,
    };

    try testing.expectEqual(@as(u64, 5000), supporting_data.call_frequency);
    try testing.expectEqual(@as(f64, 0.85), supporting_data.cache_hit_ratio);
    try testing.expectEqual(@as(f64, 1.2), supporting_data.implementation_diversity);
    try testing.expectEqual(@as(f64, 15.5), supporting_data.hot_path_percentage);
    try testing.expectEqual(@as(u32, 5000), supporting_data.profiling_samples);
}

test "HintStats recording and calculations" {
    const allocator = testing.allocator;

    var stats = OptimizationHintsGenerator.HintStats.init(allocator);
    defer stats.deinit();

    // Create test hints
    const hint1 = OptimizationHintsGenerator.OptimizationHint{
        .id = 1,
        .type = .static_dispatch,
        .priority = .high,
        .confidence = 0.95,
        .call_site = DispatchProfiler.CallSiteId{ .source_file = "", .line = 0, .column = 0, .signature_name = "" },
        .signature_name = "test",
        .estimated_speedup = 2.0,
        .estimated_memory_savings = 64,
        .current_dispatch_time_ns = 1000,
        .optimized_dispatch_time_ns = 500,
        .title = "Test Hint 1",
        .description = "Test Description 1",
        .rationale = "Test Rationale 1",
        .suggested_action = "Test Action 1",
        .code_example = null,
        .compiler_flags = null,
        .implementation_notes = null,
        .supporting_data = std.mem.zeroes(OptimizationHintsGenerator.OptimizationHint.SupportingData),
    };

    const hint2 = OptimizationHintsGenerator.OptimizationHint{
        .id = 2,
        .type = .cache_optimization,
        .priority = .medium,
        .confidence = 0.75,
        .call_site = DispatchProfiler.CallSiteId{ .source_file = "", .line = 0, .column = 0, .signature_name = "" },
        .signature_name = "test2",
        .estimated_speedup = 1.5,
        .estimated_memory_savings = 32,
        .current_dispatch_time_ns = 1200,
        .optimized_dispatch_time_ns = 800,
        .title = "Test Hint 2",
        .description = "Test Description 2",
        .rationale = "Test Rationale 2",
        .suggested_action = "Test Action 2",
        .code_example = null,
        .compiler_flags = null,
        .implementation_notes = null,
        .supporting_data = std.mem.zeroes(OptimizationHintsGenerator.OptimizationHint.SupportingData),
    };

    // Record hints
    stats.recordHint(&hint1);
    stats.recordHint(&hint2);

    // Verify statistics
    try testing.expectEqual(@as(u32, 2), stats.total_hints_generated);
    try testing.expectEqual(@as(f64, 3.5), stats.total_estimated_speedup);
    try testing.expectEqual(@as(usize, 96), stats.total_estimated_memory_savings);
    try testing.expectEqual(@as(u32, 1), stats.high_confidence_hints); // hint1 has confidence >= 0.8
    try testing.expectEqual(@as(u32, 1), stats.automatic_optimization_candidates); // hint1 has confidence >= 0.9

    // Verify type counts
    try testing.expectEqual(@as(u32, 1), stats.hints_by_type.get(.static_dispatch).?);
    try testing.expectEqual(@as(u32, 1), stats.hints_by_type.get(.cache_optimization).?);

    // Verify priority counts
    try testing.expectEqual(@as(u32, 1), stats.hints_by_priority.get(.high).?);
    try testing.expectEqual(@as(u32, 1), stats.hints_by_priority.get(.medium).?);
}
