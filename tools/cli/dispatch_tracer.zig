// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Runtime dispatch tracing tool
// Implements real-time dispatch monitoring and performance analysis

const std = @import("std");
const compat_time = @import("compat_time");
const print = std.debug.print;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;

// Import dispatch system components (mock for CLI testing)
const mock_system = @import("mock_dispatch_system.zig");
const DispatchFamily = mock_system.DispatchFamily;
const RuntimeDispatch = mock_system.RuntimeDispatch;

pub const DispatchTracer = struct {
    allocator: Allocator,
    trace_buffer: ArrayList(TraceEntry),
    active_traces: HashMap(u64, *ActiveTrace, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    performance_counters: PerformanceCounters,
    config: TracingConfig,

    const Self = @This();

    pub const TraceEntry = struct {
        timestamp: i128,
        call_id: u64,
        function_name: []const u8,
        argument_types: []const []const u8,
        resolution_strategy: ResolutionStrategy,
        resolution_time_ns: u64,
        selected_implementation: []const u8,
        cache_hit: bool,

        pub const ResolutionStrategy = enum {
            static_direct,
            perfect_hash_lookup,
            inline_cache_hit,
            inline_cache_miss,
            switch_table_lookup,
            decision_tree_traversal,
        };
    };

    pub const ActiveTrace = struct {
        call_id: u64,
        start_time: i128,
        function_name: []const u8,
        argument_types: []const []const u8,
        resolution_steps: ArrayList(ResolutionStep),

        pub const ResolutionStep = struct {
            step_name: []const u8,
            timestamp: i128,
            duration_ns: u64,
            details: []const u8,
        };
    };

    pub const PerformanceCounters = struct {
        total_dispatches: u64,
        static_dispatches: u64,
        dynamic_dispatches: u64,
        cache_hits: u64,
        cache_misses: u64,
        total_resolution_time_ns: u64,
        average_resolution_time_ns: u64,
        hot_paths: HashMap([]const u8, HotPathStats, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

        pub const HotPathStats = struct {
            call_count: u64,
            total_time_ns: u64,
            average_time_ns: u64,
            cache_hit_rate: f64,
        };
    };

    pub const TracingConfig = struct {
        enable_performance_counters: bool = true,
        enable_detailed_tracing: bool = false,
        max_trace_entries: u32 = 10000,
        hot_path_threshold: u32 = 100,
        trace_filter: ?[]const u8 = null,
        output_format: OutputFormat = .console,

        pub const OutputFormat = enum {
            console,
            json,
            csv,
            flamegraph,
        };
    };

    pub fn init(allocator: Allocator, config: TracingConfig) !Self {
        return Self{
            .allocator = allocator,
            .trace_buffer = .empty,
            .active_traces = HashMap(u64, *ActiveTrace, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .performance_counters = PerformanceCounters{
                .total_dispatches = 0,
                .static_dispatches = 0,
                .dynamic_dispatches = 0,
                .cache_hits = 0,
                .cache_misses = 0,
                .total_resolution_time_ns = 0,
                .average_resolution_time_ns = 0,
                .hot_paths = HashMap([]const u8, PerformanceCounters.HotPathStats, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            },
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.trace_buffer.deinit();

        var active_iterator = self.active_traces.iterator();
        while (active_iterator.next()) |entry| {
            entry.value_ptr.*.resolution_steps.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.active_traces.deinit();

        var hot_path_iterator = self.performance_counters.hot_paths.iterator();
        while (hot_path_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.performance_counters.hot_paths.deinit();
    }

    // Start tracing a dispatch call
    pub fn startTrace(self: *Self, call_id: u64, function_name: []const u8, argument_types: []const []const u8) !void {
        if (self.shouldTraceCall(function_name)) {
            const active_trace = try self.allocator.create(ActiveTrace);
            active_trace.* = ActiveTrace{
                .call_id = call_id,
                .start_time = compat_time.nanoTimestamp(),
                .function_name = try self.allocator.dupe(u8, function_name),
                .argument_types = try self.duplicateStringArray(argument_types),
                .resolution_steps = .empty,
            };

            try self.active_traces.put(call_id, active_trace);

            if (self.config.enable_detailed_tracing) {
                print("🔍 [TRACE START] Call ID: {d}, Function: {s}({s})\n", .{
                    call_id,
                    function_name,
                    try self.formatTypes(argument_types),
                });
            }
        }
    }

    // Add a resolution step to an active trace
    pub fn addResolutionStep(self: *Self, call_id: u64, step_name: []const u8, details: []const u8) !void {
        if (self.active_traces.get(call_id)) |active_trace| {
            const now = compat_time.nanoTimestamp();
            const duration = if (active_trace.resolution_steps.items.len > 0)
                @as(u64, @intCast(now - active_trace.resolution_steps.items[active_trace.resolution_steps.items.len - 1].timestamp))
            else
                @as(u64, @intCast(now - active_trace.start_time));

            try active_trace.resolution_steps.append(.{
                .step_name = try self.allocator.dupe(u8, step_name),
                .timestamp = now,
                .duration_ns = duration,
                .details = try self.allocator.dupe(u8, details),
            });

            if (self.config.enable_detailed_tracing) {
                print("  📋 [STEP] {s}: {s} ({d}ns)\n", .{ step_name, details, duration });
            }
        }
    }

    // Complete a dispatch trace
    pub fn completeTrace(
        self: *Self,
        call_id: u64,
        strategy: TraceEntry.ResolutionStrategy,
        selected_implementation: []const u8,
        cache_hit: bool,
    ) !void {
        if (self.active_traces.get(call_id)) |active_trace| {
            const end_time = compat_time.nanoTimestamp();
            const total_time = @as(u64, @intCast(end_time - active_trace.start_time));

            // Create trace entry
            const trace_entry = TraceEntry{
                .timestamp = active_trace.start_time,
                .call_id = call_id,
                .function_name = try self.allocator.dupe(u8, active_trace.function_name),
                .argument_types = try self.duplicateStringArray(active_trace.argument_types),
                .resolution_strategy = strategy,
                .resolution_time_ns = total_time,
                .selected_implementation = try self.allocator.dupe(u8, selected_implementation),
                .cache_hit = cache_hit,
            };

            try self.trace_buffer.append(trace_entry);

            // Update performance counters
            try self.updatePerformanceCounters(trace_entry);

            // Clean up active trace
            active_trace.resolution_steps.deinit();
            self.allocator.free(active_trace.function_name);
            self.freeStringArray(@constCast(active_trace.argument_types));
            self.allocator.destroy(active_trace);
            _ = self.active_traces.remove(call_id);

            if (self.config.enable_detailed_tracing) {
                print("✅ [TRACE END] {s} -> {s} ({d}ns, {s})\n", .{
                    trace_entry.function_name,
                    selected_implementation,
                    total_time,
                    @tagName(strategy),
                });
            }

            // Trim trace buffer if needed
            if (self.trace_buffer.items.len > self.config.max_trace_entries) {
                try self.trimTraceBuffer();
            }
        }
    }

    // Generate performance report
    pub fn generateReport(self: *Self, format: TracingConfig.OutputFormat) !void {
        switch (format) {
            .console => try self.generateConsoleReport(),
            .json => try self.generateJSONReport(),
            .csv => try self.generateCSVReport(),
            .flamegraph => try self.generateFlamegraphReport(),
        }
    }

    // Console report
    fn generateConsoleReport(self: *Self) !void {
        print("\n📊 Dispatch Performance Report\n", .{});
        print("=" ** 50 ++ "\n", .{});

        // Overall statistics
        print("\n📈 Overall Statistics:\n", .{});
        print("  Total Dispatches: {d}\n", .{self.performance_counters.total_dispatches});
        print("  Static Dispatches: {d} ({d:.1}%)\n", .{
            self.performance_counters.static_dispatches,
            @as(f64, @floatFromInt(self.performance_counters.static_dispatches)) / @as(f64, @floatFromInt(self.performance_counters.total_dispatches)) * 100,
        });
        print("  Dynamic Dispatches: {d} ({d:.1}%)\n", .{
            self.performance_counters.dynamic_dispatches,
            @as(f64, @floatFromInt(self.performance_counters.dynamic_dispatches)) / @as(f64, @floatFromInt(self.performance_counters.total_dispatches)) * 100,
        });
        print("  Cache Hit Rate: {d:.1}%\n", .{
            @as(f64, @floatFromInt(self.performance_counters.cache_hits)) / @as(f64, @floatFromInt(self.performance_counters.cache_hits + self.performance_counters.cache_misses)) * 100,
        });
        print("  Average Resolution Time: {d}ns\n", .{self.performance_counters.average_resolution_time_ns});

        // Hot paths
        if (self.performance_counters.hot_paths.count() > 0) {
            print("\n🔥 Hot Paths:\n", .{});
            var hot_path_iterator = self.performance_counters.hot_paths.iterator();
            while (hot_path_iterator.next()) |entry| {
                const stats = entry.value_ptr.*;
                print("  {s}:\n", .{entry.key_ptr.*});
                print("    Calls: {d}\n", .{stats.call_count});
                print("    Average Time: {d}ns\n", .{stats.average_time_ns});
                print("    Cache Hit Rate: {d:.1}%\n", .{stats.cache_hit_rate * 100});
                print("    Total Time: {d:.2}ms\n", .{@as(f64, @floatFromInt(stats.total_time_ns)) / 1_000_000});
            }
        }

        // Strategy breakdown
        try self.showStrategyBreakdown();

        // Recent traces
        try self.showRecentTraces(10);
    }

    // Strategy breakdown
    fn showStrategyBreakdown(self: *Self) !void {
        print("\n⚡ Strategy Breakdown:\n", .{});

        var strategy_counts = std.EnumMap(TraceEntry.ResolutionStrategy, u64).init(.{});
        var strategy_times = std.EnumMap(TraceEntry.ResolutionStrategy, u64).init(.{});

        for (self.trace_buffer.items) |entry| {
            const current_count = strategy_counts.get(entry.resolution_strategy) orelse 0;
            strategy_counts.put(entry.resolution_strategy, current_count + 1);

            const current_time = strategy_times.get(entry.resolution_strategy) orelse 0;
            strategy_times.put(entry.resolution_strategy, current_time + entry.resolution_time_ns);
        }

        inline for (std.meta.fields(TraceEntry.ResolutionStrategy)) |field| {
            const strategy = @field(TraceEntry.ResolutionStrategy, field.name);
            const count = strategy_counts.get(strategy) orelse 0;
            const total_time = strategy_times.get(strategy) orelse 0;

            if (count > 0) {
                const avg_time = total_time / count;
                print("  {s}: {d} calls, {d}ns avg\n", .{ field.name, count, avg_time });
            }
        }
    }

    // Recent traces
    fn showRecentTraces(self: *Self, limit: u32) !void {
        print("\n🕒 Recent Traces (last {d}):\n", .{limit});

        const start_idx = if (self.trace_buffer.items.len > limit)
            self.trace_buffer.items.len - limit
        else
            0;

        for (self.trace_buffer.items[start_idx..]) |entry| {
            const cache_indicator = if (entry.cache_hit) "💾" else "🔍";
            print("  {s} {s}({s}) -> {s} ({d}ns)\n", .{
                cache_indicator,
                entry.function_name,
                try self.formatTypes(entry.argument_types),
                entry.selected_implementation,
                entry.resolution_time_ns,
            });
        }
    }

    // JSON report
    fn generateJSONReport(self: *Self) !void {
        print("{{\n", .{});
        print("  \"performance_counters\": {{\n", .{});
        print("    \"total_dispatches\": {d},\n", .{self.performance_counters.total_dispatches});
        print("    \"static_dispatches\": {d},\n", .{self.performance_counters.static_dispatches});
        print("    \"dynamic_dispatches\": {d},\n", .{self.performance_counters.dynamic_dispatches});
        print("    \"cache_hits\": {d},\n", .{self.performance_counters.cache_hits});
        print("    \"cache_misses\": {d},\n", .{self.performance_counters.cache_misses});
        print("    \"average_resolution_time_ns\": {d}\n", .{self.performance_counters.average_resolution_time_ns});
        print("  }},\n", .{});

        print("  \"traces\": [\n", .{});
        for (self.trace_buffer.items, 0..) |entry, i| {
            print("    {{\n", .{});
            print("      \"timestamp\": {d},\n", .{entry.timestamp});
            print("      \"call_id\": {d},\n", .{entry.call_id});
            print("      \"function_name\": \"{s}\",\n", .{entry.function_name});
            print("      \"resolution_strategy\": \"{s}\",\n", .{@tagName(entry.resolution_strategy)});
            print("      \"resolution_time_ns\": {d},\n", .{entry.resolution_time_ns});
            print("      \"selected_implementation\": \"{s}\",\n", .{entry.selected_implementation});
            print("      \"cache_hit\": {}\n", .{entry.cache_hit});
            print("    }");
            if (i < self.trace_buffer.items.len - 1) print(",", .{});
            print("\n", .{});
        }
        print("  ]\n", .{});
        print("}}\n", .{});
    }

    // CSV report
    fn generateCSVReport(self: *Self) !void {
        print("timestamp,call_id,function_name,resolution_strategy,resolution_time_ns,selected_implementation,cache_hit\n", .{});

        for (self.trace_buffer.items) |entry| {
            print("{d},{d},{s},{s},{d},{s},{}\n", .{
                entry.timestamp,
                entry.call_id,
                entry.function_name,
                @tagName(entry.resolution_strategy),
                entry.resolution_time_ns,
                entry.selected_implementation,
                entry.cache_hit,
            });
        }
    }

    // Flamegraph report (simplified)
    fn generateFlamegraphReport(self: *Self) !void {
        print("# Dispatch Flamegraph Data\n", .{});
        print("# Format: function_name;resolution_strategy time_ns\n", .{});

        for (self.trace_buffer.items) |entry| {
            print("{s};{s} {d}\n", .{
                entry.function_name,
                @tagName(entry.resolution_strategy),
                entry.resolution_time_ns,
            });
        }
    }

    // Helper functions
    fn shouldTraceCall(self: *Self, function_name: []const u8) bool {
        if (self.config.trace_filter) |filter| {
            return std.mem.indexOf(u8, function_name, filter) != null;
        }
        return true;
    }

    fn updatePerformanceCounters(self: *Self, entry: TraceEntry) !void {
        self.performance_counters.total_dispatches += 1;

        switch (entry.resolution_strategy) {
            .static_direct => self.performance_counters.static_dispatches += 1,
            else => self.performance_counters.dynamic_dispatches += 1,
        }

        if (entry.cache_hit) {
            self.performance_counters.cache_hits += 1;
        } else {
            self.performance_counters.cache_misses += 1;
        }

        self.performance_counters.total_resolution_time_ns += entry.resolution_time_ns;
        self.performance_counters.average_resolution_time_ns =
            self.performance_counters.total_resolution_time_ns / self.performance_counters.total_dispatches;

        // Update hot path statistics
        const function_name = try self.allocator.dupe(u8, entry.function_name);
        const result = try self.performance_counters.hot_paths.getOrPut(function_name);

        if (result.found_existing) {
            self.allocator.free(function_name); // Don't need duplicate
            result.value_ptr.call_count += 1;
            result.value_ptr.total_time_ns += entry.resolution_time_ns;
            result.value_ptr.average_time_ns = result.value_ptr.total_time_ns / result.value_ptr.call_count;

            // Update cache hit rate
            const total_calls = result.value_ptr.call_count;
            const current_hit_rate = result.value_ptr.cache_hit_rate;
            const new_hit: f64 = if (entry.cache_hit) 1.0 else 0.0;
            result.value_ptr.cache_hit_rate = (current_hit_rate * @as(f64, @floatFromInt(total_calls - 1)) + new_hit) / @as(f64, @floatFromInt(total_calls));
        } else {
            result.value_ptr.* = .{
                .call_count = 1,
                .total_time_ns = entry.resolution_time_ns,
                .average_time_ns = entry.resolution_time_ns,
                .cache_hit_rate = if (entry.cache_hit) 1.0 else 0.0,
            };
        }
    }

    fn trimTraceBuffer(self: *Self) !void {
        const keep_count = self.config.max_trace_entries / 2;
        const remove_count = self.trace_buffer.items.len - keep_count;

        // Free memory for removed entries
        for (self.trace_buffer.items[0..remove_count]) |entry| {
            self.allocator.free(entry.function_name);
            self.freeStringArray(@constCast(entry.argument_types));
            self.allocator.free(entry.selected_implementation);
        }

        // Move remaining entries to front
        @memcpy(self.trace_buffer.items[0..keep_count], self.trace_buffer.items[remove_count..]);
        self.trace_buffer.shrinkRetainingCapacity(keep_count);
    }

    fn duplicateStringArray(self: *Self, strings: []const []const u8) ![][]const u8 {
        const result = try self.allocator.alloc([]const u8, strings.len);
        for (strings, 0..) |str, i| {
            result[i] = try self.allocator.dupe(u8, str);
        }
        return result;
    }

    fn freeStringArray(self: *Self, strings: [][]const u8) void {
        for (strings) |str| {
            self.allocator.free(str);
        }
        self.allocator.free(strings);
    }

    fn formatTypes(self: *Self, types: []const []const u8) ![]const u8 {
        if (types.len == 0) return try self.allocator.dupe(u8, "");
        return std.mem.join(self.allocator, ", ", types);
    }
};

// CLI interface for the tracer
pub const DispatchTracerCLI = struct {
    tracer: *DispatchTracer,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, config: DispatchTracer.TracingConfig) !Self {
        const tracer = try allocator.create(DispatchTracer);
        tracer.* = try DispatchTracer.init(allocator, config);

        return Self{
            .tracer = tracer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tracer.deinit();
        self.allocator.destroy(self.tracer);
    }

    pub fn runInteractiveMode(self: *Self) !void {
        print("🔍 Janus Dispatch Tracer - Interactive Mode\n", .{});
        print("=" ** 45 ++ "\n");
        print("Commands:\n", .{});
        print("  start <filter>     - Start tracing (optional filter)\n", .{});
        print("  stop              - Stop tracing\n", .{});
        print("  report <format>   - Generate report (console/json/csv/flamegraph)\n", .{});
        print("  clear             - Clear trace buffer\n", .{});
        print("  status            - Show current status\n", .{});
        print("  help              - Show this help\n", .{});
        print("  quit              - Exit tracer\n", .{});
        print("\n", .{});

        var io_buffer: [256]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(io_buffer[0..]);
        const stdin_io = &stdin_reader.interface;
        var buf: [256]u8 = undefined;

        while (true) {
            print("tracer> ", .{});

            if (try stdin_io.readUntilDelimiterOrEof(&buf, '\n')) |input| {
                const trimmed = std.mem.trim(u8, input, " \t\r\n");

                if (trimmed.len == 0) continue;

                var parts = std.mem.split(u8, trimmed, " ");
                const command = parts.next() orelse continue;

                if (std.mem.eql(u8, command, "quit") or std.mem.eql(u8, command, "exit")) {
                    break;
                } else if (std.mem.eql(u8, command, "help")) {
                    try self.showHelp();
                } else if (std.mem.eql(u8, command, "status")) {
                    try self.showStatus();
                } else if (std.mem.eql(u8, command, "report")) {
                    const format_str = parts.next() orelse "console";
                    try self.generateReport(format_str);
                } else if (std.mem.eql(u8, command, "clear")) {
                    try self.clearTraces();
                } else if (std.mem.eql(u8, command, "start")) {
                    const filter = parts.next();
                    try self.startTracing(filter);
                } else if (std.mem.eql(u8, command, "stop")) {
                    try self.stopTracing();
                } else {
                    print("Unknown command: {s}. Type 'help' for available commands.\n", .{command});
                }
            } else {
                break;
            }
        }

        print("Goodbye! 👋\n", .{});
    }

    fn showHelp(self: *Self) !void {
        _ = self;
        print("\n📖 Dispatch Tracer Help\n", .{});
        print("-" ** 25 ++ "\n");
        print("start [filter]    - Begin tracing dispatch calls\n", .{});
        print("                   Optional filter to trace specific functions\n", .{});
        print("stop             - Stop tracing\n", .{});
        print("report [format]  - Generate performance report\n", .{});
        print("                   Formats: console, json, csv, flamegraph\n", .{});
        print("clear            - Clear all trace data\n", .{});
        print("status           - Show tracer status and statistics\n", .{});
        print("help             - Show this help message\n", .{});
        print("quit/exit        - Exit the tracer\n", .{});
        print("\nExamples:\n", .{});
        print("  start add        - Trace only functions containing 'add'\n", .{});
        print("  report json      - Generate JSON format report\n", .{});
        print("  report flamegraph > dispatch.flame  - Save flamegraph data\n", .{});
        print("\n", .{});
    }

    fn showStatus(self: *Self) !void {
        print("\n📊 Tracer Status\n", .{});
        print("-" ** 17 ++ "\n");
        print("Active Traces: {d}\n", .{self.tracer.active_traces.count()});
        print("Total Trace Entries: {d}\n", .{self.tracer.trace_buffer.items.len});
        print("Total Dispatches: {d}\n", .{self.tracer.performance_counters.total_dispatches});
        print("Average Resolution Time: {d}ns\n", .{self.tracer.performance_counters.average_resolution_time_ns});

        if (self.tracer.config.trace_filter) |filter| {
            print("Active Filter: {s}\n", .{filter});
        } else {
            print("Filter: None (tracing all)\n", .{});
        }

        print("Detailed Tracing: {s}\n", .{if (self.tracer.config.enable_detailed_tracing) "Enabled" else "Disabled"});
        print("\n", .{});
    }

    fn generateReport(self: *Self, format_str: []const u8) !void {
        const format = if (std.mem.eql(u8, format_str, "json"))
            DispatchTracer.TracingConfig.OutputFormat.json
        else if (std.mem.eql(u8, format_str, "csv"))
            DispatchTracer.TracingConfig.OutputFormat.csv
        else if (std.mem.eql(u8, format_str, "flamegraph"))
            DispatchTracer.TracingConfig.OutputFormat.flamegraph
        else
            DispatchTracer.TracingConfig.OutputFormat.console;

        try self.tracer.generateReport(format);
    }

    fn clearTraces(self: *Self) !void {
        // Clear trace buffer
        for (self.tracer.trace_buffer.items) |entry| {
            self.allocator.free(entry.function_name);
            self.tracer.freeStringArray(entry.argument_types);
            self.allocator.free(entry.selected_implementation);
        }
        self.tracer.trace_buffer.clearRetainingCapacity();

        // Reset performance counters
        self.tracer.performance_counters = DispatchTracer.PerformanceCounters{
            .total_dispatches = 0,
            .static_dispatches = 0,
            .dynamic_dispatches = 0,
            .cache_hits = 0,
            .cache_misses = 0,
            .total_resolution_time_ns = 0,
            .average_resolution_time_ns = 0,
            .hot_paths = HashMap([]const u8, DispatchTracer.PerformanceCounters.HotPathStats, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator),
        };

        print("✅ Trace data cleared.\n", .{});
    }

    fn startTracing(self: *Self, filter: ?[]const u8) !void {
        if (filter) |f| {
            self.tracer.config.trace_filter = try self.allocator.dupe(u8, f);
            print("✅ Started tracing functions matching: {s}\n", .{f});
        } else {
            self.tracer.config.trace_filter = null;
            print("✅ Started tracing all dispatch calls\n", .{});
        }

        self.tracer.config.enable_detailed_tracing = true;
    }

    fn stopTracing(self: *Self) !void {
        self.tracer.config.enable_detailed_tracing = false;
        if (self.tracer.config.trace_filter) |filter| {
            self.allocator.free(filter);
            self.tracer.config.trace_filter = null;
        }
        print("✅ Stopped tracing\n", .{});
    }
};

// Main entry point for CLI
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = DispatchTracer.TracingConfig{};

    // Parse command line arguments
    if (args.len > 1) {
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--detailed")) {
                config.enable_detailed_tracing = true;
            } else if (std.mem.eql(u8, arg, "--json")) {
                config.output_format = .json;
            } else if (std.mem.eql(u8, arg, "--csv")) {
                config.output_format = .csv;
            } else if (std.mem.startsWith(u8, arg, "--filter=")) {
                config.trace_filter = arg[9..];
            }
        }
    }

    var cli = try DispatchTracerCLI.init(allocator, config);
    defer cli.deinit();

    try cli.runInteractiveMode();
}
