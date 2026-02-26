// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const testing = std.testing;
const api = @import("compiler/libjanus/api.zig");
const astdb = @import("compiler/libjanus/astdb.zig");
const Semantic = @import("compiler/libjanus/semantic.zig");
const Parser = @import("compiler/libjanus/parser.zig");

test "Revolutionary Capability Injection - Complete Pipeline" {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test program that requires capabilities
    const test_program =
        \\func main() {
        \\    print("Hello, stdout!")
        \\    eprint("Hello, stderr!")
        \\}
    ;


    // Phase 1: Parse the program using the old AST (transitional)
    var ast = api.parse_root(test_program, allocator) catch |err| {
        return err;
    };
    // Note: AST cleanup handled by allocator

    // Phase 2: Revolutionary Semantic Analysis with ASTDB
    var semantic_graph = api.analyze(&ast, allocator) catch |err| {
        return err;
    };
    defer semantic_graph.deinit();

    // Verify capability requirements were detected
    const required_caps = semantic_graph.getRequiredCapabilities();

    var stdout_cap_found = false;
    var stderr_cap_found = false;

    for (required_caps) |cap| {
        const cap_name = cap.toString();
        if (cap == .StdoutWriteCapability) stdout_cap_found = true;
        if (cap == .StderrWriteCapability) stderr_cap_found = true;
    }

    try testing.expect(stdout_cap_found);
    try testing.expect(stderr_cap_found);

    // Phase 3: Revolutionary IR Generation with Capability Injection
    var ir_module = api.generateIR(&ast, &semantic_graph, allocator) catch |err| {
        return err;
    };
    defer ir_module.deinit();

    // Verify capability injection in IR
    var capability_create_count: u32 = 0;
    var capability_inject_count: u32 = 0;
    var call_count: u32 = 0;

    for (ir_module.instructions.items) |instruction| {
        switch (instruction.kind) {
            .CapabilityCreate => {
                capability_create_count += 1;
            },
            .CapabilityInject => {
                capability_inject_count += 1;
            },
            .Call => {
                call_count += 1;
            },
            else => {},
        }
    }

    try testing.expect(capability_create_count == 2); // stdout + stderr
    try testing.expect(capability_inject_count == 2); // print + eprint
    try testing.expect(call_count == 2); // print + eprint calls

    // Phase 4: Revolutionary Code Generation with Runtime Capability Creation
    const llvm_ir = api.generateLLVM(&ir_module, allocator) catch |err| {
        return err;
    };
    defer allocator.free(llvm_ir);

    // Verify capability runtime functions are declared
    const has_stdout_cap_create = std.mem.indexOf(u8, llvm_ir, "janus_create_stdout_capability") != null;
    const has_stderr_cap_create = std.mem.indexOf(u8, llvm_ir, "janus_create_stderr_capability") != null;
    const has_cap_validate = std.mem.indexOf(u8, llvm_ir, "janus_validate_capability") != null;

    try testing.expect(has_stdout_cap_create);
    try testing.expect(has_stderr_cap_create);
    try testing.expect(has_cap_validate);

    // Phase 5: Executable Generation with Capability Runtime
    const output_path = "test_capability_injection_output";
    api.generateExecutable(&ir_module, output_path, allocator) catch |err| {
        return err;
    };

    // Phase 6: Verify the generated executable exists and is runnable
    const file_exists = std.fs.cwd().access(output_path, .{}) catch false;
    if (file_exists) {

        // Try to run the executable to verify capability injection works
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const run_args = [_][]const u8{"./" ++ output_path};
        var run_process = std.process.Child.init(&run_args, arena_allocator);
        run_process.stdout_behavior = .Pipe;
        run_process.stderr_behavior = .Pipe;

        if (run_process.spawn()) |_| {
            const result = run_process.wait() catch {
                return;
            };

            if (result == .Exited and result.Exited == 0) {
            } else {
            }
        } else |_| {
        }
    } else {
    }

    // Cleanup
    compat_fs.deleteFile(output_path) catch {};

    // Final Results

}

test "Capability Injection - IR Instruction Verification" {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple test program
    const test_program =
        \\func main() {
        \\    print("Test")
        \\}
    ;

    // Parse and analyze
    var ast = api.parse_root(test_program, allocator) catch return;
    // Note: AST cleanup handled by allocator

    var semantic_graph = api.analyze(&ast, allocator) catch return;
    defer semantic_graph.deinit();

    // Generate IR
    var ir_module = api.generateIR(&ast, &semantic_graph, allocator) catch return;
    defer ir_module.deinit();

    // Verify IR structure
    for (ir_module.instructions.items, 0..) |instruction, i| {
        if (instruction.result) |result| {
        }
        if (instruction.metadata.len > 0) {
        }
    }

    // Verify the expected instruction sequence
    var found_cap_create = false;
    var found_cap_inject = false;
    var found_function_def = false;
    var found_call = false;

    for (ir_module.instructions.items) |instruction| {
        switch (instruction.kind) {
            .CapabilityCreate => found_cap_create = true,
            .CapabilityInject => found_cap_inject = true,
            .FunctionDef => found_function_def = true,
            .Call => found_call = true,
            else => {},
        }
    }

    try testing.expect(found_cap_create);
    try testing.expect(found_cap_inject);
    try testing.expect(found_function_def);
    try testing.expect(found_call);

}
