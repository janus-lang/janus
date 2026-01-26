// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Source Span Utilities
//!
//! This module provides precise source location tracking and span reporting
//! for semantic analysis using ASTDB columnar APIs.

const std = @import("std");
const Allocator = std.mem.Allocator;
const libjanus = @import("astdb");
const core = libjanus.astdb.snapshot;
const node_view_mod = libjanus.astdb.node_view;
pub const SourceSpan = core.SourceSpan;

/// Source position in a file
pub const SourcePosition = struct {
    line: u32,
    column: u32,
    offset: u32,

    pub fn format(self: SourcePosition, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}:{}", .{ self.line, self.column });
    }
};

/// Source span covering a range in source code
pub const SourceSpanCompat = struct {
    start: SourcePosition,
    end: SourcePosition,
    file_path: []const u8,

    pub fn format(self: SourceSpanCompat, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}:{}:{}-{}:{}", .{ self.file_path, self.start.line, self.start.column, self.end.line, self.end.column });
    }

    /// Check if this span contains another span
    pub fn contains(self: SourceSpanCompat, other: SourceSpanCompat) bool {
        if (!std.mem.eql(u8, self.file_path, other.file_path)) return false;

        return (self.start.offset <= other.start.offset) and
            (self.end.offset >= other.end.offset);
    }

    /// Get the length of this span in characters
    pub fn length(self: SourceSpanCompat) u32 {
        return self.end.offset - self.start.offset;
    }
};

/// Convert ASTDB SourceSpan to compatibility format
pub fn convertSourceSpan(span: SourceSpan, file_path: []const u8) SourceSpanCompat {
    return SourceSpanCompat{
        .start = SourcePosition{ .line = span.line, .column = span.column, .offset = span.start },
        .end = SourcePosition{ .line = span.line, .column = span.column + (span.end - span.start), .offset = span.end },
        .file_path = file_path,
    };
}

/// Source span tracker for building spans during parsing
pub const SourceSpanTracker = struct {
    allocator: Allocator,
    file_path: []const u8,
    source_text: []const u8,
    line_starts: std.ArrayList(u32),

    pub fn init(allocator: Allocator, file_path: []const u8, source_text: []const u8) !SourceSpanTracker {
        var tracker = SourceSpanTracker{
            .allocator = allocator,
            .file_path = try allocator.dupe(u8, file_path),
            .source_text = source_text,
            .line_starts = std.ArrayList(u32).init(allocator),
        };

        try tracker.buildLineIndex();
        return tracker;
    }

    pub fn deinit(self: *SourceSpanTracker) void {
        self.allocator.free(self.file_path);
        self.line_starts.deinit();
    }

    /// Build index of line start positions
    fn buildLineIndex(self: *SourceSpanTracker) !void {
        try self.line_starts.append(0); // First line starts at offset 0

        for (self.source_text, 0..) |char, i| {
            if (char == '\n') {
                try self.line_starts.append(@intCast(i + 1));
            }
        }
    }

    /// Convert byte offset to line/column position
    pub fn offsetToPosition(self: *SourceSpanTracker, offset: u32) SourcePosition {
        // Binary search for the line containing this offset
        var line: u32 = 0;
        for (self.line_starts.items, 0..) |line_start, i| {
            if (offset < line_start) {
                line = @intCast(i - 1);
                break;
            }
            line = @intCast(i);
        }

        const line_start = self.line_starts.items[line];
        const column = offset - line_start;

        return SourcePosition{
            .line = line + 1, // 1-based line numbers
            .column = column + 1, // 1-based column numbers
            .offset = offset,
        };
    }

    /// Create a source span from start and end offsets
    pub fn createSpan(self: *SourceSpanTracker, start_offset: u32, end_offset: u32) SourceSpanCompat {
        return SourceSpanCompat{
            .start = self.offsetToPosition(start_offset),
            .end = self.offsetToPosition(end_offset),
            .file_path = self.file_path,
        };
    }
};

/// Get complete source span for any AST node using NodeView API
pub fn getNodeSpan(node_view: node_view_mod.NodeView) SourceSpanCompat {
    return convertSourceSpan(node_view.span(), node_view.unit.path);
}

/// Get extended span including all child nodes using NodeView API
pub fn getExtendedNodeSpan(node_view: node_view_mod.NodeView) SourceSpanCompat {
    var span = node_view.span();

    // Extend span to include all children
    const children = node_view.children();
    for (children) |child_id| {
        const child_view = node_view_mod.NodeView.init(node_view.ast, node_view.unit_id, child_id);
        const child_span = child_view.span();

        // Extend start if child starts earlier
        if (child_span.start < span.start) {
            span.start = child_span.start;
        }

        // Extend end if child ends later
        if (child_span.end > span.end) {
            span.end = child_span.end;
        }
    }

    return convertSourceSpan(span, node_view.unit.path);
}

/// Get source text covered by a span
pub fn getSpanText(span: SourceSpanCompat, source_text: []const u8) []const u8 {
    const start = span.start.offset;
    const end = span.end.offset;

    if (end > source_text.len) return "";
    if (start >= end) return "";

    return source_text[start..end];
}

/// Create a diagnostic message with source context
pub fn createDiagnosticWithContext(
    allocator: Allocator,
    span: SourceSpanCompat,
    source_text: []const u8,
    message: []const u8,
) ![]const u8 {
    const span_text = getSpanText(span, source_text);

    return try std.fmt.allocPrint(allocator, "{s}:{}:{}: {s} at '{s}'", .{ span.file_path, span.start.line, span.start.column, message, span_text });
}

// Comprehensive test suite
test "source position conversion" {
    const allocator = std.testing.allocator;
    const source = "line 1\nline 2\nline 3";

    var tracker = try SourceSpanTracker.init(allocator, "test.jan", source);
    defer tracker.deinit();

    // Test position at start of file
    const pos1 = tracker.offsetToPosition(0);
    try std.testing.expect(pos1.line == 1 and pos1.column == 1);

    // Test position at start of second line
    const pos2 = tracker.offsetToPosition(7); // After "line 1\n"
    try std.testing.expect(pos2.line == 2 and pos2.column == 1);

    // Test position in middle of second line
    const pos3 = tracker.offsetToPosition(10); // "ne" in "line 2"
    try std.testing.expect(pos3.line == 2 and pos3.column == 4);
}

test "source span creation and operations" {
    const allocator = std.testing.allocator;
    const source = "function test() { return 42; }";

    var tracker = try SourceSpanTracker.init(allocator, "test.jan", source);
    defer tracker.deinit();

    // Create span for "function" keyword
    const func_span = tracker.createSpan(0, 8);
    try std.testing.expect(func_span.start.line == 1);
    try std.testing.expect(func_span.start.column == 1);
    try std.testing.expect(func_span.end.column == 9);

    // Test span length
    try std.testing.expect(func_span.length() == 8);

    // Test span text extraction
    const span_text = getSpanText(func_span, source);
    try std.testing.expectEqualStrings("function", span_text);
}

test "getNodeSpan function" {
    _ = std.testing.allocator;

    // Create a mock ASTDB and unit for testing
    var db = core.AstDB.init(std.testing.allocator, false);
    defer db.deinit();

    const unit_id = try db.addUnit("test.jan", "function test");
    const unit = db.getUnit(unit_id).?;

    // Create a mock node in the unit
    const test_node = core.AstNode{
        .kind = .func_decl,
        .first_token = @enumFromInt(0),
        .last_token = @enumFromInt(1),
        .child_lo = 0,
        .child_hi = 0,
    };

    // Add tokens for the span
    const tokens = [_]core.Token{
        .{ .kind = .func, .str = null, .span = .{ .start = 0, .end = 8, .line = 1, .column = 1 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .identifier, .str = db.str_interner.getId("test"), .span = .{ .start = 9, .end = 13, .line = 1, .column = 10 }, .trivia_lo = 0, .trivia_hi = 0 },
    };

    unit.tokens = try unit.arenaAllocator().dupe(core.Token, &tokens);
    unit.nodes = try unit.arenaAllocator().dupe(core.AstNode, &[_]core.AstNode{test_node});

    // Create NodeView and test getNodeSpan function
    const node_view = node_view_mod.NodeView.init(&db, unit_id, @enumFromInt(0));
    const retrieved_span = getNodeSpan(node_view);

    try std.testing.expect(retrieved_span.start.offset == 0);
    try std.testing.expect(retrieved_span.end.offset == 13);
    try std.testing.expectEqualStrings(retrieved_span.file_path, "test.jan");
}

test "diagnostic message creation" {
    const allocator = std.testing.allocator;
    const source = "let x = invalid_syntax;";

    const error_span = SourceSpanCompat{
        .start = SourcePosition{ .line = 1, .column = 9, .offset = 8 },
        .end = SourcePosition{ .line = 1, .column = 23, .offset = 22 }, // Include full "invalid_syntax"
        .file_path = "test.jan",
    };

    const diagnostic = try createDiagnosticWithContext(allocator, error_span, source, "syntax error");
    defer allocator.free(diagnostic);

    // Should contain file path, position, and error message
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "test.jan") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "syntax error") != null);
    // The diagnostic should contain the span text "invalid_syntax"
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "invalid_syntax") != null);
}
