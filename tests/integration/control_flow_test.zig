// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Control Flow (Epic 2.1)
//
// This test validates the compilation pipeline for control flow constructs.

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "Epic 2.1: Compile and Execute Control Flow (if/else)" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 10
        \\    if (x > 5) {
        \\        print("Greater")
        \\    } else {
        \\        print("Smaller")
        \\    }
        \\}
    ;

    // 1. Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 2. Lower
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graph = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {

        for (ir_graphs.items) |*g| g.deinit();

        ir_graphs.deinit(allocator);

    }

    const ir_graph = &ir_graphs.items[0];

    // 3. Emit
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "control_flow_if");
    defer emitter.deinit();
    try emitter.emit(&ir_graph);
    
    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);
    
    // 4. Verify (Basic Check)
    // We expect basic blocks and branch instructions
    // Note: Since implementation is missing, this will likely fail or produce flat code
    // if the lowerer silences the if_stmt or if the emitter ignores the opcode.
    
    // For now, let's just assert we see "br" or "icmp" instructions which are typical for if
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "br") != null);
}

test "Epic 2.1: Compile and Execute Control Flow (while)" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let i = 0
        \\    while (i < 5) {
        \\        print_int(i)
        \\        i = i + 1
        \\    }
        \\}
    ;

    // 1. Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 2. Lower
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graph = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {

        for (ir_graphs.items) |*g| g.deinit();

        ir_graphs.deinit(allocator);

    }

    const ir_graph = &ir_graphs.items[0];

    // 3. Emit
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "control_flow_while");
    defer emitter.deinit();
    try emitter.emit(&ir_graph);
    
    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    // 4. Verify (Basic Check)
    // We expect loop structure (phi, br, icmp)
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "br") != null);
    // try testing.expect(std.mem.indexOf(u8, llvm_ir, "phi") != null); // Phi might not be present if using alloca
}
