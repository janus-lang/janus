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

    // Create a simple function: fn test() { return; }
    const function_name_id = try str_interner.get("test");

    // Create function node
    const function_node_id = try snapshot.addNode(.{
        .kind = .func_decl,
        .str_id = function_name_id,
        .children = &[_]astdb.NodeId{},
    });

    // Create parameter list (empty) - using expr_stmt as placeholder for parameter list
    const param_list_id = try snapshot.addNode(.{
        .kind = .expr_stmt, // Using available node type as placeholder
        .str_id = null,
        .children = &[_]astdb.NodeId{},
    });

    // Create function body block
    const return_stmt_id = try snapshot.addNode(.{
        .kind = .return_stmt,
        .str_id = null,
        .children = &[_]astdb.NodeId{},
    });

    const block_id = try snapshot.addNode(.{
        .kind = .block_stmt,
        .str_id = null,
        .children = &[_]astdb.NodeId{return_stmt_id},
    });

    // Update function node with children
    try snapshot.updateNodeChildren(function_node_id, &[_]astdb.NodeId{ param_list_id, block_id });

    // Create function declaration
    const function_decl_id = try snapshot.addDecl(.{
        .kind = .function,
        .name_id = function_name_id,
        .node_id = function_node_id,
        .scope_id = astdb.ScopeId.global,
    });

    // Create semantic analyzer and IR generator
    var semantic_analyzer = try SemanticAnalyzer.init(allocator, &snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    var ir_generator = try IRGenerator.init(allocator, &snapshot, &str_interner, &semantic_analyzer);
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

    // Create function: fn add(a: i32, b: i32) { return a + b; }
    const function_name_id = try str_interner.get("add");
    const param_a_id = try str_interner.get("a");
    const param_b_id = try str_interner.get("b");

    // Create parameter nodes
    const param_a_name_id = try snapshot.addNode(.{
        .kind = .identifier,
        .str_id = param_a_id,
        .children = &[_]astdb.NodeId{},
    });

    const param_a_node_id = try snapshot.addNode(.{
        .kind = .var_decl, // Using var_decl as parameter placeholder
        .str_id = null,
        .children = &[_]astdb.NodeId{param_a_name_id},
    });

    const param_b_name_id = try snapshot.addNode(.{
        .kind = .identifier,
        .str_id = param_b_id,
        .children = &[_]astdb.NodeId{},
    });

    const param_b_node_id = try snapshot.addNode(.{
        .kind = .var_decl, // Using var_decl as parameter placeholder
        .str_id = null,
        .children = &[_]astdb.NodeId{param_b_name_id},
    });

    // Create parameter list
    const param_list_id = try snapshot.addNode(.{
        .kind = .expr_stmt, // Using expr_stmt as parameter list placeholder
        .str_id = null,
        .children = &[_]astdb.NodeId{ param_a_node_id, param_b_node_id },
    });

    // Create return statement with binary expression
    const left_expr_id = try snapshot.addNode(.{
        .kind = .identifier,
        .str_id = param_a_id,
        .children = &[_]astdb.NodeId{},
    });

    const right_expr_id = try snapshot.addNode(.{
        .kind = .identifier,
        .str_id = param_b_id,
        .children = &[_]astdb.NodeId{},
    });

    const binary_expr_id = try snapshot.addNode(.{
        .kind = .binary_op,
        .str_id = null,
        .children = &[_]astdb.NodeId{ left_expr_id, right_expr_id },
    });

    const return_stmt_id = try snapshot.addNode(.{
        .kind = .return_stmt,
        .str_id = null,
        .children = &[_]astdb.NodeId{binary_expr_id},
    });

    const block_id = try snapshot.addNode(.{
        .kind = .block_stmt,
        .str_id = null,
        .children = &[_]astdb.NodeId{return_stmt_id},
    });

    // Create function node
    const function_node_id = try snapshot.addNode(.{
        .kind = .func_decl,
        .str_id = function_name_id,
        .children = &[_]astdb.NodeId{ param_list_id, block_id },
    });

    // Create function declaration
    const function_decl_id = try snapshot.addDecl(.{
        .kind = .function,
        .name_id = function_name_id,
        .node_id = function_node_id,
        .scope_id = astdb.ScopeId.global,
    });

    // Create semantic analyzer and IR generator
    var semantic_analyzer = try SemanticAnalyzer.init(allocator, &snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    var ir_generator = try IRGenerator.init(allocator, &snapshot, &str_interner, &semantic_analyzer);
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

test "Q.IROfByName - IR generation by function name" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create interner and snapshot
    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    // Create a simple function
    const function_name_id = try str_interner.get("myFunction");

    const function_node_id = try snapshot.addNode(.{
        .kind = .func_decl,
        .str_id = function_name_id,
        .children = &[_]astdb.NodeId{},
    });

    const param_list_id = try snapshot.addNode(.{
        .kind = .expr_stmt, // Using expr_stmt as parameter list placeholder
        .str_id = null,
        .children = &[_]astdb.NodeId{},
    });

    const block_id = try snapshot.addNode(.{
        .kind = .block_stmt,
        .str_id = null,
        .children = &[_]astdb.NodeId{},
    });

    try snapshot.updateNodeChildren(function_node_id, &[_]astdb.NodeId{ param_list_id, block_id });

    const function_decl_id = try snapshot.addDecl(.{
        .kind = .function,
        .name_id = function_name_id,
        .node_id = function_node_id,
        .scope_id = astdb.ScopeId.global,
    });

    // Add declaration to global scope
    try snapshot.addDeclToScope(astdb.ScopeId.global, function_decl_id);

    // Create semantic analyzer and IR generator
    var semantic_analyzer = try SemanticAnalyzer.init(allocator, &snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    var ir_generator = try IRGenerator.init(allocator, &snapshot, &str_interner, &semantic_analyzer);
    defer ir_generator.deinit();

    var ir_queries = IRQueries.init(&ir_generator);

    // Generate IR by name
    var maybe_ir = try ir_queries.irOfByName("myFunction", astdb.ScopeId.global);

    if (maybe_ir) |*function_ir| {
        defer function_ir.deinit(allocator);

        // Validate generated IR
        try testing.expectEqualStrings("myFunction", function_ir.function_name);
        try testing.expect(try ir_queries.validateIR(function_ir));

        std.debug.print("✅ Q.IROfByName test passed\n", .{});
    } else {
        try testing.expect(false); // Should have found the function
    }
}

test "IR instruction generation - Integer literals and binary operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create interner and snapshot
    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    // Create function: fn compute() { return 10 + 20; }
    const function_name_id = try str_interner.get("compute");
    const literal_10_id = try str_interner.get("10");
    const literal_20_id = try str_interner.get("20");

    // Create integer literals
    const left_literal_id = try snapshot.addNode(.{
        .kind = .int_literal,
        .str_id = literal_10_id,
        .children = &[_]astdb.NodeId{},
    });

    const right_literal_id = try snapshot.addNode(.{
        .kind = .int_literal,
        .str_id = literal_20_id,
        .children = &[_]astdb.NodeId{},
    });

    // Create binary expression
    const binary_expr_id = try snapshot.addNode(.{
        .kind = .binary_op,
        .str_id = null,
        .children = &[_]astdb.NodeId{ left_literal_id, right_literal_id },
    });

    // Create return statement
    const return_stmt_id = try snapshot.addNode(.{
        .kind = .return_stmt,
        .str_id = null,
        .children = &[_]astdb.NodeId{binary_expr_id},
    });

    const block_id = try snapshot.addNode(.{
        .kind = .block_stmt,
        .str_id = null,
        .children = &[_]astdb.NodeId{return_stmt_id},
    });

    const param_list_id = try snapshot.addNode(.{
        .kind = .expr_stmt, // Using expr_stmt as parameter list placeholder
        .str_id = null,
        .children = &[_]astdb.NodeId{},
    });

    const function_node_id = try snapshot.addNode(.{
        .kind = .func_decl,
        .str_id = function_name_id,
        .children = &[_]astdb.NodeId{ param_list_id, block_id },
    });

    const function_decl_id = try snapshot.addDecl(.{
        .kind = .function,
        .name_id = function_name_id,
        .node_id = function_node_id,
        .scope_id = astdb.ScopeId.global,
    });

    // Create semantic analyzer and IR generator
    var semantic_analyzer = try SemanticAnalyzer.init(allocator, &snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    var ir_generator = try IRGenerator.init(allocator, &snapshot, &str_interner, &semantic_analyzer);
    defer ir_generator.deinit();

    var ir_queries = IRQueries.init(&ir_generator);

    // Generate IR
    var function_ir = try ir_queries.irOf(function_decl_id);
    defer function_ir.deinit(allocator);

    // Validate generated IR has instructions
    try testing.expect(function_ir.basic_blocks.len > 0);
    const entry_block = function_ir.basic_blocks[0];
    try testing.expect(entry_block.instructions.len > 0);

    // Look for load_constant and binary_op instructions
    var found_load_constant = false;
    var found_binary_op = false;
    var found_store = false;

    for (entry_block.instructions) |instruction| {
        switch (instruction) {
            .load_constant => |load| {
                found_load_constant = true;
                try testing.expect(load.dest_reg < 10); // Reasonable register number
                switch (load.value) {
                    .integer => |val| {
                        try testing.expect(val == 10 or val == 20);
                    },
                    else => {},
                }
            },
            .binary_op => |binop| {
                found_binary_op = true;
                try testing.expect(binop.op == .add);
                try testing.expect(binop.dest_reg < 10);
            },
            .store => |store| {
                found_store = true;
                switch (store.dest_location) {
                    .return_slot => {},
                    else => {},
                }
            },
            else => {},
        }
    }

    try testing.expect(found_load_constant);
    try testing.expect(found_binary_op);
    try testing.expect(found_store);

    std.debug.print("✅ IR instruction generation test passed\n", .{});
}

test "IR validation - Invalid IR detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create interner and snapshot
    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    var semantic_analyzer = try SemanticAnalyzer.init(allocator, &snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    var ir_generator = try IRGenerator.init(allocator, &snapshot, &str_interner, &semantic_analyzer);
    defer ir_generator.deinit();

    var ir_queries = IRQueries.init(&ir_generator);

    // Test invalid IR - no basic blocks
    const invalid_ir_1 = JanusIR{
        .function_id = astdb.DeclId.invalid,
        .function_name = "test",
        .parameters = &[_]JanusIR.Parameter{},
        .return_type = JanusIR.TypeRef{
            .name = "void",
            .size_bytes = 0,
            .alignment = 1,
            .is_primitive = true,
        },
        .basic_blocks = &[_]JanusIR.BasicBlock{},
        .source_location = .{
            .file = "test.jan",
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 1,
        },
    };

    try testing.expect(!(try ir_queries.validateIR(&invalid_ir_1)));

    // Test invalid IR - empty function name
    const invalid_ir_2 = JanusIR{
        .function_id = astdb.DeclId.invalid,
        .function_name = "",
        .parameters = &[_]JanusIR.Parameter{},
        .return_type = JanusIR.TypeRef{
            .name = "void",
            .size_bytes = 0,
            .alignment = 1,
            .is_primitive = true,
        },
        .basic_blocks = &[_]JanusIR.BasicBlock{
            JanusIR.BasicBlock{
                .id = 0,
                .label = "entry",
                .instructions = &[_]JanusIR.Instruction{},
                .terminator = null,
            },
        },
        .source_location = .{
            .file = "test.jan",
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 1,
        },
    };

    try testing.expect(!(try ir_queries.validateIR(&invalid_ir_2)));

    std.debug.print("✅ IR validation test passed\n", .{});
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

    // Create multiple functions to test complete pipeline
    const functions = [_][]const u8{ "main", "helper", "compute" };
    var function_decl_ids: [3]astdb.DeclId = undefined;

    for (functions, 0..) |func_name, i| {
        const function_name_id = try str_interner.get(func_name);

        const param_list_id = try snapshot.addNode(.{
            .kind = .expr_stmt, // Using expr_stmt as parameter list placeholder
            .str_id = null,
            .children = &[_]astdb.NodeId{},
        });

        const block_id = try snapshot.addNode(.{
            .kind = .block_stmt,
            .str_id = null,
            .children = &[_]astdb.NodeId{},
        });

        const function_node_id = try snapshot.addNode(.{
            .kind = .func_decl,
            .str_id = function_name_id,
            .children = &[_]astdb.NodeId{ param_list_id, block_id },
        });

        const function_decl_id = try snapshot.addDecl(.{
            .kind = .function,
            .name_id = function_name_id,
            .node_id = function_node_id,
            .scope_id = astdb.ScopeId.global,
        });

        function_decl_ids[i] = function_decl_id;
        try snapshot.addDeclToScope(astdb.ScopeId.global, function_decl_id);
    }

    // Create semantic analyzer and IR generator
    var semantic_analyzer = try SemanticAnalyzer.init(allocator, &snapshot, &str_interner);
    defer semantic_analyzer.deinit();

    var ir_generator = try IRGenerator.init(allocator, &snapshot, &str_interner, &semantic_analyzer);
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

    // Test IR generation by name for all functions
    for (functions) |func_name| {
        var maybe_ir = try ir_queries.irOfByName(func_name, astdb.ScopeId.global);

        if (maybe_ir) |*function_ir| {
            defer function_ir.deinit(allocator);
            try testing.expectEqualStrings(func_name, function_ir.function_name);
            try testing.expect(try ir_queries.validateIR(function_ir));
        } else {
            try testing.expect(false); // Should have found the function
        }
    }

    std.debug.print("✅ Complete pipeline integration test passed\n", .{});
}
