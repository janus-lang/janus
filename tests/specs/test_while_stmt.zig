// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const semantic_analyzer = @import("semantic_analyzer_only");
const astdb = @import("astdb");
const janus_parser = @import("janus_parser");

const allocator = std.testing.allocator;

test "Semantic Analysis: Validates while condition type" {
    var parser = janus_parser.Parser.init(allocator);
    parser.enableS0(false);
    defer parser.deinit();

    const source =
        \\func main() {
        \\    while "not bool" {
        \\        print("loop", allocator)
        \\    }
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, snapshot.astdb_system, .core);

    var result = analyzer.analyze(@enumFromInt(0));

    if (result) |*info| {
        info.deinit();
        return error.ExpectedTypeMismatchInWhileCondition;
    } else |err| {
        try std.testing.expectEqual(error.SemanticError, err);
    }
}
