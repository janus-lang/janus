// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// E2E Smoke Tests: Zero-Capture Closures (SPEC-024 Phase A)
// Pipeline: Janus Source → Parser → ASTDB → QTJIR Lower → LLVM Emit → Verify
//
// These tests prove the FULL compiler pipeline generates valid, verifiable
// LLVM IR for closure syntax. LLVMVerifyModule ensures the IR is semantically
// correct and could be compiled to native code by llc.

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");
const qtjir = @import("qtjir");

/// Compile Janus source to LLVM IR and return the IR string.
/// Calls LLVMVerifyModule internally — invalid IR fails here.
fn compileToLLVM(allocator: std.mem.Allocator, source: []const u8, module_name: []const u8) ![]const u8 {
    var p = parser.Parser.init(allocator);
    defer p.deinit();

    const snapshot = try p.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, module_name);
    defer emitter.deinit();

    // emit() calls LLVMVerifyModule — invalid IR panics here
    try emitter.emit(ir_graphs.items);

    return try emitter.toString();
}

test "CLO-E2E-01: closure called with literal produces verified LLVM IR" {
    const allocator = testing.allocator;

    const source =
        \\func main() -> i32 do
        \\    let double = func(x: i32) -> i32 do
        \\        return x * 2
        \\    end
        \\    let result = double(21)
        \\    return result
        \\end
    ;

    const ir = try compileToLLVM(allocator, source, "closure_e2e_01");
    defer allocator.free(ir);

    // Verify main function exists
    try testing.expect(std.mem.indexOf(u8, ir, "define i32 @main()") != null);

    // Verify closure function was emitted as a separate function
    try testing.expect(std.mem.indexOf(u8, ir, "define i32 @__closure_0(") != null);

    // Verify the closure body: x * 2 should appear as mul instruction
    try testing.expect(std.mem.indexOf(u8, ir, "mul") != null);

    // Verify main calls the closure
    try testing.expect(std.mem.indexOf(u8, ir, "call i32 @__closure_0(") != null);
}

test "CLO-E2E-02: two closures produce two distinct LLVM functions" {
    const allocator = testing.allocator;

    const source =
        \\func main() -> i32 do
        \\    let inc = func(x: i32) -> i32 do
        \\        return x + 1
        \\    end
        \\    let dec = func(x: i32) -> i32 do
        \\        return x - 1
        \\    end
        \\    let a = inc(10)
        \\    let b = dec(a)
        \\    return b
        \\end
    ;

    const ir = try compileToLLVM(allocator, source, "closure_e2e_02");
    defer allocator.free(ir);

    // Both closures should appear as separate LLVM functions
    try testing.expect(std.mem.indexOf(u8, ir, "define i32 @__closure_0(") != null);
    try testing.expect(std.mem.indexOf(u8, ir, "define i32 @__closure_1(") != null);

    // main should call both
    try testing.expect(std.mem.indexOf(u8, ir, "call i32 @__closure_0(") != null);
    try testing.expect(std.mem.indexOf(u8, ir, "call i32 @__closure_1(") != null);
}

test "CLO-E2E-03: multi-param closure compiles to correct LLVM function signature" {
    const allocator = testing.allocator;

    const source =
        \\func main() -> i32 do
        \\    let add = func(a: i32, b: i32) -> i32 do
        \\        return a + b
        \\    end
        \\    return add(10, 32)
        \\end
    ;

    const ir = try compileToLLVM(allocator, source, "closure_e2e_03");
    defer allocator.free(ir);

    // Closure should have 2 i32 params
    try testing.expect(std.mem.indexOf(u8, ir, "define i32 @__closure_0(i32 %0, i32 %1)") != null);

    // main calls it with 2 args
    try testing.expect(std.mem.indexOf(u8, ir, "call i32 @__closure_0(") != null);

    // add instruction should appear in closure body
    try testing.expect(std.mem.indexOf(u8, ir, "add") != null);
}
