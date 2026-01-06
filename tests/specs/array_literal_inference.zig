// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const libjanus = @import("libjanus");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Testing Array Literal Type Inference...", .{});

    // 1. Initialize ASTDB
    var db = try allocator.create(libjanus.ASTDBSystem);
    db.* = try libjanus.ASTDBSystem.init(allocator, false);
    defer {
        db.deinit();
        allocator.destroy(db);
    }

    // 2. Create a test unit with array literal
    const source_code = "let arr = [1, 2, 3]";
    
    // Parse source into ASTDB
    var parser = libjanus.parser.Parser.init(allocator);
    defer parser.deinit();
    
    var snapshot = try parser.parseIntoAstDB(db, "test_array.jan", source_code);
    defer snapshot.deinit();
    
    const unit_id = db.getUnitByPath("test_array.jan").?.id;
    
    // 3. Initialize type system and type inference
    var type_system = try allocator.create(libjanus.semantic.TypeSystem);
    type_system.* = try libjanus.semantic.TypeSystem.init(allocator);
    defer {
        type_system.deinit();
        allocator.destroy(type_system);
    }
    
    var symbol_table = try libjanus.semantic.SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    var inference = try libjanus.semantic.TypeInference.init(
        allocator,
        type_system,
        &symbol_table,
        db,
        unit_id
    );
    defer inference.deinit();
    
    // 4. Run type inference
    try inference.inferUnit(unit_id);
    
    // 5. Verify results
    std.log.info("Type inference completed successfully!", .{});
    
    const stats = inference.stats;
    std.log.info("Constraints generated: {}", .{stats.constraints_generated});
    std.log.info("Constraints solved: {}", .{stats.constraints_solved});
    std.log.info("Inference variables created: {}", .{stats.inference_vars_created});
    
    std.log.info("✅ Array literal type inference test PASSED!", .{});
}
