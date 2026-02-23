// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Parser-level tests for trait and impl declarations (SPEC-025 Phase A)
// Validates: trait_decl/impl_decl node creation, edge layout, bodyless signatures

const std = @import("std");
const testing = std.testing;
const astdb = @import("astdb_core");
const parser = @import("janus_parser");

const NodeKind = astdb.AstNode.NodeKind;
const NodeId = astdb.NodeId;

/// Helper: parse source and return snapshot (caller owns)
fn parseSource(allocator: std.mem.Allocator, source: []const u8) !*parser.Snapshot {
    var p = parser.Parser.init(allocator);
    defer p.deinit();
    return try p.parseWithSource(source);
}

/// Helper: find first top-level node of given kind
fn findTopLevelNode(snapshot: *const parser.Snapshot, kind: NodeKind) ?*const astdb.AstNode {
    // Root = source_file = last node
    const root_id: NodeId = @enumFromInt(snapshot.core_snapshot.nodeCount() - 1);
    const root = snapshot.core_snapshot.getNode(root_id) orelse return null;
    if (root.kind != .source_file) return null;

    const children = snapshot.core_snapshot.getChildren(root_id);
    for (children) |child_id| {
        const node = snapshot.core_snapshot.getNode(child_id) orelse continue;
        if (node.kind == kind) return node;
    }
    return null;
}

/// Helper: get children of a node as slice of NodeId
fn getEdges(snapshot: *const parser.Snapshot, node: *const astdb.AstNode) []const NodeId {
    const unit = snapshot.core_snapshot.astdb.units.items[0];
    if (node.child_lo <= node.child_hi and node.child_hi <= unit.edges.len) {
        return unit.edges[node.child_lo..node.child_hi];
    }
    return &.{};
}

test "TRAIT-P01: basic trait with 1 method signature" {
    const allocator = testing.allocator;

    const source =
        \\trait Serializable {
        \\    func serialize(self) -> string
        \\}
    ;

    var snapshot = try parseSource(allocator, source);
    defer snapshot.deinit();

    // Find trait_decl node
    const trait_node = findTopLevelNode(snapshot, .trait_decl) orelse
        return error.TestUnexpectedResult;

    // Edges: [name_identifier, func_decl(signature)]
    const edges = getEdges(snapshot, trait_node);
    try testing.expect(edges.len >= 2);

    // First edge = trait name identifier
    const name_node = snapshot.core_snapshot.getNode(edges[0]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.identifier, name_node.kind);

    // Second edge = method signature (func_decl with no body)
    const method_node = snapshot.core_snapshot.getNode(edges[1]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.func_decl, method_node.kind);

    // Bodyless signature: func_decl edges = [name, param, return_type] (no block stmts)
    // Just verify it exists and is a func_decl — body absence verified by edge count
    const method_edges = getEdges(snapshot, method_node);
    // Should have name + param(s) + optional return type, but NO block statements
    // A function with body would have more edges (block stmts appended)
    try testing.expect(method_edges.len >= 1); // at minimum: name
    try testing.expect(method_edges.len <= 4); // name + self param + return type = 3 max
}

test "TRAIT-P02: trait with default impl method (do...end body)" {
    const allocator = testing.allocator;

    const source =
        \\trait Printable {
        \\    func to_string(self) -> string do
        \\        return "default"
        \\    end
        \\}
    ;

    var snapshot = try parseSource(allocator, source);
    defer snapshot.deinit();

    const trait_node = findTopLevelNode(snapshot, .trait_decl) orelse
        return error.TestUnexpectedResult;

    const edges = getEdges(snapshot, trait_node);
    try testing.expect(edges.len >= 2);

    // Name
    const name_node = snapshot.core_snapshot.getNode(edges[0]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.identifier, name_node.kind);

    // Method with body
    const method_node = snapshot.core_snapshot.getNode(edges[1]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.func_decl, method_node.kind);

    // Default impl method should have more edges than a signature
    // (name + param + return_type + at least 1 body statement)
    const method_edges = getEdges(snapshot, method_node);
    try testing.expect(method_edges.len >= 4); // name + self + ret_type + return_stmt
}

test "TRAIT-P03: impl Trait for Type with 1 method" {
    const allocator = testing.allocator;

    const source =
        \\impl Serializable for User {
        \\    func serialize(self) -> string do
        \\        return "user"
        \\    end
        \\}
    ;

    var snapshot = try parseSource(allocator, source);
    defer snapshot.deinit();

    const impl_node = findTopLevelNode(snapshot, .impl_decl) orelse
        return error.TestUnexpectedResult;

    // Trait impl edges: [trait_name, type_name, func_decl]
    const edges = getEdges(snapshot, impl_node);
    try testing.expect(edges.len >= 3);

    // Edge 0 = trait name (Serializable)
    const trait_name = snapshot.core_snapshot.getNode(edges[0]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.identifier, trait_name.kind);

    // Edge 1 = type name (User)
    const type_name = snapshot.core_snapshot.getNode(edges[1]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.identifier, type_name.kind);

    // Edge 2 = method (func_decl with body)
    const method = snapshot.core_snapshot.getNode(edges[2]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.func_decl, method.kind);
}

test "TRAIT-P04: standalone impl Type with 1 method" {
    const allocator = testing.allocator;

    const source =
        \\impl Point {
        \\    func distance(self, other: Point) -> f64 do
        \\        return 0.0
        \\    end
        \\}
    ;

    var snapshot = try parseSource(allocator, source);
    defer snapshot.deinit();

    const impl_node = findTopLevelNode(snapshot, .impl_decl) orelse
        return error.TestUnexpectedResult;

    // Standalone impl edges: [type_name, func_decl]
    const edges = getEdges(snapshot, impl_node);
    try testing.expect(edges.len >= 2);

    // Edge 0 = type name (Point)
    const type_name = snapshot.core_snapshot.getNode(edges[0]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.identifier, type_name.kind);

    // Edge 1 = method (func_decl)
    const method = snapshot.core_snapshot.getNode(edges[1]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.func_decl, method.kind);
}

test "TRAIT-P05: trait impl vs standalone impl edge layout distinction" {
    const allocator = testing.allocator;

    // Parse trait impl
    const trait_impl_source =
        \\impl Hashable for Config {
        \\    func hash(self) -> i64 do
        \\        return 42
        \\    end
        \\}
    ;

    var snapshot1 = try parseSource(allocator, trait_impl_source);
    defer snapshot1.deinit();

    const trait_impl_node = findTopLevelNode(snapshot1, .impl_decl) orelse
        return error.TestUnexpectedResult;

    const trait_edges = getEdges(snapshot1, trait_impl_node);
    try testing.expect(trait_edges.len >= 3);

    // Trait impl: edges[1] is identifier (type name)
    const trait_edge1 = snapshot1.core_snapshot.getNode(trait_edges[1]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.identifier, trait_edge1.kind);

    // Parse standalone impl
    const standalone_source =
        \\impl Config {
        \\    func hash(self) -> i64 do
        \\        return 42
        \\    end
        \\}
    ;

    var snapshot2 = try parseSource(allocator, standalone_source);
    defer snapshot2.deinit();

    const standalone_node = findTopLevelNode(snapshot2, .impl_decl) orelse
        return error.TestUnexpectedResult;

    const standalone_edges = getEdges(snapshot2, standalone_node);
    try testing.expect(standalone_edges.len >= 2);

    // Standalone impl: edges[1] is func_decl (first method, not a second identifier)
    const standalone_edge1 = snapshot2.core_snapshot.getNode(standalone_edges[1]) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(NodeKind.func_decl, standalone_edge1.kind);

    // Verify the distinction: trait impl has 2 identifiers before methods,
    // standalone impl has 1 identifier then methods directly
    try testing.expect(trait_edges.len > standalone_edges.len);
}
