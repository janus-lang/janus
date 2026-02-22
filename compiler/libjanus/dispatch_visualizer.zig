// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const testing = std.testing;

const DispatchProfiler = @import("dispatch_profiler.zig").DispatchProfiler;
const OptimizedDispatchTable = @import("optimized_dispatch_tables.zig").OptimizedDispatchTable;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;

/// Comprehensive dispatch visualization and debugging system
pub const DispatchVisualizer = struct {
    allocator: Allocator,
    config: VisualizationConfig,
    visualizations: ArrayList(Visualization),
    debug_info: DebugInfo,

    const Self = @This();

    pub const VisualizationConfig = struct {
        generate_svg: bool = true,
        generate_html: bool = true,
        generate_dot: bool = false,
        generate_ascii: bool = true,
        color_scheme: ColorScheme = .performance_heatmap,
        layout_algorithm: LayoutAlgorithm = .hierarchical,
        show_performance_data: bool = true,
        show_type_information: bool = true,
        show_source_locations: bool = false,
        min_call_frequency: u64 = 10,
        max_nodes: u32 = 100,
        focus_hot_paths: bool = true,

        pub const ColorScheme = enum { default, high_contrast, colorblind_friendly, performance_heatmap };
        pub const LayoutAlgorithm = enum { hierarchical, force_directed, circular, tree };
    };

    pub const Visualization = struct {
        id: u64,
        type: VisualizationType,
        format: OutputFormat,
        title: []const u8,
        description: []const u8,
        content: []const u8,
        metadata: VisualizationMetadata,

        pub const VisualizationType = enum {
            dispatch_graph, call_hierarchy, performance_heatmap, decision_tree,
            type_hierarchy, hot_path_flow, cache_analysis, implementation_distribution,
        };

        pub const OutputFormat = enum { svg, html, dot, ascii, json };

        pub const VisualizationMetadata = struct {
            creation_time: u64,
            data_source: []const u8,
            node_count: u32,
            edge_count: u32,
            complexity_score: f64,
        };
    };

    pub const DebugInfo = struct {
        dispatch_traces: ArrayList(DispatchTrace),
        resolution_steps: ArrayList(ResolutionStep),
        error_diagnostics: ArrayList(ErrorDiagnostic),
        performance_annotations: ArrayList(PerformanceAnnotation),

        pub const DispatchTrace = struct {
            call_site: DispatchProfiler.CallSiteId,
            timestamp: u64,
            argument_types: []const TypeRegistry.TypeId,
            resolution_path: []const ResolutionStep,
            final_implementation: ?*const SignatureAnalyzer.Implementation,
            dispatch_time_ns: u64,
            cache_hit: bool,
        };

        pub const ResolutionStep = struct {
            step_type: StepType,
            description: []const u8,
            candidates_before: u32,
            candidates_after: u32,
            time_taken_ns: u64,

            pub const StepType = enum {
                signature_lookup, type_filtering, specificity_analysis,
                ambiguity_check, cache_lookup, final_selection,
            };
        };

        pub const ErrorDiagnostic = struct {
            error_type: ErrorType,
            call_site: DispatchProfiler.CallSiteId,
            message: []const u8,
            suggestions: []const []const u8,
            related_implementations: []const *const SignatureAnalyzer.Implementation,

            pub const ErrorType = enum {
                no_matching_implementation, ambiguous_dispatch, type_mismatch,
                missing_import, circular_dependency,
            };
        };

        pub const PerformanceAnnotation = struct {
            location: DispatchProfiler.CallSiteId,
            annotation_type: AnnotationType,
            severity: Severity,
            message: []const u8,
            suggested_optimization: ?[]const u8,

            pub const AnnotationType = enum {
                slow_dispatch, cache_miss, hot_path,
                optimization_opportunity, performance_regression,
            };

            pub const Severity = enum {
                info,
                warning,
                error
                critical,
            };
        };

        pub fn init(allocator: Allocator) DebugInfo {
            return DebugInfo{
                .dispatch_traces = .empty,
                .resolution_steps = .empty,
                .error_diagnostics = .empty,
                .performance_annotations = .empty,
            };
        }

        pub fn deinit(self: *DebugInfo, allocator: Allocator) void {
            for (self.dispatch_traces.items) |*trace| {
                allocator.free(trace.argument_types);
                allocator.free(trace.resolution_path);
            }
            self.dispatch_traces.deinit();

            for (self.resolution_steps.items) |*step| {
                allocator.free(step.description);
            }
            self.resolution_steps.deinit();

            for (self.error_diagnostics.items) |*diagnostic| {
                allocator.free(diagnostic.message);
                for (diagnostic.suggestions) |suggestion| {
                    allocator.free(suggestion);
                }
                allocator.free(diagnostic.suggestions);
                allocator.free(diagnostic.related_implementations);
            }
            self.error_diagnostics.deinit();

            for (self.performance_annotations.items) |*annotation| {
                allocator.free(annotation.message);
                if (annotation.suggested_optimization) |opt| {
                    allocator.free(opt);
                }
            }
            self.performance_annotations.deinit();
        }
    };

    pub fn init(allocator: Allocator, config: VisualizationConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .visualizations = .empty,
            .debug_info = DebugInfo.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.visualizations.items) |*viz| {
            self.allocator.free(viz.title);
            self.allocator.free(viz.description);
            self.allocator.free(viz.content);
        }
        self.visualizations.deinit();
        self.debug_info.deinit(self.allocator);
    }

    /// Generate all visualizations from profiling data
    pub fn generateVisualizations(self: *Self, profiler: *const DispatchProfiler) !void {
        // Clear existing visualizations
        self.clearVisualizations();

        // Generate different types of visualizations
        if (self.config.generate_ascii) {
            try self.generateDispatchGraphASCII(profiler);
            try self.generateCallHierarchyASCII(profiler);
            try self.generatePerformanceHeatmapASCII(profiler);
        }

        if (self.config.generate_svg) {
            try self.generateDispatchGraphSVG(profiler);
            try self.generateDecisionTreeSVG(profiler);
            try self.generateHotPathFlowSVG(profiler);
        }

        if (self.config.generate_html) {
            try self.generateInteractiveHTML(profiler);
        }

        if (self.config.generate_dot) {
            try self.generateDotGraph(profiler);
        }
    }

    /// Generate ASCII dispatch graph visualization
    pub fn generateDispatchGraphASCII(self: *Self, profiler: *const DispatchProfiler) !void {
        var content: ArrayList(u8) = .empty;
        defer content.deinit();

        const writer = content.writer();

        try writer.writeAll("Dispatch Graph (ASCII)\n");
        try writer.writeAll("=====================\n\n");

        // Get hot call sites for visualization
        var hot_sites: ArrayList(*const DispatchProfiler.CallProfile) = .empty;
        defer hot_sites.deinit();

        var call_iter = profiler.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;
            if (profile.total_calls >= self.config.min_call_frequency) {
                if (!self.config.focus_hot_paths or profile.is_hot_path) {
                    try hot_sites.append(profile);
                }
            }
        }

        // Sort by call frequency
        const Context = struct {
            pub fn lessThan(context: @This(), a: *const DispatchProfiler.CallProfile, b: *const DispatchProfiler.CallProfile) bool {
                _ = context;
                return a.total_calls > b.total_calls;
            }
        };
        std.mem.sort(*const DispatchProfiler.CallProfile, hot_sites.items, Context{}, Context.lessThan);

        // Limit to max nodes
        const display_count = @min(hot_sites.items.len, self.config.max_nodes);

        for (hot_sites.items[0..display_count]) |profile| {
            const hotness_indicator = if (profile.is_hot_path) "🔥" else "  ";
            const cache_indicator = if (profile.cache_hit_ratio > 0.8) "✓" else if (profile.cache_hit_ratio > 0.5) "~" else "✗";

            try writer.print("{s} {s} {}:{} ({})\n", .{
                hotness_indicator,
                cache_indicator,
                profile.call_site.source_file,
                profile.call_site.line,
                profile.call_site.signature_name,
            });

            try writer.print("    Calls: {} ({d:.1}/sec)\n", .{ profile.total_calls, profile.calls_per_second });
            try writer.print("    Dispatch: {d:.1}μs avg\n", .{ profile.avg_dispatch_time / 1000.0 });
            try writer.print("    Cache: {d:.1}% hit ratio\n", .{ profile.cache_hit_ratio * 100.0 });
            try writer.print("    Implementations: {}\n", .{ profile.implementations_used.count() });

            if (self.config.show_performance_data) {
                try writer.print("    Hotness: {d:.1}\n", .{ profile.hotness_score });
            }

            try writer.writeAll("\n");
        }

        const viz = Visualization{
            .id = @intCast(std.time.nanoTimestamp()),
            .type = .dispatch_graph,
            .format = .ascii,
            .title = try self.allocator.dupe(u8, "Dispatch Graph"),
            .description = try self.allocator.dupe(u8, "ASCII visualization of dispatch call sites"),
            .content = try content.toOwnedSlice(),
            .metadata = Visualization.VisualizationMetadata{
                .creation_time = @intCast(std.time.nanoTimestamp()),
                .data_source = try self.allocator.dupe(u8, "profiler"),
                .node_count = @intCast(display_count),
                .edge_count = 0,
                .complexity_score = @as(f64, @floatFromInt(display_count)) / 10.0,
            },
        };

        try self.visualizations.append(viz);
    }

    /// Generate ASCII call hierarchy visualization
    pub fn generateCallHierarchyASCII(self: *Self, profiler: *const DispatchProfiler) !void {
        var content: ArrayList(u8) = .empty;
        defer content.deinit();

        const writer = content.writer();

        try writer.writeAll("Call Hierarchy (ASCII)\n");
        try writer.writeAll("======================\n\n");

        // Group by signature
        var signature_groups = HashMap([]const u8, ArrayList(*const DispatchProfiler.CallProfile)).init(self.allocator);
        defer {
            var iter = signature_groups.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            signature_groups.deinit();
        }

        var call_iter = profiler.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;
            if (profile.total_calls >= self.config.min_call_frequency) {
                const signature = profile.call_site.signature_name;

                if (signature_groups.getPtr(signature)) |group| {
                    try group.append(profile);
                } else {
                    var new_group: ArrayList(*const DispatchProfiler.CallProfile) = .empty;
                    try new_group.append(profile);
                    try signature_groups.put(signature, new_group);
                }
            }
        }

        // Display hierarchy
        var sig_iter = signature_groups.iterator();
        while (sig_iter.next()) |entry| {
            const signature = entry.key_ptr.*;
            const profiles = entry.value_ptr.items;

            var total_calls: u64 = 0;
            for (profiles) |profile| {
                total_calls += profile.total_calls;
            }

            try writer.print("📋 {} ({} total calls)\n", .{ signature, total_calls });

            for (profiles, 0..) |profile, i| {
                const is_last = i == profiles.len - 1;
                const prefix = if (is_last) "└── " else "├── ";
                const hotness = if (profile.is_hot_path) "🔥 " else "";

                try writer.print("  {s}{s}{}:{} ({} calls)\n", .{
                    prefix,
                    hotness,
                    profile.call_site.source_file,
                    profile.call_site.line,
                    profile.total_calls,
                });
            }

            try writer.writeAll("\n");
        }

        const viz = Visualization{
            .id = @intCast(std.time.nanoTimestamp()),
            .type = .call_hierarchy,
            .format = .ascii,
            .title = try self.allocator.dupe(u8, "Call Hierarchy"),
            .description = try self.allocator.dupe(u8, "Hierarchical view of dispatch calls by signature"),
            .content = try content.toOwnedSlice(),
            .metadata = Visualization.VisualizationMetadata{
                .creation_time = @intCast(std.time.nanoTimestamp()),
                .data_source = try self.allocator.dupe(u8, "profiler"),
                .node_count = @intCast(signature_groups.count()),
                .edge_count = @intCast(profiler.call_profiles.count()),
                .complexity_score = @as(f64, @floatFromInt(signature_groups.count())) / 5.0,
            },
        };

        try self.visualizations.append(viz);
    }

    /// Generate ASCII performance heatmap
    pub fn generatePerformanceHeatmapASCII(self: *Self, profiler: *const DispatchProfiler) !void {
        var content: ArrayList(u8) = .empty;
        defer content.deinit();

        const writer = content.writer();

        try writer.writeAll("Performance Heatmap (ASCII)\n");
        try writer.writeAll("===========================\n\n");

        // Collect performance data
        var perf_data: ArrayList(struct { profile: *const DispatchProfiler.CallProfile, score: f64 }) = .empty;
        defer perf_data.deinit();

        var call_iter = profiler.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;
            if (profile.total_calls >= self.config.min_call_frequency) {
                // Calculate performance score (higher = worse performance)
                const freq_factor = @as(f64, @floatFromInt(profile.total_calls)) / 1000.0;
                const time_factor = profile.avg_dispatch_time / 1000.0; // Convert to μs
                const cache_penalty = (1.0 - profile.cache_hit_ratio) * 2.0;
                const score = freq_factor * time_factor * (1.0 + cache_penalty);

                try perf_data.append(.{ .profile = profile, .score = score });
            }
        }

        // Sort by performance score
        const Context = struct {
            pub fn lessThan(context: @This(), a: @TypeOf(perf_data.items[0]), b: @TypeOf(perf_data.items[0])) bool {
                _ = context;
                return a.score > b.score;
            }
        };
        std.mem.sort(@TypeOf(perf_data.items[0]), perf_data.items, Context{}, Context.lessThan);

        // Generate heatmap
        try writer.writeAll("Legend: 🟥 Critical  🟧 High  🟨 Medium  🟩 Low\n\n");

        const display_count = @min(perf_data.items.len, self.config.max_nodes);
        for (perf_data.items[0..display_count]) |item| {
            const profile = item.profile;
            const score = item.score;

            // Determine heat level
            const heat_indicator = if (score > 10.0) "🟥" else if (score > 5.0) "🟧" else if (score > 2.0) "🟨" else "🟩";

            try writer.print("{s} {}:{} ({})\n", .{
                heat_indicator,
                profile.call_site.source_file,
                profile.call_site.line,
                profile.call_site.signature_name,
            });

            try writer.print("    Score: {d:.1} | Calls: {} | Time: {d:.1}μs | Cache: {d:.0}%\n", .{
                score,
                profile.total_calls,
                profile.avg_dispatch_time / 1000.0,
                profile.cache_hit_ratio * 100.0,
            });

            // Visual bar representation
            const bar_length = @min(@as(u32, @intFromFloat(score)), 50);
            try writer.writeAll("    ");
            for (0..bar_length) |_| {
                try writer.writeAll("█");
            }
            try writer.writeAll("\n\n");
        }

        const viz = Visualization{
            .id = @intCast(std.time.nanoTimestamp()),
            .type = .performance_heatmap,
            .format = .ascii,
            .title = try self.allocator.dupe(u8, "Performance Heatmap"),
            .description = try self.allocator.dupe(u8, "Visual representation of dispatch performance hotspots"),
            .content = try content.toOwnedSlice(),
            .metadata = Visualization.VisualizationMetadata{
                .creation_time = @intCast(std.time.nanoTimestamp()),
                .data_source = try self.allocator.dupe(u8, "profiler"),
                .node_count = @intCast(display_count),
                .edge_count = 0,
                .complexity_score = @as(f64, @floatFromInt(display_count)) / 20.0,
            },
        };

        try self.visualizations.append(viz);
    }

    /// Generate SVG dispatch graph
    pub fn generateDispatchGraphSVG(self: *Self, profiler: *const DispatchProfiler) !void {
        var content: ArrayList(u8) = .empty;
        defer content.deinit();

        const writer = content.writer();

        // SVG header
        try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try writer.writeAll("<svg width=\"800\" height=\"600\" xmlns=\"http://www.w3.org/2000/svg\">\n");
        try writer.writeAll("  <defs>\n");
        try writer.writeAll("    <style>\n");
        try writer.writeAll("      .hot-path { fill: #ff4444; stroke: #cc0000; }\n");
        try writer.writeAll("      .normal-path { fill: #4444ff; stroke: #0000cc; }\n");
        try writer.writeAll("      .cold-path { fill: #44ff44; stroke: #00cc00; }\n");
        try writer.writeAll("      .text { font-family: Arial, sans-serif; font-size: 10px; }\n");
        try writer.writeAll("    </style>\n");
        try writer.writeAll("  </defs>\n");

        // Title
        try writer.writeAll("  <text x=\"400\" y=\"20\" text-anchor=\"middle\" class=\"text\" font-size=\"16\">Dispatch Graph</text>\n");

        // Collect nodes for visualization
        var nodes: ArrayList(*const DispatchProfiler.CallProfile) = .empty;
        defer nodes.deinit();

        var call_iter = profiler.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;
            if (profile.total_calls >= self.config.min_call_frequency) {
                try nodes.append(profile);
            }
        }

        // Limit nodes
        const display_count = @min(nodes.items.len, self.config.max_nodes);

        // Draw nodes
        for (nodes.items[0..display_count], 0..) |profile, i| {
            const x = 100 + (i % 6) * 120;
            const y = 80 + (i / 6) * 80;

            // Determine node class based on performance
            const node_class = if (profile.is_hot_path) "hot-path" else if (profile.total_calls > 1000) "normal-path" else "cold-path";

            // Draw node circle
            const radius = @min(5 + @as(u32, @intFromFloat(@log(@as(f64, @floatFromInt(profile.total_calls))))), 20);
            try writer.print("  <circle cx=\"{}\" cy=\"{}\" r=\"{}\" class=\"{s}\"/>\n", .{ x, y, radius, node_class });

            // Add label
            try writer.print("  <text x=\"{}\" y=\"{}\" text-anchor=\"middle\" class=\"text\">{s}</text>\n", .{
                x,
                y + radius + 15,
                profile.call_site.signature_name,
            });

            // Add performance info
            if (self.config.show_performance_data) {
                try writer.print("  <text x=\"{}\" y=\"{}\" text-anchor=\"middle\" class=\"text\" font-size=\"8\">{} calls</text>\n", .{
                    x,
                    y + radius + 25,
                    profile.total_calls,
                });
            }
        }

        try writer.writeAll("</svg>\n");

        const viz = Visualization{
            .id = @intCast(std.time.nanoTimestamp()),
            .type = .dispatch_graph,
            .format = .svg,
            .title = try self.allocator.dupe(u8, "Dispatch Graph (SVG)"),
            .description = try self.allocator.dupe(u8, "SVG visualization of dispatch call sites"),
            .content = try content.toOwnedSlice(),
            .metadata = Visualization.VisualizationMetadata{
                .creation_time = @intCast(std.time.nanoTimestamp()),
                .data_source = try self.allocator.dupe(u8, "profiler"),
                .node_count = @intCast(display_count),
                .edge_count = 0,
                .complexity_score = @as(f64, @floatFromInt(display_count)) / 10.0,
            },
        };

        try self.visualizations.append(viz);
    }

    /// Generate decision tree SVG
    pub fn generateDecisionTreeSVG(self: *Self, profiler: *const DispatchProfiler) !void {
        _ = profiler; // TODO: Implement decision tree visualization

        var content: ArrayList(u8) = .empty;
        defer content.deinit();

        const writer = content.writer();

        try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try writer.writeAll("<svg width=\"600\" height=\"400\" xmlns=\"http://www.w3.org/2000/svg\">\n");
        try writer.writeAll("  <text x=\"300\" y=\"200\" text-anchor=\"middle\">Decision Tree Visualization (TODO)</text>\n");
        try writer.writeAll("</svg>\n");

        const viz = Visualization{
            .id = @intCast(std.time.nanoTimestamp()),
            .type = .decision_tree,
            .format = .svg,
            .title = try self.allocator.dupe(u8, "Decision Tree (SVG)"),
            .description = try self.allocator.dupe(u8, "SVG visualization of dispatch decision tree"),
            .content = try content.toOwnedSlice(),
            .metadata = Visualization.VisualizationMetadata{
                .creation_time = @intCast(std.time.nanoTimestamp()),
                .data_source = try self.allocator.dupe(u8, "profiler"),
                .node_count = 0,
                .edge_count = 0,
                .complexity_score = 0.0,
            },
        };

        try self.visualizations.append(viz);
    }

    /// Generate hot path flow SVG
    pub fn generateHotPathFlowSVG(self: *Self, profiler: *const DispatchProfiler) !void {
        _ = profiler; // TODO: Implement hot path flow visualization

        var content: ArrayList(u8) = .empty;
        defer content.deinit();

        const writer = content.writer();

        try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try writer.writeAll("<svg width=\"800\" height=\"600\" xmlns=\"http://www.w3.org/2000/svg\">\n");
        try writer.writeAll("  <text x=\"400\" y=\"300\" text-anchor=\"middle\">Hot Path Flow Visualization (TODO)</text>\n");
        try writer.writeAll("</svg>\n");

        const viz = Visualization{
            .id = @intCast(std.time.nanoTimestamp()),
            .type = .hot_path_flow,
            .format = .svg,
            .title = try self.allocator.dupe(u8, "Hot Path Flow (SVG)"),
            .description = try self.allocator.dupe(u8, "SVG visualization of hot path execution flow"),
            .content = try content.toOwnedSlice(),
            .metadata = Visualization.VisualizationMetadata{
                .creation_time = @intCast(std.time.nanoTimestamp()),
                .data_source = try self.allocator.dupe(u8, "profiler"),
                .node_count = 0,
                .edge_count = 0,
                .complexity_score = 0.0,
            },
        };

        try self.visualizations.append(viz);
    }

    /// Generate interactive HTML visualization
    pub fn generateInteractiveHTML(self: *Self, profiler: *const DispatchProfiler) !void {
        var content: ArrayList(u8) = .empty;
        defer content.deinit();

        const writer = content.writer();

        // HTML header
        try writer.writeAll("<!DOCTYPE html>\n");
        try writer.writeAll("<html>\n");
        try writer.writeAll("<head>\n");
        try writer.writeAll("  <title>Dispatch Visualization</title>\n");
        try writer.writeAll("  <style>\n");
        try writer.writeAll("    body { font-family: Arial, sans-serif; margin: 20px; }\n");
        try writer.writeAll("    .hot-path { background-color: #ffcccc; }\n");
        try writer.writeAll("    .normal-path { background-color: #ccccff; }\n");
        try writer.writeAll("    .cold-path { background-color: #ccffcc; }\n");
        try writer.writeAll("    table { border-collapse: collapse; width: 100%; }\n");
        try writer.writeAll("    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n");
        try writer.writeAll("    th { background-color: #f2f2f2; }\n");
        try writer.writeAll("  </style>\n");
        try writer.writeAll("</head>\n");
        try writer.writeAll("<body>\n");

        try writer.writeAll("  <h1>Dispatch Performance Analysis</h1>\n");

        // Summary statistics
        try writer.writeAll("  <h2>Summary</h2>\n");
        try writer.print("  <p>Total dispatch calls: {}</p>\n", .{profiler.counters.total_dispatch_calls});
        try writer.print("  <p>Total dispatch time: {d:.1}ms</p>\n", .{@as(f64, @floatFromInt(profiler.counters.total_dispatch_time)) / 1_000_000.0});
        try writer.print("  <p>Cache hit ratio: {d:.1}%</p>\n", .{profiler.counters.getCacheHitRatio() * 100.0});

        // Call sites table
        try writer.writeAll("  <h2>Call Sites</h2>\n");
        try writer.writeAll("  <table>\n");
        try writer.writeAll("    <tr><th>Location</th><th>Signature</th><th>Calls</th><th>Avg Time (μs)</th><th>Cache Hit %</th><th>Hot Path</th></tr>\n");

        var call_iter = profiler.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;
            if (profile.total_calls >= self.config.min_call_frequency) {
                const row_class = if (profile.is_hot_path) "hot-path" else if (profile.total_calls > 1000) "normal-path" else "cold-path";
                const hot_indicator = if (profile.is_hot_path) "🔥" else "";

                try writer.print("    <tr class=\"{s}\">", .{row_class});
                try writer.print("<td>{}:{}</td>", .{ profile.call_site.source_file, profile.call_site.line });
                try writer.print("<td>{s}</td>", .{profile.call_site.signature_name});
                try writer.print("<td>{}</td>", .{profile.total_calls});
                try writer.print("<td>{d:.1}</td>", .{profile.avg_dispatch_time / 1000.0});
                try writer.print("<td>{d:.1}</td>", .{profile.cache_hit_ratio * 100.0});
                try writer.print("<td>{s}</td>", .{hot_indicator});
                try writer.writeAll("</tr>\n");
            }
        }

        try writer.writeAll("  </table>\n");
        try writer.writeAll("</body>\n");
        try writer.writeAll("</html>\n");

        const viz = Visualization{
            .id = @intCast(std.time.nanoTimestamp()),
            .type = .dispatch_graph,
            .format = .html,
            .title = try self.allocator.dupe(u8, "Interactive Dispatch Analysis"),
            .description = try self.allocator.dupe(u8, "Interactive HTML visualization of dispatch performance"),
            .content = try content.toOwnedSlice(),
            .metadata = Visualization.VisualizationMetadata{
                .creation_time = @intCast(std.time.nanoTimestamp()),
                .data_source = try self.allocator.dupe(u8, "profiler"),
                .node_count = @intCast(profiler.call_profiles.count()),
                .edge_count = 0,
                .complexity_score = @as(f64, @floatFromInt(profiler.call_profiles.count())) / 50.0,
            },
        };

        try self.visualizations.append(viz);
    }

    /// Generate DOT graph for Graphviz
    pub fn generateDotGraph(self: *Self, profiler: *const DispatchProfiler) !void {
        var content: ArrayList(u8) = .empty;
        defer content.deinit();

        const writer = content.writer();

        try writer.writeAll("digraph DispatchGraph {\n");
        try writer.writeAll("  rankdir=TB;\n");
        try writer.writeAll("  node [shape=box, style=filled];\n");

        // Add nodes
        var call_iter = profiler.call_profiles.iterator();
        while (call_iter.next()) |entry| {
            const profile = entry.value_ptr;
            if (profile.total_calls >= self.config.min_call_frequency) {
                const color = if (profile.is_hot_path) "red" else if (profile.total_calls > 1000) "yellow" else "lightgreen";
                const node_id = @as(u32, @truncate(profile.call_site.hash()));

                try writer.print("  {} [label=\"{s}\\n{}:{}\", fillcolor={}];\n", .{
                    node_id,
                    profile.call_site.signature_name,
                    profile.call_site.source_file,
                    profile.call_site.line,
                    color,
                });
            }
        }

        try writer.writeAll("}\n");

        const viz = Visualization{
            .id = @intCast(std.time.nanoTimestamp()),
            .type = .dispatch_graph,
            .format = .dot,
            .title = try self.allocator.dupe(u8, "Dispatch Graph (DOT)"),
            .description = try self.allocator.dupe(u8, "DOT format graph for Graphviz rendering"),
            .content = try content.toOwnedSlice(),
            .metadata = Visualization.VisualizationMetadata{
                .creation_time = @intCast(std.time.nanoTimestamp()),
                .data_source = try self.allocator.dupe(u8, "profiler"),
                .node_count = @intCast(profiler.call_profiles.count()),
                .edge_count = 0,
                .complexity_score = @as(f64, @floatFromInt(profiler.call_profiles.count())) / 30.0,
            },
        };

        try self.visualizations.append(viz);
    }

    /// Get all generated visualizations
    pub fn getVisualizations(self: *const Self) []const Visualization {
        return self.visualizations.items;
    }

    /// Get visualizations by type
    pub fn getVisualizationsByType(self: *const Self, viz_type: Visualization.VisualizationType) []const Visualization {
        var filtered: ArrayList(Visualization) = .empty;
        defer filtered.deinit();

        for (self.visualizations.items) |viz| {
            if (viz.type == viz_type) {
                filtered.append(viz) catch continue;
            }
        }

        return try filtered.toOwnedSlice(alloc) catch &.{};
    }

    /// Get visualizations by format
    pub fn getVisualizationsByFormat(self: *const Self, format: Visualization.OutputFormat) []const Visualization {
        var filtered: ArrayList(Visualization) = .empty;
        defer filtered.deinit();

        for (self.visualizations.items) |viz| {
            if (viz.format == format) {
                filtered.append(viz) catch continue;
            }
        }

        return try filtered.toOwnedSlice(alloc) catch &.{};
    }

    /// Save visualization to file
    pub fn saveVisualization(self: *const Self, viz: *const Visualization, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        try file.writeAll(viz.content);
    }

    /// Save all visualizations to directory
    pub fn saveAllVisualizations(self: *const Self, directory: []const u8) !void {
        // Create directory if it doesn't exist
        std.fs.cwd().makeDir(directory) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        for (self.visualizations.items, 0..) |viz, i| {
            const extension = switch (viz.format) {
                .svg => "svg",
                .html => "html",
                .dot => "dot",
                .ascii => "txt",
                .json => "json",
            };

            const filename = try std.fmt.allocPrint(self.allocator, "{s}/viz_{}_{}.{s}", .{ directory, i, viz.type, extension });
            defer self.allocator.free(filename);

            try self.saveVisualization(&viz, filename);
        }
    }

    /// Clear all visualizations
    fn clearVisualizations(self: *Self) void {
        for (self.visualizations.items) |*viz| {
            self.allocator.free(viz.title);
            self.allocator.free(viz.description);
            self.allocator.free(viz.content);
        }
        self.visualizations.clearAndFree();
    }

// Tests

test "DispatchVisualizer basic functionality" {
    const allocator = testing.allocator;

    const config = DispatchVisualizer.VisualizationConfig{};
    var visualizer = DispatchVisualizer.init(allocator, config);
    defer visualizer.deinit();

    // Create mock profiler
    const profiler_config = DispatchProfiler.ProfilingConfig.default();
    var profiler = DispatchProfiler.init(allocator, profiler_config);
    defer profiler.deinit();

    // Generate visualizations
    try visualizer.generateVisualizations(&profiler);

    // Should have generated some visualizations
    const visualizations = visualizer.getVisualizations();
    try testing.expect(visualizations.len > 0);

    // Test filtering
    const ascii_vizs = visualizer.getVisualizationsByFormat(.ascii);
    defer allocator.free(ascii_vizs);
    try testing.expect(ascii_vizs.len > 0);
}

test "Visualization metadata validation" {
    const metadata = DispatchVisualizer.Visualization.VisualizationMetadata{
        .creation_time = 1234567890,
        .data_source = "test",
        .node_count = 10,
        .edge_count = 5,
        .complexity_score = 2.5,
    };

    try testing.expectEqual(@as(u64, 1234567890), metadata.creation_time);
    try testing.expectEqual(@as(u32, 10), metadata.node_count);
    try testing.expectEqual(@as(u32, 5), metadata.edge_count);
    try testing.expectEqual(@as(f64, 2.5), metadata.complexity_score);
}
