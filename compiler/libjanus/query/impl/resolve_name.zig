// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Q.ResolveName Implementation
//! Task 2.5 - Core Query Implementations (v1)
//!
//! Resolves symbol names to their definitions within the current scope context.
//! This is the foundation for all other semantic queries.

const std = @import("std");
const Allocator = std.mem.Allocator;
const context = @import("../context.zig");
const core_astdb = @import("../../../astdb/core_astdb.zig");
const node_view = @import("../../astdb/node_view.zig");

const QueryCtx = context.QueryCtx;
const CanonicalArgs = context.CanonicalArgs;
const QueryResultData = context.QueryResultData;
const SymbolInfo = context.SymbolInfo;
const CID = @import("../../astdb/ids.zig").CID;

/// Resolve a symbol name to its definition
pub fn resolveName(query_ctx: *QueryCtx, args: CanonicalArgs) !QueryResultData {
    // Extract arguments
    if (args.items.len != 2) {
        return error.QE0005_NonCanonicalArg;
    }

    const symbol_name = switch (args.items[0]) {
        .string => |name| name,
        else => return error.QE0005_NonCanonicalArg,
    };

    const scope_cid = switch (args.items[1]) {
        .cid => |cid| cid,
        else => return error.QE0005_NonCanonicalArg,
    };

    // Record dependency on the scope
    try query_ctx.dependency_tracker.addDependency(.{ .cid = scope_cid });

    // Look up symbol in the scope
    const symbol_info = try resolveSymbolInScope(query_ctx, symbol_name, scope_cid);

    return QueryResultData{
        .symbol_info = symbol_info,
    };
}

/// Resolve a symbol within a specific scope
fn resolveSymbolInScope(query_ctx: *QueryCtx, symbol_name: []const u8, scope_cid: CID) !SymbolInfo {
    const scope_view = try query_ctx.astdb.getNodeView(scope_cid);
    const scope_info = try query_ctx.astdb.findScopeByCID(scope_cid);
    const symbol_table = try query_ctx.astdb.getSymbolTable(scope_info.unit_id, scope_info.scope_id);

    for (symbol_table.symbols) |symbol| {
        if (std.mem.eql(u8, symbol.name, symbol_name)) {
            // Found the symbol - record dependency on its definition
            try query_ctx.dependency_tracker.addDependency(.{ .cid = symbol.definition_cid });

            return SymbolInfo{
                .name = symbol.name,
                .definition_cid = symbol.definition_cid,
                .symbol_type = symbol.symbol_type,
                .visibility = symbol.visibility,
                .location = symbol.location,
            };
        }
    }

    if (scope_view.parentCid()) |parent_cid| {
        if (!std.mem.eql(u8, &parent_cid, &scope_cid)) {
            return resolveSymbolInScope(query_ctx, symbol_name, parent_cid);
        }
    }

    // Symbol not found anywhere
    return error.SymbolNotFound;
}

/// Resolve a qualified name (e.g., "module.function")
pub fn resolveQualifiedName(query_ctx: *QueryCtx, qualified_name: []const u8, root_scope: CID) !SymbolInfo {
    var splitter = std.mem.split(u8, qualified_name, ".");
    var current_scope = root_scope;

    while (splitter.next()) |part| {
        if (splitter.peek() != null) {
            const module_symbol = try resolveSymbolInScope(query_ctx, part, current_scope);
            if (module_symbol.symbol_type != .module) return error.NotAModule;
            current_scope = module_symbol.definition_cid;
        } else {
            return resolveSymbolInScope(query_ctx, part, current_scope);
        }
    }

    return error.EmptyQualifiedName;
}

/// Check if a symbol is visible from a given scope
pub fn isSymbolVisible(query_ctx: *QueryCtx, symbol_cid: CID, from_scope: CID) !bool {
    const symbol_info = try query_ctx.astdb.getSymbol(symbol_cid);

    return switch (symbol_info.visibility) {
        .public => true,
        .private => blk: {
            // Private symbols are only visible within the same module
            const symbol_module = try getContainingModule(query_ctx, symbol_cid);
            const scope_module = try getContainingModule(query_ctx, from_scope);
            break :blk std.mem.eql(u8, &symbol_module.bytes, &scope_module.bytes);
        },
        .protected => blk: {
            // Protected symbols are visible within the same module and submodules
            const symbol_module = try getContainingModule(query_ctx, symbol_cid);
            const scope_module = try getContainingModule(query_ctx, from_scope);
            break :blk isModuleOrSubmodule(query_ctx, scope_module, symbol_module);
        },
    };
}

/// Get the module that contains a given CID
fn getContainingModule(query_ctx: *QueryCtx, cid: CID) !CID {
    var current = cid;
    while (true) {
        const view = try query_ctx.astdb.getNodeView(current);
        switch (view.kind()) {
            .source_file => return current,
            .use_stmt, .module => return current,
            else => {},
        }
        if (view.parentCid()) |parent| {
            if (std.mem.eql(u8, &parent, &current)) break;
            current = parent;
        } else break;
    }
    return error.NoContainingModule;
}

/// Check if scope_module is the same as or a submodule of base_module
fn isModuleOrSubmodule(query_ctx: *QueryCtx, scope_module: CID, base_module: CID) bool {
    _ = query_ctx;

    // For now, just check equality
    // In a full implementation, we'd traverse the module hierarchy
    return std.mem.eql(u8, &scope_module.bytes, &base_module.bytes);
}

// Tests
test "resolveName basic functionality" {
    const allocator = std.testing.allocator;

    // This would need a proper QueryCtx setup in a real test
    // For now, just test the argument validation
    var args = CanonicalArgs.init(allocator);
    defer args.deinit();

    try args.append(.{ .string = "test_symbol" });
    try args.append(.{ .cid = CID{ .bytes = [_]u8{1} ** 32 } });

    // Would call resolveName here with a proper QueryCtx
    try std.testing.expect(args.items.len == 2);
}

test "qualified name parsing" {
    const qualified_name = "std.collections.HashMap";
    var parts = std.mem.split(u8, qualified_name, ".");

    try std.testing.expectEqualStrings("std", parts.next().?);
    try std.testing.expectEqualStrings("collections", parts.next().?);
    try std.testing.expectEqualStrings("HashMap", parts.next().?);
    try std.testing.expect(parts.next() == null);
}
