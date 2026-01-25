// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Tests for the unified compiler error framework
//!
//! Verifies that:
//! - DiagnosticCollector aggregates errors correctly
//! - Tokenizer reports lexical errors to the collector
//! - Error codes follow the L/P/S/C convention

const std = @import("std");
const testing = std.testing;
const compiler_errors = @import("compiler_errors");
const janus_tokenizer = @import("janus_tokenizer");

test "DiagnosticCollector: basic error aggregation" {
    const allocator = testing.allocator;

    var collector = compiler_errors.DiagnosticCollector.init(allocator);
    defer collector.deinit();

    // Add multiple errors
    const span1 = compiler_errors.SourceSpan{
        .file = "test.jan",
        .start = .{ .line = 1, .column = 5, .byte_offset = 4 },
        .end = .{ .line = 1, .column = 6, .byte_offset = 5 },
    };
    _ = try collector.addError(.lexer, @intFromEnum(compiler_errors.LexerError.invalid_character), span1, "unexpected character '@'");

    const span2 = compiler_errors.SourceSpan{
        .file = "test.jan",
        .start = .{ .line = 3, .column = 1, .byte_offset = 20 },
        .end = .{ .line = 3, .column = 15, .byte_offset = 34 },
    };
    _ = try collector.addError(.lexer, @intFromEnum(compiler_errors.LexerError.unterminated_string), span2, "unterminated string literal");

    // Verify counts
    try testing.expectEqual(@as(u32, 2), collector.error_count);
    try testing.expectEqual(@as(usize, 2), collector.count());
    try testing.expect(collector.hasErrors());
}

test "DiagnosticCollector: warning handling" {
    const allocator = testing.allocator;

    var collector = compiler_errors.DiagnosticCollector.init(allocator);
    defer collector.deinit();

    const span = compiler_errors.SourceSpan{};
    _ = try collector.addWarning(.semantic, 11, span, "unreachable code");

    try testing.expectEqual(@as(u32, 0), collector.error_count);
    try testing.expectEqual(@as(u32, 1), collector.warning_count);
    try testing.expect(!collector.hasErrors());
}

test "Diagnostic: error code formatting" {
    const allocator = testing.allocator;

    var diag = compiler_errors.Diagnostic.init(
        allocator,
        .parser,
        2,
        .@"error",
        .{},
        "expected expression",
    );
    defer diag.deinit();

    var buf: [6]u8 = undefined;
    const code = diag.codeString(&buf);
    try testing.expectEqualStrings("P0002", code);
}

test "Tokenizer: reports invalid character to diagnostics" {
    const allocator = testing.allocator;

    var collector = compiler_errors.DiagnosticCollector.init(allocator);
    defer collector.deinit();

    // Source with invalid character
    const source = "let x = @invalid";

    var tok = janus_tokenizer.Tokenizer.init(allocator, source);
    defer tok.deinit();
    tok.setDiagnostics(&collector);
    tok.setFilename("test.jan");

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Should have reported the @ character as invalid
    try testing.expect(collector.hasErrors());
    try testing.expectEqual(@as(u32, 1), collector.error_count);
}

test "Tokenizer: reports unterminated string to diagnostics" {
    const allocator = testing.allocator;

    var collector = compiler_errors.DiagnosticCollector.init(allocator);
    defer collector.deinit();

    // Source with unterminated string
    const source = "let msg = \"hello";

    var tok = janus_tokenizer.Tokenizer.init(allocator, source);
    defer tok.deinit();
    tok.setDiagnostics(&collector);
    tok.setFilename("test.jan");

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Should have reported unterminated string
    try testing.expect(collector.hasErrors());
    try testing.expectEqual(@as(u32, 1), collector.error_count);

    // Verify the error is the right type
    try testing.expectEqual(@as(usize, 1), collector.diagnostics.items.len);
    const diag = collector.diagnostics.items[0];
    try testing.expectEqual(compiler_errors.Phase.lexer, diag.phase);
    try testing.expectEqual(@intFromEnum(compiler_errors.LexerError.unterminated_string), diag.code);
}

test "Tokenizer: valid source produces no errors" {
    const allocator = testing.allocator;

    var collector = compiler_errors.DiagnosticCollector.init(allocator);
    defer collector.deinit();

    // Valid Janus source
    const source = "let x = 42\nlet y = x + 1";

    var tok = janus_tokenizer.Tokenizer.init(allocator, source);
    defer tok.deinit();
    tok.setDiagnostics(&collector);

    const tokens = try tok.tokenize();
    defer allocator.free(tokens);

    // Should have no errors
    try testing.expect(!collector.hasErrors());
    try testing.expectEqual(@as(u32, 0), collector.error_count);

    // Should have produced tokens
    try testing.expect(tokens.len > 0);
}

test "DiagnosticCollector: source line extraction" {
    const allocator = testing.allocator;

    var collector = compiler_errors.DiagnosticCollector.init(allocator);
    defer collector.deinit();

    // Register source
    try collector.registerSource("test.jan", "line 1\nline 2 with error\nline 3");

    const span = compiler_errors.SourceSpan{
        .file = "test.jan",
        .start = .{ .line = 2, .column = 11, .byte_offset = 17 },
        .end = .{ .line = 2, .column = 16, .byte_offset = 22 },
    };

    const diag = try collector.addError(.parser, 1, span, "unexpected token 'error'");

    // Source line should be attached
    try testing.expect(diag.source_line != null);
    try testing.expectEqualStrings("line 2 with error", diag.source_line.?);
}
