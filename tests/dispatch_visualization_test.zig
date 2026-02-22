// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const compat_time = @import("compat_time");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const DispatchProfiler = @import("../compiler/libjanus/dispatch_profiler.zig").DispatchProfiler;
const DispatchVisualizer = @import("../compiler/libjanus/dispatch_visualizer.zig").DispatchVisualizer;
const DispatchDebugger = @import("../compiler/libjanus/dispatch_debugger.zig").DispatchDebugger;
const SignatureAnalyzer = @import("../compiler/libjanus/signature_analyzer.zig").SignatureAnalyzer;
const TypeRegistry = @import("../compiler/libjanus/type_registry.zig").TypeRegistry;

/// Comprehensive test suite for dispatch visualization and debugging
const VisualizationTestSuite = struct {
    allocator: Allocator,
    profiler: *DispatchProfiler,
    visualizer: *DispatchVisualizer,
    debugger: *DispatchDebugger,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        // Initialize profiler with test data
        const profiler_config = DispatchProfiler.ProfilingConfig.default();
        var profiler = try allocator.create(DispatchProfiler);
        profiler.* = DispatchProfiler.init(allocator, profiler_config);

        // Initialize visualizer
        const viz_config = DispatchVisualizer.VisualizationConfig{};
        var visualizer = try allocator.create(DispatchVisualizer);
        visualizer.* = DispatchVisualizer.init(allocator, viz_config);

        // Initialize debugger
        const debug_config = DispatchDebugger.DebugConfig.default();
        var debugger = try allocator.create(DispatchDebugger);
        debugger.* = DispatchDebugger.init(allocator, debug_config);

        return Self{
            .allocator = allocator,
            .profiler = profiler,
            .visualizer = visualizer,
            .debugger = debugger,
        };
    }

    pub fn deinit(self: *Self) void {
        self.profiler.deinit();
        self.allocator.destroy(self.profiler);

        self.visualizer.deinit();
        self.allocator.destroy(self.visualizer);

        self.debugger.deinit();
        self.allocator.destroy(self.debugger);
    }

    /// Generate test profiling data
    pub fn generateTestData(self: *Self) !void {
        self.profiler.startSession(null);

        // Create test call sites with different characteristics
        const call_sites = [_]DispatchProfiler.CallSiteId{
            // Hot path
            DispatchProfiler.CallSiteId{
                .source_file = "main.jan",
                .line = 10,
                .column = 5,
                .signature_name = "hot_function",
            },
            // Normal path
            DispatchProfiler.CallSiteId{
                .source_file = "utils.jan",
                .line = 25,
                .column = 12,
                .signature_name = "normal_function",
            },
            // Cold path
            DispatchProfiler.CallSiteId{
                .source_file = "rare.jan",
                .line = 100,
                .column = 1,
                .signature_name = "cold_function",
            },
        };

        // Create test implementations
        const implementations = [_]SignatureAnalyzer.Implementation{
            SignatureAnalyzer.Implementation{
                .function_id = SignatureAnalyzer.FunctionId{
                    .name = "hot_function",
                    .module = "main",
                    .id = 1,
                },
                .param_type_ids = &.{},
                .return_type_id = 0,
                .effects = SatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
                .source_location = SignatureAnalyzer.SourceSpan.dummy(),
                .specificity_rank = 100,
            },
            SignatureAnalyzer.Implementation{
                .function_id = SignatureAnalyzer.FunctionId{
                    .name = "normal_function",
                    .module = "utils",
                    .id = 2,
                },
                .param_type_ids = &.{},
                .return_type_id = 0,
                .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
                .source_location = SignatureAnalyzer.SourceSpan.dummy(),
                .specificity_rank = 100,
            },
            SignatureAnalyzer.Implementation{
                .function_id = SignatureAnalyzer.FunctionId{
                    .name = "cold_function",
                    .module = "rare",
                    .id = 3,
                },
                .param_type_ids = &.{},
                .return_type_id = 0,
                .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
                .source_location = SignatureAnalyzer.SourceSpan.dummy(),
                .specificity_rank = 100,
            },
        };

        // Generate different call patterns

        // Hot path: many calls, high dispatch time, poor cache performance
        for (0..10000) |i| {
            const dispatch_time = 2000 + (i % 500); // 2-2.5μs
            const cache_hit = (i % 10) == 0; // 10% cache hit rate
            self.profiler.recordDispatchCall(call_sites[0], dispatch_time, &implementations[0], cache_hit);
        }

        // Normal path: moderate calls, moderate dispatch time, good cache performance
        for (0..1000) |i| {
            const dispatch_time = 800 + (i % 200); // 0.8-1.0μs
            const cache_hit = (i % 3) != 0; // 67% cache hit rate
            self.profiler.recordDispatchCall(call_sites[1], dispatch_time, &implementations[1], cache_hit);
        }

        // Cold path: few calls, low dispatch time, excellent cache performance
        for (0..50) |i| {
            const dispatch_time = 300 + (i % 100); // 0.3-0.4μs
            const cache_hit = (i % 20) != 0; // 95% cache hit rate
            self.profiler.recordDispatchCall(call_sites[2], dispatch_time, &implementations[2], cache_hit);
        }

        self.profiler.endSession();
    }

    /// Test basic visualization generation
    pub fn testBasicVisualization(self: *Self) !void {
        // Generate test data first
        try self.generateTestData();

        // Generate visualizations
        try self.visualizer.generateVisualizations(self.profiler);

        // Verify visualizations were generated
        const visualizations = self.visualizer.getVisualizations();
        try testing.expect(visualizations.len > 0);

        // Check that we have different types of visualizations
        var has_dispatch_graph = false;
        var has_call_hierarchy = false;
        var has_performance_heatmap = false;

        for (visualizations) |viz| {
            switch (viz.type) {
                .dispatch_graph => has_dispatch_graph = true,
                .call_hierarchy => has_call_hierarchy = true,
                .performance_heatmap => has_performance_heatmap = true,
                else => {},
            }

            // Verify basic visualization properties
            try testing.expect(viz.title.len > 0);
            try testing.expect(viz.description.len > 0);
            try testing.expect(viz.content.len > 0);
            try testing.expect(viz.metadata.creation_time > 0);
        }

        try testing.expect(has_dispatch_graph);
        try testing.expect(has_call_hierarchy);
        try testing.expect(has_performance_heatmap);
    }

    /// Test ASCII visualization content
    pub fn testASCIIVisualization(self: *Self) !void {
        try self.generateTestData();
        try self.visualizer.generateVisualizations(self.profiler);

        const ascii_vizs = self.visualizer.getVisualizationsByFormat(.ascii);
        defer self.allocator.free(ascii_vizs);

        try testing.expect(ascii_vizs.len > 0);

        for (ascii_vizs) |viz| {
            // Verify ASCII content contains expected elements
            try testing.expect(std.mem.indexOf(u8, viz.content, "hot_function") != null or
                std.mem.indexOf(u8, viz.content, "normal_function") != null or
                std.mem.indexOf(u8, viz.content, "cold_function") != null);

            // Check for performance indicators
            if (viz.type == .dispatch_graph) {
                try testing.expect(std.mem.indexOf(u8, viz.content, "🔥") != null); // Hot path indicator
                try testing.expect(std.mem.indexOf(u8, viz.content, "Calls:") != null);
                try testing.expect(std.mem.indexOf(u8, viz.content, "μs") != null); // Time units
            }

            if (viz.type == .performance_heatmap) {
                try testing.expect(std.mem.indexOf(u8, viz.content, "🟥") != null or
                    std.mem.indexOf(u8, viz.content, "🟧") != null or
                    std.mem.indexOf(u8, viz.content, "🟨") != null or
                    std.mem.indexOf(u8, viz.content, "🟩") != null); // Heat indicators
            }
        }
    }

    /// Test SVG visualization generation
    pub fn testSVGVisualization(self: *Self) !void {
        try self.generateTestData();
        try self.visualizer.generateVisualizations(self.profiler);

        const svg_vizs = self.visualizer.getVisualizationsByFormat(.svg);
        defer self.allocator.free(svg_vizs);

        try testing.expect(svg_vizs.len > 0);

        for (svg_vizs) |viz| {
            // Verify SVG structure
            try testing.expect(std.mem.indexOf(u8, viz.content, "<?xml") != null);
            try testing.expect(std.mem.indexOf(u8, viz.content, "<svg") != null);
            try testing.expect(std.mem.indexOf(u8, viz.content, "</svg>") != null);

            // Check for SVG elements
            if (viz.type == .dispatch_graph) {
                try testing.expect(std.mem.indexOf(u8, viz.content, "<circle") != null);
                try testing.expect(std.mem.indexOf(u8, viz.content, "<text") != null);
            }
        }
    }

    /// Test HTML visualization generation
    pub fn testHTMLVisualization(self: *Self) !void {
        try self.generateTestData();
        try self.visualizer.generateVisualizations(self.profiler);

        const html_vizs = self.visualizer.getVisualizationsByFormat(.html);
        defer self.allocator.free(html_vizs);

        try testing.expect(html_vizs.len > 0);

        for (html_vizs) |viz| {
            // Verify HTML structure
            try testing.expect(std.mem.indexOf(u8, viz.content, "<!DOCTYPE html>") != null);
            try testing.expect(std.mem.indexOf(u8, viz.content, "<html>") != null);
            try testing.expect(std.mem.indexOf(u8, viz.content, "</html>") != null);
            try testing.expect(std.mem.indexOf(u8, viz.content, "<table>") != null);

            // Check for performance data
            try testing.expect(std.mem.indexOf(u8, viz.content, "Total dispatch calls:") != null);
            try testing.expect(std.mem.indexOf(u8, viz.content, "Cache hit ratio:") != null);
        }
    }

    /// Test visualization filtering
    pub fn testVisualizationFiltering(self: *Self) !void {
        try self.generateTestData();
        try self.visualizer.generateVisualizations(self.profiler);

        // Test filtering by type
        const dispatch_graphs = self.visualizer.getVisualizationsByType(.dispatch_graph);
        defer self.allocator.free(dispatch_graphs);

        for (dispatch_graphs) |viz| {
            try testing.expectEqual(DispatchVisualizer.Visualization.VisualizationType.dispatch_graph, viz.type);
        }

        // Test filtering by format
        const svg_vizs = self.visualizer.getVisualizationsByFormat(.svg);
        defer self.allocator.free(svg_vizs);

        for (svg_vizs) |viz| {
            try testing.expectEqual(DispatchVisualizer.Visualization.OutputFormat.svg, viz.format);
        }
    }

    /// Test debugger basic functionality
    pub fn testDebuggerBasics(self: *Self) !void {
        // Start debug session
        self.debugger.startSession();
        try testing.expect(self.debugger.current_session != null);

        const session = self.debugger.current_session.?;
        try testing.expect(session.is_active);
        try testing.expect(!session.is_paused);
        try testing.expectEqual(@as(u64, 0), session.dispatches_traced);

        // End session
        self.debugger.endSession();
        try testing.expect(self.debugger.current_session == null);
    }

    /// Test breakpoint functionality
    pub fn testBreakpoints(self: *Self) !void {
        // Add call site breakpoint
        const bp_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
            .call_site = .{
                .source_file = "test.jan",
                .line = 42,
                .signature_name = null,
            },
        };

        const bp_id = try self.debugger.addBreakpoint(.call_site, bp_condition);
        try testing.expect(bp_id > 0);

        // Verify breakpoint was added
        try testing.expectEqual(@as(usize, 1), self.debugger.breakpoints.items.len);

        const breakpoint = &self.debugger.breakpoints.items[0];
        try testing.expectEqual(bp_id, breakpoint.id);
        try testing.expect(breakpoint.is_enabled);
        try testing.expectEqual(@as(u32, 0), breakpoint.hit_count);

        // Test breakpoint matching
        const call_site = DispatchProfiler.CallSiteId{
            .source_file = "test.jan",
            .line = 42,
            .column = 10,
            .signature_name = "test_func",
        };

        var frame = DispatchDebugger.ExecutionFrame.init(self.allocator, call_site, &.{});
        defer frame.deinit(self.allocator);

        try testing.expect(breakpoint.matches(&frame));

        // Remove breakpoint
        const removed = self.debugger.removeBreakpoint(bp_id);
        try testing.expect(removed);
        try testing.expectEqual(@as(usize, 0), self.debugger.breakpoints.items.len);
    }

    /// Test watch expressions
    pub fn testWatchExpressions(self: *Self) !void {
        // Add watch expression
        const watch_expr = DispatchDebugger.Watch.WatchExpression{
            .call_frequency = .{ .signature_name = "test_func" },
        };

        const watch_id = try self.debugger.addWatch("Test Watch", watch_expr);
        try testing.expect(watch_id > 0);

        // Verify watch was added
        try testing.expectEqual(@as(usize, 1), self.debugger.watches.items.len);

        const watch = &self.debugger.watches.items[0];
        try testing.expectEqual(watch_id, watch.id);
        try testing.expectEqualStrings("Test Watch", watch.name);
        try testing.expect(watch.is_enabled);

        // Test watch evaluation (should return null for non-existent signature)
        const value = watch.evaluate(self.profiler);
        try testing.expect(value == null);
    }

    /// Test execution frame creation and management
    pub fn testExecutionFrames(self: *Self) !void {
        const call_site = DispatchProfiler.CallSiteId{
            .source_file = "test.jan",
            .line = 42,
            .column = 10,
            .signature_name = "test_func",
        };

        var frame = DispatchDebugger.ExecutionFrame.init(self.allocator, call_site, &.{});
        defer frame.deinit(self.allocator);

        // Test basic frame properties
        try testing.expect(frame.frame_id > 0);
        try testing.expect(frame.timestamp > 0);
        try testing.expectEqualStrings("test.jan", frame.call_site.source_file);
        try testing.expectEqual(@as(u32, 42), frame.call_site.line);
        try testing.expectEqualStrings("test_func", frame.call_site.signature_name);

        // Test adding resolution steps
        try frame.addResolutionStep(self.allocator, .signature_lookup, "Looking up signature", "Found 3 candidates");
        try testing.expectEqual(@as(usize, 1), frame.resolution_steps.items.len);

        const step = &frame.resolution_steps.items[0];
        try testing.expectEqual(@as(u32, 1), step.step_number);
        try testing.expectEqual(DispatchDebugger.ExecutionFrame.ResolutionStep.StepType.signature_lookup, step.step_type);
        try testing.expectEqualStrings("Looking up signature", step.description);

        // Test adding debug notes
        try frame.addDebugNote(self.allocator, "This is a test note");
        try testing.expectEqual(@as(usize, 1), frame.debug_notes.items.len);
        try testing.expectEqualStrings("This is a test note", frame.debug_notes.items[0]);

        // Test adding warnings
        try frame.addWarning(self.allocator, "This is a test warning");
        try testing.expectEqual(@as(usize, 1), frame.warnings.items.len);
        try testing.expectEqualStrings("This is a test warning", frame.warnings.items[0]);

        // Test adding errors
        try frame.addError(self.allocator, "This is a test error");
        try testing.expectEqual(@as(usize, 1), frame.errors.items.len);
        try testing.expectEqualStrings("This is a test error", frame.errors.items[0]);
    }

    /// Test debug report generation
    pub fn testDebugReportGeneration(self: *Self) !void {
        // Start session and add some test data
        self.debugger.startSession();

        // Add a breakpoint
        const bp_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
            .call_site = .{
                .source_file = "test.jan",
                .line = 42,
                .signature_name = null,
            },
        };
        _ = try self.debugger.addBreakpoint(.call_site, bp_condition);

        // Add a watch
        const watch_expr = DispatchDebugger.Watch.WatchExpression{
            .call_frequency = .{ .signature_name = "test_func" },
        };
        _ = try self.debugger.addWatch("Test Watch", watch_expr);

        // Generate report
        var report_buffer: ArrayList(u8) = .empty;
        defer report_buffer.deinit();

        try self.debugger.generateDebugReport(report_buffer.writer());

        const report = report_buffer.items;

        // Verify report contains expected sections
        try testing.expect(std.mem.indexOf(u8, report, "Dispatch Debug Report") != null);
        try testing.expect(std.mem.indexOf(u8, report, "Session ID:") != null);
        try testing.expect(std.mem.indexOf(u8, report, "Breakpoints") != null);
        try testing.expect(std.mem.indexOf(u8, report, "Watch Expressions") != null);

        self.debugger.endSession();
    }

    /// Test visualization file saving
    pub fn testVisualizationSaving(self: *Self) !void {
        try self.generateTestData();
        try self.visualizer.generateVisualizations(self.profiler);

        const visualizations = self.visualizer.getVisualizations();
        if (visualizations.len > 0) {
            const viz = &visualizations[0];

            // Save to temporary file
            const temp_file = "test_viz_output.tmp";
            try self.visualizer.saveVisualization(viz, temp_file);

            // Verify file was created and contains expected content
            const file_content = try compat_fs.readFileAlloc(self.allocator, temp_file, std.math.maxInt(usize));
            defer self.allocator.free(file_content);

            try testing.expectEqualStrings(viz.content, file_content);

            // Clean up
            compat_fs.deleteFile(temp_file) catch {};
        }
    }

    /// Test performance characteristics
    pub fn testPerformanceCharacteristics(self: *Self) !void {
        // Generate large dataset
        self.profiler.startSession(null);

        const call_site = DispatchProfiler.CallSiteId{
            .source_file = "perf_test.jan",
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

        // Record many calls
        for (0..10000) |_| {
            self.profiler.recordDispatchCall(call_site, 1000, &impl, true);
        }

        self.profiler.endSession();

        // Measure visualization generation time
        const start_time = compat_time.nanoTimestamp();
        try self.visualizer.generateVisualizations(self.profiler);
        const end_time = compat_time.nanoTimestamp();

        const generation_time = end_time - start_time;

        // Should complete within reasonable time (< 100ms)
        try testing.expect(generation_time < 100 * std.time.ns_per_ms);

        // Verify visualizations were generated
        const visualizations = self.visualizer.getVisualizations();
        try testing.expect(visualizations.len > 0);
    }
};

// Test runner

test "Dispatch visualization and debugging comprehensive test suite" {
    const allocator = testing.allocator;

    var test_suite = try VisualizationTestSuite.init(allocator);
    defer test_suite.deinit();

    // Run all tests
    try test_suite.testBasicVisualization();
    try test_suite.testASCIIVisualization();
    try test_suite.testSVGVisualization();
    try test_suite.testHTMLVisualization();
    try test_suite.testVisualizationFiltering();
    try test_suite.testDebuggerBasics();
    try test_suite.testBreakpoints();
    try test_suite.testWatchExpressions();
    try test_suite.testExecutionFrames();
    try test_suite.testDebugReportGeneration();
    try test_suite.testVisualizationSaving();
    try test_suite.testPerformanceCharacteristics();
}

// Individual test cases for specific functionality

test "VisualizationMetadata validation" {
    const metadata = DispatchVisualizer.Visualization.VisualizationMetadata{
        .creation_time = 1234567890,
        .data_source = "test_profiler",
        .node_count = 15,
        .edge_count = 8,
        .complexity_score = 3.5,
    };

    try testing.expectEqual(@as(u64, 1234567890), metadata.creation_time);
    try testing.expectEqual(@as(u32, 15), metadata.node_count);
    try testing.expectEqual(@as(u32, 8), metadata.edge_count);
    try testing.expectEqual(@as(f64, 3.5), metadata.complexity_score);
}

test "DebugSession lifecycle" {
    var session = DispatchDebugger.DebugSession.init();

    try testing.expect(session.session_id > 0);
    try testing.expect(session.start_time > 0);
    try testing.expectEqual(@as(u64, 0), session.end_time);
    try testing.expect(session.is_active);
    try testing.expect(!session.is_paused);

    session.end();

    try testing.expect(!session.is_active);
    try testing.expect(session.end_time > 0);
    try testing.expect(session.getDuration() > 0);
}

test "Breakpoint condition types" {
    // Test call site condition
    const call_site_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
        .call_site = .{
            .source_file = "test.jan",
            .line = 42,
            .signature_name = "test_func",
        },
    };

    // Test signature condition
    const signature_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
        .signature = .{
            .name = "test_func",
            .module = "test_module",
        },
    };

    // Test slow dispatch condition
    const slow_dispatch_condition = DispatchDebugger.Breakpoint.BreakpointCondition{
        .slow_dispatch = .{
            .threshold_ns = 5000,
        },
    };

    // Verify conditions can be created
    try testing.expectEqual(DispatchDebugger.Breakpoint.BreakpointType.call_site, call_site_condition);
    try testing.expectEqual(DispatchDebugger.Breakpoint.BreakpointType.signature, signature_condition);
    try testing.expectEqual(DispatchDebugger.Breakpoint.BreakpointType.slow_dispatch, slow_dispatch_condition);
}

test "Watch value types" {
    const integer_value = DispatchDebugger.Watch.WatchValue{ .integer = 42 };
    const float_value = DispatchDebugger.Watch.WatchValue{ .float = 3.14 };
    const string_value = DispatchDebugger.Watch.WatchValue{ .string = "test" };
    const boolean_value = DispatchDebugger.Watch.WatchValue{ .boolean = true };

    switch (integer_value) {
        .integer => |i| try testing.expectEqual(@as(u64, 42), i),
        else => try testing.expect(false),
    }

    switch (float_value) {
        .float => |f| try testing.expectEqual(@as(f64, 3.14), f),
        else => try testing.expect(false),
    }

    switch (string_value) {
        .string => |s| try testing.expectEqualStrings("test", s),
        else => try testing.expect(false),
    }

    switch (boolean_value) {
        .boolean => |b| try testing.expect(b),
        else => try testing.expect(false),
    }
}
