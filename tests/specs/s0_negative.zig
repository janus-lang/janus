// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const region = @import("region");
const astdb_core = @import("astdb");

fn parseS0(source: []const u8, A: std.mem.Allocator) !void {
    var interner = astdb_core.StrInterner.initWithMode(A, true);
    defer interner.deinit();
    var lx = region.RegionLexer.init(A, source, &interner);
    defer lx.deinit();
    try lx.tokenize();
    const toks = lx.getTokens();
    var rp = region.RegionParser.init(A, toks, &interner);
    defer rp.deinit();
    rp.enableS0(true);
    _ = try rp.parse();
}

fn expectS0ErrorMessage(source: []const u8, expected: []const u8) !void {
    const A = testing.allocator;
    var interner = astdb_core.StrInterner.initWithMode(A, true);
    defer interner.deinit();
    var lx = try region.RegionLexer.init(A, source, &interner);
    defer lx.deinit();
    try lx.tokenize();
    const toks = lx.getTokens();
    var rp = region.RegionParser.init(A, toks, &interner);
    defer rp.deinit();
    rp.enableS0(true);
    const result = rp.parse();
    try testing.expectError(error.ParseError, result);
    try testing.expect(rp.diagnostics.items.len > 0);
    const msg = interner.getString(rp.diagnostics.items[0].message);
    try testing.expect(std.mem.eql(u8, msg, expected));
}

fn expectS0ErrorContains(source: []const u8, needle: []const u8) !void {
    const A = testing.allocator;
    var interner = astdb_core.StrInterner.initWithMode(A, true);
    defer interner.deinit();
    var lx = try region.RegionLexer.init(A, source, &interner);
    defer lx.deinit();
    try lx.tokenize();
    const toks = lx.getTokens();
    var rp = region.RegionParser.init(A, toks, &interner);
    defer rp.deinit();
    rp.enableS0(true);
    const result = rp.parse();
    try testing.expectError(error.ParseError, result);
    try testing.expect(rp.diagnostics.items.len > 0);
    const msg = interner.getString(rp.diagnostics.items[0].message);
    try testing.expect(std.mem.indexOf(u8, msg, needle) != null);
}

test "S0 negative: named arguments are rejected" {
    const A = testing.allocator;
    // Named arg in call: print(msg: "hi")
    try testing.expectError(error.ParseError, parseS0("func main() { print(msg: \"hi\") }", A));
}

test "S0 negative: trailing blocks are rejected" {
    const A = testing.allocator;
    // Trailing block after call
    try testing.expectError(error.ParseError, parseS0("func main() { print(\"x\") { |v| v } }", A));
}

test "S0 negative: non-S0 operators are rejected" {
    const A = testing.allocator;
    // Use addition operator in expression
    try testing.expectError(error.ParseError, parseS0("func main() { print(1+2) }", A));
}

test "S0 negative: array and table literals are rejected" {
    const A = testing.allocator;
    try testing.expectError(error.ParseError, parseS0("func main() { print([1,2]) }", A));
    try testing.expectError(error.ParseError, parseS0("func main() { print({a:1}) }", A));
}

test "S0 diagnostics: parameters are rejected with explicit message" {
    try expectS0ErrorMessage("func main(x) {}", "S0: parameters are not allowed");
}

test "S0 diagnostics: return types are rejected with explicit message" {
    try expectS0ErrorMessage("func main() -> i32 {}", "S0: return types are not allowed");
}

test "S0 diagnostics: statement reports token name" {
    try expectS0ErrorContains("func main() { let x = 1 }", "let");
}

test "S0 diagnostics: literal expression statements are rejected" {
    try expectS0ErrorMessage("func main() { 42 }", "S0: expression statements must be identifier references or calls");
}

test "S0 diagnostics: named arguments produce dedicated message" {
    try expectS0ErrorMessage("func main() { print(msg: \"hi\") }", "S0: named arguments are not allowed");
}

test "S0 positive: identifier expression statements are allowed" {
    const source = "func main() { task }";
    const A = testing.allocator;
    var interner = astdb_core.StrInterner.initWithMode(A, true);
    defer interner.deinit();
    var lx = try region.RegionLexer.init(A, source, &interner);
    defer lx.deinit();
    try lx.tokenize();
    const toks = lx.getTokens();
    var rp = region.RegionParser.init(A, toks, &interner);
    defer rp.deinit();
    rp.enableS0(true);
    _ = try rp.parse();
    try testing.expectEqual(@as(usize, 0), rp.diagnostics.items.len);
}

test "S0 positive: call expression statements are allowed" {
    const source = "func main() { print(\"hi\") }";
    const A = testing.allocator;
    var interner = astdb_core.StrInterner.initWithMode(A, true);
    defer interner.deinit();
    var lx = try region.RegionLexer.init(A, source, &interner);
    defer lx.deinit();
    try lx.tokenize();
    const toks = lx.getTokens();
    var rp = region.RegionParser.init(A, toks, &interner);
    defer rp.deinit();
    rp.enableS0(true);
    _ = try rp.parse();
    try testing.expectEqual(@as(usize, 0), rp.diagnostics.items.len);
}
