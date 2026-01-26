// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Semantic Error Management System
//!
//! This module provides sophisticated error recovery strategies, error suppression to prevent cascading errors, and comprehensive diagnostic generation with
//! actionable suggestions for developers.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;

const source_span_utils = @import("source_span_utils.zig");
const SourceSpan = source_span_utils.SourceSpan;
const AstNode = source_span_utils.AstNode;

/// Error severity levels
pub const ErrorSeverity = enum {
    @"error", // Compilation-stopping error
    warning, // Potential issue, compilation continues
    info, // Informational message
    hint, // Optimization or style suggestion

    pub fn toString(self: ErrorSeverity) []const u8 {
        return switch (self) {
            .@"error" => "error",
            .warning => "warning",
            .info => "info",
            .hint => "hint",
        };
    }
};

/// Error categories for better organization
pub const ErrorCategory = enum {
    syntax,
    semantic,
    type_system,
    visibility,
    profile,
    performance,
    style,
};

/// Inference context - describes WHERE the type mismatch occurred
pub const InferenceContext = enum {
    /// Variable/let declaration with type annotation
    assignment,
    /// Function call argument
    argument,
    /// Return statement vs function signature
    return_value,
    /// Binary operator operands
    binary_op,
    /// Unary operator operand
    unary_op,
    /// Array/slice indexing
    index_access,
    /// Struct field access
    field_access,
    /// Condition in if/while/match
    condition,
    /// Array literal element type mismatch
    array_element,
    /// Match arm result type
    match_arm,
    /// Generic constraint violation
    generic_constraint,
    /// Unknown/general context
    unknown,

    pub fn toString(self: InferenceContext) []const u8 {
        return switch (self) {
            .assignment => "variable assignment",
            .argument => "function argument",
            .return_value => "return statement",
            .binary_op => "binary operation",
            .unary_op => "unary operation",
            .index_access => "index access",
            .field_access => "field access",
            .condition => "condition expression",
            .array_element => "array element",
            .match_arm => "match arm",
            .generic_constraint => "generic constraint",
            .unknown => "expression",
        };
    }

    pub fn getErrorCode(self: InferenceContext) []const u8 {
        return switch (self) {
            .assignment => "E3001",
            .argument => "E3002",
            .return_value => "E3003",
            .binary_op => "E3004",
            .unary_op => "E3005",
            .index_access => "E3006",
            .field_access => "E3007",
            .condition => "E3008",
            .array_element => "E3009",
            .match_arm => "E3010",
            .generic_constraint => "E3011",
            .unknown => "E3000",
        };
    }
};

/// Diagnostic suggestion with confidence level
pub const DiagnosticSuggestion = struct {
    message: []const u8,
    replacement_span: ?SourceSpan,
    replacement_text: ?[]const u8,
    confidence: f32, // 0.0 to 1.0

    pub fn deinit(self: *DiagnosticSuggestion, allocator: Allocator) void {
        allocator.free(self.message);
        if (self.replacement_text) |text| {
            allocator.free(text);
        }
    }
};

/// Comprehensive diagnostic information
pub const Diagnostic = struct {
    severity: ErrorSeverity,
    category: ErrorCategory,
    code: []const u8,
    message: []const u8,
    primary_span: SourceSpan,
    secondary_spans: []SourceSpan,
    suggestions: []DiagnosticSuggestion,
    notes: [][]const u8,

    pub fn deinit(self: *Diagnostic, allocator: Allocator) void {
        allocator.free(self.code);
        allocator.free(self.message);
        allocator.free(self.secondary_spans);
        for (self.suggestions) |*suggestion| {
            suggestion.deinit(allocator);
        }
        allocator.free(self.suggestions);
        for (self.notes) |note| {
            allocator.free(note);
        }
        allocator.free(self.notes);
    }
};

/// Comprehensive error manager
pub const ErrorManager = struct {
    allocator: Allocator,
    diagnostics: ArrayList(Diagnostic),
    max_errors: usize,
    error_count: usize,

    pub fn init(allocator: Allocator) ErrorManager {
        return ErrorManager{
            .allocator = allocator,
            .diagnostics = ArrayList(Diagnostic).init(allocator),
            .max_errors = 100, // Stop after 100 errors
            .error_count = 0,
        };
    }

    pub fn deinit(self: *ErrorManager) void {
        for (self.diagnostics.items) |*diagnostic| {
            diagnostic.deinit(self.allocator);
        }
        self.diagnostics.deinit();
    }

    /// Add a diagnostic
    pub fn addDiagnostic(self: *ErrorManager, diagnostic: Diagnostic) !bool {
        if (diagnostic.severity == .@"error") {
            self.error_count += 1;
            if (self.error_count > self.max_errors) {
                return false;
            }
        }

        try self.diagnostics.append(diagnostic);
        return true;
    }

    pub fn reportError(
        self: *ErrorManager,
        category: ErrorCategory,
        code: []const u8,
        message: []const u8,
        span: SourceSpan,
    ) !bool {
        const diagnostic = Diagnostic{
            .severity = .@"error",
            .category = category,
            .code = try self.allocator.dupe(u8, code),
            .message = try self.allocator.dupe(u8, message),
            .primary_span = span,
            .secondary_spans = &.{},
            .suggestions = &.{},
            .notes = &.{},
        };
        return self.addDiagnostic(diagnostic);
    }

    pub fn reportWarning(
        self: *ErrorManager,
        category: ErrorCategory,
        code: []const u8,
        message: []const u8,
        span: SourceSpan,
    ) !bool {
        const diagnostic = Diagnostic{
            .severity = .warning,
            .category = category,
            .code = try self.allocator.dupe(u8, code),
            .message = try self.allocator.dupe(u8, message),
            .primary_span = span,
            .secondary_spans = &.{},
            .suggestions = &.{},
            .notes = &.{},
        };
        return self.addDiagnostic(diagnostic);
    }

    pub fn reportUndefinedSymbol(
        self: *ErrorManager,
        symbol_name: []const u8,
        span: SourceSpan,
        suggestions: []const []const u8,
    ) !bool {
        var diagnostic_suggestions = ArrayList(DiagnosticSuggestion).init(self.allocator);
        defer diagnostic_suggestions.deinit();

        for (suggestions) |suggestion| {
            try diagnostic_suggestions.append(.{
                .message = try std.fmt.allocPrint(self.allocator, "Did you mean '{s}'?", .{suggestion}),
                .replacement_span = span,
                .replacement_text = try self.allocator.dupe(u8, suggestion),
                .confidence = 0.8,
            });
        }

        const diagnostic = Diagnostic{
            .severity = .@"error",
            .category = .semantic,
            .code = try self.allocator.dupe(u8, "E001"),
            .message = try std.fmt.allocPrint(self.allocator, "Undefined symbol '{s}'", .{symbol_name}),
            .primary_span = span,
            .secondary_spans = &.{},
            .suggestions = try diagnostic_suggestions.toOwnedSlice(),
            .notes = &.{},
        };
        return self.addDiagnostic(diagnostic);
    }

    pub fn reportTypeMismatch(
        self: *ErrorManager,
        expected_type: []const u8,
        actual_type: []const u8,
        span: SourceSpan,
    ) !bool {
        // Delegate to context-aware version with unknown context
        return self.reportTypeMismatchWithContext(
            expected_type,
            actual_type,
            span,
            null,
            .unknown,
            null,
        );
    }

    /// Report type mismatch with full context information
    /// - context: WHERE the mismatch occurred (assignment, argument, return, etc.)
    /// - declaration_span: Optional span pointing to WHY the expected type was required
    /// - extra_note: Optional additional note (e.g., "argument 2 of function `foo`")
    pub fn reportTypeMismatchWithContext(
        self: *ErrorManager,
        expected_type: []const u8,
        actual_type: []const u8,
        primary_span: SourceSpan,
        declaration_span: ?SourceSpan,
        context: InferenceContext,
        extra_note: ?[]const u8,
    ) !bool {
        var secondary_spans = ArrayList(SourceSpan).init(self.allocator);
        defer secondary_spans.deinit();

        var notes = ArrayList([]const u8).init(self.allocator);
        defer notes.deinit();

        var suggestions = ArrayList(DiagnosticSuggestion).init(self.allocator);
        defer suggestions.deinit();

        // Add declaration span if provided
        if (declaration_span) |decl_span| {
            try secondary_spans.append(decl_span);
        }

        // Build context-aware message
        const message = try std.fmt.allocPrint(
            self.allocator,
            "Type mismatch in {s}: expected `{s}`, found `{s}`",
            .{ context.toString(), expected_type, actual_type },
        );

        // Add extra note if provided
        if (extra_note) |note| {
            try notes.append(try self.allocator.dupe(u8, note));
        }

        // Generate cast suggestions based on types
        if (try self.generateCastSuggestion(expected_type, actual_type)) |suggestion| {
            try suggestions.append(suggestion);
        }

        const diagnostic = Diagnostic{
            .severity = .@"error",
            .category = .type_system,
            .code = try self.allocator.dupe(u8, context.getErrorCode()),
            .message = message,
            .primary_span = primary_span,
            .secondary_spans = try secondary_spans.toOwnedSlice(),
            .suggestions = try suggestions.toOwnedSlice(),
            .notes = try notes.toOwnedSlice(),
        };
        return self.addDiagnostic(diagnostic);
    }

    /// Generate cast suggestion based on type pair
    fn generateCastSuggestion(
        self: *ErrorManager,
        expected_type: []const u8,
        actual_type: []const u8,
    ) !?DiagnosticSuggestion {
        // Integer widening: i32 -> i64
        if (isIntegerType(actual_type) and isIntegerType(expected_type)) {
            if (getIntegerWidth(actual_type) < getIntegerWidth(expected_type)) {
                return DiagnosticSuggestion{
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Consider widening with `as {s}` or `@intCast(value)`",
                        .{expected_type},
                    ),
                    .replacement_span = null,
                    .replacement_text = null,
                    .confidence = 0.9,
                };
            } else {
                // Narrowing - warn about potential truncation
                return DiagnosticSuggestion{
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Narrowing from `{s}` to `{s}` may truncate. Use `@truncate(value)` if intentional.",
                        .{ actual_type, expected_type },
                    ),
                    .replacement_span = null,
                    .replacement_text = null,
                    .confidence = 0.7,
                };
            }
        }

        // Float to int
        if (isFloatType(actual_type) and isIntegerType(expected_type)) {
            return DiagnosticSuggestion{
                .message = try self.allocator.dupe(u8, "Use `@floatToInt(value)` to convert. Note: this will truncate the fractional part."),
                .replacement_span = null,
                .replacement_text = null,
                .confidence = 0.8,
            };
        }

        // Int to float
        if (isIntegerType(actual_type) and isFloatType(expected_type)) {
            return DiagnosticSuggestion{
                .message = try self.allocator.dupe(u8, "Use `@intToFloat(value)` to convert."),
                .replacement_span = null,
                .replacement_text = null,
                .confidence = 0.9,
            };
        }

        return null;
    }

    pub fn reportInitializationError(
        self: *ErrorManager,
        variable_name: []const u8,
        usage_span: SourceSpan,
        declaration_span: ?SourceSpan,
    ) !bool {
        var secondary_spans = ArrayList(SourceSpan).init(self.allocator);
        defer secondary_spans.deinit();

        if (declaration_span) |decl_span| {
            try secondary_spans.append(decl_span);
        }

        const diagnostic = Diagnostic{
            .severity = .@"error",
            .category = .semantic,
            .code = try self.allocator.dupe(u8, "E003"),
            .message = try std.fmt.allocPrint(self.allocator, "Variable '{s}' used before initialization", .{variable_name}),
            .primary_span = usage_span,
            .secondary_spans = try secondary_spans.toOwnedSlice(),
            .suggestions = &.{},
            .notes = &.{},
        };
        return self.addDiagnostic(diagnostic);
    }

    /// Generate symbol suggestions using Levenshtein distance
    pub fn generateSymbolSuggestions(
        self: *ErrorManager,
        target: []const u8,
        available_symbols: []const []const u8,
        max_suggestions: usize,
    ) ![][]const u8 {
        const SuggestionCandidate = struct {
            symbol: []const u8,
            distance: usize,

            fn lessThan(_: void, a: @This(), b: @This()) bool {
                return a.distance < b.distance;
            }
        };

        var suggestions = ArrayList(SuggestionCandidate).init(self.allocator);
        defer suggestions.deinit();

        for (available_symbols) |symbol| {
            const distance = levenshteinDistance(target, symbol);
            const max_distance = @max(target.len, symbol.len) / 2;
            if (distance <= max_distance) {
                try suggestions.append(.{ .symbol = symbol, .distance = distance });
            }
        }

        std.sort.insertion(SuggestionCandidate, suggestions.items, {}, SuggestionCandidate.lessThan);

        var result = ArrayList([]const u8).init(self.allocator);
        const count = @min(suggestions.items.len, max_suggestions);
        for (suggestions.items[0..count]) |candidate| {
            try result.append(try self.allocator.dupe(u8, candidate.symbol));
        }

        return result.toOwnedSlice();
    }

    /// Format diagnostic with source context
    pub fn formatDiagnostic(self: *ErrorManager, diagnostic: *const Diagnostic, source_text: []const u8) ![]const u8 {
        var output = ArrayList(u8).init(self.allocator);
        const writer = output.writer();

        // Write diagnostic header
        try writer.print("{s}: {s}\n", .{ @tagName(diagnostic.severity), diagnostic.message });

        // Write location
        try writer.print("  --> {s}:{}:{}\n", .{
            diagnostic.primary_span.file_path,
            diagnostic.primary_span.start.line,
            diagnostic.primary_span.start.column,
        });

        // Write source context if available
        if (getSourceLine(source_text, diagnostic.primary_span.start.line)) |line| {
            try writer.print("   |\n");
            try writer.print("{:3} | {s}\n", .{ diagnostic.primary_span.start.line, line });
            try formatDiagnosticHelper(diagnostic, writer);
        }

        return output.toOwnedSlice();
    }

    /// Get statistics for all diagnostics
    pub fn getStatistics(self: *ErrorManager) DiagnosticStatistics {
        var stats: DiagnosticStatistics = .{};
        for (self.diagnostics.items) |diagnostic| {
            switch (diagnostic.severity) {
                .@"error" => stats.error_count += 1,
                .warning => stats.warning_count += 1,
                .info => stats.info_count += 1,
                .hint => stats.hint_count += 1,
            }
        }
        return stats;
    }

    fn getSourceLine(source_text: []const u8, line_number: u32) ?[]const u8 {
        var current_line: u32 = 1;
        var line_start: usize = 0;

        for (source_text, 0..) |char, i| {
            if (char == '\n') {
                if (current_line == line_number) {
                    return source_text[line_start..i];
                }
                current_line += 1;
                line_start = i + 1;
            }
        }

        if (current_line == line_number) {
            return source_text[line_start..];
        }
        return null;
    }
};

/// Diagnostic statistics
pub const DiagnosticStatistics = struct {
    error_count: usize = 0,
    warning_count: usize = 0,
    info_count: usize = 0,
    hint_count: usize = 0,

    pub fn totalCount(self: DiagnosticStatistics) usize {
        return self.error_count + self.warning_count + self.info_count + self.hint_count;
    }

    pub fn hasErrors(self: DiagnosticStatistics) bool {
        return self.error_count > 0;
    }
};

// Standalone helper function
fn formatDiagnosticHelper(diagnostic: *const Diagnostic, writer: anytype) !void {
    const column_offset = diagnostic.primary_span.start.column;
    const span_length = diagnostic.primary_span.end.column - diagnostic.primary_span.start.column;

    var i: usize = 0;
    while (i < column_offset) : (i += 1) {
        try writer.writeByte(' ');
    }

    i = 0;
    while (i < span_length) : (i += 1) {
        try writer.writeByte('^');
    }
    try writer.writeByte('\n');

    // Suggestions
    for (diagnostic.suggestions) |suggestion| {
        try writer.print("help: {s}\n", .{suggestion.message});
        if (suggestion.replacement_text) |replacement| {
            try writer.print("      try: {s}\n", .{replacement});
        }
    }

    // Notes
    for (diagnostic.notes) |note| {
        try writer.print("note: {s}\n", .{note});
    }
}

// Optimized Levenshtein distance calculation
fn levenshteinDistance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    // Use stack allocation for small strings, heap for large ones
    var stack_buffer: [256]usize = undefined;
    var prev_row: []usize = undefined;
    var heap_buffer: ?[]usize = null;

    if (b.len + 1 <= stack_buffer.len) {
        prev_row = stack_buffer[0 .. b.len + 1];
    } else {
        heap_buffer = std.heap.page_allocator.alloc(usize, b.len + 1) catch return @max(a.len, b.len);
        prev_row = heap_buffer.?;
    }
    defer if (heap_buffer) |buf| std.heap.page_allocator.free(buf);

    for (0..b.len + 1) |j| prev_row[j] = j;

    for (1..a.len + 1) |i| {
        var curr_val = i;
        for (1..b.len + 1) |j| {
            const cost: usize = if (a[i - 1] == b[j - 1]) 0 else 1;
            const new_val = @min(@min(curr_val + 1, prev_row[j] + 1), prev_row[j - 1] + cost);
            prev_row[j - 1] = curr_val;
            curr_val = new_val;
        }
        prev_row[b.len] = curr_val;
    }

    return prev_row[b.len];
}

// Type classification helpers for cast suggestions
fn isIntegerType(type_name: []const u8) bool {
    const integer_types = [_][]const u8{
        "i8",    "i16",   "i32", "i64", "i128",
        "u8",    "u16",   "u32", "u64", "u128",
        "isize", "usize",
    };
    for (integer_types) |int_type| {
        if (std.mem.eql(u8, type_name, int_type)) return true;
    }
    return false;
}

fn isFloatType(type_name: []const u8) bool {
    return std.mem.eql(u8, type_name, "f32") or
        std.mem.eql(u8, type_name, "f64") or
        std.mem.eql(u8, type_name, "f16") or
        std.mem.eql(u8, type_name, "f128");
}

fn getIntegerWidth(type_name: []const u8) u16 {
    if (type_name.len < 2) return 0;
    // Skip 'i' or 'u' prefix
    const width_str = type_name[1..];
    if (std.mem.eql(u8, width_str, "size")) return 64; // Assume 64-bit platform
    return std.fmt.parseInt(u16, width_str, 10) catch 0;
}

// ============================================================================
// TESTS
// ============================================================================

test "error manager basic functionality" {
    const allocator = std.testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    const test_span = SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 5, .offset = 4 },
        .end = source_span_utils.SourcePosition{ .line = 1, .column = 10, .offset = 9 },
        .file_path = "test.jan",
    };

    // Test error reporting
    const reported = try error_manager.reportError(.semantic, "E001", "Test error", test_span);
    try std.testing.expect(reported);

    // Check diagnostic was created
    try std.testing.expect(error_manager.diagnostics.items.len == 1);

    const diagnostic = &error_manager.diagnostics.items[0];
    try std.testing.expect(diagnostic.category == .semantic);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "Test error") != null);
}

test "type mismatch error generation" {
    const allocator = std.testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    const test_span = SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = source_span_utils.SourcePosition{ .line = 1, .column = 10, .offset = 9 },
        .file_path = "test.jan",
    };

    // Test type mismatch reporting (legacy API, delegates to context-aware)
    const reported = try error_manager.reportTypeMismatch("i64", "i32", test_span);
    try std.testing.expect(reported);

    // Check diagnostic was created
    try std.testing.expect(error_manager.diagnostics.items.len == 1);

    const diagnostic = &error_manager.diagnostics.items[0];
    try std.testing.expect(diagnostic.category == .type_system);
    // New format uses backticks
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "expected `i64`") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "found `i32`") != null);
}

test "context-aware type mismatch with suggestions" {
    const allocator = std.testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    const primary_span = SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 5, .column = 18, .offset = 100 },
        .end = source_span_utils.SourcePosition{ .line = 5, .column = 28, .offset = 110 },
        .file_path = "test.jan",
    };

    const declaration_span = SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 5, .column = 10, .offset = 92 },
        .end = source_span_utils.SourcePosition{ .line = 5, .column = 13, .offset = 95 },
        .file_path = "test.jan",
    };

    // Test context-aware reporting with assignment context
    const reported = try error_manager.reportTypeMismatchWithContext(
        "i64",
        "i32",
        primary_span,
        declaration_span,
        .assignment,
        "in variable `count`",
    );
    try std.testing.expect(reported);

    const diagnostic = &error_manager.diagnostics.items[0];

    // Check error code matches context
    try std.testing.expectEqualStrings("E3001", diagnostic.code);

    // Check message includes context
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "variable assignment") != null);

    // Check secondary span was added
    try std.testing.expect(diagnostic.secondary_spans.len == 1);

    // Check note was added
    try std.testing.expect(diagnostic.notes.len == 1);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.notes[0], "count") != null);

    // Check suggestion was generated (integer widening)
    try std.testing.expect(diagnostic.suggestions.len == 1);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.suggestions[0].message, "widening") != null);
}

test "type helper functions" {
    // Test integer type detection
    try std.testing.expect(isIntegerType("i32"));
    try std.testing.expect(isIntegerType("u64"));
    try std.testing.expect(isIntegerType("isize"));
    try std.testing.expect(!isIntegerType("f32"));
    try std.testing.expect(!isIntegerType("String"));

    // Test float type detection
    try std.testing.expect(isFloatType("f32"));
    try std.testing.expect(isFloatType("f64"));
    try std.testing.expect(!isFloatType("i32"));

    // Test integer width extraction
    try std.testing.expectEqual(@as(u16, 32), getIntegerWidth("i32"));
    try std.testing.expectEqual(@as(u16, 64), getIntegerWidth("u64"));
    try std.testing.expectEqual(@as(u16, 64), getIntegerWidth("isize"));
}
