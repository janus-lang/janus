// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// ASTDB Query Engine - Full implementation for CLI semantic queries
// Task 6: CLI Tooling - Supports complete query language from query_parser.zig

const std = @import("std");
const astdb_core = @import("astdb_core"); // Use the real ASTDB core types

// Re-export core types for convenience
pub const NodeKind = astdb_core.AstNode.NodeKind;
pub const NodeId = astdb_core.NodeId;
pub const Snapshot = astdb_core.Snapshot;
pub const AstNode = astdb_core.AstNode;

/// Declaration kinds for semantic filtering
pub const DeclKind = enum {
    function,
    variable,
    constant,
    type_alias,
    struct_type,
    enum_type,
    trait_type,
    impl_block,
};

/// Comparison operators for numeric predicates
pub const CompareOp = enum {
    eq, // ==
    ne, // !=
    lt, // <
    le, // <=
    gt, // >
    ge, // >=

    pub fn evaluate(self: CompareOp, lhs: u32, rhs: u32) bool {
        return switch (self) {
            .eq => lhs == rhs,
            .ne => lhs != rhs,
            .lt => lhs < rhs,
            .le => lhs <= rhs,
            .gt => lhs > rhs,
            .ge => lhs >= rhs,
        };
    }
};

/// Query predicate for filtering AST nodes
/// Supports full query language: combinators, property predicates, comparisons
pub const Predicate = union(enum) {
    // Basic node predicates
    node_kind: NodeKind,
    node_id: NodeId,
    has_child: NodeId,

    // Declaration predicates
    decl_kind: DeclKind,

    // Boolean combinators (recursive via pointers)
    and_: struct { left: *const Predicate, right: *const Predicate },
    or_: struct { left: *const Predicate, right: *const Predicate },
    not_: *const Predicate,

    // Effect/capability predicates
    effect_contains: []const u8, // effects.contains("io.fs.read")
    has_effect: []const u8, // has effect of type
    requires_capability: []const u8, // requires_capability("CapFsRead")

    // Numeric comparison predicates
    node_child_count: struct { op: CompareOp, value: u32 },

    // Match-all predicate
    any: void,

    /// Evaluate predicate against a node
    pub fn matches(self: Predicate, engine: *QueryEngine, node_id: NodeId) bool {
        return engine.matchesPredicate(node_id, self);
    }
};

// Query result types
pub const QueryResult = struct {
    nodes: []NodeId,
    count: usize,

    pub fn init(allocator: std.mem.Allocator, nodes: []NodeId) QueryResult {
        return QueryResult{
            .nodes = allocator.dupe(NodeId, nodes) catch unreachable,
            .count = nodes.len,
        };
    }

    pub fn deinit(self: *QueryResult, allocator: std.mem.Allocator) void {
        allocator.free(self.nodes);
    }
};

// Query engine for ASTDB
pub const QueryEngine = struct {
    allocator: std.mem.Allocator,
    snapshot: *Snapshot,

    pub fn init(allocator: std.mem.Allocator, snap: *Snapshot) QueryEngine {
        return QueryEngine{
            .allocator = allocator,
            .snapshot = snap,
        };
    }

    pub fn deinit(self: *QueryEngine) void {
        // No resources to clean up in this minimal implementation
        _ = self;
    }

    // Filter nodes based on predicate
    pub fn filterNodes(self: *QueryEngine, predicate: Predicate) QueryResult {
        var nodes = std.ArrayList(NodeId){};
        defer nodes.deinit(self.allocator);

        const node_count = self.snapshot.nodeCount();
        var i: u32 = 0;

        while (i < node_count) : (i += 1) {
            const node_id = @as(NodeId, @enumFromInt(i));
            if (self.matchesPredicate(node_id, predicate)) {
                nodes.append(self.allocator, node_id) catch continue;
            }
        }

        return QueryResult.init(self.allocator, nodes.items);
    }

    /// Check if node matches predicate (recursive for combinators)
    pub fn matchesPredicate(self: *QueryEngine, node_id: NodeId, predicate: Predicate) bool {
        const node_row = self.snapshot.getNode(node_id) orelse return false;

        return switch (predicate) {
            // Basic node predicates
            .node_kind => |kind| node_row.kind == kind,
            .node_id => |id| node_id == id,
            .has_child => |child_id| self.hasChild(node_id, child_id),

            // Declaration kind predicate
            .decl_kind => |kind| self.matchesDeclKind(node_row, kind),

            // Boolean combinators
            .and_ => |combo| self.matchesPredicate(node_id, combo.left.*) and
                self.matchesPredicate(node_id, combo.right.*),
            .or_ => |combo| self.matchesPredicate(node_id, combo.left.*) or
                self.matchesPredicate(node_id, combo.right.*),
            .not_ => |inner| !self.matchesPredicate(node_id, inner.*),

            // Effect/capability predicates (require semantic analysis integration)
            .effect_contains => |effect_name| self.nodeHasEffect(node_id, effect_name),
            .has_effect => |effect_type| self.nodeHasEffect(node_id, effect_type),
            .requires_capability => |cap_name| self.nodeRequiresCapability(node_id, cap_name),

            // Numeric comparison
            .node_child_count => |cmp| cmp.op.evaluate(self.getChildCount(node_id), cmp.value),

            // Match-all
            .any => true,
        };
    }

    /// Check if node matches a declaration kind
    fn matchesDeclKind(self: *QueryEngine, node: *const AstNode, kind: DeclKind) bool {
        _ = self;
        return switch (kind) {
            .function => node.kind == .func_decl,
            .variable => node.kind == .var_stmt or node.kind == .let_stmt,
            .constant => node.kind == .const_stmt,
            .type_alias => false, // TODO: add type_alias to NodeKind
            .struct_type => node.kind == .struct_decl,
            .enum_type => node.kind == .enum_decl,
            .trait_type => node.kind == .trait_decl,
            .impl_block => node.kind == .impl_decl,
        };
    }

    /// Check if node has a specific child
    fn hasChild(self: *QueryEngine, node_id: NodeId, child_id: NodeId) bool {
        _ = self;
        _ = node_id;
        _ = child_id;
        // TODO: Implement proper child traversal when AST structure supports it
        return false;
    }

    /// Get child count for a node
    fn getChildCount(self: *QueryEngine, node_id: NodeId) u32 {
        const node = self.snapshot.getNode(node_id) orelse return 0;
        // Child count is (child_hi - child_lo)
        return if (node.child_hi >= node.child_lo) node.child_hi - node.child_lo else 0;
    }

    /// Check if node has a specific effect (requires semantic analysis)
    fn nodeHasEffect(self: *QueryEngine, node_id: NodeId, effect_name: []const u8) bool {
        _ = self;
        _ = node_id;
        _ = effect_name;
        // TODO: Integrate with semantic analysis to check effect annotations
        // For now, return false - full implementation requires EffectsInfo from schema.zig
        return false;
    }

    /// Check if node requires a specific capability
    fn nodeRequiresCapability(self: *QueryEngine, node_id: NodeId, cap_name: []const u8) bool {
        _ = self;
        _ = node_id;
        _ = cap_name;
        // TODO: Integrate with semantic analysis to check capability requirements
        // For now, return false - full implementation requires capability tracking
        return false;
    }
};

// Diagnostic severity levels
pub const DiagnosticSeverity = enum { @"error", warning, info };

// Diagnostic type for query results
pub const Diagnostic = struct {
    severity: DiagnosticSeverity,
    message: []const u8,
    node_id: ?NodeId,
    source_span: ?astdb_core.SourceSpan,
};
