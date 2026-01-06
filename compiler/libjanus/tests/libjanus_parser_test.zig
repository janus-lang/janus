// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const parser = @import("../parser.zig");
const tokenizer = @import("../tokenizer.zig");
const NodeKind = parser.NodeKind;
const TokenType = tokenizer.TokenType;

test "parse array literal into ASTDB" {
    const allocator = std.testing.allocator;
    const source = "let a = [1, \"hello\"]";

    // 1. Create ASTDB system
    var astdb_system = try parser.AstDB.init(allocator, true);
    defer astdb_system.deinit();

    // 2. Tokenize source into the unit
    _ = try parser.tokenizeIntoSnapshot(&astdb_system, source);

    // 3. Parse tokens into nodes
    try parser.parseTokensIntoNodes(&astdb_system);

    // 4. Get snapshot
    const snapshot = try astdb_system.createSnapshot();

    // 5. Verify the AST
    // Find the source_file node (should be the root)
    const root_node = snapshot.getNode(snapshot.nodeCount() - 1) orelse return error.TestNoRootNode;
    try std.testing.expectEqual(NodeKind.source_file, root_node.kind);

    // Find the let_stmt node
    try std.testing.expectEqual(@as(u32, 1), root_node.child_hi - root_node.child_lo);
    const let_stmt_idx = root_node.child_lo;
    const let_stmt_node = snapshot.getNode(let_stmt_idx) orelse return error.TestNoLetStmt;
    try std.testing.expectEqual(NodeKind.let_stmt, let_stmt_node.kind);

    // The children of let_stmt are identifier and array_lit
    try std.testing.expectEqual(@as(u32, 2), let_stmt_node.child_hi - let_stmt_node.child_lo);
    const array_lit_idx = let_stmt_node.child_lo + 1;
    const array_lit_node = snapshot.getNode(array_lit_idx) orelse return error.TestNoArrayLit;
    try std.testing.expectEqual(NodeKind.array_lit, array_lit_node.kind);

    // The children of array_lit are the elements
    try std.testing.expectEqual(@as(u32, 2), array_lit_node.child_hi - array_lit_node.child_lo);
    const int_lit_idx = array_lit_node.child_lo;
    const str_lit_idx = array_lit_node.child_lo + 1;

    const int_lit_node = snapshot.getNode(int_lit_idx) orelse return error.TestNoIntLit;
    try std.testing.expectEqual(NodeKind.integer_literal, int_lit_node.kind);

    const str_lit_node = snapshot.getNode(str_lit_idx) orelse return error.TestNoStrLit;
    try std.testing.expectEqual(NodeKind.string_literal, str_lit_node.kind);
}

test "parse integer literal" {
    const source = "func main() { 123 }";
    var tokens_list = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens_list);

    var root = try parser.parse(tokens_list, std.testing.allocator);
    defer root.deinit(std.testing.allocator);
    defer std.testing.allocator.destroy(root);

    try std.testing.expectEqual(root.kind, NodeKind.Root);
    const func_decl = root.right.?;
    try std.testing.expectEqual(func_decl.kind, NodeKind.FunctionDecl);
    const int_literal = func_decl.right.?;
    try std.testing.expectEqual(int_literal.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqualStrings(int_literal.text, "123");
}

test "parse simple addition" {
    const source = "func main() { 1 + 2 }";
    var tokens_list = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens_list);

    var root = try parser.parse(tokens_list, std.testing.allocator);
    defer std.testing.allocator.destroy(root);

    try std.testing.expectEqual(root.kind, NodeKind.Root);
    const func_decl = root.right.?;
    try std.testing.expectEqual(func_decl.kind, NodeKind.FunctionDecl);
    const binary_expr = func_decl.right.?;
    try std.testing.expectEqual(binary_expr.kind, NodeKind.BinaryExpr);
    try std.testing.expectEqualStrings(binary_expr.text, "+");
    try std.testing.expectEqual(binary_expr.left.?.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqualStrings(binary_expr.left.?.text, "1");
    try std.testing.expectEqual(binary_expr.right.?.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqualStrings(binary_expr.right.?.text, "2");
}

test "parse multiplication precedence" {
    const source = "func main() { 1 + 2 * 3 }";
    var tokens_list = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens_list);

    var root = try parser.parse(tokens_list, std.testing.allocator);
    defer std.testing.allocator.destroy(root);

    try std.testing.expectEqual(root.kind, NodeKind.Root);
    const func_decl = root.right.?;
    try std.testing.expectEqual(func_decl.kind, NodeKind.FunctionDecl);
    const add_expr = func_decl.right.?;
    try std.testing.expectEqual(add_expr.kind, NodeKind.BinaryExpr);
    try std.testing.expectEqualStrings(add_expr.text, "+");
    try std.testing.expectEqual(add_expr.left.?.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqualStrings(add_expr.left.?.text, "1");

    const mul_expr = add_expr.right.?;
    try std.testing.expectEqual(mul_expr.kind, NodeKind.BinaryExpr);
    try std.testing.expectEqualStrings(mul_expr.text, "*");
    try std.testing.expectEqual(mul_expr.left.?.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqualStrings(mul_expr.left.?.text, "2");
    try std.testing.expectEqual(mul_expr.right.?.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqualStrings(mul_expr.right.?.text, "3");
}

test "parse hello world function" {
    const source = "func main() { print(\"Hello, Janus!\") }";
    var tokens_list = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens_list);

    var root = try parser.parse(tokens_list, std.testing.allocator);
    defer std.testing.allocator.destroy(root);

    try std.testing.expectEqual(root.kind, NodeKind.Root);

    const func_decl = root.right.?;
    try std.testing.expectEqual(func_decl.kind, NodeKind.FunctionDecl);
    try std.testing.expectEqualStrings(func_decl.text, "main");

    const func_name_node = func_decl.left.?;
    try std.testing.expectEqual(func_name_node.kind, NodeKind.Identifier);
    try std.testing.expectEqualStrings(func_name_node.text, "main");

    const call_expr = func_decl.right.?;
    try std.testing.expectEqual(call_expr.kind, NodeKind.CallExpr);
    try std.testing.expectEqualStrings(call_expr.text, "print");

    const call_identifier = call_expr.left.?;
    try std.testing.expectEqual(call_identifier.kind, NodeKind.Identifier);
    try std.testing.expectEqualStrings(call_identifier.text, "print");

    const string_literal = call_expr.right.?;
    try std.testing.expectEqual(string_literal.kind, NodeKind.StringLiteral);
    try std.testing.expectEqualStrings(string_literal.text, "\"Hello, Janus!\"");
}

test "parse parentheses" {
    const source = "func main() { (1 + 2) * 3 }";
    var tokens_list = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens_list);

    var root = try parser.parse(tokens_list, std.testing.allocator);
    defer std.testing.allocator.destroy(root);

    try std.testing.expectEqual(root.kind, NodeKind.Root);
    const func_decl = root.right.?;
    try std.testing.expectEqual(func_decl.kind, NodeKind.FunctionDecl);
    const mul_expr = func_decl.right.?;
    try std.testing.expectEqual(mul_expr.kind, NodeKind.BinaryExpr);
    try std.testing.expectEqualStrings(mul_expr.text, "*");

    const add_expr = mul_expr.left.?;
    try std.testing.expectEqual(add_expr.kind, NodeKind.BinaryExpr);
    try std.testing.expectEqualStrings(add_expr.text, "+");
    try std.testing.expectEqual(add_expr.left.?.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqualStrings(add_expr.left.?.text, "1");
    try std.testing.expectEqual(add_expr.right.?.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqualStrings(add_expr.right.?.text, "2");

    try std.testing.expectEqual(mul_expr.right.?.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqualStrings(mul_expr.right.?.text, "3");
}
