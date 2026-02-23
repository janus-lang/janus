// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;
const TestMetadata = @import("test_metadata.zig").TestMetadata;

/// Golden Diff Engine - Semantic LLVM IR comparison for Golden Test Framework
/// Performs intelligent comparison focusing on meaning rather than
/// Enforces metadata contracts through deep IR analysis
pub const GoldenDiff = struct {
    allocator: Allocator,

    const Self = @This();

    /// Semantic difference types
    pub const DifferenceType = enum {
        function_signature,
        instruction_sequence,
        dispatch_table_structure,
        call_pattern,
        type_coercion,
        optimization_annotation,
        metadata_mismatch,
        performance_regression,
    };

    /// Severity levels for differences
    pub const Severity = enum {
        critical, // Breaks functionality
        major, // Significant performance impact
        minor, // Cosmetic or negligible impact
        info, // Informational only
    };

    /// Location within IR
    pub const IRLocation = struct {
        function_name: []const u8,
        basic_block: ?[]const u8,
        instruction_index: ?u32,
        line_number: u32,
    };

    /// Semantic difference found during comparison
    pub const SemanticDifference = struct {
        difference_type: DifferenceType,
        severity: Severity,
        location: IRLocation,
        expected: []const u8,
        actual: []const u8,
        description: []const u8,
        suggestion: ?[]const u8,

        pub fn deinit(self: *SemanticDifference, allocator: Allocator) void {
            allocator.free(self.expected);
            allocator.free(self.actual);
            allocator.free(self.description);
            if (self.suggestion) |suggestion| {
                allocator.free(suggestion);
            }
        }
    };

    /// IR analysis result
    pub const IRAnalysis = struct {
        functions: []FunctionAnalysis,
        dispatch_tables: []DispatchTableAnalysis,
        call_patterns: []CallPatternAnalysis,
        performance_metrics: PerformanceMetrics,

        pub const FunctionAnalysis = struct {
            name: []const u8,
            signature: []const u8,
            attributes: [][]const u8,
            instruction_count: u32,
            basic_block_count: u32,
            is_inlined: bool,
            optimization_level: OptimizationLevel,

            pub const OptimizationLevel = enum {
                none,
                basic,
                aggressive,
                size_optimized,
            };
        };

        pub const DispatchTableAnalysis = struct {
            table_name: []const u8,
            entry_count: u32,
            table_type: TableType,
            access_pattern: AccessPattern,

            pub const TableType = enum {
                direct_array,
                switch_table,
                hash_table,
                binary_search,
            };

            pub const AccessPattern = enum {
                constant_time,
                logarithmic,
                linear,
                unknown,
            };
        };

        pub const CallPatternAnalysis = struct {
            caller_function: []const u8,
            callee_function: []const u8,
            call_type: CallType,
            is_tail_call: bool,
            is_inlined: bool,

            pub const CallType = enum {
                direct,
                indirect,
                virtual,
                intrinsic,
            };
        };

        pub const PerformanceMetrics = struct {
            total_instructions: u32,
            memory_allocations: u32,
            function_calls: u32,
            indirect_calls: u32,
            branch_instructions: u32,
            estimated_cycles: u64,
        };

        pub fn deinit(self: *IRAnalysis, allocator: Allocator) void {
            for (self.functions) |*func| {
                allocator.free(func.name);
                allocator.free(func.signature);
                for (func.attributes) |attr| {
                    allocator.free(attr);
                }
                allocator.free(func.attributes);
            }
            allocator.free(self.functions);

            for (self.dispatch_tables) |*table| {
                allocator.free(table.table_name);
            }
            allocator.free(self.dispatch_tables);

            for (self.call_patterns) |*pattern| {
                allocator.free(pattern.caller_function);
                allocator.free(pattern.callee_function);
            }
            allocator.free(self.call_patterns);
        }
    };

    /// Comparison result
    pub const ComparisonResult = struct {
        matches_semantically: bool,
        differences: []SemanticDifference,
        golden_analysis: IRAnalysis,
        generated_analysis: IRAnalysis,
        contract_violations: []ContractViolation,

        pub const ContractViolation = struct {
            violation_type: ViolationType,
            description: []const u8,
            expected_behavior: []const u8,
            actual_behavior: []const u8,
            metadata_source: []const u8,

            pub const ViolationType = enum {
                dispatch_strategy_mismatch,
                performance_regression,
                optimization_failure,
                platform_incompatibility,
                validation_rule_failure,
            };

            pub fn deinit(self: *ContractViolation, allocator: Allocator) void {
                allocator.free(self.description);
                allocator.free(self.expected_behavior);
                allocator.free(self.actual_behavior);
                allocator.free(self.metadata_source);
            }
        };

        pub fn deinit(self: *ComparisonResult, allocator: Allocator) void {
            for (self.differences) |*diff| {
                diff.deinit(allocator);
            }
            allocator.free(self.differences);

            self.servicelden_analysis.deinit(allocator);
            self.generated_analysis.deinit(allocator);

            for (self.contract_violations) |*violation| {
                violation.deinit(allocator);
            }
            allocator.free(self.contract_violations);
        }
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Compare generated IR against golden reference with metadata contracts
    pub fn compareIR(self: *Self, golden_ir: []const u8, generated_ir: []const u8, metadata: TestMetadata) !ComparisonResult {
        // Analyze both IR files
        const golden_analysis = try self.analyzeIR(golden_ir);
        const generated_analysis = try self.analyzeIR(generated_ir);

        // Find semantic differences
        var differences: ArrayList(SemanticDifference) = .empty;
        defer differences.deinit();

        try self.compareFunctions(&differences, golden_analysis.functions, generated_analysis.functions);
        try self.compareDispatchTables(&differences, golden_analysis.dispatch_tables, generated_analysis.dispatch_tables);
        try self.compareCallPatterns(&differences, golden_analysis.call_patterns, generated_analysis.call_patterns);
        try self.comparePerformanceMetrics(&differences, golden_analysis.performance_metrics, generated_analysis.performance_metrics);

        // Check contract violations
        var contract_violations: ArrayList(ComparisonResult.ContractViolation) = .empty;
        defer contract_violations.deinit();

        try self.validateMetadataContracts(&contract_violations, generated_analysis, metadata);

        const matches_semantically = differences.items.len == 0 and
            contract_violations.items.len == 0;

        return ComparisonResult{
            .matches_semantically = matches_semantically,
            .differences = try differences.toOwnedSlice(),
            .servicelden_analysis = golden_analysis,
            .generated_analysis = generated_analysis,
            .contract_violations = try contract_violations.toOwnedSlice(),
        };
    }

    /// Analyze LLVM IR to extract semantic information
    fn analyzeIR(self: *Self, ir: []const u8) !IRAnalysis {
        var functions: ArrayList(IRAnalysis.FunctionAnalysis) = .empty;
        defer functions.deinit();

        var dispatch_tables: ArrayList(IRAnalysis.DispatchTableAnalysis) = .empty;
        defer dispatch_tables.deinit();

        var call_patterns: ArrayList(IRAnalysis.CallPatternAnalysis) = .empty;
        defer call_patterns.deinit();

        var performance_metrics = IRAnalysis.PerformanceMetrics{
            .total_instructions = 0,
            .memory_allocations = 0,
            .function_calls = 0,
            .indirect_calls = 0,
            .branch_instructions = 0,
            .estimated_cycles = 0,
        };

        // Parse IR line by line
        var lines = std.mem.splitScalar(u8, ir, '\n');
        var current_function: ?[]const u8 = null;
        var line_number: u32 = 0;

        while (lines.next()) |line| {
            line_number += 1;
            const trimmed = std.mem.trim(u8, line, " \t");

            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, ";")) {
                continue; // Skip empty lines and comments
            }

            // Detect function definitions
            if (std.mem.startsWith(u8, trimmed, "define")) {
                const func_analysis = try self.parseFunctionDefinition(trimmed);
                try functions.append(func_analysis);
                current_function = func_analysis.name;
            }

            // Detect dispatch tables
            else if (std.mem.indexOf(u8, trimmed, "dispatch_table") != null) {
                const table_analysis = try self.parseDispatchTable(trimmed);
                try dispatch_tables.append(table_analysis);
            }

            // Detect call patterns
            else if (std.mem.indexOf(u8, trimmed, "call") != null) {
                if (current_function) |caller| {
                    const call_analysis = try self.parseCallPattern(trimmed, caller);
                    try call_patterns.append(call_analysis);
                    performance_metrics.function_calls += 1;

                    if (std.mem.indexOf(u8, trimmed, "indirect") != null) {
                        performance_metrics.indirect_calls += 1;
                    }
                }
            }

            // Count instructions and other metrics
            if (self.isInstruction(trimmed)) {
                performance_metrics.total_instructions += 1;

                if (std.mem.indexOf(u8, trimmed, "alloca") != null or
                    std.mem.indexOf(u8, trimmed, "malloc") != null)
                {
                    performance_metrics.memory_allocations += 1;
                }

                if (std.mem.indexOf(u8, trimmed, "br") != null or
                    std.mem.indexOf(u8, trimmed, "switch") != null)
                {
                    performance_metrics.branch_instructions += 1;
                }
            }
        }

        // Estimate cycles based on instruction mix
        performance_metrics.estimated_cycles = self.estimateCycles(performance_metrics);

        return IRAnalysis{
            .functions = try functions.toOwnedSlice(),
            .dispatch_tables = try dispatch_tables.toOwnedSlice(),
            .call_patterns = try call_patterns.toOwnedSlice(),
            .performance_metrics = performance_metrics,
        };
    }

    /// Parse function definition from IR line
    fn parseFunctionDefinition(self: *Self, line: []const u8) !IRAnalysis.FunctionAnalysis {
        // Extract function name from "define ... @function_name(...)"
        const at_pos = std.mem.indexOf(u8, line, "@") orelse return error.InvalidFunctionDefinition;
        const paren_pos = std.mem.indexOf(u8, line[at_pos..], "(") orelse return error.InvalidFunctionDefinition;

        const func_name = line[at_pos + 1 .. at_pos + paren_pos];

        return IRAnalysis.FunctionAnalysis{
            .name = try self.allocator.dupe(u8, func_name),
            .signature = try self.allocator.dupe(u8, line),
            .attributes = &.{}, // Would be parsed from attributes section
            .instruction_count = 0, // Would be counted during full analysis
            .basic_block_count = 0, // Would be counted during full analysis
            .is_inlined = std.mem.indexOf(u8, line, "inlinehint") != null,
            .optimization_level = .basic, // Would be determined from attributes
        };
    }

    /// Parse dispatch table from IR line
    fn parseDispatchTable(self: *Self, line: []const u8) !IRAnalysis.DispatchTableAnalysis {
        // Extract table name and analyze structure
        const at_pos = std.mem.indexOf(u8, line, "@") orelse return error.InvalidDispatchTable;
        const eq_pos = std.mem.indexOf(u8, line[at_pos..], "=") orelse return error.InvalidDispatchTable;

        const table_name = std.mem.trim(u8, line[at_pos + 1 .. at_pos + eq_pos], " ");

        // Determine table type based on structure
        const table_type: IRAnalysis.DispatchTableAnalysis.TableType = if (std.mem.indexOf(u8, line, "[") != null)
            .direct_array
        else if (std.mem.indexOf(u8, line, "switch") != null)
            .switch_table
        else
            .hash_table;

        return IRAnalysis.DispatchTableAnalysis{
            .table_name = try self.allocator.dupe(u8, table_name),
            .entry_count = 0, // Would be parsed from array size
            .table_type = table_type,
            .access_pattern = .constant_time, // Would be analyzed
        };
    }

    /// Parse call pattern from IR line
    fn parseCallPattern(self: *Self, line: []const u8, caller: []const u8) !IRAnalysis.CallPatternAnalysis {
        // Extract callee function name
        const at_pos = std.mem.indexOf(u8, line, "@");
        const callee = if (at_pos) |pos| blk: {
            const end_pos = std.mem.indexOfAny(u8, line[pos..], " (") orelse line.len - pos;
            break :blk line[pos + 1 .. pos + end_pos];
        } else "unknown";

        const call_type: IRAnalysis.CallPatternAnalysis.CallType = if (std.mem.indexOf(u8, line, "indirect") != null)
            .indirect
        else if (std.mem.indexOf(u8, line, "@llvm.") != null)
            .intrinsic
        else
            .direct;

        return IRAnalysis.CallPatternAnalysis{
            .caller_function = try self.allocator.dupe(u8, caller),
            .callee_function = try self.allocator.dupe(u8, callee),
            .call_type = call_type,
            .is_tail_call = std.mem.indexOf(u8, line, "tail") != null,
            .is_inlined = false, // Would be determined by analysis
        };
    }

    /// Check if line represents an instruction
    fn isInstruction(_: *Self, line: []const u8) bool {
        return std.mem.indexOf(u8, line, "=") != null or
            std.mem.startsWith(u8, line, "ret") or
            std.mem.startsWith(u8, line, "br") or
            std.mem.startsWith(u8, line, "call") or
            std.mem.startsWith(u8, line, "store") or
            std.mem.startsWith(u8, line, "load");
    }

    /// Estimate execution cycles based on instruction mix
    fn estimateCycles(_: *Self, metrics: IRAnalysis.PerformanceMetrics) u64 {
        // Simplified cycle estimation
        var cycles: u64 = 0;
        cycles += metrics.total_instructions; // Base cost
        cycles += metrics.memory_allocations * 10; // Memory operations are expensive
        cycles += metrics.indirect_calls * 5; // Indirect calls have overhead
        cycles += metrics.branch_instructions * 2; // Branches can cause pipeline stalls
        return cycles;
    }

    /// Compare function analyses
    fn compareFunctions(self: *Self, differences: *ArrayList(SemanticDifference), golden: []IRAnalysis.FunctionAnalysis, generated: []IRAnalysis.FunctionAnalysis) !void {
        // Check for missing or extra functions
        for (golden) |golden_func| {
            var found = false;
            for (generated) |generated_func| {
                if (std.mem.eql(u8, golden_func.name, generated_func.name)) {
                    found = true;
                    // Compare function details
                    if (!std.mem.eql(u8, golden_func.signature, generated_func.signature)) {
                        try differences.append(.{
                            .difference_type = .function_signature,
                            .severity = .major,
                            .location = .{
                                .function_name = try self.allocator.dupe(u8, golden_func.name),
                                .basic_block = null,
                                .instruction_index = null,
                                .line_number = 0,
                            },
                            .expected = try self.allocator.dupe(u8, golden_func.signature),
                            .actual = try self.allocator.dupe(u8, generated_func.signature),
                            .description = try std.fmt.allocPrint(self.allocator, "Function signature mismatch for '{s}'", .{golden_func.name}),
                            .suggestion = try std.fmt.allocPrint(self.allocator, "Ensure function signature matches golden reference"),
                        });
                    }
                    break;
                }
            }

            if (!found) {
                try differences.append(.{
                    .difference_type = .function_signature,
                    .severity = .critical,
                    .location = .{
                        .function_name = try self.allocator.dupe(u8, golden_func.name),
                        .basic_block = null,
                        .instruction_index = null,
                        .line_number = 0,
                    },
                    .expected = try self.allocator.dupe(u8, golden_func.name),
                    .actual = try self.allocator.dupe(u8, "missing"),
                    .description = try std.fmt.allocPrint(self.allocator, "Missing function '{s}' in generated IR", .{golden_func.name}),
                    .suggestion = try std.fmt.allocPrint(self.allocator, "Ensure all required functions are generated"),
                });
            }
        }
    }

    /// Compare dispatch table analyses
    fn compareDispatchTables(self: *Self, differences: *ArrayList(SemanticDifference), golden: []IRAnalysis.DispatchTableAnalysis, generated: []IRAnalysis.DispatchTableAnalysis) !void {
        for (golden) |golden_table| {
            var found = false;
            for (generated) |generated_table| {
                if (std.mem.eql(u8, golden_table.table_name, generated_table.table_name)) {
                    found = true;

                    if (golden_table.table_type != generated_table.table_type) {
                        try differences.append(.{
                            .difference_type = .dispatch_table_structure,
                            .severity = .major,
                            .location = .{
                                .function_name = try self.allocator.dupe(u8, "global"),
                                .basic_block = null,
                                .instruction_index = null,
                                .line_number = 0,
                            },
                            .expected = try std.fmt.allocPrint(self.allocator, "{}", .{golden_table.table_type}),
                            .actual = try std.fmt.allocPrint(self.allocator, "{}", .{generated_table.table_type}),
                            .description = try std.fmt.allocPrint(self.allocator, "Dispatch table type mismatch for '{s}'", .{golden_table.table_name}),
                            .suggestion = try std.fmt.allocPrint(self.allocator, "Ensure dispatch table uses expected optimization strategy"),
                        });
                    }
                    break;
                }
            }

            if (!found) {
                try differences.append(.{
                    .difference_type = .dispatch_table_structure,
                    .severity = .critical,
                    .location = .{
                        .function_name = try self.allocator.dupe(u8, "global"),
                        .basic_block = null,
                        .instruction_index = null,
                        .line_number = 0,
                    },
                    .expected = try self.allocator.dupe(u8, golden_table.table_name),
                    .actual = try self.allocator.dupe(u8, "missing"),
                    .description = try std.fmt.allocPrint(self.allocator, "Missing dispatch table '{s}' in generated IR", .{golden_table.table_name}),
                    .suggestion = try std.fmt.allocPrint(self.allocator, "Ensure dispatch table is generated for multiple implementations"),
                });
            }
        }
    }

    /// Compare call pattern analyses
    fn compareCallPatterns(self: *Self, differences: *ArrayList(SemanticDifference), golden: []IRAnalysis.CallPatternAnalysis, generated: []IRAnalysis.CallPatternAnalysis) !void {
        // Check for significant differences in call patterns
        var golden_direct_calls: u32 = 0;
        var golden_indirect_calls: u32 = 0;
        var generated_direct_calls: u32 = 0;
        var generated_indirect_calls: u32 = 0;

        for (golden) |pattern| {
            switch (pattern.call_type) {
                .direct => golden_direct_calls += 1,
                .indirect => golden_indirect_calls += 1,
                else => {},
            }
        }

        for (generated) |pattern| {
            switch (pattern.call_type) {
                .direct => generated_direct_calls += 1,
                .indirect => generated_indirect_calls += 1,
                else => {},
            }
        }

        // Check for significant deviations in call patterns
        if (golden_direct_calls != generated_direct_calls or golden_indirect_calls != generated_indirect_calls) {
            try differences.append(.{
                .difference_type = .call_pattern,
                .severity = .major,
                .location = .{
                    .function_name = try self.allocator.dupe(u8, "global"),
                    .basic_block = null,
                    .instruction_index = null,
                    .line_number = 0,
                },
                .expected = try std.fmt.allocPrint(self.allocator, "direct: {}, indirect: {}", .{ golden_direct_calls, golden_indirect_calls }),
                .actual = try std.fmt.allocPrint(self.allocator, "direct: {}, indirect: {}", .{ generated_direct_calls, generated_indirect_calls }),
                .description = try self.allocator.dupe(u8, "Call pattern distribution differs from golden reference"),
                .suggestion = try self.allocator.dupe(u8, "Review dispatch optimization strategy"),
            });
        }
    }

    /// Compare performance metrics
    fn comparePerformanceMetrics(self: *Self, differences: *ArrayList(SemanticDifference), golden: IRAnalysis.PerformanceMetrics, generated: IRAnalysis.PerformanceMetrics) !void {
        // Check for significant performance regressions
        const instruction_ratio = @as(f64, @floatFromInt(generated.total_instructions)) / @as(f64, @floatFromInt(golden.total_instructions));

        if (instruction_ratio > 1.1) { // More than 10% increase in instructions
            try differences.append(.{
                .difference_type = .performance_regression,
                .severity = .major,
                .location = .{
                    .function_name = try self.allocator.dupe(u8, "global"),
                    .basic_block = null,
                    .instruction_index = null,
                    .line_number = 0,
                },
                .expected = try std.fmt.allocPrint(self.allocator, "{} instructions", .{golden.total_instructions}),
                .actual = try std.fmt.allocPrint(self.allocator, "{} instructions", .{generated.total_instructions}),
                .description = try std.fmt.allocPrint(self.allocator, "Instruction count increased by {d:.1}%", .{(instruction_ratio - 1.0) * 100.0}),
                .suggestion = try self.allocator.dupe(u8, "Review optimization passes and dispatch strategy"),
            });
        }
    }

    /// Validate metadata contracts against generated IR
    fn validateMetadataContracts(self: *Self, violations: *ArrayList(ComparisonResult.ContractViolation), analysis: IRAnalysis, metadata: TestMetadata) !void {
        // Check expected dispatch strategy
        if (metadata.expected_strategy) |expected_strategy| {
            const has_expected_pattern = switch (expected_strategy) {
                .static_dispatch => analysis.dispatch_tables.len == 0 and analysis.performance_metrics.indirect_calls == 0,
                .switch_table => blk: {
                    for (analysis.dispatch_tables) |table| {
                        if (table.table_type == .switch_table) break :blk true;
                    }
                    break :blk false;
                },
                .perfect_hash => blk: {
                    for (analysis.dispatch_tables) |table| {
                        if (table.table_type == .hash_table) break :blk true;
                    }
                    break :blk false;
                },
                else => true, // Other strategies not implemented yet
            };

            if (!has_expected_pattern) {
                try violations.append(.{
                    .violation_type = .dispatch_strategy_mismatch,
                    .description = try std.fmt.allocPrint(self.allocator, "Expected dispatch strategy '{}' not found in generated IR", .{expected_strategy}),
                    .expected_behavior = try std.fmt.allocPrint(self.allocator, "IR should implement {} dispatch pattern", .{expected_strategy}),
                    .actual_behavior = try self.allocator.dupe(u8, "Different or missing dispatch pattern detected"),
                    .metadata_source = try self.allocator.dupe(u8, "@expected-strategy metadata"),
                });
            }
        }

        // Check performance expectations
        for (metadata.performance_expectations) |expectation| {
            const violation_found = switch (expectation.metric) {
                .instruction_count => blk: {
                    const actual_count = @as(f64, @floatFromInt(analysis.performance_metrics.total_instructions));
                    break :blk !self.meetsExpectation(actual_count, expectation);
                },
                .memory_usage_bytes => blk: {
                    const actual_allocs = @as(f64, @floatFromInt(analysis.performance_metrics.memory_allocations));
                    break :blk !self.meetsExpectation(actual_allocs, expectation);
                },
                else => false, // Other metrics not implemented yet
            };

            if (violation_found) {
                try violations.append(.{
                    .violation_type = .performance_regression,
                    .description = try std.fmt.allocPrint(self.allocator, "Performance expectation '{}' not met", .{expectation.metric}),
                    .expected_behavior = try std.fmt.allocPrint(self.allocator, "{} {} {d}", .{ expectation.metric, expectation.operator, expectation.threshold }),
                    .actual_behavior = try self.allocator.dupe(u8, "Performance requirement violated"),
                    .metadata_source = try self.allocator.dupe(u8, "@performance metadata"),
                });
            }
        }
    }

    /// Check if actual value meets performance expectation
    fn meetsExpectation(_: *Self, actual_value: f64, expectation: TestMetadata.PerformanceExpectation) bool {
        const threshold = expectation.threshold;
        const tolerance = expectation.tolerance orelse 0.0;

        return switch (expectation.operator) {
            .less_than => actual_value < threshold * (1.0 + tolerance / 100.0),
            .less_equal => actual_value <= threshold * (1.0 + tolerance / 100.0),
            .greater_than => actual_value > threshold * (1.0 - tolerance / 100.0),
            .greater_equal => actual_value >= threshold * (1.0 - tolerance / 100.0),
            .approximately => @abs(actual_value - threshold) <= threshold * (tolerance / 100.0),
            .within_range => @abs(actual_value - threshold) <= tolerance,
        };
    }
};
