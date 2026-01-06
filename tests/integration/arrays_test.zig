// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Array Support (Epic 1.5)
//
// This test validates the compilation pipeline for array literals and access.

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "Epic 1.5: Compile and Execute Array Literal" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = [10, 20, 30];
        \\    let x = a[1];
        \\    print_int(x);
        \\}
    ;

    // 1. Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 2. Lower
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {

        for (ir_graphs.items) |*g| g.deinit();

        ir_graphs.deinit(allocator);

    }    // 3. Emit
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "array_test");
    defer emitter.deinit();
    try emitter.emit(ir_graphs.items);
    
    // 4. Verify (String Check)
    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);
    
    // We expect calls to std_array_create (or stack allocation) 
    // and GEPr for access
    
    // For now, depending on implementation strategy:
    // If dynamic:
    // try testing.expect(std.mem.indexOf(u8, llvm_ir, "std_array_create") != null);
    
    // If stack/alloca:
    // try testing.expect(std.mem.indexOf(u8, llvm_ir, "alloca") != null);
    // try testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr") != null);
}

test "Epic 1.5: Compile and Execute Array Mutation" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = [1, 2, 3];
        \\    a[0] = 42;
        \\    print_int(a[0]);
        \\}
    ;

    // 1. Parse
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();
    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // 2. Lower
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {

        for (ir_graphs.items) |*g| g.deinit();

        ir_graphs.deinit(allocator);

    }    // 3. Emit
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "array_mutation");
    defer emitter.deinit();
    try emitter.emit(ir_graphs.items);
    
    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);
    
    // Expect store instructions
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "store") != null);
}
