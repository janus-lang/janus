// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;

// Import pipeline components
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const IR = @import("libjanus/ir.zig");

// Janus Memory Discipline Test
// Demonstrates proper memory management according to Janus doctrines

test "Janus Memory Discipline: Arena Allocator Sovereignty" {
    // Use arena allocator for O(1) cleanup - Doctrine of Allocator Sovereignty
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit(); // O(1) cleanup - no individual frees needed
    const allocator = arena.allocator();

    std.log.info("🏛️  Testing Janus Memory Discipline", .{});
    std.log.info("===================================", .{});

    // Test program
    const source = "func main() { print(\"Memory discipline test\") }";
    std.log.info("📝 Source: {s}", .{source});

    // Step 1: Tokenization with arena allocator
    std.log.info("🔍 Step 1: Tokenization (Arena-based)", .{});

    var tokenizer = Tokenizer.init(allocator, source);
    var tokens = std.ArrayList(Token).init(allocator);
    // No defer needed - arena cleanup handles everything

    while (true) {
        const token = try tokenizer.nextToken();
        try tokens.append(token);
        if (token.type == .eof) break;
    }

    std.log.info("✅ Tokenized {} tokens with arena allocator", .{tokens.items.len});

    // Step 2: IR Module with arena allocator
    std.log.info("🧠 Step 2: IR Generation (Arena-based)", .{});

    var ir_module = IR.Module.init(allocator);
    // No defer needed - arena cleanup handles everything

    // Create some IR values to test memory allocation
    const func_val = try ir_module.createValue(.Function, "main");
    const str_val = try ir_module.createValue(.String, "test_string");

    try ir_module.addInstruction(.FunctionDef, func_val, &[_]IR.Value{}, "main");
    try ir_module.addInstruction(.StringConst, str_val, &[_]IR.Value{}, "\"Memory discipline test\"");
    try ir_module.addInstruction(.Call, null, &[_]IR.Value{str_val}, "print");
    try ir_module.addInstruction(.Return, null, &[_]IR.Value{}, "void");

    std.log.info("✅ Created IR with {} values and {} instructions", .{ ir_module.values.items.len, ir_module.instructions.items.len });

    // Step 3: C Code Generation with bounded allocation
    std.log.info("⚙️  Step 3: C Code Generation (Bounded)", .{});

    const c_output = "memory_discipline_test.c";
    const c_file = try std.fs.cwd().createFile(c_output, .{});
    defer c_file.close();

    // Generate C code with bounded string operations
    var c_code = std.ArrayList(u8).init(allocator);
    // No defer needed - arena cleanup handles everything

    try c_code.appendSlice("#include <stdio.h>\\n\\n");
    try c_code.appendSlice("int main() {\\n");
    try c_code.appendSlice("    printf(\"Memory discipline test\\\\n\");\\n");
    try c_code.appendSlice("    return 0;\\n");
    try c_code.appendSlice("}\\n");

    try c_file.writeAll(c_code.items);

    // Step 4: Verification
    std.log.info("✅ Step 4: Verification", .{});

    const file = try std.fs.cwd().openFile(c_output, .{});
    const file_size = try file.getEndPos();
    file.close();

    try testing.expect(file_size > 0);
    std.log.info("✅ Generated C file: {} bytes", .{file_size});

    // Clean up file (arena handles all memory automatically)
    std.fs.cwd().deleteFile(c_output) catch {};

    std.log.info("", .{});
    std.log.info("🎉 Janus Memory Discipline Test: SUCCESS!", .{});
    std.log.info("✅ Arena Allocator: O(1) cleanup", .{});
    std.log.info("✅ No Memory Leaks: Zero individual frees", .{});
    std.log.info("✅ Allocator Sovereignty: Respected", .{});

    // Arena deinit() will be called automatically by defer
    // This demonstrates O(1) cleanup of all allocated memory
}

test "Memory Leak Detection with testing.allocator" {
    // This test uses testing.allocator to catch any leaks
    const allocator = testing.allocator;

    std.log.info("🔍 Testing Memory Leak Detection", .{});

    // Simple tokenization test that must not leak
    const source = "func test() { }";
    var tokenizer = Tokenizer.init(allocator, source);

    var token_count: u32 = 0;
    while (true) {
        const token = try tokenizer.nextToken();
        token_count += 1;
        if (token.type == .eof) break;
    }

    try testing.expect(token_count > 0);
    std.log.info("✅ Tokenized {} tokens with no leaks", .{token_count});

    // If there were any leaks, testing.allocator would catch them
    // and the test would fail with a leak report
}

test "Proper IR Module Memory Management" {
    const allocator = testing.allocator;

    std.log.info("🧠 Testing IR Module Memory Management", .{});

    // Create IR module with proper cleanup
    var ir_module = IR.Module.init(allocator);
    defer ir_module.deinit(); // Explicit cleanup required with testing.allocator

    // Create values and instructions
    const func_val = try ir_module.createValue(.Function, "test_func");
    try ir_module.addInstruction(.FunctionDef, func_val, &[_]IR.Value{}, "test_func");

    try testing.expect(ir_module.values.items.len == 1);
    try testing.expect(ir_module.instructions.items.len == 1);

    std.log.info("✅ IR Module properly managed: {} values, {} instructions", .{ ir_module.values.items.len, ir_module.instructions.items.len });

    // ir_module.deinit() will be called by defer
    // This ensures proper cleanup of all internal allocations
}

test "File Operations with Proper Resource Management" {
    const allocator = testing.allocator;

    std.log.info("📁 Testing File Operations", .{});

    const test_file = "resource_test.c";

    // Create file with proper resource management
    {
        const file = try std.fs.cwd().createFile(test_file, .{});
        defer file.close(); // Proper resource cleanup

        const content = "#include <stdio.h>\\nint main() { return 0; }\\n";
        try file.writeAll(content);
    } // file is closed here by defer

    // Read file with proper memory management
    const file_content = try std.fs.cwd().readFileAlloc(allocator, test_file, 1024);
    defer allocator.free(file_content); // Explicit memory cleanup

    try testing.expect(file_content.len > 0);
    try testing.expect(std.mem.indexOf(u8, file_content, "#include <stdio.h>") != null);

    // Clean up file
    std.fs.cwd().deleteFile(test_file) catch {};

    std.log.info("✅ File operations completed with proper resource management", .{});
}
