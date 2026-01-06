// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Interface Extractor - Critical Foundation for Incremental Compilation
// Task 1.1: Define Interface Extraction Rules
//
// This module implements the precise distinction between public interface
// and private implementation - the make-or-b detail of incremental compilation.
//
// DOCTRINE: Get this wrong and we have either:
// 1. Catastrophic incorrectness (missing rebuilds on interface changes)
// 2. Useless inefficiency (rebuilding everything on implementation changes)

const std = @import("std");
const astdb = @import("../astdb.zig");
const Snapshot = astdb.Snapshot;
const NodeId = astdb.NodeId;
const NodeKind = astdb.NodeKind;
const DeclId = astdb.DeclId;
const DeclKind = astdb.DeclKind;
const DeclRow = astdb.snapshot.DeclRow;
const NodeRow = astdb.snapshot.NodeRow;
const StrId = astdb.StrId;

/// Interface Element represents a component of the public interface
/// that affects dependent compilation units when changed
pub const InterfaceElement = struct {
    /// The declaration this element represents
    decl_id: DeclId,

    /// The kind of interface element
    kind: InterfaceElementKind,

    /// The signature or type information that defines the interface
    signature: InterfaceSignature,

    /// Source location for debugging and error reporting
    span: astdb.Span,
};

/// Categories of interface elements that affect dependent compilation
pub const InterfaceElementKind = enum {
    /// Public function declaration (signature only, not implementation)
    public_function,

    /// Public constant declaration (name and type, not value)
    public_constant,

    /// Public type definition (structure, not implementation details)
    public_type,

    /// Exported module interface
    public_module,

    /// Public struct field (for public structs)
    public_struct_field,

    /// Public enum variant (for public enums)
    public_enum_variant,
};

/// Signature information that defines the interface contract
pub const InterfaceSignature = union(InterfaceElementKind) {
    public_function: FunctionSignature,
    public_constant: ConstantSignature,
    public_type: TypeSignature,
    public_module: ModuleSignature,
    public_struct_field: FieldSignature,
    public_enum_variant: VariantSignature,
};

/// Function signature - only the interface, not the implementation
/// Function signature - only the interface, not the implementation
/// Implementation details that do NOT affect interface:
/// - Function body
/// - Local variables
/// - Implementation algorithms
/// - Comments and formatting
pub const FunctionSignature = struct {
    name: StrId,
    parameters: []const ParameterSignature,
    return_type: TypeSignature,
    is_exported: bool,
};

/// Parameter signature for function interfaces
pub const ParameterSignature = struct {
    name: StrId,
    type_sig: TypeSignature,
    is_optional: bool,
};

/// Constant signature - name and type, not value
/// Implementation details that do NOT affect interface:
/// - Constant value (unless it affects type inference)
/// - Initialization expression
pub const ConstantSignature = struct {
    name: StrId,
    type_sig: TypeSignature,
    is_exported: bool,
};

/// Type signature - structure, not implementation
/// For structs: field names and types (not layout or implementation)
/// For enums: variant names and types (not values or representation)
/// For aliases: target type (not implementation details)
pub const TypeSignature = struct {
    name: StrId,
    kind: TypeKind,
    is_exported: bool,
};

pub const TypeKind = enum {
    basic,
    struct_type,
    enum_type,
    function_type,
    pointer_type,
    array_type,
    slice_type,
    optional_type,
    alias_type,
};

/// Module signature - exported interface
pub const ModuleSignature = struct {
    name: StrId,
    exported_symbols: []const StrId,
};

/// Struct field signature
pub const FieldSignature = struct {
    name: StrId,
    type_sig: TypeSignature,
    is_public: bool,
};

/// Enum variant signature
pub const VariantSignature = struct {
    name: StrId,
    type_sig: ?TypeSignature, // Some variants have associated data
};

/// Interface Extractor - extracts public interface elements from ASTDB
pub const InterfaceExtractor = struct {
    allocator: std.mem.Allocator,
    snapshot: *const Snapshot,

    pub fn init(allocator: std.mem.Allocator, snapshot: *const Snapshot) InterfaceExtractor {
        return InterfaceExtractor{
            .allocator = allocator,
            .snapshot = snapshot,
        };
    }

    /// Extract all interface elements from a compilation unit
    /// This is the CRITICAL function that determines interface vs implementation
    pub fn extractInterface(self: *InterfaceExtractor, root_node: NodeId) ![]InterfaceElement {
        var interface_elements = std.ArrayList(InterfaceElement).init(self.allocator);
        defer interface_elements.deinit();

        try self.extractFromNode(root_node, &interface_elements);

        return interface_elements.toOwnedSlice();
    }

    /// Recursively extract interface elements from AST nodes
    fn extractFromNode(self: *InterfaceExtractor, node_id: NodeId, elements: *std.ArrayList(InterfaceElement)) !void {
        const node = self.snapshot.getNode(node_id) orelse return;

        switch (node.kind) {
            .func_decl => try self.extractFunctionInterface(node_id, elements),
            .struct_decl => try self.extractStructInterface(node_id, elements),
            .enum_decl => try self.extractEnumInterface(node_id, elements),
            .var_decl => try self.extractVariableInterface(node_id, elements),
            .module_decl => try self.extractModuleInterface(node_id, elements),

            // Recurse into container nodes
            .program, .block_stmt, .root => {
                const children = node.children(self.snapshot);
                for (children) |child_id| {
                    try self.extractFromNode(child_id, elements);
                }
            },

            // Implementation details - ignore for interface extraction
            .expr_stmt, .assign_stmt, .if_stmt, .while_stmt, .for_stmt, .return_stmt, .break_stmt, .continue_stmt, .binary_op, .unary_op, .call_expr, .index_expr, .field_expr, .int_literal, .float_literal, .string_literal, .bool_literal, .null_literal, .identifier, .qualified_name => {
                // These are implementation details, not interface elements
            },

            else => {
                // For unknown node types, recurse to be safe
                const children = node.children(self.snapshot);
                for (children) |child_id| {
                    try self.extractFromNode(child_id, elements);
                }
            },
        }
    }

    /// Extract function interface (signature only, not implementation)
    fn extractFunctionInterface(self: *InterfaceExtractor, node_id: NodeId, elements: *std.ArrayList(InterfaceElement)) !void {
        // TODO: Query ASTDB for function declaration details
        // For now, create a placeholder implementation

        const decl_id = self.findDeclForNode(node_id) orelse return;
        const decl = self.snapshot.getDecl(decl_id) orelse return;

        // Only extract if this is a public/exported function
        if (!self.isDeclPublic(decl_id)) return;

        const signature = try self.extractFunctionSignature(node_id, decl);
        const span = self.getNodeSpan(node_id);

        try elements.append(InterfaceElement{
            .decl_id = decl_id,
            .kind = .public_function,
            .signature = InterfaceSignature{ .public_function = signature },
            .span = span,
        });
    }

    /// Extract struct interface (fields and methods, not layout)
    fn extractStructInterface(self: *InterfaceExtractor, node_id: NodeId, elements: *std.ArrayList(InterfaceElement)) !void {
        const decl_id = self.findDeclForNode(node_id) orelse return;

        // Only extract if this is a public struct
        if (!self.isDeclPublic(decl_id)) return;

        // Extract struct type signature
        const type_sig = try self.extractTypeSignature(node_id);
        const span = self.getNodeSpan(node_id);

        try elements.append(InterfaceElement{
            .decl_id = decl_id,
            .kind = .public_type,
            .signature = InterfaceSignature{ .public_type = type_sig },
            .span = span,
        });

        // Extract public fields
        try self.extractStructFields(node_id, elements);
    }

    /// Extract enum interface (variants, not representation)
    fn extractEnumInterface(self: *InterfaceExtractor, node_id: NodeId, elements: *std.ArrayList(InterfaceElement)) !void {
        const decl_id = self.findDeclForNode(node_id) orelse return;

        // Only extract if this is a public enum
        if (!self.isDeclPublic(decl_id)) return;

        // Extract enum type signature
        const type_sig = try self.extractTypeSignature(node_id);
        const span = self.getNodeSpan(node_id);

        try elements.append(InterfaceElement{
            .decl_id = decl_id,
            .kind = .public_type,
            .signature = InterfaceSignature{ .public_type = type_sig },
            .span = span,
        });

        // Extract enum variants
        try self.extractEnumVariants(node_id, elements);
    }

    /// Extract variable interface (constants only, not regular variables)
    fn extractVariableInterface(self: *InterfaceExtractor, node_id: NodeId, elements: *std.ArrayList(InterfaceElement)) !void {
        const decl_id = self.findDeclForNode(node_id) orelse return;
        const decl = self.snapshot.getDecl(decl_id) orelse return;

        // Only extract public constants, not regular variables
        if (decl.kind != .constant) return;
        if (!self.isDeclPublic(decl_id)) return;

        const signature = try self.extractConstantSignature(node_id, decl);
        const span = self.getNodeSpan(node_id);

        try elements.append(InterfaceElement{
            .decl_id = decl_id,
            .kind = .public_constant,
            .signature = InterfaceSignature{ .public_constant = signature },
            .span = span,
        });
    }

    /// Extract module interface (exported symbols)
    fn extractModuleInterface(self: *InterfaceExtractor, node_id: NodeId, elements: *std.ArrayList(InterfaceElement)) !void {
        const decl_id = self.findDeclForNode(node_id) orelse return;

        const signature = try self.extractModuleSignature(node_id);
        const span = self.getNodeSpan(node_id);

        try elements.append(InterfaceElement{
            .decl_id = decl_id,
            .kind = .public_module,
            .signature = InterfaceSignature{ .public_module = signature },
            .span = span,
        });
    }

    // Helper functions for signature extraction

    fn extractFunctionSignature(self: *InterfaceExtractor, _: NodeId, decl: DeclRow) !FunctionSignature {
        // TODO: Implement actual signature extraction from ASTDB
        // For now, return a placeholder
        return FunctionSignature{
            .name = decl.name,
            .parameters = &[_]ParameterSignature{}, // TODO: Extract parameters
            .return_type = TypeSignature{
                .name = try self.snapshot.str_interner.get("void"), // TODO: Extract actual return type
                .kind = .basic,
                .is_exported = false,
            },
            .is_exported = true, // TODO: Determine export status properly
        };
    }

    fn extractConstantSignature(self: *InterfaceExtractor, node_id: NodeId, decl: DeclRow) !ConstantSignature {
        return ConstantSignature{
            .name = decl.name,
            .type_sig = try self.extractTypeSignature(node_id),
            .is_exported = self.isDeclPublic(decl.node),
        };
    }

    fn extractTypeSignature(self: *InterfaceExtractor, node_id: NodeId) !TypeSignature {
        const node = self.snapshot.getNode(node_id) orelse return error.InvalidNode;

        // TODO: Implement proper type signature extraction
        return TypeSignature{
            .name = try self.snapshot.str_interner.get("unknown"), // TODO: Extract actual type name
            .kind = switch (node.kind) {
                .struct_decl => .struct_type,
                .enum_decl => .enum_type,
                .func_decl => .function_type,
                else => .basic,
            },
            .is_exported = false, // TODO: Determine export status
        };
    }

    fn extractModuleSignature(self: *InterfaceExtractor, _: NodeId) !ModuleSignature {
        // TODO: Extract exported symbols from module
        return ModuleSignature{
            .name = try self.snapshot.str_interner.get("module"), // TODO: Extract actual module name
            .exported_symbols = &[_]StrId{}, // TODO: Extract exported symbols
        };
    }

    fn extractStructFields(_: *InterfaceExtractor, struct_node: NodeId, elements: *std.ArrayList(InterfaceElement)) !void {
        // TODO: Extract public struct fields
        _ = struct_node;
        _ = elements;
    }

    fn extractEnumVariants(_: *InterfaceExtractor, enum_node: NodeId, elements: *std.ArrayList(InterfaceElement)) !void {
        // TODO: Extract enum variants
        _ = enum_node;
        _ = elements;
    }

    // Helper functions for ASTDB queries

    fn findDeclForNode(self: *InterfaceExtractor, node_id: NodeId) ?DeclId {
        // Search through all declarations to find one associated with this node
        const decl_count = self.snapshot.declCount();
        var i: u32 = 0;
        while (i < decl_count) : (i += 1) {
            const decl_id: DeclId = @enumFromInt(i);
            if (self.snapshot.getDecl(decl_id)) |decl| {
                if (std.meta.eql(decl.node, node_id)) {
                    return decl_id;
                }
            }
        }
        return null;
    }

    fn isDeclPublic(self: *InterfaceExtractor, decl_id: DeclId) bool {
        // For now, determine publicity based on declaration kind
        // TODO: Implement proper visibility analysis based on language semantics
        const decl = self.snapshot.getDecl(decl_id) orelse return false;

        switch (decl.kind) {
            .function, .constant, .type_alias => {
                // Functions, constants, and type aliases are public by default
                // TODO: Check for explicit visibility modifiers
                return true;
            },
            .struct_field, .enum_variant => {
                // Fields and variants inherit visibility from their parent
                // TODO: Implement proper parent visibility checking
                return true;
            },
            .variable, .parameter => {
                // Variables and parameters are typically private
                return false;
            },
            .import, .module => {
                // Imports and modules have special visibility rules
                return true;
            },
        }
    }

    fn getNodeSpan(self: *InterfaceExtractor, node_id: NodeId) astdb.Span {
        const node = self.snapshot.getNode(node_id) orelse return astdb.Span{
            .start_byte = 0,
            .end_byte = 0,
            .start_line = 0,
            .start_col = 0,
            .end_line = 0,
            .end_col = 0,
        };

        // Get span from the first token of the node
        if (self.snapshot.getToken(node.first_token)) |token| {
            return token.span;
        }

        return astdb.Span{
            .start_byte = 0,
            .end_byte = 0,
            .start_line = 0,
            .start_col = 0,
            .end_line = 0,
            .end_col = 0,
        };
    }
};

// Interface Extraction Rules - The Critical Distinctions
//
// PUBLIC INTERFACE (affects dependent compilation):
// 1. Function signatures (name, parameters, return type) - NOT implementation
// 2. Public type definitions (struct/enum structure) - NOT layout or values
// 3. Public constants (name and type) - NOT value unless it affects types
// 4. Exported module symbols - NOT internal implementation
// 5. Public struct fields (name and type) - NOT private fields or methods
// 6. Public enum variants (name and associated types) - NOT representation
//
// PRIVATE IMPLEMENTATION (does NOT affect dependent compilation):
// 1. Function bodies and implementation logic
// 2. Private variables and local state
// 3. Internal algorithms and data structures
// 4. Comments, formatting, and documentation
// 5. Private helper functions and methods
// 6. Struct layout and memory representation
// 7. Enum value assignments and internal representation
// 8. Constant values (unless they affect type inference)
//
// EDGE CASES (require careful consideration):
// 1. Inline functions - signature is interface, body might affect optimization
// 2. Template/generic instantiations - signature affects interface
// 3. Macro expansions - expanded form affects interface
// 4. Type inference - changes that affect inferred types are interface changes
// 5. Default parameter values - part of interface contract
// 6. Function overloading - all overloads are part of interface
