// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Golden Test Framework Error Registry
/// Provides structured error codes and messages for golden test failures
/// Enables forensic-level debugging and clear failure reporting
pub const ErrorRegistry = struct {
    /// Golden Test Error Codes (G1xxx series)
    pub const ErrorCode = enum(u16) {
        // IR Generation Errors (G1000-G1099)
        G1001_IR_GENERATION_FAILED = 1001,
        G1002_GOLDEN_REFERENCE_MISSING = 1002,
        G1003_PLATFORM_NOT_SUPPORTED = 1003,
        G1004_OPTIMIZATION_LEVEL_INVALID = 1004,
        G1005_COMPILATION_TIMEOUT = 1005,

        // Semantic Comparison Errors (G1100-G1199)
        G1101_FUNCTION_SIGNATURE_MISMATCH = 1101,
        G1102_INSTRUCTION_SEQUENCE_DIFFERS = 1102,
        G1103_DISPATCH_TABLE_MISSING = 1103,
        G1104_CALL_PATTERN_INCORRECT = 1104,
        G1105_TYPE_COERCION_MISSING = 1105,
        G1106_OPTIMIZATION_ANNOTATION_WRONG = 1106,

        // Performance Contract Violations (G1200-G1299)
        G1201_DISPATCH_OVERHEAD_EXCEEDED = 1201,
        G1202_MEMORY_USAGE_EXCEEDED = 1202,
        G1203_INSTRUCTION_COUNT_EXCEEDED = 1203,
        G1204_CACHE_HIT_RATIO_LOW = 1204,
        G1205_PERFORMANCE_REGRESSION = 1205,

        // Metadata Contract Violations (G1300-G1399)
        G1301_DISPATCH_STRATEGY_MISMATCH = 1301,
        G1302_PLATFORM_REQUIREMENT_UNMET = 1302,
        G1303_VALIDATION_RULE_FAILED = 1303,
        G1304_QUALITY_GATE_FAILED = 1304,
        G1305_DEPENDENCY_MISSING = 1305,

        // Framework Errors (G1400-G1499)
        G1401_METADATA_PARSE_ERROR = 1401,
        G1402_TEST_CASE_INVALID = 1402,
        G1403_GOLDEN_MATRIX_CORRUPTED = 1403,
        G1404_FRAMEWORK_INTERNAL_ERROR = 1404,
        G1405_CONFIGURATION_ERROR = 1405,

        pub fn toString(self: ErrorCode) []const u8 {
            return switch (self) {
                .G1001_IR_GENERATION_FAILED => "G1001",
                .G1002_GOLDEN_REFERENCE_MISSING => "G1002",
                .G1003_PLATFORM_NOT_SUPPORTED => "G1003",
                .G1004_OPTIMIZATION_LEVEL_INVALID => "G1004",
                .G1005_COMPILATION_TIMEOUT => "G1005",
                .G1101_FUNCTION_SIGNATURE_MISMATCH => "G1101",
                .G1102_INSTRUCTION_SEQUENCE_DIFFERS => "G1102",
                .G1103_DISPATCH_TABLE_MISSING => "G1103",
                .G1104_CALL_PATTERN_INCORRECT => "G1104",
                .G1105_TYPE_COERCION_MISSING => "G1105",
                .G1106_OPTIMIZATION_ANNOTATION_WRONG => "G1106",
                .G1201_DISPATCH_OVERHEAD_EXCEEDED => "G1201",
                .G1202_MEMORY_USAGE_EXCEEDED => "G1202",
                .G1203_INSTRUCTION_COUNT_EXCEEDED => "G1203",
                .G1204_CACHE_HIT_RATIO_LOW => "G1204",
                .G1205_PERFORMANCE_REGRESSION => "G1205",
                .G1301_DISPATCH_STRATEGY_MISMATCH => "G1301",
                .G1302_PLATFORM_REQUIREMENT_UNMET => "G1302",
                .G1303_VALIDATION_RULE_FAILED => "G1303",
                .G1304_QUALITY_GATE_FAILED => "G1304",
                .G1305_DEPENDENCY_MISSING => "G1305",
                .G1401_METADATA_PARSE_ERROR => "G1401",
                .G1402_TEST_CASE_INVALID => "G1402",
                .G1403_GOLDEN_MATRIX_CORRUPTED => "G1403",
                .G1404_FRAMEWORK_INTERNAL_ERROR => "G1404",
                .G1405_CONFIGURATION_ERROR => "G1405",
            };
        }
    };

    /// Structured error information
    pub const ErrorInfo = struct {
        code: ErrorCode,
        title: []const u8,
        description: []const u8,
        category: ErrorCategory,
        severity: ErrorSeverity,
        suggested_actions: [][]const u8,
        documentation_link: ?[]const u8,

        pub const ErrorCategory = enum {
            ir_generation,
            semantic_comparison,
            performance_contract,
            metadata_contract,
            framework_internal,
        };

        pub const ErrorSeverity = enum {
            critical, // Test failure, build should fail
            major, // Significant issue, requires attention
            minor, // Warning, may indicate problem
            info, // Informational, no action required
        };
    };

    /// Detailed failure report
    pub const FailureReport = struct {
        error_code: ErrorCode,
        test_case: []const u8,
        platform: []const u8,
        optimization_level: []const u8,
        timestamp: i64,
        error_message: []const u8,
        context: FailureContext,
        forensic_data: ForensicData,

        pub const FailureContext = struct {
            golden_reference_path: ?[]const u8,
            generated_ir_path: ?[]const u8,
            metadata_source: ?[]const u8,
            compiler_version: ?[]const u8,
            environment_info: ?[]const u8,
        };

        pub const ForensicData = struct {
            ir_diff_summary: ?[]const u8,
            performance_metrics: ?[]const u8,
            contract_violations: ?[]const u8,
            stack_trace: ?[]const u8,
            debug_artifacts: ?[]const u8,
        };

        pub fn deinit(self: *FailureReport, allocator: Allocator) void {
            allocator.free(self.test_case);
            allocator.free(self.platform);
            allocator.free(self.optimization_level);
            allocator.free(self.error_message);

            if (self.context.servicelden_reference_path) |path| allocator.free(path);
            if (self.context.generated_ir_path) |path| allocator.free(path);
            if (self.context.metadata_source) |source| allocator.free(source);
            if (self.context.compiler_version) |version| allocator.free(version);
            if (self.context.environment_info) |info| allocator.free(info);

            if (self.forensic_data.ir_diff_summary) |summary| allocator.free(summary);
            if (self.forensic_data.performance_metrics) |metrics| allocator.free(metrics);
            if (self.forensic_data.contract_violations) |violations| allocator.free(violations);
            if (self.forensic_data.stack_trace) |trace| allocator.free(trace);
            if (self.forensic_data.debug_artifacts) |artifacts| allocator.free(artifacts);
        }
    };

    allocator: Allocator,
    error_database: std.HashMap(ErrorCode, ErrorInfo, std.hash_map.AutoContext(ErrorCode), std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var registry = Self{
            .allocator = allocator,
            .error_database = std.HashMap(ErrorCode, ErrorInfo, std.hash_map.AutoContext(ErrorCode), std.hash_map.default_max_load_percentage).init(allocator),
        };

        try registry.populateErrorDatabase();
        return registry;
    }

    pub fn deinit(self: *Self) void {
        self.error_database.deinit();
    }

    /// Get error information for a specific error code
    pub fn getErrorInfo(self: *Self, code: ErrorCode) ?ErrorInfo {
        return self.error_database.get(code);
    }

    /// Create a detailed failure report
    pub fn createFailureReport(
        self: *Self,
        error_code: ErrorCode,
        test_case: []const u8,
        platform: []const u8,
        optimization_level: []const u8,
        error_message: []const u8,
        context: FailureReport.FailureContext,
        forensic_data: FailureReport.ForensicData,
    ) !FailureReport {
        return FailureReport{
            .error_code = error_code,
            .test_case = try self.allocator.dupe(u8, test_case),
            .platform = try self.allocator.dupe(u8, platform),
            .optimization_level = try self.allocator.dupe(u8, optimization_level),
            .timestamp = std.time.timestamp(),
            .error_message = try self.allocator.dupe(u8, error_message),
            .context = .{
                .servicelden_reference_path = if (context.servicelden_reference_path) |path| try self.allocator.dupe(u8, path) else null,
                .generated_ir_path = if (context.generated_ir_path) |path| try self.allocator.dupe(u8, path) else null,
                .metadata_source = if (context.metadata_source) |source| try self.allocator.dupe(u8, source) else null,
                .compiler_version = if (context.compiler_version) |version| try self.allocator.dupe(u8, version) else null,
                .environment_info = if (context.environment_info) |info| try self.allocator.dupe(u8, info) else null,
            },
            .forensic_data = .{
                .ir_diff_summary = if (forensic_data.ir_diff_summary) |summary| try self.allocator.dupe(u8, summary) else null,
                .performance_metrics = if (forensic_data.performance_metrics) |metrics| try self.allocator.dupe(u8, metrics) else null,
                .contract_violations = if (forensic_data.contract_violations) |violations| try self.allocator.dupe(u8, violations) else null,
                .stack_trace = if (forensic_data.stack_trace) |trace| try self.allocator.dupe(u8, trace) else null,
                .debug_artifacts = if (forensic_data.debug_artifacts) |artifacts| try self.allocator.dupe(u8, artifacts) else null,
            },
        };
    }

    /// Format failure report as human-readable text
    pub fn formatFailureReport(self: *Self, report: FailureReport) ![]u8 {
        const error_info = self.getErrorInfo(report.error_code) orelse return error.UnknownErrorCode;

        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit();

        const writer = buffer.writer();

        // Header
        try writer.print("🚨 GOLDEN TEST FAILURE REPORT\n");
        try writer.print("═══════════════════════════════════════════════════════════════\n\n");

        // Error summary
        try writer.print("ERROR: {} - {s}\n", .{ report.error_code.toString(), error_info.title });
        try writer.print("SEVERITY: {}\n", .{error_info.severity});
        try writer.print("CATEGORY: {}\n", .{error_info.category});
        try writer.print("TIMESTAMP: {}\n\n", .{report.timestamp});

        // Test context
        try writer.print("TEST CONTEXT:\n");
        try writer.print("  Test Case: {s}\n", .{report.test_case});
        try writer.print("  Platform: {s}\n", .{report.platform});
        try writer.print("  Optimization: {s}\n", .{report.optimization_level});

        if (report.context.compiler_version) |version| {
            try writer.print("  Compiler Version: {s}\n", .{version});
        }

        if (report.context.environment_info) |info| {
            try writer.print("  Environment: {s}\n", .{info});
        }
        try writer.print("\n");

        // Error description
        try writer.print("DESCRIPTION:\n");
        try writer.print("{s}\n\n", .{error_info.description});

        // Error message
        try writer.print("ERROR MESSAGE:\n");
        try writer.print("{s}\n\n", .{report.error_message});

        // Forensic data
        if (report.forensic_data.ir_diff_summary) |summary| {
            try writer.print("IR DIFF SUMMARY:\n");
            try writer.print("{s}\n\n", .{summary});
        }

        if (report.forensic_data.performance_metrics) |metrics| {
            try writer.print("PERFORMANCE METRICS:\n");
            try writer.print("{s}\n\n", .{metrics});
        }

        if (report.forensic_data.contract_violations) |violations| {
            try writer.print("CONTRACT VIOLATIONS:\n");
            try writer.print("{s}\n\n", .{violations});
        }

        // File paths
        if (report.context.servicelden_reference_path) |path| {
            try writer.print("GOLDEN REFERENCE: {s}\n", .{path});
        }

        if (report.context.generated_ir_path) |path| {
            try writer.print("GENERATED IR: {s}\n", .{path});
        }

        if (report.context.metadata_source) |source| {
            try writer.print("METADATA SOURCE: {s}\n", .{source});
        }
        try writer.print("\n");

        // Suggested actions
        try writer.print("SUGGESTED ACTIONS:\n");
        for (error_info.suggested_actions) |action| {
            try writer.print("  • {s}\n", .{action});
        }

        if (error_info.documentation_link) |link| {
            try writer.print("\nDOCUMENTATION: {s}\n", .{link});
        }

        // Debug information
        if (report.forensic_data.stack_trace) |trace| {
            try writer.print("\nSTACK TRACE:\n");
            try writer.print("{s}\n", .{trace});
        }

        if (report.forensic_data.debug_artifacts) |artifacts| {
            try writer.print("\nDEBUG ARTIFACTS:\n");
            try writer.print("{s}\n", .{artifacts});
        }

        try writer.print("\n═══════════════════════════════════════════════════════════════\n");
        try writer.print("Golden Test Framework - Forensic Failure Analysis\n");

        return try buffer.toOwnedSlice(alloc);
    }

    /// Populate the error database with all known errors
    fn populateErrorDatabase(self: *Self) !void {
        // IR Generation Errors
        try self.error_database.put(.G1001_IR_GENERATION_FAILED, .{
            .code = .G1001_IR_GENERATION_FAILED,
            .title = "IR Generation Failed",
            .description = "The compiler failed to generate LLVM IR for the test case. This indicates a fundamental compilation error that prevents golden test validation.",
            .category = .ir_generation,
            .severity = .critical,
            .suggested_actions = &.{
                "Check compiler error messages for syntax or semantic errors",
                "Verify test case is valid Janus code",
                "Ensure all dependencies are available",
                "Check compiler installation and configuration",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#ir-generation-failures",
        });

        try self.error_database.put(.G1002_GOLDEN_REFERENCE_MISSING, .{
            .code = .G1002_GOLDEN_REFERENCE_MISSING,
            .title = "Golden Reference Missing",
            .description = "The golden reference IR file for this test case and platform combination does not exist. Golden tests require canonical reference files to validate against.",
            .category = .ir_generation,
            .severity = .critical,
            .suggested_actions = &.{
                "Generate golden reference using approved compiler version",
                "Verify platform and optimization level are supported",
                "Check golden reference file path and naming convention",
                "Update Golden IR Test Matrix if new test case",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#golden-references",
        });

        // Semantic Comparison Errors
        try self.error_database.put(.G1101_FUNCTION_SIGNATURE_MISMATCH, .{
            .code = .G1101_FUNCTION_SIGNATURE_MISMATCH,
            .title = "Function Signature Mismatch",
            .description = "Generated IR contains function signatures that differ from the golden reference. This indicates changes in function generation, parameter handling, or return types.",
            .category = .semantic_comparison,
            .severity = .major,
            .suggested_actions = &.{
                "Compare function signatures in detail",
                "Check for changes in type system or ABI",
                "Verify parameter passing conventions",
                "Review function attribute generation",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#function-signatures",
        });

        try self.error_database.put(.G1103_DISPATCH_TABLE_MISSING, .{
            .code = .G1103_DISPATCH_TABLE_MISSING,
            .title = "Dispatch Table Missing",
            .description = "Expected dispatch table not found in generated IR. This indicates the multiple dispatch optimization failed to generate the required dispatch infrastructure.",
            .category = .semantic_comparison,
            .severity = .critical,
            .suggested_actions = &.{
                "Check multiple dispatch implementation detection",
                "Verify dispatch strategy selection logic",
                "Review optimization pass ordering",
                "Ensure multiple implementations are properly detected",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#dispatch-tables",
        });

        // Performance Contract Violations
        try self.error_database.put(.G1201_DISPATCH_OVERHEAD_EXCEEDED, .{
            .code = .G1201_DISPATCH_OVERHEAD_EXCEEDED,
            .title = "Dispatch Overhead Exceeded",
            .description = "The measured dispatch overhead exceeds the performance contract specified in the test metadata. This indicates a performance regression in the dispatch optimization.",
            .category = .performance_contract,
            .severity = .major,
            .suggested_actions = &.{
                "Profile dispatch performance in detail",
                "Check for optimization pass regressions",
                "Review dispatch strategy selection",
                "Analyze instruction count and call patterns",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#performance-contracts",
        });

        try self.error_database.put(.G1203_INSTRUCTION_COUNT_EXCEEDED, .{
            .code = .G1203_INSTRUCTION_COUNT_EXCEEDED,
            .title = "Instruction Count Exceeded",
            .description = "Generated IR contains more instructions than allowed by the performance contract. This may indicate optimization failures or code generation regressions.",
            .category = .performance_contract,
            .severity = .major,
            .suggested_actions = &.{
                "Analyze instruction count differences",
                "Check optimization pass effectiveness",
                "Review code generation patterns",
                "Compare with previous compiler versions",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#instruction-count",
        });

        // Metadata Contract Violations
        try self.error_database.put(.G1301_DISPATCH_STRATEGY_MISMATCH, .{
            .code = .G1301_DISPATCH_STRATEGY_MISMATCH,
            .title = "Dispatch Strategy Mismatch",
            .description = "The generated IR does not implement the expected dispatch strategy specified in the test metadata. This indicates the dispatch optimizer selected a different strategy than expected.",
            .category = .metadata_contract,
            .severity = .major,
            .suggested_actions = &.{
                "Review dispatch strategy selection logic",
                "Check implementation count and complexity",
                "Verify optimization heuristics",
                "Update metadata if strategy change is intentional",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#dispatch-strategies",
        });

        try self.error_database.put(.G1303_VALIDATION_RULE_FAILED, .{
            .code = .G1303_VALIDATION_RULE_FAILED,
            .title = "Validation Rule Failed",
            .description = "A custom validation rule specified in the test metadata failed when applied to the generated IR. This indicates the IR does not meet the specific requirements for this test case.",
            .category = .metadata_contract,
            .severity = .major,
            .suggested_actions = &.{
                "Review failed validation rule logic",
                "Check IR structure against rule requirements",
                "Verify rule implementation is correct",
                "Update rule if requirements have changed",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#validation-rules",
        });

        // Framework Errors
        try self.error_database.put(.G1401_METADATA_PARSE_ERROR, .{
            .code = .G1401_METADATA_PARSE_ERROR,
            .title = "Metadata Parse Error",
            .description = "Failed to parse test metadata from the test case file. This indicates malformed or invalid metadata annotations in the test case.",
            .category = .framework_internal,
            .severity = .critical,
            .suggested_actions = &.{
                "Check metadata syntax in test case file",
                "Verify all required metadata fields are present",
                "Review metadata parser implementation",
                "Validate metadata against schema",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#metadata-format",
        });

        try self.error_database.put(.G1403_GOLDEN_MATRIX_CORRUPTED, .{
            .code = .G1403_GOLDEN_MATRIX_CORRUPTED,
            .title = "Golden Matrix Corrupted",
            .description = "The Golden IR Test Matrix appears to be corrupted or inconsistent. This indicates potential file system issues or unauthorized modifications to golden references.",
            .category = .framework_internal,
            .severity = .critical,
            .suggested_actions = &.{
                "Verify golden reference file integrity",
                "Check file system permissions and health",
                "Restore from backup if available",
                "Regenerate golden references if necessary",
            },
            .documentation_link = "https://janus-lang.org/docs/golden-tests#matrix-integrity",
        });
    }
};
