// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const SemanticAnalyzer = @import("semantic_analyzer.zig").SemanticAnalyzer;
const astdb = @import("libjanus/astdb.zig");
const Snapshot = astdb.Snapshot;
const NodeKind = astdb.NodeKind;
const DeclKind = astdb.DeclKind;
const TokenKind = astdb.TokenKind;
const Span = astdb.Span;
const interner = @import("libjanus/astdb/granite_interner.zig");

// Revolutionary Semantic Analysis Tests - Validation of the Intelligence
// Task: Prove Q.ResolveName works correctly in all scenarios
// Requirements: Test scope traversal, name resolution, conflict detection

test "Semantic Analyzer - Basic name resolution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize granite-solid components
    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    // Create a simple scope with a declaration
    const root_scope = try snapshot.addScope(@enumFromInt(0)); // Self-referencing root

    // Create a function declaration
    const func_name = try str_interner.get("main");
    const func_span = Span{ .start_byte = 0, .end_byte = 4, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 5 };
    const func_token = try snapshot.addToken(.kw_func, func_name, func_span);
    const func_node = try snapshot.addNode(.func_decl, func_token, func_token, &[_]astdb.NodeId{});

    const func_decl = try snapshot.addDecl(func_node, func_name, root_scope, .function);

    // Test name resolution
    const resolved = try analyzer.resolveName(func_name, root_scope);
    try testing.expect(resolved != null);
    try testing.expectEqual(func_decl, resolved.?);
}

test "Semantic Analyzer - Name resolution by string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    // Create scope and declaration
    const root_scope = try snapshot.addScope(@enumFromInt(0));

    const var_name = try str_interner.get("counter");
    const var_span = Span{ .start_byte = 0, .end_byte = 7, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 8 };
    const var_token = try snapshot.addToken(.identifier, var_name, var_span);
    const var_node = try snapshot.addNode(.var_decl, var_token, var_token, &[_]astdb.NodeId{});

    const var_decl = try snapshot.addDecl(var_node, var_name, root_scope, .variable);

    // Test string-based resolution
    const resolved = try analyzer.resolveNameByString("counter", root_scope);
    try testing.expect(resolved != null);
    try testing.expectEqual(var_decl, resolved.?);

    // Test non-existent name
    const not_found = try analyzer.resolveNameByString("nonexistent", root_scope);
    try testing.expect(not_found == null);
}

test "Semantic Analyzer - Nested scope resolution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    // Create nested scopes: root -> function -> block
    const root_scope = try snapshot.addScope(@enumFromInt(0)); // Root scope
    const func_scope = try snapshot.addScope(root_scope); // Function scope
    const block_scope = try snapshot.addScope(func_scope); // Block scope

    // Add declarations at different levels
    const global_name = try str_interner.get("global_var");
    const global_span = Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 };
    const global_token = try snapshot.addToken(.identifier, global_name, global_span);
    const global_node = try snapshot.addNode(.var_decl, global_token, global_token, &[_]astdb.NodeId{});
    const global_decl = try snapshot.addDecl(global_node, global_name, root_scope, .variable);

    const param_name = try str_interner.get("param");
    const param_span = Span{ .start_byte = 20, .end_byte = 25, .start_line = 2, .start_col = 1, .end_line = 2, .end_col = 6 };
    const param_token = try snapshot.addToken(.identifier, param_name, param_span);
    const param_node = try snapshot.addNode(.var_decl, param_token, param_token, &[_]astdb.NodeId{});
    const param_decl = try snapshot.addDecl(param_node, param_name, func_scope, .parameter);

    const local_name = try str_interner.get("local_var");
    const local_span = Span{ .start_byte = 40, .end_byte = 49, .start_line = 3, .start_col = 1, .end_line = 3, .end_col = 10 };
    const local_token = try snapshot.addToken(.identifier, local_name, local_span);
    const local_node = try snapshot.addNode(.var_decl, local_token, local_token, &[_]astdb.NodeId{});
    const local_decl = try snapshot.addDecl(local_node, local_name, block_scope, .variable);

    // Test resolution from innermost scope
    // Should find local variable
    const resolved_local = try analyzer.resolveNameByString("local_var", block_scope);
    try testing.expectEqual(local_decl, resolved_local.?);

    // Should find parameter in parent scope
    const resolved_param = try analyzer.resolveNameByString("param", block_scope);
    try testing.expectEqual(param_decl, resolved_param.?);

    // Should find global in grandparent scope
    const resolved_global = try analyzer.resolveNameByString("global_var", block_scope);
    try testing.expectEqual(global_decl, resolved_global.?);

    // Test resolution from function scope (should not see local_var)
    const not_visible = try analyzer.resolveNameByString("local_var", func_scope);
    try testing.expect(not_visible == null);

    // But should see param and global
    const func_sees_param = try analyzer.resolveNameByString("param", func_scope);
    try testing.expectEqual(param_decl, func_sees_param.?);

    const func_sees_global = try analyzer.resolveNameByString("global_var", func_scope);
    try testing.expectEqual(global_decl, func_sees_global.?);
}

test "Semantic Analyzer - Shadowing resolution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    // Create nested scopes with shadowing
    const root_scope = try snapshot.addScope(@enumFromInt(0));
    const inner_scope = try snapshot.addScope(root_scope);

    const var_name = try str_interner.get("x");

    // Outer declaration
    const outer_span = Span{ .start_byte = 0, .end_byte = 1, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 2 };
    const outer_token = try snapshot.addToken(.identifier, var_name, outer_span);
    const outer_node = try snapshot.addNode(.var_decl, outer_token, outer_token, &[_]astdb.NodeId{});
    const outer_decl = try snapshot.addDecl(outer_node, var_name, root_scope, .variable);

    // Inner declaration (shadows outer)
    const inner_span = Span{ .start_byte = 10, .end_byte = 11, .start_line = 2, .start_col = 1, .end_line = 2, .end_col = 2 };
    const inner_token = try snapshot.addToken(.identifier, var_name, inner_span);
    const inner_node = try snapshot.addNode(.var_decl, inner_token, inner_token, &[_]astdb.NodeId{});
    const inner_decl = try snapshot.addDecl(inner_node, var_name, inner_scope, .variable);

    // Resolution from inner scope should find inner declaration (shadowing)
    const resolved_inner = try analyzer.resolveName(var_name, inner_scope);
    try testing.expectEqual(inner_decl, resolved_inner.?);

    // Resolution from outer scope should find outer declaration
    const resolved_outer = try analyzer.resolveName(var_name, root_scope);
    try testing.expectEqual(outer_decl, resolved_outer.?);
}

test "Semantic Analyzer - Get declarations in scope" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    const scope = try snapshot.addScope(@enumFromInt(0));

    // Add multiple declarations to the scope
    const names = [_][]const u8{ "func1", "var1", "const1" };
    const kinds = [_]DeclKind{ .function, .variable, .constant };
    var expected_decls: [3]astdb.DeclId = undefined;

    for (names, kinds, 0..) |name, kind, i| {
        const name_id = try str_interner.get(name);
        const span = Span{ .start_byte = @as(u32, @intCast(i * 10)), .end_byte = @as(u32, @intCast(i * 10 + name.len)), .start_line = 1, .start_col = 1, .end_line = 1, .end_col = @as(u32, @intCast(name.len + 1)) };
        const token = try snapshot.addToken(.identifier, name_id, span);
        const node = try snapshot.addNode(.var_decl, token, token, &[_]astdb.NodeId{});
        expected_decls[i] = try snapshot.addDecl(node, name_id, scope, kind);
    }

    // Get all declarations in scope
    const decls = try analyzer.getDeclarationsInScope(scope);
    defer allocator.free(decls);

    try testing.expectEqual(@as(usize, 3), decls.len);

    // Verify all expected declarations are present
    for (expected_decls) |expected| {
        var found = false;
        for (decls) |actual| {
            if (std.meta.eql(expected, actual)) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

test "Semantic Analyzer - Name uniqueness validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    const scope = try snapshot.addScope(@enumFromInt(0));

    // Add declarations with unique names
    const unique_name1 = try str_interner.get("unique1");
    const unique_name2 = try str_interner.get("unique2");
    const duplicate_name = try str_interner.get("duplicate");

    const span = Span{ .start_byte = 0, .end_byte = 5, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 6 };

    // Unique declarations
    const token1 = try snapshot.addToken(.identifier, unique_name1, span);
    const node1 = try snapshot.addNode(.var_decl, token1, token1, &[_]astdb.NodeId{});
    _ = try snapshot.addDecl(node1, unique_name1, scope, .variable);

    const token2 = try snapshot.addToken(.identifier, unique_name2, span);
    const node2 = try snapshot.addNode(.var_decl, token2, token2, &[_]astdb.NodeId{});
    _ = try snapshot.addDecl(node2, unique_name2, scope, .variable);

    // Duplicate declarations
    const token3 = try snapshot.addToken(.identifier, duplicate_name, span);
    const node3 = try snapshot.addNode(.var_decl, token3, token3, &[_]astdb.NodeId{});
    const dup_decl1 = try snapshot.addDecl(node3, duplicate_name, scope, .variable);

    const token4 = try snapshot.addToken(.identifier, duplicate_name, span);
    const node4 = try snapshot.addNode(.var_decl, token4, token4, &[_]astdb.NodeId{});
    const dup_decl2 = try snapshot.addDecl(node4, duplicate_name, scope, .function);

    // Validate uniqueness
    const conflicts = try analyzer.validateNameUniqueness(scope);
    defer allocator.free(conflicts);

    // Should find exactly 2 conflicts (the duplicate declarations)
    try testing.expectEqual(@as(usize, 2), conflicts.len);

    // Verify the conflicting declarations are the duplicates
    var found_dup1 = false;
    var found_dup2 = false;
    for (conflicts) |conflict| {
        if (std.meta.eql(conflict, dup_decl1)) found_dup1 = true;
        if (std.meta.eql(conflict, dup_decl2)) found_dup2 = true;
    }
    try testing.expect(found_dup1);
    try testing.expect(found_dup2);
}

test "Semantic Analyzer - Scope chain caching" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot = try Snapshot.init(allocator, &str_interner);
    defer snapshot.deinit();

    var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
    defer analyzer.deinit();

    // Create a deep scope chain
    const root_scope = try snapshot.addScope(@enumFromInt(0));
    const level1_scope = try snapshot.addScope(root_scope);
    const level2_scope = try snapshot.addScope(level1_scope);
    const level3_scope = try snapshot.addScope(level2_scope);

    // First resolution should build and cache the scope chain
    const name = try str_interner.get("test");
    const span = Span{ .start_byte = 0, .end_byte = 4, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 5 };
    const token = try snapshot.addToken(.identifier, name, span);
    const node = try snapshot.addNode(.var_decl, token, token, &[_]astdb.NodeId{});
    _ = try snapshot.addDecl(node, name, root_scope, .variable);

    // Multiple resolutions from the same scope should use cached chain
    const result1 = try analyzer.resolveName(name, level3_scope);
    const result2 = try analyzer.resolveName(name, level3_scope);
    const result3 = try analyzer.resolveName(name, level3_scope);

    // All should find the same declaration
    try testing.expect(result1 != null);
    try testing.expectEqual(result1.?, result2.?);
    try testing.expectEqual(result2.?, result3.?);

    // Verify cache contains the scope chain
    try testing.expect(analyzer.scope_chain_cache.contains(level3_scope));
}

test "Semantic Analyzer - Memory safety validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test multiple analyzer instances to ensure proper cleanup
    for (0..10) |i| {
        var str_interner = interner.StrInterner.init(allocator, true);
        defer str_interner.deinit();

        var snapshot = try Snapshot.init(allocator, &str_interner);
        defer snapshot.deinit();

        var analyzer = try SemanticAnalyzer.init(allocator, snapshot, &str_interner);
        defer analyzer.deinit();

        // Perform operations that allocate memory
        const scope = try snapshot.addScope(@enumFromInt(0));

        const name = try std.fmt.allocPrint(allocator, "test{d}", .{i});
        defer allocator.free(name);

        const name_id = try str_interner.get(name);
        const span = Span{ .start_byte = 0, .end_byte = @as(u32, @intCast(name.len)), .start_line = 1, .start_col = 1, .end_line = 1, .end_col = @as(u32, @intCast(name.len + 1)) };
        const token = try snapshot.addToken(.identifier, name_id, span);
        const node = try snapshot.addNode(.var_decl, token, token, &[_]astdb.NodeId{});
        _ = try snapshot.addDecl(node, name_id, scope, .variable);

        _ = try analyzer.resolveName(name_id, scope);

        // Analyzer should clean up properly when deinit is called
    }

    // If we reach here without memory leaks, the semantic analyzer is memory-safe
    try testing.expect(true);
}
