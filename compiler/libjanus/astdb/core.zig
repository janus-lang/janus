// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Minimal ASTDB core types for libjanus compatibility
// These are simplified versions of the types in ../../astdb/core.zig

// Core ID types
pub const NodeId = enum(u32) { _ };
pub const TokenId = enum(u32) { _ };
pub const DeclId = enum(u32) { _ };
pub const ScopeId = enum(u32) { _ };
pub const UnitId = enum(u32) { _ };
pub const StrId = enum(u32) { _ };

// NodeKind enum (must be at top level for compatibility)
pub const NodeKind = enum {
    // Top-level items
    source_file,
    func_decl,
    async_func_decl, // :service profile - async function
    struct_decl,
    union_decl,
    enum_decl,
    trait_decl,
    impl_decl,
    using_decl,
    use_stmt,
    error_decl, // error set definition

    // Statements
    expr_stmt,
    let_stmt,
    var_stmt,
    const_stmt,
    if_stmt,
    while_stmt,
    for_stmt,
    return_stmt,
    defer_stmt,
    break_stmt,
    continue_stmt,
    block_stmt,
    fail_stmt, // fail ErrorType.Variant
    nursery_stmt, // :service profile - nursery { spawn tasks }
    using_resource_stmt, // :service profile - using resource = open() do ... end
    using_shared_stmt, // :service profile - using shared resource = open() do ... end

    // Expressions
    binary_expr,
    unary_expr,
    call_expr,
    index_expr,
    field_expr,
    cast_expr,
    paren_expr,
    catch_expr, // expr catch err { block }
    try_expr, // expr? (error propagation)
    await_expr, // :service profile - await async_expr
    spawn_expr, // :service profile - spawn task()

    // Literals
    integer_literal,
    float_literal,
    string_literal,
    char_literal,
    bool_literal,
    null_literal,
    array_lit,
    array_literal,
    struct_literal,

    // Types
    primitive_type,
    pointer_type,
    array_type,
    slice_type,
    function_type,
    named_type,
    error_union_type, // T ! E
    dyn_trait_ref, // &dyn Trait — fat pointer trait object

    // Patterns
    identifier_pattern,
    wildcard_pattern,
    literal_pattern,
    struct_pattern,

    // Misc
    identifier,
    parameter,
    field,
    variant,
    type_param,
};

// Source location information
pub const SourceSpan = struct {
    start: u32,
    end: u32,
    line: u32,
    column: u32,
};
pub const Span = SourceSpan; // Alias for compatibility

// AST Node representation
pub const AstNode = struct {
    kind: NodeKind,
    first_token: TokenId,
    last_token: TokenId,
    child_lo: u32,
    child_hi: u32,
};

// Snapshot for querying ASTDB
pub const Snapshot = struct {
    // Minimal implementation for compatibility
    pub fn nodeCount(self: *const Snapshot) u32 {
        _ = self;
        return 0;
    }

    pub fn getNode(self: *const Snapshot, node_id: NodeId) ?*const AstNode {
        _ = self;
        _ = node_id;
        return null;
    }
};
