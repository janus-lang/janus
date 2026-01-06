// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const semantic_analyzer = @import("semantic_analyzer_only");
const astdb = @import("astdb");
const janus_parser = @import("janus_parser");

const allocator = std.testing.allocator;

test "Type Checking: Rejects mismatching argument types" {
    // 1. Setup Parser
    var parser = janus_parser.Parser.init(allocator);
    parser.enableS0(false);
    defer parser.deinit();

    // 2. Parse source with type mismatch
    // print expects (string, Allocator) in :min
    // We pass (bool, Allocator) - wait, getting an Allocator is hard in test snippet.
    // Let's use print(string, Allocator) vs print(string, string)

    // Valid: print("Hello", allocator)
    // Invalid: print("Hello", "World") -> 2nd arg should be Allocator

    const source =
        \\func main(allocator: Allocator) {
        \\    print("Hello", "World")
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 3. Initialize Semantic Analyzer
    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, snapshot.astdb_system, .core);

    // 4. Analyze
    var result = analyzer.analyze(@enumFromInt(0));

    // We expect failure (SemanticError)
    if (result) |*info| {
        info.deinit();
        return error.ExpectedTypeMismatch;
    } else |err| {
        // ideally check err == error.SemanticError or similar
        std.debug.print("Got expected error: {}\n", .{err});
    }
}
