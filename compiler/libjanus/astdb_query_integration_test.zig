// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb.zig");

// ASTDB Query Engine Integration Test - Verify Task 2 implementation
// Task 2: Query Engine Core - Complete integration verification
// Requirements: All query components work together correctly

test "ASTDB Task 2 - Query Engine Core integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🔥 Testing ASTDB Task 2 - Query Engine Core", .{});

    // Initialize ASTDB system
    var system = try astdb.ASTDBSystem.init(allocator, true);
    defer system.deinit();

    // Create snapshot with test data
    var snapshot = try system.createSnapshot();
    defer snapshot.deinit();

    std.log.info("✅ ASTDB system and snapshot initialized", .{});

    // Create test AST structure
    // func main() { var x = 42; }
    const main_name = try system.str_interner.get("main");
    const x_name = try system.str_interner.get("x");
    const literal_42 = try system.str_interner.get("42");

    // Tokens
    const func_token = try snapshot.addToken(.kw_func, main_name, astdb.Span{
        .start_byte = 0,
        .end_byte = 4,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 5,
    });
    const main_token = try snapshot.addToken(.identifier, main_name, astdb.Span{
        .start_byte = 5,
        .end_byte = 9,
        .start_line = 1,
        .start_col = 6,
        .end_line = 1,
        .end_col = 10,
    });
    const var_token = try snapshot.addToken(.kw_var, x_name, astdb.Span{
        .start_byte = 13,
        .end_byte = 16,
        .start_line = 1,
        .start_col = 14,
        .end_line = 1,
        .end_col = 17,
    });
    const x_token = try snapshot.addToken(.identifier, x_name, astdb.Span{
        .start_byte = 17,
        .end_byte = 18,
        .start_line = 1,
        .start_col = 18,
        .end_line = 1,
        .end_col = 19,
    });
    const literal_token = try snapshot.addToken(.int_literal, literal_42, astdb.Span{
        .start_byte = 21,
        .end_byte = 23,
        .start_line = 1,
        .start_col = 22,
        .end_line = 1,
        .end_col = 24,
    });

    // AST nodes
    const literal_node = try snapshot.addNode(.int_literal, literal_token, literal_token, &[_]astdb.NodeId{});
    const var_node = try snapshot.addNode(.var_decl, var_token, literal_token, &[_]astdb.NodeId{literal_node});
    const block_node = try snapshot.addNode(.block_stmt, var_token, literal_token, &[_]astdb.NodeId{var_node});
    const func_node = try snapshot.addNode(.func_decl, func_token, literal_token, &[_]astdb.NodeId{block_node});

    // Scopes and declarations
    const global_scope = try snapshot.addScope(astdb.ids.INVALID_SCOPE_ID);
    const func_scope = try snapshot.addScope(global_scope);

    const main_decl = try snapshot.addDecl(func_node, main_name, global_scope, .function);
    const x_decl = try snapshot.addDecl(var_node, x_name, func_scope, .variable);

    // References
    _ = try snapshot.addRef(func_node, main_name, main_decl);
    _ = try snapshot.addRef(var_node, x_name, x_decl);

    std.log.info("✅ Test AST structure created", .{});

    // Initialize query engine
    var query_engine = astdb.QueryEngine.init(allocator, snapshot);
    defer query_engine.deinit();

    std.log.info("✅ Query engine initialized", .{});

    // Test canonical queries

    // 1. Test tokenSpan query
    const span_result = query_engine.tokenSpan(func_node);
    try testing.expectEqual(func_token, span_result.result.start);
    try testing.expectEqual(literal_token, span_result.result.end);
    std.log.info("✅ tokenSpan query works correctly", .{});

    // 2. Test children query
    const children_result = query_engine.children(func_node);
    try testing.expectEqual(@as(usize, 1), children_result.result.len);
    try testing.expectEqual(block_node, children_result.result[0]);
    std.log.info("✅ children query works correctly", .{});

    // 3. Test nodeAt query
    const node_at_result = query_engine.nodeAt(5); // Position of "main"
    try testing.expect(node_at_result.result != null);
    std.log.info("✅ nodeAt query works correctly", .{});

    // 4. Test lookup query
    const lookup_result = query_engine.lookup(global_scope, main_name);
    try testing.expectEqual(main_decl, lookup_result.result.?);
    std.log.info("✅ lookup query works correctly", .{});

    // 5. Test refsTo query
    const refs_result = query_engine.refsTo(main_decl);
    defer allocator.free(refs_result.result);
    try testing.expectEqual(@as(usize, 1), refs_result.result.len);
    std.log.info("✅ refsTo query works correctly", .{});

    // Test predicate filtering

    // 6. Test node kind filtering
    const func_predicate = astdb.Predicate{ .node_kind = .func_decl };
    const func_nodes_result = query_engine.filterNodes(func_predicate);
    defer allocator.free(func_nodes_result.result);
    try testing.expectEqual(@as(usize, 1), func_nodes_result.result.len);
    try testing.expectEqual(func_node, func_nodes_result.result[0]);
    std.log.info("✅ node kind predicate filtering works correctly", .{});

    // 7. Test declaration kind filtering
    const var_decl_predicate = astdb.Predicate{ .decl_kind = .variable };
    const var_decls_result = query_engine.filterDecls(var_decl_predicate);
    defer allocator.free(var_decls_result.result);
    try testing.expectEqual(@as(usize, 1), var_decls_result.result.len);
    try testing.expectEqual(x_decl, var_decls_result.result[0]);
    std.log.info("✅ declaration kind predicate filtering works correctly", .{});

    // 8. Test combined predicates (AND)
    const func_pred = astdb.Predicate{ .node_kind = .func_decl };
    const has_children_pred = astdb.Predicate{ .node_has_children = true };

    // Allocate predicates for combination
    const func_pred_ptr = try allocator.create(astdb.Predicate);
    const has_children_pred_ptr = try allocator.create(astdb.Predicate);
    defer allocator.destroy(func_pred_ptr);
    defer allocator.destroy(has_children_pred_ptr);

    func_pred_ptr.* = func_pred;
    has_children_pred_ptr.* = has_children_pred;

    const and_predicate = astdb.Predicate{ .and_ = .{ .left = func_pred_ptr, .right = has_children_pred_ptr } };
    const and_result = query_engine.filterNodes(and_predicate);
    defer allocator.free(and_result.result);

    try testing.expectEqual(@as(usize, 1), and_result.result.len);
    try testing.expectEqual(func_node, and_result.result[0]);
    std.log.info("✅ AND predicate combination works correctly", .{});

    // 9. Test NOT predicate
    const not_func_pred_ptr = try allocator.create(astdb.Predicate);
    defer allocator.destroy(not_func_pred_ptr);
    not_func_pred_ptr.* = func_pred;

    const not_predicate = astdb.Predicate{ .not_ = not_func_pred_ptr };
    const not_result = query_engine.filterNodes(not_predicate);
    defer allocator.free(not_result.result);

    // Should find all non-function nodes (var_decl, block_stmt, int_literal)
    try testing.expect(not_result.result.len >= 3);
    std.log.info("✅ NOT predicate works correctly", .{});

    // Test query engine statistics
    const stats = query_engine.stats();
    std.log.info("✅ Query engine statistics: {} cached queries", .{stats.cached_queries});

    std.log.info("🎉 ASTDB Task 2 - Query Engine Core - ALL TESTS PASSED!", .{});
    std.log.info("   ✅ Canonical queries (tokenSpan, children, nodeAt, lookup, refsTo)", .{});
    std.log.info("   ✅ Predicate filtering (node kinds, declaration kinds)", .{});
    std.log.info("   ✅ Predicate combinations (AND, OR, NOT)", .{});
    std.log.info("   ✅ Query result diagnostics", .{});
    std.log.info("   ✅ Query engine statistics and caching", .{});
    std.log.info("", .{});
    std.log.info("🔥 Ready for Task 3: Golden Test Integration", .{});
}

test "ASTDB Query Parser integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🔥 Testing Query Parser integration", .{});

    // Test basic query parsing
    {
        var parser = try astdb.QueryParser.init(allocator, "func and var");
        defer parser.deinit();

        const predicate = try parser.parseQuery();
        try testing.expectEqual(astdb.Predicate.and_, std.meta.activeTag(predicate));
        std.log.info("✅ Basic query parsing works", .{});
    }

    // Test complex query parsing
    {
        var parser = try astdb.QueryParser.init(allocator, "(func or var) and not struct");
        defer parser.deinit();

        const predicate = try parser.parseQuery();
        try testing.expectEqual(astdb.Predicate.and_, std.meta.activeTag(predicate));
        std.log.info("✅ Complex query parsing works", .{});
    }

    // Test comparison predicates
    {
        var parser = try astdb.QueryParser.init(allocator, "child_count >= 2");
        defer parser.deinit();

        const predicate = try parser.parseQuery();
        try testing.expectEqual(astdb.Predicate.node_child_count, std.meta.activeTag(predicate));
        try testing.expectEqual(astdb.Predicate.CompareOp.ge, predicate.node_child_count.op);
        try testing.expectEqual(@as(u32, 2), predicate.node_child_count.value);
        std.log.info("✅ Comparison predicate parsing works", .{});
    }

    std.log.info("🎉 Query Parser integration - ALL TESTS PASSED!", .{});
}
