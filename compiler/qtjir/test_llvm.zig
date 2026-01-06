// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// LLVM Bindings Tests

const std = @import("std");
const testing = std.testing;
const llvm = @import("llvm_bindings.zig");

test "LLVM: Create and dispose context" {
    const ctx = llvm.contextCreate();
    defer llvm.contextDispose(ctx);

    try testing.expect(ctx != null);
}

test "LLVM: Create module" {
    const ctx = llvm.contextCreate();
    defer llvm.contextDispose(ctx);

    const module = llvm.moduleCreateWithNameInContext("test_module", ctx);
    defer llvm.disposeModule(module);

    try testing.expect(module != null);
}

test "LLVM: Create builder" {
    const ctx = llvm.contextCreate();
    defer llvm.contextDispose(ctx);

    const builder = llvm.createBuilderInContext(ctx);
    defer llvm.disposeBuilder(builder);

    try testing.expect(builder != null);
}

test "LLVM: Create simple function" {
    llvm.initializeNativeTarget();

    const ctx = llvm.contextCreate();
    defer llvm.contextDispose(ctx);

    const module = llvm.moduleCreateWithNameInContext("test", ctx);
    defer llvm.disposeModule(module);

    const builder = llvm.createBuilderInContext(ctx);
    defer llvm.disposeBuilder(builder);

    // Create function: void main()
    const void_type = llvm.voidTypeInContext(ctx);
    const func_type = llvm.functionType(void_type, null, 0, false);
    const func = llvm.addFunction(module, "main", func_type);

    // Create entry block
    const entry = llvm.appendBasicBlockInContext(ctx, func, "entry");
    llvm.positionBuilderAtEnd(builder, entry);

    // Build return
    _ = llvm.buildRetVoid(builder);

    // Verify module
    try llvm.verifyModule(module);

    // Print IR
    const ir = llvm.printModuleToString(module);
    defer llvm.disposeMessage(ir);

    const ir_str = std.mem.span(ir);
    try testing.expect(std.mem.indexOf(u8, ir_str, "define void @main()") != null);
}

test "LLVM: Create function with add operation" {
    llvm.initializeNativeTarget();

    const ctx = llvm.contextCreate();
    defer llvm.contextDispose(ctx);

    const module = llvm.moduleCreateWithNameInContext("test", ctx);
    defer llvm.disposeModule(module);

    const builder = llvm.createBuilderInContext(ctx);
    defer llvm.disposeBuilder(builder);

    // Create function: i32 add_test()
    const i32_type = llvm.int32TypeInContext(ctx);
    const func_type = llvm.functionType(i32_type, null, 0, false);
    const func = llvm.addFunction(module, "add_test", func_type);

    // Create entry block
    const entry = llvm.appendBasicBlockInContext(ctx, func, "entry");
    llvm.positionBuilderAtEnd(builder, entry);

    // Create constants: 2 + 3
    const lhs = llvm.constInt(i32_type, 2, false);
    const rhs = llvm.constInt(i32_type, 3, false);

    // Build add
    const result = llvm.buildAdd(builder, lhs, rhs, "add");

    // Build return
    _ = llvm.buildRet(builder, result);

    // Verify module
    try llvm.verifyModule(module);

    // Print IR
    const ir = llvm.printModuleToString(module);
    defer llvm.disposeMessage(ir);

    const ir_str = std.mem.span(ir);
    try testing.expect(std.mem.indexOf(u8, ir_str, "add i32") != null);
}
