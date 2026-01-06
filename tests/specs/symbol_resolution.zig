// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const libjanus = @import("libjanus");
const astdb = libjanus.astdb;
const semantic = libjanus.semantic;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Testing Symbol Resolution...", .{});

    // 1. Initialize ASTDB
    var db = try allocator.create(libjanus.ASTDBSystem);
    db.* = try libjanus.ASTDBSystem.init(allocator, false);
    defer {
        db.deinit();
        allocator.destroy(db);
    }

    // 2. Parse source
    const source_code = "func add(a, b) { return a + b }";
    
    var parser = libjanus.parser.Parser.init(allocator);
    defer parser.deinit();
    
    var snapshot = try parser.parseIntoAstDB(db, "test_unit.jan", source_code);
    defer snapshot.deinit();
    
    const unit_id = db.getUnitByPath("test_unit.jan").?.id;
    
    // 4. Initialize Symbol Resolver
    var resolver = try semantic.SymbolResolver.init(allocator, db);
    defer resolver.deinit();
    
    // 5. Run Resolution
    try resolver.resolveUnit(unit_id);
    
    // 6. Verify Symbols
    std.log.info("Verifying symbols...", .{});
    
    // Check 'add' function symbol
    const add_sym = resolver.symbol_table.lookup("add");
    if (add_sym) |sym| {
        std.log.info("Found symbol 'add': kind={}", .{sym.kind});
        if (sym.kind != .function) return error.TestFailed;
    } else {
        std.log.err("Symbol 'add' not found", .{});
        return error.TestFailed;
    }
    
    // Check parameters 'a' and 'b' should NOT be in global scope
    if (resolver.symbol_table.lookup("a") != null) {
        std.log.err("Symbol 'a' leaked to global scope", .{});
        return error.TestFailed;
    }
    
    std.log.info("Symbol resolution test passed!", .{});
}
