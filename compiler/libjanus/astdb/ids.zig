// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// ASTDB Stable ID Types
// Task 1: AST Persistence Layer - Strongly typed IDs
// Requirements: SPEC-astdb-query.md section 2.1, 2.2

/// String interning ID - references UTF-8 bytes in global interner
pub const StrId = enum(u32) { _ };

/// AST Node ID - references row in snapshot node table
pub const NodeId = enum(u32) { _ };

/// Declaration ID - references row in snapshot decl table
pub const DeclId = enum(u32) { _ };

/// Type ID - references row in global type interner
pub const TypeId = enum(u32) { _ };

/// Scope ID - references row in snapshot scope table
pub const ScopeId = enum(u32) { _ };

/// Token ID - references row in snapshot token table
pub const TokenId = enum(u32) { _ };

/// Reference ID - references row in snapshot refs table
pub const RefId = enum(u32) { _ };

/// Diagnostic ID - references row in snapshot diags table
pub const DiagId = enum(u32) { _ };

/// CID Subject - common union type for content ID computation
pub const CIDSubject = union(enum) {
    node: NodeId,
    decl: DeclId,
    module: void, // Module unit (all top-level items)
};

/// Content ID - BLAKE3 hash of normalized semantic content
pub const CID = [32]u8;

/// Invalid/null ID sentinel values
pub const INVALID_STR_ID: StrId = @enumFromInt(0xFFFFFFFF);
pub const INVALID_NODE_ID: NodeId = @enumFromInt(0xFFFFFFFF);
pub const INVALID_DECL_ID: DeclId = @enumFromInt(0xFFFFFFFF);
pub const INVALID_TYPE_ID: TypeId = @enumFromInt(0xFFFFFFFF);
pub const INVALID_SCOPE_ID: ScopeId = @enumFromInt(0xFFFFFFFF);

/// Convert ID to raw u32 for serialization/indexing
pub fn toU32(id: anytype) u32 {
    return @intFromEnum(id);
}

/// Convert raw u32 to typed ID
pub fn fromU32(comptime T: type, raw: u32) T {
    return @enumFromInt(raw);
}

test "ID type safety" {
    const testing = std.testing;

    const str_id: StrId = @enumFromInt(42);
    const node_id: NodeId = @enumFromInt(42);

    // IDs are strongly typed - cannot mix
    try testing.expectEqual(@as(u32, 42), toU32(str_id));
    try testing.expectEqual(@as(u32, 42), toU32(node_id));

    // Round-trip conversion
    try testing.expectEqual(str_id, fromU32(StrId, 42));
    try testing.expectEqual(node_id, fromU32(NodeId, 42));
}
