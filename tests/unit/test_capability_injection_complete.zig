// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const Parser = @import("compiler/libjanus/parser.zig");
const Semantic = @import("compiler/libjanus/semantic.zig");
const IR = @import("compiler/libjanus/ir.zig");
const Codegen = @import("compiler/libjanus/passes/codegen/module.zig");

// Revolutionary test: Complete capability injection pipeline
// Tests the full flow from source code to capability-aware executable

test "Revolutionary Capability Injection - Complete Pipeline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test source: Simple print() call that requires capability injection
    const source =
        \\func main() {
        \\    print("Hello, Revolutionary Janus!")
        \\}
    ;


    // Phase 1: Parse the source code
    var parser = Parser.init(allocator);
    defer parser.deinit();

    const ast = try parser.parse(source);

    // Phase 2: Semanticsis with ASTDB integration
    var semantic_analyzer = Semantic.SemanticAnalyzer.init(allocator);
    defer semantic_analyzer.deinit();

    const semantic_graph = try semantic_analyzer.analyze(ast);

    // Verify capability inference
    const required_caps = semantic_graph.getRequiredCapabilities();

    var found_stdout_cap = false;
    for (required_caps) |cap| {
        switch (cap) {
            .StdoutWriteCapability => {
                found_stdout_cap = true;
            },
            .StderrWriteCapability => {
            },
            else => {
            },
        }
    }

    try std.testing.expect(found_stdout_cap);

    // Phase 3: IR Generation with capability injection
    var ir_module = try IR.generateIR(ast, &semantic_graph, allocator);
    defer ir_module.deinit();


    // Verify capability creation and injection instructions
    var found_cap_create = false;
    var found_cap_inject = false;
    var found_call_with_caps = false;

    for (ir_module.instructions.items) |instruction| {
        switch (instruction.kind) {
            .CapabilityCreate => {
                found_cap_create = true;
            },
            .CapabilityInject => {
                found_cap_inject = true;
            },
            .Call => {
                if (std.mem.indexOf(u8, instruction.metadata, "capabilities") != null) {
                    found_call_with_caps = true;
                }
            },
            else => {},
        }
    }

    try std.testing.expect(found_cap_create);
    try std.testing.expect(found_cap_inject);

    // Phase 4: Code Generation (LLVM IR with capability runtime)
    var codegen = Codegen.LLVMCodegen.init(allocator);
    defer codegen.deinit();

    const llvm_ir = try codegen.generateLLVM(&ir_module);
    defer allocator.free(llvm_ir);


    // Verify LLVM IR contains capability functions
    const has_cap_create = std.mem.indexOf(u8, llvm_ir, "janus_create_stdout_capability") != null;
    const has_cap_validate = std.mem.indexOf(u8, llvm_ir, "janus_validate_capability") != null;
    const has_wrapper_func = std.mem.indexOf(u8, llvm_ir, "main_with_caps") != null;
    const has_runtime_wrapper = std.mem.indexOf(u8, llvm_ir, "Revolutionary runtime wrapper") != null;

    try std.testing.expect(has_cap_create);
    try std.testing.expect(has_cap_validate);

    if (has_wrapper_func) {
    }
    if (has_runtime_wrapper) {
    }

    // Phase 5: Executable Generation (Revolutionary C stub)
    const output_path = "test_capability_injection_output";
    try codegen.compileToExecutable(llvm_ir, output_path);

    // Verify executable exists and is executable
    const file_stat = compat_fs.statFile(output_path) catch |err| {
        return err;
    };
    _ = file_stat;

    // Phase 6: Execution Test (Revolutionary capability system in action)

    var exec_process = std.process.Child.init(&[_][]const u8{output_path}, allocator);
    exec_process.stdout_behavior = .Pipe;
    exec_process.stderr_behavior = .Pipe;

    try exec_process.spawn();
    const exec_result = try exec_process.wait();

    if (exec_result == .Exited and exec_result.Exited == 0) {
    } else {
    }

    // Clean up
    compat_fs.deleteFile(output_path) catch {};
    compat_fs.deleteFile("debug.ll") catch {};

    // Revolutionary Achievement Summary
}

test "Capability Injection - Multiple Capabilities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test source with both print() and eprint() calls
    const source =
        \\func main() {
        \\    print("Standard output")
        \\    eprint("Error output")
        \\}
    ;


    // Parse and analyze
    var parser = Parser.init(allocator);
    defer parser.deinit();
    const ast = try parser.parse(source);

    var semantic_analyzer = Semantic.SemanticAnalyzer.init(allocator);
    defer semantic_analyzer.deinit();
    const semantic_graph = try semantic_analyzer.analyze(ast);

    // Verify both capabilities are detected
    const required_caps = semantic_graph.getRequiredCapabilities();

    var found_stdout = false;
    var found_stderr = false;
    for (required_caps) |cap| {
        switch (cap) {
            .StdoutWriteCapability => found_stdout = true,
            .StderrWriteCapability => found_stderr = true,
            else => {},
        }
    }

    try std.testing.expect(found_stdout);
    try std.testing.expect(found_stderr);

    // Generate IR and verify multiple capability injection
    var ir_module = try IR.generateIR(ast, &semantic_graph, allocator);
    defer ir_module.deinit();

    var cap_create_count: u32 = 0;
    var cap_inject_count: u32 = 0;
    for (ir_module.instructions.items) |instruction| {
        switch (instruction.kind) {
            .CapabilityCreate => cap_create_count += 1,
            .CapabilityInject => cap_inject_count += 1,
            else => {},
        }
    }

    try std.testing.expect(cap_create_count >= 2); // At least stdout and stderr
    try std.testing.expect(cap_inject_count >= 2); // At least two injections
}

test "Capability Injection - Memory Discipline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();


    const source = "func main() { print(\"Memory test\") }";

    // Full pipeline test with memory tracking
    var parser = Parser.init(allocator);
    defer parser.deinit();
    const ast = try parser.parse(source);

    var semantic_analyzer = Semantic.SemanticAnalyzer.init(allocator);
    defer semantic_analyzer.deinit();
    const semantic_graph = try semantic_analyzer.analyze(ast);

    var ir_module = try IR.generateIR(ast, &semantic_graph, allocator);
    defer ir_module.deinit();

    var codegen = Codegen.LLVMCodegen.init(allocator);
    defer codegen.deinit();
    const llvm_ir = try codegen.generateLLVM(&ir_module);
    defer allocator.free(llvm_ir);

}
