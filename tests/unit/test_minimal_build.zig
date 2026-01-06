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

    std.debug.print("🔧 Testing Janus Core Compilation Pipeline\n", .{});
    std.debug.print("Source:\n{s}\n", .{source});

    // Test tokenization
    std.debug.print("\n--- Tokenization ---\n", .{});
    const tokens = janus.tokenize(source, allocator) catch |err| {
        std.debug.print("❌ Tokenization failed: {}\n", .{err});
        return;
    };
    defer allocator.free(tokens);
    std.debug.print("✅ Tokenized: {} tokens\n", .{tokens.len});

    // Test parsing
    std.debug.print("\n--- Parsing ---\n", .{});
    const ast = janus.parse_root(source, allocator) catch |err| {
        std.debug.print("❌ Parsing failed: {}\n", .{err});
        return;
    };
    defer {
        ast.deinit(allocator);
        allocator.destroy(ast);
    }
    std.debug.print("✅ Parsed AST successfully\n", .{});

    // Test semantic analysis
    std.debug.print("\n--- Semantic Analysis ---\n", .{});
    var semantic_graph = janus.analyze(ast, allocator) catch |err| {
        std.debug.print("❌ Semantic analysis failed: {}\n", .{err});
        return;
    };
    defer semantic_graph.deinit();
    std.debug.print("✅ Semantic analysis complete: {} symbols\n", .{semantic_graph.symbols.items.len});

    // Test IR generation
    std.debug.print("\n--- IR Generation ---\n", .{});
    var ir_module = janus.generateIR(ast, &semantic_graph, allocator) catch |err| {
        std.debug.print("❌ IR generation failed: {}\n", .{err});
        return;
    };
    defer ir_module.deinit();
    std.debug.print("✅ IR generated: {} instructions\n", .{ir_module.instructions.items.len});

    // Print IR for inspection
    std.debug.print("\n--- Generated IR ---\n", .{});
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    try ir_module.print(&stdout_writer.interface);
    try stdout_writer.flush();

    // Test C code generation
    std.debug.print("\n--- C Code Generation ---\n", .{});
    const c_codegen = @import("compiler/libjanus/codegen_c.zig");
    c_codegen.emit_c(&ir_module, "test_output.c", allocator) catch |err| {
        std.debug.print("❌ C codegen failed: {}\n", .{err});
        return;
    };
    std.debug.print("✅ C code generated: test_output.c\n", .{});

    // Try to compile with gcc
    std.debug.print("\n--- Executable Generation ---\n", .{});
    const gcc_args = [_][]const u8{ "gcc", "-o", "test_output", "test_output.c" };
    var gcc_process = std.process.Child.init(&gcc_args, allocator);
    gcc_process.stdout_behavior = .Ignore;
    gcc_process.stderr_behavior = .Ignore;

    const gcc_result = gcc_process.spawnAndWait() catch |err| {
        std.debug.print("❌ GCC not available: {}\n", .{err});
        std.debug.print("✅ But C code was generated successfully!\n", .{});
        return;
    };

    if (gcc_result == .Exited and gcc_result.Exited == 0) {
        std.debug.print("✅ Executable generated: test_output\n", .{});

        // Try to run it
        std.debug.print("\n--- Running Generated Program ---\n", .{});
        const run_args = [_][]const u8{"./test_output"};
        var run_process = std.process.Child.init(&run_args, allocator);
        const run_result = run_process.spawnAndWait() catch |err| {
            std.debug.print("❌ Failed to run: {}\n", .{err});
            return;
        };

        if (run_result == .Exited and run_result.Exited == 0) {
            std.debug.print("✅ Program executed successfully!\n", .{});
        }
    } else {
        std.debug.print("❌ GCC compilation failed\n", .{});
        std.debug.print("✅ But C code was generated successfully!\n", .{});
    }

    std.debug.print("\n🎉 Core pipeline test complete!\n", .{});
}
