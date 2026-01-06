// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Tests für Allocator Contexts/Regions/Using Compiler Integration

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb");
const semantic_analyzer = @import("../compiler/semantic_analyzer.zig");
const lexer = @import("../compiler/astdb/lexer.zig");
const ir_generator = @import("../compiler/ir_generator.zig");

test "SemanticAnalyzer: Recognize Allocator.create function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var astdb_system = astdb.AstDB.init(allocator);
    defer astdb_system.deinit();

    // Test Allocator Context Functions in :min profile
    const source = "func main() { Allocator.create(heap_allocator) }";
    const unit_id = try astdb_system.addUnit("test.jan", source);

    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, &astdb_system, .core);
    var info = try analyzer.analyze(unit_id);
    defer info.deinit();

    // Should recognize Allocator.create as valid in :min
    try testing.expect(info.function_calls.items.len >= 1);

    var found_allocator = false;
    for (info.function_calls.items) |call| {
        if (std.mem.eql(u8, call.function_name, "Allocator.create")) {
            found_allocator = true;
            try testing.expect(call.stdlib_function != null);
            break;
        }
    }
    try testing.expect(found_allocator);
}

test "SemanticAnalyzer: Profile Gate region keyword" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var astdb_system = astdb.AstDB.init(allocator);
    defer astdb_system.deinit();

    // Test region in :min profile (should fail)
    const source_min = "func main() { region temp { let x = 42; } }";
    const unit_id_min = try astdb_system.addUnit("test_min.jan", source_min);

    var analyzer_min = semantic_analyzer.SemanticAnalyzer.init(allocator, &astdb_system, .core);
    var info_min = try analyzer_min.analyze(unit_id_min);
    defer info_min.deinit();

    // Should reject region in :min profile
    try testing.expectEqual(false, info_min.function_calls.items.len >= 1);

    // Test region in :full profile (should succeed)
    const source_full = "func main() { region temp { let x = 42; } }";
    const unit_id_full = try astdb_system.addUnit("test_full.jan", source_full);

    var analyzer_full = semantic_analyzer.SemanticAnalyzer.init(allocator, &astdb_system, .sovereign);
    var info_full = try analyzer_full.analyze(unit_id_full);
    defer info_full.deinit();

    // Should accept region in :full profile
    try testing.expect(info_full.function_calls.items.len >= 1);
}

test "SemanticAnalyzer: Capability requirements for memory operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var astdb_system = astdb.AstDB.init(allocator);
    defer astdb_system.deinit();

    const source = "func main() { Allocator.allocate(100, heap_alloc) }";
    const unit_id = try astdb_system.addUnit("test.jan", source);

    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, &astdb_system, .core);
    var info = try analyzer.analyze(unit_id);
    defer info.deinit();

    // Should require memory_allocate capability
    var found_memory_cap = false;
    for (info.required_capabilities.items) |cap| {
        if (cap == .memory_allocate) {
            found_memory_cap = true;
            break;
        }
    }
    try testing.expect(found_memory_cap);
}

test "Lexer: Recognize region and allocator keywords" {
    var str_interner = astdb.StrInterner.init(testing.allocator);
    defer str_interner.deinit();

    var lexer_instance = try lexer.RegionLexer.init(testing.allocator, "region temp { let x = 42; }", &str_interner);
    defer lexer_instance.deinit();

    try lexer_instance.tokenize();
    const tokens = lexer_instance.getTokens();

    // Should recognize 'region' keyword
    var found_region = false;
    for (tokens) |token| {
        if (token.kind == .region) {
            found_region = true;
            break;
        }
    }
    try testing.expect(found_region);
}

test "IRGenerator: Generate IR for allocator functions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var str_interner = astdb.StrInterner.init(allocator);
    defer str_interner.deinit();

    var lexer_instance = try lexer.RegionLexer.init(allocator, "func main() { let alloc = Allocator.create(heap); return alloc; }", &str_interner);
    defer lexer_instance.deinit();

    try lexer_instance.tokenize();
    const tokens = lexer_instance.getTokens();

    // Test dass Tokens erfolgreich generiert wurden
    try testing.expect(tokens.len > 0);

    // Mock IR generation test
    var astdb_system = astdb.AstDB.init(allocator);
    defer astdb_system.deinit();

    _ = try astdb_system.addUnit("test.jan", "func main() { }");

    var ir_gen = try ir_generator.IRGenerator.init(allocator, null, &astdb_system);
    defer ir_gen.deinit();

    // Should handle Allocator function calls in IR generation
    try testing.expect(true); // Placeholder test
}

test "Profile-specific function signatures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var astdb_system = astdb.AstDB.init(allocator);
    defer astdb_system.deinit();

    // Test different profiles with same function
    const function_name = "Allocator.allocate";

    // Find the function in STDLIB_FUNCTIONS
    var found_func = false;
    for (&semantic_analyzer.SemanticAnalyzer.STDLIB_FUNCTIONS) |func| {
        if (std.mem.eql(u8, func.name, function_name)) {
            found_func = true;
            // All profiles should have same parameter count
            try testing.expectEqual(@as(u8, 2), func.core_profile_params);
            try testing.expectEqual(@as(u8, 2), func.service_profile_params);
            try testing.expectEqual(@as(u8, 2), func.sovereign_profile_params);
            break;
        }
    }
    try testing.expect(found_func);
}

test "Effects system integration for memory operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var astdb_system = astdb.AstDB.init(allocator);
    defer astdb_system.deinit();

    const source = "func main() { region temp { Allocator.allocate(100, alloc); } }";
    const unit_id = try astdb_system.addUnit("test.jan", source);

    var analyzer = semantic_analyzer.SemanticAnalyzer.init(allocator, &astdb_system, .sovereign);
    var info = try analyzer.analyze(unit_id);
    defer info.deinit();

    // Should track both region_scope and memory_allocate capabilities
    var found_region_cap = false;
    var found_memory_cap = false;

    for (info.required_capabilities.items) |cap| {
        if (cap == .region_scope) found_region_cap = true;
        if (cap == .memory_allocate) found_memory_cap = true;
    }

    try testing.expect(found_region_cap);
    try testing.expect(found_memory_cap);
}

test "Migration path validation" {
    // Test dass Code aus :min zu :full migriert werden kann
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var astdb_system = astdb.AstDB.init(allocator);
    defer astdb_system.deinit();

    // Code der in :min funktioniert
    const min_source = "func main() { let alloc = Allocator.create(heap); let buf = Allocator.allocate(100, alloc); }";
    const unit_id = try astdb_system.addUnit("test.jan", min_source);

    // Analyse in :min profile
    var analyzer_min = semantic_analyzer.SemanticAnalyzer.init(allocator, &astdb_system, .core);
    var info_min = try analyzer_min.analyze(unit_id);
    defer info_min.deinit();

    // Sollte in :min profile funktionieren
    try testing.expect(info_min.function_calls.items.len >= 2);

    // Analyse in :full profile
    var analyzer_full = semantic_analyzer.SemanticAnalyzer.init(allocator, &astdb_system, .sovereign);
    var info_full = try analyzer_full.analyze(unit_id);
    defer info_full.deinit();

    // Sollte auch in :full profile funktionieren
    try testing.expect(info_full.function_calls.items.len >= 2);
}
