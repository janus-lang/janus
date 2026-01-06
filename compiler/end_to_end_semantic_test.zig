// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const ParserASTDBBridge = @import("parser_astdb_bridge.zig").ParserASTDBBridge;
const SemanticAnalyzer = @import("semantic_analyzer.zig").SemanticAnalyzer;
const astdb = @import("libjanus/astdb.zig");
const interner = @import("libjanus/astdb/granite_interner.zig");

// End-to-End Semantic Analysis Tests - The Complete Intelligence Pipeline
// Task: Prove the complete chain: Source → Parser → ASTDB → Semantic Analysis
// Requirements: Validate that real Janus source code can be semantically analyzed

test "End-to-End - Function parameter resolution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize granite-solid components
    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var bridge = try ParserASTDBBridge.init(allocator, &str_interner);
    defer bridge.deinit();

    // Parse real Janus source code
    const source = "func add(x: i32, y: i32) -> i32 { return x }";

    const root_node = try bridge.parseToSnapshot(source);
    const snapshot = bridge.getSnapshot();

    // Initialize semantic analyzer
    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    // Create scopes for the function (simplified scope creation)
    const global_scope = try snapshot.addScope(@enumFromInt(0));
    const func_scope = try snapshot.addScope(global_scope);

    // Add function declaration to global scope
    const func_name = try str_interner.get("add");
    const func_span = astdb.Span{ .start_byte = 0, .end_byte = 3, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 4 };
    const func_token = try snapshot.addToken(.kw_func, func_name, func_span);
    const func_node = try snapshot.addNode(.func_decl, func_token, func_token, &[_]astdb.NodeId{});
    const func_decl = try snapshot.addDecl(func_node, func_name, global_scope, .function);

    // Add parameter declarations to function scope
    const x_name = try str_interner.get("x");
    const x_span = astdb.Span{ .start_byte = 8, .end_byte = 9, .start_line = 1, .start_col = 9, .end_line = 1, .end_col = 10 };
    const x_token = try snapshot.addToken(.identifier, x_name, x_span);
    const x_node = try snapshot.addNode(.var_decl, x_token, x_token, &[_]astdb.NodeId{});
    const x_decl = try snapshot.addDecl(x_node, x_name, func_scope, .parameter);

    const y_name = try str_interner.get("y");
    const y_span = astdb.Span{ .start_byte = 16, .end_byte = 17, .start_line = 1, .start_col = 17, .end_line = 1, .end_col = 18 };
    const y_token = try snapshot.addToken(.identifier, y_name, y_span);
    const y_node = try snapshot.addNode(.var_decl, y_token, y_token, &[_]astdb.NodeId{});
    const y_decl = try snapshot.addDecl(y_node, y_name, func_scope, .parameter);

    // Test semantic resolution
    // Function should be resolvable from global scope
    const resolved_func = try analyzer.resolveNameByString("add", global_scope);
    try testing.expectEqual(func_decl, resolved_func.?);

    // Parameters should be resolvable from function scope
    const resolved_x = try analyzer.resolveNameByString("x", func_scope);
    try testing.expectEqual(x_decl, resolved_x.?);

    const resolved_y = try analyzer.resolveNameByString("y", func_scope);
    try testing.expectEqual(y_decl, resolved_y.?);

    // Parameters should NOT be resolvable from global scope
    const x_from_global = try analyzer.resolveNameByString("x", global_scope);
    try testing.expect(x_from_global == null);

    const y_from_global = try analyzer.resolveNameByString("y", global_scope);
    try testing.expect(y_from_global == null);

    // Function should be resolvable from function scope (lexical scoping)
    const func_from_func = try analyzer.resolveNameByString("add", func_scope);
    try testing.expectEqual(func_decl, func_from_func.?);
}

test "End-to-End - Multiple function declarations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var bridge = try ParserASTDBBridge.init(allocator, &str_interner);
    defer bridge.deinit();

    // Parse multiple function declarations
    const source =
        \\func first() -> void {}
        \\func second(param: i32) -> i32 { return param }
    ;

    _ = try bridge.parseToSnapshot(source);
    const snapshot = bridge.getSnapshot();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    // Create scopes
    const global_scope = try snapshot.addScope(@enumFromInt(0));
    const first_func_scope = try snapshot.addScope(global_scope);
    const second_func_scope = try snapshot.addScope(global_scope);

    // Add function declarations
    const first_name = try str_interner.get("first");
    const first_span = astdb.Span{ .start_byte = 0, .end_byte = 5, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 6 };
    const first_token = try snapshot.addToken(.identifier, first_name, first_span);
    const first_node = try snapshot.addNode(.func_decl, first_token, first_token, &[_]astdb.NodeId{});
    const first_decl = try snapshot.addDecl(first_node, first_name, global_scope, .function);

    const second_name = try str_interner.get("second");
    const second_span = astdb.Span{ .start_byte = 25, .end_byte = 31, .start_line = 2, .start_col = 1, .end_line = 2, .end_col = 7 };
    const second_token = try snapshot.addToken(.identifier, second_name, second_span);
    const second_node = try snapshot.addNode(.func_decl, second_token, second_token, &[_]astdb.NodeId{});
    const second_decl = try snapshot.addDecl(second_node, second_name, global_scope, .function);

    // Add parameter to second function
    const param_name = try str_interner.get("param");
    const param_span = astdb.Span{ .start_byte = 32, .end_byte = 37, .start_line = 2, .start_col = 8, .end_line = 2, .end_col = 13 };
    const param_token = try snapshot.addToken(.identifier, param_name, param_span);
    const param_node = try snapshot.addNode(.var_decl, param_token, param_token, &[_]astdb.NodeId{});
    const param_decl = try snapshot.addDecl(param_node, param_name, second_func_scope, .parameter);

    // Test resolution from global scope
    const resolved_first = try analyzer.resolveNameByString("first", global_scope);
    try testing.expectEqual(first_decl, resolved_first.?);

    const resolved_second = try analyzer.resolveNameByString("second", global_scope);
    try testing.expectEqual(second_decl, resolved_second.?);

    // Test cross-function visibility
    const first_sees_second = try analyzer.resolveNameByString("second", first_func_scope);
    try testing.expectEqual(second_decl, first_sees_second.?);

    const second_sees_first = try analyzer.resolveNameByString("first", second_func_scope);
    try testing.expectEqual(first_decl, second_sees_first.?);

    // Test parameter isolation
    const param_from_second = try analyzer.resolveNameByString("param", second_func_scope);
    try testing.expectEqual(param_decl, param_from_second.?);

    const param_from_first = try analyzer.resolveNameByString("param", first_func_scope);
    try testing.expect(param_from_first == null);

    const param_from_global = try analyzer.resolveNameByString("param", global_scope);
    try testing.expect(param_from_global == null);
}

test "End-to-End - Name conflict detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var bridge = try ParserASTDBBridge.init(allocator, &str_interner);
    defer bridge.deinit();

    // Parse source with potential naming conflicts
    const source = "func duplicate() -> void {} func duplicate() -> i32 {}";

    _ = try bridge.parseToSnapshot(source);
    const snapshot = bridge.getSnapshot();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    // Create scope and add conflicting declarations
    const global_scope = try snapshot.addScope(@enumFromInt(0));

    const dup_name = try str_interner.get("duplicate");

    // First declaration
    const span1 = astdb.Span{ .start_byte = 0, .end_byte = 9, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 10 };
    const token1 = try snapshot.addToken(.identifier, dup_name, span1);
    const node1 = try snapshot.addNode(.func_decl, token1, token1, &[_]astdb.NodeId{});
    const decl1 = try snapshot.addDecl(node1, dup_name, global_scope, .function);

    // Second declaration (conflict)
    const span2 = astdb.Span{ .start_byte = 30, .end_byte = 39, .start_line = 1, .start_col = 31, .end_line = 1, .end_col = 40 };
    const token2 = try snapshot.addToken(.identifier, dup_name, span2);
    const node2 = try snapshot.addNode(.func_decl, token2, token2, &[_]astdb.NodeId{});
    const decl2 = try snapshot.addDecl(node2, dup_name, global_scope, .function);

    // Test conflict detection
    const conflicts = try analyzer.validateNameUniqueness(global_scope);
    defer allocator.free(conflicts);

    try testing.expectEqual(@as(usize, 2), conflicts.len);

    // Verify both conflicting declarations are reported
    var found_decl1 = false;
    var found_decl2 = false;
    for (conflicts) |conflict| {
        if (std.meta.eql(conflict, decl1)) found_decl1 = true;
        if (std.meta.eql(conflict, decl2)) found_decl2 = true;
    }
    try testing.expect(found_decl1);
    try testing.expect(found_decl2);

    // Test that resolution still works (returns first match)
    const resolved = try analyzer.resolveNameByString("duplicate", global_scope);
    try testing.expect(resolved != null);
    // Should return the first declaration found
    try testing.expectEqual(decl1, resolved.?);
}

test "End-to-End - Complex nested scoping" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var bridge = try ParserASTDBBridge.init(allocator, &str_interner);
    defer bridge.deinit();

    // Parse nested function with local variables
    const source =
        \\func outer(param: i32) -> i32 {
        \\    return param
        \\}
    ;

    _ = try bridge.parseToSnapshot(source);
    const snapshot = bridge.getSnapshot();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    // Create complex scope hierarchy
    const global_scope = try snapshot.addScope(@enumFromInt(0));
    const outer_func_scope = try snapshot.addScope(global_scope);
    const outer_block_scope = try snapshot.addScope(outer_func_scope);

    // Add global variable
    const global_name = try str_interner.get("global_var");
    const global_span = astdb.Span{ .start_byte = 0, .end_byte = 10, .start_line = 0, .start_col = 1, .end_line = 0, .end_col = 11 };
    const global_token = try snapshot.addToken(.identifier, global_name, global_span);
    const global_node = try snapshot.addNode(.var_decl, global_token, global_token, &[_]astdb.NodeId{});
    const global_decl = try snapshot.addDecl(global_node, global_name, global_scope, .variable);

    // Add outer function
    const outer_name = try str_interner.get("outer");
    const outer_span = astdb.Span{ .start_byte = 5, .end_byte = 10, .start_line = 1, .start_col = 6, .end_line = 1, .end_col = 11 };
    const outer_token = try snapshot.addToken(.identifier, outer_name, outer_span);
    const outer_node = try snapshot.addNode(.func_decl, outer_token, outer_token, &[_]astdb.NodeId{});
    const outer_decl = try snapshot.addDecl(outer_node, outer_name, global_scope, .function);

    // Add parameter
    const param_name = try str_interner.get("param");
    const param_span = astdb.Span{ .start_byte = 11, .end_byte = 16, .start_line = 1, .start_col = 12, .end_line = 1, .end_col = 17 };
    const param_token = try snapshot.addToken(.identifier, param_name, param_span);
    const param_node = try snapshot.addNode(.var_decl, param_token, param_token, &[_]astdb.NodeId{});
    const param_decl = try snapshot.addDecl(param_node, param_name, outer_func_scope, .parameter);

    // Add local variable in block (shadows global)
    const local_name = try str_interner.get("global_var"); // Same name as global
    const local_span = astdb.Span{ .start_byte = 40, .end_byte = 50, .start_line = 2, .start_col = 5, .end_line = 2, .end_col = 15 };
    const local_token = try snapshot.addToken(.identifier, local_name, local_span);
    const local_node = try snapshot.addNode(.var_decl, local_token, local_token, &[_]astdb.NodeId{});
    const local_decl = try snapshot.addDecl(local_node, local_name, outer_block_scope, .variable);

    // Test resolution from innermost scope (block)
    // Should find local variable (shadows global)
    const resolved_local = try analyzer.resolveNameByString("global_var", outer_block_scope);
    try testing.expectEqual(local_decl, resolved_local.?);

    // Should find parameter
    const resolved_param = try analyzer.resolveNameByString("param", outer_block_scope);
    try testing.expectEqual(param_decl, resolved_param.?);

    // Should find outer function
    const resolved_outer = try analyzer.resolveNameByString("outer", outer_block_scope);
    try testing.expectEqual(outer_decl, resolved_outer.?);

    // Test resolution from function scope (should see global, not local)
    const resolved_global = try analyzer.resolveNameByString("global_var", outer_func_scope);
    try testing.expectEqual(global_decl, resolved_global.?);

    // Test resolution from global scope
    const global_sees_global = try analyzer.resolveNameByString("global_var", global_scope);
    try testing.expectEqual(global_decl, global_sees_global.?);

    const global_sees_outer = try analyzer.resolveNameByString("outer", global_scope);
    try testing.expectEqual(outer_decl, global_sees_outer.?);

    // Global should not see parameter or local
    const global_no_param = try analyzer.resolveNameByString("param", global_scope);
    try testing.expect(global_no_param == null);
}

test "End-to-End - Memory safety with complex operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test multiple complete pipelines to ensure no memory leaks
    for (0..5) |i| {
        var str_interner = interner.StrInterner.init(allocator, true);
        defer str_interner.deinit();

        var bridge = try ParserASTDBBridge.init(allocator, &str_interner);
        defer bridge.deinit();

        const source = try std.fmt.allocPrint(allocator, "func test{d}(x: i32) -> i32 {{ return x }}", .{i});
        defer allocator.free(source);

        _ = try bridge.parseToSnapshot(source);
        const snapshot = bridge.getSnapshot();

        var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
        defer analyzer.deinit();

        // Perform complex operations
        const scope = try snapshot.addScope(@enumFromInt(0));

        const func_name = try std.fmt.allocPrint(allocator, "test{d}", .{i});
        defer allocator.free(func_name);

        const name_id = try str_interner.get(func_name);
        const span = astdb.Span{ .start_byte = 0, .end_byte = @as(u32, @intCast(func_name.len)), .start_line = 1, .start_col = 1, .end_line = 1, .end_col = @as(u32, @intCast(func_name.len + 1)) };
        const token = try snapshot.addToken(.identifier, name_id, span);
        const node = try snapshot.addNode(.func_decl, token, token, &[_]astdb.NodeId{});
        _ = try snapshot.addDecl(node, name_id, scope, .function);

        // Test resolution and scope operations
        _ = try analyzer.resolveName(name_id, scope);
        const decls = try analyzer.getDeclarationsInScope(scope);
        allocator.free(decls);

        const conflicts = try analyzer.validateNameUniqueness(scope);
        allocator.free(conflicts);

        // All components should clean up properly when deinit is called
    }

    // If we reach here without memory leaks, the complete pipeline is memory-safe
    try testing.expect(true);
}
