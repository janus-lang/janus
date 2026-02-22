// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("../../../compiler/libjanus/astdb.zig");

// Golden Test Framework - Semantic Diff Analysis
// Task 3: Golden Test Integration - Precise semantic change detection
// Requirements: Human-readable diffs, targeted invalidation tracking

pub const DiffKind = enum {
    TypeChange,
    LiteralChange,
    EffectMaskChange,
    CapSetChange,
    DispatchResChange,
    APIShapeChange,
    NodeStructureChange,
    DeclarationChange,
};

pub const DiffItem = struct {
    item_name: []const u8,
    kind: DiffKind,
    detail_json: []const u8, // compact JSON for golden comparison

    pub fn format(self: DiffItem, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator,
            "{{\"item\":\"{s}\",\"kind\":\"{s}\",\"detail\":{s}}}",
            .{ self.item_name, @tagName(self.kind), self.detail_json }
        );
    }
};

pub const SemanticDiffer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SemanticDiffer {
        return SemanticDiffer{ .allocator = allocator };
    }

    /// Compare two snapshots and produce semantic diff
    pub fn diffSnapshots(self: *SemanticDiffer, old_snap: *const astdb.Snapshot, new_snap: *const astdb.Snapshot) ![]DiffItem {
        var diffs: std.ArrayList(DiffItem) = .empty;
        defer diffs.deinit();

        // Compare declarations (functions, variables, etc.)
        try self.diffDeclarations(old_snap, new_snap, &diffs);

        // Compare node structures
        try self.diffNodeStructures(old_snap, new_snap, &diffs);

        return try diffs.toOwnedSlice(alloc);
    }

    /// Compare declarations between snapshots
    fn diffDeclarations(self: *SemanticDiffer, old_snap: *const astdb.Snapshot, new_snap: *const astdb.Snapshot, diffs: *std.ArrayList(DiffItem)) !void {
        // Build declaration maps by name for comparison
        var old_decls = std.HashMap(astdb.StrId, astdb.DeclId, StrIdContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer old_decls.deinit();

        var new_decls = std.HashMap(astdb.StrId, astdb.DeclId, StrIdContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer new_decls.deinit();

        // Populate old declarations
        for (0..old_snap.declCount()) |i| {
            const decl_id: astdb.DeclId = @enumFromInt(@as(u32, @intCast(i)));
            const decl = old_snap.getDecl(decl_id) orelse continue;
            try old_decls.put(decl.name, decl_id);
        }

        // Populate new declarations
        for (0..new_snap.declCount()) |i| {
            constd: astdb.DeclId = @enumFromInt(@as(u32, @intCast(i)));
            const decl = new_snap.getDecl(decl_id) orelse continue;
            try new_decls.put(decl.name, decl_id);
        }

        // Compare declarations
        var new_iter = new_decls.iterator();
        while (new_iter.next()) |new_entry| {
            const name_id = new_entry.key_ptr.*;
            const new_decl_id = new_entry.value_ptr.*;
            const new_decl = new_snap.getDecl(new_decl_id).?;

            const name_str = new_snap.str_interner.str(name_id);

            if (old_decls.get(name_id)) |old_decl_id| {
                const old_decl = old_snap.getDecl(old_decl_id).?;

                // Compare declaration properties
                if (old_decl.kind != new_decl.kind) {
                    const detail = try std.fmt.allocPrint(self.allocator,
                        "{{\"from\":\"{s}\",\"to\":\"{s}\"}}",
                        .{ @tagName(old_decl.kind), @tagName(new_decl.kind) }
                    );

                    try diffs.append(DiffItem{
                        .item_name = try self.allocator.dupe(u8, name_str),
                        .kind = .DeclarationChange,
                        .detail_json = detail,
                    });
                }

                // Compare associated nodes for deeper changes
                try self.compareNodes(old_snap, new_snap, old_decl.node, new_decl.node, name_str, diffs);

            } else {
                // New declaration
                const detail = try std.fmt.allocPrint(self.allocator,
                    "{{\"added\":\"{s}\"}}",
                    .{ @tagName(new_decl.kind) }
                );

                try diffs.append(DiffItem{
                    .item_name = try self.allocator.dupe(u8, name_str),
                    .kind = .DeclarationChange,
                    .detail_json = detail,
                });
            }
        }

        // Check for removed declarations
        var old_iter = old_decls.iterator();
        while (old_iter.next()) |old_entry| {
            const name_id = old_entry.key_ptr.*;
            const old_decl_id = old_entry.value_ptr.*;

            if (!new_decls.contains(name_id)) {
                const old_decl = old_snap.getDecl(old_decl_id).?;
                const name_str = old_snap.str_interner.str(name_id);

                const detail = try std.fmt.allocPrint(self.allocator,
                    "{{\"removed\":\"{s}\"}}",
                    .{ @tagName(old_decl.kind) }
                );

                try diffs.append(DiffItem{
                    .item_name = try self.allocator.dupe(u8, name_str),
                    .kind = .DeclarationChange,
                    .detail_json = detail,
                });
            }
        }
    }

    /// Compare individual nodes for semantic changes
    fn compareNodes(self: *SemanticDiffer, old_snap: *const astdb.Snapshot, new_snap: *const astdb.Snapshot,
                   old_node_id: astdb.NodeId, new_node_id: astdb.NodeId, item_name: []const u8,
                   diffs: *std.ArrayList(DiffItem)) !void {

        const old_node = old_snap.getNode(old_node_id) orelse return;
        const new_node = new_snap.getNode(new_node_id) orelse return;

        // Compare node kinds
        if (old_node.kind != new_node.kind) {
            const detail = try std.fmt.allocPrint(self.allocator,
                "{{\"from\":\"{s}\",\"to\":\"{s}\"}}",
                .{ @tagName(old_node.kind), @tagName(new_node.kind) }
            );

            try diffs.append(DiffItem{
                .item_name = try self.allocator.dupe(u8, item_name),
                .kind = .NodeStructureChange,
                .detail_json = detail,
            });
            return; // Major structural change, don't compare further
        }

        // Compare literals
        if (old_node.kind == .int_literal or old_node.kind == .float_literal or
            old_node.kind == .string_literal or old_node.kind == .bool_literal) {

            const old_token = old_snap.getToken(old_node.first_token);
            const new_token = new_snap.getToken(new_node.first_token);

            if (old_token != null and new_token != null) {
                const old_str = old_snap.str_interner.str(old_token.?.str_id);
                const new_str = new_snap.str_interner.str(new_token.?.str_id);

                if (!std.mem.eql(u8, old_str, new_str)) {
                    const detail = try std.fmt.allocPrint(self.allocator,
                        "{{\"from\":\"{s}\",\"to\":\"{s}\"}}",
                        .{ old_str, new_str }
                    );

                    try diffs.append(DiffItem{
                        .item_name = try self.allocator.dupe(u8, item_name),
                        .kind = .LiteralChange,
                        .detail_json = detail,
                    });
                }
            }
        }

        // Compare child structure
        if (old_node.child_count != new_node.child_count) {
            const detail = try std.fmt.allocPrint(self.allocator,
                "{{\"old_children\":{},\"new_children\":{}}}",
                .{ old_node.child_count, new_node.child_count }
            );

            try diffs.append(DiffItem{
                .item_name = try self.allocator.dupe(u8, item_name),
                .kind = .NodeStructureChange,
                .detail_json = detail,
            });
        }

        // Recursively compare children (limited depth to avoid explosion)
        const min_children = @min(old_node.child_count, new_node.child_count);
        const old_children = old_node.children(old_snap);
        const new_children = new_node.children(new_snap);

        for (0..core_children) |i| {
            try self.compareNodes(old_snap, new_snap, old_children[i], new_children[i], item_name, diffs);
        }
    }

    /// Compare node structures between snapshots
    fn diffNodeStructures(self: *SemanticDiffer, old_snap: *const astdb.Snapshot, new_snap: *const astdb.Snapshot, diffs: *std.ArrayList(DiffItem)) !void {
        // Compare CIDs if available
        if (old_snap.nodeCount() != new_snap.nodeCount()) {
            const detail = try std.fmt.allocPrint(self.allocator,
                "{{\"old_nodes\":{},\"new_nodes\":{}}}",
                .{ old_snap.nodeCount(), new_snap.nodeCount() }
            );

            try diffs.append(DiffItem{
                .item_name = try self.allocator.dupe(u8, "AST"),
                .kind = .NodeStructureChange,
                .detail_json = detail,
            });
        }

        // Compare CIDs for nodes that exist in both snapshots
        const min_nodes = @min(old_snap.nodeCount(), new_snap.nodeCount());
        for (0..core_nodes) |i| {
            const node_id: astdb.NodeId = @enumFromInt(@as(u32, @intCast(i)));

            const old_cid = old_snap.getCID(node_id);
            const new_cid = new_snap.getCID(node_id);

            if (old_cid != null and new_cid != null) {
                if (!std.mem.eql(u8, &old_cid.?, &new_cid.?)) {
                    const old_hex = try astdb.CIDUtils.format(old_cid.?, self.allocator);
                    defer self.allocator.free(old_hex);
                    const new_hex = try astdb.CIDUtils.format(new_cid.?, self.allocator);
                    defer self.allocator.free(new_hex);

                    const detail = try std.fmt.allocPrint(self.allocator,
                        "{{\"old_cid\":\"{s}\",\"new_cid\":\"{s}\"}}",
                        .{ old_hex, new_hex }
                    );

                    const item_name = try std.fmt.allocPrint(self.allocator, "node_{}", .{i});

                    try diffs.append(DiffItem{
                        .item_name = item_name,
                        .kind = .NodeStructureChange,
                        .detail_json = detail,
                    });
                }
            }
        }
    }

    /// Format diff results as JSON for golden comparison
    pub fn formatDiffAsJSON(self: *SemanticDiffer, diffs: []const DiffItem) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit();

        const writer = buf.writer();

        try writer.writeAll("{\"changed\":[");

        for (diffs, 0..) |diff, i| {
            if (i > 0) try writer.writeAll(",");
            const formatted = try diff.format(self.allocator);
            defer self.allocator.free(formatted);
            try writer.writeAll(formatted);
        }

        try writer.writeAll("],\"unchanged\":[]}"); // TODO: Track unchanged items

        return try buf.toOwnedSlice(alloc);
    }

    const StrIdContext = struct {
        pub fn hash(self: @This(), str_id: astdb.StrId) u64 {
            _ = self;
            return std.hash_map.getAutoHashFn(u32, void)({}, astdb.ids.toU32(str_id));
        }

        pub fn eql(self: @This(), a: astdb.StrId, b: astdb.StrId) bool {
            _ = self;
            return std.meta.eql(a, b);
        }
    };
};

test "SemanticDiffer basic functionality" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = try astdb.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    // Create old snapshot
    var old_snapshot = try astdb.Snapshot.init(allocator, &str_interner);
    defer old_snapshot.deinit();

    const old_str = try str_interner.get("42");
    const old_token = try old_snapshot.addToken(.int_literal, old_str, astdb.Span{
        .start_byte = 0, .end_byte = 2, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 3,
    });
    const old_node = try old_snapshot.addNode(.int_literal, old_token, old_token, &[_]astdb.NodeId{});

    // Create new snapshot with different literal
    var new_snapshot = try astdb.Snapshot.init(allocator, &str_interner);
    defer new_snapshot.deinit();

    const new_str = try str_interner.get("43");
    const new_token = try new_snapshot.addToken(.int_literal, new_str, astdb.Span{
        .start_byte = 0, .end_byte = 2, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 3,
    });
    const new_node = try new_snapshot.addNode(.int_literal, new_token, new_token, &[_]astdb.NodeId{});

    // Add declarations for comparison
    const func_name = try str_interner.get("test");
    const scope_id = try old_snapshot.addScope(astdb.ids.INVALID_SCOPE_ID);
    _ = try old_snapshot.addDecl(old_node, func_name, scope_id, .function);

    const new_scope_id = try new_snapshot.addScope(astdb.ids.INVALID_SCOPE_ID);
    _ = try new_snapshot.addDecl(new_node, func_name, new_scope_id, .function);

    // Run diff
    var differ = SemanticDiffer.init(allocator);
    const diffs = try differ.diffSnapshots(old_snapshot, new_snapshot);
    defer {
        for (diffs) |diff| {
            allocator.free(diff.item_name);
            allocator.free(diff.detail_json);
        }
        allocator.free(diffs);
    }

    // Should detect literal change
    try testing.expect(diffs.len > 0);

    // Format as JSON
    const json = try differ.formatDiffAsJSON(diffs);
    defer allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "LiteralChange") != null);

    std.log.info("✅ SemanticDiffer basic functionality test passed", .{});
}
