// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Semantic = @import("semantic.zig");
const Parser = @import("parser.zig");
const Tokenizer = @import("tokenizer.zig");

// Test helper to create AST from source
fn parseForTest(source: []const u8, allocator: std.mem.Allocator) !*Parser.Node {
    const tokens = try Tokenizer.tokenize(source, allocator);
    defer allocator.free(tokens);
    return Parser.parse(tokens, allocator);
}

test "semantic: simple function analysis" {
    const allocator = testing.allocator;

    const source = "func main() { print(\"Hello\") }";
    const root = try parseForTest(source, allocator);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
    }

    var graph = try Semantic.analyze(root, allocator);
    defer graph.deinit();

    // Should have built-in print and user function main
    try testing.expect(graph.symbols.items.len == 2);

    // Check built-in print function
    const print_symbol = graph.findSymbol("print");
    try testing.expect(print_symbol != null);
    try testing.expect(print_symbol.?.type == .Function);
    try testing.expect(print_symbol.?.kind == .Builtin);

    // Check user-defined main function
    const main_symbol = graph.findSymbol("main");
    try testing.expect(main_symbol != null);
    try testing.expect(main_symbol.?.type == .Function);
    try testing.expect(main_symbol.?.kind == .Function);
}

test "semantic: built-in print function" {
    const allocator = testing.allocator;

    const source = "func test() { print(\"message\") }";
    const root = try parseForTest(source, allocator);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
    }

    var graph = try Semantic.analyze(root, allocator);
    defer graph.deinit();

    // Should successfully analyze print call with string argument
    try testing.expect(graph.symbols.items.len == 2); // print + test

    const print_symbol = graph.findSymbol("print");
    try testing.expect(print_symbol != null);
    try testing.expect(print_symbol.?.kind == .Builtin);
}

test "semantic: type checking for string literals" {
    const allocator = testing.allocator;

    const source = "func example() { print(\"test string\") }";
    const root = try parseForTest(source, allocator);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
    }

    var graph = try Semantic.analyze(root, allocator);
    defer graph.deinit();

    // Should successfully type-check string literal argument to print
    try testing.expect(graph.symbols.items.len == 2);
}

test "semantic: undefined function error" {
    const allocator = testing.allocator;

    const source = "func test() { undefined_func(\"arg\") }";
    const root = try parseForTest(source, allocator);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
    }

    // Should return semantic error for undefined function
    const result = Semantic.analyze(root, allocator);
    try testing.expectError(error.SemanticError, result);
}

test "semantic: empty program" {
    const allocator = testing.allocator;

    const source = "";
    const root = try parseForTest(source, allocator);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
    }

    var graph = try Semantic.analyze(root, allocator);
    defer graph.deinit();

    // Should have only built-in symbols
    try testing.expect(graph.symbols.items.len == 1); // just print

    const print_symbol = graph.findSymbol("print");
    try testing.expect(print_symbol != null);
    try testing.expect(print_symbol.?.kind == .Builtin);
}

test "semantic: symbol table operations" {
    const allocator = testing.allocator;

    var graph = Semantic.SemanticGraph.init(allocator);
    defer graph.deinit();

    // Test adding symbols
    try graph.addSymbol(Semantic.Symbol{
        .name = "test_func",
        .type = .Function,
        .kind = .Function,
    });

    // Test finding symbols
    const symbol = graph.findSymbol("test_func");
    try testing.expect(symbol != null);
    try testing.expectEqualStrings("test_func", symbol.?.name);
    try testing.expect(symbol.?.type == .Function);

    // Test non-existent symbol
    const missing = graph.findSymbol("missing");
    try testing.expect(missing == null);
}

test "semantic: type system" {
    // Test type string representation
    try testing.expectEqualStrings("void", Semantic.Type.Void.toString());
    try testing.expectEqualStrings("string", Semantic.Type.String.toString());
    try testing.expectEqualStrings("function", Semantic.Type.Function.toString());
    try testing.expectEqualStrings("unknown", Semantic.Type.Unknown.toString());
}
