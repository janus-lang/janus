// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const bootstrap_s0 = @import("bootstrap_s0");
const region = @import("region");
const SemanticAnalyzer = @import("semantic_analyzer_only").SemanticAnalyzer;
const astdb = @import("astdb");

test "S0 gate defaults to enabled" {
    try testing.expect(bootstrap_s0.isEnabled());
}

test "S0 gate scoped guard restores previous state" {
    const original = bootstrap_s0.isEnabled();
    var guard = bootstrap_s0.scoped(!original);
    try testing.expectEqual(!original, bootstrap_s0.isEnabled());
    guard.deinit();
    try testing.expectEqual(original, bootstrap_s0.isEnabled());
}

test "RegionParser inherits global S0 gate" {
    var str_interner = astdb.StrInterner.initWithMode(testing.allocator, true);
    defer str_interner.deinit();

    const main_id = try str_interner.intern("main");
    const param_id = try str_interner.intern("x");
    const type_id = try str_interner.intern("i32");

    var tokens = [_]region.Token{
        .{ .kind = .func, .str = null, .span = .{ .start = 0, .end = 4, .line = 1, .column = 1 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .identifier, .str = main_id, .span = .{ .start = 5, .end = 9, .line = 1, .column = 6 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .left_paren, .str = null, .span = .{ .start = 9, .end = 10, .line = 1, .column = 10 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .identifier, .str = param_id, .span = .{ .start = 10, .end = 11, .line = 1, .column = 11 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .colon, .str = null, .span = .{ .start = 11, .end = 12, .line = 1, .column = 12 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .identifier, .str = type_id, .span = .{ .start = 12, .end = 15, .line = 1, .column = 13 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .right_paren, .str = null, .span = .{ .start = 15, .end = 16, .line = 1, .column = 16 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .left_brace, .str = null, .span = .{ .start = 17, .end = 18, .line = 1, .column = 18 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .right_brace, .str = null, .span = .{ .start = 18, .end = 19, .line = 1, .column = 19 }, .trivia_lo = 0, .trivia_hi = 0 },
        .{ .kind = .eof, .str = null, .span = .{ .start = 19, .end = 19, .line = 1, .column = 20 }, .trivia_lo = 0, .trivia_hi = 0 },
    };

    {
        var guard = bootstrap_s0.scoped(true);
        defer guard.deinit();
        var parser = region.RegionParser.init(testing.allocator, &tokens, &str_interner);
        defer parser.deinit();
        try testing.expectError(error.ParseError, parser.parse());
    }

    {
        var guard = bootstrap_s0.scoped(false);
        defer guard.deinit();
        var parser = region.RegionParser.init(testing.allocator, &tokens, &str_interner);
        defer parser.deinit();
        _ = try parser.parse();
    }
}

test "SemanticAnalyzer init respects S0 gate" {
    var db = astdb.AstDB.initWithMode(testing.allocator, true);
    defer db.deinit();

    {
        var guard = bootstrap_s0.scoped(true);
        defer guard.deinit();
        const analyzer = SemanticAnalyzer.init(testing.allocator, &db, .service);
        try testing.expectEqual(.core, analyzer.profile);
    }

    {
        var guard = bootstrap_s0.scoped(false);
        defer guard.deinit();
        const analyzer = SemanticAnalyzer.init(testing.allocator, &db, .service);
        try testing.expectEqual(.service, analyzer.profile);
    }
}
