// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const semantic_analyzer = @import("semantic_analyzer_only");
const astdb = @import("astdb");
const janus_parser = @import("janus_parser");

const allocator = std.testing.allocator;

test "Semantic Analysis: Recurses into if statement blocks" {
    // 1. Setup Parser
    var parser = janus_parser.Parser.init(allocator);
    parser.enableS0(false);
    defer parser.deinit();

    // 2. Parse source with error inside if block
    const source =
        \\func main() {
        \\    if true {
        \\        print("1", "2", "3") // print takes 2 args, 3 provided -> Error
        \\    }
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 3. Initialize Semantic Analyzer
    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, snapshot.astdb_system, .core);

    // 4. Analyze - Expect Error
    var result = analyzer.analyze(@enumFromInt(0));

    if (result) |*info| {
        info.deinit();
        // If we get here, it means semantic analysis passed, which means it IGNORED the error inside the if block.
        return error.ExpectedSemanticErrorInIfBlock;
    } else |err| {
        try std.testing.expectEqual(error.SemanticError, err);
    }
}

test "Semantic Analysis: Validates if condition type" {
    // 1. Setup Parser
    var parser = janus_parser.Parser.init(allocator);
    parser.enableS0(false);
    defer parser.deinit();

    // 2. Parse source with non-boolean condition
    const source =
        \\func main() {
        \\    if "not bool" {
        \\        print("ok", allocator)
        \\    }
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, snapshot.astdb_system, .core);

    var result = analyzer.analyze(@enumFromInt(0));

    if (result) |*info| {
        info.deinit();
        return error.ExpectedTypeMismatchInIfCondition;
    } else |err| {
        try std.testing.expectEqual(error.SemanticError, err);
    }
}
