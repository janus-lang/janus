// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const testing = std.testing;
const api = @import("compiler/libjanus/api.zig");

test "Revolutionary Capability Injection - Simple Test" {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple test program
    const test_program =
        \\func main() {
        \\    print("Hello, Revolutionary Janus!")
        \\}
    ;


    // Phase 1: Parse the program
    var program = api.parse_root(test_program, allocator) catch |err| {
        return err;
    };
    // Note: Program cleanup handled by allocator

    // Phase 2: Semantic analysis
    var semantic_graph = api.analyze(&program, allocator) catch |err| {
        return err;
    };
    defer semantic_graph.deinit();

    // Verify capability requirements
    const required_caps = semantic_graph.getRequiredCapabilities();

    var stdout_cap_found = false;
    for (required_caps) |cap| {
        const cap_name = cap.toString();
        if (cap == .StdoutWriteCapability) stdout_cap_found = true;
    }

    try testing.expect(stdout_cap_found);

    // Phase 3: IR Generation
    var ir_module = api.generateIR(&program, &semantic_graph, allocator) catch |err| {
        return err;
    };
    defer ir_module.deinit();

    // Verify capability injection in IR
    var capability_create_count: u32 = 0;
    var capability_inject_count: u32 = 0;

    for (ir_module.instructions.items) |instruction| {
        switch (instruction.kind) {
            .CapabilityCreate => {
                capability_create_count += 1;
            },
            .CapabilityInject => {
                capability_inject_count += 1;
            },
            .Call => {
            },
            .FunctionDef => {
            },
            else => {},
        }
    }

    try testing.expect(capability_create_count >= 1); // At least stdout capability

    // Phase 4: Code Generation
    const llvm_ir = api.generateLLVM(&ir_module, allocator) catch |err| {
        return err;
    };
    defer allocator.free(llvm_ir);

    // Verify capability runtime functions
    const has_stdout_cap_create = std.mem.indexOf(u8, llvm_ir, "janus_create_stdout_capability") != null;
    const has_cap_validate = std.mem.indexOf(u8, llvm_ir, "janus_validate_capability") != null;

    try testing.expect(has_stdout_cap_create);
    try testing.expect(has_cap_validate);

    // Phase 5: Executable Generation
    const output_path = "test_capability_simple_output";
    api.generateExecutable(&ir_module, output_path, allocator) catch |err| {
        return err;
    };

    // Cleanup
    compat_fs.deleteFile(output_path) catch {};
    compat_fs.deleteFile("debug.ll") catch {};

    // Revolutionary Achievement Summary
}
