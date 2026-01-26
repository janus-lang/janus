// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const semantic_analyzer = @import("semantic_analyzer_only");
const astdb = @import("astdb");
const janus_parser = @import("janus_parser");

const allocator = std.testing.allocator;

test "Semantic Analysis: Tracks variable declarations" {
    // 1. Setup Parser
    var parser = janus_parser.Parser.init(allocator);
    parser.enableS0(false);
    defer parser.deinit();

    // 2. Parse source with variable declaration
    const source =
        \\func main() {
        \\    var x: i32 = 42
        \\    let y = "hello"
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 3. Initialize Semantic Analyzer
    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, snapshot.astdb_system, .core);

    // 4. Analyze
    var result = try analyzer.analyze(@enumFromInt(0));
    defer result.deinit();

    // 5. Verify results
    try std.testing.expectEqual(@as(usize, 2), result.variable_declarations.items.len);

    const var_x = result.variable_declarations.items[0];
    try std.testing.expectEqualStrings("x", var_x.variable_name);
    try std.testing.expectEqualStrings("i32", var_x.type_name);

    const var_y = result.variable_declarations.items[1];
    try std.testing.expectEqualStrings("y", var_y.variable_name);
    try std.testing.expectEqualStrings("string", var_y.type_name); // inferred
}

test "Semantic Analysis: Detects type mismatch in declaration" {
    // 1. Setup Parser
    var parser = janus_parser.Parser.init(allocator);
    parser.enableS0(false);
    defer parser.deinit();

    // 2. Parse source with mismatch
    // var x: i32 = "string"
    const source =
        \\func main() {
        \\    var x: i32 = "string"
        \\}
    ;

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, snapshot.astdb_system, .core);

    var result = analyzer.analyze(@enumFromInt(0));
    // Expect error
    if (result) |*info| {
        info.deinit();
        return error.ExpectedTypeMismatch;
    } else |err| {
        try std.testing.expectEqual(error.SemanticError, err);
    }
}
