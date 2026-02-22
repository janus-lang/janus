// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// CLI tool for querying dispatch information
// Implements: janus query dispatch-ir <symbol>
//            janus query dispatch <signature>
//            janus trace dispatch <call>

const std = @import("std");
const print = std.debug.print;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;

// Import dispatch system components (mock for CLI testing)
const mock_system = @import("mock_dispatch_system.zig");
const DispatchFamily = mock_system.DispatchFamily;
const DispatchTableOptimizer = mock_system.DispatchTableOptimizer;

pub const DispatchQueryCLI = struct {
    allocator: Allocator,
    dispatch_families: HashMap([]const u8, *DispatchFamily, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    optimizer: *DispatchTableOptimizer,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .dispatch_families = HashMap([]const u8, *DispatchFamily, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .optimizer = try DispatchTableOptimizer.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.dispatch_families.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.dispatch_families.deinit();
        self.optimizer.deinit();
        self.allocator.destroy(self.optimizer);
    }

    // Main CLI entry point
    pub fn run(self: *Self, args: []const []const u8) !void {
        if (args.len < 2) {
            try self.printUsage();
            return;
        }

        const command = args[1];

        if (std.mem.eql(u8, command, "query")) {
            if (args.len < 3) {
                try self.printQueryUsage();
                return;
            }

            const subcommand = args[2];
            if (std.mem.eql(u8, subcommand, "dispatch-ir")) {
                try self.queryDispatchIR(args[3..]);
            } else if (std.mem.eql(u8, subcommand, "dispatch")) {
                try self.queryDispatch(args[3..]);
            } else {
                try self.printQueryUsage();
            }
        } else if (std.mem.eql(u8, command, "trace")) {
            if (args.len < 3) {
                try self.printTraceUsage();
                return;
            }

            const subcommand = args[2];
            if (std.mem.eql(u8, subcommand, "dispatch")) {
                try self.traceDispatch(args[3..]);
            } else {
                try self.printTraceUsage();
            }
        } else {
            try self.printUsage();
        }
    }

    // Query dispatch IR generation for a symbol
    fn queryDispatchIR(self: *Self, args: []const []const u8) !void {
        if (args.len == 0) {
            print("Error: Missing symbol name\n", .{});
            try self.printQueryUsage();
            return;
        }

        const symbol = args[0];
        const show_performance = self.hasFlag(args, "--show-performance");
        const show_optimization = self.hasFlag(args, "--show-optimization");

        print("🔍 Dispatch IR Query: {s}\n", .{symbol});
        print("=" ** 50 ++ "\n", .{});

        // Find dispatch family
        const family = self.dispatch_families.get(symbol);
        if (family == null) {
            print("❌ No dispatch family found for symbol '{s}'\n", .{symbol});
            try self.suggestSimilarSymbols(symbol);
            return;
        }

        const dispatch_family = family.?;

        // Show basic information
        try self.showFamilyInfo(dispatch_family);

        // Generate and show IR
        try self.showGeneratedIR(dispatch_family, show_performance, show_optimization);

        if (show_performance) {
            try self.showPerformanceAnalysis(dispatch_family);
        }

        if (show_optimization) {
            try self.showOptimizationDetails(dispatch_family);
        }
    }

    // Query dispatch signature information
    fn queryDispatch(self: *Self, args: []const []const u8) !void {
        if (args.len == 0) {
            print("Error: Missing signature name\n", .{});
            try self.printQueryUsage();
            return;
        }

        const signature = args[0];
        const show_candidates = self.hasFlag(args, "--show-candidates");
        const show_resolution = self.hasFlag(args, "--show-resolution");

        print("📋 Dispatch Query: {s}\n", .{signature});
        print("=" ** 50 ++ "\n", .{});

        // Find and display signature information
        const family = self.dispatch_families.get(signature);
        if (family == null) {
            print("❌ No dispatch family found for signature '{s}'\n", .{signature});
            try self.suggestSimilarSymbols(signature);
            return;
        }

        const dispatch_family = family.?;

        try self.showSignatureOverview(dispatch_family);

        if (show_candidates) {
            try self.showAllCandidates(dispatch_family);
        }

        if (show_resolution) {
            try self.showResolutionRules(dispatch_family);
        }
    }

    // Trace dispatch resolution for a specific call
    fn traceDispatch(self: *Self, args: []const []const u8) !void {
        if (args.len == 0) {
            print("Error: Missing call expression\n", .{});
            try self.printTraceUsage();
            return;
        }

        const call_expr = args[0];
        const verbose = self.hasFlag(args, "--verbose");
        const show_timing = self.hasFlag(args, "--timing");

        print("🔍 Dispatch Trace: {s}\n", .{call_expr});
        print("=" ** 50 ++ "\n", .{});

        // Parse call expression (simplified for demo)
        const parsed_call = try self.parseCallExpression(call_expr);

        // Find dispatch family
        const family = self.dispatch_families.get(parsed_call.function_name);
        if (family == null) {
            print("❌ No dispatch family found for function '{s}'\n", .{parsed_call.function_name});
            return;
        }

        const dispatch_family = family.?;

        // Trace resolution step by step
        try self.traceResolutionSteps(dispatch_family, parsed_call, verbose, show_timing);
    }

    // Show family information
    fn showFamilyInfo(self: *Self, family: *DispatchFamily) !void {
        _ = self;
        print("📊 Family Overview:\n", .{});
        print("  Name: {s}\n", .{family.name});
        print("  Implementations: {d}\n", .{family.implementations.items.len});
        print("  Strategy: {s}\n", .{@tagName(family.strategy)});
        print("  Static Resolvable: {s}\n", .{if (family.is_static_resolvable) "✅ Yes" else "❌ No"});
        print("\n", .{});
    }

    // Show generated IR
    fn showGeneratedIR(self: *Self, family: *DispatchFamily, show_performance: bool, show_optimization: bool) !void {
        print("🔧 Generated LLVM IR:\n", .{});
        print("-" ** 30 ++ "\n", .{});

        // Generate IR using the optimizer
        var ir_result = try self.optimizer.generateDispatchIR(family);
        defer ir_result.deinit();

        // Display the IR with syntax highlighting (simplified)
        try self.displayIRWithHighlighting(ir_result.ir_code);

        if (show_performance) {
            print("\n📈 Performance Characteristics:\n", .{});
            print("  Strategy: {s}\n", .{@tagName(ir_result.strategy)});
            print("  Estimated Cycles: {d}\n", .{ir_result.estimated_cycles});
            print("  Memory Overhead: {d} bytes\n", .{ir_result.memory_overhead});
            print("  Cache Efficiency: {s}\n", .{ir_result.cache_efficiency});
        }

        if (show_optimization) {
            print("\n⚡ Optimization Details:\n", .{});
            for (ir_result.optimizations) |opt| {
                print("  • {s}: {s}\n", .{ opt.name, opt.description });
            }
        }
    }

    // Show performance analysis
    fn showPerformanceAnalysis(self: *Self, family: *DispatchFamily) !void {
        print("\n📊 Performance Analysis:\n", .{});
        print("-" ** 25 ++ "\n", .{});

        // Analyze performance characteristics
        const analysis = try self.optimizer.analyzePerformance(family);
        defer analysis.deinit();

        print("  Dispatch Overhead: {d}ns\n", .{analysis.dispatch_overhead_ns});
        print("  Memory Usage: {d} bytes\n", .{analysis.memory_usage_bytes});
        print("  Cache Misses: {d}%\n", .{analysis.cache_miss_percentage});
        print("  Hot Path Optimization: {s}\n", .{if (analysis.has_hot_path_optimization) "✅ Enabled" else "❌ Disabled"});

        if (analysis.bottlenecks.len > 0) {
            print("\n⚠️  Performance Bottlenecks:\n", .{});
            for (analysis.bottlenecks) |bottleneck| {
                print("    • {s}: {s}\n", .{ bottleneck.location, bottleneck.description });
            }
        }

        if (analysis.recommendations.len > 0) {
            print("\n💡 Optimization Recommendations:\n", .{});
            for (analysis.recommendations) |rec| {
                print("    • {s}\n", .{rec});
            }
        }
    }

    // Show optimization details
    fn showOptimizationDetails(self: *Self, family: *DispatchFamily) !void {
        print("\n⚙️  Optimization Strategy Details:\n", .{});
        print("-" ** 35 ++ "\n");

        const strategy_info = try self.optimizer.getStrategyInfo(family);
        defer strategy_info.deinit();

        print("  Selected Strategy: {s}\n", .{@tagName(strategy_info.strategy)});
        print("  Selection Reason: {s}\n", .{strategy_info.selection_reason});
        print("  Fallback Available: {s}\n", .{if (strategy_info.has_fallback) "✅ Yes" else "❌ No"});

        switch (strategy_info.strategy) {
            .perfect_hash => {
                print("  Hash Function: {s}\n", .{strategy_info.perfect_hash.hash_function});
                print("  Table Size: {d} entries\n", .{strategy_info.perfect_hash.table_size});
                print("  Load Factor: {d:.2}%\n", .{strategy_info.perfect_hash.load_factor * 100});
            },
            .inline_cache => {
                print("  Cache Size: {d} slots\n", .{strategy_info.inline_cache.cache_size});
                print("  Hit Rate: {d:.1}%\n", .{strategy_info.inline_cache.hit_rate * 100});
                print("  Eviction Policy: {s}\n", .{strategy_info.inline_cache.eviction_policy});
            },
            .switch_table => {
                print("  Table Entries: {d}\n", .{strategy_info.switch_table.entry_count});
                print("  Jump Table: {s}\n", .{if (strategy_info.switch_table.uses_jump_table) "✅ Yes" else "❌ No"});
            },
        }
    }

    // Show signature overview
    fn showSignatureOverview(self: *Self, family: *DispatchFamily) !void {
        print("📝 Signature: {s}\n", .{family.name});
        print("  Arity: {d} parameters\n", .{family.arity});
        print("  Implementations: {d}\n", .{family.implementations.items.len});
        print("  Ambiguities: {d}\n", .{family.ambiguity_count});
        print("\n", .{});

        print("🎯 Implementation Summary:\n", .{});
        for (family.implementations.items, 0..) |impl, i| {
            const status = if (impl.is_reachable) "✅" else "❌";
            print("  {d}. {s} {s}({s}) -> {s}\n", .{
                i + 1,
                status,
                impl.name,
                try self.formatParameterTypes(impl.parameter_types),
                impl.return_type,
            });
        }
        print("\n", .{});
    }

    // Show all candidates
    fn showAllCandidates(self: *Self, family: *DispatchFamily) !void {
        print("🔍 All Candidates:\n", .{});
        print("-" ** 20 ++ "\n");

        for (family.implementations.items, 0..) |impl, i| {
            print("Candidate {d}: {s}\n", .{ i + 1, impl.name });
            print("  Parameters: ({s})\n", .{try self.formatParameterTypes(impl.parameter_types)});
            print("  Return Type: {s}\n", .{impl.return_type});
            print("  Specificity Rank: {d}\n", .{impl.specificity_rank});
            print("  Source: {s}:{d}:{d}\n", .{ impl.source_file, impl.source_line, impl.source_column });
            print("  Reachable: {s}\n", .{if (impl.is_reachable) "✅ Yes" else "❌ No"});

            if (!impl.is_reachable) {
                print("  Unreachable Reason: {s}\n", .{impl.unreachable_reason});
            }

            print("\n", .{});
        }
    }

    // Show resolution rules
    fn showResolutionRules(self: *Self, family: *DispatchFamily) !void {
        print("⚖️  Resolution Rules:\n", .{});
        print("-" ** 20 ++ "\n");

        print("1. Exact Type Match (highest priority)\n", .{});
        print("2. Subtype Match (by specificity)\n", .{});
        print("3. Convertible Match (lowest priority)\n", .{});
        print("\n", .{});

        print("🎯 Specificity Ordering:\n", .{});
        const sorted_impls = try self.getSortedImplementations(family);
        defer sorted_impls.deinit();

        for (sorted_impls.items, 0..) |impl, i| {
            print("  {d}. {s}({s})\n", .{
                i + 1,
                impl.name,
                try self.formatParameterTypes(impl.parameter_types),
            });
        }
    }

    // Trace resolution steps
    fn traceResolutionSteps(self: *Self, family: *DispatchFamily, call: ParsedCall, verbose: bool, show_timing: bool) !void {
        print("🔍 Resolution Trace for: {s}({s})\n", .{ call.function_name, try self.formatArgumentTypes(call.argument_types) });
        print("-" ** 40 ++ "\n");

        var step: u32 = 1;

        // Step 1: Find matching candidates
        print("Step {d}: Finding matching candidates...\n", .{step});
        step += 1;

        const matching_candidates = try self.findMatchingCandidates(family, call.argument_types);
        defer matching_candidates.deinit();

        print("  Found {d} matching candidates:\n", .{matching_candidates.items.len});
        for (matching_candidates.items) |candidate| {
            print("    • {s}({s})\n", .{ candidate.name, try self.formatParameterTypes(candidate.parameter_types) });
        }
        print("\n", .{});

        if (matching_candidates.items.len == 0) {
            print("❌ No matching candidates found. Resolution failed.\n", .{});
            try self.showAvailableAlternatives(family, call.argument_types);
            return;
        }

        // Step 2: Apply specificity rules
        print("Step {d}: Applying specificity rules...\n", .{step});
        step += 1;

        const most_specific = try self.findMostSpecific(matching_candidates.items, call.argument_types, verbose);

        if (most_specific.len == 1) {
            print("✅ Resolution successful!\n", .{});
            print("  Selected: {s}({s})\n", .{ most_specific[0].name, try self.formatParameterTypes(most_specific[0].parameter_types) });

            if (show_timing) {
                try self.showTimingAnalysis(family, call);
            }
        } else if (most_specific.len > 1) {
            print("❌ Ambiguous dispatch!\n", .{});
            print("  Conflicting candidates:\n", .{});
            for (most_specific) |candidate| {
                print("    • {s}({s})\n", .{ candidate.name, try self.formatParameterTypes(candidate.parameter_types) });
            }
        } else {
            print("❌ No most specific candidate found.\n", .{});
        }
    }

    // Helper functions
    fn hasFlag(self: *Self, args: []const []const u8, flag: []const u8) bool {
        _ = self;
        for (args) |arg| {
            if (std.mem.eql(u8, arg, flag)) {
                return true;
            }
        }
        return false;
    }

    fn suggestSimilarSymbols(self: *Self, symbol: []const u8) !void {
        print("\n💡 Did you mean one of these?\n", .{});

        var suggestions: ArrayList([]const u8) = .empty;
        defer suggestions.deinit();

        var iterator = self.dispatch_families.iterator();
        while (iterator.next()) |entry| {
            const name = entry.key_ptr.*;
            if (self.calculateLevenshteinDistance(symbol, name) <= 2) {
                try suggestions.append(name);
            }
        }

        if (suggestions.items.len > 0) {
            for (suggestions.items) |suggestion| {
                print("  • {s}\n", .{suggestion});
            }
        } else {
            print("  No similar symbols found.\n", .{});
        }
    }

    fn calculateLevenshteinDistance(self: *Self, a: []const u8, b: []const u8) u32 {
        _ = self;
        // Simplified Levenshtein distance calculation
        if (a.len == 0) return @intCast(b.len);
        if (b.len == 0) return @intCast(a.len);

        // For demo purposes, just check if one is a substring of the other
        if (std.mem.indexOf(u8, a, b) != null or std.mem.indexOf(u8, b, a) != null) {
            return 1;
        }

        return 3; // Default high distance
    }

    // Placeholder structures and functions for demo
    const ParsedCall = struct {
        function_name: []const u8,
        argument_types: []const []const u8,
    };

    fn parseCallExpression(self: *Self, expr: []const u8) !ParsedCall {
        _ = self;
        // Simplified parsing for demo
        // Real implementation would use proper parser

        const paren_pos = std.mem.indexOf(u8, expr, "(") orelse return error.InvalidExpression;
        const function_name = expr[0..paren_pos];

        // For demo, just return empty argument types
        return ParsedCall{
            .function_name = function_name,
            .argument_types = &[_][]const u8{},
        };
    }

    fn formatParameterTypes(self: *Self, types: []const []const u8) ![]const u8 {
        // Simplified formatting for demo
        if (types.len == 0) return "";
        return std.mem.join(self.allocator, ", ", types);
    }

    fn formatArgumentTypes(self: *Self, types: []const []const u8) ![]const u8 {
        return self.formatParameterTypes(types);
    }

    fn displayIRWithHighlighting(self: *Self, ir_code: []const u8) !void {
        _ = self;
        // Simplified IR display for demo
        print("{s}\n", .{ir_code});
    }

    // Usage help functions
    fn printUsage(self: *Self) !void {
        _ = self;
        print("Janus Dispatch CLI Tools\n", .{});
        print("========================\n\n", .{});
        print("Usage: janus <command> [options]\n\n", .{});
        print("Commands:\n", .{});
        print("  query dispatch-ir <symbol>     Show generated LLVM IR for dispatch\n", .{});
        print("  query dispatch <signature>     Show dispatch signature information\n", .{});
        print("  trace dispatch <call>          Trace dispatch resolution step-by-step\n\n", .{});
        print("Examples:\n", .{});
        print("  janus query dispatch-ir add --show-performance\n", .{});
        print("  janus query dispatch process --show-candidates\n", .{});
        print("  janus trace dispatch 'add(5, 10)' --verbose\n\n", .{});
    }

    fn printQueryUsage(self: *Self) !void {
        _ = self;
        print("Query Commands:\n", .{});
        print("===============\n\n", .{});
        print("janus query dispatch-ir <symbol> [options]\n", .{});
        print("  Show generated LLVM IR for dispatch family\n", .{});
        print("  Options:\n", .{});
        print("    --show-performance    Include performance analysis\n", .{});
        print("    --show-optimization   Show optimization details\n\n", .{});
        print("janus query dispatch <signature> [options]\n", .{});
        print("  Show dispatch signature information\n", .{});
        print("  Options:\n", .{});
        print("    --show-candidates     List all candidate implementations\n", .{});
        print("    --show-resolution     Show resolution rules and ordering\n\n", .{});
    }

    fn printTraceUsage(self: *Self) !void {
        _ = self;
        print("Trace Commands:\n", .{});
        print("===============\n\n", .{});
        print("janus trace dispatch <call> [options]\n", .{});
        print("  Trace dispatch resolution step-by-step\n", .{});
        print("  Options:\n", .{});
        print("    --verbose     Show detailed resolution steps\n", .{});
        print("    --timing      Include timing analysis\n\n", .{});
        print("Examples:\n", .{});
        print("  janus trace dispatch 'process(data)'\n", .{});
        print("  janus trace dispatch 'add(x, y)' --verbose --timing\n\n", .{});
    }

    // Placeholder implementations for missing functions
    fn findMatchingCandidates(self: *Self, family: *DispatchFamily, arg_types: []const []const u8) !ArrayList(DispatchFamily.Implementation) {
        _ = arg_types;
        var candidates: ArrayList(DispatchFamily.Implementation) = .empty;

        // For demo, return all implementations
        for (family.implementations.items) |impl| {
            try candidates.append(impl);
        }

        return candidates;
    }

    fn findMostSpecific(self: *Self, candidates: []const DispatchFamily.Implementation, arg_types: []const []const u8, verbose: bool) ![]const DispatchFamily.Implementation {
        _ = self;
        _ = arg_types;
        _ = verbose;

        // For demo, return first candidate
        if (candidates.len > 0) {
            return candidates[0..1];
        }
        return candidates[0..0];
    }

    fn showAvailableAlternatives(self: *Self, family: *DispatchFamily, arg_types: []const []const u8) !void {
        _ = arg_types;

        print("\n💡 Available alternatives:\n", .{});
        for (family.implementations.items) |impl| {
            print("  • {s}({s})\n", .{ impl.name, try self.formatParameterTypes(impl.parameter_types) });
        }
    }

    fn showTimingAnalysis(self: *Self, family: *DispatchFamily, call: ParsedCall) !void {
        _ = family;
        _ = call;

        print("\n⏱️  Timing Analysis:\n", .{});
        print("  Dispatch Resolution: 45ns\n", .{});
        print("  Cache Lookup: 12ns\n", .{});
        print("  Total Overhead: 57ns\n", .{});

        _ = self;
    }

    fn getSortedImplementations(self: *Self, family: *DispatchFamily) !ArrayList(DispatchFamily.Implementation) {
        var sorted: ArrayList(DispatchFamily.Implementation) = .empty;

        for (family.implementations.items) |impl| {
            try sorted.append(impl);
        }

        // Sort by specificity rank (simplified)
        // Real implementation would use proper sorting

        return sorted;
    }
};

// Main CLI entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var cli = try DispatchQueryCLI.init(allocator);
    defer cli.deinit();

    // Load dispatch families from project (placeholder)
    const loader = DispatchQueryCLIExt;
    try loader.loadDispatchFamilies(&cli);

    try cli.run(args);
}

// Extension for loading dispatch families
pub const DispatchQueryCLIExt = struct {
    pub fn loadDispatchFamilies(cli: *DispatchQueryCLI) !void {
        // Placeholder: In real implementation, this would:
        // 1. Parse project files
        // 2. Build dispatch families
        // 3. Populate the CLI's dispatch_families map

        // For demo, create some sample families
        try createSampleDispatchFamilies(cli);
    }

    fn createSampleDispatchFamilies(cli: *DispatchQueryCLI) !void {
        // Create sample "add" family
        const add_family = try cli.allocator.create(DispatchFamily);
        add_family.* = try DispatchFamily.init(cli.allocator, "add");

        // Add sample implementations
        try add_family.addImplementation(.{
            .name = "add_i32",
            .parameter_types = &[_][]const u8{ "i32", "i32" },
            .return_type = "i32",
            .specificity_rank = 1,
            .is_reachable = true,
            .source_file = "math.jan",
            .source_line = 10,
            .source_column = 1,
            .unreachable_reason = "",
        });

        try add_family.addImplementation(.{
            .name = "add_f64",
            .parameter_types = &[_][]const u8{ "f64", "f64" },
            .return_type = "f64",
            .specificity_rank = 1,
            .is_reachable = true,
            .source_file = "math.jan",
            .source_line = 15,
            .source_column = 1,
            .unreachable_reason = "",
        });

        try cli.dispatch_families.put("add", add_family);

        // Create sample "process" family
        const process_family = try cli.allocator.create(DispatchFamily);
        process_family.* = try DispatchFamily.init(cli.allocator, "process");

        try process_family.addImplementation(.{
            .name = "process_string",
            .parameter_types = &[_][]const u8{"string"},
            .return_type = "string",
            .specificity_rank = 1,
            .is_reachable = true,
            .source_file = "data.jan",
            .source_line = 20,
            .source_column = 1,
            .unreachable_reason = "",
        });

        try cli.dispatch_families.put("process", process_family);
    }
};
