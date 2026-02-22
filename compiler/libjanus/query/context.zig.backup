// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Query Context & Canonical Args
// Task 2.1 - Foundation for all semantic queries

const std = @import("std");
const Allocator = std.mem.Allocator;
const Blake3 = std.crypto.hash.Blake3;
const schema = @import("../astdb/schema.zig");
const node_view = @import("../astdb/node_view.zig");
const astdb = schema;

/// Query Context - manages query execution environment and canonical argument handling
pub const QueryCtx = struct {
    allocator: Allocator,
    astdb: *AstDatabase,
    memo_table: *MemoTable,
    dependency_tracker: *DependencyTracker,
    performance_monitor: PerformanceMonitor,

    const Self = @This();

    pub fn init(allocator: Allocator, ast_database: *AstDatabase) !Self {
        return Self{
            .allocator = allocator,
            .astdb = ast_database,
            .memo_table = try MemoTable.init(allocator),
            .dependency_tracker = try DependencyTracker.init(allocator),
            .performance_monitor = PerformanceMonitor.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.memo_table.deinit();
        self.dependency_tracker.deinit();
    }

    /// Execute a query with canonical argument validation
    pub fn executeQuery(self: *Self, query_id: QueryId, args: QueryArgs) !QueryResult {
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = std.time.nanoTimestamp() - start_time;
            self.performance_monitor.recordQuery(query_id, elapsed);
        }

        // Validate arguments are canonical
        const canonical_args = try self.canonicalizeArgs(args);

        // Check memo table first
        const memo_key = try self.computeMemoKey(query_id, canonical_args);
        if (self.memo_table.get(memo_key)) |cached_result| {
            return QueryResult{
                .data = cached_result.data,
                .dependencies = cached_result.dependencies,
                .from_cache = true,
            };
        }

        // Execute query and track dependencies
        self.dependency_tracker.startQuery(memo_key);
        defer self.dependency_tracker.endQuery();

        const result = try self.executeQueryImpl(query_id, canonical_args);

        // Cache result with dependencies
        const dependencies = self.dependency_tracker.getDependencies(memo_key);
        try self.memo_table.put(memo_key, CachedResult{
            .data = result.data,
            .dependencies = dependencies,
        });

        return QueryResult{
            .data = result.data,
            .dependencies = dependencies,
            .from_cache = false,
        };
    }

    fn executeQueryImpl(self: *Self, query_id: QueryId, args: CanonicalArgs) !QueryResultData {
        return switch (query_id) {
            .ResolveName => try @import("impl/resolve_name.zig").resolveName(self, args),
            .TypeOf => try @import("impl/type_of.zig").typeOf(self, args),
            .Dispatch => try @import("impl/dispatch.zig").dispatch(self, args),
            .EffectsOf => try @import("impl/effects_of.zig").effectsOf(self, args),
            .DefinitionOf => try @import("impl/definition_of.zig").definitionOf(self, args),
            .Hover => try @import("impl/hover.zig").hover(self, args),
            .IROf => try @import("impl/ir_of.zig").irOf(self, args),
        };
    }

    fn canonicalizeArgs(self: *Self, args: QueryArgs) !CanonicalArgs {
        // Ensure all arguments are in canonical form
        // CIDs must be properly formatted, scalars normalized
        var canonical = CanonicalArgs.init(self.allocator);

        for (args.items) |arg| {
            const canonical_arg = switch (arg) {
                .cid => |cid| blk: {
                    if (!isCanonicalCID(cid)) {
                        return error.QE0005_NonCanonicalArg;
                    }
                    break :blk arg;
                },
                .scalar => |scalar| try canonicalizeScalar(scalar),
                .string => |str| try canonicalizeString(str),
            };
            try canonical.append(canonical_arg);
        }

        return canonical;
    }

    fn computeMemoKey(self: *Self, query_id: QueryId, args: CanonicalArgs) !MemoKey {
        var hasher = Blake3.init(.{});

        // Hash query ID
        hasher.update(@tagName(query_id));

        // Hash canonical arguments
        for (args.items) |arg| {
            switch (arg) {
                .cid => |cid| hasher.update(&cid),
                .scalar => |scalar| hasher.update(std.mem.asBytes(&scalar)),
                .string => |str| hasher.update(str),
            }
        }

        var key_bytes: [32]u8 = undefined;
        hasher.final(&key_bytes);

        return MemoKey{ .hash = key_bytes };
    }

    // Query implementations (stubs for now)
    fn executeResolveName(self: *Self, args: CanonicalArgs) !QueryResultData {
        // TODO: Implement name resolution
        return QueryResultData{ .symbol_info = undefined };
    }

    fn executeTypeOf(self: *Self, args: CanonicalArgs) !QueryResultData {
        // TODO: Implement type inference
        return QueryResultData{ .type_info = undefined };
    }

    fn executeDispatch(self: *Self, args: CanonicalArgs) !QueryResultData {
        // TODO: Implement dispatch resolution
        return QueryResultData{ .dispatch_info = undefined };
    }

    fn executeEffectsOf(self: *Self, args: CanonicalArgs) !QueryResultData {
        // TODO: Implement effect analysis
        return QueryResultData{ .effects_info = undefined };
    }

    fn executeDefinitionOf(self: *Self, args: CanonicalArgs) !QueryResultData {
        // TODO: Implement definition lookup
        return QueryResultData{ .definition_info = undefined };
    }

    fn executeHover(self: *Self, args: CanonicalArgs) !QueryResultData {
        // TODO: Implement hover information
        return QueryResultData{ .hover_info = undefined };
    }

    fn executeIROf(self: *Self, args: CanonicalArgs) !QueryResultData {
        // TODO: Implement IR generation with CAS storage
        return QueryResultData{ .ir_info = undefined };
    }
};

/// Query identifiers for the v1 catalogue
pub const QueryId = enum {
    ResolveName,
    TypeOf,
    Dispatch,
    EffectsOf,
    DefinitionOf,
    Hover,
    IROf,
};

/// Query arguments before canonicalization
pub const QueryArgs = std.ArrayList(QueryArg);

pub const QueryArg = union(enum) {
    cid: CID,
    scalar: i64,
    string: []const u8,
};

/// Canonical arguments after validation
pub const CanonicalArgs = std.ArrayList(QueryArg);

/// Query result with dependency tracking
pub const QueryResult = struct {
    data: QueryResultData,
    dependencies: []Dependency,
    from_cache: bool,
};

pub const QueryResultData = union(enum) {
    symbol_info: SymbolInfo,
    type_info: TypeInfo,
    dispatch_info: DispatchInfo,
    effects_info: EffectsInfo,
    definition_info: DefinitionInfo,
    hover_info: HoverInfo,
    ir_info: IRInfo,
};

/// Memoization key for query results
pub const MemoKey = struct {
    hash: [32]u8,

    pub fn eql(self: MemoKey, other: MemoKey) bool {
        return std.mem.eql(u8, &self.hash, &other.hash);
    }
};

/// Cached query result
pub const CachedResult = struct {
    data: QueryResultData,
    dependencies: []Dependency,
};

/// Dependency tracking for invalidation
pub const Dependency = union(enum) {
    cid: CID,
    query: MemoKey,
};

/// Performance monitoring
pub const PerformanceMonitor = struct {
    query_times: std.HashMap(QueryId, u64),

    pub fn init() PerformanceMonitor {
        return PerformanceMonitor{
            .query_times = std.HashMap(QueryId, u64).init(std.heap.page_allocator),
        };
    }

    pub fn recordQuery(self: *PerformanceMonitor, query_id: QueryId, elapsed_ns: u64) void {
        self.query_times.put(query_id, elapsed_ns) catch {};
    }

    pub fn getAverageTime(self: *PerformanceMonitor, query_id: QueryId) ?u64 {
        return self.query_times.get(query_id);
    }
};

// Utility functions for canonicalization
fn isCanonicalCID(cid: CID) bool {
    // CID is already [32]u8, so always valid length
    // Could add additional validation here if needed
    _ = cid;
    return true;
}

fn canonicalizeScalar(scalar: i64) !QueryArg {
    // Scalars are already canonical
    return QueryArg{ .scalar = scalar };
}

fn canonicalizeString(str: []const u8) !QueryArg {
    // Strings must be UTF-8 validated and normalized
    if (!std.unicode.utf8ValidateSlice(str)) {
        return error.QE0005_NonCanonicalArg;
    }
    return QueryArg{ .string = str };
}

const core_astdb = @import("../../astdb/core_astdb.zig");

// Forward declarations for types that will be implemented
pub const AstDatabase = struct {
    db: *core_astdb.AstDB,
    allocator: Allocator,

    pub fn getNode(self: *AstDatabase, cid: CID) !astdb.AstNode {
        const located = node_view.findNodeByCID(self.db, cid) orelse return error.NodeNotFound;
        const view = node_view.NodeView.init(self.db, located.unit_id, located.node_id);
        return astdb.fromView(view, self.allocator);
    }

    pub fn getNodeView(self: *AstDatabase, cid: CID) !node_view.NodeView {
        const located = node_view.findNodeByCID(self.db, cid) orelse return error.NodeNotFound;
        return node_view.NodeView.init(self.db, located.unit_id, located.node_id);
    }

    pub fn getSymbolTable(self: *AstDatabase, unit_id: core_astdb.UnitId, scope_id: core_astdb.ScopeId) !astdb.SymbolTable {
        const decl_ids = try self.db.getDeclsInScope(unit_id, scope_id, self.allocator);
        var symbols = std.ArrayList(astdb.Symbol).init(self.allocator);
        errdefer symbols.deinit();

        for (decl_ids) |decl_id| {
            const decl = self.db.getDecl(unit_id, decl_id).?;
            const view = node_view.NodeView.init(self.db, unit_id, decl.node);
            const symbol = astdb.Symbol{
                .name = self.db.getString(decl.name),
                .definition_cid = self.db.getCID(unit_id, decl.node) orelse undefined,
                .symbol_type = declKindToSymbolType(decl.kind),
                .visibility = .public, // TODO: get visibility
                .location = view.span(),
            };
            try symbols.append(symbol);
        }

        return astdb.SymbolTable{
            .symbols = try symbols.toOwnedSlice(),
        };
    }

    pub fn getTypeRegistry(self: *AstDatabase, context_cid: CID) !astdb.TypeRegistry {
        _ = self;
        _ = context_cid;
        return error.NotImplemented;
    }

    pub fn getTypeDefinition(self: *AstDatabase, type_cid: CID) !astdb.TypeDefinition {
        _ = self;
        _ = type_cid;
        return error.NotImplemented;
    }

    pub fn getImports(self: *AstDatabase, scope_cid: CID) ![]CID {
        _ = self;
        _ = scope_cid;
        return error.NotImplemented;
    }

    pub fn resolveModulePath(self: *AstDatabase, module_path: []const u8) !CID {
        _ = self;
        _ = module_path;
        return error.NotImplemented;
    }

    pub fn getModuleRegistry(self: *AstDatabase) !astdb.ModuleRegistry {
        _ = self;
        return error.NotImplemented;
    }

    pub fn getSymbol(self: *AstDatabase, symbol_cid: CID) !astdb.SymbolInfo {
        _ = self;
        _ = symbol_cid;
        return error.NotImplemented;
    }

    pub fn findScopeByCID(self: *AstDatabase, scope_cid: CID) !struct { unit_id: core_astdb.UnitId, scope_id: core_astdb.ScopeId } {
        const located = node_view.findNodeByCID(self.db, scope_cid) orelse return error.ScopeNotFound;
        const unit = self.db.getUnit(located.unit_id) orelse return error.ScopeNotFound;
        for (unit.scopes, 0..) |scope, scope_index| {
            if (scope.node == located.node_id) {
                return .{
                    .unit_id = located.unit_id,
                    .scope_id = @enumFromInt(scope_index),
                };
            }
        }
        return error.ScopeNotFound;
    }
};

fn declKindToSymbolType(kind: core_astdb.Decl.DeclKind) astdb.SymbolType {
    return switch (kind) {
        .function => .function,
        .variable => .variable,
        .constant => .constant,
        .parameter => .parameter,
        .type_def => .type,
        .field => .field,
        .variant => .field,
    };
}

pub const MemoTable = @import("memo.zig").MemoTable;
pub const DependencyTracker = @import("deps.zig").DependencyTracker;
pub const CID = @import("../astdb/ids.zig").CID;

// ASTDB type definitions (placeholders for now)

// Result type definitions (expanded for v1 implementation)
pub const SymbolInfo = schema.SymbolInfo;
pub const TypeInfo = schema.TypeInfo;
pub const DispatchInfo = schema.DispatchInfo;
pub const EffectsInfo = schema.EffectsInfo;
pub const DefinitionInfo = schema.DefinitionInfo;
pub const HoverInfo = schema.HoverInfo;
pub const IRInfo = schema.IRInfo;
