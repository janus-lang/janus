// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb");
const SemanticAnalyzer = @import("semantic_analyzer_only").SemanticAnalyzer;
const Parser = @import("janus_parser").Parser;

test "Semantic: Range Integers OK" {
    const A = testing.allocator;
    const source = "func main() { let r = 1..10 }";

    var db_system = try astdb.AstDB.init(A, true);
    defer db_system.deinit();

    const unit_id = try db_system.addUnit("test.jan", source);
    var p = Parser.init(A);
    defer p.deinit();

    _ = try p.parseIntoAstDB(&db_system, "test.jan", source);

    var sema = SemanticAnalyzer.init(A, &db_system, .core);
    var info = try sema.analyze(unit_id);
    defer info.deinit();
}

test "Semantic: Exclusive Range Integers OK" {
    const A = testing.allocator;
    const source = "func main() { let r = 1..<10 }";

    var db_system = try astdb.AstDB.init(A, true);
    defer db_system.deinit();

    const unit_id = try db_system.addUnit("test.jan", source);
    var p = Parser.init(A);
    defer p.deinit();

    _ = try p.parseIntoAstDB(&db_system, "test.jan", source);

    var sema = SemanticAnalyzer.init(A, &db_system, .core);
    var info = try sema.analyze(unit_id);
    defer info.deinit();
}

test "Semantic: Range Non-Integer Checks" {
    const A = testing.allocator;
    const sources = [_][]const u8{
        "func main() { let r = \"a\"..10 }",
        "func main() { let r = 1..\"b\" }",
        "func main() { let r = \"a\"..\"b\" }",
    };

    for (sources) |src| {
        var db_system = try astdb.AstDB.init(A, true);
        defer db_system.deinit();

        const unit_id = try db_system.addUnit("test.jan", src);
        var p = Parser.init(A);
        defer p.deinit();

        _ = try p.parseIntoAstDB(&db_system, "test.jan", src);

        var sema = SemanticAnalyzer.init(A, &db_system, .core);
        try testing.expectError(error.SemanticError, sema.analyze(unit_id));
    }
}
