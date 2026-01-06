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

    std.log.info("Testing Symbol Resolution for Calls...", .{});

    // 1. Initialize ASTDB
    var db = try allocator.create(libjanus.ASTDBSystem);
    db.* = try libjanus.ASTDBSystem.init(allocator, false);
    defer {
        db.deinit();
        allocator.destroy(db);
    }

    // 2. Parse source with function declaration and call
    const source_code = 
        \\func add(a, b) { return a + b }
        \\func main() { 
        \\    add(1, 2)
        \\    undefined_func()
        \\}
    ;
    
    var parser = libjanus.parser.Parser.init(allocator);
    defer parser.deinit();
    
    var snapshot = try parser.parseIntoAstDB(db, "test_calls.jan", source_code);
    defer snapshot.deinit();
    
    const unit_id = db.getUnitByPath("test_calls.jan").?.id;
    
    // 4. Initialize Symbol Resolver
    var resolver = try semantic.SymbolResolver.init(allocator, db);
    defer resolver.deinit();
    
    // 5. Run Resolution
    try resolver.resolveUnit(unit_id);
    
    // 6. Verify Diagnostics
    const diagnostics = resolver.getDiagnostics();
    var found_undefined = false;
    
    for (diagnostics) |diag| {
        std.log.info("Diagnostic: {s}", .{diag.message});
        if (std.mem.indexOf(u8, diag.message, "Undefined symbol 'undefined_func'") != null) {
            found_undefined = true;
        }
    }
    
    if (!found_undefined) {
        std.log.err("Failed to report undefined symbol 'undefined_func'", .{});
        return error.TestFailed;
    }
    
    // Check stats
    const stats = resolver.getStatistics();
    std.log.info("Stats: decls={}, resolved={}, undefined={}", .{
        stats.declarations_collected, 
        stats.references_resolved, 
        stats.undefined_references
    });
    
    // We expect:
    // Decls: add, main, a, b (params of add) -> 4
    // Resolved: add (in main), a (in add), b (in add) -> 3
    // Undefined: undefined_func -> 1
    
    if (stats.undefined_references != 1) {
        std.log.err("Expected 1 undefined reference, found {}", .{stats.undefined_references});
        return error.TestFailed;
    }
    
    std.log.info("Symbol resolution call test passed!", .{});
}
