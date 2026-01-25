// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Unified Compiler Error Framework
//!
//! Provides a consistent diagnostic system across all compiler phases:
//! - Lexer (L0xxx codes)
//! - Parser (P0xxx codes)
//! - Semantic (S0xxx codes)
//! - CodeGen (C0xxx codes)
//!
//! Features:
//! - Source location tracking with spans
//! - Error aggregation (collect multiple errors before failing)
//! - Helpful error messages with suggestions
//! - Fix suggestions with confidence scores
//! - Related info for context

const std = @import("std");

/// Compiler phase that produced the diagnostic
pub const Phase = enum {
    lexer,
    parser,
    semantic,
    codegen,
    linker,
    warning, // NextGen: Warnings (W0xxx)
    info, // NextGen: Info/Hints (I0xxx)

    pub fn prefix(self: Phase) []const u8 {
        return switch (self) {
            .lexer => "L",
            .parser => "P",
            .semantic => "S",
            .codegen => "C",
            .linker => "K",
            .warning => "W",
            .info => "I",
        };
    }
};

/// Severity level of the diagnostic
pub const Severity = enum {
    @"error",
    warning,
    note,
    hint,

    pub fn symbol(self: Severity) []const u8 {
        return switch (self) {
            .@"error" => "error",
            .warning => "warning",
            .note => "note",
            .hint => "hint",
        };
    }

    pub fn isError(self: Severity) bool {
        return self == .@"error";
    }
};

/// Source position in a file
pub const SourcePos = struct {
    line: u32 = 1,
    column: u32 = 1,
    byte_offset: u32 = 0,

    pub fn format(self: SourcePos, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}:{}", .{ self.line, self.column });
    }
};

/// Span of source code (start to end position)
pub const SourceSpan = struct {
    file: ?[]const u8 = null,
    start: SourcePos = .{},
    end: SourcePos = .{},

    pub fn format(self: SourceSpan, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.file) |f| {
            try writer.print("{s}:", .{f});
        }
        try writer.print("{}:{}", .{ self.start.line, self.start.column });
    }
};

/// A suggested fix for an error
pub const FixSuggestion = struct {
    description: []const u8,
    replacement: []const u8,
    span: SourceSpan,
    confidence: f32 = 1.0, // 0.0 to 1.0

    pub fn deinit(self: *FixSuggestion, allocator: std.mem.Allocator) void {
        allocator.free(self.description);
        allocator.free(self.replacement);
    }
};

/// Related information providing context
pub const RelatedInfo = struct {
    message: []const u8,
    span: SourceSpan,

    pub fn deinit(self: *RelatedInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

/// A compiler diagnostic (error, warning, note, or hint)
pub const Diagnostic = struct {
    allocator: std.mem.Allocator,

    // Classification
    phase: Phase,
    code: u16, // Numeric code within phase (e.g., 1 = L0001)
    severity: Severity,

    // Location
    span: SourceSpan,

    // Messages
    summary: []const u8, // Brief description
    explanation: ?[]const u8 = null, // Detailed explanation
    source_line: ?[]const u8 = null, // The actual source line for display

    // Help
    fixes: std.ArrayListUnmanaged(FixSuggestion) = .{},
    related: std.ArrayListUnmanaged(RelatedInfo) = .{},

    pub fn init(allocator: std.mem.Allocator, phase: Phase, code: u16, severity: Severity, span: SourceSpan, summary: []const u8) Diagnostic {
        return .{
            .allocator = allocator,
            .phase = phase,
            .code = code,
            .severity = severity,
            .span = span,
            .summary = summary,
            .fixes = .{},
            .related = .{},
        };
    }

    pub fn deinit(self: *Diagnostic) void {
        for (self.fixes.items) |*fix| {
            fix.deinit(self.allocator);
        }
        self.fixes.deinit(self.allocator);
        for (self.related.items) |*rel| {
            rel.deinit(self.allocator);
        }
        self.related.deinit(self.allocator);
    }

    /// Get the full error code string (e.g., "P0001")
    pub fn codeString(self: Diagnostic, buf: *[6]u8) []const u8 {
        const prefix = self.phase.prefix();
        _ = std.fmt.bufPrint(buf, "{s}{d:0>4}", .{ prefix, self.code }) catch return "?????";
        return buf[0..5];
    }

    /// Add a fix suggestion
    pub fn addFix(self: *Diagnostic, description: []const u8, replacement: []const u8, span: SourceSpan) !void {
        try self.fixes.append(self.allocator, .{
            .description = try self.allocator.dupe(u8, description),
            .replacement = try self.allocator.dupe(u8, replacement),
            .span = span,
            .confidence = 1.0,
        });
    }

    /// Add related information
    pub fn addRelated(self: *Diagnostic, message: []const u8, span: SourceSpan) !void {
        try self.related.append(self.allocator, .{
            .message = try self.allocator.dupe(u8, message),
            .span = span,
        });
    }

    /// Format the diagnostic for terminal output
    pub fn format(self: Diagnostic, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var code_buf: [6]u8 = undefined;
        const code_str = self.codeString(&code_buf);

        // Main error line: file:line:col: error[P0001]: message
        try writer.print("{}: {s}[{s}]: {s}\n", .{
            self.span,
            self.severity.symbol(),
            code_str,
            self.summary,
        });

        // Source line with caret if available
        if (self.source_line) |src| {
            try writer.print("  |\n", .{});
            try writer.print("{d: >3} | {s}\n", .{ self.span.start.line, src });
            try writer.print("  | ", .{});
            // Print carets under the error span
            var i: u32 = 1;
            while (i < self.span.start.column) : (i += 1) {
                try writer.writeByte(' ');
            }
            const len = if (self.span.end.column > self.span.start.column)
                self.span.end.column - self.span.start.column
            else
                1;
            var j: u32 = 0;
            while (j < len) : (j += 1) {
                try writer.writeByte('^');
            }
            try writer.writeByte('\n');
        }

        // Explanation if present
        if (self.explanation) |exp| {
            try writer.print("  = {s}\n", .{exp});
        }

        // Fix suggestions
        for (self.fixes.items) |fix| {
            try writer.print("  help: {s}\n", .{fix.description});
            if (fix.replacement.len > 0) {
                try writer.print("        {s}\n", .{fix.replacement});
            }
        }

        // Related info
        for (self.related.items) |rel| {
            try writer.print("  --> {}: {s}\n", .{ rel.span, rel.message });
        }
    }
};

/// Collects diagnostics across compilation phases
pub const DiagnosticCollector = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.ArrayListUnmanaged(Diagnostic) = .{},
    error_count: u32 = 0,
    warning_count: u32 = 0,
    source_cache: std.StringHashMapUnmanaged([]const u8) = .{},

    pub fn init(allocator: std.mem.Allocator) DiagnosticCollector {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DiagnosticCollector) void {
        for (self.diagnostics.items) |*diag| {
            diag.deinit();
        }
        self.diagnostics.deinit(self.allocator);
        self.source_cache.deinit(self.allocator);
    }

    /// Register source code for a file (enables source line display)
    pub fn registerSource(self: *DiagnosticCollector, filename: []const u8, source: []const u8) !void {
        try self.source_cache.put(self.allocator, filename, source);
    }

    /// Add a diagnostic
    pub fn add(self: *DiagnosticCollector, diag: Diagnostic) !void {
        if (diag.severity.isError()) {
            self.error_count += 1;
        } else if (diag.severity == .warning) {
            self.warning_count += 1;
        }
        try self.diagnostics.append(self.allocator, diag);
    }

    /// Create and add an error diagnostic
    pub fn addError(
        self: *DiagnosticCollector,
        phase: Phase,
        code: u16,
        span: SourceSpan,
        summary: []const u8,
    ) !*Diagnostic {
        var diag = Diagnostic.init(self.allocator, phase, code, .@"error", span, summary);

        // Try to attach source line
        if (span.file) |file| {
            if (self.source_cache.get(file)) |src| {
                diag.source_line = getLine(src, span.start.line);
            }
        }

        self.error_count += 1;
        try self.diagnostics.append(self.allocator, diag);
        return &self.diagnostics.items[self.diagnostics.items.len - 1];
    }

    /// Create and add a warning diagnostic
    pub fn addWarning(
        self: *DiagnosticCollector,
        phase: Phase,
        code: u16,
        span: SourceSpan,
        summary: []const u8,
    ) !*Diagnostic {
        var diag = Diagnostic.init(self.allocator, phase, code, .warning, span, summary);

        if (span.file) |file| {
            if (self.source_cache.get(file)) |src| {
                diag.source_line = getLine(src, span.start.line);
            }
        }

        self.warning_count += 1;
        try self.diagnostics.append(self.allocator, diag);
        return &self.diagnostics.items[self.diagnostics.items.len - 1];
    }

    /// Check if there are any errors
    pub fn hasErrors(self: DiagnosticCollector) bool {
        return self.error_count > 0;
    }

    /// Get total diagnostic count
    pub fn count(self: DiagnosticCollector) usize {
        return self.diagnostics.items.len;
    }

    /// Format all diagnostics for output
    pub fn format(self: DiagnosticCollector, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        for (self.diagnostics.items) |diag| {
            try writer.print("{}\n", .{diag});
        }

        // Summary line
        if (self.error_count > 0 or self.warning_count > 0) {
            try writer.print("{s}: ", .{if (self.error_count > 0) "error" else "warning"});
            if (self.error_count > 0) {
                try writer.print("{} error{s}", .{ self.error_count, if (self.error_count == 1) "" else "s" });
            }
            if (self.warning_count > 0) {
                if (self.error_count > 0) try writer.print(", ", .{});
                try writer.print("{} warning{s}", .{ self.warning_count, if (self.warning_count == 1) "" else "s" });
            }
            try writer.print(" generated\n", .{});
        }
    }

    /// Emit all diagnostics to stderr
    pub fn emit(self: DiagnosticCollector) void {
        const stderr = std.io.getStdErr().writer();
        stderr.print("{}", .{self}) catch {};
    }
};

// ============================================================================
// LEXER ERROR CODES (L0xxx)
// ============================================================================

pub const LexerError = enum(u16) {
    invalid_character = 1, // L0001: Unexpected character
    unterminated_string = 2, // L0002: String literal not closed
    unterminated_char = 3, // L0003: Character literal not closed
    invalid_escape = 4, // L0004: Invalid escape sequence
    invalid_number = 5, // L0005: Malformed numeric literal
    unterminated_comment = 6, // L0006: Block comment not closed
    invalid_utf8 = 7, // L0007: Invalid UTF-8 sequence
};

// ============================================================================
// PARSER ERROR CODES (P0xxx)
// ============================================================================

pub const ParserError = enum(u16) {
    unexpected_token = 1, // P0001: Unexpected token
    expected_expression = 2, // P0002: Expected expression
    expected_statement = 3, // P0003: Expected statement
    expected_identifier = 4, // P0004: Expected identifier
    expected_type = 5, // P0005: Expected type annotation
    expected_delimiter = 6, // P0006: Expected delimiter (e.g., semicolon, comma)
    unclosed_paren = 7, // P0007: Unclosed parenthesis
    unclosed_brace = 8, // P0008: Unclosed brace
    unclosed_bracket = 9, // P0009: Unclosed bracket
    invalid_declaration = 10, // P0010: Invalid declaration
    duplicate_modifier = 11, // P0011: Duplicate modifier
    invalid_operator = 12, // P0012: Invalid operator in context
    premature_eof = 13, // P0013: Unexpected end of file
    invalid_assignment_target = 14, // P0014: Invalid assignment target
    missing_function_body = 15, // P0015: Function requires body
};

// ============================================================================
// SEMANTIC ERROR CODES (S0xxx)
// ============================================================================

pub const SemanticError = enum(u16) {
    // S0xxx - General Semantic Errors
    undefined_identifier = 1, // S0001: Undefined identifier
    undefined_function = 2, // S0002: Undefined function
    undefined_type = 3, // S0003: Undefined type
    type_mismatch = 4, // S0004: Type mismatch
    invalid_operand = 5, // S0005: Invalid operand for operator
    ambiguous_call = 6, // S0006: Ambiguous function call
    no_matching_overload = 7, // S0007: No matching function overload
    duplicate_definition = 8, // S0008: Duplicate definition
    invalid_return_type = 9, // S0009: Invalid return type
    missing_return = 10, // S0010: Missing return statement
    unreachable_code = 11, // S0011: Unreachable code
    profile_violation = 100, // S0100: Feature not available in profile
    capability_required = 101, // S0101: Capability required

    // S1xxx - Dispatch and Resolution (NextGen)
    dispatch_ambiguous = 1101, // S1101: Ambiguous function dispatch
    dispatch_no_match = 1102, // S1102: No matching function
    dispatch_internal = 1103, // S1103: Internal resolution error
    dispatch_visibility = 1104, // S1104: Visibility violation in dispatch

    // S2xxx - Type Inference (NextGen)
    type_inference_mismatch = 2001, // S2001: Type mismatch (inferred vs expected)
    type_inference_failed = 2002, // S2002: Type inference failed
    type_constraint_violation = 2003, // S2003: Generic constraint violated
    type_flow_divergence = 2004, // S2004: Type flow diverged from expected

    // S3xxx - Effect System (NextGen)
    effect_missing_capability = 3001, // S3001: Required capability not available
    effect_leak = 3002, // S3002: Effect escapes its handler
    effect_purity_violation = 3003, // S3003: Impure operation in pure context
    effect_unhandled = 3004, // S3004: Effect not handled

    // S4xxx - Module and Import (NextGen)
    import_not_found = 4001, // S4001: Import not found
    import_ambiguous = 4002, // S4002: Ambiguous import
    import_circular = 4003, // S4003: Circular import dependency
    visibility_violation = 4004, // S4004: Visibility violation

    // S5xxx - Pattern Matching (NextGen)
    pattern_incomplete = 5001, // S5001: Non-exhaustive pattern match
    pattern_unreachable = 5002, // S5002: Unreachable pattern
    pattern_type_mismatch = 5003, // S5003: Pattern type mismatch

    // S6xxx - Lifetime and Memory (NextGen)
    lifetime_exceeded = 6001, // S6001: Lifetime exceeded
    borrow_conflict = 6002, // S6002: Conflicting borrows
    use_after_move = 6003, // S6003: Use after move
};

// ============================================================================
// WARNING CODES (W0xxx) - NextGen
// ============================================================================

pub const Warning = enum(u16) {
    // W0xxx - General Warnings
    unused_variable = 1, // W0001: Unused variable
    unused_import = 2, // W0002: Unused import
    unused_function = 3, // W0003: Unused function
    deprecated_usage = 4, // W0004: Using deprecated feature
    shadowed_variable = 5, // W0005: Variable shadows outer scope

    // W01xx - Type Warnings
    implicit_conversion = 100, // W0100: Implicit type conversion
    lossy_conversion = 101, // W0101: Potentially lossy conversion
    nullable_access = 102, // W0102: Accessing potentially null value

    // W02xx - Performance Warnings
    inefficient_pattern = 200, // W0200: Inefficient pattern detected
    redundant_clone = 201, // W0201: Redundant clone operation
    allocation_in_loop = 202, // W0202: Allocation inside loop

    // W03xx - Style Warnings
    naming_convention = 300, // W0300: Naming convention violation
    complexity_high = 301, // W0301: High cyclomatic complexity
    function_too_long = 302, // W0302: Function exceeds recommended length
};

// ============================================================================
// INFO/HINT CODES (I0xxx) - NextGen
// ============================================================================

pub const Info = enum(u16) {
    // I0xxx - Informational Messages
    similar_function_exists = 1, // I0001: Similar function exists in scope
    conversion_available = 2, // I0002: Type conversion is available
    alternative_approach = 3, // I0003: Alternative approach suggested

    // I01xx - Type Hints
    inferred_type = 100, // I0100: Type was inferred as
    constraint_from = 101, // I0101: Constraint originates from
    type_flow_trace = 102, // I0102: Type flow trace

    // I02xx - Resolution Hints
    candidate_rejected = 200, // I0200: Candidate rejected because
    visibility_note = 201, // I0201: Note about visibility
    import_suggestion = 202, // I0202: Consider importing
};

// ============================================================================
// CODEGEN ERROR CODES (C0xxx)
// ============================================================================

pub const CodegenError = enum(u16) {
    unsupported_feature = 1, // C0001: Unsupported feature
    internal_error = 2, // C0002: Internal codegen error
    llvm_error = 3, // C0003: LLVM backend error
    link_error = 4, // C0004: Linking error
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Extract a specific line from source text
fn getLine(source: []const u8, line_num: u32) ?[]const u8 {
    if (line_num == 0) return null;

    var current_line: u32 = 1;
    var line_start: usize = 0;

    for (source, 0..) |c, i| {
        if (current_line == line_num) {
            // Found the start of our line, now find the end
            var line_end = i;
            while (line_end < source.len and source[line_end] != '\n') {
                line_end += 1;
            }
            return source[line_start..line_end];
        }
        if (c == '\n') {
            current_line += 1;
            line_start = i + 1;
        }
    }

    // Handle last line without trailing newline
    if (current_line == line_num and line_start < source.len) {
        return source[line_start..];
    }

    return null;
}

// ============================================================================
// TESTS
// ============================================================================

test "Diagnostic formatting" {
    const allocator = std.testing.allocator;

    var collector = DiagnosticCollector.init(allocator);
    defer collector.deinit();

    // Register source
    try collector.registerSource("test.jan", "let x = 42;\nlet y = x + ;\n");

    // Add an error
    const span = SourceSpan{
        .file = "test.jan",
        .start = .{ .line = 2, .column = 12, .byte_offset = 23 },
        .end = .{ .line = 2, .column = 13, .byte_offset = 24 },
    };
    var diag = try collector.addError(.parser, @intFromEnum(ParserError.expected_expression), span, "expected expression after '+'");
    try diag.addFix("add an expression", "let y = x + 0;", span);

    try std.testing.expect(collector.hasErrors());
    try std.testing.expectEqual(@as(u32, 1), collector.error_count);
}

test "DiagnosticCollector counts" {
    const allocator = std.testing.allocator;

    var collector = DiagnosticCollector.init(allocator);
    defer collector.deinit();

    const span = SourceSpan{};

    _ = try collector.addError(.lexer, 1, span, "error 1");
    _ = try collector.addError(.parser, 1, span, "error 2");
    _ = try collector.addWarning(.semantic, 1, span, "warning 1");

    try std.testing.expectEqual(@as(u32, 2), collector.error_count);
    try std.testing.expectEqual(@as(u32, 1), collector.warning_count);
    try std.testing.expectEqual(@as(usize, 3), collector.count());
}

test "getLine extracts correct lines" {
    const source = "line 1\nline 2\nline 3\n";

    try std.testing.expectEqualStrings("line 1", getLine(source, 1).?);
    try std.testing.expectEqualStrings("line 2", getLine(source, 2).?);
    try std.testing.expectEqualStrings("line 3", getLine(source, 3).?);
    try std.testing.expect(getLine(source, 0) == null);
    try std.testing.expect(getLine(source, 5) == null);
}

test "error code string formatting" {
    const allocator = std.testing.allocator;
    const span = SourceSpan{};

    var diag = Diagnostic.init(allocator, .parser, 1, .@"error", span, "test");
    defer diag.deinit();

    var buf: [6]u8 = undefined;
    const code = diag.codeString(&buf);
    try std.testing.expectEqualStrings("P0001", code);
}
