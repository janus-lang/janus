// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const core = @import("astdb_core");
const ids = @import("ids.zig");
const CID = ids.CID;
const UnitId = core.UnitId;
const NodeId = core.NodeId;
const TokenId = core.TokenId;
const SourceSpan = core.SourceSpan;

/// Lightweight façade on top of core ASTDB rows. Exposes convenience helpers so
/// higher layers can reason about nodes without touching the raw tables.
pub const NodeView = struct {
    ast: *core.AstDB,
    unit: *core.CompilationUnit,
    unit_id: UnitId,
    node_id: NodeId,

    pub fn init(ast: *core.AstDB, unit_id: UnitId, node_id: NodeId) NodeView {
        const unit = ast.getUnit(unit_id).?;
        return .{
            .ast = ast,
            .unit = unit,
            .unit_id = unit_id,
            .node_id = node_id,
        };
    }

    fn node(self: NodeView) *const core.AstNode {
        return &self.unit.nodes[@intFromEnum(self.node_id)];
    }

    pub fn kind(self: NodeView) core.AstNode.NodeKind {
        return self.node().kind;
    }

    pub fn span(self: NodeView) SourceSpan {
        const n = self.node();
        const first_tok = self.unit.tokens[@intFromEnum(n.first_token)];
        const last_tok = self.unit.tokens[@intFromEnum(n.last_token)];
        return SourceSpan{
            .start = first_tok.span.start,
            .end = last_tok.span.end,
            .line = first_tok.span.line,
            .column = first_tok.span.column,
        };
    }

    pub fn children(self: NodeView) []const NodeId {
        const n = self.node();
        return self.unit.edges[n.child_lo..n.child_hi];
    }

    pub fn childCount(self: NodeView) usize {
        const n = self.node();
        return n.child_hi - n.child_lo;
    }

    pub fn childAt(self: NodeView, index: usize) ?NodeView {
        const n = self.node();
        if (index >= n.child_hi - n.child_lo) return null;
        const child_id = self.unit.edges[n.child_lo + index];
        return NodeView.init(self.ast, self.unit_id, child_id);
    }

    pub fn cid(self: NodeView) ?CID {
        if (self.unit.cids.len == 0) return null;
        const idx = @intFromEnum(self.node_id);
        if (idx >= self.unit.cids.len) return null;
        return self.unit.cids[idx];
    }

    pub fn childCid(self: NodeView, child: NodeId) ?CID {
        if (self.unit.cids.len == 0) return null;
        const idx = @intFromEnum(child);
        if (idx >= self.unit.cids.len) return null;
        return self.unit.cids[idx];
    }

    pub fn parent(self: NodeView) ?NodeView {
        const target_idx = @intFromEnum(self.node_id);
        for (self.unit.nodes, 0..) |_, idx| {
            const candidate = self.unit.nodes[idx];
            if (candidate.child_lo <= target_idx and target_idx < candidate.child_hi) {
                return NodeView.init(self.ast, self.unit_id, @enumFromInt(idx));
            }
        }
        return null;
    }

    pub fn parentCid(self: NodeView) ?CID {
        if (self.parent()) |p| {
            return p.cid();
        }
        return null;
    }

    pub fn identifierText(self: NodeView) ?[]const u8 {
        const n = self.node();
        switch (n.kind) {
            .identifier, .identifier_pattern, .named_type => return self.tokenText(n.first_token),
            else => return null,
        }
    }

    pub fn literalText(self: NodeView) ?[]const u8 {
        const n = self.node();
        switch (n.kind) {
            .integer_literal, .float_literal, .string_literal, .char_literal, .bool_literal, .null_literal => return self.tokenText(n.first_token),
            else => return null,
        }
    }

    pub fn functionName(self: NodeView) ?[]const u8 {
        if (self.kind() != .func_decl) return null;
        const child_nodes = self.children();
        if (child_nodes.len == 0) return null;
        const first_child = child_nodes[0];
        const child_view = NodeView.init(self.ast, self.unit_id, first_child);
        return child_view.identifierText();
    }

    pub fn parameterNodes(self: NodeView) []const NodeId {
        if (self.kind() != .func_decl) return &.{};
        const child_nodes = self.children();
        if (child_nodes.len <= 1) return &.{};
        return child_nodes[1..];
    }

    pub fn callCallee(self: NodeView) ?NodeView {
        if (self.kind() != .call_expr) return null;
        const n = self.node();
        if (n.child_lo == n.child_hi) return null;
        const callee_id = self.unit.edges[n.child_lo];
        return NodeView.init(self.ast, self.unit_id, callee_id);
    }

    pub fn callArguments(self: NodeView) []const NodeId {
        if (self.kind() != .call_expr) return &.{};
        const n = self.node();
        if (n.child_hi <= n.child_lo + 1) return &.{};
        return self.unit.edges[n.child_lo + 1 .. n.child_hi];
    }

    pub fn modulePath(self: NodeView, allocator: std.mem.Allocator) ![]const u8 {
        if (self.kind() != .use_stmt and self.kind() != .module) return allocator.dupe(u8, "");
        var builder = std.ArrayList(u8).init(allocator);
        var writer = builder.writer();
        const child_nodes = self.children();
        var first = true;
        for (child_nodes) |child_id| {
            const child_view = NodeView.init(self.ast, self.unit_id, child_id);
            if (child_view.identifierText()) |text| {
                if (!first) try writer.print(".");
                try writer.print("{s}", .{text});
                first = false;
            }
        }
        return builder.toOwnedSlice();
    }

    fn tokenText(self: NodeView, token_id: TokenId) ?[]const u8 {
        const tok = self.unit.tokens[@intFromEnum(token_id)];
        if (tok.str) |sid| {
            return self.ast.str_interner.getString(sid);
        }
        return null;
    }
};

pub fn findNodeByCID(ast: *core.AstDB, cid: CID) ?struct { unit_id: UnitId, node_id: NodeId } {
    for (ast.units.items) |unit| {
        for (unit.cids, 0..) |node_cid, idx| {
            if (std.mem.eql(u8, &node_cid, &cid)) {
                return .{ .unit_id = unit.id, .node_id = @enumFromInt(idx) };
            }
        }
    }
    return null;
}
