// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Interface CID Generator - Critical Foundation for Incremental Compilation
// Task 1.2: Implement InterfaceCID Generation
//
// This module generates BLAKE3 content-addressed identifiers for interface-only content.
// The InterfaceCID must be stable across implementation changes but change when
// the public interface changes.
//
// DOCTRINE: This is the keystone that determines incremental compilation success.
// Get this wrong and we either miss rebuilds (catastrophic) or rebuild everything (useless).

const std = @import("std");
const astdb = @import("../astdb.zig");
const interface_extractor = @import("interface_extractor.zig");
const InterfaceElement = interface_extractor.InterfaceElement;
const InterfaceExtractor = interface_extractor.InterfaceExtractor;
const Snapshot = astdb.Snapshot;
const NodeId = astdb.NodeId;
const CID = astdb.CID;

// BLAKE3 for cryptographic content addressing
const Blake3 = std.crypto.hash.Blake3;

/// Interface CID - Content-addressed identifier for public interface only
/// This is separate from the full implementation CID
pub const InterfaceCID = struct {
    hash: [32]u8,

    pub fn eql(self: InterfaceCID, other: InterfaceCID) bool {
        return std.mem.eql(u8, &self.hash, &other.hash);
    }

    pub fn format(self: InterfaceCID, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("InterfaceCID(");
        const hex_chars = "0123456789abcdef";
        for (self.hash) |byte| {
            try writer.writeByte(hex_chars[byte >> 4]);
            try writer.writeByte(hex_chars[byte & 0x0f]);
        }
        try writer.writeAll(")");
    }
};

/// Interface CID Generator - generates content-addressed identifiers for interfaces
pub const InterfaceCIDGenerator = struct {
    allocator: std.mem.Allocator,
    snapshot: *const Snapshot,
    extractor: InterfaceExtractor,

    pub fn init(allocator: std.mem.Allocator, snapshot: *const Snapshot) InterfaceCIDGenerator {
        return InterfaceCIDGenerator{
            .allocator = allocator,
            .snapshot = snapshot,
            .extractor = InterfaceExtractor.init(allocator, snapshot),
        };
    }

    /// Generate InterfaceCID for a compilation unit
    /// This is the CRITICAL function that determines interface identity
    pub fn generateInterfaceCID(self: *InterfaceCIDGenerator, root_node: NodeId) !InterfaceCID {
        // Extract interface elements in deterministic order
        const interface_elements = try self.extractor.extractInterface(root_node);
        defer self.allocator.free(interface_elements);

        // Sort interface elements for deterministic hashing
        std.sort.insertion(InterfaceElement, interface_elements, {}, compareInterfaceElements);

        // Generate BLAKE3 hash of interface content
        var hasher = Blake3.init(.{});

        // Hash each interface element in deterministic order
        for (interface_elements) |element| {
            try self.hashInterfaceElement(&hasher, element);
        }

        const hash = hasher.final();
        return InterfaceCID{ .hash = hash };
    }

    /// Generate InterfaceCID for multiple compilation units (for dependency analysis)
    pub fn generateDependencyInterfaceCID(self: *InterfaceCIDGenerator, dependency_cids: []const InterfaceCID) !InterfaceCID {
        // Sort dependency CIDs for deterministic hashing
        const sorted_cids = try self.allocator.dupe(InterfaceCID, dependency_cids);
        defer self.allocator.free(sorted_cids);

        std.sort.insertion(InterfaceCID, sorted_cids, {}, compareInterfaceCIDs);

        var hasher = Blake3.init(.{});

        // Hash dependency CIDs in sorted order
        for (sorted_cids) |cid| {
            hasher.update(&cid.hash);
        }

        const hash = hasher.final();
        return InterfaceCID{ .hash = hash };
    }

    /// Hash a single interface element into the BLAKE3 hasher
    fn hashInterfaceElement(self: *InterfaceCIDGenerator, hasher: *Blake3, element: InterfaceElement) !void {
        // Hash the element kind first
        hasher.update(@tagName(element.kind));

        // Hash the signature based on element kind
        switch (element.signature) {
            .public_function => |func_sig| {
                try self.hashFunctionSignature(hasher, func_sig);
            },
            .public_constant => |const_sig| {
                try self.hashConstantSignature(hasher, const_sig);
            },
            .public_type => |type_sig| {
                try self.hashTypeSignature(hasher, type_sig);
            },
            .public_module => |mod_sig| {
                try self.hashModuleSignature(hasher, mod_sig);
            },
            .public_struct_field => |field_sig| {
                try self.hashFieldSignature(hasher, field_sig);
            },
            .public_enum_variant => |variant_sig| {
                try self.hashVariantSignature(hasher, variant_sig);
            },
        }
    }

    /// Hash function signature - only interface parts, not implementation
    fn hashFunctionSignature(self: *InterfaceCIDGenerator, hasher: *Blake3, signature: interface_extractor.FunctionSignature) !void {
        // Hash function name
        const name_str = self.snapshot.str_interner.str(signature.name);
        hasher.update(name_str);

        // Hash export status
        hasher.update(if (signature.is_exported) "exported" else "private");

        // Hash parameters in order
        hasher.update("params:");
        for (signature.parameters) |param| {
            const param_name = self.snapshot.str_interner.str(param.name);
            hasher.update(param_name);
            hasher.update(":");
            try self.hashTypeSignature(hasher, param.type_sig);
            hasher.update(if (param.is_optional) "?" else "");
            hasher.update(";");
        }

        // Hash return type
        hasher.update("returns:");
        try self.hashTypeSignature(hasher, signature.return_type);

        // NOTE: Function implementation is NOT hashed - only the signature
        // This is the critical distinction that enables incremental compilation
    }

    /// Hash constant signature - name and type, not value
    fn hashConstantSignature(self: *InterfaceCIDGenerator, hasher: *Blake3, signature: interface_extractor.ConstantSignature) !void {
        // Hash constant name
        const name_str = self.snapshot.str_interner.str(signature.name);
        hasher.update(name_str);

        // Hash export status
        hasher.update(if (signature.is_exported) "exported" else "private");

        // Hash type signature
        hasher.update("type:");
        try self.hashTypeSignature(hasher, signature.type_sig);

        // NOTE: Constant value is NOT hashed unless it affects type inference
        // This allows implementation changes without interface changes
    }

    /// Hash type signature - structure, not implementation details
    fn hashTypeSignature(self: *InterfaceCIDGenerator, hasher: *Blake3, signature: interface_extractor.TypeSignature) !void {
        // Hash type name
        const name_str = self.snapshot.str_interner.str(signature.name);
        hasher.update(name_str);

        // Hash type kind
        hasher.update(@tagName(signature.kind));

        // Hash export status
        hasher.update(if (signature.is_exported) "exported" else "private");

        // TODO: Hash type-specific details (struct fields, enum variants, etc.)
        // For now, just hash the basic information
    }

    /// Hash module signature - exported symbols only
    fn hashModuleSignature(self: *InterfaceCIDGenerator, hasher: *Blake3, signature: interface_extractor.ModuleSignature) !void {
        // Hash module name
        const name_str = self.snapshot.str_interner.str(signature.name);
        hasher.update(name_str);

        // Hash exported symbols in sorted order
        hasher.update("exports:");

        // Sort exported symbols for deterministic hashing
        const sorted_symbols = try self.allocator.dupe(astdb.StrId, signature.exported_symbols);
        defer self.allocator.free(sorted_symbols);

        std.sort.insertion(astdb.StrId, sorted_symbols, self.snapshot.str_interner, compareStrIds);

        for (sorted_symbols) |symbol_id| {
            const symbol_str = self.snapshot.str_interner.str(symbol_id);
            hasher.update(symbol_str);
            hasher.update(";");
        }
    }

    /// Hash struct field signature
    fn hashFieldSignature(self: *InterfaceCIDGenerator, hasher: *Blake3, signature: interface_extractor.FieldSignature) !void {
        // Hash field name
        const name_str = self.snapshot.str_interner.str(signature.name);
        hasher.update(name_str);

        // Hash visibility
        hasher.update(if (signature.is_public) "public" else "private");

        // Hash field type
        hasher.update("type:");
        try self.hashTypeSignature(hasher, signature.type_sig);
    }

    /// Hash enum variant signature
    fn hashVariantSignature(self: *InterfaceCIDGenerator, hasher: *Blake3, signature: interface_extractor.VariantSignature) !void {
        // Hash variant name
        const name_str = self.snapshot.str_interner.str(signature.name);
        hasher.update(name_str);

        // Hash associated type if present
        if (signature.type_sig) |type_sig| {
            hasher.update("type:");
            try self.hashTypeSignature(hasher, type_sig);
        } else {
            hasher.update("no_type");
        }
    }
};

// Comparison functions for deterministic ordering

fn compareInterfaceElements(context: void, a: InterfaceElement, b: InterfaceElement) bool {
    _ = context;

    // First compare by kind
    const a_kind_order = getInterfaceElementOrder(a.kind);
    const b_kind_order = getInterfaceElementOrder(b.kind);

    if (a_kind_order != b_kind_order) {
        return a_kind_order < b_kind_order;
    }

    // Then compare by declaration ID for stable ordering
    return @intFromEnum(a.decl_id) < @intFromEnum(b.decl_id);
}

fn getInterfaceElementOrder(kind: interface_extractor.InterfaceElementKind) u8 {
    return switch (kind) {
        .public_module => 0,
        .public_type => 1,
        .public_constant => 2,
        .public_function => 3,
        .public_struct_field => 4,
        .public_enum_variant => 5,
    };
}

fn compareInterfaceCIDs(context: void, a: InterfaceCID, b: InterfaceCID) bool {
    _ = context;
    return std.mem.lessThan(u8, &a.hash, &b.hash);
}

fn compareStrIds(interner: *const astdb.interner.StrInterner, a: astdb.StrId, b: astdb.StrId) bool {
    const a_str = interner.str(a);
    const b_str = interner.str(b);
    return std.mem.lessThan(u8, a_str, b_str);
}

// Interface CID Rules - The Critical Distinctions for Hashing
//
// INCLUDED IN INTERFACE CID (changes trigger dependent rebuilds):
// 1. Function signatures (name, parameters, return type, export status)
// 2. Type definitions (name, kind, structure for structs/enums)
// 3. Public constants (name, type, export status)
// 4. Module exports (exported symbol names)
// 5. Public struct fields (name, type, visibility)
// 6. Public enum variants (name, associated types)
// 7. Visibility modifiers (public/private/exported)
//
// EXCLUDED FROM INTERFACE CID (changes do NOT trigger dependent rebuilds):
// 1. Function implementations and method bodies
// 2. Private variables and local state
// 3. Constant values (unless they affect type inference)
// 4. Comments, documentation, and formatting
// 5. Private helper functions and internal methods
// 6. Struct memory layout and field ordering (unless part of ABI)
// 7. Enum value assignments and internal representation
// 8. Implementation algorithms and data structures
// 9. Debug information and metadata
//
// EDGE CASES (require careful consideration):
// 1. Inline functions - signature is interface, inlining hints might affect ABI
// 2. Generic/template instantiations - type parameters affect interface
// 3. Default parameter values - part of interface contract
// 4. Type inference - changes affecting inferred types are interface changes
// 5. Macro expansions - expanded form affects interface
// 6. ABI-affecting attributes - calling conventions, alignment, etc.
//
// DETERMINISTIC ORDERING REQUIREMENTS:
// 1. Interface elements sorted by kind, then by declaration ID
// 2. Function parameters sorted by position (maintain order)
// 3. Struct fields sorted by declaration order (ABI requirement)
// 4. Enum variants sorted by declaration order
// 5. Module exports sorted alphabetically by name
// 6. Dependency CIDs sorted by hash value
//
// This deterministic ordering ensures that identical interfaces always
// produce identical InterfaceCIDs, enabling reliable incremental compilation.
