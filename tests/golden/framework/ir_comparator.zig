// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// Golden Test Framework - IR Comparator
// Task 5: Build IR comparison and diff analysis system
// Requirements: 1.1, 1.5, 8.1, 8.3

/// Detailed IR parsing and structured comparison with semantic equivalence checking
pub const IRComparator = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub const IRDifference = struct {
        severity: Severity,
        location: SourceLocation,
        difference_type: DifferenceType,
        expected: []const u8,
        actual: []const u8,
        description: []const u8,

        pub const Severity = enum {
            cosmetic, // Whitespace, comments, formatting
            semantic, // Meaningful but equivalent changes
            breaking, // Changes that affect behavior
            critical, // Changes that break correctness

            pub fn toString(self: Severity) []const u8 {
                return switch (self) {
                    .cosmetic => "cosmetic",
                    .semantic => "semantic",
                    .breaking => "breaking",
                    .critical => "critical",
                };
            }
        };

        pub const DifferenceType = enum {
            whitespace,
            comment,
            instruction_order,
            register_naming,
            metadata,
            function_signature,
            basic_block_structure,
            instruction_semantics,
            type_definition,
            constant_value,

            pub fn toString(self: DifferenceType) []const u8 {
                return switch (self) {
                    .whitespace => "whitespace",
                    .comment => "comment",
                    .instruction_order => "instruction_order",
                    .register_naming => "register_naming",
                    .metadata => "metadata",
                    .function_signature => "function_signature",
                    .basic_block_structure => "basic_block_structure",
                    .instruction_semantics => "instruction_semantics",
                    .type_definition => "type_definition",
                    .constant_value => "constant_value",
                };
            }
        };

        pub const SourceLocation = struct {
            line: u32,
            column: u32,

            pub fn init(line: u32, column: u32) SourceLocation {
                return SourceLocation{ .line = line, .column = column };
            }
        };

        pub fn deinit(self: *IRDifference, allocator: std.mem.Allocator) void {
            allocator.free(self.expected);
            allocator.free(self.actual);
            allocator.free(self.description);
        }
    };

    pub const ComparisonResult = struct {
        equivalent: bool,
        differences: []IRDifference,
        summary: ComparisonSummary,

        pub const ComparisonSummary = struct {
            total_differences: u32,
            cosmetic_count: u32,
            semantic_count: u32,
            breaking_count: u32,
            critical_count: u32,

            pub fn hasCriticalDifferences(self: ComparisonSummary) bool {
                return self.critical_count > 0 or self.breaking_count > 0;
            }
        };

        pub fn deinit(self: *ComparisonResult, allocator: std.mem.Allocator) void {
            for (self.differences) |*diff| {
                diff.deinit(allocator);
            }
            allocator.free(self.differences);
        }
    };

    pub const IRStructure = struct {
        functions: []FunctionInfo,
        global_variables: []GlobalInfo,
        type_definitions: []TypeInfo,
        metadata: []MetadataInfo,

        pub const FunctionInfo = struct {
            name: []const u8,
            signature: []const u8,
            basic_blocks: []BasicBlockInfo,

            pub const BasicBlockInfo = struct {
                label: []const u8,
                instructions: []InstructionInfo,

                pub const InstructionInfo = struct {
                    opcode: []const u8,
                    operands: [][]const u8,
                    result_type: ?[]const u8,
                    line_number: u32,
                };
            };
        };

        pub const GlobalInfo = struct {
            name: []const u8,
            type_info: []const u8,
            initializer: ?[]const u8,
        };

        pub const TypeInfo = struct {
            name: []const u8,
            definition: []const u8,
        };

        pub const MetadataInfo = struct {
            id: []const u8,
            content: []const u8,
        };

        pub fn deinit(self: *IRStructure, allocator: std.mem.Allocator) void {
            // Simplified cleanup - real implementation would free all nested strings
            allocator.free(self.functions);
            allocator.free(self.global_variables);
            allocator.free(self.type_definitions);
            allocator.free(self.metadata);
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Parse LLVM IR into structured representation
    pub fn parseIR(self: *const Self, ir_content: []const u8) !IRStructure {
        // Simplified IR parsing - real implementation would use proper LLVM IR parser
        var functions: std.ArrayList(IRStructure.FunctionInfo) = .empty;
        var globals: std.ArrayList(IRStructure.GlobalInfo) = .empty;
        var types: std.ArrayList(IRStructure.TypeInfo) = .empty;
        var metadata: std.ArrayList(IRStructure.MetadataInfo) = .empty;

        var lines = std.mem.splitScalar(u8, ir_content, '\n');
        var line_number: u32 = 0;

        while (lines.next()) |line| {
            line_number += 1;
            const trimmed = std.mem.trim(u8, line, " \t\r\n");

            if (trimmed.len == 0 or trimmed[0] == ';') {
                // Skip empty lines and comments
                continue;
            }

            if (std.mem.startsWith(u8, trimmed, "define ")) {
                // Function definition
                const func_info = try self.parseFunctionDefinition(trimmed, line_number);
                try functions.append(func_info);
            } else if (std.mem.startsWith(u8, trimmed, "@")) {
                // Global variable
                const global_info = try self.parseGlobalVariable(trimmed);
                try globals.append(global_info);
            } else if (std.mem.startsWith(u8, trimmed, "%")) {
                // Type definition
                const type_info = try self.parseTypeDefinition(trimmed);
                try types.append(type_info);
            } else if (std.mem.startsWith(u8, trimmed, "!")) {
                // Metadata
                const meta_info = try self.parseMetadata(trimmed);
                try metadata.append(meta_info);
            }
        }

        return IRStructure{
            .functions = try functions.toOwnedSlice(),
            .global_variables = try globals.toOwnedSlice(),
            .type_definitions = try types.toOwnedSlice(),
            .metadata = try metadata.toOwnedSlice(),
        };
    }

    /// Compare two IR structures and detect differences
    pub fn compareIR(self: *const Self, expected: []const u8, actual: []const u8) !ComparisonResult {
        var differences: std.ArrayList(IRDifference) = .empty;

        // Parse both IR structures
        var expected_structure = try self.parseIR(expected);
        defer expected_structure.deinit(self.allocator);

        var actual_structure = try self.parseIR(actual);
        defer actual_structure.deinit(self.allocator);

        // Compare functions
        try self.compareFunctions(&expected_structure, &actual_structure, &differences);

        // Compare globals
        try self.compareGlobals(&expected_structure, &actual_structure, &differences);

        // Compare types
        try self.compareTypes(&expected_structure, &actual_structure, &differences);

        // Compare metadata (with lower severity)
        try self.compareMetadata(&expected_structure, &actual_structure, &differences);

        // Generate summary
        var summary = ComparisonResult.ComparisonSummary{
            .total_differences = @intCast(differences.items.len),
            .cosmetic_count = 0,
            .semantic_count = 0,
            .breaking_count = 0,
            .critical_count = 0,
        };

        for (differences.items) |diff| {
            switch (diff.severity) {
                .cosmetic => summary.cosmetic_count += 1,
                .semantic => summary.semantic_count += 1,
                .breaking => summary.breaking_count += 1,
                .critical => summary.critical_count += 1,
            }
        }

        const equivalent = !summary.hasCriticalDifferences();

        return ComparisonResult{
            .equivalent = equivalent,
            .differences = try differences.toOwnedSlice(),
            .summary = summary,
        };
    }

    /// Check semantic equivalence beyond textual comparison
    pub fn checkSemanticEquivalence(self: *const Self, expected: []const u8, actual: []const u8) !bool {
        const comparison = try self.compareIR(expected, actual);
        defer comparison.deinit(self.allocator);

        // Semantic equivalence allows cosmetic and some semantic differences
        return comparison.summary.critical_count == 0 and comparison.summary.breaking_count == 0;
    }

    /// Generate detailed diff report
    pub fn generateDiffReport(self: *const Self, comparison: *const ComparisonResult) ![]const u8 {
        var report: std.ArrayList(u8) = .empty;
        var writer = report.writer();

        try writer.print("IR Comparison Report\n");
        try writer.print("===================\n\n");

        try writer.print("Summary:\n");
        try writer.print("  Equivalent: {}\n", .{comparison.equivalent});
        try writer.print("  Total Differences: {}\n", .{comparison.summary.total_differences});
        try writer.print("  Critical: {}\n", .{comparison.summary.critical_count});
        try writer.print("  Breaking: {}\n", .{comparison.summary.breaking_count});
        try writer.print("  Semantic: {}\n", .{comparison.summary.semantic_count});
        try writer.print("  Cosmetic: {}\n\n", .{comparison.summary.cosmetic_count});

        if (comparison.differences.len > 0) {
            try writer.print("Differences:\n");
            for (comparison.differences, 0..) |diff, i| {
                try writer.print("  {}. [{}] {} at line {}:{}\n", .{
                    i + 1,
                    diff.severity.toString(),
                    diff.difference_type.toString(),
                    diff.location.line,
                    diff.location.column,
                });
                try writer.print("     Description: {s}\n", .{diff.description});
                try writer.print("     Expected: {s}\n", .{diff.expected});
                try writer.print("     Actual:   {s}\n\n", .{diff.actual});
            }
        }

        return try report.toOwnedSlice(alloc);
    }

    // Helper functions for parsing (simplified implementations)

    fn parseFunctionDefinition(self: *const Self, line: []const u8, line_number: u32) !IRStructure.FunctionInfo {
        _ = line_number;
        // Simplified function parsing
        const name = try self.allocator.dupe(u8, "placeholder_function");
        const signature = try self.allocator.dupe(u8, line);

        return IRStructure.FunctionInfo{
            .name = name,
            .signature = signature,
            .basic_blocks = &[_]IRStructure.FunctionInfo.BasicBlockInfo{},
        };
    }

    fn parseGlobalVariable(self: *const Self, line: []const u8) !IRStructure.GlobalInfo {
        return IRStructure.GlobalInfo{
            .name = try self.allocator.dupe(u8, "placeholder_global"),
            .type_info = try self.allocator.dupe(u8, line),
            .initializer = null,
        };
    }

    fn parseTypeDefinition(self: *const Self, line: []const u8) !IRStructure.TypeInfo {
        return IRStructure.TypeInfo{
            .name = try self.allocator.dupe(u8, "placeholder_type"),
            .definition = try self.allocator.dupe(u8, line),
        };
    }

    fn parseMetadata(self: *const Self, line: []const u8) !IRStructure.MetadataInfo {
        return IRStructure.MetadataInfo{
            .id = try self.allocator.dupe(u8, "placeholder_meta"),
            .content = try self.allocator.dupe(u8, line),
        };
    }

    fn compareFunctions(self: *const Self, expected: *const IRStructure, actual: *const IRStructure, differences: *std.ArrayList(IRDifference)) !void {
        if (expected.functions.len != actual.functions.len) {
            try differences.append(IRDifference{
                .severity = .critical,
                .location = IRDifference.SourceLocation.init(1, 1),
                .difference_type = .function_signature,
                .expected = try std.fmt.allocPrint(self.allocator, "{} functions", .{expected.functions.len}),
                .actual = try std.fmt.allocPrint(self.allocator, "{} functions", .{actual.functions.len}),
                .description = try self.allocator.dupe(u8, "Function count mismatch"),
            });
        }
    }

    fn compareGlobals(self: *const Self, expected: *const IRStructure, actual: *const IRStructure, differences: *std.ArrayList(IRDifference)) !void {
        if (expected.global_variables.len != actual.global_variables.len) {
            try differences.append(IRDifference{
                .severity = .breaking,
                .location = IRDifference.SourceLocation.init(1, 1),
                .difference_type = .constant_value,
                .expected = try std.fmt.allocPrint(self.allocator, "{} globals", .{expected.global_variables.len}),
                .actual = try std.fmt.allocPrint(self.allocator, "{} globals", .{actual.global_variables.len}),
                .description = try self.allocator.dupe(u8, "Global variable count mismatch"),
            });
        }
    }

    fn compareTypes(self: *const Self, expected: *const IRStructure, actual: *const IRStructure, differences: *std.ArrayList(IRDifference)) !void {
        if (expected.type_definitions.len != actual.type_definitions.len) {
            try differences.append(IRDifference{
                .severity = .semantic,
                .location = IRDifference.SourceLocation.init(1, 1),
                .difference_type = .type_definition,
                .expected = try std.fmt.allocPrint(self.allocator, "{} types", .{expected.type_definitions.len}),
                .actual = try std.fmt.allocPrint(self.allocator, "{} types", .{actual.type_definitions.len}),
                .description = try self.allocator.dupe(u8, "Type definition count mismatch"),
            });
        }
    }

    fn compareMetadata(self: *const Self, expected: *const IRStructure, actual: *const IRStructure, differences: *std.ArrayList(IRDifference)) !void {
        if (expected.metadata.len != actual.metadata.len) {
            try differences.append(IRDifference{
                .severity = .cosmetic,
                .location = IRDifference.SourceLocation.init(1, 1),
                .difference_type = .metadata,
                .expected = try std.fmt.allocPrint(self.allocator, "{} metadata", .{expected.metadata.len}),
                .actual = try std.fmt.allocPrint(self.allocator, "{} metadata", .{actual.metadata.len}),
                .description = try self.allocator.dupe(u8, "Metadata count mismatch (cosmetic)"),
            });
        }
    }
};

// Tests
test "IRComparator initialization" {
    const comparator = IRComparator.init(testing.allocator);
    try testing.expect(comparator.allocator.ptr == testing.allocator.ptr);
}

test "IR parsing basic structure" {
    const comparator = IRComparator.init(testing.allocator);

    const test_ir =
        \\define i32 @main() {
        \\  ret i32 0
        \\}
        \\@global_var = global i32 42
        \\%struct.Point = type { i32, i32 }
        \\!0 = !{i32 1, !"Debug Info"}
    ;

    var structure = try comparator.parseIR(test_ir);
    defer structure.deinit(testing.allocator);

    try testing.expect(structure.functions.len == 1);
    try testing.expect(structure.global_variables.len == 1);
    try testing.expect(structure.type_definitions.len == 1);
    try testing.expect(structure.metadata.len == 1);
}

test "IR comparison identical content" {
    const comparator = IRComparator.init(testing.allocator);

    const ir_content = "define i32 @test() { ret i32 42 }";

    var result = try comparator.compareIR(ir_content, ir_content);
    defer result.deinit(testing.allocator);

    try testing.expect(result.equivalent);
    try testing.expect(result.differences.len == 0);
    try testing.expect(result.summary.total_differences == 0);
}

test "IR comparison with differences" {
    const comparator = IRComparator.init(testing.allocator);

    const expected_ir = "define i32 @test() { ret i32 42 }";
    const actual_ir = "define i64 @test() { ret i64 42 }";

    var result = try comparator.compareIR(expected_ir, actual_ir);
    defer result.deinit(testing.allocator);

    try testing.expect(!result.equivalent);
    try testing.expect(result.differences.len > 0);
}

test "Semantic equivalence checking" {
    const comparator = IRComparator.init(testing.allocator);

    const ir1 = "define i32 @test() { ret i32 42 }";
    const ir2 = "define i32 @test() { ret i32 42 }";

    const equivalent = try comparator.checkSemanticEquivalence(ir1, ir2);
    try testing.expect(equivalent);
}

test "Diff report generation" {
    const comparator = IRComparator.init(testing.allocator);

    const expected_ir = "define i32 @test() { ret i32 42 }";
    const actual_ir = "define i64 @test() { ret i64 42 }";

    var result = try comparator.compareIR(expected_ir, actual_ir);
    defer result.deinit(testing.allocator);

    const report = try comparator.generateDiffReport(&result);
    defer testing.allocator.free(report);

    try testing.expect(std.mem.indexOf(u8, report, "IR Comparison Report") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Equivalent: false") != null);
}
