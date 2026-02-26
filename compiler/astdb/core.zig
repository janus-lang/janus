// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const interners = @import("intern.zig");
const cid = @import("cid.zig");
const doc_types_mod = @import("doc_types.zig");

// Re-export common types to avoid module conflicts
pub const StrId = interners.StrId;
pub const TypeId = interners.TypeId;
pub const SymId = interners.SymId;
pub const StrInterner = interners.StrInterner;

// Additional strongly typed IDs for ASTDB
pub const NodeId = enum(u32) { _ };
pub const TokenId = enum(u32) { _ };
pub const ScopeId = enum(u32) { _ };
pub const DeclId = enum(u32) { _ };
pub const RefId = enum(u32) { _ };
pub const DiagId = enum(u32) { _ };
pub const UnitId = enum(u32) { _ };

// Invalid ID constants for initialization
pub const INVALID_SCOPE_ID: ScopeId = @enumFromInt(0xFFFFFFFF);

/// Source location information
pub const SourceSpan = struct {
    start: u32,
    end: u32,
    line: u32,
    column: u32,
};

/// Token representation with trivia
pub const Token = struct {
    kind: TokenKind,
    str: ?StrId, // null for punctuation/keywords
    span: SourceSpan,
    trivia_lo: u32, // index into trivia array
    trivia_hi: u32, // exclusive end

    pub const TokenKind = enum {
        // Literals
        integer_literal,
        float_literal,
        string_literal,
        char_literal,
        bool_literal,
        null_literal,

        // Identifiers and Symbols
        identifier,
        symbol, // :atom for :elixir profile

        // Keywords - :min profile (18 total)
        func,
        let,
        var_,
        if_,
        else_,
        for_,
        while_,
        defer_,
        match,
        when,
        unless,
        return_,
        break_,
        continue_,
        do_,
        end,
        test_, // PROBATIO: Integrated verification

        // Keywords - :go profile additions
        package,
        const_,
        nil_,
        switch_,
        case,
        default_,
        go_,
        where,

        // Keywords - :elixir profile additions
        actor,
        spawn,

        // Keywords - :full profile additions
        cap,
        with,
        using,
        comptime_,
        yield_,
        pub_,

        // Keywords - :sovereign profile additions
        requires,
        ensures,
        invariant,
        ghost, // for ghost code state

        // Keywords - :core profile additions (error handling)
        error_,   // error ErrorType { Variant } - error type declaration
        fail_,    // fail ErrorType.Variant
        catch_,   // expr catch err { ... }

        // Keywords - :service profile additions (async/await)
        async_,   // async func - asynchronous functions
        await_,   // await expr - wait for async result
        nursery_, // nursery { } - structured concurrency scope
        spawn_,   // spawn task - launch concurrent task
        shared_,  // using shared resource - shared resource management
        select_,  // select { } - CSP multi-channel wait
        timeout_, // timeout(duration) - select timeout case

        // Additional keywords from syntax spec
        type_,
        enum_,
        flags,
        struct_,
        struct_kw,
        union_,
        trait,
        impl,
        dyn_,
        export_,
        import_,
        as_,
        use_,
        extern_,
        zig_,
        graft,
        in_,
        and_,
        or_,
        not_,
        true_,
        false_,
        null_,

        // Arithmetic Operators
        plus, // +
        minus, // -
        star, // *
        star_star, // ** (power)
        slash, // /
        percent, // %

        // Comparison Operators
        equal_equal, // ==
        not_equal, // !=
        less, // <
        less_equal, // <=
        greater, // >
        greater_equal, // >=

        // Logical Operators
        logical_and, // and, &&
        logical_or, // or, ||
        logical_not, // not, !

        // Bitwise Operators
        bitwise_and, // &
        bitwise_or, // |
        bitwise_xor, // ^
        bitwise_not, // ~
        left_shift, // <<
        right_shift, // >>

        // Assignment Operators
        assign, // =
        equal, // = (for compatibility with existing code)
        walrus_assign, // :=
        colon_equal, // := (alias for walrus_assign for :service profile)
        plus_assign, // +=
        minus_assign, // -=
        star_assign, // *=
        slash_assign, // /=
        percent_assign, // %=
        ampersand_assign, // &=
        pipe_assign, // |=
        xor_assign, // ^=
        left_shift_assign, // <<=
        right_shift_assign, // >>=

        // Advanced Operators (:full profile)
        pipeline, // |>
        placeholder, // __
        optional_chain, // ?.
        null_coalesce, // ??
        range_inclusive, // ..
        range_exclusive, // ..<

        // Punctuation
        left_paren, // (
        right_paren, // )
        left_brace, // {
        right_brace, // }
        left_bracket, // [
        right_bracket, // ]
        semicolon, // ;
        comma, // ,
        dot, // .
        colon, // :
        double_colon, // ::
        arrow, // ->
        arrow_fat, // =>
        question, // ?
        exclamation, // !
        at_sign, // @
        hash, // #
        dollar, // $
        ampersand, // &
        pipe, // |
        caret, // ^
        tilde, // ~
        backtick, // `

        // String interpolation and special literals
        string_interp_start, // $"
        string_interp_mid, // middle part of interpolation
        string_interp_end, // end of interpolation
        byte_string, // b"..."
        regex_string, // re"..."

        // Comments and Documentation
        line_comment, // //
        block_comment, // /* */
        doc_comment, // ///

        // Special
        newline,
        whitespace,
        eof,
        invalid,
    };
};

/// Trivia (whitespace, comments)
pub const Trivia = struct {
    kind: TriviaKind,
    span: SourceSpan,

    pub const TriviaKind = enum {
        whitespace,
        line_comment,
        block_comment,
        doc_comment,
    };
};

/// AST Node representation
pub const AstNode = struct {
    kind: NodeKind,
    first_token: TokenId,
    last_token: TokenId,
    child_lo: u32, // index into edges array
    child_hi: u32, // exclusive end

    pub const NodeKind = enum {
        // Top-level items
        source_file,
        func_decl,
        async_func_decl, // :service profile - async function
        extern_func, // External function declaration (no body)
        struct_decl,
        union_decl,
        enum_decl,
        error_decl, // Error type declaration (:core profile)
        trait_decl,
        impl_decl,
        using_decl,
        use_stmt,
        use_selective, // use module.{item1, item2} selective imports
        use_zig, // use zig "path.zig" - native Zig module import
        import_stmt,
        test_decl, // PROBATIO: Integrated verification

        // Contracts (High-Assurance)
        requires_clause,
        ensures_clause,
        invariant_clause,

        // Statements
        expr_stmt,
        let_stmt,
        var_stmt,
        const_stmt,
        if_stmt,
        while_stmt,
        defer_stmt,
        for_stmt,
        return_stmt,
        break_stmt,
        continue_stmt,
        block_stmt,
        fail_stmt, // Error handling: fail ErrorType.Variant (:core profile)
        nursery_stmt, // :service profile - nursery { spawn tasks }
        using_resource_stmt, // :service profile - using resource = open() do ... end
        using_shared_stmt, // :service profile - using shared resource = open() do ... end
        select_stmt,  // :service profile - select { case ch.recv() ... }
        select_case,  // :service profile - case in select (recv/send)
        select_timeout, // :service profile - timeout case in select
        select_default, // :service profile - default case in select
        match_stmt,
        match_arm,
        postfix_when,
        postfix_unless,

        // Expressions
        binary_expr,
        unary_expr,
        call_expr,
        index_expr,
        slice_inclusive_expr, // Slice: arr[start..end] (inclusive)
        slice_exclusive_expr, // Slice: arr[start..<end] (exclusive)
        field_expr,
        cast_expr,
        paren_expr,
        range_inclusive_expr, // Range: start..end (inclusive)
        range_exclusive_expr, // Range: start..<end (exclusive)
        catch_expr, // Error handling: expr catch err { ... } (:core profile)
        try_expr, // Error handling: expr? (:core profile)
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
        optional_type,
        error_union_type, // Error handling: T ! E (:core profile)
        function_type,
        named_type,
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

    pub fn children(self: AstNode, snapshot: *const Snapshot) []const NodeId {
        // This is a compatibility method for legacy code
        // We need to find which node_id this AstNode corresponds to
        // For now, we'll search through the first unit to find this node
        if (snapshot.astdb.units.items.len > 0) {
            const unit = snapshot.astdb.units.items[0];
            for (unit.nodes, 0..) |node, i| {
                // FIX: Compare node content instead of pointers
                if (std.meta.eql(node, self)) {
                    const node_id: NodeId = @enumFromInt(i);
                    return snapshot.getChildren(node_id);
                }
            }
        }
        return &.{};
    }
};

/// Scope information for symbol resolution
pub const Scope = struct {
    parent: ?ScopeId,
    first_decl: ?DeclId,
    kind: ScopeKind,

    pub const ScopeKind = enum {
        global,
        function,
        block,
        struct_,
        struct_kw,
        union_,
        enum_,
        trait,
        impl,
    };
};

/// Declaration information
pub const Decl = struct {
    node: NodeId,
    name: StrId,
    scope: ScopeId,
    kind: DeclKind,
    next_in_scope: ?DeclId, // linked list within scope

    pub const DeclKind = enum {
        function,
        variable,
        constant,
        parameter,
        type_def,
        field,
        variant,
    };
};

/// Reference information for LSP features
pub const Ref = struct {
    at_node: NodeId,
    name: StrId,
    decl: ?DeclId, // null if unresolved
    kind: RefKind,

    pub const RefKind = enum {
        read,
        write,
        call,
        type_ref,
    };
};

/// Diagnostic information
pub const Diagnostic = struct {
    code: DiagCode,
    severity: Severity,
    span: SourceSpan,
    message: StrId,
    fix: ?FixIt,

    pub const DiagCode = enum(u32) {
        // Parser errors (P0000-P9999)
        P0001, // unexpected token
        P0002, // missing semicolon
        P0003, // unmatched delimiter

        // ^ errors (S0000-S9999)
        S0001, // undefined symbol
        S0002, // type mismatch
        S0003, // duplicate declaration

        // IR errors (I0000-I9999)
        I0001, // codegen failure

        // Daemon errors (D0000-D9999)
        D0001, // RPC error

        // Profile gate errors
        E2001, // :min profile violation
        E2501, // :go profile violation
        E2601, // :elixir profile violation
        E3001, // :full profile violation

        _,
    };

    pub const Severity = enum {
        err,
        warning,
        info,
        hint,
    };

    pub const FixIt = struct {
        description: StrId,
        edits: []TextEdit,

        pub const TextEdit = struct {
            span: SourceSpan,
            new_text: StrId,
        };
    };
};

/// Compilation unit with dedicated arena
pub const CompilationUnit = struct {
    id: UnitId,
    path: []const u8,
    source: []const u8,
    arena: std.heap.ArenaAllocator, // Unit-specific arena for unit data
    is_removed: bool,

    // Unit-specific data (allocated in unit's arena)
    tokens: []Token,
    trivia: []Trivia,
    nodes: []AstNode,
    edges: []NodeId,
    scopes: []Scope,
    decls: []Decl,
    refs: []Ref,
    diags: []Diagnostic,
    cids: [][32]u8,

    // RFC-025: 10th columnar array — structured documentation
    docs: doc_types_mod.DocStore,

    // Span indexing for this unit
    token_spans: SpanIndex(TokenId),
    node_spans: SpanIndex(NodeId),

    pub fn init(alloc: std.mem.Allocator, id: UnitId, unit_path: []const u8, src: []const u8) !*CompilationUnit {
        const unit = try alloc.create(CompilationUnit);
        unit.* = CompilationUnit{
            .id = id,
            .path = try alloc.dupe(u8, unit_path),
            .source = try alloc.dupe(u8, src),
            .arena = std.heap.ArenaAllocator.init(alloc), // Unit-specific arena backed by sovereign allocator
            .is_removed = false,
            .tokens = &.{},
            .trivia = &.{},
            .nodes = &.{},
            .edges = &.{},
            .scopes = &.{},
            .decls = &.{},
            .refs = &.{},
            .diags = &.{},
            .cids = &.{},
            .docs = doc_types_mod.DocStore.init(alloc),
            .token_spans = SpanIndex(TokenId).init(alloc),
            .node_spans = SpanIndex(NodeId).init(alloc),
        };
        return unit;
    }

    pub fn deinit(self: *CompilationUnit, alloc: std.mem.Allocator) void {
        self.node_spans.deinit();
        self.token_spans.deinit();
        self.docs.deinit();
        self.arena.deinit(); // O(1) cleanup of all unit-specific data
        alloc.free(self.path);
        alloc.free(self.source);
        alloc.destroy(self);
    }

    /// Get arena allocator for this unit
    pub fn arenaAllocator(self: *CompilationUnit) std.mem.Allocator {
        return self.arena.allocator();
    }
};

/// Snapshot of ASTDB state for querying
pub const Snapshot = struct {
    astdb: *AstDB,

    pub fn deinit(self: *Snapshot) void {
        // For now, snapshots don't own resources
        _ = self;
    }

    pub fn nodeCount(self: *const Snapshot) u32 {
        var total: u32 = 0;
        for (self.astdb.units.items) |unit| {
            if (!unit.is_removed) {
                total += @intCast(unit.nodes.len);
            }
        }
        return total;
    }

    pub fn tokenCount(self: *const Snapshot) u32 {
        var total: u32 = 0;
        for (self.astdb.units.items) |unit| {
            if (!unit.is_removed) {
                total += @intCast(unit.tokens.len);
            }
        }
        return total;
    }

    pub fn declCount(self: *const Snapshot) u32 {
        var total: u32 = 0;
        for (self.astdb.units.items) |unit| {
            if (!unit.is_removed) {
                total += @intCast(unit.decls.len);
            }
        }
        return total;
    }

    pub fn getDecl(self: *const Snapshot, unit_id: UnitId, decl_id: DeclId) ?*const Decl {
        const unit_index = @intFromEnum(unit_id);
        if (unit_index >= self.astdb.units.items.len) return null;

        const unit = self.astdb.units.items[unit_index];
        if (unit.is_removed) return null;

        const decl_index = @intFromEnum(decl_id);
        if (decl_index >= unit.decls.len) return null;

        return &unit.decls[decl_index];
    }

    // Compatibility method for legacy call sites - assumes first unit
    pub fn getDeclCompat(self: *const Snapshot, decl_id: DeclId) ?*const Decl {
        if (self.astdb.units.items.len == 0) return null;
        const first_unit_id: UnitId = @enumFromInt(0);
        return self.getDecl(first_unit_id, decl_id);
    }

    pub fn getToken(self: *const Snapshot, token_id: TokenId) ?*const Token {
        // For now, assume token_id corresponds to first unit's tokens
        if (self.astdb.units.items.len > 0) {
            const unit = self.astdb.units.items[0];
            const index = @intFromEnum(token_id);
            if (index < unit.tokens.len) {
                return &unit.tokens[index];
            }
        }
        return null;
    }

    pub fn getNodeScope(self: *const Snapshot, node_id: NodeId) ?ScopeId {
        // For now, assume node_id corresponds to first unit's nodes
        if (self.astdb.units.items.len > 0) {
            const unit = self.astdb.units.items[0];
            const index = @intFromEnum(node_id);
            if (index < unit.nodes.len) {
                // For now, return a default scope - this is a stub implementation
                return @enumFromInt(0);
            }
        }
        return null;
    }

    pub fn getScope(self: *const Snapshot, scope_id: ScopeId) ?*const Scope {
        // For now, assume scope_id corresponds to first unit's scopes
        if (self.astdb.units.items.len > 0) {
            const unit = self.astdb.units.items[0];
            const index = @intFromEnum(scope_id);
            if (index < unit.scopes.len) {
                return &unit.scopes[index];
            }
        }
        return null;
    }

    pub fn refCount(self: *const Snapshot) u32 {
        var total: u32 = 0;
        for (self.astdb.units.items) |unit| {
            if (!unit.is_removed) {
                total += @intCast(unit.refs.len);
            }
        }
        return total;
    }

    pub fn getRef(self: *const Snapshot, ref_id: RefId) ?*const Ref {
        // For now, assume ref_id corresponds to first unit's refs
        if (self.astdb.units.items.len > 0) {
            const unit = self.astdb.units.items[0];
            const index = @intFromEnum(ref_id);
            if (index < unit.refs.len) {
                return &unit.refs[index];
            }
        }
        return null;
    }

    pub fn getNode(self: *const Snapshot, node_id: NodeId) ?*const AstNode {
        // For now, assume node_id corresponds to first unit's nodes
        if (self.astdb.units.items.len > 0) {
            const unit = self.astdb.units.items[0];
            const index = @intFromEnum(node_id);
            if (index < unit.nodes.len) {
                return &unit.nodes[index];
            }
        }
        return null;
    }

    pub fn getChildren(self: *const Snapshot, node_id: NodeId) []const NodeId {
        // For now, assume node_id corresponds to first unit's nodes
        if (self.astdb.units.items.len > 0) {
            const unit = self.astdb.units.items[0];
            const index = @intFromEnum(node_id);
            if (index < unit.nodes.len) {
                const node = &unit.nodes[index];
                // Bounds check: child_lo/child_hi must be valid edge indices
                if (node.child_lo <= node.child_hi and node.child_hi <= unit.edges.len) {
                    return unit.edges[node.child_lo..node.child_hi];
                }
            }
        }
        return &.{};
    }
};

/// Immutable snapshot of AST database with per-unit arenas
pub const AstDB = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    units: std.ArrayList(*CompilationUnit),
    unit_map: std.HashMap([]const u8, UnitId, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    next_unit_id: u32,

    // Global interners for content addressing
    str_interner: interners.StrInterner,
    type_interner: interners.TypeInterner,
    sym_interner: interners.SymInterner,

    pub fn init(allocator: std.mem.Allocator, deterministic: bool) !Self {
        return Self.initWithMode(allocator, deterministic);
    }

    pub fn initWithMode(allocator: std.mem.Allocator, deterministic: bool) Self {
        return Self{
            .allocator = allocator,
            .units = .empty,
            .unit_map = std.HashMap([]const u8, UnitId, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .next_unit_id = 0,
            .str_interner = interners.StrInterner.initWithMode(allocator, deterministic),
            .type_interner = interners.TypeInterner.init(allocator),
            .sym_interner = interners.SymInterner.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up all units (O(1) per unit via arena)
        for (self.units.items) |unit| {
            unit.deinit(self.allocator);
        }
        self.units.deinit(self.allocator);
        self.unit_map.deinit();

        // Clean up global interners
        self.str_interner.deinit();
        self.type_interner.deinit();
        self.sym_interner.deinit();
    }

    /// Create a snapshot for querying
    pub fn createSnapshot(self: *Self) !Snapshot {
        return Snapshot{
            .astdb = self,
        };
    }

    /// Add a compilation unit with dedicated arena
    pub fn addUnit(self: *Self, unit_path: []const u8, src: []const u8) !UnitId {
        const unit_id = @as(UnitId, @enumFromInt(self.next_unit_id));
        self.next_unit_id += 1;

        const unit = try CompilationUnit.init(self.allocator, unit_id, unit_path, src);
        try self.units.append(self.allocator, unit);
        try self.unit_map.put(unit.path, unit_id);

        return unit_id;
    }

    /// Remove a compilation unit and free its arena
    pub fn removeUnit(self: *Self, unit_id: UnitId) !void {
        const index = @intFromEnum(unit_id);
        if (index >= self.units.items.len) return error.InvalidUnitId;

        const unit = self.units.items[index];
        if (unit.is_removed) return error.InvalidUnitId;

        // Remove from map
        _ = self.unit_map.remove(unit.path);

        // Mark as removed (cleanup happens in main deinit)
        unit.is_removed = true;
    }

    /// Get compilation unit by ID
    pub fn getUnit(self: *Self, unit_id: UnitId) ?*CompilationUnit {
        const index = @intFromEnum(unit_id);
        if (index >= self.units.items.len) return null;
        const unit = self.units.items[index];
        if (unit.is_removed) return null;
        return unit;
    }

    /// Get compilation unit by ID (const)
    pub fn getUnitConst(self: *const Self, unit_id: UnitId) ?*const CompilationUnit {
        const index = @intFromEnum(unit_id);
        if (index >= self.units.items.len) return null;
        const unit = self.units.items[index];
        if (unit.is_removed) return null;
        return unit;
    }

    /// Get compilation unit by path
    pub fn getUnitByPath(self: *Self, path: []const u8) ?*CompilationUnit {
        const unit_id = self.unit_map.get(path) orelse return null;
        return self.getUnit(unit_id);
    }

    /// Get children of a node within a unit
    pub fn getChildren(self: *const Self, unit_id: UnitId, node_id: NodeId) []const NodeId {
        const unit = self.getUnitConst(unit_id) orelse return &.{};
        const node = self.getNode(unit_id, node_id) orelse return &.{};
        return unit.edges[node.child_lo..node.child_hi];
    }

    /// Get node by ID within a unit
    pub fn getNode(self: *const Self, unit_id: UnitId, node_id: NodeId) ?*const AstNode {
        const unit = self.getUnitConst(unit_id) orelse return null;
        const index = @intFromEnum(node_id);
        if (index >= unit.nodes.len) return null;
        return &unit.nodes[index];
    }

    /// Get token by ID within a unit
    pub fn getToken(self: *Self, unit_id: UnitId, token_id: TokenId) ?*const Token {
        const unit = self.getUnit(unit_id) orelse return null;
        const index = @intFromEnum(token_id);
        if (index >= unit.tokens.len) return null;
        return &unit.tokens[index];
    }

    /// Get scope by ID within a unit
    pub fn getScope(self: *Self, unit_id: UnitId, scope_id: ScopeId) ?*const Scope {
        const unit = self.getUnit(unit_id) orelse return null;
        const index = @intFromEnum(scope_id);
        if (index >= unit.scopes.len) return null;
        return &unit.scopes[index];
    }

    /// Get declaration by ID within a unit
    pub fn getDecl(self: *Self, unit_id: UnitId, decl_id: DeclId) ?*const Decl {
        const unit = self.getUnit(unit_id) orelse return null;
        const index = @intFromEnum(decl_id);
        if (index >= unit.decls.len) return null;
        return &unit.decls[index];
    }

    /// Get reference by ID within a unit
    pub fn getRef(self: *Self, unit_id: UnitId, ref_id: RefId) ?*const Ref {
        const unit = self.getUnit(unit_id) orelse return null;
        const index = @intFromEnum(ref_id);
        if (index >= unit.refs.len) return null;
        return &unit.refs[index];
    }

    /// Get diagnostic by ID within a unit
    pub fn getDiag(self: *Self, unit_id: UnitId, diag_id: DiagId) ?*const Diagnostic {
        const unit = self.getUnit(unit_id) orelse return null;
        const index = @intFromEnum(diag_id);
        if (index >= unit.diags.len) return null;
        return &unit.diags[index];
    }

    /// Get content ID for node within a unit
    pub fn getCID(self: *Self, unit_id: UnitId, node_id: NodeId) ?[32]u8 {
        const unit = self.getUnit(unit_id) orelse return null;
        const index = @intFromEnum(node_id);
        if (index >= unit.cids.len) return null;
        return unit.cids[index];
    }

    /// Find token at byte position within a unit
    pub fn tokenAt(self: *Self, unit_id: UnitId, pos: u32) ?TokenId {
        const unit = self.getUnit(unit_id) orelse return null;
        return unit.token_spans.findAt(pos);
    }

    /// Find node at byte position within a unit
    pub fn nodeAt(self: *Self, unit_id: UnitId, pos: u32) ?NodeId {
        const unit = self.getUnit(unit_id) orelse return null;
        return unit.node_spans.findAt(pos);
    }

    /// Get all declarations in a scope within a unit
    pub fn getDeclsInScope(self: *Self, unit_id: UnitId, scope_id: ScopeId, allocator: std.mem.Allocator) ![]DeclId {
        var decls: std.ArrayList(DeclId) = .empty;

        const scope = self.getScope(unit_id, scope_id) orelse return decls.toOwnedSlice(allocator);
        var current_decl = scope.first_decl;

        while (current_decl) |decl_id| {
            try decls.append(allocator, decl_id);
            const decl = self.getDecl(unit_id, decl_id) orelse break;
            current_decl = decl.next_in_scope;
        }

        return decls.toOwnedSlice(allocator);
    }

    /// Get all references to a declaration within a unit
    pub fn getRefsToDecl(self: *Self, unit_id: UnitId, target_decl: DeclId, allocator: std.mem.Allocator) ![]RefId {
        var refs: std.ArrayList(RefId) = .empty;

        const unit = self.getUnit(unit_id) orelse return refs.toOwnedSlice(allocator);
        for (unit.refs, 0..) |ref, i| {
            if (ref.decl == target_decl) {
                try refs.append(allocator, RefId(@intCast(i)));
            }
        }

        return refs.toOwnedSlice(allocator);
    }

    /// Intern a string, returning stable SID. Thread-safe.
    pub fn internString(self: *Self, bytes: []const u8) !StrId {
        return self.str_interner.intern(bytes);
    }

    /// Get string by SID
    pub fn getString(self: *Self, sid: StrId) []const u8 {
        return self.str_interner.getString(sid);
    }

    /// Get string by SID (nullable version)
    pub fn getStringOpt(self: *Self, sid: StrId) ?[]const u8 {
        return self.str_interner.get(sid);
    }

    /// Intern a type, returning stable TypeId. Thread-safe.
    pub fn internType(self: *Self, type_data: interners.TypeInterner.Type) !TypeId {
        return self.type_interner.intern(type_data);
    }

    /// Get type by TypeId
    pub fn getType(self: *Self, type_id: TypeId) *const interners.TypeInterner.Type {
        return self.type_interner.getType(type_id);
    }

    /// Intern a symbol, returning stable SymId. Thread-safe.
    pub fn internSymbol(self: *Self, symbol: interners.SymInterner.Symbol) !SymId {
        return self.sym_interner.intern(symbol);
    }

    /// Get symbol by SymId
    pub fn getSymbol(self: *Self, sym_id: SymId) ?*const interners.SymInterner.Symbol {
        return self.sym_interner.get(sym_id);
    }

    /// Compute content ID for a scope
    pub fn computeCID(self: *Self, scope: cid.CidScope, allocator: std.mem.Allocator) ![32]u8 {
        var encoder = cid.SemanticEncoder.init(allocator, self, self.str_interner.deterministic);
        defer encoder.deinit();
        return encoder.computeCID(scope);
    }
};

/// Span index for efficient position-based queries
fn SpanIndex(comptime IdType: type) type {
    return struct {
        const Self = @This();

        entries: std.ArrayList(Entry),
        allocator: std.mem.Allocator,

        const Entry = struct {
            start: u32,
            end: u32,
            id: IdType,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .entries = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.entries.deinit(self.allocator);
        }

        pub fn add(self: *Self, start: u32, end: u32, id: IdType) !void {
            try self.entries.append(self.allocator, .{ .start = start, .end = end, .id = id });
        }

        pub fn finalize(self: *Self) void {
            // Sort by start position for binary search
            std.sort.insertion(Entry, self.entries.items, {}, struct {
                fn lessThan(context: void, a: Entry, b: Entry) bool {
                    _ = context;
                    return a.start < b.start;
                }
            }.lessThan);
        }

        pub fn findAt(self: *const Self, pos: u32) ?IdType {
            // Binary search for position
            var left: usize = 0;
            var right: usize = self.entries.items.len;

            while (left < right) {
                const mid = left + (right - left) / 2;
                const entry = self.entries.items[mid];

                if (pos < entry.start) {
                    right = mid;
                } else if (pos >= entry.end) {
                    left = mid + 1;
                } else {
                    return entry.id;
                }
            }

            return null;
        }
    };
}

// Tests
test "AstDB basic functionality" {
    var db = try AstDB.init(std.testing.allocator, false);
    defer db.deinit();

    // Test adding units
    const unit1 = try db.addUnit("test1.jan", "func main() {}");
    const unit2 = try db.addUnit("test2.jan", "struct Foo {}");

    try std.testing.expectEqual(@as(UnitId, @enumFromInt(0)), unit1);
    try std.testing.expectEqual(@as(UnitId, @enumFromInt(1)), unit2);

    // Test unit retrieval
    const retrieved_unit1 = db.getUnit(unit1);
    try std.testing.expect(retrieved_unit1 != null);
    try std.testing.expectEqualStrings("test1.jan", retrieved_unit1.?.path);
    try std.testing.expectEqualStrings("func main() {}", retrieved_unit1.?.source);

    // Test unit removal (O(1) cleanup)
    try db.removeUnit(unit1);
    try std.testing.expect(db.getUnit(unit1) == null);
}

test "SpanIndex functionality" {
    var index = SpanIndex(NodeId).init(std.testing.allocator);
    defer index.deinit();

    try index.add(0, 10, @enumFromInt(0));
    try index.add(10, 20, @enumFromInt(1));
    try index.add(20, 30, @enumFromInt(2));

    index.finalize();

    try std.testing.expectEqual(@as(NodeId, @enumFromInt(0)), index.findAt(5).?);
    try std.testing.expectEqual(@as(NodeId, @enumFromInt(1)), index.findAt(15).?);
    try std.testing.expectEqual(@as(NodeId, @enumFromInt(2)), index.findAt(25).?);
    try std.testing.expectEqual(@as(?NodeId, null), index.findAt(35));
}

test "AstDB node relationships" {
    var db = try AstDB.init(std.testing.allocator, false);
    defer db.deinit();

    const unit_id = try db.addUnit("test.jan", "func main() { struct Foo {} }");
    const unit = db.getUnit(unit_id).?;
    const arena = unit.arenaAllocator();

    // Create test data using fixed arrays - granite-solid architecture
    const nodes_array = [_]AstNode{
        // Root node with 2 children
        .{
            .kind = .source_file,
            .first_token = @enumFromInt(0),
            .last_token = @enumFromInt(10),
            .child_lo = 0,
            .child_hi = 2,
        },
        // Child nodes
        .{
            .kind = .func_decl,
            .first_token = @enumFromInt(0),
            .last_token = @enumFromInt(5),
            .child_lo = 2,
            .child_hi = 2, // no children
        },
        .{
            .kind = .struct_decl,
            .first_token = @enumFromInt(6),
            .last_token = @enumFromInt(10),
            .child_lo = 2,
            .child_hi = 2, // no children
        },
    };

    const edges_array = [_]NodeId{ @enumFromInt(1), @enumFromInt(2) };

    // Allocate with proper ownership - no ArrayList heresy
    unit.nodes = try arena.dupe(AstNode, &nodes_array);
    unit.edges = try arena.dupe(NodeId, &edges_array);

    // Test relationships
    const root_children = db.getChildren(unit_id, @enumFromInt(0));
    try std.testing.expectEqual(@as(usize, 2), root_children.len);
    try std.testing.expectEqual(@as(NodeId, @enumFromInt(1)), root_children[0]);
    try std.testing.expectEqual(@as(NodeId, @enumFromInt(2)), root_children[1]);

    const func_children = db.getChildren(unit_id, @enumFromInt(1));
    try std.testing.expectEqual(@as(usize, 0), func_children.len);
}

test "AstDB O(1) unit teardown" {
    var db = try AstDB.init(std.testing.allocator, false);
    defer db.deinit();

    // Create multiple units with significant data
    var units: [10]UnitId = undefined;
    for (&units, 0..) |*unit_id, i| {
        var buf: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(&buf, "test_{d}.jan", .{i});
        unit_id.* = try db.addUnit(path, "func main() { let x = 42; }");

        // Allocate some data in each unit's arena
        const unit = db.getUnit(unit_id.*).?;
        const arena = unit.arenaAllocator();

        // Simulate parser output using granite-solid allocation
        const nodes_slice = try arena.alloc(AstNode, 100);
        for (nodes_slice, 0..) |*node, j| {
            node.* = .{
                .kind = .func_decl,
                .first_token = @enumFromInt(@as(u32, @intCast(j))),
                .last_token = @enumFromInt(@as(u32, @intCast(j + 1))),
                .child_lo = 0,
                .child_hi = 0,
            };
        }
        unit.nodes = nodes_slice;
    }

    // Measure teardown time (should be O(1) per unit)
    const start_time = compat_time.nanoTimestamp();

    // Remove all units
    for (units) |unit_id| {
        try db.removeUnit(unit_id);
    }

    const end_time = compat_time.nanoTimestamp();
    const duration_ns = end_time - start_time;

    // Should complete very quickly (< 1ms for 10 units)
    try std.testing.expect(duration_ns < 1_000_000); // 1ms in nanoseconds
}
test "AstDB string interning integration" {
    var db = try AstDB.init(std.testing.allocator, false);
    defer db.deinit();

    // Test string interning
    const hello_id = try db.internString("hello");
    const world_id = try db.internString("world");
    const hello_id2 = try db.internString("hello"); // duplicate

    // Should deduplicate
    try std.testing.expectEqual(hello_id, hello_id2);
    try std.testing.expect(hello_id != world_id);

    // Should retrieve correctly
    try std.testing.expectEqualStrings("hello", db.getString(hello_id));
    try std.testing.expectEqualStrings("world", db.getString(world_id));
}

test "AstDB deterministic mode" {
    var db1 = AstDB.initWithMode(std.testing.allocator, true);
    defer db1.deinit();

    var db2 = AstDB.initWithMode(std.testing.allocator, true);
    defer db2.deinit();

    const test_strings = [_][]const u8{ "func", "main", "let", "x", "42" };

    var ids1: [test_strings.len]StrId = undefined;
    var ids2: [test_strings.len]StrId = undefined;

    // Intern same strings in both databases
    for (test_strings, 0..) |str, i| {
        ids1[i] = try db1.internString(str);
        ids2[i] = try db2.internString(str);
    }

    // Should produce identical IDs in deterministic mode
    for (ids1, ids2) |id1, id2| {
        try std.testing.expectEqual(id1, id2);
    }
}
test "AstDB CID computation integration" {
    var db = AstDB.initWithMode(std.testing.allocator, true);
    defer db.deinit();

    // Create a test unit
    const unit_id = try db.addUnit("test.jan", "func main() {}");

    // Compute module CID
    const module_cid = try db.computeCID(.{ .module_unit = unit_id }, std.testing.allocator);

    // Should produce a valid 32-byte hash
    try std.testing.expectEqual(@as(usize, 32), module_cid.len);

    // Computing the same CID again should be identical
    const module_cid2 = try db.computeCID(.{ .module_unit = unit_id }, std.testing.allocator);
    try std.testing.expectEqualSlices(u8, &module_cid, &module_cid2);
}
