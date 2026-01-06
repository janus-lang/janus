// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Import from parent directory since we're in tests/
const parser = @import("../parser.zig");
const tokenizer = @import("../tokenizer.zig");
const NodeKind = parser.NodeKind;

test "parse single function creates dispatch family" {
    const source = "func add() { 42 }";
    const tokens_list = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens_list);

    const root = try parser.parse(tokens_list, std.testing.allocator);
    defer root.deinit(std.testing.allocator);
    defer std.testing.allocator.destroy(root);

    try std.testing.expectEqual(root.kind, NodeKind.Root);

    // Should have a dispatch family as the first child
    const family = root.right.?;
    try std.testing.expectEqual(family.kind, NodeKind.DispatchFamily);
    try std.testing.expectEqualStrings(family.text, "add");

    // Family should have one implementation
    try std.testing.expect(family.implementations != null);
    try std.testing.expectEqual(family.implementations.?.items.len, 1);

    // The implementation should be a function declaration
    const func_impl = family.implementations.?.items[0];
    try std.testing.expectEqual(func_impl.kind, NodeKind.FunctionDecl);
    try std.testing.expectEqualStrings(func_impl.text, "add");
}

test "parse multiple functions with same name creates dispatch family" {
    const source =
        \\func add() { 1 }
        \\func add() { 2 }
        \\func add() { 3 }
    ;
    const tokens_list = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens_list);

    const root = try parser.parse(tokens_list, std.testing.allocator);
    defer root.deinit(std.testing.allocator);
    defer std.testing.allocator.destroy(root);

    try std.testing.expectEqual(root.kind, NodeKind.Root);

    // Should have one dispatch family
    const family = root.right.?;
    try std.testing.expectEqual(family.kind, NodeKind.DispatchFamily);
    try std.testing.expectEqualStrings(family.text, "add");

    // Family should have three implementations
    try std.testing.expect(family.implementations != null);
    try std.testing.expectEqual(family.implementations.?.items.len, 3);

    // All implementations should be function declarations with the same name
    for (family.implementations.?.items) |impl| {
        try std.testing.expectEqual(impl.kind, NodeKind.FunctionDecl);
        try std.testing.expectEqualStrings(impl.text, "add");
    }

    // Check that the bodies are different (1, 2, 3)
    const first_body = family.implementations.?.items[0].right.?;
    const second_body = family.implementations.?.items[1].right.?;
    const third_body = family.implementations.?.items[2].right.?;

    try std.testing.expectEqual(first_body.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqual(second_body.kind, NodeKind.IntegerLiteral);
    try std.testing.expectEqual(third_body.kind, NodeKind.IntegerLiteral);

    try std.testing.expectEqualStrings(first_body.text, "1");
    try std.testing.expectEqualStrings(second_body.text, "2");
    try std.testing.expectEqualStrings(third_body.text, "3");
}

test "parse functions with different names creates separate dispatch families" {
    const source =
        \\func add() { 1 }
        \\func multiply() { 2 }
        \\func add() { 3 }
    ;
    const tokens_list = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens_list);

    const root = try parser.parse(tokens_list, std.testing.allocator);
    defer root.deinit(std.testing.allocator);
    defer std.testing.allocator.destroy(root);

    try std.testing.expectEqual(root.kind, NodeKind.Root);

    // Should have two dispatch families
    const first_family = root.right.?;
    const second_family = first_family.right.?;

    try std.testing.expectEqual(first_family.kind, NodeKind.DispatchFamily);
    try std.testing.expectEqual(second_family.kind, NodeKind.DispatchFamily);

    // Check family names (order might vary, so check both possibilities)
    const first_name = first_family.text;
    const second_name = second_family.text;

    const has_add = std.mem.eql(u8, first_name, "add") or std.mem.eql(u8, second_name, "add");
    const has_multiply = std.mem.eql(u8, first_name, "multiply") or std.mem.eql(u8, second_name, "multiply");

    try std.testing.expect(has_add);
    try std.testing.expect(has_multiply);

    // The add family should have 2 implementations, multiply should have 1
    if (std.mem.eql(u8, first_name, "add")) {
        try std.testing.expectEqual(first_family.implementations.?.items.len, 2);
        try std.testing.expectEqual(second_family.implementations.?.items.len, 1);
    } else {
        try std.testing.expectEqual(first_family.implementations.?.items.len, 1);
        try std.testing.expectEqual(second_family.implementations.?.items.len, 2);
    }
}

test "dispatch family preserves function body expressions" {
    const source =
        \\func process() { print("hello") }
        \\func process() { 42 + 24 }
    ;
    const tokens_list = try tokenizer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens_list);

    const root = try parser.parse(tokens_list, std.testing.allocator);
    defer root.deinit(std.testing.allocator);
    defer std.testing.allocator.destroy(root);

    try std.testing.expectEqual(root.kind, NodeKind.Root);

    const family = root.right.?;
    try std.testing.expectEqual(family.kind, NodeKind.DispatchFamily);
    try std.testing.expectEqualStrings(family.text, "process");
    try std.testing.expectEqual(family.implementations.?.items.len, 2);

    // First implementation should have a call expression
    const first_impl = family.implementations.?.items[0];
    const first_body = first_impl.right.?;
    try std.testing.expectEqual(first_body.kind, NodeKind.CallExpr);
    try std.testing.expectEqualStrings(first_body.text, "print");

    // Second implementation should have a binary expression
    const second_impl = family.implementations.?.items[1];
    const second_body = second_impl.right.?;
    try std.testing.expectEqual(second_body.kind, NodeKind.BinaryExpr);
    try std.testing.expectEqualStrings(second_body.text, "+");
}
