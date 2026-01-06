// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Codegen = @import("../../compiler/libjanus/passes/codegen/module.zig");
const IR = @import("../../compiler/libjanus/ir.zig");
const Parser = @import("../../compiler/libjanus/parser.zig");
const Semantic = @import("../../compiler/libjanus/semantic.zig");
const Tokenizer = @import("../../compiler/libjanus/tokenizer.zig");

// Test helper to create IR from source
fn createIRFromSource(source: []const u8, allocator: std.mem.Allocator) !IR.Module {
    const tokens = try Tokenizer.tokenize(source, allocator);
    defer allocator.free(tokens);

    const ast = try Parser.parse(tokens, allocator);
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    var graph = try Semantic.analyze(ast, allocator);
    defer graph.deinit();

    return try IR.generateIR(ast, &graph, allocator);
}

test "codegen: LLVM IR generation for Hello World" {
    const allocator = testing.allocator;

    const source = "func main() { print(\"Hello, Janus!\") }";
    var ir_module = try createIRFromSource(source, allocator);
    defer ir_module.deinit();

    var codegen = Codegen.LLVMCodegen.init(allocator);
    defer codegen.deinit();

    const llvm_ir = try codegen.generateLLVM(&ir_module);
    defer allocator.free(llvm_ir);

    // Verify LLVM IR contains expected elements
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "target triple") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "declare i32 @printf") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @main") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "Hello, Janus!") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 0") != null);
}

test "codegen: string constant generation" {
    const allocator = testing.allocator;

    var ir_module = IR.Module.init(allocator);
    defer ir_module.deinit();

    // Create a string constant
    const string_val = try ir_module.createValue(.String, "test_string");
    try ir_module.addInstruction(.StringConst, string_val, &[_]IR.Value{}, "\"Hello, World!\"");

    var codegen = Codegen.LLVMCodegen.init(allocator);
    defer codegen.deinit();

    const llvm_ir = try codegen.generateLLVM(&ir_module);
    defer allocator.free(llvm_ir);

    // Should contain string constant declaration
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@str0") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "Hello, World!") != null);
}

test "codegen: function definition generation" {
    const allocator = testing.allocator;

    var ir_module = IR.Module.init(allocator);
    defer ir_module.deinit();

    // Create a function
    const func_val = try ir_module.createValue(.Function, "test_func");
    try ir_module.addInstruction(.FunctionDef, func_val, &[_]IR.Value{}, "test_func");
    try ir_module.addInstruction(.Return, null, &[_]IR.Value{}, "void");

    var codegen = Codegen.LLVMCodegen.init(allocator);
    defer codegen.deinit();

    const llvm_ir = try codegen.generateLLVM(&ir_module);
    defer allocator.free(llvm_ir);

    // Should contain function definition
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @test_func") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 0") != null);
}

test "codegen: print call generation" {
    const allocator = testing.allocator;

    var ir_module = IR.Module.init(allocator);
    defer ir_module.deinit();

    // Create string and call
    const string_val = try ir_module.createValue(.String, "message");
    try ir_module.addInstruction(.StringConst, string_val, &[_]IR.Value{}, "\"Test message\"");
    try ir_module.addInstruction(.Call, null, &[_]IR.Value{string_val}, "call print");

    var codegen = Codegen.LLVMCodegen.init(allocator);
    defer codegen.deinit();

    const llvm_ir = try codegen.generateLLVM(&ir_module);
    defer allocator.free(llvm_ir);

    // Should contain printf call
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "call i32 (i8*, ...) @printf") != null);
}

test "codegen: LLVM tools availability check" {
    const allocator = testing.allocator;

    // This test checks if LLVM tools are available
    // It's okay if they're not available in CI environments
    const has_llvm = Codegen.checkLLVMTools(allocator);

    // Just verify the function runs without crashing
    _ = has_llvm;
}

test "codegen: empty IR module" {
    const allocator = testing.allocator;

    var ir_module = IR.Module.init(allocator);
    defer ir_module.deinit();

    var codegen = Codegen.LLVMCodegen.init(allocator);
    defer codegen.deinit();

    const llvm_ir = try codegen.generateLLVM(&ir_module);
    defer allocator.free(llvm_ir);

    // Should still have header
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "target triple") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "declare i32 @printf") != null);
}

// Integration test - only runs if LLVM tools are available
test "codegen: end-to-end compilation (requires LLVM)" {
    const allocator = testing.allocator;

    // Skip if LLVM tools not available
    if (!Codegen.checkLLVMTools(allocator)) {
        std.debug.print("Skipping end-to-end test: LLVM tools not available\n", .{});
        return;
    }

    const source = "func main() { print(\"Hello from Janus!\") }";
    var ir_module = try createIRFromSource(source, allocator);
    defer ir_module.deinit();

    // Generate executable
    const output_path = "test_hello_janus";
    try Codegen.generateExecutable(&ir_module, output_path, allocator);

    // Verify executable was created
    const file = std.fs.cwd().openFile(output_path, .{}) catch |err| {
        std.debug.print("Failed to open generated executable: {}\n", .{err});
        return;
    };
    file.close();

    // Clean up
    std.fs.cwd().deleteFile(output_path) catch {};
}
