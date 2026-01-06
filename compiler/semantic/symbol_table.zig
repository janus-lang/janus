// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Symbol Table - The Foundation of Semantic Understanding
//!
//! This module implements the hierarchical symbol table that binds every
//! identifier in the ASTDB to its unique declaration. It provides the
//! foundation upon which the entire type system is built.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
// HashMap will be used with full std.HashMap syntax
const Mutex = std.Thread.Mutex;

const astdb = @import("astdb");
const Blake3 = std.crypto.hash.Blake3;
const Blake3Hash = [Blake3.digest_length]u8;

/// Unique identifier for symbols
pub const SymbolId = enum(u32) { _ };

/// Unique identifier for scopes
pub const ScopeId = enum(u32) { _ };

/// String identifier from global interner
pub const StringId = enum(u32) {
    _,

    pub fn eql(self: StringId, other: StringId) bool {
        return @intFromEnum(self) == @intFromEnum(other);
    }
};

/// AST node identifier
pub const NodeId = astdb.NodeId;

/// Source location span
pub const SourceSpan = astdb.SourceSpan;

/// Import TypeId from type system for consistency
const type_system = @import("type_system.zig");
pub const TypeId = type_system.TypeId;

/// Symbol Table - Hierarchical scope and symbol management
pub const SymbolTable = struct {
    allocator: Allocator,
    symbol_interner: SymbolInterner,
    scopes: ArrayList(Scope),
    scope_map: std.HashMap(ScopeId, u32, std.hash_map.AutoContext(ScopeId), std.hash_map.default_max_load_percentage),
    symbols: ArrayList(Symbol),
    symbol_map: std.HashMap(SymbolId, u32, std.hash_map.AutoContext(SymbolId), std.hash_map.default_max_load_percentage),
    scope_stack: ArrayList(ScopeId),
    global_scope: ScopeId,
    mutex: Mutex = .{},
    next_symbol_id: u32 = 0,
    next_scope_id: u32 = 0,

    pub const Scope = struct {
        id: ScopeId,
        parent: ?ScopeId,
        kind: ScopeKind,
        bindings: std.HashMap(StringId, SymbolId, std.hash_map.AutoContext(StringId), std.hash_map.default_max_load_percentage),
        children: ArrayList(ScopeId),

        pub const ScopeKind = enum {
            global,
            module,
            function,
            block,
            struct_body,
            enum_body,
        };
    };

    pub const Symbol = struct {
        id: SymbolId,
        name: StringId,
        kind: SymbolKind,
        type_id: ?TypeId = null,
        declaration_node: NodeId,
        declaration_span: SourceSpan,
        visibility: Visibility,
        scope_id: ScopeId,

        pub const SymbolKind = enum {
            variable,
            function,
            parameter,
            type_alias,
            struct_type,
            enum_type,
        };

        pub const Visibility = enum {
            private,
            module_local,
            public,
        };
    };

    pub fn lookup(self: *SymbolTable, name: []const u8) ?SymbolId {
        const name_id = self.symbol_interner.intern(name) catch return null;
        return self.resolveIdentifier(name_id, null);
    }

    pub fn init(allocator: Allocator) !*SymbolTable {
        const table = try allocator.create(SymbolTable);
        table.* = SymbolTable{
            .allocator = allocator,
            .symbol_interner = SymbolInterner.init(allocator),
            .scopes = ArrayList(Scope).init(allocator),
            .scope_map = std.HashMap(ScopeId, u32, std.hash_map.AutoContext(ScopeId), std.hash_map.default_max_load_percentage).init(allocator),
            .symbols = ArrayList(Symbol).init(allocator),
            .symbol_map = std.HashMap(SymbolId, u32, std.hash_map.AutoContext(SymbolId), std.hash_map.default_max_load_percentage).init(allocator),
            .scope_stack = ArrayList(ScopeId).init(allocator),
            .global_scope = @enumFromInt(0),
        };

        // Create global scope
        const global_scope = try table.createScope(null, .global);
        try table.pushScope(global_scope);
        return table;
    }

    pub fn deinit(self: *SymbolTable) void {
        self.symbol_interner.deinit();
        for (self.scopes.items) |*scope| {
            scope.bindings.deinit();
            scope.children.deinit();
        }
        self.scopes.deinit();
        self.scope_map.deinit();
        self.symbols.deinit();
        self.symbol_map.deinit();
        self.scope_stack.deinit();
        self.allocator.destroy(self);
    }

    pub fn createScope(self: *SymbolTable, parent: ?ScopeId, kind: Scope.ScopeKind) !ScopeId {
        const scope_id: ScopeId = @enumFromInt(self.next_scope_id);
        self.next_scope_id += 1;

        const scope = Scope{
            .id = scope_id,
            .parent = parent,
            .kind = kind,
            .bindings = std.HashMap(StringId, SymbolId, std.hash_map.AutoContext(StringId), std.hash_map.default_max_load_percentage).init(self.allocator),
            .children = ArrayList(ScopeId).init(self.allocator),
        };

        const index = self.scopes.items.len;
        try self.scopes.append(scope);
        try self.scope_map.put(scope_id, @intCast(index));
        return scope_id;
    }

    pub fn getScope(self: *SymbolTable, scope_id: ScopeId) ?*Scope {
        const index = self.scope_map.get(scope_id) orelse return null;
        return &self.scopes.items[index];
    }

    pub fn pushScope(self: *SymbolTable, scope_id: ScopeId) !void {
        try self.scope_stack.append(scope_id);
    }

    pub fn popScope(self: *SymbolTable) ?ScopeId {
        return if (self.scope_stack.items.len > 0) self.scope_stack.pop() else null;
    }

    pub fn getCurrentScope(self: *SymbolTable) ?ScopeId {
        return if (self.scope_stack.items.len > 0)
            self.scope_stack.items[self.scope_stack.items.len - 1]
        else
            null;
    }

    pub fn resolveIdentifier(self: *SymbolTable, name: StringId, scope_id: ?ScopeId) ?SymbolId {
        const start_scope = scope_id orelse self.getCurrentScope() orelse return null;
        var current_scope_id = start_scope;

        while (true) {
            const scope = self.getScope(current_scope_id) orelse break;
            if (scope.bindings.get(name)) |symbol_id| {
                return symbol_id;
            }
            current_scope_id = scope.parent orelse break;
        }
        return null;
    }

    pub fn getSymbol(self: *SymbolTable, symbol_id: SymbolId) ?*Symbol {
        const index = self.symbol_map.get(symbol_id) orelse return null;
        return &self.symbols.items[index];
    }

    // Methods needed by validation engine
    pub fn contains(self: *SymbolTable, name: []const u8) bool {
        const name_id = self.symbol_interner.intern(name) catch return false;
        return self.resolveIdentifier(name_id, null) != null;
    }

    pub fn isDuplicate(self: *SymbolTable, name: []const u8) bool {
        const name_id = self.symbol_interner.intern(name) catch return false;
        for (self.scopes.items) |scope| {
            if (scope.bindings.contains(name_id)) {
                return true;
            }
        }
        return false;
    }

    pub fn isDuplicateInCurrentScope(self: *SymbolTable, name: []const u8) bool {
        const name_id = self.symbol_interner.intern(name) catch return false;
        const current_scope_id = self.getCurrentScope() orelse return false;
        const current_scope = self.getScope(current_scope_id) orelse return false;
        return current_scope.bindings.contains(name_id);
    }

    pub fn declareSymbol(self: *SymbolTable, name: StringId, kind: Symbol.SymbolKind, declaration_node: NodeId, declaration_span: SourceSpan, visibility: Symbol.Visibility, type_id: ?TypeId) !SymbolId {
        const current_scope_id = self.getCurrentScope() orelse return error.NoCurrentScope;
        const current_scope = self.getScope(current_scope_id).?;

        // Check for duplicates
        if (current_scope.bindings.contains(name)) {
            return error.DuplicateDeclaration;
        }

        const symbol_id: SymbolId = @enumFromInt(self.next_symbol_id);
        self.next_symbol_id += 1;

        const symbol = Symbol{
            .id = symbol_id,
            .name = name,
            .kind = kind,
            .type_id = type_id,
            .declaration_node = declaration_node,
            .declaration_span = declaration_span,
            .visibility = visibility,
            .scope_id = current_scope_id,
        };

        try self.symbols.append(symbol);
        try self.symbol_map.put(symbol_id, @intCast(self.symbols.items.len - 1));

        try current_scope.bindings.put(name, symbol_id);

        return symbol_id;
    }

    pub fn addTemporaryVariable(self: *SymbolTable, name: []const u8) !void {
        const name_id = try self.symbol_interner.intern(name);
        const current_scope_id = self.getCurrentScope() orelse return error.NoCurrentScope;

        const symbol = Symbol{
            .id = @enumFromInt(self.next_symbol_id),
            .name = name_id,
            .kind = .variable,
            .type_id = null,
            .scope_id = current_scope_id,
            .declaration_node = @enumFromInt(0),
            .declaration_span = SourceSpan{ .start = 0, .end = 0, .line = 0, .column = 0 },
            .visibility = .private,
        };

        self.next_symbol_id += 1;
        try self.symbols.append(symbol);
        try self.symbol_map.put(symbol.id, self.symbols.items.len - 1);

        const current_scope = self.getScope(current_scope_id).?;
        try current_scope.bindings.put(name_id, symbol.id);
    }

    pub fn removeTemporaryVariable(self: *SymbolTable, name: []const u8) void {
        const name_id = self.symbol_interner.intern(name) catch return;
        const current_scope_id = self.getCurrentScope() orelse return;
        const current_scope = self.getScope(current_scope_id) orelse return;
        _ = current_scope.bindings.remove(name_id);
    }

    pub fn isAccessible(self: *SymbolTable, name: []const u8) bool {
        const name_id = self.symbol_interner.intern(name) catch return false;
        return self.resolveIdentifier(name_id, null) != null;
    }
};

/// Symbol Interner for efficient string deduplication
const SymbolInterner = struct {
    allocator: Allocator,
    strings: ArrayList([]const u8),
    string_map: std.HashMap(Blake3Hash, StringId, std.hash_map.AutoContext(Blake3Hash), std.hash_map.default_max_load_percentage),
    next_id: u32 = 0,

    pub fn init(allocator: Allocator) SymbolInterner {
        return SymbolInterner{
            .allocator = allocator,
            .strings = ArrayList([]const u8).init(allocator),
            .string_map = std.HashMap(Blake3Hash, StringId, std.hash_map.AutoContext(Blake3Hash), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *SymbolInterner) void {
        for (self.strings.items) |string| {
            self.allocator.free(string);
        }
        self.strings.deinit();
        self.string_map.deinit();
    }

    pub fn intern(self: *SymbolInterner, string: []const u8) !StringId {
        var hasher = Blake3.init(.{});
        hasher.update(string);
        var hash: Blake3Hash = undefined;
        hasher.final(&hash);

        if (self.string_map.get(hash)) |existing_id| {
            return existing_id;
        }

        const string_id: StringId = @enumFromInt(self.next_id);
        self.next_id += 1;

        const owned_string = try self.allocator.dupe(u8, string);
        try self.strings.append(owned_string);
        try self.string_map.put(hash, string_id);
        return string_id;
    }

    pub fn getString(self: *SymbolInterner, string_id: StringId) []const u8 {
        const index: u32 = @intFromEnum(string_id);
        if (index >= self.strings.items.len) return "";
        return self.strings.items[index];
    }
};

test "symbol table basic operations" {
    const allocator = std.testing.allocator;
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();

    try std.testing.expect(!symbol_table.contains("test_symbol"));
    try std.testing.expect(!symbol_table.isDuplicate("test_symbol"));
}
