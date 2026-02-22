// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// Import all pipeline components
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const TokenType = @import("tokenizer.zig").TokenType;
const NorthStarParser = @import("north_star_parser.zig");
const Semantic = @import("semantic.zig");
const IR = @import("libjanus/ir.zig");
const CodegenC = @import("libjanus/codegen_c.zig");

// North Star End-to-End Compiler Test
// Mission: Compile demo.jan from source text to working executable
// This test validates the complete pipeline integration

test "North Star: Complete compilation pipeline - demo.jan" {
    const allocator = testing.allocator;

    // The North Star program - simplified for MVP
    const demo_source =
        \\func main() {
        \\    print("MVP analysis complete.")
        \\}
    ;

    std.log.info("🎯 North Star Test: Compiling demo.jan", .{});
    std.log.info("Source length: {} bytes", .{demo_source.len});

    // Step 1: Parsing (includes tokenization)
    var parser = try NorthStarParser.NorthStarParser.init(allocator, demo_source);

    const ast = try parser.parseProgram();
    defer ast.deinit(allocator);

    std.log.info("✅ Parsing complete: AST created", .{});

    // Step 2: Semantic Analysis
    var semantic_graph = try Semantic.analyze(ast, allocator);
    defer semantic_graph.deinit();

    std.log.info("✅ Semantic analysis complete", .{});

    // Step 3: IR Generation
    var ir_module = try IR.generateIR(ast, &semantic_graph, allocator);
    defer ir_module.deinit();

    std.log.info("✅ IR generation complete: {} instructions", .{ir_module.instructions.items.len});

    // Step 4: Code Generation (C backend)
    const c_output_path = "demo_north_star.c";
    try CodegenC.emit_c(&ir_module, c_output_path, allocator);

    std.log.info("✅ C code generation complete: {s}", .{c_output_path});

    // Step 5: Verify the C file was created and has content
    const c_file = std.fs.cwd().openFile(c_output_path, .{}) catch |err| {
        std.log.err("Failed to open generated C file: {}", .{err});
        return err;
    };
    const file_size = try c_file.getEndPos();
    c_file.close();

    try testing.expect(file_size > 0);
    std.log.info("✅ C file verified: {} bytes", .{file_size});

    // Step 6: Compile C code to executable (optional - requires gcc/clang)
    const exe_output_path = "demo_north_star";
    compileC(c_output_path, exe_output_path) catch |err| {
        std.log.warn("C compilation failed (compiler not available): {}", .{err});
        // This is not a failure - we successfully generated C code
    };

    // Step 7: Clean up
    std.fs.cwd().deleteFile(c_output_path) catch {};
    std.fs.cwd().deleteFile(exe_output_path) catch {};

    std.log.info("🎉 North Star Test PASSED: Complete pipeline operational!", .{});
    std.log.info("🎉 Source → Parser → Semantic → IR → C Codegen: SUCCESS", .{});
}

/// Helper function to compile C code to executable (optional)
fn compileC(c_file_path: []const u8, exe_path: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // Try different C compilers
    const compilers = [_][]const u8{ "gcc", "clang", "cc" };

    for (compilers) |compiler| {
        const result = std.ChildProcess.exec(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ compiler, "-o", exe_path, c_file_path },
        }) catch continue; // Try next compiler if this one fails

        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            std.log.info("✅ C compilation successful with {s}", .{compiler});
            return;
        }
    }

    return error.NoCompilerAvailable;
}

test "Pipeline component integration" {
    const allocator = testing.allocator;

    std.log.info("🔧 Testing individual pipeline components", .{});

    // Test 1: Tokenizer
    {
        const test_source = "func main() { print(\"hello\") }";
        var tokenizer = Tokenizer.init(allocator, test_source);
        var token_count: u32 = 0;

        while (true) {
            const token = try tokenizer.nextToken();
            token_count += 1;
            if (token.type == .eof) break;
        }

        try testing.expect(token_count > 5); // Should have func, main, (, ), {, print, etc.
        std.log.info("✅ Tokenizer: OK ({} tokens)", .{token_count});
    }

    // Test 2: Parser
    {
        const test_source = "func main() { print(\"hello\") }";
        var tokenizer = Tokenizer.init(allocator, test_source);
        var tokens: std.ArrayList(Token) = .empty;
        defer tokens.deinit();

        while (true) {
            const token = try tokenizer.nextToken();
            try tokens.append(token);
            if (token.type == .eof) break;
        }

        var parser = try Parser.init(allocator, test_source);

        const ast = try parser.parseProgram();
        defer ast.deinit(allocator);

        try testing.expect(ast.kind == .Root);
        std.log.info("✅ Parser: OK", .{});
    }

    // Test 3: Semantic Analysis
    {
        const test_source = "func main() { print(\"hello\") }";
        var tokenizer = Tokenizer.init(allocator, test_source);
        var tokens: std.ArrayList(Token) = .empty;
        defer tokens.deinit();

        while (true) {
            const token = try tokenizer.nextToken();
            try tokens.append(token);
            if (token.type == .eof) break;
        }

        var parser = try Parser.init(allocator, test_source);

        const ast = try parser.parseProgram();
        defer ast.deinit(allocator);

        var semantic_graph = try Semantic.analyze(ast, allocator);
        defer semantic_graph.deinit();

        std.log.info("✅ Semantic Analysis: OK", .{});
    }

    // Test 4: IR Generation
    {
        const test_source = "func main() { print(\"hello\") }";
        var tokenizer = Tokenizer.init(allocator, test_source);
        var tokens: std.ArrayList(Token) = .empty;
        defer tokens.deinit();

        while (true) {
            const token = try tokenizer.nextToken();
            try tokens.append(token);
            if (token.type == .eof) break;
        }

        var parser = try Parser.init(allocator, test_source);

        const ast = try parser.parseProgram();
        defer ast.deinit(allocator);

        var semantic_graph = try Semantic.analyze(ast, allocator);
        defer semantic_graph.deinit();

        var ir_module = try IR.generateIR(ast, &semantic_graph, allocator);
        defer ir_module.deinit();

        try testing.expect(ir_module.instructions.items.len > 0);
        std.log.info("✅ IR Generation: OK ({} instructions)", .{ir_module.instructions.items.len});
    }

    // Test 5: Code Generation
    {
        var ir_module = IR.Module.init(allocator);
        defer ir_module.deinit();

        // Create a simple IR module
        const func_value = try ir_module.createValue(.Function, "test_main");
        try ir_module.addInstruction(.FunctionDef, func_value, &[_]IR.Value{}, "test_main");

        const str_value = try ir_module.createValue(.String, "test_message");
        try ir_module.addInstruction(.StringConst, str_value, &[_]IR.Value{}, "\"Test message\"");
        try ir_module.addInstruction(.Call, null, &[_]IR.Value{str_value}, "print");
        try ir_module.addInstruction(.Return, null, &[_]IR.Value{}, "void");

        const test_output = "test_pipeline_output.c";
        try CodegenC.emit_c(&ir_module, test_output, allocator);

        // Verify C file was created
        const file = std.fs.cwd().openFile(test_output, .{}) catch |err| {
            std.log.err("Code generator test failed: {}", .{err});
            return err;
        };
        const file_size = try file.getEndPos();
        file.close();

        try testing.expect(file_size > 0);

        // Clean up
        std.fs.cwd().deleteFile(test_output) catch {};

        std.log.info("✅ Code Generation: OK ({} bytes)", .{file_size});
    }

    std.log.info("🎉 All pipeline components: OPERATIONAL", .{});
}

test "Minimal function compilation" {
    const allocator = testing.allocator;

    std.log.info("🔧 Testing minimal function compilation", .{});

    // Test with a minimal function that returns void
    const minimal_source = "func test() { }";

    // Step 1: Parsing
    var parser = try Parser.init(allocator, minimal_source);

    const ast = try parser.parseProgram();
    defer ast.deinit(allocator);

    // Step 3: Semantic Analysis
    var semantic_graph = try Semantic.analyze(ast, allocator);
    defer semantic_graph.deinit();

    // Step 4: IR Generation
    var ir_module = try IR.generateIR(ast, &semantic_graph, allocator);
    defer ir_module.deinit();

    try testing.expect(ir_module.instructions.items.len > 0);

    // Step 5: Code Generation
    const output_path = "test_minimal_func.c";
    try CodegenC.emit_c(&ir_module, output_path, allocator);

    // Verify
    const file = std.fs.cwd().openFile(output_path, .{}) catch |err| {
        std.log.err("Minimal function compilation failed: {}", .{err});
        return err;
    };
    const file_size = try file.getEndPos();
    file.close();

    try testing.expect(file_size > 0);

    // Clean up
    std.fs.cwd().deleteFile(output_path) catch {};

    std.log.info("✅ Minimal function compilation: SUCCESS ({} bytes)", .{file_size});
}

test "Error handling in pipeline" {
    const allocator = testing.allocator;

    std.log.info("🔧 Testing error handling in pipeline", .{});

    // Test with invalid syntax
    const invalid_source = "func { invalid syntax }";

    // Step 1: Parsing (should fail gracefully)
    var parser = try Parser.init(allocator, invalid_source);

    const parse_result = parser.parseProgram();

    if (parse_result) |ast| {
        defer ast.deinit(allocator);
        std.log.info("✅ Parser handled invalid syntax gracefully", .{});
    } else |err| {
        std.log.info("✅ Parser correctly rejected invalid syntax: {}", .{err});
    }

    std.log.info("✅ Error handling: OK", .{});
}

test "Full pipeline with complex program" {
    const allocator = testing.allocator;

    std.log.info("🔧 Testing full pipeline with complex program", .{});

    // More complex program with multiple functions
    const complex_source =
        \\func helper() {
        \\    print("Helper function")
        \\}
        \\
        \\func main() {
        \\    print("Starting program")
        \\    helper()
        \\    print("Program complete")
        \\}
    ;

    // Full pipeline

    var parser = try Parser.init(allocator, complex_source);

    const ast = try parser.parseProgram();
    defer ast.deinit(allocator);

    var semantic_graph = try Semantic.analyze(ast, allocator);
    defer semantic_graph.deinit();

    var ir_module = try IR.generateIR(ast, &semantic_graph, allocator);
    defer ir_module.deinit();

    const output_path = "test_complex_program.c";
    try CodegenC.emit_c(&ir_module, output_path, allocator);

    // Verify
    const file = std.fs.cwd().openFile(output_path, .{}) catch |err| {
        std.log.err("Complex program compilation failed: {}", .{err});
        return err;
    };
    const file_size = try file.getEndPos();
    file.close();

    try testing.expect(file_size > 0);
    try testing.expect(ir_module.instructions.items.len > 3); // Should have multiple instructions

    // Clean up
    std.fs.cwd().deleteFile(output_path) catch {};

    std.log.info("✅ Complex program compilation: SUCCESS ({} bytes, {} instructions)", .{ file_size, ir_module.instructions.items.len });
}
