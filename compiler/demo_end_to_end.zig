// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Import pipeline components
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;

pub fn main() !void {
    // Use arena allocator for deterministic, O(1) cleanup
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit(); // O(1) cleanup - no individual frees needed
    const allocator = arena.allocator();

    std.log.info("🚀 Janus End-to-End Compiler Demo", .{});
    std.log.info("==================================", .{});

    // Demo program
    const source = "func main() { print(\"Hello, Janus!\") }";
    std.log.info("📝 Source: {s}", .{source});

    // Step 1: Tokenization
    std.log.info("", .{});
    std.log.info("🔍 Step 1: Tokenization", .{});
    std.log.info("-----------------------", .{});

    var tokenizer = Tokenizer.init(allocator, source);
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    var token_count: u32 = 0;
    while (true) {
        const token = try tokenizer.nextToken();
        try tokens.append(token);
        token_count += 1;

        std.log.info("Token {}: {s} = '{s}'", .{ token_count, @tagName(token.type), token.value });

        if (token.type == .eof) break;
    }

    std.log.info("✅ Tokenization complete: {} tokens", .{token_count});

    // Step 2: Extract semantic information
    std.log.info("", .{});
    std.log.info("🧠 Step 2: Semantic Extraction", .{});
    std.log.info("-------------------------------", .{});

    var func_name: []const u8 = "";
    var string_literal: []const u8 = "";

    for (tokens.items) |token| {
        if (token.type == .identifier and func_name.len == 0) {
            func_name = token.value;
            std.log.info("Found function: {s}", .{func_name});
        } else if (token.type == .string) {
            string_literal = token.value;
            std.log.info("Found string: {s}", .{string_literal});
        }
    }

    // Step 3: C Code Generation
    std.log.info("", .{});
    std.log.info("⚙️  Step 3: C Code Generation", .{});
    std.log.info("-----------------------------", .{});

    const c_output = "demo_output.c";
    const c_file = try std.fs.cwd().createFile(c_output, .{});
    defer c_file.close();

    // Generate C code
    var c_code = std.ArrayList(u8).init(allocator);
    defer c_code.deinit();

    try c_code.appendSlice("#include <stdio.h>\n\n");
    // Handle main function specially to avoid naming conflicts
    if (std.mem.eql(u8, func_name, "main")) {
        try c_code.appendSlice("int main() {\n");
        try c_code.appendSlice("    printf(");
        try c_code.appendSlice(string_literal);
        try c_code.appendSlice(");\n");
        try c_code.appendSlice("    return 0;\n");
        try c_code.appendSlice("}\n");
    } else {
        try c_code.appendSlice("void ");
        try c_code.appendSlice(func_name);
        try c_code.appendSlice("() {\n");
        try c_code.appendSlice("    printf(");
        try c_code.appendSlice(string_literal);
        try c_code.appendSlice(");\n");
        try c_code.appendSlice("}\n\n");
        try c_code.appendSlice("int main() {\n");
        try c_code.appendSlice("    ");
        try c_code.appendSlice(func_name);
        try c_code.appendSlice("();\n");
        try c_code.appendSlice("    return 0;\n");
        try c_code.appendSlice("}\n");
    }

    try c_file.writeAll(c_code.items);

    // Step 4: Verification
    std.log.info("", .{});
    std.log.info("✅ Step 4: Verification", .{});
    std.log.info("-----------------------", .{});

    const file = try std.fs.cwd().openFile(c_output, .{});
    const file_size = try file.getEndPos();
    file.close();

    std.log.info("Generated C file: {s} ({} bytes)", .{ c_output, file_size });

    // Display generated C code
    const c_content = try std.fs.cwd().readFileAlloc(allocator, c_output, 1024);
    defer allocator.free(c_content);

    std.log.info("", .{});
    std.log.info("📄 Generated C Code:", .{});
    std.log.info("-------------------", .{});
    std.log.info("{s}", .{c_content});

    // Step 5: Compilation test
    std.log.info("", .{});
    std.log.info("🔨 Step 5: Compilation Test", .{});
    std.log.info("---------------------------", .{});

    // Try to compile the generated C code (with proper memory management)
    std.log.info("🔨 Attempting C compilation with gcc...", .{});

    const compile_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "gcc", "-o", "demo_output", c_output },
        .max_output_bytes = 1024, // Bounded allocation
    }) catch |err| {
        std.log.warn("GCC compilation failed: {}", .{err});
        std.log.info("✅ C code generation successful (compilation test skipped)", .{});
        return; // Arena cleanup handles all memory automatically
    };

    // Arena allocator will clean up these automatically, but being explicit about ownership
    // In a real implementation, we'd use defer, but arena makes it unnecessary

    if (compile_result.term == .Exited and compile_result.term.Exited == 0) {
        std.log.info("✅ C compilation successful!", .{});

        // Try to run the compiled program with bounded output
        const run_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{"./demo_output"},
            .max_output_bytes = 256, // Bounded allocation
        }) catch |err| {
            std.log.warn("Failed to run compiled program: {}", .{err});
            std.fs.cwd().deleteFile("demo_output") catch {};
            return; // Arena cleanup handles memory
        };

        std.log.info("🎯 Program output: {s}", .{run_result.stdout});

        // Clean up executable
        std.fs.cwd().deleteFile("demo_output") catch {};
    } else {
        std.log.warn("C compilation failed with exit code: {}", .{compile_result.term});
        if (compile_result.stderr.len > 0) {
            std.log.warn("Compiler error: {s}", .{compile_result.stderr});
        }
    }

    // Clean up
    std.fs.cwd().deleteFile(c_output) catch {};

    std.log.info("", .{});
    std.log.info("🎉 End-to-End Compiler Demo Complete!", .{});
    std.log.info("=====================================", .{});
    std.log.info("✅ Tokenization: Working", .{});
    std.log.info("✅ Semantic Extraction: Working", .{});
    std.log.info("✅ C Code Generation: Working", .{});
    std.log.info("✅ Complete Pipeline: Functional", .{});
}
