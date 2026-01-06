// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const core = @import("astdb_core");

/// Minimal binder: discovers declarations in ASTDB units
/// and populates unit.decls and global scope linkage.
/// Supports: func_decl, let_stmt, var_stmt, const_stmt
pub fn bindAll(db: *core.AstDB) !void {
    // Iterate over physical unit indices; index is the UnitId
    for (db.units.items, 0..) |unit, idx| {
        _ = unit; // we use idx as the id
        const uid: core.UnitId = @enumFromInt(@as(u32, @intCast(idx)));
        const u = db.getUnit(uid) orelse continue;
        if (u.is_removed) continue;
        try bindUnit(db, uid);
    }
}

/// Minimal binder: discovers declarations in ASTDB units
/// and populates unit.decls and global scope linkage.
/// Supports: func_decl, let_stmt, var_stmt, const_stmt
pub fn bindUnit(db: *core.AstDB, unit_id: core.UnitId) !void {
    const unit = db.getUnit(unit_id) orelse return;
    const arena = unit.arenaAllocator();

    // Ensure a global scope exists
    if (unit.scopes.len == 0) {
        unit.scopes = try arena.alloc(core.Scope, 1);
        unit.scopes[0] = core.Scope{ .parent = null, .first_decl = null, .kind = .global };
    }

    // Count all declaration nodes
    var count: usize = 0;
    for (unit.nodes) |nd| {
        switch (nd.kind) {
            .func_decl, .let_stmt, .var_stmt, .const_stmt => count += 1,
            else => {},
        }
    }
    if (count == 0) return;

    // Allocate decls (rebuild)
    unit.decls = try arena.alloc(core.Decl, count);
    unit.scopes[0].first_decl = null;

    // Extract names and fill decls; chain in scope
    var prev: ?core.DeclId = null;
    var idx: usize = 0;
    for (unit.nodes, 0..) |nd, i| {
        const decl_kind: core.Decl.DeclKind = switch (nd.kind) {
            .func_decl => .function,
            .let_stmt => .variable,
            .var_stmt => .variable,
            .const_stmt => .constant,
            else => continue,
        };

        const name_sid = extractDeclName(db, unit_id, @enumFromInt(@as(u32, @intCast(i)))) catch |err| {
            std.log.warn("Binder: Failed to extract name for node {d}: {s}", .{ i, @errorName(err) });
            continue;
        };

        unit.decls[idx] = core.Decl{
            .node = @enumFromInt(@as(u32, @intCast(i))),
            .name = name_sid,
            .scope = @enumFromInt(0),
            .kind = decl_kind,
            .next_in_scope = null,
        };
        const did: core.DeclId = @enumFromInt(@as(u32, @intCast(idx)));
        if (prev) |p| {
            unit.decls[@intFromEnum(p)].next_in_scope = did;
        } else {
            unit.scopes[0].first_decl = did;
        }
        prev = did;
        idx += 1;
    }
}

/// Extract declaration name from any declaration node
/// Supports: func_decl, let_stmt, var_stmt, const_stmt
fn extractDeclName(db: *core.AstDB, unit_id: core.UnitId, node_id: core.NodeId) !core.StrId {
    const unit = db.getUnit(unit_id) orelse return error.InvalidNode;
    const nd = unit.nodes[@intFromEnum(node_id)];
    const start_index = @intFromEnum(nd.first_token);

    // Scan forward to find the first identifier token
    // For func: `func <name> (...)`
    // For let/var/const: `let <name> = ...` or `let <name>: Type = ...`
    var i = start_index + 1;
    while (i < unit.tokens.len) : (i += 1) {
        const tok = unit.tokens[i];
        if (tok.kind == .identifier) {
            if (tok.str) |sid| return sid;
            // Fallback: extract from source span
            const s: usize = tok.span.start;
            const e: usize = tok.span.end;
            if (e <= unit.source.len and s < e) {
                return db.internString(unit.source[s..e]);
            }
            break;
        }
        // Stop scan if we pass certain delimiters
        if (tok.kind == .left_paren or tok.kind == .colon or tok.kind == .assign) break;
    }
    // Fallback: intern "anonymous"
    return db.internString("anonymous");
}
