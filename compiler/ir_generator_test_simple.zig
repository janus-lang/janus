// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("libjanus/astdb.zig");
const Snapshot = astdb.Snapshot;
const interner = @import("libjanus/astdb/granite_interner.zig");
const SemanticAnalyzer = @import("semantic_analyzer.zig").SemanticAnalyzer;
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const IRQueries = @import("ir_generator.zig").IRQueries;
const JanusIR = @import("ir_generator.zig").JanusIR;

// Revolutionary IR Generation Tests - Proving the Transmutation Engine
// Task: Phase 4 - Validate Q.IROf and complete pipeline from source to IR

test "IR Generator initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create interner and snapshot
    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    // Create semantic analyzer
    var semantic_analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    // Create IR generator
    var ir_generator = try IRGenerator.init(allocator, snapshot, &str_interner, &semantic_analyzer);
    defer ir_generator.deinit();

    // Verify initialization
    try testing.expect(ir_generator.next_register == 0);
    try testing.expect(ir_generator.next_block_id == 0);

    std.debug.print("✅ IR Generator initialization test passed\n", .{});
}

test "Q.IROf - Simple function IR generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create interner and snapshot
    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    // Create global scope
    const global_scope = try snapshot.addScope(astdb.ids.INVALID_SCOPE_ID);

    // Create a simple function: fn test() { return; }
    const function_name_id = try str_interner.get("test");

    // Create tokens
    const func_token = try snapshot.addToken(.kw_func, function_name_id, astdb.Span{
        .start_byte = 0,
        .end_byte = 4,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 5,
    });

    // Create parameter list (empty)
    const param_list_id = try snapshot.addNode(.expr_stmt, func_token, func_token, &[_]astdb.NodeId{});

    // Create function body block
    const return_stmt_id = try snapshot.addNode(.return_stmt, func_token, func_token, &[_]astdb.NodeId{});
    const block_id = try snapshot.addNode(.block_stmt, func_token, func_token, &[_]astdb.NodeId{return_stmt_id});

    // Create function node with children
    const function_node_id = try snapshot.addNode(.func_decl, func_token, func_token, &[_]astdb.NodeId{ param_list_id, block_id });

    // Create function declaration
    const function_decl_id = try snapshot.addDecl(function_node_id, function_name_id, global_scope, .function);

    // Create semantic analyzer and IR generator
    var semantic_analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    var ir_generator = try IRGenerator.init(allocator, snapshot, &str_interner, &semantic_analyzer);
    defer ir_generator.deinit();

    var ir_queries = IRQueries.init(&ir_generator);

    // Generate IR
    var function_ir = try ir_queries.irOf(function_decl_id);
    defer function_ir.deinit(allocator);

    // Validate generated IR
    try testing.expect(function_ir.basic_blocks.len > 0);
    try testing.expectEqualStrings("test", function_ir.function_name);
    try testing.expect(function_ir.parameters.len == 0);

    // Validate IR structure
    try testing.expect(try ir_queries.validateIR(&function_ir));

    std.debug.print("✅ Q.IROf simple function test passed\n", .{});
}

test "Q.IROf - Function with parameters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create interner and snapshot
    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    // Create global scope
    const global_scope = try snapshot.addScope(astdb.ids.INVALID_SCOPE_ID);

    // Create function: fn add(a: i32, b: i32) { return a + b; }
    const function_name_id = try str_interner.get("add");
    const param_a_id = try str_interner.get("a");
    const param_b_id = try str_interner.get("b");

    // Create tokens
    const func_token = try snapshot.addToken(.kw_func, function_name_id, astdb.Span{
        .start_byte = 0,
        .end_byte = 3,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 4,
    });

    const param_a_token = try snapshot.addToken(.identifier, param_a_id, astdb.Span{
        .start_byte = 4,
        .end_byte = 5,
        .start_line = 1,
        .start_col = 5,
        .end_line = 1,
        .end_col = 6,
    });

    const param_b_token = try snapshot.addToken(.identifier, param_b_id, astdb.Span{
        .start_byte = 6,
        .end_byte = 7,
        .start_line = 1,
        .start_col = 7,
        .end_line = 1,
        .end_col = 8,
    });

    // Create parameter nodes
    const param_a_name_id = try snapshot.addNode(.identifier, param_a_token, param_a_token, &[_]astdb.NodeId{});
    const param_a_node_id = try snapshot.addNode(.var_decl, param_a_token, param_a_token, &[_]astdb.NodeId{param_a_name_id});

    const param_b_name_id = try snapshot.addNode(.identifier, param_b_token, param_b_token, &[_]astdb.NodeId{});
    const param_b_node_id = try snapshot.addNode(.var_decl, param_b_token, param_b_token, &[_]astdb.NodeId{param_b_name_id});

    // Create parameter list
    const param_list_id = try snapshot.addNode(.expr_stmt, func_token, func_token, &[_]astdb.NodeId{ param_a_node_id, param_b_node_id });

    // Create return statement with binary expression
    const left_expr_id = try snapshot.addNode(.identifier, param_a_token, param_a_token, &[_]astdb.NodeId{});
    const right_expr_id = try snapshot.addNode(.identifier, param_b_token, param_b_token, &[_]astdb.NodeId{});
    const binary_expr_id = try snapshot.addNode(.binary_op, param_a_token, param_b_token, &[_]astdb.NodeId{ left_expr_id, right_expr_id });

    const return_stmt_id = try snapshot.addNode(.return_stmt, func_token, func_token, &[_]astdb.NodeId{binary_expr_id});
    const block_id = try snapshot.addNode(.block_stmt, func_token, func_token, &[_]astdb.NodeId{return_stmt_id});

    // Create function node
    const function_node_id = try snapshot.addNode(.func_decl, func_token, func_token, &[_]astdb.NodeId{ param_list_id, block_id });

    // Create function declaration
    const function_decl_id = try snapshot.addDecl(function_node_id, function_name_id, global_scope, .function);

    // Create semantic analyzer and IR generator
    var semantic_analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    var ir_generator = try IRGenerator.init(allocator, snapshot, &str_interner, &semantic_analyzer);
    defer ir_generator.deinit();

    var ir_queries = IRQueries.init(&ir_generator);

    // Generate IR
    var function_ir = try ir_queries.irOf(function_decl_id);
    defer function_ir.deinit(allocator);

    // Validate generated IR
    try testing.expect(function_ir.basic_blocks.len > 0);
    try testing.expectEqualStrings("add", function_ir.function_name);
    try testing.expect(function_ir.parameters.len == 2);

    // Validate parameters
    try testing.expectEqualStrings("a", function_ir.parameters[0].name);
    try testing.expectEqualStrings("b", function_ir.parameters[1].name);
    try testing.expect(function_ir.parameters[0].param_index == 0);
    try testing.expect(function_ir.parameters[1].param_index == 1);

    // Validate basic block has instructions
    try testing.expect(function_ir.basic_blocks[0].instructions.len > 0);

    // Validate IR structure
    try testing.expect(try ir_queries.validateIR(&function_ir));

    std.debug.print("✅ Q.IROf function with parameters test passed\n", .{});
}

test "Complete pipeline - Source to IR integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create interner and snapshot
    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    // Create global scope
    const global_scope = try snapshot.addScope(astdb.ids.INVALID_SCOPE_ID);

    // Create multiple functions to test complete pipeline
    const functions = [_][]const u8{ "main", "helper", "compute" };
    var function_decl_ids: [3]astdb.DeclId = undefined;

    for (functions, 0..) |func_name, i| {
        const function_name_id = try str_interner.get(func_name);

        // Create token
        const func_token = try snapshot.addToken(.kw_func, function_name_id, astdb.Span{
            .start_byte = @as(u32, @intCast(i * 10)),
            .end_byte = @as(u32, @intCast(i * 10 + func_name.len)),
            .start_line = @as(u32, @intCast(i + 1)),
            .start_col = 1,
            .end_line = @as(u32, @intCast(i + 1)),
            .end_col = @as(u32, @intCast(func_name.len + 1)),
        });

        const param_list_id = try snapshot.addNode(.expr_stmt, func_token, func_token, &[_]astdb.NodeId{});
        const block_id = try snapshot.addNode(.block_stmt, func_token, func_token, &[_]astdb.NodeId{});
        const function_node_id = try snapshot.addNode(.func_decl, func_token, func_token, &[_]astdb.NodeId{ param_list_id, block_id });

        const function_decl_id = try snapshot.addDecl(function_node_id, function_name_id, global_scope, .function);

        function_decl_ids[i] = function_decl_id;
    }

    // Create semantic analyzer and IR generator
    var semantic_analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    var ir_generator = try IRGenerator.init(allocator, snapshot, &str_interner, &semantic_analyzer);
    defer ir_generator.deinit();

    var ir_queries = IRQueries.init(&ir_generator);

    // Generate IR for all functions
    for (function_decl_ids, 0..) |decl_id, i| {
        var function_ir = try ir_queries.irOf(decl_id);
        defer function_ir.deinit(allocator);

        // Validate each generated IR
        try testing.expectEqualStrings(functions[i], function_ir.function_name);
        try testing.expect(try ir_queries.validateIR(&function_ir));
        try testing.expect(function_ir.basic_blocks.len > 0);
    }

    std.debug.print("✅ Complete pipeline integration test passed\n", .{});
}
