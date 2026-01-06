// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const ir_generator = @import("libjanus_ir_generator");
const janus_parser = @import("janus_parser");
const astdb_core = @import("astdb"); // astdb module exports core types
const astdb_bind = @import("astdb_binder");
const JanusIR = ir_generator.JanusIR;

test "IR: Variable Declaration and Usage" {
    const allocator = std.testing.allocator;

    // Setup
    var db_system = try astdb_core.AstDB.init(allocator, true);
    defer db_system.deinit();

    var parser_instance = janus_parser.Parser.init(allocator);
    defer parser_instance.deinit();

    const source =
        \\func main() do
        \\    let x = 42
        \\    return x
        \\end
    ;

    var snapshot = try parser_instance.parseIntoAstDB(&db_system, "test_var.jan", source);
    defer snapshot.deinit();

    // Bind global declarations
    const unit_id = snapshot.core_snapshot.astdb.units.items[0].id;
    try astdb_bind.bindUnit(&db_system, unit_id);

    var ir_gen = try ir_generator.IRGenerator.init(allocator, &snapshot, &db_system);
    defer ir_gen.deinit();

    // Find main function decl
    var main_decl_id: ?astdb_core.DeclId = null;
    const unit = snapshot.core_snapshot.astdb.units.items[0];

    // Iterate over decls to find main
    if (unit.decls.len > 0) {
        for (unit.decls, 0..) |decl, index| {
            if (decl.kind == .function) {
                main_decl_id = @enumFromInt(index);
                break;
            }
        }
    }

    // If unit.decls is not available directly, we might need a different way.
    // But let's assume we can search if we knew the range.
    // For now, let's print what Decl 0 is if main_decl_id is null/assumed 0.

    if (main_decl_id == null) {
        // Fallback or debug
        const decl_0 = snapshot.core_snapshot.getDecl(unit_id, @enumFromInt(0));
        if (decl_0) |d| {
            std.debug.print("Decl 0 Kind: {}\n", .{d.kind});
        } else {
            std.debug.print("Decl 0 not found\n", .{});
        }
        main_decl_id = @enumFromInt(0); // Try 0 anyway but we know it failed
    }

    const ir = try ir_gen.generateIR(unit_id, main_decl_id.?);
    var mut_ir = ir;
    defer mut_ir.deinit(allocator);

    // Verify Instructions
    // Expected:
    // 1. LoadConstant (42) -> reg_0
    // 2. Alloca (x) -> slot_0 (Optional, but good for explicit IR)
    // 3. Store (reg_0 -> slot_0)
    // 4. LoadLocal (slot_0) -> reg_1
    // 5. Return (reg_1)

    var has_store_local = false;
    var has_load_local = false;
    var return_reg: ?u32 = null;
    var load_reg: ?u32 = null;

    for (ir.basic_blocks) |block| {
        for (block.instructions) |inst| {
            switch (inst) {
                .store => |s| {
                    switch (s.dest_location) {
                        .local_var => |_| {
                            has_store_local = true;
                        },
                        else => {},
                    }
                },
                .load_local => |l| {
                    has_load_local = true;
                    load_reg = l.dest_reg;
                },
                else => {},
            }
        }
        if (block.terminator) |term| {
            switch (term) {
                .return_value => |val| {
                    return_reg = val;
                },
                else => {},
            }
        }
    }

    try testing.expect(has_store_local);
    try testing.expect(has_load_local);

    // Verify data flow: Return should return the register loaded from local
    if (return_reg != null and load_reg != null) {
        try testing.expectEqual(return_reg.?, load_reg.?);
    } else {
        return error.MissingInstructions;
    }
}
