// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const testing = std.testing;

const DispatchProfiler = @import("dispatch_profiler.zig").DispatchProfiler;
const DispatchVisualizer = @import("dispatch_visualizer.zig").DispatchVisualizer;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;

/// Interactive dispatch debugging and analysis system
pub const DispatchDebugger = struct {
    allocator: Allocator,

    // Debug configuration
    config: DebugConfig,

    // Debug session state
    current_session: ?DebugSession,

    // Breakpoints and watches
    breakpoints: ArrayList(Breakpoint),
    watches: ArrayList(Watch),

    // Debug history
    execution_history: ArrayList(ExecutionFrame),

    // Analysis tools
    profiler: ?*DispatchProfiler,
    visualizer: ?*DispatchVisualizer,

    const Self = @This();

    /// Debug configuration options
    pub const DebugConfig = struct {
        // Tracing options
        trace_all_dispatches: bool = false,
        trace_hot_paths_only: bool = true,
        trace_failed_dispatches: bool = true,
        trace_ambiguous_dispatches: bool = true,

        // Breakpoint options
        break_on_slow_dispatch: bool = false,
        slow_dispatch_threshold_ns: u64 = 10000, // 10μs
        break_on_cache_miss: bool = false,
        break_on_ambiguity: bool = true,

        // Output options
        verbose_output: bool = false,
        show_resolution_steps: bool = true,
        show_type_information: bool = true,
        show_performance_data: bool = true,

        // Analysis options
        enable_profiling: bool = true,
        enable_visualization: bool = true,
        auto_generate_reports: bool = false,

        pub fn default() DebugConfig {
            return DebugConfig{};
        }
    };

    /// Debug session management
    pub const DebugSession = struct {
        session_id: u64,
        start_time: u64,
        end_time: u64,

        // Session state
        is_active: bool,
        is_paused: bool,
        current_frame: ?*ExecutionFrame,

        // Session statistics
        dispatches_traced: u64,
        breakpoints_hit: u64,
        errors_encountered: u64,

        pub fn init() DebugSession {
            return DebugSession{
                .session_id = @intCast(std.time.nanoTimestamp()),
                .start_time = @intCast(std.time.nanoTimestamp()),
                .end_time = 0,
                .is_active = true,
                .is_paused = false,
                .current_frame = null,
                .dispatches_traced = 0,
                .breakpoints_hit = 0,
                .errors_encountered = 0,
            };
        }

        pub fn end(self: *DebugSession) void {
            self.end_time = @intCast(std.time.nanoTimestamp());
            self.is_active = false;
        }

        pub fn getDuration(self: *const DebugSession) u64 {
            const end = if (self.end_time > 0) self.end_time else @as(u64, @intCast(std.time.nanoTimestamp()));
            return end - self.start_time;
        }
    };

    /// Execution frame for debugging
    pub const ExecutionFrame = struct {
        frame_id: u64,
        timestamp: u64,

        // Call context
        call_site: DispatchProfiler.CallSiteId,
        argument_types: []const TypeRegistry.TypeId,

        // Resolution process
        resolution_steps: ArrayList(ResolutionStep),
        candidates: ArrayList(CandidateInfo),

        // Final result
        selected_implementation: ?*const SignatureAnalyzer.Implementation,
        dispatch_time_ns: u64,
        cache_hit: bool,

        // Debug information
        debug_notes: ArrayList([]const u8),
        warnings: ArrayList([]const u8),
        errors: ArrayList([]const u8),

        pub const ResolutionStep = struct {
            step_number: u32,
            step_type: StepType,
            description: []const u8,
            candidates_before: u32,
            candidates_after: u32,
            time_taken_ns: u64,
            details: []const u8,

            pub const StepType = enum {
                signature_lookup,
                type_filtering,
                specificity_analysis,
                ambiguity_resolution,
                cache_lookup,
                final_selection,
                error_handling,
            };
        };

        pub const CandidateInfo = struct {
            implementation: *const SignatureAnalyzer.Implementation,
            specificity_score: u32,
            match_quality: f64,
            rejection_reason: ?[]const u8,
            is_selected: bool,
        };

        pub fn init(allocator: Allocator, call_site: DispatchProfiler.CallSiteId, argument_types: []const TypeRegistry.TypeId) ExecutionFrame {
            return ExecutionFrame{
                .frame_id = @intCast(std.time.nanoTimestamp()),
                .timestamp = @intCast(std.time.nanoTimestamp()),
                .call_site = call_site,
                .argument_types = argument_types,
                .resolution_steps = .empty,
                .candidates = .empty,
                .selected_implementation = null,
                .dispatch_time_ns = 0,
                .cache_hit = false,
                .debug_notes = .empty,
                .warnings = .empty,
                .errors = .empty,
            };
        }

        pub fn deinit(self: *ExecutionFrame, allocator: Allocator) void {
            for (self.resolution_steps.items) |*step| {
                allocator.free(step.description);
                allocator.free(step.details);
            }
            self.resolution_steps.deinit();

            for (self.candidates.items) |*candidate| {
                if (candidate.rejection_reason) |reason| {
                    allocator.free(reason);
                }
            }
            self.candidates.deinit();

            for (self.debug_notes.items) |note| {
                allocator.free(note);
            }
            self.debug_notes.deinit();

            for (self.warnings.items) |warning| {
                allocator.free(warning);
            }
            self.warnings.deinit();

            for (self.errors.items) |error_msg| {
                allocator.free(error_msg);
            }
            self.errors.deinit();

            allocator.free(self.argument_types);
        }

        pub fn addResolutionStep(self: *ExecutionFrame, allocator: Allocator, step_type: ResolutionStep.StepType, description: []const u8, details: []const u8) !void {
            const step = ResolutionStep{
                .step_number = @intCast(self.resolution_steps.items.len + 1),
                .step_type = step_type,
                .description = try allocator.dupe(u8, description),
                .candidates_before = @intCast(self.candidates.items.len),
                .candidates_after = 0, // Will be updated later
                .time_taken_ns = 0, // Will be updated later
                .details = try allocator.dupe(u8, details),
            };

            try self.resolution_steps.append(step);
        }

        pub fn addCandidate(self: *ExecutionFrame, implementation: *const SignatureAnalyzer.Implementation, specificity_score: u32, match_quality: f64) !void {
            const candidate = CandidateInfo{
                .implementation = implementation,
                .specificity_score = specificity_score,
                .match_quality = match_quality,
                .rejection_reason = null,
                .is_selected = false,
            };

            try self.candidates.append(candidate);
        }

        pub fn rejectCandidate(self: *ExecutionFrame, allocator: Allocator, implementation: *const SignatureAnalyzer.Implementation, reason: []const u8) !void {
            for (self.candidates.items) |*candidate| {
                if (candidate.implementation == implementation) {
                    candidate.rejection_reason = try allocator.dupe(u8, reason);
                    break;
                }
            }
        }

        pub fn selectImplementation(self: *ExecutionFrame, implementation: *const SignatureAnalyzer.Implementation) void {
            self.selected_implementation = implementation;

            for (self.candidates.items) |*candidate| {
                candidate.is_selected = (candidate.implementation == implementation);
            }
        }

        pub fn addDebugNote(self: *ExecutionFrame, allocator: Allocator, note: []const u8) !void {
            try self.debug_notes.append(try allocator.dupe(u8, note));
        }

        pub fn addWarning(self: *ExecutionFrame, allocator: Allocator, warning: []const u8) !void {
            try self.warnings.append(try allocator.dupe(u8, warning));
        }

        pub fn addError(self: *ExecutionFrame, allocator: Allocator, error_msg: []const u8) !void {
            try self.errors.append(try allocator.dupe(u8, error_msg));
        }
    };

    /// Breakpoint configuration
    pub const Breakpoint = struct {
        id: u64,
        type: BreakpointType,
        condition: BreakpointCondition,
        is_enabled: bool,
        hit_count: u32,

        pub const BreakpointType = enum {
            call_site,
            signature,
            slow_dispatch,
            cache_miss,
            ambiguous_dispatch,
            error_condition,
        };

        pub const BreakpointCondition = union(BreakpointType) {
            call_site: struct {
                source_file: []const u8,
                line: u32,
                signature_name: ?[]const u8,
            },
            signature: struct {
                name: []const u8,
                module: ?[]const u8,
            },
            slow_dispatch: struct {
                threshold_ns: u64,
            },
            cache_miss: struct {
                consecutive_misses: u32,
            },
            ambiguous_dispatch: struct {
                min_candidates: u32,
            },
            error_condition: struct {
                error_type: []const u8,
            },
        };

        pub fn matches(self: *const Breakpoint, frame: *const ExecutionFrame) bool {
            if (!self.is_enabled) return false;

            switch (self.condition) {
                .call_site => |cond| {
                    const matches_file = std.mem.eql(u8, cond.source_file, frame.call_site.source_file);
                    const matches_line = cond.line == frame.call_site.line;
                    const matches_signature = if (cond.signature_name) |name|
                        std.mem.eql(u8, name, frame.call_site.signature_name)
                    else
                        true;

                    return matches_file and matches_line and matches_signature;
                },
                .signature => |cond| {
                    const matches_name = std.mem.eql(u8, cond.name, frame.call_site.signature_name);
                    // TODO: Add module matching when available
                    return matches_name;
                },
                .slow_dispatch => |cond| {
                    return frame.dispatch_time_ns >= cond.threshold_ns;
                },
                .cache_miss => |_| {
                    return !frame.cache_hit;
                },
                .ambiguous_dispatch => |cond| {
                    return frame.candidates.items.len >= cond.min_candidates;
                },
                .error_condition => |_| {
                    return frame.errors.items.len > 0;
                },
            }
        }
    };

    /// Watch expression for monitoring values
    pub const Watch = struct {
        id: u64,
        name: []const u8,
        expression: WatchExpression,
        is_enabled: bool,
        last_value: ?WatchValue,

        pub const WatchExpression = union(enum) {
            call_frequency: struct {
                signature_name: []const u8,
            },
            dispatch_time: struct {
                call_site: DispatchProfiler.CallSiteId,
            },
            cache_hit_ratio: struct {
                signature_name: []const u8,
            },
            implementation_count: struct {
                signature_name: []const u8,
            },
        };

        pub const WatchValue = union(enum) {
            integer: u64,
            float: f64,
            string: []const u8,
            boolean: bool,
        };

        pub fn evaluate(self: *Watch, profiler: *const DispatchProfiler) ?WatchValue {
            switch (self.expression) {
                .call_frequency => |expr| {
                    if (profiler.getSignatureProfile(expr.signature_name)) |profile| {
                        return WatchValue{ .integer = profile.total_calls };
                    }
                },
                .dispatch_time => |expr| {
                    if (profiler.getCallSiteProfile(expr.call_site)) |profile| {
                        return WatchValue{ .float = profile.avg_dispatch_time };
                    }
                },
                .cache_hit_ratio => |expr| {
                    if (profiler.getSignatureProfile(expr.signature_name)) |_| {
                        // TODO: Calculate cache hit ratio for signature
                        return WatchValue{ .float = 0.0 };
                    }
                },
                .implementation_count => |expr| {
                    if (profiler.getSignatureProfile(expr.signature_name)) |profile| {
                        return WatchValue{ .integer = @intCast(profile.implementations.count()) };
                    }
                },
            }
            return null;
        }
    };

    pub fn init(allocator: Allocator, config: DebugConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .current_session = null,
            .breakpoints = .empty,
            .watches = .empty,
            .execution_history = .empty,
            .profiler = null,
            .visualizer = null,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up execution history
        for (self.execution_history.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.execution_history.deinit();

        // Clean up breakpoints
        for (self.breakpoints.items) |*bp| {
            switch (bp.condition) {
                .call_site => |cond| {
                    self.allocator.free(cond.source_file);
                    if (cond.signature_name) |name| {
                        self.allocator.free(name);
                    }
                },
                .signature => |cond| {
                    self.allocator.free(cond.name);
                    if (cond.module) |module| {
                        self.allocator.free(module);
                    }
                },
                .error_condition => |cond| {
                    self.allocator.free(cond.error_type);
                },
                else => {},
            }
        }
        self.breakpoints.deinit();

        // Clean up watches
        for (self.watches.items) |*watch| {
            self.allocator.free(watch.name);
            switch (watch.expression) {
                .call_frequency => |expr| {
                    self.allocator.free(expr.signature_name);
                },
                .cache_hit_ratio => |expr| {
                    self.allocator.free(expr.signature_name);
                },
                .implementation_count => |expr| {
                    self.allocator.free(expr.signature_name);
                },
                else => {},
            }

            if (watch.last_value) |value| {
                switch (value) {
                    .string => |str| self.allocator.free(str),
                    else => {},
                }
            }
        }
        self.watches.deinit();
    }

    /// Start a debug session
    pub fn startSession(self: *Self) void {
        self.current_session = DebugSession.init();

        // Initialize profiler if enabled
        if (self.config.enable_profiling and self.profiler == null) {
            const profiler_config = DispatchProfiler.ProfilingConfig.default();
            var profiler = self.allocator.create(DispatchProfiler) catch return;
            profiler.* = DispatchProfiler.init(self.allocator, profiler_config);
            self.profiler = profiler;
            self.profiler.?.startSession(null);
        }

        // Initialize visualizer if enabled
        if (self.config.enable_visualization and self.visualizer == null) {
            const viz_config = DispatchVisualizer.VisualizationConfig{};
            var visualizer = self.allocator.create(DispatchVisualizer) catch return;
            visualizer.* = DispatchVisualizer.init(self.allocator, viz_config);
            self.visualizer = visualizer;
        }
    }

    /// End the current debug session
    pub fn endSession(self: *Self) void {
        if (self.current_session) |*session| {
            session.end();

            // End profiler session
            if (self.profiler) |profiler| {
                profiler.endSession();
            }

            // Generate reports if enabled
            if (self.config.auto_generate_reports) {
                var stderr_buffer: [1024]u8 = undefined;
                var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
                self.generateDebugReport(&stderr_writer.interface) catch {};
                stderr_writer.flush() catch {};
            }

            self.current_session = null;
        }
    }

    /// Trace a dispatch call
    pub fn traceDispatch(self: *Self, call_site: DispatchProfiler.CallSiteId, argument_types: []const TypeRegistry.TypeId) !*ExecutionFrame {
        // Check if we should trace this dispatch
        if (!self.shouldTrace(call_site)) {
            return error.TracingDisabled;
        }

        // Create execution frame
        var frame = ExecutionFrame.init(self.allocator, call_site, try self.allocator.dupe(TypeRegistry.TypeId, argument_types));

        // Update session statistics
        if (self.current_session) |*session| {
            session.dispatches_traced += 1;
            session.current_frame = &frame;
        }

        // Add to execution history
        try self.execution_history.append(frame);

        return &self.execution_history.items[self.execution_history.items.len - 1];
    }

    /// Check if execution should break at current frame
    pub fn shouldBreak(self: *Self, frame: *const ExecutionFrame) bool {
        for (self.breakpoints.items) |*bp| {
            if (bp.matches(frame)) {
                bp.hit_count += 1;

                if (self.current_session) |*session| {
                    session.breakpoints_hit += 1;
                    session.is_paused = true;
                }

                return true;
            }
        }

        return false;
    }

    /// Add a breakpoint
    pub fn addBreakpoint(self: *Self, bp_type: Breakpoint.BreakpointType, condition: Breakpoint.BreakpointCondition) !u64 {
        const bp_id = @as(u64, @intCast(std.time.nanoTimestamp()));

        const breakpoint = Breakpoint{
            .id = bp_id,
            .type = bp_type,
            .condition = condition,
            .is_enabled = true,
            .hit_count = 0,
        };

        try self.breakpoints.append(breakpoint);
        return bp_id;
    }

    /// Remove a breakpoint
    pub fn removeBreakpoint(self: *Self, bp_id: u64) bool {
        for (self.breakpoints.items, 0..) |bp, i| {
            if (bp.id == bp_id) {
                _ = self.breakpoints.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Add a watch expression
    pub fn addWatch(self: *Self, name: []const u8, expression: Watch.WatchExpression) !u64 {
        const watch_id = @as(u64, @intCast(std.time.nanoTimestamp()));

        const watch = Watch{
            .id = watch_id,
            .name = try self.allocator.dupe(u8, name),
            .expression = expression,
            .is_enabled = true,
            .last_value = null,
        };

        try self.watches.append(watch);
        return watch_id;
    }

    /// Update all watch expressions
    pub fn updateWatches(self: *Self) void {
        if (self.profiler) |profiler| {
            for (self.watches.items) |*watch| {
                if (watch.is_enabled) {
                    watch.last_value = watch.evaluate(profiler);
                }
            }
        }
    }

    /// Generate comprehensive debug report
    pub fn generateDebugReport(self: *Self, writer: anytype) !void {
        try writer.writeAll("Dispatch Debug Report\n");
        try writer.writeAll("====================\n\n");

        // Session information
        if (self.current_session) |session| {
            try writer.print("Session ID: {}\n", .{session.session_id});
            try writer.print("Duration: {d:.1}ms\n", .{@as(f64, @floatFromInt(session.getDuration())) / 1_000_000.0});
            try writer.print("Dispatches traced: {}\n", .{session.dispatches_traced});
            try writer.print("Breakpoints hit: {}\n", .{session.breakpoints_hit});
            try writer.print("Errors encountered: {}\n", .{session.errors_encountered});
            try writer.writeAll("\n");
        }

        // Execution history summary
        try writer.print("Execution History ({} frames):\n", .{self.execution_history.items.len});
        try writer.writeAll("--------------------------------\n");

        for (self.execution_history.items, 0..) |frame, i| {
            if (i >= 10) { // Limit to first 10 frames
                try writer.print("... and {} more frames\n", .{self.execution_history.items.len - 10});
                break;
            }

            try writer.print("Frame {}: {}:{} ({})\n", .{
                i + 1,
                frame.call_site.source_file,
                frame.call_site.line,
                frame.call_site.signature_name,
            });

            if (frame.selected_implementation) |impl| {
                try writer.print("  Selected: {s} ({d:.1}μs)\n", .{
                    impl.function_id.name,
                    @as(f64, @floatFromInt(frame.dispatch_time_ns)) / 1000.0,
                });
            } else {
                try writer.writeAll("  No implementation selected\n");
            }

            if (frame.errors.items.len > 0) {
                try writer.print("  Errors: {}\n", .{frame.errors.items.len});
            }

            if (frame.warnings.items.len > 0) {
                try writer.print("  Warnings: {}\n", .{frame.warnings.items.len});
            }
        }

        try writer.writeAll("\n");

        // Breakpoints status
        try writer.print("Breakpoints ({}):\n", .{self.breakpoints.items.len});
        try writer.writeAll("------------------\n");

        for (self.breakpoints.items) |bp| {
            const status = if (bp.is_enabled) "enabled" else "disabled";
            try writer.print("  {} ({}): {} hits\n", .{ bp.type, status, bp.hit_count });
        }

        try writer.writeAll("\n");

        // Watch expressions
        try writer.print("Watch Expressions ({}):\n", .{self.watches.items.len});
        try writer.writeAll("------------------------\n");

        for (self.watches.items) |watch| {
            try writer.print("  {s}: ", .{watch.name});

            if (watch.last_value) |value| {
                switch (value) {
                    .integer => |i| try writer.print("{}\n", .{i}),
                    .float => |f| try writer.print("{d:.2}\n", .{f}),
                    .string => |s| try writer.print("\"{s}\"\n", .{s}),
                    .boolean => |b| try writer.print("{}\n", .{b}),
                }
            } else {
                try writer.writeAll("(no value)\n");
            }
        }

        // Include profiler report if available
        if (self.profiler) |profiler| {
            try writer.writeAll("\nProfiler Data:\n");
            try writer.writeAll("--------------\n");
            try profiler.generateReport(writer);
        }
    }

    /// Get execution frame by ID
    pub fn getExecutionFrame(self: *const Self, frame_id: u64) ?*const ExecutionFrame {
        for (self.execution_history.items) |*frame| {
            if (frame.frame_id == frame_id) {
                return frame;
            }
        }
        return null;
    }

    /// Get recent execution frames
    pub fn getRecentFrames(self: *const Self, count: u32) []const ExecutionFrame {
        const start_idx = if (self.execution_history.items.len > count)
            self.execution_history.items.len - count
        else
            0;

        return self.execution_history.items[start_idx..];
    }

    /// Clear execution history
    pub fn clearHistory(self: *Self) void {
        for (self.execution_history.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.execution_history.clearAndFree();
    }

    // Private helper methods

    fn shouldTrace(self: *const Self, call_site: DispatchProfiler.CallSiteId) bool {
        if (self.config.trace_all_dispatches) return true;

        if (self.config.trace_hot_paths_only) {
            // Check if this is a hot path (simplified check)
            if (self.profiler) |profiler| {
                if (profiler.getCallSiteProfile(call_site)) |profile| {
                    return profile.is_hot_path;
                }
            }
        }

        return false;
    }
};

// Tests

test "DispatchDebugger basic functionality" {
    const allocator = testing.allocator;

    const config = DispatchDebugger.DebugConfig.default();
    var debugger = DispatchDebugger.init(allocator, config);
    defer debugger.deinit();

    // Start debug session
    debugger.startSession();
    try testing.expect(debugger.current_session != null);

    // Create test call site
    const call_site = DispatchProfiler.CallSiteId{
        .source_file = "test.jan",
        .line = 42,
        .column = 10,
        .signature_name = "test_func",
    };

    // Trace a dispatch (will fail due to tracing disabled, but that's expected)
    const trace_result = debugger.traceDispatch(call_site, &.{});
    try testing.expectError(error.TracingDisabled, trace_result);

    // End session
    debugger.endSession();
    try testing.expect(debugger.current_session == null);
}

test "Breakpoint matching" {
    const call_site = DispatchProfiler.CallSiteId{
        .source_file = "test.jan",
        .line = 42,
        .column = 10,
        .signature_name = "test_func",
    };

    const breakpoint = DispatchDebugger.Breakpoint{
        .id = 1,
        .type = .call_site,
        .condition = DispatchDebugger.Breakpoint.BreakpointCondition{
            .call_site = .{
                .source_file = "test.jan",
                .line = 42,
                .signature_name = null,
            },
        },
        .is_enabled = true,
        .hit_count = 0,
    };

    const allocator = testing.allocator;
    var frame = DispatchDebugger.ExecutionFrame.init(allocator, call_site, &.{});
    defer frame.deinit(allocator);

    // Should match
    try testing.expect(breakpoint.matches(&frame));
}

test "Watch expression evaluation" {
    const allocator = testing.allocator;

    // Create mock profiler
    const profiler_config = DispatchProfiler.ProfilingConfig.default();
    var profiler = DispatchProfiler.init(allocator, profiler_config);
    defer profiler.deinit();

    var watch = DispatchDebugger.Watch{
        .id = 1,
        .name = "test_watch",
        .expression = DispatchDebugger.Watch.WatchExpression{
            .call_frequency = .{ .signature_name = "test_func" },
        },
        .is_enabled = true,
        .last_value = null,
    };

    // Should return null for non-existent signature
    const value = watch.evaluate(&profiler);
    try testing.expect(value == null);
}
