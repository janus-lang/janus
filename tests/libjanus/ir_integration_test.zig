// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const IR = @import("../../compiler/libjanus/ir.zig");
const Parser = @import("../../compiler/libjanus/parser.zig");
const Semantic = @import("../../compiler/libjanus/semantic.zig");
const Tokenizer = @import("../../compiler/libjanus/tokenizer.zig");

// Test helper to create semantic graph from source
fn analyzeForTest(source: []const u8, allocator: std.mem.Allocator) !struct { ast: *Parser.Node, graph: Semantic.SemanticGraph } {
    const tokens = try Tokenizer.tokenize(source, allocator);
    defer allocator.free(tokens);

    const ast = try Parser.parse(tokens, allocator);
    const graph = try Semantic.analyze(ast, allocator);

    return .{ .ast = ast, .graph = graph };
}

test "ir: simple function IR generation" {
    const allocator = testing.allocator;

    const source = "func main() { print(\"Hello\") }";
    const result = try analyzeForTest(source, allocator);
    defer {
        result.ast.deinit(allocator);
        allocator.destroy(result.ast);
        var graph = result.graph;
        graph.deinit();
    }

    var ir_module = try IR.generateIR(result.ast, &result.graph, allocator);
    defer ir_module.deinit();

    // Should have instructions for: function def, string const, call, return
    try testing.expect(ir_module.instructions.items.len >= 3);

    // Check function definition
    const func_def = ir_module.instructions.items[0];
    try testing.expect(func_def.kind == .FunctionDef);
    try testing.expect(func_def.result != null);
    try testing.expect(func_def.result.?.type == .Function);
    try testing.expectEqualStrings("main", func_def.metadata);

    // Should have string constant
    var found_string = false;
    var found_call = false;
    var found_return = false;

    for (ir_module.instructions.items) |instruction| {
        switch (instruction.kind) {
            .StringConst => {
                found_string = true;
                try testing.expect(instruction.result != null);
                try testing.expect(instruction.result.?.type == .String);
            },
            .Call => {
                found_call = true;
                try testing.expect(instruction.operands.len > 0);
            },
            .Return => {
                found_return = true;
            },
            else => {},
        }
    }

    try testing.expect(found_string);
    try testing.expect(found_call);
    try testing.expect(found_return);
}

test "ir: string constant generation" {
    const allocator = testing.allocator;

    const source = "func test() { print(\"test string\") }";
    const result = try analyzeForTest(source, allocator);
    defer {
        result.ast.deinit(allocator);
        allocator.destroy(result.ast);
        var graph = result.graph;
        graph.deinit();
    }

    var ir_module = try IR.generateIR(result.ast, &result.graph, allocator);
    defer ir_module.deinit();

    // Find string constant instruction
    var string_const: ?IR.Instruction = null;
    for (ir_module.instructions.items) |instruction| {
        if (instruction.kind == .StringConst) {
            string_const = instruction;
            break;
        }
    }

    try testing.expect(string_const != null);
    try testing.expect(string_const.?.result != null);
    try testing.expect(string_const.?.result.?.type == .String);
    try testing.expectEqualStrings("\"test string\"", string_const.?.metadata);
}

test "ir: function call generation" {
    const allocator = testing.allocator;

    const source = "func example() { print(\"message\") }";
    const result = try analyzeForTest(source, allocator);
    defer {
        result.ast.deinit(allocator);
        allocator.destroy(result.ast);
        var graph = result.graph;
        graph.deinit();
    }

    var ir_module = try IR.generateIR(result.ast, &result.graph, allocator);
    defer ir_module.deinit();

    // Find call instruction
    var call_instr: ?IR.Instruction = null;
    for (ir_module.instructions.items) |instruction| {
        if (instruction.kind == .Call) {
            call_instr = instruction;
            break;
        }
    }

    try testing.expect(call_instr != null);
    try testing.expect(call_instr.?.operands.len > 0); // Should have string argument
    try testing.expect(std.mem.indexOf(u8, call_instr.?.metadata, "print") != null);
}

test "ir: empty program" {
    const allocator = testing.allocator;

    const source = "";
    const result = try analyzeForTest(source, allocator);
    defer {
        result.ast.deinit(allocator);
        allocator.destroy(result.ast);
        var graph = result.graph;
        graph.deinit();
    }

    var ir_module = try IR.generateIR(result.ast, &result.graph, allocator);
    defer ir_module.deinit();

    // Empty program should have no instructions
    try testing.expect(ir_module.instructions.items.len == 0);
}

test "ir: value creation and management" {
    const allocator = testing.allocator;

    var module = IR.Module.init(allocator);
    defer module.deinit();

    // Test value creation
    const value1 = try module.createValue(.String, "test1");
    const value2 = try module.createValue(.Function, "test2");

    try testing.expect(value1.id == 0);
    try testing.expect(value2.id == 1);
    try testing.expect(value1.type == .String);
    try testing.expect(value2.type == .Function);
    try testing.expectEqualStrings("test1", value1.name);
    try testing.expectEqualStrings("test2", value2.name);

    // Test instruction creation
    try module.addInstruction(.StringConst, value1, &[_]IR.Value{}, "test metadata");

    try testing.expect(module.instructions.items.len == 1);
    const instruction = module.instructions.items[0];
    try testing.expect(instruction.kind == .StringConst);
    try testing.expect(instruction.result != null);
    try testing.expect(instruction.result.?.id == value1.id);
}

test "ir: instruction formatting" {
    const allocator = testing.allocator;

    var module = IR.Module.init(allocator);
    defer module.deinit();

    const value = try module.createValue(.String, "hello");
    try module.addInstruction(.StringConst, value, &[_]IR.Value{}, "\"hello\"");

    // Test that we can format instructions (basic smoke test)
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    const writer = buffer.writer();
    try module.print(writer);

    const output = buffer.items;
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "StringConst") != null);
}

test "ir: value type system" {
    // Test value type string representation
    try testing.expectEqualStrings("void", IR.ValueType.Void.toString());
    try testing.expectEqualStrings("string", IR.ValueType.String.toString());
    try testing.expectEqualStrings("function", IR.ValueType.Function.toString());
}
