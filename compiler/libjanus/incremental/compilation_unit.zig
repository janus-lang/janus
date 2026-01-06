// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Compilation Unit - Core Abstraction for Incremental Compilation
// Task 2.1: Create Compilation Unit Abstraction
//
// This module defines the CompilationUnit structure that represents a complete
// compilation unit with both interface and implementation content-addressed identifiers.
// This is built upon the proven Interface Hashing foundation.

const std = @import("std");
const astdb = @import("../astdb.zig");
const interface_cid_mod = @import("interface_cid.zig");
const InterfaceCID = interface_cid_mod.InterfaceCID;
const Snapshot = astdb.Snapshot;
const NodeId = astdb.NodeId;
const CID = astdb.CID;

// BLAKE3 for cryptographic content addressing
const Blake3 = std.crypto.hash.Blake3;

/// Semantic CID - Content-addressed identifier for complete semantic content
/// This includes both interface and implementation, used for full compilation tracking
pub const SemanticCID = struct {
    hash: [32]u8,

    pub fn eql(self: SemanticCID, other: SemanticCID) bool {
        return std.mem.eql(u8, &self.hash, &other.hash);
    }

    pub fn format(self: SemanticCID, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("SemanticCID(");
        const hex_chars = "0123456789abcdef";
        for (self.hash) |byte| {
            try writer.writeByte(hex_chars[byte >> 4]);
            try writer.writeByte(hex_chars[byte & 0x0f]);
        }
        try writer.writeAll(")");
    }
};

/// Compilation Unit - Represents a complete compilation unit with dual CID tracking
pub const CompilationUnit = struct {
    /// Source file path for this compilation unit
    source_file: []const u8,

    /// Interface CID - changes only when public interface changes
    interface_cid: InterfaceCID,

    /// Semantic CID - changes when any semantic content changes
    semantic_cid: SemanticCID,

    /// Dependency Interface CID - represents interface dependencies
    dependency_cid: InterfaceCID,

    /// Root ASTDB node for this compilation unit
    root_node: NodeId,

    /// Last modification timestamp
    last_modified: i64,

    /// Compilation unit metadata
    metadata: CompilationUnitMetadata,

    pub fn init(
        allocator: std.mem.Allocator,
        source_file: []const u8,
        root_node: NodeId,
        interface_cid: InterfaceCID,
        semantic_cid: SemanticCID,
        dependency_cid: InterfaceCID,
    ) !CompilationUnit {
        const owned_source_file = try allocator.dupe(u8, source_file);

        return CompilationUnit{
            .source_file = owned_source_file,
            .interface_cid = interface_cid,
            .semantic_cid = semantic_cid,
            .dependency_cid = dependency_cid,
            .root_node = root_node,
            .last_modified = std.time.timestamp(),
            .metadata = CompilationUnitMetadata.init(),
        };
    }

    pub fn deinit(self: *CompilationUnit, allocator: std.mem.Allocator) void {
        allocator.free(self.source_file);
        self.metadata.deinit(allocator);
    }

    /// Check if this compilation unit needs rebuilding based on interface dependencies
    pub fn needsRebuild(self: *const CompilationUnit, current_dependency_cid: InterfaceCID) bool {
        return !self.dependency_cid.eql(current_dependency_cid);
    }

    /// Check if this compilation unit's interface has changed
    pub fn interfaceChanged(self: *const CompilationUnit, new_interface_cid: InterfaceCID) bool {
        return !self.interface_cid.eql(new_interface_cid);
    }

    /// Check if this compilation unit's implementation has changed
    pub fn implementationChanged(self: *const CompilationUnit, new_semantic_cid: SemanticCID) bool {
        return !self.semantic_cid.eql(new_semantic_cid);
    }

    /// Update CIDs after recompilation
    pub fn updateCIDs(
        self: *CompilationUnit,
        new_interface_cid: InterfaceCID,
        new_semantic_cid: SemanticCID,
        new_dependency_cid: InterfaceCID,
    ) void {
        self.interface_cid = new_interface_cid;
        self.semantic_cid = new_semantic_cid;
        self.dependency_cid = new_dependency_cid;
        self.last_modified = std.time.timestamp();
        self.metadata.compilation_count += 1;
    }

    /// Serialize compilation unit for persistent storage
    pub fn serialize(self: *const CompilationUnit, writer: anytype) !void {
        // Write source file path
        try writer.writeInt(u32, @as(u32, @intCast(self.source_file.len)), .little);
        try writer.writeAll(self.source_file);

        // Write CIDs
        try writer.writeAll(&self.interface_cid.hash);
        try writer.writeAll(&self.semantic_cid.hash);
        try writer.writeAll(&self.dependency_cid.hash);

        // Write root node ID
        try writer.writeInt(u32, @intFromEnum(self.root_node), .little);

        // Write timestamp
        try writer.writeInt(i64, self.last_modified, .little);

        // Write metadata
        try self.metadata.serialize(writer);
    }

    /// Deserialize compilation unit from persistent storage
    pub fn deserialize(allocator: std.mem.Allocator, reader: anytype) !CompilationUnit {
        // Read source file path
        const path_len = try reader.readInt(u32, .little);
        const source_file = try allocator.alloc(u8, path_len);
        try reader.readNoEof(source_file);

        // Read CIDs
        var interface_hash: [32]u8 = undefined;
        var semantic_hash: [32]u8 = undefined;
        var dependency_hash: [32]u8 = undefined;

        try reader.readNoEof(&interface_hash);
        try reader.readNoEof(&semantic_hash);
        try reader.readNoEof(&dependency_hash);

        // Read root node ID
        const root_node_raw = try reader.readInt(u32, .little);
        const root_node: NodeId = @enumFromInt(root_node_raw);

        // Read timestamp
        const last_modified = try reader.readInt(i64, .little);

        // Read metadata
        const metadata = try CompilationUnitMetadata.deserialize(allocator, reader);

        return CompilationUnit{
            .source_file = source_file,
            .interface_cid = InterfaceCID{ .hash = interface_hash },
            .semantic_cid = SemanticCID{ .hash = semantic_hash },
            .dependency_cid = InterfaceCID{ .hash = dependency_hash },
            .root_node = root_node,
            .last_modified = last_modified,
            .metadata = metadata,
        };
    }
};

/// Compilation Unit Metadata - Additional information for debugging and optimization
pub const CompilationUnitMetadata = struct {
    /// Number of times this unit has been compiled
    compilation_count: u32,

    /// Size of the source file in bytes
    source_size: u64,

    /// Number of interface elements extracted
    interface_element_count: u32,

    /// Number of ASTDB nodes in this compilation unit
    node_count: u32,

    /// Compilation time statistics
    last_compilation_time_ms: u64,
    total_compilation_time_ms: u64,

    /// Cache hit statistics
    interface_cache_hits: u32,
    semantic_cache_hits: u32,

    pub fn init() CompilationUnitMetadata {
        return CompilationUnitMetadata{
            .compilation_count = 0,
            .source_size = 0,
            .interface_element_count = 0,
            .node_count = 0,
            .last_compilation_time_ms = 0,
            .total_compilation_time_ms = 0,
            .interface_cache_hits = 0,
            .semantic_cache_hits = 0,
        };
    }

    pub fn deinit(self: *CompilationUnitMetadata, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // No dynamic allocations in metadata currently
    }

    pub fn recordCompilation(self: *CompilationUnitMetadata, compilation_time_ms: u64) void {
        self.compilation_count += 1;
        self.last_compilation_time_ms = compilation_time_ms;
        self.total_compilation_time_ms += compilation_time_ms;
    }

    pub fn recordCacheHit(self: *CompilationUnitMetadata, cache_type: CacheType) void {
        switch (cache_type) {
            .interface => self.interface_cache_hits += 1,
            .semantic => self.semantic_cache_hits += 1,
        }
    }

    pub fn getAverageCompilationTime(self: *const CompilationUnitMetadata) f64 {
        if (self.compilation_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_compilation_time_ms)) / @as(f64, @floatFromInt(self.compilation_count));
    }

    pub fn serialize(self: *const CompilationUnitMetadata, writer: anytype) !void {
        try writer.writeInt(u32, self.compilation_count, .little);
        try writer.writeInt(u64, self.source_size, .little);
        try writer.writeInt(u32, self.interface_element_count, .little);
        try writer.writeInt(u32, self.node_count, .little);
        try writer.writeInt(u64, self.last_compilation_time_ms, .little);
        try writer.writeInt(u64, self.total_compilation_time_ms, .little);
        try writer.writeInt(u32, self.interface_cache_hits, .little);
        try writer.writeInt(u32, self.semantic_cache_hits, .little);
    }

    pub fn deserialize(allocator: std.mem.Allocator, reader: anytype) !CompilationUnitMetadata {
        _ = allocator;

        return CompilationUnitMetadata{
            .compilation_count = try reader.readInt(u32, .little),
            .source_size = try reader.readInt(u64, .little),
            .interface_element_count = try reader.readInt(u32, .little),
            .node_count = try reader.readInt(u32, .little),
            .last_compilation_time_ms = try reader.readInt(u64, .little),
            .total_compilation_time_ms = try reader.readInt(u64, .little),
            .interface_cache_hits = try reader.readInt(u32, .little),
            .semantic_cache_hits = try reader.readInt(u32, .little),
        };
    }
};

pub const CacheType = enum {
    interface,
    semantic,
};

/// Semantic CID Generator - generates content-addressed identifiers for complete semantic content
pub const SemanticCIDGenerator = struct {
    allocator: std.mem.Allocator,
    snapshot: *const Snapshot,
    interface_cid_generator: interface_cid_mod.InterfaceCIDGenerator,

    pub fn init(allocator: std.mem.Allocator, snapshot: *const Snapshot) SemanticCIDGenerator {
        return SemanticCIDGenerator{
            .allocator = allocator,
            .snapshot = snapshot,
            .interface_cid_generator = interface_cid_mod.InterfaceCIDGenerator.init(allocator, snapshot),
        };
    }

    /// Generate SemanticCID for complete compilation unit (interface + implementation)
    pub fn generateSemanticCID(self: *SemanticCIDGenerator, root_node: NodeId) !SemanticCID {
        var hasher = Blake3.init(.{});

        // Hash the complete semantic content of the compilation unit
        try self.hashSemanticContent(&hasher, root_node);

        const hash = hasher.final();
        return SemanticCID{ .hash = hash };
    }

    /// Generate both Interface and Semantic CIDs for a compilation unit
    pub fn generateDualCIDs(self: *SemanticCIDGenerator, root_node: NodeId) !struct {
        interface_cid: InterfaceCID,
        semantic_cid: SemanticCID,
    } {
        const interface_cid = try self.interface_cid_generator.generateInterfaceCID(root_node);
        const semantic_cid = try self.generateSemanticCID(root_node);

        return .{
            .interface_cid = interface_cid,
            .semantic_cid = semantic_cid,
        };
    }

    /// Hash complete semantic content including both interface and implementation
    fn hashSemanticContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        const node = self.snapshot.getNode(node_id) orelse return;

        // Hash node kind
        hasher.update(@tagName(node.kind));

        // Hash node-specific semantic content
        switch (node.kind) {
            .func_decl => try self.hashFunctionContent(hasher, node_id),
            .struct_decl => try self.hashStructContent(hasher, node_id),
            .enum_decl => try self.hashEnumContent(hasher, node_id),
            .var_decl => try self.hashVariableContent(hasher, node_id),
            .module_decl => try self.hashModuleContent(hasher, node_id),

            // Hash implementation details for complete semantic content
            .block_stmt, .expr_stmt, .assign_stmt, .if_stmt, .while_stmt, .for_stmt, .return_stmt, .break_stmt, .continue_stmt => {
                try self.hashStatementContent(hasher, node_id);
            },

            .binary_op, .unary_op, .call_expr, .index_expr, .field_expr, .cast_expr => {
                try self.hashExpressionContent(hasher, node_id);
            },

            .int_literal, .float_literal, .string_literal, .bool_literal, .null_literal => {
                try self.hashLiteralContent(hasher, node_id);
            },

            .identifier, .qualified_name => {
                try self.hashIdentifierContent(hasher, node_id);
            },

            // Container nodes - recurse into children
            .program, .root => {
                const children = node.children(self.snapshot);
                for (children) |child_id| {
                    try self.hashSemanticContent(hasher, child_id);
                }
            },

            else => {
                // For unknown node types, hash children
                const children = node.children(self.snapshot);
                for (children) |child_id| {
                    try self.hashSemanticContent(hasher, child_id);
                }
            },
        }
    }

    // Semantic content hashing for specific node types

    fn hashFunctionContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        // Hash both signature (interface) AND implementation (body)
        // This is different from InterfaceCID which only hashes signature

        // TODO: Extract and hash function signature
        // TODO: Extract and hash function body
        // For now, hash the node structure
        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.hashSemanticContent(hasher, child_id);
        }
    }

    fn hashStructContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        // Hash both public fields (interface) AND private fields/methods (implementation)
        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.hashSemanticContent(hasher, child_id);
        }
    }

    fn hashEnumContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        // Hash both variants (interface) AND values/representation (implementation)
        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.hashSemanticContent(hasher, child_id);
        }
    }

    fn hashVariableContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        // Hash both type (interface) AND value/initialization (implementation)
        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.hashSemanticContent(hasher, child_id);
        }
    }

    fn hashModuleContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        // Hash both exports (interface) AND internal implementation
        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.hashSemanticContent(hasher, child_id);
        }
    }

    fn hashStatementContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        // Hash statement implementation details
        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.hashSemanticContent(hasher, child_id);
        }
    }

    fn hashExpressionContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        // Hash expression implementation details
        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.hashSemanticContent(hasher, child_id);
        }
    }

    fn hashLiteralContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        // Hash literal values
        const node = self.snapshot.getNode(node_id) orelse return;

        // Get the literal value from the first token
        if (self.snapshot.getToken(node.first_token)) |token| {
            const literal_str = self.snapshot.str_interner.str(token.str_id);
            hasher.update(literal_str);
        }
    }

    fn hashIdentifierContent(self: *SemanticCIDGenerator, hasher: *Blake3, node_id: NodeId) !void {
        // Hash identifier names
        const node = self.snapshot.getNode(node_id) orelse return;

        // Get the identifier name from the first token
        if (self.snapshot.getToken(node.first_token)) |token| {
            const identifier_str = self.snapshot.str_interner.str(token.str_id);
            hasher.update(identifier_str);
        }
    }
};

// Compilation Unit Rules - The Dual CID Architecture
//
// INTERFACE CID (InterfaceCID):
// - Changes only when public interface changes
// - Used for dependency analysis and rebuild decisions
// - Enables efficient incremental compilation
// - Generated by InterfaceCIDGenerator (proven foundation)
//
// SEMANTIC CID (SemanticCID):
// - Changes when any semantic content changes (interface OR implementation)
// - Used for complete compilation unit tracking
// - Enables cache validation and integrity checking
// - Includes everything that affects compilation output
//
// DEPENDENCY CID:
// - Represents the interface dependencies of this compilation unit
// - Changes when dependencies' interfaces change
// - Used to determine if this unit needs rebuilding
// - Computed from dependent units' InterfaceCIDs
//
// COMPILATION UNIT LIFECYCLE:
// 1. Parse source file into ASTDB snapshot
// 2. Generate InterfaceCID (interface-only content)
// 3. Generate SemanticCID (complete semantic content)
// 4. Compute DependencyCID (from dependencies' InterfaceCIDs)
// 5. Store CompilationUnit with dual CID tracking
// 6. Use InterfaceCID for dependency analysis
// 7. Use SemanticCID for cache validation
// 8. Update CIDs after recompilation
//
// This dual CID architecture enables both efficiency (InterfaceCID-based rebuilds)
// and correctness (SemanticCID-based validation) in incremental compilation.
