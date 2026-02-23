// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR LLVM Bindings (via Zig's vendored LLVM)

const std = @import("std");

// Import Zig's LLVM-C bindings
pub const c = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/Target.h");
    @cInclude("llvm-c/TargetMachine.h");
    @cInclude("llvm-c/Analysis.h");
});

// Type aliases for safety
pub const Context = c.LLVMContextRef;
pub const Module = c.LLVMModuleRef;
pub const Builder = c.LLVMBuilderRef;
pub const Value = c.LLVMValueRef;
pub const Type = c.LLVMTypeRef;
pub const BasicBlock = c.LLVMBasicBlockRef;

// Direct extern declarations for LLVM target init functions.
// LLVMInitializeNativeTarget() is an inline C function that expands via
// preprocessor macros (LLVM_NATIVE_TARGET → LLVMInitializeX86Target, etc).
// Zig's @cImport can't resolve these macros inside inline functions,
// causing a segfault at NULL. We bypass this by calling the real symbols.
extern "c" fn LLVMInitializeX86TargetInfo() void;
extern "c" fn LLVMInitializeX86Target() void;
extern "c" fn LLVMInitializeX86TargetMC() void;
extern "c" fn LLVMInitializeX86AsmPrinter() void;
extern "c" fn LLVMInitializeX86AsmParser() void;

/// Initialize LLVM native target (x86_64)
pub fn initializeNativeTarget() void {
    LLVMInitializeX86TargetInfo();
    LLVMInitializeX86Target();
    LLVMInitializeX86TargetMC();
    LLVMInitializeX86AsmPrinter();
    LLVMInitializeX86AsmParser();
}

/// Create LLVM context
pub fn contextCreate() Context {
    return c.LLVMContextCreate();
}

/// Dispose LLVM context
pub fn contextDispose(ctx: Context) void {
    c.LLVMContextDispose(ctx);
}

/// Create module with name
pub fn moduleCreateWithNameInContext(name: [*:0]const u8, ctx: Context) Module {
    return c.LLVMModuleCreateWithNameInContext(name, ctx);
}

/// Dispose module
pub fn disposeModule(module: Module) void {
    c.LLVMDisposeModule(module);
}

/// Create IR builder
pub fn createBuilderInContext(ctx: Context) Builder {
    return c.LLVMCreateBuilderInContext(ctx);
}

/// Dispose builder
pub fn disposeBuilder(builder: Builder) void {
    c.LLVMDisposeBuilder(builder);
}

/// Get i1 type (boolean)
pub fn int1TypeInContext(ctx: Context) Type {
    return c.LLVMInt1TypeInContext(ctx);
}

/// Get i32 type
pub fn int32TypeInContext(ctx: Context) Type {
    return c.LLVMInt32TypeInContext(ctx);
}

/// Get void type
pub fn voidTypeInContext(ctx: Context) Type {
    return c.LLVMVoidTypeInContext(ctx);
}

/// Get double type (f64)
pub fn doubleTypeInContext(ctx: Context) Type {
    return c.LLVMDoubleTypeInContext(ctx);
}

/// Create function type
pub fn functionType(return_type: Type, param_types: ?[*]Type, param_count: u32, is_var_arg: bool) Type {
    return c.LLVMFunctionType(
        return_type,
        param_types,
        param_count,
        if (is_var_arg) 1 else 0,
    );
}

/// Add function to module
pub fn addFunction(module: Module, name: [*:0]const u8, func_type: Type) Value {
    return c.LLVMAddFunction(module, name, func_type);
}

/// Append basic block
pub fn appendBasicBlockInContext(ctx: Context, func: Value, name: [*:0]const u8) BasicBlock {
    return c.LLVMAppendBasicBlockInContext(ctx, func, name);
}

/// Position builder at end of block
pub fn positionBuilderAtEnd(builder: Builder, block: BasicBlock) void {
    c.LLVMPositionBuilderAtEnd(builder, block);
}

/// Build return void
pub fn buildRetVoid(builder: Builder) Value {
    return c.LLVMBuildRetVoid(builder);
}

/// Build return
pub fn buildRet(builder: Builder, value: Value) Value {
    return c.LLVMBuildRet(builder, value);
}

/// Build add
pub fn buildAdd(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildAdd(builder, lhs, rhs, name);
}

/// Build sub
pub fn buildSub(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildSub(builder, lhs, rhs, name);
}

/// Build mul
pub fn buildMul(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildMul(builder, lhs, rhs, name);
}

/// Build sdiv
pub fn buildSDiv(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildSDiv(builder, lhs, rhs, name);
}

/// Build srem (signed remainder/modulo)
pub fn buildSRem(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildSRem(builder, lhs, rhs, name);
}

/// Build bitwise AND
pub fn buildAnd(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildAnd(builder, lhs, rhs, name);
}

/// Build bitwise OR
pub fn buildOr(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildOr(builder, lhs, rhs, name);
}

/// Build bitwise XOR
pub fn buildXor(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildXor(builder, lhs, rhs, name);
}

/// Build left shift
pub fn buildShl(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildShl(builder, lhs, rhs, name);
}

/// Build arithmetic right shift (sign-extend)
pub fn buildAShr(builder: Builder, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildAShr(builder, lhs, rhs, name);
}

/// Build bitwise NOT (xor with -1)
pub fn buildNot(builder: Builder, val: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildNot(builder, val, name);
}

/// Build ICmp
pub fn buildICmp(builder: Builder, op: c.LLVMIntPredicate, lhs: Value, rhs: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildICmp(builder, op, lhs, rhs, name);
}

/// Build ZExt
pub fn buildZExt(builder: Builder, val: Value, dest_ty: Type, name: [*:0]const u8) Value {
    return c.LLVMBuildZExt(builder, val, dest_ty, name);
}

/// Create constant int
pub fn constInt(ty: Type, value: u64, sign_extend: bool) Value {
    return c.LLVMConstInt(ty, value, if (sign_extend) 1 else 0);
}

/// Create constant real (f64)
pub fn constReal(ty: Type, value: f64) Value {
    return c.LLVMConstReal(ty, value);
}

/// Print module to string
pub fn printModuleToString(module: Module) [*:0]const u8 {
    return c.LLVMPrintModuleToString(module);
}

/// Dispose message
pub fn disposeMessage(msg: [*c]u8) void {
    c.LLVMDisposeMessage(msg);
}

/// Verify module
pub fn verifyModule(module: Module) !void {
    var error_msg: [*c]u8 = null;
    if (c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &error_msg) != 0) {
        defer disposeMessage(error_msg);
        std.debug.print("LLVM module verification failed: {s}\n", .{error_msg});
        return error.InvalidModule;
    }
}

/// Create array type
pub fn arrayType(elem_type: Type, count: u32) Type {
    return c.LLVMArrayType(elem_type, count);
}

/// Get type of value
pub fn typeof(val: Value) Type {
    return c.LLVMTypeOf(val);
}

/// Build alloca
pub fn buildAlloca(builder: Builder, ty: Type, name: [*:0]const u8) Value {
    return c.LLVMBuildAlloca(builder, ty, name);
}

/// Build store
pub fn buildStore(builder: Builder, val: Value, ptr: Value) Value {
    return c.LLVMBuildStore(builder, val, ptr);
}

/// Build load (typed)
pub fn buildLoad2(builder: Builder, ty: Type, ptr: Value, name: [*:0]const u8) Value {
    return c.LLVMBuildLoad2(builder, ty, ptr, name);
}

/// Build GEP (typed for opaque pointers)
pub fn buildInBoundsGEP2(builder: Builder, ty: Type, ptr: Value, indices: [*]Value, num_indices: u32, name: [*:0]const u8) Value {
    return c.LLVMBuildInBoundsGEP2(builder, ty, ptr, indices, num_indices, name);
}

/// Build unconditional branch
pub fn buildBr(builder: Builder, dest: BasicBlock) Value {
    return c.LLVMBuildBr(builder, dest);
}

/// Build conditional branch
pub fn buildCondBr(builder: Builder, cond: Value, then_blk: BasicBlock, else_blk: BasicBlock) Value {
    return c.LLVMBuildCondBr(builder, cond, then_blk, else_blk);
}

/// Create an anonymous struct type
pub fn structTypeInContext(ctx: Context, element_types: [*]Type, element_count: u32, is_packed: bool) Type {
    return c.LLVMStructTypeInContext(ctx, element_types, element_count, if (is_packed) 1 else 0);
}

/// Create a named struct type (for recursive types)
pub fn structCreateNamed(ctx: Context, name: [*:0]const u8) Type {
    return c.LLVMStructCreateNamed(ctx, name);
}

/// Set body of a named struct type
pub fn structSetBody(struct_ty: Type, element_types: [*]Type, element_count: u32, is_packed: bool) void {
    c.LLVMStructSetBody(struct_ty, element_types, element_count, if (is_packed) 1 else 0);
}

/// Get struct element type at index
pub fn getElementType(ty: Type) Type {
    return c.LLVMGetElementType(ty);
}

/// Build struct GEP (typed for opaque pointers)
pub fn buildStructGEP2(builder: Builder, ty: Type, ptr: Value, idx: u32, name: [*:0]const u8) Value {
    return c.LLVMBuildStructGEP2(builder, ty, ptr, idx, name);
}

/// Build insert value (for aggregates - struct/array)
pub fn buildInsertValue(builder: Builder, agg_val: Value, elem_val: Value, idx: u32, name: [*:0]const u8) Value {
    return c.LLVMBuildInsertValue(builder, agg_val, elem_val, idx, name);
}

/// Build extract value (for aggregates - struct/array)
pub fn buildExtractValue(builder: Builder, agg_val: Value, idx: u32, name: [*:0]const u8) Value {
    return c.LLVMBuildExtractValue(builder, agg_val, idx, name);
}

/// Get undefined value of type
pub fn getUndef(ty: Type) Value {
    return c.LLVMGetUndef(ty);
}

/// Count struct element types
pub fn countStructElementTypes(struct_ty: Type) u32 {
    return c.LLVMCountStructElementTypes(struct_ty);
}

/// Get struct element types
pub fn getStructElementTypes(struct_ty: Type, dest: [*]Type) void {
    c.LLVMGetStructElementTypes(struct_ty, dest);
}
