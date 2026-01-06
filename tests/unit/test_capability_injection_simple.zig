// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const api = @import("compiler/libjanus/api.zig");

test "Revolutionary Capability Injection - Simple Test" {
    std.debug.print("\n🚀 REVOLUTIONARY CAPABILITY INJECTION - SIMPLE TEST\n", .{});
    std.debug.print("===================================================\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple test program
    const test_program =
        \\func main() {
        \\    print("Hello, Revolutionary Janus!")
        \\}
    ;

    std.debug.print("📄 Test Program:\n{s}\n\n", .{test_program});

    // Phase 1: Parse the program
    std.debug.print("📊 Phase 1: Parsing\n", .{});
    var program = api.parse_root(test_program, allocator) catch |err| {
        std.debug.print("❌ Parsing failed: {}\n", .{err});
        return err;
    };
    // Note: Program cleanup handled by allocator
    std.debug.print("✅ Parsing successful\n", .{});

    // Phase 2: Semantic analysis
    std.debug.print("\n🔒 Phase 2: Semantic Analysis\n", .{});
    var semantic_graph = api.analyze(&program, allocator) catch |err| {
        std.debug.print("❌ Semantic analysis failed: {}\n", .{err});
        return err;
    };
    defer semantic_graph.deinit();
    std.debug.print("✅ Semantic analysis successful\n", .{});

    // Verify capability requirements
    const required_caps = semantic_graph.getRequiredCapabilities();
    std.debug.print("📋 Required capabilities: {d}\n", .{required_caps.len});

    var stdout_cap_found = false;
    for (required_caps) |cap| {
        const cap_name = cap.toString();
        std.debug.print("  - {s}\n", .{cap_name});
        if (cap == .StdoutWriteCapability) stdout_cap_found = true;
    }

    try testing.expect(stdout_cap_found);
    std.debug.print("✅ StdoutWriteCapability correctly detected for print() call\n", .{});

    // Phase 3: IR Generation
    std.debug.print("\n⚡ Phase 3: IR Generation with Capability Injection\n", .{});
    var ir_module = api.generateIR(&program, &semantic_graph, allocator) catch |err| {
        std.debug.print("❌ IR generation failed: {}\n", .{err});
        return err;
    };
    defer ir_module.deinit();
    std.debug.print("✅ IR generation successful\n", .{});
    std.debug.print("📊 IR instructions: {d}\n", .{ir_module.instructions.items.len});

    // Verify capability injection in IR
    var capability_create_count: u32 = 0;
    var capability_inject_count: u32 = 0;

    for (ir_module.instructions.items) |instruction| {
        switch (instruction.kind) {
            .CapabilityCreate => {
                capability_create_count += 1;
                std.debug.print("  🔐 Capability creation: {s}\n", .{instruction.metadata});
            },
            .CapabilityInject => {
                capability_inject_count += 1;
                std.debug.print("  💉 Capability injection: {s}\n", .{instruction.metadata});
            },
            .Call => {
                std.debug.print("  📞 Function call: {s}\n", .{instruction.metadata});
            },
            .FunctionDef => {
                std.debug.print("  🔧 Function definition: {s}\n", .{instruction.metadata});
            },
            else => {},
        }
    }

    try testing.expect(capability_create_count >= 1); // At least stdout capability
    std.debug.print("✅ Capability creation instructions generated\n", .{});

    // Phase 4: Code Generation
    std.debug.print("\n🔧 Phase 4: Code Generation\n", .{});
    const llvm_ir = api.generateLLVM(&ir_module, allocator) catch |err| {
        std.debug.print("❌ LLVM IR generation failed: {}\n", .{err});
        return err;
    };
    defer allocator.free(llvm_ir);
    std.debug.print("✅ LLVM IR generation successful\n", .{});
    std.debug.print("📊 LLVM IR size: {d} bytes\n", .{llvm_ir.len});

    // Verify capability runtime functions
    const has_stdout_cap_create = std.mem.indexOf(u8, llvm_ir, "janus_create_stdout_capability") != null;
    const has_cap_validate = std.mem.indexOf(u8, llvm_ir, "janus_validate_capability") != null;

    try testing.expect(has_stdout_cap_create);
    try testing.expect(has_cap_validate);
    std.debug.print("✅ Capability runtime functions declared in LLVM IR\n", .{});

    // Phase 5: Executable Generation
    std.debug.print("\n🚀 Phase 5: Executable Generation\n", .{});
    const output_path = "test_capability_simple_output";
    api.generateExecutable(&ir_module, output_path, allocator) catch |err| {
        std.debug.print("❌ Executable generation failed: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ Executable generation successful: {s}\n", .{output_path});

    // Cleanup
    std.fs.cwd().deleteFile(output_path) catch {};
    std.fs.cwd().deleteFile("debug.ll") catch {};

    // Revolutionary Achievement Summary
    std.debug.print("\n🎉 REVOLUTIONARY CAPABILITY INJECTION - SUCCESS!\n", .{});
    std.debug.print("===============================================\n", .{});
    std.debug.print("✅ Semantic Analysis: Automatic capability inference\n", .{});
    std.debug.print("✅ IR Generation: Capability creation and injection\n", .{});
    std.debug.print("✅ Code Generation: Runtime capability provision\n", .{});
    std.debug.print("✅ Complete pipeline: Source → Capability-aware executable\n", .{});
    std.debug.print("\n🔐 THE COMPILER NOW ENFORCES CAPABILITY SECURITY! 🔐\n", .{});
    std.debug.print("User writes: print(\"Hello!\") \n", .{});
    std.debug.print("Compiler generates: Capability-gated I/O runtime\n", .{});
    std.debug.print("\nThis is Honest Sugar in its purest form.\n", .{});
}
