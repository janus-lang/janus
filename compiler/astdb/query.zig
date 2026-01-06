// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("astdb_core");

const NodeId = astdb.NodeId;
const UnitId = astdb.UnitId;
const DeclId = astdb.DeclId;
const TokenId = astdb.TokenId;
const RefId = astdb.RefId;
const AstDB = astdb.AstDB;
const CompilationUnit = astdb.CompilationUnit;
const Token = astdb.Token;

pub const Position = struct {
    line: u32,
    character: u32,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Location = struct {
    uri: []const u8,
    range: Range,
};

/// Helper to convert byte offsets to line/column positions
pub const LineIndex = struct {
    line_starts: []usize, // Byte offset where each line starts
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !LineIndex {
        var starts = try std.ArrayList(usize).initCapacity(allocator, 16);
        errdefer starts.deinit(allocator);

        try starts.append(allocator, 0); // Line 0 starts at byte 0

        for (source, 0..) |byte, i| {
            if (byte == '\n') {
                try starts.append(allocator, i + 1); // Next line starts after \n
            }
        }

        return .{
            .line_starts = try starts.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LineIndex) void {
        self.allocator.free(self.line_starts);
    }

    pub fn byteToPosition(self: LineIndex, byte_offset: usize) Position {
        // Binary search to find which line contains this byte offset
        var line: u32 = 0;
        for (self.line_starts, 0..) |_, i| {
            if (i + 1 < self.line_starts.len and byte_offset >= self.line_starts[i + 1]) {
                continue;
            }
            line = @intCast(i);
            break;
        }

        const line_start = self.line_starts[line];
        const character: u32 = @intCast(byte_offset - line_start);

        return .{ .line = line, .character = character };
    }

    pub fn positionToByte(self: LineIndex, position: Position) ?usize {
        if (position.line >= self.line_starts.len) return null;
        const line_start = self.line_starts[position.line];

        // Check if next line exists to boundary check
        var line_end: usize = 0;
        if (position.line + 1 < self.line_starts.len) {
            line_end = self.line_starts[position.line + 1];
        } else {
            // Implicit EOF
            line_end = std.math.maxInt(usize);
        }

        const offset = line_start + position.character;
        if (offset >= line_end) return null; // Character out of bounds for this line
        return offset;
    }
};

/// Find the most specific node at the given position
pub fn findNodeAtPosition(
    db: *AstDB,
    unit_id: UnitId,
    line: u32,
    character: u32,
    allocator: std.mem.Allocator,
) !?NodeId {
    const unit = db.getUnit(unit_id) orelse return null;

    // We need a LineIndex to convert (line, char) -> byte offset
    var line_index = try LineIndex.init(allocator, unit.source);
    defer line_index.deinit();

    const offset = line_index.positionToByte(.{ .line = line, .character = character }) orelse return null;

    // 1. Find token at position
    var tid: ?u32 = null;
    for (unit.tokens, 0..) |tok, i| {
        const start = tok.span.start;
        const end = tok.span.end;
        if (start <= offset and offset < end) {
            tid = @as(u32, @intCast(i));
            break;
        }
    }

    // Fallback: cursor might be at end of token (e.g. "word|")
    if (tid == null and offset > 0) {
        const prev_offset = offset - 1;
        for (unit.tokens, 0..) |tok, i| {
            if (tok.span.start <= prev_offset and prev_offset < tok.span.end) {
                tid = @as(u32, @intCast(i));
                break;
            }
        }
    }

    if (tid == null) return null;
    const token_idx = tid.?;

    // 2. Find Deepest Node covering this token
    var best_node: ?NodeId = null;
    var best_range: usize = std.math.maxInt(usize);

    for (unit.nodes, 0..) |node, i| {
        const first = @intFromEnum(node.first_token);
        const last = @intFromEnum(node.last_token);

        if (first <= token_idx and token_idx <= last) {
            const range = last - first;
            if (range < best_range) {
                best_range = range;
                best_node = @enumFromInt(i);
            }
        }
    }

    return best_node;
}

/// Find the definition of a symbol at the given node
pub fn findDefinition(
    db: *AstDB,
    unit_id: UnitId,
    node_id: NodeId,
) ?Location {
    // 1. Get the symbol name from the node
    const unit = db.getUnit(unit_id) orelse return null;
    const node = db.getNode(unit_id, node_id) orelse return null;

    // Check if node is an identifier
    if (node.kind != .identifier) return null;

    // Get the token for the identifier
    const first_tok = db.getToken(unit_id, node.first_token) orelse return null;
    if (first_tok.kind != .identifier) return null;

    const name_sid = first_tok.str orelse return null;
    const name = db.str_interner.get(name_sid) orelse return null;

    // 2. Search for declaration with matching name
    // This is a naive search. Ideally we use scopes.
    // TODO: Use scope-based resolution when binder is ready.

    for (unit.decls) |decl| {
        const decl_name_sid = decl.name;
        const decl_name = db.str_interner.get(decl_name_sid) orelse continue;

        if (std.mem.eql(u8, decl_name, name)) {
            // Found definition! Get location.
            // const decl_node = db.getNode(unit_id, decl.node) orelse continue;

            // We need to construct a location.
            // Ideally we shouldn't re-compute LineIndex every time if we can avoid it,
            // but `query` functions are stateless convenience helpers.
            // We might need to pass `LineIndex` or re-create it.
            // For now, re-create (expensive but safe).
            // Wait, `Location` needs `line` and `char`.
            // We'll return a special struct or just rely on wrapper to handle allocation?
            // LineIndex requires allocator.
            // Let's assume we can alloc a LineIndex here temporarily.

            // Actually, `findDefinition` returning `Location` implies `query` has access to allocator for LineIndex construction?
            // No, `Location` is POD.
            // We need an allocator to build LineIndex.
            return null; // See caller note below
        }
    }

    return null;
}

/// Improved signature that takes allocator for LineIndex
pub fn resolveDefinitionLocation(db: *AstDB, unit_id: UnitId, node_id: NodeId, allocator: std.mem.Allocator) !?Location {
    const unit = db.getUnit(unit_id) orelse return null;
    const node = db.getNode(unit_id, node_id) orelse return null;

    if (node.kind != .identifier) return null;
    const first_tok = db.getToken(unit_id, node.first_token) orelse return null;
    const name_sid = first_tok.str orelse return null;
    const name = db.str_interner.get(name_sid) orelse return null;

    // Naive search in current unit
    // TODO: Cross-unit search via imports
    for (unit.decls) |decl| {
        const decl_name = db.str_interner.get(decl.name) orelse continue;
        if (std.mem.eql(u8, decl_name, name)) {
            const decl_node = db.getNode(unit_id, decl.node) orelse continue;
            const decl_tok = db.getToken(unit_id, decl_node.first_token) orelse continue;

            var line_index = try LineIndex.init(allocator, unit.source);
            defer line_index.deinit();

            const start_pos = line_index.byteToPosition(decl_tok.span.start);
            const end_pos = line_index.byteToPosition(decl_tok.span.end);

            return Location{
                .uri = unit.path,
                .range = .{ .start = start_pos, .end = end_pos },
            };
        }
    }
    return null;
}

pub fn resolveReferences(db: *AstDB, target_unit_id: UnitId, target_node_id: NodeId, allocator: std.mem.Allocator) ![]Location {
    var locations = try std.ArrayList(Location).initCapacity(allocator, 8);
    errdefer locations.deinit(allocator);

    // 1. Identify the symbol we are looking for
    const unit = db.getUnit(target_unit_id) orelse return locations.toOwnedSlice(allocator);

    // const node = db.getNode(target_unit_id, target_node_id) orelse return locations.toOwnedSlice(allocator); // unused

    // If target is an identifier/decl, get its name
    // Assuming target_node_id points to the usage or definition
    const node_ptr = db.getNode(target_unit_id, target_node_id) orelse return locations.toOwnedSlice(allocator);

    var name_sid: astdb.StrId = undefined;

    // Handle different node types to find the name identifier
    if (node_ptr.kind == .func_decl) {
        // Scan children for name? Or scan AST tokens?
        // func_decl first_token is 'func'. Name is usually next (if not anonymous).
        const start_tok_idx = @intFromEnum(node_ptr.first_token);

        // Scan forward a few tokens to find identifier (max 5 tokens to be safe)
        var curr_idx = start_tok_idx;
        var found = false;

        var iter_count: usize = 0;
        const limit = if (unit.tokens.len > 0) unit.tokens.len else 0;

        while (curr_idx < limit and iter_count < 5) : (curr_idx += 1) {
            const t = unit.tokens[curr_idx];

            // Skip keywords and trivia-like things if necessary, but parser structure enforces order.
            // func [identifier] ...
            if (t.kind == .func) continue;

            if (t.kind == .identifier) {
                if (t.str) |sid| {
                    name_sid = sid;
                    found = true;
                }
                break;
            }
            // Stop at punctuation that ends decl head
            if (t.kind == .left_paren or t.kind == .do_ or t.kind == .left_brace) break;
            iter_count += 1;
        }

        if (!found) return locations.toOwnedSlice(allocator);
    } else {
        // Default: assume first token is the identifier (works for identifier nodes, var_stmt if variable check, etc)
        // Ideally we should be more robust here too.
        const tok = db.getToken(target_unit_id, node_ptr.first_token) orelse return locations.toOwnedSlice(allocator);
        name_sid = tok.str orelse return locations.toOwnedSlice(allocator);
    }

    // 2. Scan ALL units for usages
    // This is O(N) where N is total source size. Slow but correct (Sovereign).
    for (db.units.items) |u| {
        if (u.is_removed) continue;

        // Optimization: Check if unit contains the string at all?
        // Skip for now.

        // Scan all tokens in unit for matching identifier
        for (u.tokens, 0..) |other_tok, i| {
            if (other_tok.kind != .identifier) continue;
            const other_sid = other_tok.str orelse continue;

            // Fast integer comparison of StrIds
            if (other_sid == name_sid) {
                // Found a match!
                // Now we need its location.
                var line_index = try LineIndex.init(allocator, u.source);
                defer line_index.deinit();

                const start_pos = line_index.byteToPosition(other_tok.span.start);
                const end_pos = line_index.byteToPosition(other_tok.span.end);

                try locations.append(allocator, Location{
                    .uri = u.path,
                    .range = .{ .start = start_pos, .end = end_pos },
                });

                // We don't verify scope binding yet (Phase 2 Binder).
                // This is a "textual" reference search on AST tokens.
                _ = i;
            }
        }
    }

    return locations.toOwnedSlice(allocator);
}
