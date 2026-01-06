// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ConversionPath = @import("conversion_registry.zig").ConversionPath;
const Conversion = @import("conversion_registry.zig").Conversion;

/// RAII wrapper for ConversionPath that ensures exactly-once cleanup
/// Eliminates double-free issues in cross-component scenarios
pub const ScopedConversionPath = struct {
    path: ConversionPath,
    is_owned: bool,
    allocator: Allocator,

    /// Create a scoped path that owns its data
    pub fn owned(allocator: Allocator) ScopedConversionPath {
        return ScopedConversionPath{
            .path = ConversionPath.init(allocator),
            .is_owned = true,
            .allocator = allocator,
        };
    }

    /// Create a scoped path from an existing path (takes ownership)
    pub fn fromPath(path: ConversionPath) ScopedConversionPath {
        return ScopedConversionPath{
            .path = path,
            .is_owned = true,
            .allocator = path.allocator,
        };
    }

    /// Create a non-owning view of an existing path
    pub fn view(path: *const ConversionPath) ScopedConversionPath {
        return ScopedConversionPath{
            .path = path.*,
            .is_owned = false,
            .allocator = path.allocator,
        };
    }

    /// Clone the path, creating a new owned instance
    pub fn clone(self: *const ScopedConversionPath, allocator: Allocator) !ScopedConversionPath {
        const cloned_path = try self.path.clone(allocator);
        return ScopedConversionPath{
            .path = cloned_path,
            .is_owned = true,
            .allocator = allocator,
        };
    }

    /// Release ownership without cleanup (for transferring ownership)
    pub fn release(self: *ScopedConversionPath) ConversionPath {
        self.is_owned = false;
        return self.path;
    }

    /// Get a non-owning reference to the path
    pub fn get(self: *const ScopedConversionPath) *const ConversionPath {
        return &self.path;
    }

    /// Get a mutable reference to the path (only if owned)
    pub fn getMut(self: *ScopedConversionPath) *ConversionPath {
        std.debug.assert(self.is_owned);
        return &self.path;
    }

    /// Add a conversion to the path (only if owned)
    pub fn addConversion(self: *ScopedConversionPath, conversion: Conversion) !void {
        std.debug.assert(self.is_owned);
        try self.path.addConversion(conversion);
    }

    /// RAII cleanup - called automatically when scope ends
    pub fn deinit(self: *ScopedConversionPath) void {
        if (self.is_owned) {
            self.path.deinit();
            self.is_owned = false;
        }
    }
};

/// Arena-based temporary conversion path manager
/// Use for ephemeral paths during resolution that don't need to outlive the arena
pub const ConversionArena = struct {
    arena: std.heap.ArenaAllocator,
    paths: std.ArrayList(ConversionPath),

    pub fn init(backing_allocator: Allocator) ConversionArena {
        return ConversionArena{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
            .paths = std.ArrayList(ConversionPath).init(backing_allocator),
        };
    }

    pub fn deinit(self: *ConversionArena) void {
        self.paths.deinit();
        self.arena.deinit();
    }

    /// Create a temporary conversion path that will be cleaned up with the arena
    pub fn createPath(self: *ConversionArena) !*ConversionPath {
        const arena_allocator = self.arena.allocator();
        const path = ConversionPath.init(arena_allocator);
        try self.paths.append(path);
        return &self.paths.items[self.paths.items.len - 1];
    }

    /// Clone a path into the arena (temporary copy)
    pub fn clonePath(self: *ConversionArena, source: *const ConversionPath) !*ConversionPath {
        const arena_allocator = self.arena.allocator();
        const cloned = try source.clone(arena_allocator);
        try self.paths.append(cloned);
        return &self.paths.items[self.paths.items.len - 1];
    }

    /// Get the arena allocator for temporary allocations
    pub fn allocator(self: *ConversionArena) Allocator {
        return self.arena.allocator();
    }
};

// Tests
test "ScopedConversionPath RAII" {
    var scoped = ScopedConversionPath.owned(std.testing.allocator);
    defer scoped.deinit();

    // Test that we can add conversions
    const conversion = Conversion{
        .from = @import("type_registry.zig").TypeId.I32,
        .to = @import("type_registry.zig").TypeId.F64,
        .cost = 5,
        .is_lossy = false,
        .method = .builtin_cast,
        .syntax_template = "{} as f64",
    };

    try scoped.addConversion(conversion);
    try std.testing.expect(scoped.get().conversions.len == 1);
    try std.testing.expect(scoped.get().total_cost == 5);
}

test "ScopedConversionPath view (non-owning)" {
    var owned = ScopedConversionPath.owned(std.testing.allocator);
    defer owned.deinit();

    // Create a view that doesn't own the data
    var view = ScopedConversionPath.view(owned.get());
    defer view.deinit(); // Should be safe to call, but won't actually free

    try std.testing.expect(view.get().conversions.len == 0);
}

test "ScopedConversionPath clone" {
    var original = ScopedConversionPath.owned(std.testing.allocator);
    defer original.deinit();

    const conversion = Conversion{
        .from = @import("type_registry.zig").TypeId.I32,
        .to = @import("type_registry.zig").TypeId.F64,
        .cost = 5,
        .is_lossy = false,
        .method = .builtin_cast,
        .syntax_template = "{} as f64",
    };

    try original.addConversion(conversion);

    var cloned = try original.clone(std.testing.allocator);
    defer cloned.deinit();

    try std.testing.expect(cloned.get().conversions.len == 1);
    try std.testing.expect(cloned.get().total_cost == 5);
}

test "ConversionArena temporary paths" {
    var arena = ConversionArena.init(std.testing.allocator);
    defer arena.deinit();

    // Create temporary paths
    const path1 = try arena.createPath();
    const path2 = try arena.createPath();

    try std.testing.expect(path1 != path2);
    try std.testing.expect(path1.conversions.len == 0);
    try std.testing.expect(path2.conversions.len == 0);

    // Arena cleanup handles all paths automatically
}
