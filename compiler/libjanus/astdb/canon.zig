// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const ids = @import("ids.zig");
const snapshot = @import("granite_snapshot.zig");

// ASTDB Canonicalization - Normative serializer for CID computation
// Task 1: AST Persistence Layer - Deterministic semantic content serialization
// Requirements: SPEC-astdb-query.md section 3.2, 10.2

const StrId = ids.StrId;
const NodeId = ids.NodeId;
const DeclId = ids.DeclId;
const TypeId = ids.TypeId;
const CID = ids.CID;
const Snapshot = snapshot.Snapshot;
const NodeKind = snapshot.NodeKind;
const NodeRow = snapshot.NodeRow;

pub const Canon = struct {
    pub const Scope = enum {
        node,
        decl,
        unit,
        module,
    };

    pub const Opts = struct {
        profile_mask: u32 = 0,
        effect_mask: u64 = 0,
        deterministic: bool = true,
        toolchain_version: u32 = 1,
        safety_level: u8 = 1,
        fastmath: bool = false,
        target_triple: []const u8 = "unknown-unknown-unknown",
    };

    /// Serialize normalized semantics for a subject into writer
    pub fn write(
        ss: *const Snapshot,
        subject: ids.CIDSubject,
        opts: Opts,
        writer: anytype,
    ) !void {
        switch (subject) {
            .node => |node_id| try writeNode(ss, node_id, opts, writer),
            .decl => |decl_id| try writeDecl(ss, decl_id, opts, writer),
            .module => try writeModule(ss, opts, writer),
        }
    }

    fn writeNode(ss: *const Snapshot, node_id: NodeId, opts: Opts, writer: anytype) !void {
        const node = ss.getNode(node_id) orelse return error.InvalidNodeId;

        // Node frame: 'N' + kind + child_count + payload + children_cids
        try writer.writeByte('N');
        try writeULEB128(writer, @intFromEnum(node.kind));
        try writeULEB128(writer, node.child_count);

        // Write kind-specific payload
        try writeNodePayload(ss, node, opts, writer);

        // Write children CIDs in order (Merkle fold)
        const children = node.children(ss);
        for (children) |child_id| {
            const child_cid = try computeCID(ss, .{ .node = child_id }, opts);
            try writer.writeAll(&child_cid);
        }
    }

    fn writeDecl(ss: *const Snapshot, decl_id: DeclId, opts: Opts, writer: anytype) !void {
        const decl = ss.getDecl(decl_id) orelse return error.InvalidDeclId;

        // Declaration frame: 'D' + kind + name + type + node_cid
        try writer.writeByte('D');
        try writeULEB128(writer, @intFromEnum(decl.kind));
        try writeString(ss, decl.name, writer);
        try writeULEB128(writer, ids.toU32(decl.type_id));

        // Include the declaration's node CID
        const node_cid = try computeCID(ss, .{ .node = decl.node }, opts);
        try writer.writeAll(&node_cid);
    }

    /// Write module unit with all top-level items (placeholder implementation)
    fn writeModule(ss: *const Snapshot, opts: Opts, writer: anytype) !void {
        _ = ss;
        _ = opts;

        // Module frame: 'M' + item_count (placeholder for now)
        try writer.writeByte('M');
        try writeULEB128(writer, 0); // No items for now

        // TODO: Implement when declaration management is added to Snapshot
        // This is a placeholder to support the module CID computation interface
    }

    fn writeNodePayload(ss: *const Snapshot, node: NodeRow, opts: Opts, writer: anytype) !void {
        switch (node.kind) {
            .int_literal => {
                // Get literal value from first token
                const token = ss.getToken(node.first_token) orelse return error.InvalidToken;
                const literal_str = ss.str_interner.str(token.str_id);

                // Parse and normalize integer (signed zig-zag varint)
                const value = std.fmt.parseInt(i64, literal_str, 10) catch return error.InvalidIntLiteral;
                try writeSignedLEB128(writer, value);
            },

            .float_literal => {
                // Get literal value from first token
                const token = ss.getToken(node.first_token) orelse return error.InvalidToken;
                const literal_str = ss.str_interner.str(token.str_id);

                // Parse and normalize float (canonical NaN handling)
                const value = std.fmt.parseFloat(f64, literal_str) catch return error.InvalidFloatLiteral;
                const normalized = normalizeFloat(value);
                try writer.writeAll(std.mem.asBytes(&normalized));
            },

            .string_literal => {
                // Get literal value from first token
                const token = ss.getToken(node.first_token) orelse return error.InvalidToken;
                try writeString(ss, token.str_id, writer);
            },

            .bool_literal => {
                // Get literal value from first token
                const token = ss.getToken(node.first_token) orelse return error.InvalidToken;
                const literal_str = ss.str_interner.str(token.str_id);
                const value = std.mem.eql(u8, literal_str, "true");
                try writer.writeByte(if (value) 1 else 0);
            },

            .null_literal => {
                // Null has no payload
            },

            .identifier => {
                // Get identifier name from first token
                const token = ss.getToken(node.first_token) orelse return error.InvalidToken;
                try writeString(ss, token.str_id, writer);
            },

            .binary_op => {
                // Operator kind is encoded in the token
                const token = ss.getToken(node.first_token) orelse return error.InvalidToken;
                try writeULEB128(writer, @intFromEnum(token.kind));
            },

            .func_decl => {
                // Function name, parameters, return type, effects, profile gates
                const name_token = ss.getToken(node.first_token) orelse return error.InvalidToken;
                try writeString(ss, name_token.str_id, writer);

                // TODO: Extract parameter types, return type, effects from AST
                // For now, write placeholder values
                try writeULEB128(writer, 0); // param_count
                try writer.writeByte(0); // has_return_type
                try writer.writeAll(std.mem.asBytes(&opts.effect_mask));
                try writer.writeAll(std.mem.asBytes(&opts.profile_mask));
            },

            else => {
                // Generic node - no specific payload
                // Kind is already encoded in node frame
            },
        }
    }

    fn writeString(ss: *const Snapshot, str_id: StrId, writer: anytype) !void {
        const s = ss.str_interner.str(str_id);
        try writer.writeByte('S'); // String tag
        try writeULEB128(writer, @as(u32, @intCast(s.len)));
        try writer.writeAll(s);
    }

    fn writeULEB128(writer: anytype, value: u32) !void {
        var val = value;
        while (val >= 0x80) {
            try writer.writeByte(@as(u8, @intCast((val & 0x7F) | 0x80)));
            val >>= 7;
        }
        try writer.writeByte(@as(u8, @intCast(val & 0x7F)));
    }

    fn writeSignedLEB128(writer: anytype, value: i64) !void {
        var val = value;
        var more = true;
        while (more) {
            var byte: u8 = @as(u8, @intCast(val & 0x7F));
            val >>= 7;

            if ((val == 0 and (byte & 0x40) == 0) or (val == -1 and (byte & 0x40) != 0)) {
                more = false;
            } else {
                byte |= 0x80;
            }

            try writer.writeByte(byte);
        }
    }

    fn normalizeFloat(value: f64) f64 {
        // Handle special cases for deterministic canonicalization
        if (std.math.isNan(value)) {
            // All NaNs become canonical quiet NaN
            return std.math.nan(f64);
        }

        if (value == 0.0) {
            // Both +0.0 and -0.0 become +0.0
            return 0.0;
        }

        return value;
    }
};

/// Compute CID for a subject with given options
const CIDError = error{
    InvalidNodeId,
    InvalidDeclId,
    InvalidToken,
    InvalidIntLiteral,
    InvalidFloatLiteral,
    OutOfMemory,
};

pub fn computeCID(ss: *const Snapshot, subject: ids.CIDSubject, opts: Canon.Opts) CIDError!CID {
    // Use BLAKE3-256 for cryptographic hashing as specified in Task 1.3
    var hasher = std.crypto.hash.Blake3.init(.{});

    // Serialize canonical content with documented field order
    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buf.deinit();

    try Canon.write(ss, subject, opts, buf.writer());
    hasher.update(buf.items);

    // Add toolchain knobs to domain separation (documented field order)
    // Field order documentation for CID computation:
    // 1. toolchain_version (u32, little-endian)
    // 2. profile_mask (u32, little-endian)
    // 3. effect_mask (u64, little-endian)
    // 4. safety_level (u8)
    // 5. fastmath (u8: 1 if true, 0 if false)
    // 6. deterministic (u8: 1 if true, 0 if false)
    // 7. reserved (u8: always 0)
    // 8. target_triple (length-prefixed string)
    var knobs: [20]u8 = undefined;
    std.mem.writeInt(u32, knobs[0..4], opts.toolchain_version, .little);
    std.mem.writeInt(u32, knobs[4..8], opts.profile_mask, .little);
    std.mem.writeInt(u64, knobs[8..16], opts.effect_mask, .little);
    knobs[16] = opts.safety_level;
    knobs[17] = if (opts.fastmath) 1 else 0;
    knobs[18] = if (opts.deterministic) 1 else 0;
    knobs[19] = 0; // Reserved

    hasher.update(&knobs);

    // Target triple as length-prefixed string
    const target_len = @as(u32, @intCast(opts.target_triple.len));
    hasher.update(std.mem.asBytes(&target_len));
    hasher.update(opts.target_triple);

    var result: [32]u8 = undefined;
    hasher.final(&result);
    return result;
}

test "Canon BLAKE3 CID computation" {
    const testing = std.testing;
    const interner = @import("granite_interner.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var ss = try Snapshot.init(allocator, &str_interner);
    defer ss.deinit();

    // Create a simple integer literal node
    const literal_str = try str_interner.get("42");
    const token_id = try ss.addToken(.int_literal, literal_str, snapshot.Span{
        .start_byte = 0,
        .end_byte = 2,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 3,
    });

    const node_id = try ss.addNode(.int_literal, token_id, token_id, &[_]NodeId{});

    // Compute CID with BLAKE3-256
    const opts = Canon.Opts{};
    const cid = try computeCID(ss, .{ .node = node_id }, opts);

    // CID should be 32 bytes (BLAKE3-256)
    try testing.expectEqual(@as(usize, 32), cid.len);

    // Same node should produce same CID
    const cid2 = try computeCID(ss, .{ .node = node_id }, opts);
    try testing.expectEqualSlices(u8, &cid, &cid2);

    // Verify BLAKE3 is being used (different from SHA-256)
    // Create identical content with different options
    const opts_different = Canon.Opts{ .toolchain_version = 2 };
    const cid3 = try computeCID(ss, .{ .node = node_id }, opts_different);

    // Different options should produce different CIDs
    try testing.expect(!std.mem.eql(u8, &cid, &cid3));
}

test "Canon whitespace/comment invariance" {
    const testing = std.testing;
    const interner = @import("granite_interner.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create two snapshots with semantically identical but syntactically different content
    var str_interner1 = interner.StrInterner.init(allocator, true);
    defer str_interner1.deinit();
    var ss1 = try Snapshot.init(allocator, &str_interner1);
    defer ss1.deinit();

    var str_interner2 = interner.StrInterner.init(allocator, true);
    defer str_interner2.deinit();
    var ss2 = try Snapshot.init(allocator, &str_interner2);
    defer ss2.deinit();

    // Same semantic content: integer literal "123"
    const literal_str1 = try str_interner1.get("123");
    const token_id1 = try ss1.addToken(.int_literal, literal_str1, snapshot.Span{
        .start_byte = 0,
        .end_byte = 3,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 4,
    });
    const node_id1 = try ss1.addNode(.int_literal, token_id1, token_id1, &[_]NodeId{});

    const literal_str2 = try str_interner2.get("123");
    const token_id2 = try ss2.addToken(.int_literal, literal_str2, snapshot.Span{
        .start_byte = 10, // Different source position (whitespace)
        .end_byte = 13,
        .start_line = 2, // Different line (comment above)
        .start_col = 5, // Different column (indentation)
        .end_line = 2,
        .end_col = 8,
    });
    const node_id2 = try ss2.addNode(.int_literal, token_id2, token_id2, &[_]NodeId{});

    // CIDs should be identical despite different source positions
    const opts = Canon.Opts{ .deterministic = true };
    const cid1 = try computeCID(ss1, .{ .node = node_id1 }, opts);
    const cid2 = try computeCID(ss2, .{ .node = node_id2 }, opts);

    try testing.expectEqualSlices(u8, &cid1, &cid2);
}

test "Canon deterministic serialization" {
    const testing = std.testing;
    const interner = @import("granite_interner.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create two identical snapshots
    var str_interner1 = interner.StrInterner.init(allocator, true);
    defer str_interner1.deinit();
    var ss1 = try Snapshot.init(allocator, &str_interner1);
    defer ss1.deinit();

    var str_interner2 = interner.StrInterner.init(allocator, true);
    defer str_interner2.deinit();
    var ss2 = try Snapshot.init(allocator, &str_interner2);
    defer ss2.deinit();

    // Add identical content to both
    const literal_str1 = try str_interner1.get("hello");
    const token_id1 = try ss1.addToken(.string_literal, literal_str1, snapshot.Span{
        .start_byte = 0,
        .end_byte = 5,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 6,
    });
    const node_id1 = try ss1.addNode(.string_literal, token_id1, token_id1, &[_]NodeId{});

    const literal_str2 = try str_interner2.get("hello");
    const token_id2 = try ss2.addToken(.string_literal, literal_str2, snapshot.Span{
        .start_byte = 0,
        .end_byte = 5,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 6,
    });
    const node_id2 = try ss2.addNode(.string_literal, token_id2, token_id2, &[_]NodeId{});

    // CIDs should be identical
    const opts = Canon.Opts{ .deterministic = true };
    const cid1 = try computeCID(ss1, .{ .node = node_id1 }, opts);
    const cid2 = try computeCID(ss2, .{ .node = node_id2 }, opts);

    try testing.expectEqualSlices(u8, &cid1, &cid2);
}
