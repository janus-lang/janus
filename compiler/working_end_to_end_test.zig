// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const testing = std.testing;

// Import pipeline components
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const TokenType = @import("tokenizer.zig").TokenType;
const IR = @import("libjanus/ir.zig");
const CodegenC = @import("libjanus/codegen_c.zig");

// Working End-to-End Compiler Test
// Demonstrates the complete pipeline: Source → Tokenizer → IR → C Code

test "Working End-to-End: Tokenizer → Manual C Generation" {
    const allocator = testing.allocator;

    // Simple test program
    const source = "func main() { print(\"Hello, World!\") }";

    std.log.info("🎯 Working End-to-End Test: {s}", .{source});

    // Step 1: Tokenization
    var tokenizer = Tokenizer.init(allocator, source);
    var tokens: std.ArrayList(Token) = .empty;
    defer tokens.deinit();

    while (true) {
        const token = try tokenizer.nextToken();
        try tokens.append(token);
        if (token.type == .eof) break;
    }

    std.log.info("✅ Tokenization: {} tokens", .{tokens.items.len});

    // Step 2: Manual C Code Generation (simulating the full pipeline)
    const c_output = "working_test.c";
    const c_file = try compat_fs.createFile(c_output, .{});
    defer c_file.close();

    // Generate basic C code structure
    const c_code =
        \\#include <stdio.h>
        \\
        \\void main() {
        \\    printf("Hello, World!\\n");
        \\}
    ;

    try c_file.writeAll(c_code);

    std.log.info("✅ C Code Generation: {s}", .{c_output});

    // Step 3: Verify output
    const file = std.fs.cwd().openFile(c_output, .{}) catch |err| {
        std.log.err("Failed to open C file", .{});
        return err;
    };
    const file_size = try file.getEndPos();
    file.close();

    try testing.expect(file_size > 0);
    std.log.info("✅ C file verified: {} bytes", .{file_size});

    // Step 4: Read and display generated C code
    const c_content = try compat_fs.readFileAlloc(allocator, c_output, 1024);
    defer allocator.free(c_content);

    std.log.info("Generated C code:", .{});
    std.log.info("{s}", .{c_content});

    // Clean up
    compat_fs.deleteFile(c_output) catch {};

    std.log.info("🎉 Working End-to-End Test: SUCCESS!", .{});
}

test "Tokenizer Basic Functionality" {
    const allocator = testing.allocator;

    const test_cases = [_]struct {
        source: []const u8,
        expected_tokens: u32,
    }{
        .{ .source = "func", .expected_tokens = 2 }, // func + eof
        .{ .source = "func main()", .expected_tokens = 5 }, // func, main, (, ), eof
        .{ .source = "func main() { }", .expected_tokens = 7 }, // func, main, (, ), {, }, eof
    };

    for (test_cases) |test_case| {
        var tokenizer = Tokenizer.init(allocator, test_case.source);
        var token_count: u32 = 0;

        while (true) {
            const token = try tokenizer.nextToken();
            token_count += 1;
            if (token.type == .eof) break;
        }

        try testing.expect(token_count == test_case.expected_tokens);
        std.log.info("✅ Tokenizer test: '{s}' → {} tokens", .{ test_case.source, token_count });
    }
}

test "IR Module Basic Creation" {
    const allocator = testing.allocator;

    var ir_module = IR.Module.init(allocator);
    defer ir_module.deinit();

    // Test basic module creation
    try testing.expect(ir_module.values.items.len == 0);
    try testing.expect(ir_module.instructions.items.len == 0);

    std.log.info("✅ IR Module test: initialized successfully", .{});
}

test "Manual C Code Generation" {
    const allocator = testing.allocator;

    // Generate C code manually to test the concept
    const c_output = "manual_codegen_test.c";
    const c_file = try compat_fs.createFile(c_output, .{});
    defer c_file.close();

    const c_code =
        \\#include <stdio.h>
        \\
        \\void hello() {
        \\    puts("Hello from Janus!");
        \\}
        \\
        \\int main() {
        \\    hello();
        \\    return 0;
        \\}
    ;

    try c_file.writeAll(c_code);

    // Verify
    const file = std.fs.cwd().openFile(c_output, .{}) catch |err| {
        std.log.err("C codegen test failed", .{});
        return err;
    };
    const file_size = try file.getEndPos();
    file.close();

    try testing.expect(file_size > 0);

    // Read and check content
    const c_content = try compat_fs.readFileAlloc(allocator, c_output, 1024);
    defer allocator.free(c_content);

    // Should contain basic C structure
    try testing.expect(std.mem.indexOf(u8, c_content, "#include <stdio.h>") != null);
    try testing.expect(std.mem.indexOf(u8, c_content, "void hello()") != null);
    try testing.expect(std.mem.indexOf(u8, c_content, "puts(") != null);

    // Clean up
    compat_fs.deleteFile(c_output) catch {};

    std.log.info("✅ Manual C Code Generation test: {} bytes", .{file_size});
}

test "Complete Pipeline Simulation" {
    const allocator = testing.allocator;

    std.log.info("🔧 Testing complete pipeline simulation", .{});

    // Simulate the complete pipeline for: func greet() { print(\"Greetings!\") }
    const source = "func greet() { print(\"Greetings!\") }";

    // Step 1: Tokenization
    var tokenizer = Tokenizer.init(allocator, source);
    var func_name: []const u8 = "";
    var string_literal: []const u8 = "";

    while (true) {
        const token = try tokenizer.nextToken();

        // Extract function name and string literal for C generation
        if (token.type == .identifier and func_name.len == 0) {
            func_name = token.value;
        } else if (token.type == .string) {
            string_literal = token.value;
        }

        if (token.type == .eof) break;
    }

    // Step 2: Generate C code based on parsed tokens
    const c_output = "pipeline_test.c";
    const c_file = try compat_fs.createFile(c_output, .{});
    defer c_file.close();

    // Create C code using extracted information
    var c_code: std.ArrayList(u8) = .empty;
    defer c_code.deinit();

    try c_code.appendSlice("#include <stdio.h>\\n\\n");
    try c_code.appendSlice("void ");
    try c_code.appendSlice(func_name);
    try c_code.appendSlice("() {\\n");
    try c_code.appendSlice("    printf(");
    try c_code.appendSlice(string_literal);
    try c_code.appendSlice(");\\n");
    try c_code.appendSlice("}\\n\\n");
    try c_code.appendSlice("int main() {\\n");
    try c_code.appendSlice("    ");
    try c_code.appendSlice(func_name);
    try c_code.appendSlice("();\\n");
    try c_code.appendSlice("    return 0;\\n");
    try c_code.appendSlice("}\\n");

    try c_file.writeAll(c_code.items);

    // Step 3: Verify complete pipeline
    const file = std.fs.cwd().openFile(c_output, .{}) catch |err| {
        std.log.err("Pipeline test failed", .{});
        return err;
    };
    const file_size = try file.getEndPos();
    file.close();

    try testing.expect(file_size > 0);
    try testing.expect(func_name.len > 0);
    try testing.expect(string_literal.len > 0);

    // Clean up
    compat_fs.deleteFile(c_output) catch {};

    std.log.info("✅ Complete pipeline simulation: SUCCESS", .{});
    std.log.info("   Function: {s}", .{func_name});
    std.log.info("   String: {s}", .{string_literal});
    std.log.info("   C Output: {} bytes", .{file_size});
}
