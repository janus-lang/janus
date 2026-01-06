// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const semantic_analyzer = @import("semantic_analyzer_only");
const astdb = @import("astdb");
const janus_parser = @import("janus_parser");

// Mock or minimal allocator for tests
const allocator = std.testing.allocator;

test "Core Profile: Rejects 'using' statement" {
    // 1. Setup Parser
    var parser = janus_parser.Parser.init(allocator);
    parser.enableS0(false);
    defer parser.deinit();

    // 2. Parse source with forbidden statement
    // 'using' is parsed at top level but should be rejected in :min
    const source = "using std";

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 3. Initialize Semantic Analyzer with :core profile using SNAPSHOT's DB
    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, snapshot.astdb_system, .core);

    // 4. Analyze and expect error
    var result = analyzer.analyze(@enumFromInt(0));

    if (result) |*info| {
        info.deinit();
        // If it succeeds, that's bad for this test (we want it to reject)
        return error.ExpectedProfileViolation;
    } else |err| {
        // We expect a semantic error (ProfileViolation or similar)
        // For now, allow any error, but ideally verify it's the right one
        std.debug.print("Got expected error: {}\n", .{err});
    }
}

test "Core Profile: Accepts valid code" {
    var parser = janus_parser.Parser.init(allocator);
    parser.enableS0(false);
    defer parser.deinit();

    const source =
        \\func main(allocator: Allocator) {
        \\    print("Hello", allocator)
        \\}
    ;
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, snapshot.astdb_system, .core);
    var info = try analyzer.analyze(@enumFromInt(0));
    defer info.deinit();
}
