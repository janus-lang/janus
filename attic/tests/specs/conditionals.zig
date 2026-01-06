// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb");
const janus_parser = @import("janus_parser");
const ir_generator = @import("libjanus_ir_generator");
const astdb_binder = @import("astdb_binder");

test "IR: Basic If Statement" {
    const A = testing.allocator;
    const source =
        \\func main(x: i32) {
        \\    if x == 1 {
        \\        print("is one")
        \\    }
        \\}
    ;

    var db_system = try astdb.AstDB.init(A, true);
    defer db_system.deinit();

    const unit_id = try db_system.addUnit("test.jan", source);

    var p = janus_parser.Parser.init(A);
    defer p.deinit();

    var snapshot = try p.parseIntoAstDB(&db_system, "test.jan", source);
    try astdb_binder.bindUnit(&db_system, unit_id);
    defer snapshot.deinit();

    var ir_gen = try ir_generator.IRGenerator.init(A, &snapshot, &db_system);
    defer ir_gen.deinit();

    // Find the main function declaration
    // In this simple test, it's likely the first declaration
    const main_decl_id: astdb.DeclId = @enumFromInt(0);

    const ir = try ir_gen.generateIR(unit_id, main_decl_id);
    var mut_ir = ir;
    defer mut_ir.deinit(A);

    // Verify IR contains branching
    var has_conditional_branch = false;
    for (ir.basic_blocks) |block| {
        if (block.terminator) |term| {
            if (term == .conditional_branch) {
                has_conditional_branch = true;
            }
        }
    }

    try testing.expect(has_conditional_branch);
}

test "IR: If-Else Statement" {
    const A = testing.allocator;
    const source =
        \\func main(x: i32) {
        \\    if x == 1 {
        \\        print("is one")
        \\    } else {
        \\        print("is not one")
        \\    }
        \\}
    ;

    var db_system = try astdb.AstDB.init(A, true);
    defer db_system.deinit();

    const unit_id = try db_system.addUnit("test.jan", source);

    var p = janus_parser.Parser.init(A);
    defer p.deinit();

    var snapshot = try p.parseIntoAstDB(&db_system, "test.jan", source);
    try astdb_binder.bindUnit(&db_system, unit_id);
    defer snapshot.deinit();

    var ir_gen = try ir_generator.IRGenerator.init(A, &snapshot, &db_system);
    defer ir_gen.deinit();

    const main_decl_id: astdb.DeclId = @enumFromInt(0);

    const ir = try ir_gen.generateIR(unit_id, main_decl_id);
    var mut_ir = ir;
    defer mut_ir.deinit(A);

    try testing.expect(ir.basic_blocks.len >= 3); // entry, true, false, merge
}
