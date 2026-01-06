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

    std.log.info("Testing Type Checking...", .{});

    // 1. Initialize ASTDB
    var db = try libjanus.ASTDBSystem.init(allocator);
    defer db.deinit();

    // 2. Create a dummy compilation unit
    const unit_id = try db.createUnit("test_unit");
    
    // 3. Parse code with type error: foo expects 1 arg, gets 2
    const source_code = "func foo(x) {} func main() { foo(1, 2) }";
    
    var tokenizer = libjanus.tokenizer.Tokenizer.init(source_code);
    var parser = libjanus.parser.Parser.init(allocator, &tokenizer, &db, unit_id);
    defer parser.deinit();
    
    try parser.parse();
    
    // 4. Initialize Symbol Resolver and Type Checker
    var symbol_table = try semantic.SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    var resolver = try semantic.SymbolResolver.init(allocator, &db, &symbol_table);
    defer resolver.deinit();
    
    var checker = try semantic.TypeChecker.init(allocator, &db, &symbol_table);
    defer checker.deinit();
    
    // 5. Run Resolution first
    try resolver.resolveUnit(unit_id);
    
    // 6. Run Type Checking
    try checker.checkUnit(unit_id);
    
    // 7. Verify Diagnostics
    std.log.info("Verifying diagnostics...", .{});
    
    if (checker.diagnostics.items.len == 0) {
        std.log.err("Expected type error, but got none", .{});
        return error.TestFailed;
    }
    
    const diag = checker.diagnostics.items[0];
    std.log.info("Found diagnostic: kind={}, message='{s}'", .{diag.kind, diag.message});
    
    if (diag.kind != .invalid_call) {
        std.log.err("Expected invalid_call error, got {}", .{diag.kind});
        return error.TestFailed;
    }
    
    // Check message content
    if (std.mem.indexOf(u8, diag.message, "expects 1 arguments, but got 2") == null) {
        std.log.err("Unexpected error message", .{});
        return error.TestFailed;
    }
    
    std.log.info("Type checking test passed!", .{});
}
