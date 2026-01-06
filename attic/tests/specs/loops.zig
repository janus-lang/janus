// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const ir_generator = @import("libjanus_ir_generator");
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb");
const astdb_bind = @import("astdb_binder");
const JanusIR = ir_generator.JanusIR;

test "IR: While Loop with Counter" {
    const allocator = std.testing.allocator;

    // Setup
    var db_system = try astdb_core.AstDB.init(allocator, true);
    defer db_system.deinit();

    var parser_instance = janus_parser.Parser.init(allocator);
    defer parser_instance.deinit();

    const source =
        \\func count() do
        \\    let i = 0
        \\    while i < 10 do
        \\        i = i + 1
        \\    end
        \\    return i
        \\end
    ;

    var snapshot = try parser_instance.parseIntoAstDB(&db_system, "test_loop.jan", source);
    defer snapshot.deinit();

    const unit_id = snapshot.core_snapshot.astdb.units.items[0].id;
    try astdb_bind.bindUnit(&db_system, unit_id);

    var ir_gen = try ir_generator.IRGenerator.init(allocator, &snapshot, &db_system);
    defer ir_gen.deinit();

    // Find main function
    var main_decl_id: ?astdb_core.DeclId = null;
    const unit = snapshot.core_snapshot.astdb.units.items[0];

    if (unit.decls.len > 0) {
        for (unit.decls, 0..) |decl, index| {
            if (decl.kind == .function) {
                main_decl_id = @enumFromInt(index);
                break;
            }
        }
    }

    if (main_decl_id == null) {
        return error.NoFunctionFound;
    }

    const ir = try ir_gen.generateIR(unit_id, main_decl_id.?);
    var mut_ir = ir;
    defer mut_ir.deinit(allocator);

    // Verify Loop Structure
    // Expected blocks: entry, header, body, exit, unreachable
    try testing.expect(ir.basic_blocks.len >= 4);

    // Find header block (should have conditional_branch)
    var has_header = false;
    var has_body = false;
    var has_back_edge = false;

    for (ir.basic_blocks) |block| {
        if (block.terminator) |term| {
            switch (term) {
                .conditional_branch => {
                    has_header = true;
                },
                .branch => |br| {
                    // Check if this is a back-edge (body -> header)
                    // In our case, body should branch back to header (block 1)
                    if (br.target_block == 1) {
                        has_back_edge = true;
                    }
                },
                else => {},
            }
        }

        // Body block should have instructions (i = i + 1)
        if (block.instructions.len > 0) {
            for (block.instructions) |inst| {
                if (inst == .binary_op) {
                    has_body = true;
                }
            }
        }
    }

    try testing.expect(has_header);
    try testing.expect(has_body);
    try testing.expect(has_back_edge);
}
