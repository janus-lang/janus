// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Main CLI entry point for Janus dispatch tools
// Implements: janus query dispatch-ir <symbol>
//            janus query dispatch <signature>
//            janus trace dispatch <call>

const std = @import("std");
const print = std.debug.print;
const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;

const DispatchQueryCLI = @import("dispatch_query.zig").DispatchQueryCLI;
const DispatchTracerCLI = @import("dispatch_tracer.zig").DispatchTracerCLI;
const DispatchTracer = @import("dispatch_tracer.zig").DispatchTracer;

pub const JanusDispatchCLI = struct {
    allocator: Allocator,
    query_cli: ?*DispatchQueryCLI,
    tracer_cli: ?*DispatchTracerCLI,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .query_cli = null,
            .tracer_cli = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.query_cli) |cli| {
            cli.deinit();
            self.allocator.destroy(cli);
        }

        if (self.tracer_cli) |cli| {
            cli.deinit();
            self.allocator.destroy(cli);
        }
    }

    pub fn run(self: *Self, args: []const []const u8) !void {
        if (args.len < 2) {
            try self.printUsage();
            return;
        }

        const command = args[1];

        if (std.mem.eql(u8, command, "query")) {
            try self.runQueryCommand(args);
        } else if (std.mem.eql(u8, command, "trace")) {
            try self.runTraceCommand(args);
        } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help")) {
            try self.printUsage();
        } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version")) {
            try self.printVersion();
        } else {
            print("Error: Unknown command '{s}'\n\n", .{command});
            try self.printUsage();
        }
    }

    fn runQueryCommand(self: *Self, args: []const []const u8) !void {
        if (self.query_cli == null) {
            self.query_cli = try self.allocator.create(DispatchQueryCLI);
            self.query_cli.?.* = try DispatchQueryCLI.init(self.allocator);

            // Load dispatch families from project
            const loader = @import("dispatch_query.zig").DispatchQueryCLIExt;
            try loader.loadDispatchFamilies(self.query_cli.?);
        }

        try self.query_cli.?.run(args);
    }

    fn runTraceCommand(self: *Self, args: []const []const u8) !void {
        if (args.len < 3) {
            try self.printTraceUsage();
            return;
        }

        const subcommand = args[2];

        if (std.mem.eql(u8, subcommand, "dispatch")) {
            // Parse tracing options
            var config = DispatchTracer.TracingConfig{};
            var call_expr: ?[]const u8 = null;

            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                const arg = args[i];

                if (std.mem.eql(u8, arg, "--verbose")) {
                    config.enable_detailed_tracing = true;
                } else if (std.mem.eql(u8, arg, "--timing")) {
                    config.enable_performance_counters = true;
                } else if (std.mem.eql(u8, arg, "--json")) {
                    config.output_format = .json;
                } else if (std.mem.eql(u8, arg, "--csv")) {
                    config.output_format = .csv;
                } else if (std.mem.eql(u8, arg, "--flamegraph")) {
                    config.output_format = .flamegraph;
                } else if (std.mem.startsWith(u8, arg, "--filter=")) {
                    config.trace_filter = arg[9..];
                } else if (std.mem.startsWith(u8, arg, "--max-entries=")) {
                    config.max_trace_entries = std.fmt.parseInt(u32, arg[14..], 10) catch 10000;
                } else if (!std.mem.startsWith(u8, arg, "--")) {
                    call_expr = arg;
                }
            }

            if (call_expr) |expr| {
                // Single call tracing
                try self.traceSingleCall(expr, config);
            } else {
                // Interactive tracing mode
                try self.runInteractiveTracing(config);
            }
        } else {
            try self.printTraceUsage();
        }
    }

    fn traceSingleCall(self: *Self, call_expr: []const u8, config: DispatchTracer.TracingConfig) !void {
        print("🔍 Tracing dispatch for: {s}\n", .{call_expr});
        print("=" ** 40 ++ "\n", .{});

        // Create tracer
        var tracer = try DispatchTracer.init(self.allocator, config);
        defer tracer.deinit();

        // Simulate tracing the call (in real implementation, this would hook into the runtime)
        const call_id: u64 = 1;

        // Parse the call expression (simplified)
        const parsed_call = try self.parseCallExpression(call_expr);

        // Start trace
        try tracer.startTrace(call_id, parsed_call.function_name, parsed_call.argument_types);

        // Simulate resolution steps
        try tracer.addResolutionStep(call_id, "candidate_filtering", "Found 3 matching candidates");
        try tracer.addResolutionStep(call_id, "specificity_analysis", "Applying subtype ordering");
        try tracer.addResolutionStep(call_id, "cache_lookup", "Cache miss, performing full resolution");
        try tracer.addResolutionStep(call_id, "ir_generation", "Generated optimized dispatch code");

        // Complete trace
        try tracer.completeTrace(
            call_id,
            .switch_table_lookup,
            "add_i32_optimized",
            false, // cache miss
        );

        // Generate report
        try tracer.generateReport(config.output_format);
    }

    fn runInteractiveTracing(self: *Self, config: DispatchTracer.TracingConfig) !void {
        if (self.tracer_cli == null) {
            self.tracer_cli = try self.allocator.create(DispatchTracerCLI);
            self.tracer_cli.?.* = try DispatchTracerCLI.init(self.allocator, config);
        }

        try self.tracer_cli.?.runInteractiveMode();
    }

    // Helper function to parse call expressions
    fn parseCallExpression(self: *Self, expr: []const u8) !ParsedCall {
        // Find function name (everything before first '(')
        const paren_pos = std.mem.indexOf(u8, expr, "(") orelse return error.InvalidExpression;
        const function_name = expr[0..paren_pos];

        // For demo purposes, extract argument types from the expression
        // Real implementation would use proper parsing
        const args_start = paren_pos + 1;
        const close_paren = std.mem.lastIndexOf(u8, expr, ")") orelse return error.InvalidExpression;
        const args_str = expr[args_start..close_paren];

        // Simple argument type inference (very basic for demo)
        var arg_types = ArrayList([]const u8).init(self.allocator);
        defer arg_types.deinit();

        if (args_str.len > 0) {
            var arg_iter = std.mem.split(u8, args_str, ",");
            while (arg_iter.next()) |arg| {
                const trimmed = std.mem.trim(u8, arg, " \t");
                const arg_type = try self.inferArgumentType(trimmed);
                try arg_types.append(arg_type);
            }
        }

        return ParsedCall{
            .function_name = function_name,
            .argument_types = try arg_types.toOwnedSlice(),
        };
    }

    fn inferArgumentType(self: *Self, arg: []const u8) ![]const u8 {
        _ = self;

        // Very basic type inference for demo
        if (std.mem.indexOf(u8, arg, ".") != null) {
            return "f64";
        } else if (std.mem.indexOf(u8, arg, "\"") != null or std.mem.indexOf(u8, arg, "'") != null) {
            return "string";
        } else if (std.fmt.parseInt(i32, arg, 10)) |_| {
            return "i32";
        } else |_| {
            return "unknown";
        }
    }

    const ParsedCall = struct {
        function_name: []const u8,
        argument_types: [][]const u8,
    };

    fn printUsage(self: *Self) !void {
        _ = self;
        print("Janus Dispatch CLI Tools\n", .{});
        print("========================\n\n", .{});
        print("A comprehensive toolkit for analyzing and debugging Janus dispatch behavior.\n\n", .{});

        print("USAGE:\n", .{});
        print("    janus <COMMAND> [OPTIONS]\n\n", .{});

        print("COMMANDS:\n", .{});
        print("    query dispatch-ir <symbol>     Show generated LLVM IR for dispatch family\n", .{});
        print("    query dispatch <signature>     Show dispatch signature information\n", .{});
        print("    trace dispatch [call]          Trace dispatch resolution (interactive or single call)\n", .{});
        print("    help, --help                   Show this help message\n", .{});
        print("    version, --version             Show version information\n\n", .{});

        print("QUERY OPTIONS:\n", .{});
        print("    --show-performance             Include performance analysis in IR query\n", .{});
        print("    --show-optimization            Show optimization strategy details\n", .{});
        print("    --show-candidates              List all candidate implementations\n", .{});
        print("    --show-resolution              Show resolution rules and ordering\n\n", .{});

        print("TRACE OPTIONS:\n", .{});
        print("    --verbose                      Show detailed resolution steps\n", .{});
        print("    --timing                       Include timing analysis\n", .{});
        print("    --json                         Output in JSON format\n", .{});
        print("    --csv                          Output in CSV format\n", .{});
        print("    --flamegraph                   Output flamegraph data\n", .{});
        print("    --filter=<pattern>             Trace only functions matching pattern\n", .{});
        print("    --max-entries=<n>              Maximum trace entries to keep\n\n", .{});

        print("EXAMPLES:\n", .{});
        print("    # Query dispatch IR with performance analysis\n", .{});
        print("    janus query dispatch-ir add --show-performance\n\n", .{});

        print("    # Show all candidates for a signature\n", .{});
        print("    janus query dispatch process --show-candidates\n\n", .{});

        print("    # Trace a specific call with verbose output\n", .{});
        print("    janus trace dispatch 'add(5, 10)' --verbose --timing\n\n", .{});

        print("    # Interactive tracing with JSON output\n", .{});
        print("    janus trace dispatch --json\n\n", .{});

        print("    # Trace only functions containing 'math' and save flamegraph\n", .{});
        print("    janus trace dispatch --filter=math --flamegraph > dispatch.flame\n\n", .{});

        print("For more information, visit: https://github.com/janus-lang/janus\n", .{});
    }

    fn printTraceUsage(self: *Self) !void {
        _ = self;
        print("Trace Commands:\n", .{});
        print("===============\n\n", .{});
        print("janus trace dispatch [call] [options]\n", .{});
        print("  Trace dispatch resolution step-by-step\n\n", .{});

        print("MODES:\n", .{});
        print("  Interactive Mode (no call specified):\n", .{});
        print("    Starts an interactive tracing session where you can:\n", .{});
        print("    - Start/stop tracing with filters\n", .{});
        print("    - Generate reports in various formats\n", .{});
        print("    - Monitor real-time dispatch performance\n\n", .{});

        print("  Single Call Mode (call specified):\n", .{});
        print("    Traces resolution for a specific function call\n", .{});
        print("    Example: janus trace dispatch 'add(5, 10)'\n\n", .{});

        print("OPTIONS:\n", .{});
        print("    --verbose          Show detailed resolution steps\n", .{});
        print("    --timing           Include timing analysis\n", .{});
        print("    --json             Output in JSON format\n", .{});
        print("    --csv              Output in CSV format\n", .{});
        print("    --flamegraph       Output flamegraph data\n", .{});
        print("    --filter=<pattern> Trace only matching functions\n", .{});
        print("    --max-entries=<n>  Maximum trace entries (default: 10000)\n\n", .{});

        print("INTERACTIVE COMMANDS:\n", .{});
        print("    start [filter]     Start tracing (with optional filter)\n", .{});
        print("    stop               Stop tracing\n", .{});
        print("    report [format]    Generate report (console/json/csv/flamegraph)\n", .{});
        print("    clear              Clear trace buffer\n", .{});
        print("    status             Show current status\n", .{});
        print("    help               Show help\n", .{});
        print("    quit               Exit tracer\n\n", .{});
    }

    fn printVersion(self: *Self) !void {
        _ = self;
        print("Janus Dispatch CLI Tools v0.1.0\n", .{});
        print("Built with Zig {s}\n", .{@import("builtin").zig_version_string});
        print("Part of the Janus Programming Language\n", .{});
        print("https://github.com/janus-lang/janus\n", .{});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var cli = JanusDispatchCLI.init(allocator);
    defer cli.deinit();

    try cli.run(args);
}
