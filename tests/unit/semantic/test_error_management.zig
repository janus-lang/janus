// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Error Management System Test Suite
//!
//! This test suite validates the semantic error and warning structures,
//! error recovery strategies, and comprehensive diagnostic generation.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const ErrorManager = @import("../../../compiler/semantic/error_manager.zig").ErrorManager;
const Diagnostic = @import("../../../compiler/semantic/error_manager.zig").Diagnostic;
const DiagnosticSuggestion = @import("../../../compiler/semantic/error_manager.zig").DiagnosticSuggestion;
const ErrorSeverity = @import("../../../compiler/semantic/error_manager.zig").ErrorSeverity;
const ErrorCategory = @import("../../../compiler/semantic/error_manager.zig").ErrorCategory;
const ErrorSuppression = @import("../../../compiler/semantic/error_manager.zig").ErrorSuppression;
const RecoveryStrategy = @import("../../../compiler/semantic/error_manager.zig").RecoveryStrategy;

const SemanticError = @import("../../../compiler/semantic/validation_engine.zig").SemanticError;
const SemanticWarning = @import("../../../compiler/semantic/validation_engine.zig").SemanticWarning;
const SemanticErrorKind = @import("../../../compiler/semantic/validation_engine.zig").SemanticErrorKind;

const source_span_utils = @import("../../../compiler/semantic/source_span_utils.zig");
const SourceSpan = source_span_utils.SourceSpan;
const SourcePosition = source_span_utils.SourcePosition;

test "semantic error structure creation and management" {
    const allocator = testing.allocator;

    const test_span = SourceSpan{
        .start = SourcePosition{ .line = 10, .column = 5, .offset = 150 },
        .end = SourcePosition{ .line = 10, .column = 15, .offset = 160 },
        .file_path = "src/main.jan",
    };

    // Create semantic error with suggestions
    var error_info = SemanticError{
        .kind = .undefined_symbol,
        .span = test_span,
        .message = try allocator.dupe(u8, "Undefined symbol 'calcualte'"),
        .suggestions = try allocator.alloc([]const u8, 2),
        .related_spans = try allocator.alloc(SourceSpan, 1),
    };

    error_info.suggestions[0] = try allocator.dupe(u8, "calculate");
    error_info.suggestions[1] = try allocator.dupe(u8, "calibrate");
    error_info.related_spans[0] = SourceSpan{
        .start = SourcePosition{ .line = 5, .column = 1, .offset = 80 },
        .end = SourcePosition{ .line = 5, .column = 10, .offset = 89 },
        .file_path = "src/main.jan",

    defer error_info.deinit(allocator);

    // Verify error properties
    try testing.expect(error_info.kind == .undefined_symbol);
    try testing.expect(std.mem.eql(u8, error_info.message, "Undefined symbol 'calcualte'"));
    try testing.expect(error_info.suggestions.len == 2);
    try testing.expect(std.mem.eql(u8, error_info.suggestions[0], "calculate"));
    try testing.expect(std.mem.eql(u8, error_info.suggestions[1], "calibrate"));
    try testing.expect(error_info.related_spans.len == 1);
    try testing.expect(error_info.span.start.line == 10);
    try testing.expect(error_info.span.start.column == 5);
}

test "semantic warning structure creation and management" {
    const allocator = testing.allocator;

    const test_span = SourceSpan{
        .start = SourcePosition{ .line = 15, .column = 8, .offset = 200 },
        .end = SourcePosition{ .line = 15, .column = 20, .offset = 212 },
        .file_path = "src/utils.jan",
    };

    var warning = SemanticWarning{
        .span = test_span,
        .message = try allocator.dupe(u8, "Unused variable 'temp_result'"),
    };

    defer warning.deinit(allocator);

    // Verify warning properties
    try testing.expect(std.mem.eql(u8, warning.message, "Unused variable 'temp_result'"));
    try testing.expect(warning.span.start.line == 15);
    try testing.expect(warning.span.start.column == 8);
    try testing.expect(std.mem.eql(u8, warning.span.file_path, "src/utils.jan"));
}

test "error manager initialization and basic operations" {
    const allocator = testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    // Test initial state
    try testing.expect(error_manager.diagnostics.items.len == 0);
    try testing.expect(error_manager.error_count == 0);
    try testing.expect(!error_manager.shouldStopCompilation());
    try testing.expect(error_manager.max_errors == 100);

    // Test error limit configuration
    error_manager.max_errors = 5;
    try testing.expect(error_manager.max_errors == 5);
}

test "diagnostic creation with severity levels" {
    const allocator = testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    const test_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = SourcePosition{ .line = 1, .column = 10, .offset = 9 },
        .file_path = "test.jan",
    };

    // Test error reporting
    const error_reported = try error_manager.reportError(.semantic, "E001", "Test error message", test_span);
    try testing.expect(error_reported);
    try testing.expect(error_manager.diagnostics.items.len == 1);
    try testing.expect(error_manager.error_count == 1);

    const error_diagnostic = &error_manager.diagnostics.items[0];
    try testing.expect(error_diagnostic.severity == .error);
    try testing.expect(error_diagnostic.category == .semantic);
    try testing.expect(std.mem.eql(u8, error_diagnostic.code, "E001"));

    // Test warning reporting
    const warning_reported = try error_manager.reportWarning(.style, "W001", "Test warning message", test_span);
    try testing.expect(warning_reported);
    try testing.expect(error_manager.diagnostics.items.len == 2);
    try testing.expect(error_manager.error_count == 1); // Warnings don't increment error count

    const warning_diagnostic = &error_manager.diagnostics.items[1];
    try testing.expect(warning_diagnostic.severity == .warning);
    try testing.expect(warning_diagnostic.category == .style);
    try testing.expect(std.mem.eql(u8, warning_diagnostic.code, "W001"));
}

test "error suppression system functionality" {
    const allocator = testing.allocator;

    var suppression = ErrorSuppression.init(allocator);
    defer suppression.deinit();

    const primary_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 10, .offset = 100 },
        .end = SourcePosition{ .line = 1, .column = 20, .offset = 110 },
        .file_path = "test.jan",
    };

    // Initially should not suppress
    try testing.expect(!suppression.shouldSuppress(primary_span));

    // Add suppression around the span
    try suppression.suppressAround(primary_span);

    // Should now suppress errors in the vicinity
    const nearby_span1 = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 12, .offset = 102 },
        .end = SourcePosition{ .line = 1, .column = 15, .offset = 105 },
        .file_path = "test.jan",
    };

    const nearby_span2 = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 8, .offset = 98 },
        .end = SourcePosition{ .line = 1, .column = 11, .offset = 101 },
        .file_path = "test.jan",
    };

    try testing.expect(suppression.shouldSuppress(nearby_span1));
    try testing.expect(suppression.shouldSuppress(nearby_span2));

    // Distant spans should not be suppressed
    const distant_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 1, .offset = 1 },
        .end = SourcePosition{ .line = 1, .column = 5, .offset = 5 },
        .file_path = "test.jan",
    };

    try testing.expect(!suppression.shouldSuppress(distant_span));
}

test "error suppression integration with error manager" {
    const allocator = testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    const primary_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 10, .offset = 100 },
        .end = SourcePosition{ .line = 1, .column = 20, .offset = 110 },
        .file_path = "test.jan",
    };

    // Report first error
    const first_reported = try error_manager.reportError(.semantic, "E001", "Primary error", primary_span);
    try testing.expect(first_reported);
    try testing.expect(error_manager.diagnostics.items.len == 1);

    // Report nearby error - should be suppressed
    const nearby_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 12, .offset = 102 },
        .end = SourcePosition{ .line = 1, .column = 15, .offset = 105 },
        .file_path = "test.jan",
    };

    const second_reported = try error_manager.reportError(.semantic, "E002", "Nearby error", nearby_span);
    try testing.expect(!second_reported); // Should be suppressed
    try testing.expect(error_manager.diagnostics.items.len == 1); // No new diagnostic added

    // Report distant error - should not be suppressed
    const distant_span = SourceSpan{
        .start = SourcePosition{ .line = 5, .column = 1, .offset = 200 },
        .end = SourcePosition{ .line = 5, .column = 10, .offset = 209 },
        .file_path = "test.jan",
    };

    const third_reported = try error_manager.reportError(.semantic, "E003", "Distant error", distant_span);
    try testing.expect(third_reported);
    try testing.expect(error_manager.diagnostics.items.len == 2);
}

test "undefined symbol error with suggestions" {
    const allocator = testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    const test_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = SourcePosition{ .line = 1, .column = 8, .offset = 7 },
        .file_path = "test.jan",
    };

    const suggestions = [_][]const u8{ "calculate", "calibrate", "accumulate" };

    const reported = try error_manager.reportUndefinedSymbol("calcualte", test_span, &suggestions);
    try testing.expect(reported);

    // Check diagnostic was created with suggestions
    try testing.expect(error_manager.diagnostics.items.len == 1);

    const diagnostic = &error_manager.diagnostics.items[0];
    try testing.expect(diagnostic.severity == .error);
    try testing.expect(diagnostic.category == .semantic);
    try testing.expect(std.mem.eql(u8, diagnostic.code, "E001"));
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "Undefined symbol 'calcualte'") != null);

    // Check suggestions
    try testing.expect(diagnostic.suggestions.len == 3);
    for (diagnostic.suggestions, 0..) |suggestion, i| {
        try testing.expect(std.mem.indexOf(u8, suggestion.message, suggestions[i]) != null);
        try testing.expect(suggestion.confidence == 0.8);
        try testing.expect(suggestion.replacement_span != null);
        try testing.expect(suggestion.replacement_text != null);
        try testing.expect(std.mem.eql(u8, suggestion.replacement_text.?, suggestions[i]));
    }
}

test "type mismatch error with conversion suggestions" {
    const allocator = testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    const test_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = SourcePosition{ .line = 1, .column = 5, .offset = 4 },
        .file_path = "test.jan",
    };

    // Test type mismatch with possible conversion
    const reported = try error_manager.reportTypeMismatch("i64", "i32", test_span);
    try testing.expect(reported);

    try testing.expect(error_manager.diagnostics.items.len == 1);

    const diagnostic = &error_manager.diagnostics.items[0];
    try testing.expect(diagnostic.severity == .error);
    try testing.expect(diagnostic.category == .type_system);
    try testing.expect(std.mem.eql(u8, diagnostic.code, "E002"));
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "expected 'i64'") != null);
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "found 'i32'") != null);

    // Should have conversion suggestion
    try testing.expect(diagnostic.suggestions.len == 1);
    try testing.expect(std.mem.indexOf(u8, diagnostic.suggestions[0].message, "Consider converting") != null);

    // Test type mismatch without possible conversion
    const test_span2 = SourceSpan{
        .start = SourcePosition{ .line = 2, .column = 1, .offset = 20 },
        .end = SourcePosition{ .line = 2, .column = 5, .offset = 24 },
        .file_path = "test.jan",
    };

    const reported2 = try error_manager.reportTypeMismatch("string", "bool", test_span2);
    try testing.expect(reported2);

    try testing.expect(error_manager.diagnostics.items.len == 2);

    const diagnostic2 = &error_manager.diagnostics.items[1];
    try testing.expect(diagnostic2.suggestions.len == 0); // No conversion possible
}

test "diagnostic formatting and display" {
    const allocator = testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    const test_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 5, .offset = 4 },
        .end = SourcePosition{ .line = 1, .column = 13, .offset = 12 },
        .file_path = "test.jan",
    };

    const source_text = "let calcualte = 42;";

    // Create diagnostic with suggestions
    const suggestions = [_][]const u8{"calculate"};
    const reported = try error_manager.reportUndefinedSymbol("calcualte", test_span, &suggestions);
    try testing.expect(reported);

    // Format the diagnostic
    const formatted = try error_manager.formatDiagnostic(&error_manager.diagnostics.items[0], source_text);
    defer allocator.free(formatted);

    // Check formatted output contains expected elements
    try testing.expect(std.mem.indexOf(u8, formatted, "error[E001]") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Undefined symbol 'calcualte'") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "test.jan:1:5") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "calcualte") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "help:") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "calculate") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "^^^") != null); // Error underline
}

test "error limit and compilation stopping" {
    const allocator = testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    // Set low error limit for testing
    error_manager.max_errors = 3;

    const test_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = SourcePosition{ .line = 1, .column = 5, .offset = 4 },
        .file_path = "test.jan",
    };

    // Report errors up to the limit
    for (0..3) |i| {
        const message = try std.fmt.allocPrint(allocator, "Error {}", .{i});
        defer allocator.free(message);

        const reported = try error_manager.reportError(.semantic, "E001", message, test_span);
        try testing.expect(reported);
    }

    try testing.expect(error_manager.error_count == 3);
    try testing.expect(error_manager.shouldStopCompilation());

    // Additional errors should be rejected
    const additional_reported = try error_manager.reportError(.semantic, "E001", "Additional error", test_span);
    try testing.expect(!additional_reported);
    try testing.expect(error_manager.diagnostics.items.len == 3); // No new diagnostic added
}

test "recovery point management" {
    const allocator = testing.allocator;

    var error_manager = ErrorManager.init(allocator);
    defer error_manager.deinit();

    // Initially no recovery points
    try testing.expect(error_manager.getRecoveryPoint() == null);

    // Create test AST node
    const test_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = SourcePosition{ .line = 5, .column = 1, .offset = 100 },
        .file_path = "test.jan",
    };

    const test_node = source_span_utils.AstNode{
        .kind = .function_declaration,
        .span = test_span,
        .children = &[_]*const source_span_utils.AstNode{},
    };

    // Add recovery points
    try error_manager.addRecoveryPoint(&test_node, .skip_to_semicolon, "function body");
    try error_manager.addRecoveryPoint(&test_node, .skip_to_brace, "block statement");

    try testing.expect(error_manager.recovery_points.items.len == 2);

    // Get most recent recovery point
    const recovery_point = error_manager.getRecoveryPoint();
    try testing.expect(recovery_point != null);
    try testing.expect(recovery_point.?.strategy == .skip_to_brace);
    try testing.expect(std.mem.eql(u8, recovery_point.?.context, "block statement"));
}

test "diagnostic suggestion confidence and ranking" {
    const allocator = testing.allocator;

    // Create diagnostic suggestions with different confidence levels
    var high_confidence = DiagnosticSuggestion{
        .message = try allocator.dupe(u8, "High confidence suggestion"),
        .replacement_span = null,
        .replacement_text = null,
        .confidence = 0.9,
    };
    defer high_confidence.deinit(allocator);

    var medium_confidence = DiagnosticSuggestion{
        .message = try allocator.dupe(u8, "Medium confidence suggestion"),
        .replacement_span = null,
        .replacement_text = null,
        .confidence = 0.6,
    };
    defer medium_confidence.deinit(allocator);

    var low_confidence = DiagnosticSuggestion{
        .message = try allocator.dupe(u8, "Low confidence suggestion"),
        .replacement_span = null,
        .replacement_text = null,
        .confidence = 0.3,
    };
    defer low_confidence.deinit(allocator);

    // Verify confidence levels
    try testing.expect(high_confidence.confidence > medium_confidence.confidence);
    try testing.expect(medium_confidence.confidence > low_confidence.confidence);
    try testing.expect(high_confidence.confidence == 0.9);
    try testing.expect(medium_confidence.confidence == 0.6);
    try testing.expect(low_confidence.confidence == 0.3);
}