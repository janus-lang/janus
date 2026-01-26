// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Import Resolver - Resolves import statements to file paths
//!
//! Given an AST, extracts all import statements and resolves them to
//! actual file paths that can be compiled.

const std = @import("std");
const astdb_core = @import("astdb_core");
const Snapshot = astdb_core.Snapshot;
const NodeId = astdb_core.NodeId;
const UnitId = astdb_core.UnitId;

pub const ImportInfo = struct {
    /// Module path components (e.g., ["std", "string"] for "import std.string")
    path_components: []const []const u8,
    /// Resolved file path (if found)
    resolved_path: ?[]const u8,
    /// The AST node for this import
    node_id: NodeId,
};

pub const ImportResolver = struct {
    allocator: std.mem.Allocator,
    imports: std.ArrayListUnmanaged(ImportInfo),
    search_paths: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator) ImportResolver {
        return .{
            .allocator = allocator,
            .imports = .{},
            .search_paths = .{},
        };
    }

    pub fn deinit(self: *ImportResolver) void {
        for (self.imports.items) |import_info| {
            for (import_info.path_components) |comp| {
                self.allocator.free(comp);
            }
            self.allocator.free(import_info.path_components);
            if (import_info.resolved_path) |path| {
                self.allocator.free(path);
            }
        }
        self.imports.deinit(self.allocator);

        for (self.search_paths.items) |path| {
            self.allocator.free(path);
        }
        self.search_paths.deinit(self.allocator);
    }

    /// Add a directory to search for imported modules
    pub fn addSearchPath(self: *ImportResolver, path: []const u8) !void {
        const owned = try self.allocator.dupe(u8, path);
        try self.search_paths.append(self.allocator, owned);
    }

    /// Extract all import statements from a compilation unit
    pub fn extractImports(self: *ImportResolver, snapshot: *const Snapshot, unit_id: UnitId) !void {
        const unit = snapshot.astdb.getUnitConst(unit_id) orelse return error.InvalidUnitId;

        for (unit.nodes, 0..) |node, i| {
            if (node.kind == .import_stmt) {
                const node_id: NodeId = @enumFromInt(@as(u32, @intCast(i)));
                try self.processImportNode(snapshot, node_id, &node);
            }
        }
    }

    fn processImportNode(self: *ImportResolver, snapshot: *const Snapshot, node_id: NodeId, node: *const astdb_core.AstNode) !void {
        // Import children are the path components (identifiers)
        const children = snapshot.getChildren(node_id);
        if (children.len == 0) return;

        var path_components = std.ArrayListUnmanaged([]const u8){};
        errdefer {
            for (path_components.items) |comp| {
                self.allocator.free(comp);
            }
            path_components.deinit(self.allocator);
        }

        for (children) |child_id| {
            const child = snapshot.getNode(child_id) orelse continue;
            if (child.kind == .identifier) {
                const token = snapshot.getToken(child.first_token) orelse continue;
                if (token.str) |str_id| {
                    const name = snapshot.astdb.str_interner.getString(str_id);
                    const owned_name = try self.allocator.dupe(u8, name);
                    try path_components.append(self.allocator, owned_name);
                }
            }
        }

        if (path_components.items.len == 0) return;

        // Try to resolve the file path
        const resolved = try self.resolveModulePath(path_components.items);

        _ = node;
        try self.imports.append(self.allocator, .{
            .path_components = try path_components.toOwnedSlice(self.allocator),
            .resolved_path = resolved,
            .node_id = node_id,
        });
    }

    /// Resolve a module path to a file path
    /// e.g., ["mathlib"] -> "./mathlib.jan" or "lib/mathlib.jan"
    fn resolveModulePath(self: *ImportResolver, components: []const []const u8) !?[]const u8 {
        if (components.len == 0) return null;

        // Build the relative path: components joined by '/' + ".jan"
        var path_buf = std.ArrayListUnmanaged(u8){};
        defer path_buf.deinit(self.allocator);

        for (components, 0..) |comp, i| {
            if (i > 0) try path_buf.append(self.allocator, '/');
            try path_buf.appendSlice(self.allocator, comp);
        }
        try path_buf.appendSlice(self.allocator, ".jan");

        const relative_path = try path_buf.toOwnedSlice(self.allocator);
        defer self.allocator.free(relative_path);

        // Try each search path
        for (self.search_paths.items) |search_path| {
            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ search_path, relative_path });

            // Check if file exists
            if (std.fs.cwd().access(full_path, .{})) |_| {
                return full_path;
            } else |_| {
                self.allocator.free(full_path);
            }
        }

        // Try current directory
        if (std.fs.cwd().access(relative_path, .{})) |_| {
            return try self.allocator.dupe(u8, relative_path);
        } else |_| {}

        return null;
    }

    /// Get all resolved import paths
    pub fn getResolvedPaths(self: *const ImportResolver) []const ?[]const u8 {
        var paths = self.allocator.alloc(?[]const u8, self.imports.items.len) catch return &[_]?[]const u8{};
        for (self.imports.items, 0..) |import_info, i| {
            paths[i] = import_info.resolved_path;
        }
        return paths;
    }

    /// Get module name from import (first component or joined path)
    pub fn getModuleName(self: *const ImportResolver, index: usize) ?[]const u8 {
        if (index >= self.imports.items.len) return null;
        const import_info = self.imports.items[index];
        if (import_info.path_components.len == 0) return null;
        return import_info.path_components[import_info.path_components.len - 1];
    }
};

test "ImportResolver basic" {
    const allocator = std.testing.allocator;
    var resolver = ImportResolver.init(allocator);
    defer resolver.deinit();

    try resolver.addSearchPath(".");
    try resolver.addSearchPath("lib");
}
