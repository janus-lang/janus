// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus = @import("compiler/libjanus/api.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test the core compilation pipeline
    const source =
        \\func main() do
        \\    print("Hello, Janus!")
        \\end
    ;


    // Test tokenization
    const tokens = janus.tokenize(source, allocator) catch |err| {
        return;
    };
    defer allocator.free(tokens);

    // Test parsing
    const ast = janus.parse_root(source, allocator) catch |err| {
        return;
    };
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }

    // Test semantic analysis
    var semantic_graph = janus.analyze(ast, allocator) catch |err| {
        return;
    };
    defer semantic_graph.deinit();

    // Test IR generation
    var ir_module = janus.generateIR(ast, &semantic_graph, allocator) catch |err| {
        return;
    };
    defer ir_module.deinit();

    // Print IR for inspection
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    try ir_module.print(&stdout_writer.interface);
    try stdout_writer.flush();

    // Test C code generation
    const c_codegen = @import("compiler/libjanus/codegen_c.zig");
    c_codegen.emit_c(&ir_module, "test_output.c", allocator) catch |err| {
        return;
    };

    // Try to compile with gcc
    const gcc_args = [_][]const u8{ "gcc", "-o", "test_output", "test_output.c" };
    var gcc_process = std.process.Child.init(&gcc_args, allocator);
    gcc_process.stdout_behavior = .Ignore;
    gcc_process.stderr_behavior = .Ignore;

    const gcc_result = gcc_process.spawnAndWait() catch |err| {
        return;
    };

    if (gcc_result == .Exited and gcc_result.Exited == 0) {

        // Try to run it
        const run_args = [_][]const u8{"./test_output"};
        var run_process = std.process.Child.init(&run_args, allocator);
        const run_result = run_process.spawnAndWait() catch |err| {
            return;
        };

        if (run_result == .Exited and run_result.Exited == 0) {
        }
    } else {
    }

}
