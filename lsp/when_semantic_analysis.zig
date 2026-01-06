// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! LSP Semantic Analysis for `when` Keyword
//!
//! This module provides comprehensive semantic analysis support for the new
//! `when` keyword, including validation, diagnostics, and code intelligence.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

/// Semantic analysis for when keyword usage
pub const WhenSemanticAnalyzer = struct {
    allocator: Allocator,
    diagnostics: ArrayList(Diagnostic),

    pub fn init(allocator: Allocator) WhenSemanticAnalyzer {
        return WhenSemanticAnalyzer{
            .allocator = allocator,
            .diagnostics = ArrayList(Diagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *WhenSemanticAnalyzer) void {
        for (self.diagnostics.items) |*diagnostic| {
            diagnostic.deinit(self.allr);
        }
        self.diagnostics.deinit();
    }

    /// Analyze when keyword usage in source code
    pub fn analyzeWhenUsage(self: *WhenSemanticAnalyzer, source: []const u8, file_path: []const u8) ![]Diagnostic {
        self.diagnostics.clearRetainingCapacity();

        // Parse and analyze when keyword contexts
        try self.analyzeMatchGuards(source, file_path);
        try self.analyzePostfixConditionals(source, file_path);
        try self.validateWhenSyntax(source, file_path);

        return try self.diagnostics.toOwnedSlice();
    }

    /// Analyze when guards in match statements
    fn analyzeMatchGuards(self: *WhenSemanticAnalyzer, source: []const u8, file_path: []const u8) !void {
        var line_number: u32 = 1;
        var lines = std.mem.split(u8, source, "\n");

        while (lines.next()) |line| {
            defer line_number += 1;

            // Look for match guard patterns: "pattern when condition =>"
            if (std.mem.indexOf(u8, line, "when") != null and std.mem.indexOf(u8, line, "=>") != null) {
                try self.validateMatchGuard(line, line_number, file_path);
            }
        }
    }

    /// Analyze postfix when conditionals
    fn analyzePostfixConditionals(self: *WhenSemanticAnalyzer, source: []const u8, file_path: []const u8) !void {
        var line_number: u32 = 1;
        var lines = std.mem.split(u8, source, "\n");

        while (lines.next()) |line| {
            defer line_number += 1;

            // Look for postfix patterns: "statement when condition"
            if (std.mem.indexOf(u8, line, "when") != null and std.mem.indexOf(u8, line, "=>") == null) {
                try self.validatePostfixConditional(line, line_number, file_path);
            }
        }
    }

    /// Validate when syntax usage
    fn validateWhenSyntax(self: *WhenSemanticAnalyzer, source: []const u8, file_path: []const u8) !void {
        _ = source;
        _ = file_path;
        // Additional syntax validation can be added here
    }

    /// Validate match guard syntax
    fn validateMatchGuard(self: *WhenSemanticAnalyzer, line: []const u8, line_number: u32, file_path: []const u8) !void {
        const when_pos = std.mem.indexOf(u8, line, "when") orelse return;
        const arrow_pos = std.mem.indexOf(u8, line, "=>") orelse return;

        // Ensure when comes before =>
        if (when_pos >= arrow_pos) {
            const diagnostic = Diagnostic{
                .severity = .Error,
                .message = try self.allocator.dupe(u8, "Invalid match guard: 'when' must come before '=>'"),
                .file_path = try self.allocator.dupe(u8, file_path),
                .line = line_number,
                .column = @intCast(when_pos + 1),
                .suggestions = try self.createMatchGuardSuggestions(),
            };
            try self.diagnostics.append(diagnostic);
            return;
        }

        // Check for condition after when
        const condition_start = when_pos + 4; // "when".len
        if (condition_start >= line.len or std.mem.trim(u8, line[condition_start..arrow_pos], " \t").len == 0) {
            const diagnostic = Diagnostic{
                .severity = .Error,
                .message = try self.allocator.dupe(u8, "Match guard missing condition after 'when'"),
                .file_path = try self.allocator.dupe(u8, file_path),
                .line = line_number,
                .column = @intCast(condition_start + 1),
                .suggestions = try self.createConditionSuggestions(),
            };
            try self.diagnostics.append(diagnostic);
        }
    }

    /// Validate postfix conditional syntax
    fn validatePostfixConditional(self: *WhenSemanticAnalyzer, line: []const u8, line_number: u32, file_path: []const u8) !void {
        const when_pos = std.mem.indexOf(u8, line, "when") orelse return;

        // Check for statement before when
        const statement_part = std.mem.trim(u8, line[0..when_pos], " \t");
        if (statement_part.len == 0) {
            const diagnostic = Diagnostic{
                .severity = .Error,
                .message = try self.allocator.dupe(u8, "Postfix conditional missing statement before 'when'"),
                .file_path = try self.allocator.dupe(u8, file_path),
                .line = line_number,
                .column = 1,
                .suggestions = try self.createStatementSuggestions(),
            };
            try self.diagnostics.append(diagnostic);
            return;
        }

        // Check for condition after when
        const condition_start = when_pos + 4; // "when".len
        if (condition_start >= line.len or std.mem.trim(u8, line[condition_start..], " \t").len == 0) {
            const diagnostic = Diagnostic{
                .severity = .Error,
                .message = try self.allocator.dupe(u8, "Postfix conditional missing condition after 'when'"),
                .file_path = try self.allocator.dupe(u8, file_path),
                .line = line_number,
                .column = @intCast(condition_start + 1),
                .suggestions = try self.createConditionSuggestions(),
            };
            try self.diagnostics.append(diagnostic);
            return;
        }

        // Validate statement type for postfix conditionals
        try self.validatePostfixStatement(statement_part, line_number, file_path);
    }

    /// Validate that statement is appropriate for postfix when
    fn validatePostfixStatement(self: *WhenSemanticAnalyzer, statement: []const u8, line_number: u32, file_path: []const u8) !void {
        const valid_statements = [_][]const u8{ "return", "break", "continue", "log.", "print", "throw", "yield" };

        var is_valid = false;
        for (valid_statements) |valid| {
            if (std.mem.startsWith(u8, std.mem.trim(u8, statement, " \t"), valid)) {
                is_valid = true;
                break;
            }
        }

        // Also allow assignments and function calls
        if (!is_valid) {
            if (std.mem.indexOf(u8, statement, "=") != null or
                std.mem.indexOf(u8, statement, "(") != null)
            {
                is_valid = true;
            }
        }

        if (!is_valid) {
            const diagnostic = Diagnostic{
                .severity = .Warning,
                .message = try std.fmt.allocPrint(self.allocator, "Statement '{}' may not be suitable for postfix conditional", .{std.mem.trim(u8, statement, " \t")}),
                .file_path = try self.allocator.dupe(u8, file_path),
                .line = line_number,
                .column = 1,
                .suggestions = try self.createPostfixStatementSuggestions(),
            };
            try self.diagnostics.append(diagnostic);
        }
    }

    /// Create suggestions for match guard fixes
    fn createMatchGuardSuggestions(self: *WhenSemanticAnalyzer) ![][]const u8 {
        var suggestions = ArrayList([]const u8).init(self.allocator);

        try suggestions.append(try self.allocator.dupe(u8, "Use format: pattern when condition => result"));
        try suggestions.append(try self.allocator.dupe(u8, "Example: n when n > 0 => \"positive\""));

        return suggestions.toOwnedSlice();
    }

    /// Create suggestions for missing conditions
    fn createConditionSuggestions(self: *WhenSemanticAnalyzer) ![][]const u8 {
        var suggestions = ArrayList([]const u8).init(self.allocator);

        try suggestions.append(try self.allocator.dupe(u8, "Add a boolean condition after 'when'"));
        try suggestions.append(try self.allocator.dupe(u8, "Example: when x > 0"));
        try suggestions.append(try self.allocator.dupe(u8, "Example: when user != null"));

        return suggestions.toOwnedSlice();
    }

    /// Create suggestions for missing statements
    fn createStatementSuggestions(self: *WhenSemanticAnalyzer) ![][]const u8 {
        var suggestions = ArrayList([]const u8).init(self.allocator);

        try suggestions.append(try self.allocator.dupe(u8, "Add a statement before 'when'"));
        try suggestions.append(try self.allocator.dupe(u8, "Example: return error when condition"));
        try suggestions.append(try self.allocator.dupe(u8, "Example: break when found"));

        return suggestions.toOwnedSlice();
    }

    /// Create suggestions for postfix statement improvements
    fn createPostfixStatementSuggestions(self: *WhenSemanticAnalyzer) ![][]const u8 {
        var suggestions = ArrayList([]const u8).init(self.allocator);

        try suggestions.append(try self.allocator.dupe(u8, "Consider using regular if statement for complex logic"));
        try suggestions.append(try self.allocator.dupe(u8, "Postfix when works best with: return, break, continue, assignments"));

        return suggestions.toOwnedSlice();
    }

    /// Provide code actions for when keyword improvements
    pub fn getCodeActions(self: *WhenSemanticAnalyzer, line: []const u8, position: Position) ![]CodeAction {
        var actions = ArrayList(CodeAction).init(self.allocator);

        // Convert postfix when to regular if statement
        if (std.mem.indexOf(u8, line, "when") != null and std.mem.indexOf(u8, line, "=>") == null) {
            const action = CodeAction{
                .title = "Convert to if statement",
                .kind = .Refactor,
                .edit = try self.createIfStatementConversion(line),
            };
            try actions.append(action);
        }

        // Convert if statement to postfix when (if simple enough)
        if (std.mem.indexOf(u8, line, "if") != null and self.isSimpleIfStatement(line)) {
            const action = CodeAction{
                .title = "Convert to postfix when",
                .kind = .Refactor,
                .edit = try self.createPostfixWhenConversion(line),
            };
            try actions.append(action);
        }

        _ = position; // Position-specific actions could be added here

        return actions.toOwnedSlice();
    }

    /// Check if if statement is simple enough for postfix conversion
    fn isSimpleIfStatement(self: *WhenSemanticAnalyzer, line: []const u8) bool {
        _ = self;
        // Simple heuristic: single line if with do...end
        return std.mem.indexOf(u8, line, "if") != null and
            std.mem.indexOf(u8, line, "do") != null and
            std.mem.indexOf(u8, line, "end") != null;
    }

    /// Create if statement conversion edit
    fn createIfStatementConversion(self: *WhenSemanticAnalyzer, line: []const u8) !TextEdit {
        const when_pos = std.mem.indexOf(u8, line, "when") orelse return error.NoWhenFound;

        const statement = std.mem.trim(u8, line[0..when_pos], " \t");
        const condition = std.mem.trim(u8, line[when_pos + 4 ..], " \t");

        const new_text = try std.fmt.allocPrint(self.allocator, "if {s} do\n    {s}\nend", .{ condition, statement });

        return TextEdit{
            .range = Range{ .start = Position{ .line = 0, .character = 0 }, .end = Position{ .line = 0, .character = @intCast(line.len) } },
            .new_text = new_text,
        };
    }

    /// Create postfix when conversion edit
    fn createPostfixWhenConversion(self: *WhenSemanticAnalyzer, line: []const u8) !TextEdit {
        // Extract if condition and statement
        // This is a simplified implementation
        const new_text = try self.allocator.dupe(u8, "// Conversion not implemented yet");

        return TextEdit{
            .range = Range{ .start = Position{ .line = 0, .character = 0 }, .end = Position{ .line = 0, .character = @intCast(line.len) } },
            .new_text = new_text,
        };
    }
};

/// LSP diagnostic structure
pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    file_path: []const u8,
    line: u32,
    column: u32,
    suggestions: [][]const u8,

    pub const Severity = enum {
        Error,
        Warning,
        Information,
        Hint,
    };

    pub fn deinit(self: *Diagnostic, allocator: Allocator) void {
        allocator.free(self.message);
        allocator.free(self.file_path);
        for (self.suggestions) |suggestion| {
            allocator.free(suggestion);
        }
        allocator.free(self.suggestions);
    }
};

/// LSP position structure
pub const Position = struct {
    line: u32,
    character: u32,
};

/// LSP range structure
pub const Range = struct {
    start: Position,
    end: Position,
};

/// LSP text edit structure
pub const TextEdit = struct {
    range: Range,
    new_text: []const u8,
};

/// LSP code action structure
pub const CodeAction = struct {
    title: []const u8,
    kind: Kind,
    edit: TextEdit,

    pub const Kind = enum {
        QuickFix,
        Refactor,
        Source,
    };
};

// Comprehensive test suite
test "when guard validation" {
    const allocator = std.testing.allocator;

    var analyzer = WhenSemanticAnalyzer.init(allocator);
    defer analyzer.deinit();

    const source =
        \\match x do
        \\  n when n > 0 => "positive"
        \\  n when => "invalid"
        \\  _ => "other"
        \\end
    ;

    const diagnostics = try analyzer.analyzeWhenUsage(source, "test.jan");
    defer {
        for (diagnostics) |*diagnostic| {
            diagnostic.deinit(allocator);
        }
        allocator.free(diagnostics);
    }

    // Should find error in line with missing condition
    try std.testing.expect(diagnostics.len > 0);

    var found_missing_condition = false;
    for (diagnostics) |diagnostic| {
        if (std.mem.indexOf(u8, diagnostic.message, "missing condition") != null) {
            found_missing_condition = true;
        }
    }
    try std.testing.expect(found_missing_condition);
}

test "postfix when validation" {
    const allocator = std.testing.allocator;

    var analyzer = WhenSemanticAnalyzer.init(allocator);
    defer analyzer.deinit();

    const source =
        \\return error when user == null
        \\when condition
        \\break when found
    ;

    const diagnostics = try analyzer.analyzeWhenUsage(source, "test.jan");
    defer {
        for (diagnostics) |*diagnostic| {
            diagnostic.deinit(allocator);
        }
        allocator.free(diagnostics);
    }

    // Should find error in line with missing statement
    try std.testing.expect(diagnostics.len > 0);

    var found_missing_statement = false;
    for (diagnostics) |diagnostic| {
        if (std.mem.indexOf(u8, diagnostic.message, "missing statement") != null) {
            found_missing_statement = true;
        }
    }
    try std.testing.expect(found_missing_statement);
}
