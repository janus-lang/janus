// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const ids = @import("ids.zig");
const interner = @import("granite_interner.zig");

// GRANITE-SOLID ASTDB Snapshot - Architecturally incapable of leaking
// Fixed-capacity columnar storage that honors arena's append-only contract
// Requirements: SPEC-astdb-query.md section 2.2, 4.1

pub const StrId = ids.StrId;
pub const NodeId = ids.NodeId;
pub const TokenId = ids.TokenId;
pub const DeclId = ids.DeclId;
pub const ScopeId = ids.ScopeId;
pub const RefId = ids.RefId;
pub const DiagId = ids.DiagId;
pub const TypeId = ids.TypeId;
pub const CID = ids.CID;

pub const NodeKind = enum(u8) {
    // Literals
    int_literal,
    float_literal,
    string_literal,
    bool_literal,
    null_literal,

    // Identifiers and references
    identifier,
    qualified_name,

    // Expressions
    binary_op,
    unary_op,
    call_expr,
    index_expr,
    field_expr,
    cast_expr,

    // Statements
    block_stmt,
    expr_stmt,
    var_decl,
    assign_stmt,
    if_stmt,
    while_stmt,
    for_stmt,
    return_stmt,
    defer_stmt,
    break_stmt,
    continue_stmt,

    // Declarations
    func_decl,
    struct_decl,
    enum_decl,
    import_decl,
    module_decl,

    // Types
    basic_type,
    pointer_type,
    array_type,
    slice_type,
    optional_type,
    function_type,

    // Special
    error_node,
    root,
    program,
};

pub const TokenKind = enum(u8) {
    // Literals
    int_literal,
    float_literal,
    string_literal,
    char_literal,

    // Identifiers
    identifier,

    // Keywords
    kw_func,
    kw_var,
    kw_const,
    kw_if,
    kw_else,
    kw_while,
    kw_for,
    kw_return,
    kw_break,
    kw_continue,
    kw_struct,
    kw_enum,
    kw_import,
    kw_module,
    kw_true,
    kw_false,
    kw_null,

    // Operators
    plus,
    minus,
    star,
    slash,
    percent,
    equal,
    not_equal,
    less,
    less_equal,
    greater,
    greater_equal,
    logical_and,
    logical_or,
    logical_not,
    assign,

    // Delimiters
    lparen,
    rparen,
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    semicolon,
    comma,
    dot,
    colon,
    arrow,

    // Special
    newline,
    eof,
    invalid,
};

pub const DeclKind = enum(u8) {
    function,
    variable,
    constant,
    type_alias,
    struct_field,
    enum_variant,
    parameter,
    import,
    module,
};

pub const Span = struct {
    start_byte: u32,
    end_byte: u32,
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,
};

pub const TokenRow = struct {
    kind: TokenKind,
    str_id: StrId,
    span: Span,
    trivia_start: u32,
    trivia_end: u32,
};

pub const NodeRow = struct {
    kind: NodeKind,
    first_token: TokenId,
    last_token: TokenId,
    child_start: u32,
    child_count: u32,

    pub fn children(self: NodeRow, snapshot: *const Snapshot) []const NodeId {
        return snapshot.edges.get()[self.child_start .. self.child_start + self.child_count];
    }
};

pub const ScopeRow = struct {
    parent: ScopeId,
    first_decl: DeclId,
    decl_count: u32,
};

pub const DeclRow = struct {
    node: NodeId,
    name: StrId,
    scope: ScopeId,
    kind: DeclKind,
    type_id: TypeId,
};

pub const RefRow = struct {
    at_node: NodeId,
    name: StrId,
    target_decl: DeclId,
};

pub const DiagRow = struct {
    code: u32,
    severity: u8, // 0=error, 1=warning, 2=info
    span: Span,
    message: StrId,
};

// GRANITE-SOLID: Fixed-capacity tables that cannot leak
const GraniteTokenTable = struct {
    const MAX_TOKENS = 16384;

    data: [MAX_TOKENS]TokenRow,
    len: u32,

    fn init() GraniteTokenTable {
        return GraniteTokenTable{
            .data = undefined,
            .len = 0,
        };
    }

    fn append(self: *GraniteTokenTable, item: TokenRow) !TokenId {
        if (self.len >= MAX_TOKENS) {
            return error.CapacityExceeded;
        }
        self.data[self.len] = item;
        const id: TokenId = @enumFromInt(self.len);
        self.len += 1;
        return id;
    }

    fn get(self: *const GraniteTokenTable, id: TokenId) ?TokenRow {
        const raw_id = ids.toU32(id);
        if (raw_id >= self.len) return null;
        return self.data[raw_id];
    }

    fn count(self: *const GraniteTokenTable) u32 {
        return self.len;
    }
};

const GraniteNodeTable = struct {
    const MAX_NODES = 16384;

    data: [MAX_NODES]NodeRow,
    len: u32,

    fn init() GraniteNodeTable {
        return GraniteNodeTable{
            .data = undefined,
            .len = 0,
        };
    }

    fn append(self: *GraniteNodeTable, item: NodeRow) !NodeId {
        if (self.len >= MAX_NODES) {
            return error.CapacityExceeded;
        }
        self.data[self.len] = item;
        const id: NodeId = @enumFromInt(self.len);
        self.len += 1;
        return id;
    }

    fn get(self: *const GraniteNodeTable, id: NodeId) ?NodeRow {
        const raw_id = ids.toU32(id);
        if (raw_id >= self.len) return null;
        return self.data[raw_id];
    }

    fn count(self: *const GraniteNodeTable) u32 {
        return self.len;
    }
};

const GraniteEdgeTable = struct {
    const MAX_EDGES = 65536;

    data: [MAX_EDGES]NodeId,
    len: u32,

    fn init() GraniteEdgeTable {
        return GraniteEdgeTable{
            .data = undefined,
            .len = 0,
        };
    }

    fn appendSlice(self: *GraniteEdgeTable, items: []const NodeId) !u32 {
        if (self.len + items.len > MAX_EDGES) {
            return error.CapacityExceeded;
        }
        const start_index = self.len;
        for (items) |item| {
            self.data[self.len] = item;
            self.len += 1;
        }
        return start_index;
    }

    fn get(self: *const GraniteEdgeTable) []const NodeId {
        return self.data[0..self.len];
    }

    fn count(self: *const GraniteEdgeTable) u32 {
        return self.len;
    }
};

const GraniteScopeTable = struct {
    const MAX_SCOPES = 4096;

    data: [MAX_SCOPES]ScopeRow,
    len: u32,

    fn init() GraniteScopeTable {
        return GraniteScopeTable{
            .data = undefined,
            .len = 0,
        };
    }

    fn append(self: *GraniteScopeTable, item: ScopeRow) !ScopeId {
        if (self.len >= MAX_SCOPES) {
            return error.CapacityExceeded;
        }
        self.data[self.len] = item;
        const id: ScopeId = @enumFromInt(self.len);
        self.len += 1;
        return id;
    }

    fn get(self: *const GraniteScopeTable, id: ScopeId) ?ScopeRow {
        const raw_id = ids.toU32(id);
        if (raw_id >= self.len) return null;
        return self.data[raw_id];
    }

    fn count(self: *const GraniteScopeTable) u32 {
        return self.len;
    }
};

const GraniteDeclTable = struct {
    const MAX_DECLS = 8192;

    data: [MAX_DECLS]DeclRow,
    len: u32,

    fn init() GraniteDeclTable {
        return GraniteDeclTable{
            .data = undefined,
            .len = 0,
        };
    }

    fn append(self: *GraniteDeclTable, item: DeclRow) !DeclId {
        if (self.len >= MAX_DECLS) {
            return error.CapacityExceeded;
        }
        self.data[self.len] = item;
        const id: DeclId = @enumFromInt(self.len);
        self.len += 1;
        return id;
    }

    fn get(self: *const GraniteDeclTable, id: DeclId) ?DeclRow {
        const raw_id = ids.toU32(id);
        if (raw_id >= self.len) return null;
        return self.data[raw_id];
    }

    fn count(self: *const GraniteDeclTable) u32 {
        return self.len;
    }
};

const GraniteRefTable = struct {
    const MAX_REFS = 16384;

    data: [MAX_REFS]RefRow,
    len: u32,

    fn init() GraniteRefTable {
        return GraniteRefTable{
            .data = undefined,
            .len = 0,
        };
    }

    fn append(self: *GraniteRefTable, item: RefRow) !RefId {
        if (self.len >= MAX_REFS) {
            return error.CapacityExceeded;
        }
        self.data[self.len] = item;
        const id: RefId = @enumFromInt(self.len);
        self.len += 1;
        return id;
    }

    fn get(self: *const GraniteRefTable, id: RefId) ?RefRow {
        const raw_id = ids.toU32(id);
        if (raw_id >= self.len) return null;
        return self.data[raw_id];
    }

    fn count(self: *const GraniteRefTable) u32 {
        return self.len;
    }
};

const GraniteDiagTable = struct {
    const MAX_DIAGS = 2048;

    data: [MAX_DIAGS]DiagRow,
    len: u32,

    fn init() GraniteDiagTable {
        return GraniteDiagTable{
            .data = undefined,
            .len = 0,
        };
    }

    fn append(self: *GraniteDiagTable, item: DiagRow) !DiagId {
        if (self.len >= MAX_DIAGS) {
            return error.CapacityExceeded;
        }
        self.data[self.len] = item;
        const id: DiagId = @enumFromInt(self.len);
        self.len += 1;
        return id;
    }

    fn get(self: *const GraniteDiagTable, id: DiagId) ?DiagRow {
        const raw_id = ids.toU32(id);
        if (raw_id >= self.len) return null;
        return self.data[raw_id];
    }

    fn count(self: *const GraniteDiagTable) u32 {
        return self.len;
    }
};

// GRANITE-SOLID: Fixed-capacity CID cache with linear search
const GraniteCIDCache = struct {
    const MAX_CIDS = 8192;

    const Entry = struct {
        node_id: NodeId,
        cid: CID,
    };

    data: [MAX_CIDS]Entry,
    len: u32,

    fn init() GraniteCIDCache {
        return GraniteCIDCache{
            .data = undefined,
            .len = 0,
        };
    }

    fn put(self: *GraniteCIDCache, node_id: NodeId, cid: CID) !void {
        // Check if already exists (update in place)
        for (0..self.len) |i| {
            if (std.meta.eql(self.data[i].node_id, node_id)) {
                self.data[i].cid = cid;
                return;
            }
        }

        // Add new entry
        if (self.len >= MAX_CIDS) {
            return error.CapacityExceeded;
        }
        self.data[self.len] = Entry{
            .node_id = node_id,
            .cid = cid,
        };
        self.len += 1;
    }

    fn get(self: *const GraniteCIDCache, node_id: NodeId) ?CID {
        for (0..self.len) |i| {
            if (std.meta.eql(self.data[i].node_id, node_id)) {
                return self.data[i].cid;
            }
        }
        return null;
    }

    fn count(self: *const GraniteCIDCache) u32 {
        return self.len;
    }
};

pub const Snapshot = struct {
    arena: std.heap.ArenaAllocator,
    str_interner: *interner.StrInterner,

    // GRANITE-SOLID: Fixed-capacity tables - architecturally incapable of leaking
    tokens: GraniteTokenTable,
    nodes: GraniteNodeTable,
    edges: GraniteEdgeTable,
    scopes: GraniteScopeTable,
    decls: GraniteDeclTable,
    refs: GraniteRefTable,
    diags: GraniteDiagTable,
    cids: GraniteCIDCache,
    // Node -> Scope mapping (fixed-capacity, parallel to nodes)
    node_scopes: GraniteNodeScopeTable,

    pub fn init(allocator: std.mem.Allocator, str_interner: *interner.StrInterner) !*Snapshot {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();

        const snapshot = try arena_allocator.create(Snapshot);
        snapshot.* = Snapshot{
            .arena = arena,
            .str_interner = str_interner,
            .tokens = GraniteTokenTable.init(),
            .nodes = GraniteNodeTable.init(),
            .edges = GraniteEdgeTable.init(),
            .scopes = GraniteScopeTable.init(),
            .decls = GraniteDeclTable.init(),
            .refs = GraniteRefTable.init(),
            .diags = GraniteDiagTable.init(),
            .cids = GraniteCIDCache.init(),
            .node_scopes = GraniteNodeScopeTable.init(),
        };

        return snapshot;
    }

    pub fn deinit(self: *Snapshot) void {
        // GRANITE-SOLID: O(1) arena deallocation - all memory freed at once
        // Fixed arrays are stack-allocated, no cleanup needed
        self.arena.deinit();
    }

    // Append-only table operations (immutable rows)

    pub fn addToken(self: *Snapshot, kind: TokenKind, str_id: StrId, span: Span) !TokenId {
        return try self.tokens.append(TokenRow{
            .kind = kind,
            .str_id = str_id,
            .span = span,
            .trivia_start = 0,
            .trivia_end = 0,
        });
    }

    pub fn addNode(self: *Snapshot, kind: NodeKind, first_token: TokenId, last_token: TokenId, children: []const NodeId) !NodeId {
        const child_start = try self.edges.appendSlice(children);

        return try self.nodes.append(NodeRow{
            .kind = kind,
            .first_token = first_token,
            .last_token = last_token,
            .child_start = child_start,
            .child_count = @as(u32, @intCast(children.len)),
        });
    }

    pub fn addScope(self: *Snapshot, parent: ScopeId) !ScopeId {
        return try self.scopes.append(ScopeRow{
            .parent = parent,
            .first_decl = ids.INVALID_DECL_ID,
            .decl_count = 0,
        });
    }

    pub fn addDecl(self: *Snapshot, node: NodeId, name: StrId, scope: ScopeId, kind: DeclKind) !DeclId {
        return try self.decls.append(DeclRow{
            .node = node,
            .name = name,
            .scope = scope,
            .kind = kind,
            .type_id = ids.INVALID_TYPE_ID,
        });
    }

    pub fn addRef(self: *Snapshot, at_node: NodeId, name: StrId, target_decl: DeclId) !RefId {
        return try self.refs.append(RefRow{
            .at_node = at_node,
            .name = name,
            .target_decl = target_decl,
        });
    }

    pub fn addDiag(self: *Snapshot, code: u32, severity: u8, span: Span, message: StrId) !DiagId {
        return try self.diags.append(DiagRow{
            .code = code,
            .severity = severity,
            .span = span,
            .message = message,
        });
    }

    // Table access operations

    pub fn getToken(self: *const Snapshot, id: TokenId) ?TokenRow {
        return self.tokens.get(id);
    }

    pub fn getNode(self: *const Snapshot, id: NodeId) ?NodeRow {
        return self.nodes.get(id);
    }

    pub fn getScope(self: *const Snapshot, id: ScopeId) ?ScopeRow {
        return self.scopes.get(id);
    }

    pub fn getDecl(self: *const Snapshot, id: DeclId) ?DeclRow {
        return self.decls.get(id);
    }

    pub fn getRef(self: *const Snapshot, id: RefId) ?RefRow {
        return self.refs.get(id);
    }

    pub fn getDiag(self: *const Snapshot, id: DiagId) ?DiagRow {
        return self.diags.get(id);
    }

    pub fn getCID(self: *const Snapshot, id: NodeId) ?CID {
        return self.cids.get(id);
    }

    pub fn setCID(self: *Snapshot, id: NodeId, cid: CID) !void {
        try self.cids.put(id, cid);
    }

    // Node -> Scope mapping helpers
    pub fn setNodeScope(self: *Snapshot, node: NodeId, scope: ScopeId) void {
        self.node_scopes.set(node, scope);
    }

    pub fn getNodeScope(self: *const Snapshot, node: NodeId) ?ScopeId {
        return self.node_scopes.get(node);
    }

    // Statistics and introspection

    pub fn nodeCount(self: *const Snapshot) u32 {
        return self.nodes.count();
    }

    pub fn tokenCount(self: *const Snapshot) u32 {
        return self.tokens.count();
    }

    pub fn declCount(self: *const Snapshot) u32 {
        return self.decls.count();
    }

    pub fn diagCount(self: *const Snapshot) u32 {
        return self.diags.count();
    }

    pub fn refCount(self: *const Snapshot) u32 {
        return self.refs.count();
    }
};

const GraniteNodeScopeTable = struct {
    const MAX = 16384; // match MAX_NODES
    data: [MAX]ScopeId,
    len: u32,

    fn init() GraniteNodeScopeTable {
        var data: [MAX]ScopeId = undefined;
        // Initialize with INVALID scope to be safe
        for (&data, 0..) |*slot, i| {
            _ = i;
            slot.* = ids.INVALID_SCOPE_ID;
        }
        return GraniteNodeScopeTable{ .data = data, .len = 0 };
    }

    fn set(self: *GraniteNodeScopeTable, node: NodeId, scope: ScopeId) void {
        const idx = ids.toU32(node);
        if (idx >= self.len) self.len = idx + 1;
        self.data[idx] = scope;
    }

    fn get(self: *const GraniteNodeScopeTable, node: NodeId) ?ScopeId {
        const idx = ids.toU32(node);
        if (idx >= self.len) return null;
        const s = self.data[idx];
        if (std.meta.eql(s, ids.INVALID_SCOPE_ID)) return null;
        return s;
    }
};

// GRANITE-SOLID TEST SUITE - Brutal validation
test "Granite Snapshot - Basic Operations" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var str_interner = interner.StrInterner.init(allocator, false);
        defer str_interner.deinit();

        var snapshot = try Snapshot.init(allocator, &str_interner);
        defer snapshot.deinit();

        // Add some tokens
        const hello_str = try str_interner.get("hello");
        const token_id = try snapshot.addToken(.identifier, hello_str, Span{
            .start_byte = 0,
            .end_byte = 5,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 6,
        });

        // Add a node
        const node_id = try snapshot.addNode(.identifier, token_id, token_id, &[_]NodeId{});

        // Verify retrieval
        const token = snapshot.getToken(token_id).?;
        try testing.expectEqual(TokenKind.identifier, token.kind);
        try testing.expectEqual(hello_str, token.str_id);

        const node = snapshot.getNode(node_id).?;
        try testing.expectEqual(NodeKind.identifier, node.kind);
        try testing.expectEqual(@as(u32, 0), node.child_count);

        // Verify counts
        try testing.expectEqual(@as(u32, 1), snapshot.tokenCount());
        try testing.expectEqual(@as(u32, 1), snapshot.nodeCount());
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite Snapshot - CID Cache" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var str_interner = interner.StrInterner.init(allocator, false);
        defer str_interner.deinit();

        var snapshot = try Snapshot.init(allocator, &str_interner);
        defer snapshot.deinit();

        // Add a node
        const hello_str = try str_interner.get("hello");
        const token_id = try snapshot.addToken(.identifier, hello_str, Span{
            .start_byte = 0,
            .end_byte = 5,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 6,
        });
        const node_id = try snapshot.addNode(.identifier, token_id, token_id, &[_]NodeId{});

        // Test CID operations
        try testing.expect(snapshot.getCID(node_id) == null);

        const test_cid: CID = [_]u8{0} ** 31 ++ [_]u8{42}; // Test CID with last byte = 42
        try snapshot.setCID(node_id, test_cid);

        const retrieved_cid = snapshot.getCID(node_id).?;
        try testing.expectEqual(test_cid, retrieved_cid);
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite Snapshot - Stress Test" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var str_interner = interner.StrInterner.init(allocator, false);
        defer str_interner.deinit();

        var snapshot = try Snapshot.init(allocator, &str_interner);
        defer snapshot.deinit();

        // Add many tokens and nodes
        for (0..1000) |i| {
            const str = try std.fmt.allocPrint(allocator, "token_{d}", .{i});
            defer allocator.free(str);

            const str_id = try str_interner.get(str);
            const token_id = try snapshot.addToken(.identifier, str_id, Span{
                .start_byte = @as(u32, @intCast(i * 10)),
                .end_byte = @as(u32, @intCast(i * 10 + 5)),
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 6,
            });

            _ = try snapshot.addNode(.identifier, token_id, token_id, &[_]NodeId{});
        }

        // Verify counts
        try testing.expectEqual(@as(u32, 1000), snapshot.tokenCount());
        try testing.expectEqual(@as(u32, 1000), snapshot.nodeCount());
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}
