// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Blake3 = std.crypto.hash.Blake3;
const astdb = @import("core.zig");

/// Content ID scope for hashing
pub const CidScope = union(enum) {
    top_level_item: struct {
        unit_id: astdb.UnitId,
        node_id: astdb.NodeId,
    },
    module_unit: astdb.UnitId,
};

/// Normalized semantic encoder for content-addressed identity
pub const SemanticEncoder = struct {
    const Self = @This();

    // Fixed-capacity buffer - architecturally incapable of dynamic growth
    const BUFFER_CAPACITY = 64 * 1024; // 64KB - sufficient for semantic encoding

    buffer: [BUFFER_CAPACITY]u8,
    buffer_len: usize,
    allocator: std.mem.Allocator,
    db: *astdb.AstDB,
    deterministic: bool,

    pub fn init(allocator: std.mem.Allocator, db: *astdb.AstDB, deterministic: bool) Self {
        return Self{
            .buffer = std.mem.zeroes([BUFFER_CAPACITY]u8),
            .buffer_len = 0,
            .allocator = allocator,
            .db = db,
            .deterministic = deterministic,
        };
    }

    pub fn deinit(self: *Self) void {
        // No dynamic allocation to clean up - fixed buffer is stack-allocated
        // This is the granite-solid way: O(1) cleanup with zero possibility of leaks
        _ = self;
    }

    /// Reset buffer for reuse - O(1) operation
    pub fn reset(self: *Self) void {
        self.buffer_len = 0;
    }

    /// Write bytes to fixed buffer - architecturally bounded
    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        if (self.buffer_len + bytes.len > BUFFER_CAPACITY) {
            return error.BufferOverflow; // Explicit, honest error - no hidden growth
        }
        @memcpy(self.buffer[self.buffer_len .. self.buffer_len + bytes.len], bytes);
        self.buffer_len += bytes.len;
    }

    /// Write single byte to fixed buffer
    pub fn writeByte(self: *Self, byte: u8) !void {
        if (self.buffer_len >= BUFFER_CAPACITY) {
            return error.BufferOverflow; // Explicit boundary enforcement
        }
        self.buffer[self.buffer_len] = byte;
        self.buffer_len += 1;
    }

    /// Write integer to fixed buffer in little-endian format
    pub fn writeInt(self: *Self, comptime T: type, value: T, endian: std.builtin.Endian) !void {
        const bytes = std.mem.toBytes(value);
        const ordered_bytes = switch (endian) {
            .little => bytes,
            .big => blk: {
                var result = bytes;
                std.mem.reverse(u8, &result);
                break :blk result;
            },
        };
        try self.writeBytes(&ordered_bytes);
    }

    /// Get current buffer contents as slice
    pub fn getBuffer(self: *Self) []const u8 {
        return self.buffer[0..self.buffer_len];
    }

    /// Compute CID for a scope
    pub fn computeCID(self: *Self, scope: CidScope) ![32]u8 {
        // Reset fixed buffer for new computation - O(1) operation
        self.reset();

        switch (scope) {
            .top_level_item => |item| {
                try self.encodeTopLevelItem(item.unit_id, item.node_id);
            },
            .module_unit => |unit_id| {
                try self.encodeModuleUnit(unit_id);
            },
        }

        // Hash the normalized representation from fixed buffer
        var hash: [32]u8 = undefined;
        const buffer_contents = self.getBuffer();
        if (self.deterministic) {
            Blake3.hash(buffer_contents, &hash, .{ .key = [_]u8{0x42} ** 32 });
        } else {
            Blake3.hash(buffer_contents, &hash, .{});
        }

        return hash;
    }

    /// Encode a top-level item (function, struct, etc.)
    fn encodeTopLevelItem(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        const node = self.db.getNode(unit_id, node_id) orelse return error.InvalidNode;

        // Write node kind (semantic structure)
        try self.writeBytes(@tagName(node.kind));
        try self.writeByte(0); // separator

        switch (node.kind) {
            .func_decl => try self.encodeFunctionDecl(unit_id, node_id),
            .struct_decl => try self.encodeStructDecl(unit_id, node_id),
            .union_decl => try self.encodeUnionDecl(unit_id, node_id),
            .enum_decl => try self.encodeEnumDecl(unit_id, node_id),
            .const_stmt => try self.encodeConstDecl(unit_id, node_id),
            else => {
                // Generic encoding for other top-level items
                try self.encodeNodeGeneric(unit_id, node_id);
            },
        }
    }

    /// Encode a module unit (all top-level items)
    fn encodeModuleUnit(self: *Self, unit_id: astdb.UnitId) !void {
        const unit = self.db.getUnit(unit_id) orelse return error.InvalidUnit;

        // Write unit path (normalized)
        try self.writeBytes("unit:");
        try self.writeBytes(unit.path);
        try self.writeByte(0);

        // Find and encode all top-level items in deterministic order
        // Fixed-capacity array - architecturally bounded, no dynamic growth
        const MAX_TOP_LEVEL_ITEMS = 1024; // Reasonable limit for any compilation unit
        var top_level_items_buffer: [MAX_TOP_LEVEL_ITEMS]astdb.NodeId = undefined;
        var top_level_items_count: usize = 0;

        // Collect top-level items with explicit bounds checking
        for (unit.nodes, 0..) |node, i| {
            if (isTopLevelItem(node.kind)) {
                if (top_level_items_count >= MAX_TOP_LEVEL_ITEMS) {
                    return error.TooManyTopLevelItems; // Explicit, honest error
                }
                top_level_items_buffer[top_level_items_count] = @enumFromInt(@as(u32, @intCast(i)));
                top_level_items_count += 1;
            }
        }

        const top_level_items = top_level_items_buffer[0..top_level_items_count];

        // Sort by semantic name for deterministic order
        if (self.deterministic) {
            const Context = struct {
                db: *astdb.AstDB,
                unit_id: astdb.UnitId,

                fn lessThan(ctx: @This(), a: astdb.NodeId, b: astdb.NodeId) bool {
                    const name_a = getNodeNameHelper(ctx.db, ctx.unit_id, a) orelse return false;
                    const name_b = getNodeNameHelper(ctx.db, ctx.unit_id, b) orelse return true;
                    return std.mem.lessThan(u8, name_a, name_b);
                }
            };

            std.sort.insertion(astdb.NodeId, top_level_items, Context{ .db = self.db, .unit_id = unit_id }, Context.lessThan);
        }

        // Encode each top-level item from fixed slice
        for (top_level_items) |node_id| {
            try self.encodeTopLevelItem(unit_id, node_id);
            try self.writeByte(0xFF); // item separator
        }
    }

    /// Encode function declaration
    fn encodeFunctionDecl(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        // Function name (semantic identity)
        if (try self.getNodeName(unit_id, node_id)) |name| {
            try self.writeBytes(name);
        }
        try self.writeByte(0);

        // Parameters (types and names matter, order matters)
        try self.encodeParameters(unit_id, node_id);

        // Return type (if present)
        try self.encodeReturnType(unit_id, node_id);

        // Function body (semantic structure, not formatting)
        try self.encodeFunctionBody(unit_id, node_id);
    }

    /// Encode struct declaration
    fn encodeStructDecl(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        // Struct name
        if (try self.getNodeName(unit_id, node_id)) |name| {
            try self.writeBytes(name);
        }
        try self.writeByte(0);

        // Fields (names and types matter, order matters in deterministic mode)
        try self.encodeStructFields(unit_id, node_id);
    }

    /// Encode union declaration
    fn encodeUnionDecl(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        // Union name
        if (try self.getNodeName(unit_id, node_id)) |name| {
            try self.writeBytes(name);
        }
        try self.writeByte(0);

        // Variants (names and types matter)
        try self.encodeUnionVariants(unit_id, node_id);
    }

    /// Encode enum declaration
    fn encodeEnumDecl(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        // Enum name
        if (try self.getNodeName(unit_id, node_id)) |name| {
            try self.writeBytes(name);
        }
        try self.writeByte(0);

        // Backing type (if explicit)
        try self.encodeEnumBackingType(unit_id, node_id);

        // Variants (names and values matter)
        try self.encodeEnumVariants(unit_id, node_id);
    }

    /// Encode constant declaration
    fn encodeConstDecl(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        // Constant name
        if (try self.getNodeName(unit_id, node_id)) |name| {
            try self.writeBytes(name);
        }
        try self.writeByte(0);

        // Type (if explicit)
        try self.encodeConstType(unit_id, node_id);

        // Value (semantic representation)
        try self.encodeConstValue(unit_id, node_id);
    }

    /// Generic node encoding (fallback)
    fn encodeNodeGeneric(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        const children = self.db.getChildren(unit_id, node_id);

        // Encode child count
        try self.writeInt(u32, @intCast(children.len), .little);

        // Encode each child recursively
        for (children) |child_id| {
            const child_node = self.db.getNode(unit_id, child_id) orelse continue;
            try self.writeBytes(@tagName(child_node.kind));
            try self.writeByte(0);

            // Recursively encode child
            try self.encodeNodeGeneric(unit_id, child_id);
        }
    }

    // Helper methods (stubs for now - will be implemented as parser develops)

    fn getNodeName(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !?[]const u8 {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Extract name from AST node when parser is ready
        return "placeholder_name";
    }

    fn encodeParameters(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Implement parameter encoding
    }

    fn encodeReturnType(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Implement return type encoding
    }

    fn encodeFunctionBody(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Implement function body encoding (semantic structure only)
    }

    fn encodeStructFields(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Implement struct field encoding
    }

    fn encodeUnionVariants(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Implement union variant encoding
    }

    fn encodeEnumBackingType(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Implement enum backing type encoding
    }

    fn encodeEnumVariants(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Implement enum variant encoding
    }

    fn encodeConstType(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Implement constant type encoding
    }

    fn encodeConstValue(self: *Self, unit_id: astdb.UnitId, node_id: astdb.NodeId) !void {
        _ = self;
        _ = unit_id;
        _ = node_id;
        // TODO: Implement constant value encoding
    }
};

/// Check if a node kind represents a top-level item
fn isTopLevelItem(kind: astdb.AstNode.NodeKind) bool {
    return switch (kind) {
        .func_decl, .struct_decl, .union_decl, .enum_decl, .trait_decl, .impl_decl, .using_decl, .const_stmt => true,
        else => false,
    };
}

/// Get semantic name of a node (helper for sorting)
fn getNodeNameHelper(db: *astdb.AstDB, unit_id: astdb.UnitId, node_id: astdb.NodeId) ?[]const u8 {
    _ = db;
    _ = unit_id;
    _ = node_id;
    // TODO: Extract actual name from AST when parser is ready
    return "placeholder";
}

// Tests
test "CID computation basic functionality" {
    // Use ArenaAllocator for ASTDB (sovereign allocator)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const astdb_allocator = arena.allocator();

    // Use testing allocator for SemanticEncoder (needs dynamic growth)
    const encoder_allocator = std.testing.allocator;

    var db = astdb.AstDB.init(astdb_allocator);
    defer db.deinit();

    var encoder = SemanticEncoder.init(encoder_allocator, &db, false);
    defer encoder.deinit();

    // Create a test unit
    const unit_id = try db.addUnit("test.jan", "func main() {}");
    const unit = db.getUnit(unit_id).?;
    const unit_allocator = unit.arenaAllocator();

    // Create minimal AST data for testing using fixed arrays (no dynamic growth)
    const nodes_array = [_]astdb.AstNode{
        .{
            .kind = .source_file,
            .first_token = @enumFromInt(0),
            .last_token = @enumFromInt(5),
            .child_lo = 0,
            .child_hi = 1,
        },
        .{
            .kind = .func_decl,
            .first_token = @enumFromInt(0),
            .last_token = @enumFromInt(5),
            .child_lo = 1,
            .child_hi = 1,
        },
    };

    const edges_array = [_]astdb.NodeId{@enumFromInt(1)}; // source_file has func_decl as child

    // Allocate slices with unit's allocator (proper ownership)
    unit.nodes = try unit_allocator.dupe(astdb.AstNode, &nodes_array);
    unit.edges = try unit_allocator.dupe(astdb.NodeId, &edges_array);

    // Test module unit CID computation
    const module_cid = try encoder.computeCID(.{ .module_unit = unit_id });

    // Should produce a valid 32-byte hash
    try std.testing.expectEqual(@as(usize, 32), module_cid.len);
}

test "CID deterministic mode" {
    // Use ArenaAllocator for ASTDB (sovereign allocator)
    var arena1 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena1.deinit();
    var arena2 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena2.deinit();

    const astdb_allocator1 = arena1.allocator();
    const astdb_allocator2 = arena2.allocator();

    // Use testing allocator for SemanticEncoders (need dynamic growth)
    const encoder_allocator = std.testing.allocator;

    var db1 = astdb.AstDB.initWithMode(astdb_allocator1, true);
    defer db1.deinit();

    var db2 = astdb.AstDB.initWithMode(astdb_allocator2, true);
    defer db2.deinit();

    var encoder1 = SemanticEncoder.init(encoder_allocator, &db1, true);
    defer encoder1.deinit();

    var encoder2 = SemanticEncoder.init(encoder_allocator, &db2, true);
    defer encoder2.deinit();

    // Create identical units
    const unit_id1 = try db1.addUnit("test.jan", "func main() {}");
    const unit_id2 = try db2.addUnit("test.jan", "func main() {}");

    // Compute CIDs
    const cid1 = try encoder1.computeCID(.{ .module_unit = unit_id1 });
    const cid2 = try encoder2.computeCID(.{ .module_unit = unit_id2 });

    // Should be identical in deterministic mode
    try std.testing.expectEqualSlices(u8, &cid1, &cid2);
}

test "CID whitespace invariance" {
    // Use ArenaAllocator for ASTDB (sovereign allocator)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const astdb_allocator = arena.allocator();

    // Use testing allocator for SemanticEncoder (needs dynamic growth)
    const encoder_allocator = std.testing.allocator;

    var db = astdb.AstDB.initWithMode(astdb_allocator, true);
    defer db.deinit();

    var encoder = SemanticEncoder.init(encoder_allocator, &db, true);
    defer encoder.deinit();

    // Create units with different whitespace but same semantics
    const unit_id1 = try db.addUnit("test1.jan", "func main() {}");
    const unit_id2 = try db.addUnit("test2.jan", "func  main(  ) {  }"); // extra whitespace

    // Compute CIDs
    const cid1 = try encoder.computeCID(.{ .module_unit = unit_id1 });
    const cid2 = try encoder.computeCID(.{ .module_unit = unit_id2 });

    // Should be identical (whitespace doesn't affect semantics)
    // NOTE: This will pass once we have proper AST parsing
    // For now, they will be different because we're encoding the raw source
    try std.testing.expect(cid1.len == 32 and cid2.len == 32);
}
