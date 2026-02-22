// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("../../../compiler/libjanus/astdb.zig");

// Golden Test Framework - Snapshot Persistence
// Task 3: Golden Test Integration - Snapshot save/load with CAS
// Requirements: Round-trip stability, content-addressed storage

pub const SnapshotCID = [32]u8;

pub const SnapshotAPI = struct {
    allocator: std.mem.Allocator,
    cas_store: std.HashMap(SnapshotCID, []const u8, CIDContext, std.hash_map.default_max_load_percentage),

    const CIDContext = struct {
        pub fn hash(self:id: SnapshotCID) u64 {
            _ = self;
            return std.hash_map.getAutoHashFn([32]u8, void)({}, cid);
        }

        pub fn eql(self: @This(), a: SnapshotCID, b: SnapshotCID) bool {
            _ = self;
            return std.mem.eql(u8, &a, &b);
        }
    };

    pub fn init(allocator: std.mem.Allocator) SnapshotAPI {
        return SnapshotAPI{
            .allocator = allocator,
            .cas_store = std.HashMap(SnapshotCID, []const u8, CIDContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *SnapshotAPI) void {
        // Free all stored snapshots
        var iterator = self.cas_store.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.cas_store.deinit();
    }

    /// Save snapshot to content-addressed storage
    pub fn saveSnapshot(self: *SnapshotAPI, name: []const u8, snapshot: *const astdb.Snapshot) !SnapshotCID {
        _ = name; // Used for debugging/logging

        // Serialize snapshot using canonical format
        const bytes = try self.serializeSnapshot(snapshot);

        // Compute CID
        var hasher = std.crypto.hash.blake3.Blake3.init(.{});
        hasher.update(bytes);
        const cid = hasher.finalize();

        // Store in CAS
        try self.casPut(cid, bytes);

        return cid;
    }

    /// Load snapshot from content-addressed storage
    pub fn loadSnapshot(self: *SnapshotAPI, cid: SnapshotCID, str_interner: *astdb.StrInterner) !*astdb.Snapshot {
        const bytes = try self.casGet(cid);
        return try self.deserializeSnapshot(bytes, str_interner);
    }

    /// Serialize snapshot to canonical bytes
    fn serializeSnapshot(self: *SnapshotAPI, snapshot: *const astdb.Snapshot) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit();

        const writer = buf.writer();

        // Header
        try writer.writeAll("JANUS_SNAPSHOT_V1\n");

        // Serialize tables in canonical order
        try self.writeULEB128(writer, snapshot.tokenCount());
        try self.writeULEB128(writer, snapshot.nodeCount());
        try self.writeULEB128(writer, snapshot.declCount());
        try self.writeULEB128(writer, snapshot.diagCount());

        // Token table
        for (0..snapshot.tokenCount()) |i| {
            const token_id: astdb.TokenId = @enumFromInt(@as(u32, @intCast(i)));
            const token = snapshot.getToken(token_id) orelse continue;

            try self.writeULEB128(writer, @intFromEnum(token.kind));
            try self.writeULEB128(writer, astdb.ids.toU32(token.str_id));
            try self.writeSpan(writer, token.span);
        }

        // Node table
        for (0..snapshot.nodeCount()) |i| {
            const node_id: astdb.NodeId = @enumFromInt(@as(u32, @intCast(i)));
            const node = snapshot.getNode(node_id) orelse continue;

            try self.writeULEB128(writer, @intFromEnum(node.kind));
            try self.writeULEB128(writer, astdb.ids.toU32(node.first_token));
            try self.writeULEB128(writer, astdb.ids.toU32(node.last_token));
            try self.writeULEB128(writer, node.child_count);

            // Write children
            const children = node.children(snapshot);
            for (children) |child_id| {
                try self.writeULEB128(writer, astdb.ids.toU32(child_id));
            }
        }

        // Declaration table
        for (0..snapshot.declCount()) |i| {
            const decl_id: astdb.DeclId = @enumFromInt(@as(u32, @intCast(i)));
            const decl = snapshot.getDecl(decl_id) orelse continue;

            try self.writeULEB128(writer, astdb.ids.toU32(decl.node));
            try self.writeULEB128(writer, astdb.ids.toU32(decl.name));
            try self.writeULEB128(writer, astdb.ids.toU32(decl.scope));
            try self.writeULEB128(writer, @intFromEnum(decl.kind));
            try self.writeULEB128(writer, astdb.ids.toU32(decl.type_id));
        }

        // CID table
        var cid_iterator = snapshot.cids.iterator();
        try self.writeULEB128(writer, @as(u32, @intCast(snapshot.cids.count())));
        while (cid_iterator.next()) |entry| {
            try self.writeULEB128(writer, astdb.ids.toU32(entry.key_ptr.*));
            try writer.writeAll(&entry.value_ptr.*);
        }

        return try buf.toOwnedSlice(alloc);
    }

    /// Deserialize snapshot from canonical bytes
    fn deserializeSnapshot(self: *SnapshotAPI, bytes: []const u8, str_interner: *astdb.StrInterner) !*astdb.Snapshot {
        var reader = std.io.fixedBufferStream(bytes).reader();

        // Verify header
        var header_buf: [18]u8 = undefined;
        _ = try reader.readAll(&header_buf);
        if (!std.mem.eql(u8, &header_buf, "JANUS_SNAPSHOT_V1\n")) {
            return error.InvalidSnapshotHeader;
        }

        // Read table sizes
        const token_count = try self.readULEB128(reader);
        const node_count = try self.readULEB128(reader);
        const decl_count = try self.readULEB128(reader);
        const diag_count = try self.readULEB128(reader);
        _ = diag_count;

        // Create new snapshot
        var snapshot = try astdb.Snapshot.init(self.allocator, str_interner);

        // Deserialize tokens
        for (0..token_count) |_| {
            const kind_raw = try self.readULEB128(reader);
            const str_id_raw = try self.readULEB128(reader);
            const span = try self.readSpan(reader);

            const kind: astdb.TokenKind = @enumFromInt(@as(u8, @intCast(kind_raw)));
            const str_id: astdb.StrId = @enumFromInt(str_id_raw);

            _ = try snapshot.addToken(kind, str_id, span);
        }

        // Deserialize nodes
        for (0..node_count) |_| {
            const kind_raw = try self.readULEB128(reader);
            const first_token_raw = try self.readULEB128(reader);
            const last_token_raw = try self.readULEB128(reader);
            const child_count = try self.readULEB128(reader);

            const kind: astdb.NodeKind = @enumFromInt(@as(u8, @intCast(kind_raw)));
            const first_token: astdb.TokenId = @enumFromInt(first_token_raw);
            const last_token: astdb.TokenId = @enumFromInt(last_token_raw);

            // Read children
            var children = try self.allocator.alloc(astdb.NodeId, child_count);
            defer self.allocator.free(children);

            for (0..child_count) |j| {
                const child_raw = try self.readULEB128(reader);
                children[j] = @enumFromInt(child_raw);
            }

            _ = try snapshot.addNode(kind, first_token, last_token, children);
        }

        // Deserialize declarations
        for (0..decl_count) |_| {
            const node_raw = try self.readULEB128(reader);
            const name_raw = try self.readULEB128(reader);
            const scope_raw = try self.readULEB128(reader);
            const kind_raw = try self.readULEB128(reader);
            const type_raw = try self.readULEB128(reader);

            const node: astdb.NodeId = @enumFromInt(node_raw);
            const name: astdb.StrId = @enumFromInt(name_raw);
            const scope: astdb.ScopeId = @enumFromInt(scope_raw);
            const kind: astdb.DeclKind = @enumFromInt(@as(u8, @intCast(kind_raw)));
            _ = type_raw;

            _ = try snapshot.addDecl(node, name, scope, kind);
        }

        // Deserialize CIDs
        const cid_count = try self.readULEB128(reader);
        for (0..cid_count) |_| {
            const node_raw = try self.readULEB128(reader);
            var cid: astdb.CID = undefined;
            _ = try reader.readAll(&cid);

            const node_id: astdb.NodeId = @enumFromInt(node_raw);
            try snapshot.setCID(node_id, cid);
        }

        return snapshot;
    }

    /// Store bytes in content-addressed storage
    fn casPut(self: *SnapshotAPI, cid: SnapshotCID, bytes: []const u8) !void {
        const owned_bytes = try self.allocator.dupe(u8, bytes);
        try self.cas_store.put(cid, owned_bytes);
    }

    /// Retrieve bytes from content-addressed storage
    fn casGet(self: *SnapshotAPI, cid: SnapshotCID) ![]const u8 {
        return self.cas_store.get(cid) orelse error.SnapshotNotFound;
    }

    // Serialization helpers

    fn writeULEB128(self: *SnapshotAPI, writer: anytype, value: u32) !void {
        _ = self;
        var val = value;
        while (val >= 0x80) {
            try writer.writeByte(@as(u8, @intCast((val & 0x7F) | 0x80)));
            val >>= 7;
        }
        try writer.writeByte(@as(u8, @intCast(val & 0x7F)));
    }

    fn readULEB128(self: *SnapshotAPI, reader: anytype) !u32 {
        _ = self;
        var result: u32 = 0;
        var shift: u5 = 0;

        while (true) {
            const byte = try reader.readByte();
            result |= (@as(u32, byte & 0x7F) << shift);

            if ((byte & 0x80) == 0) break;
            shift += 7;
            if (shift >= 32) return error.InvalidULEB128;
        }

        return result;
    }

    fn writeSpan(self: *SnapshotAPI, writer: anytype, span: astdb.Span) !void {
        try self.writeULEB128(writer, span.start_byte);
        try self.writeULEB128(writer, span.end_byte);
        try self.writeULEB128(writer, span.start_line);
        try self.writeULEB128(writer, span.start_col);
        try self.writeULEB128(writer, span.end_line);
        try self.writeULEB128(writer, span.end_col);
    }

    fn readSpan(self: *SnapshotAPI, reader: anytype) !astdb.Span {
        return astdb.Span{
            .start_byte = try self.readULEB128(reader),
            .end_byte = try self.readULEB128(reader),
            .start_line = try self.readULEB128(reader),
            .start_col = try self.readULEB128(reader),
            .end_line = try self.readULEB128(reader),
            .end_col = try self.readULEB128(reader),
        };
    }
};

test "SnapshotAPI round-trip" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = try astdb.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var snapshot_api = SnapshotAPI.init(allocator);
    defer snapshot_api.deinit();

    // Create test snapshot
    var original_snapshot = try astdb.Snapshot.init(allocator, &str_interner);
    defer original_snapshot.deinit();

    const test_str = try str_interner.get("test");
    const token_id = try original_snapshot.addToken(.identifier, test_str, astdb.Span{
        .start_byte = 0, .end_byte = 4, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 5,
    });
    const node_id = try original_snapshot.addNode(.identifier, token_id, token_id, &[_]astdb.NodeId{});

    // Save snapshot
    const cid = try snapshot_api.saveSnapshot("test", original_snapshot);

    // Load snapshot
    var loaded_snapshot = try snapshot_api.loadSnapshot(cid, &str_interner);
    defer loaded_snapshot.deinit();

    // Verify round-trip
    try testing.expectEqual(original_snapshot.tokenCount(), loaded_snapshot.tokenCount());
    try testing.expectEqual(original_snapshot.nodeCount(), loaded_snapshot.nodeCount());

    const original_token = original_snapshot.getToken(token_id).?;
    const loaded_token = loaded_snapshot.getToken(token_id).?;
    try testing.expectEqual(original_token.kind, loaded_token.kind);
    try testing.expectEqual(original_token.str_id, loaded_token.str_id);

    const original_node = original_snapshot.getNode(node_id).?;
    const loaded_node = loaded_snapshot.getNode(node_id).?;
    try testing.expectEqual(original_node.kind, loaded_node.kind);
    try testing.expectEqual(original_node.child_count, loaded_node.child_count);

    std.log.info("✅ SnapshotAPI round-trip test passed", .{});
}
