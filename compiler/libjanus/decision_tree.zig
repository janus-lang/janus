// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;

/// Decision tree node for efficient subtype-based dispatch
pub const DecisionNode = struct {
    /// Type being tested at this node
    type_id: TypeId,
    /// Parameter index being tested (for multi-parameter dispatch)
    param_index: u32,
    /// Implementation to use if this type matches exactly
    exact_impl: ?*const Implementation,
    /// Child nodes for more specific subtypes
    children: ArrayList(*DecisionNode),
    /// Fallback implementation for this type and all its subtypes
    fallback_impl: ?*const Implementation,
    /// Parent node (null for root)
    parent: ?*DecisionNode,

    const Self = @This();

    pub fn init(allocator: Allocator, type_id: TypeId, param_index: u32) !*Self {
        const node = try allocator.create(Self);
        node.* = Self{
            .type_id = type_id,
            .param_index = param_index,
            .exact_impl = null,
            .children = ArrayList(*DecisionNode).init(allocator),
            .fallback_impl = null,
            .parent = null,
        };
        return node;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }
        self.children.deinit();
    }

    /// Add a child node for a more specific subtype
    pub fn addChild(self: *Self, child: *DecisionNode) !void {
        child.parent = self;
        try self.children.append(child);
    }

    /// Find the most specific matching implementation for given argument types
    pub fn findMatch(self: *Self, registry: *const TypeRegistry, arg_types: []const TypeId) ?*const Implementation {
        if (self.param_index >= arg_types.len) return self.fallback_impl;

        const arg_type = arg_types[self.param_index];

        // Check for exact match first
        if (arg_type == self.type_id and self.exact_impl != null) {
            return self.exact_impl;
        }

        // Check if argument type is a subtype of this node's type
        if (!registry.isSubtype(arg_type, self.type_id)) {
            return null; // This branch doesn't match
        }

        // Try children first (more specific matches)
        for (self.children.items) |child| {
            if (child.findMatch(registry, arg_types)) |impl| {
                return impl;
            }
        }

        // Fall back to this node's implementation
        return self.fallback_impl;
    }

    /// Get depth of this node in the tree
    pub fn getDepth(self: *const Self) u32 {
        var depth: u32 = 0;
        var current = self.parent;
        while (current) |node| {
            depth += 1;
            current = node.parent;
        }
        return depth;
    }
};

/// Implementation reference with metadata
pub const Implementation = struct {
    /// Unique identifier for this implementation
    id: u32,
    /// Function pointer or reference
    func_ptr: *const anyopaque,
    /// Parameter types for this implementation
    param_types: []const TypeId,
    /// Source location for debugging
    source_location: SourceLocation,
    /// Performance metrics
    call_count: u64 = 0,
    total_time_ns: u64 = 0,

    pub const SourceLocation = struct {
        file: []const u8,
        line: u32,
        column: u32,
    };

    /// Calculate average execution time
    pub fn getAverageTimeNs(self: *const Implementation) f64 {
        if (self.call_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.call_count));
    }
};

/// Decision tree for efficient subtype-based dispatch
pub const DecisionTree = struct {
    allocator: Allocator,
    /// Root nodes for each parameter position
    roots: ArrayList(*DecisionNode),
    /// All implementations indexed by ID
    implementations: std.AutoHashMap(u32, *Implementation),
    /// Type registry for subtype queries
    registry: *const TypeRegistry,
    /// Performance statistics
    stats: Statistics,

    pub const Statistics = struct {
        total_lookups: u64 = 0,
        cache_hits: u64 = 0,
        tree_traversals: u64 = 0,
        max_depth_reached: u32 = 0,
        avg_traversal_depth: f64 = 0.0,

        pub fn getCacheHitRate(self: *const Statistics) f64 {
            if (self.total_lookups == 0) return 0.0;
            return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(self.total_lookups));
        }
    };

    const Self = @This();

    pub fn init(allocator: Allocator, registry: *const TypeRegistry) Self {
        return Self{
            .allocator = allocator,
            .roots = ArrayList(*DecisionNode).init(allocator),
            .implementations = std.AutoHashMap(u32, *Implementation).init(allocator),
            .registry = registry,
            .stats = Statistics{},
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up all nodes
        for (self.roots.items) |root| {
            root.deinit(self.allocator);
            self.allocator.destroy(root);
        }
        self.roots.deinit();

        // Clean up implementations
        var impl_iter = self.implementations.iterator();
        while (impl_iter.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.implementations.deinit();
    }

    /// Build decision tree from a set of implementations
    pub fn buildTree(self: *Self, implementations: []const Implementation) !void {
        // Clear existing tree
        for (self.roots.items) |root| {
            root.deinit(self.allocator);
            self.allocator.destroy(root);
        }
        self.roots.clearRetainingCapacity();

        // Store implementations
        for (implementations) |impl| {
            const stored_impl = try self.allocator.create(Implementation);
            stored_impl.* = impl;
            try self.implementations.put(impl.id, stored_impl);
        }

        // Group implementations by parameter count
        var param_counts = std.AutoHashMap(u32, ArrayList(*const Implementation)).init(self.allocator);
        defer {
            var iter = param_counts.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            param_counts.deinit();
        }

        for (implementations) |*impl| {
            const param_count = @as(u32, @intCast(impl.param_types.len));
            var list = param_counts.get(param_count) orelse ArrayList(*const Implementation).init(self.allocator);
            try list.append(impl);
            try param_counts.put(param_count, list);
        }

        // Build trees for each parameter count
        var iter = param_counts.iterator();
        while (iter.next()) |entry| {
            const param_count = entry.key_ptr.*;
            const impls = entry.value_ptr.items;

            try self.buildTreeForParamCount(param_count, impls);
        }
    }

    /// Build decision tree for implementations with specific parameter count
    fn buildTreeForParamCount(self: *Self, param_count: u32, implementations: []*const Implementation) !void {
        _ = param_count; // Parameter count is implicit in the implementations
        if (implementations.len == 0) return;

        // Create a single root node that handles all parameters
        const root = try DecisionNode.init(self.allocator, TypeRegistry.INVALID_TYPE_ID, 0);
        try self.roots.append(root);

        // Build tree starting from parameter 0
        try self.buildSubtree(root, implementations, 0);
    }

    /// Recursively build subtree for a parameter position
    fn buildSubtree(self: *Self, node: *DecisionNode, implementations: []*const Implementation, param_idx: u32) !void {
        if (implementations.len == 0) return;

        // If we've processed all parameters, store the implementation
        if (param_idx >= implementations[0].param_types.len) {
            if (implementations.len == 1) {
                node.exact_impl = implementations[0];
            } else {
                node.fallback_impl = self.findMostGeneral(implementations);
            }
            return;
        }

        // Group implementations by type at this parameter position
        var type_groups = std.AutoHashMap(TypeId, ArrayList(*const Implementation)).init(self.allocator);
        defer {
            var iter = type_groups.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            type_groups.deinit();
        }

        for (implementations) |impl| {
            if (param_idx >= impl.param_types.len) continue;

            const type_id = impl.param_types[param_idx];
            var list = type_groups.get(type_id) orelse ArrayList(*const Implementation).init(self.allocator);
            try list.append(impl);
            try type_groups.put(type_id, list);
        }

        // Create child nodes for each type
        var iter = type_groups.iterator();
        while (iter.next()) |entry| {
            const type_id = entry.key_ptr.*;
            const type_impls = entry.value_ptr.items;

            const child = try DecisionNode.init(self.allocator, type_id, param_idx);
            try node.addChild(child);

            // Recursively build subtree for next parameter
            try self.buildSubtree(child, type_impls, param_idx + 1);
        }
    }

    /// Check if implementation is an exact match for the given type at parameter position
    fn isExactMatch(self: *Self, impl: *const Implementation, param_idx: u32, type_id: TypeId) bool {
        _ = self;
        if (param_idx >= impl.param_types.len) return false;
        return impl.param_types[param_idx] == type_id;
    }

    /// Find the most general implementation from a list
    fn findMostGeneral(self: *Self, implementations: []*const Implementation) *const Implementation {
        if (implementations.len == 0) return implementations[0];

        var most_general = implementations[0];
        var min_specificity: u32 = std.math.maxInt(u32);

        for (implementations) |impl| {
            const specificity = self.calculateSpecificity(impl);
            if (specificity < min_specificity) {
                min_specificity = specificity;
                most_general = impl;
            }
        }

        return most_general;
    }

    /// Calculate specificity score for an implementation
    fn calculateSpecificity(self: *Self, impl: *const Implementation) u32 {
        var score: u32 = 0;
        for (impl.param_types) |type_id| {
            // Use the type's inherent specificity weight
            if (self.registry.getTypeInfo(type_id)) |type_info| {
                score += type_info.kind.specificityWeight();
            }
        }
        return score;
    }

    /// Find matching implementation using decision tree traversal
    pub fn findImplementation(self: *Self, arg_types: []const TypeId) ?*const Implementation {
        self.stats.total_lookups += 1;

        if (self.roots.items.len == 0) return null;

        // Try each root (different parameter counts)
        for (self.roots.items) |root| {
            if (self.findMatchInSubtree(root, arg_types, 0)) |impl| {
                self.stats.tree_traversals += 1;
                self.updateTraversalStats(root, arg_types);
                return impl;
            }
        }

        return null;
    }

    /// Find match in subtree starting from given node and parameter index
    fn findMatchInSubtree(self: *Self, node: *DecisionNode, arg_types: []const TypeId, param_idx: u32) ?*const Implementation {
        // If we've matched all parameters, return the implementation
        if (param_idx >= arg_types.len) {
            return node.exact_impl orelse node.fallback_impl;
        }

        const arg_type = arg_types[param_idx];

        // Look for exact match in children first
        for (node.children.items) |child| {
            if (child.type_id == arg_type) {
                if (self.findMatchInSubtree(child, arg_types, param_idx + 1)) |impl| {
                    return impl;
                }
            }
        }

        // Look for subtype matches in children
        for (node.children.items) |child| {
            if (self.registry.isSubtype(arg_type, child.type_id)) {
                if (self.findMatchInSubtree(child, arg_types, param_idx + 1)) |impl| {
                    return impl;
                }
            }
        }

        // Look for wildcard/any matches (types that accept any argument)
        for (node.children.items) |child| {
            // Check if this child's type is a supertype of the argument (more general)
            if (self.registry.isSubtype(child.type_id, arg_type) or
                self.isWildcardType(child.type_id))
            {
                if (self.findMatchInSubtree(child, arg_types, param_idx + 1)) |impl| {
                    return impl;
                }
            }
        }

        // No match found
        return null;
    }

    /// Check if a type is a wildcard type that matches any argument
    fn isWildcardType(self: *Self, type_id: TypeId) bool {
        // Check if this is our "any" type by looking at the type name
        if (self.registry.getTypeInfo(type_id)) |type_info| {
            return std.mem.eql(u8, type_info.name, "any");
        }
        return false;
    }

    /// Update traversal statistics
    fn updateTraversalStats(self: *Self, root: *DecisionNode, arg_types: []const TypeId) void {
        const depth = self.calculateTraversalDepth(root, arg_types);
        if (depth > self.stats.max_depth_reached) {
            self.stats.max_depth_reached = depth;
        }

        // Update running average
        const total_traversals = @as(f64, @floatFromInt(self.stats.tree_traversals));
        const current_avg = self.stats.avg_traversal_depth;
        const new_depth = @as(f64, @floatFromInt(depth));
        self.stats.avg_traversal_depth = (current_avg * (total_traversals - 1.0) + new_depth) / total_traversals;
    }

    /// Calculate depth of traversal for given argument types
    fn calculateTraversalDepth(self: *Self, root: *DecisionNode, arg_types: []const TypeId) u32 {
        _ = self;
        _ = arg_types;
        // Simplified depth calculation - in practice would track actual traversal
        return root.getDepth() + 1;
    }

    /// Get performance statistics
    pub fn getStatistics(self: *const Self) Statistics {
        return self.stats;
    }

    /// Reset performance statistics
    pub fn resetStatistics(self: *Self) void {
        self.stats = Statistics{};
    }

    /// Print tree structure for debugging
    pub fn printTree(self: *const Self, writer: anytype) !void {
        try writer.print("Decision Tree ({} roots):\n", .{self.roots.items.len});
        for (self.roots.items, 0..) |root, i| {
            try writer.print("Root {}: ", .{i});
            try self.printNode(writer, root, 0);
        }
    }

    /// Print node and its children recursively
    fn printNode(self: *const Self, writer: anytype, node: *const DecisionNode, indent: u32) !void {
        var i: u32 = 0;
        while (i < indent) : (i += 1) {
            try writer.print("  ");
        }

        try writer.print("Type {} (param {})", .{ node.type_id, node.param_index });
        if (node.exact_impl != null) {
            try writer.print(" [exact: {}]", .{node.exact_impl.?.id});
        }
        if (node.fallback_impl != null) {
            try writer.print(" [fallback: {}]", .{node.fallback_impl.?.id});
        }
        try writer.print("\n");

        for (node.children.items) |child| {
            try self.printNode(writer, child, indent + 1);
        }
    }
};

// Tests
test "DecisionTree basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = try TypeRegistry.init(allocator);
    defer registry.deinit();

    // Register some test types
    const int_type = try registry.registerType("int", .primitive, &.{});
    const float_type = try registry.registerType("float", .primitive, &.{});
    const string_type = try registry.registerType("string", .primitive, &.{});

    var tree = DecisionTree.init(allocator, &registry);
    defer tree.deinit();

    // Create test implementations
    const impl1 = Implementation{
        .id = 1,
        .func_ptr = @ptrCast(&testing.expect),
        .param_types = &[_]TypeId{int_type},
        .source_location = .{ .file = "test.janus", .line = 1, .column = 1 },
    };

    const impl2 = Implementation{
        .id = 2,
        .func_ptr = @ptrCast(&testing.expect),
        .param_types = &[_]TypeId{float_type},
        .source_location = .{ .file = "test.janus", .line = 2, .column = 1 },
    };

    const implementations = [_]Implementation{ impl1, impl2 };
    try tree.buildTree(&implementations);

    // Test finding implementations
    const int_args = [_]TypeId{int_type};
    const found_int = tree.findImplementation(&int_args);
    try testing.expect(found_int != null);
    try testing.expectEqual(@as(u32, 1), found_int.?.id);

    const float_args = [_]TypeId{float_type};
    const found_float = tree.findImplementation(&float_args);
    try testing.expect(found_float != null);
    try testing.expectEqual(@as(u32, 2), found_float.?.id);

    // Test non-matching type
    const string_args = [_]TypeId{string_type};
    const found_string = tree.findImplementation(&string_args);
    try testing.expect(found_string == null);
}

test "DecisionTree subtype matching" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = try TypeRegistry.init(allocator);
    defer registry.deinit();

    // Register type hierarchy: Animal -> Dog -> Puppy
    const animal_type = try registry.registerType("Animal", .table_open, &.{});
    const dog_type = try registry.registerType("Dog", .table_open, &[_]TypeId{animal_type});
    const puppy_type = try registry.registerType("Puppy", .table_sealed, &[_]TypeId{dog_type});

    // Subtype relationships are set up during registration

    var tree = DecisionTree.init(allocator, &registry);
    defer tree.deinit();

    // Create implementations for different specificity levels
    const animal_impl = Implementation{
        .id = 1,
        .func_ptr = @ptrCast(&testing.expect),
        .param_types = &[_]TypeId{animal_type},
        .source_location = .{ .file = "test.janus", .line = 1, .column = 1 },
    };

    const dog_impl = Implementation{
        .id = 2,
        .func_ptr = @ptrCast(&testing.expect),
        .param_types = &[_]TypeId{dog_type},
        .source_location = .{ .file = "test.janus", .line = 2, .column = 1 },
    };

    const implementations = [_]Implementation{ animal_impl, dog_impl };
    try tree.buildTree(&implementations);

    // Test that puppy matches dog implementation (more specific)
    const puppy_args = [_]TypeId{puppy_type};
    const found_puppy = tree.findImplementation(&puppy_args);
    try testing.expect(found_puppy != null);
    try testing.expectEqual(@as(u32, 2), found_puppy.?.id); // Should match dog_impl

    // Test that dog matches dog implementation
    const dog_args = [_]TypeId{dog_type};
    const found_dog = tree.findImplementation(&dog_args);
    try testing.expect(found_dog != null);
    try testing.expectEqual(@as(u32, 2), found_dog.?.id);

    // Test that animal matches animal implementation
    const animal_args = [_]TypeId{animal_type};
    const found_animal = tree.findImplementation(&animal_args);
    try testing.expect(found_animal != null);
    try testing.expectEqual(@as(u32, 1), found_animal.?.id);
}

test "DecisionTree multi-parameter dispatch" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = try TypeRegistry.init(allocator);
    defer registry.deinit();

    const int_type = try registry.registerType("int", .primitive, &.{});
    const float_type = try registry.registerType("float", .primitive, &.{});
    const string_type = try registry.registerType("string", .primitive, &.{});

    var tree = DecisionTree.init(allocator, &registry);
    defer tree.deinit();

    // Create multi-parameter implementations
    const int_int_impl = Implementation{
        .id = 1,
        .func_ptr = @ptrCast(&testing.expect),
        .param_types = &[_]TypeId{ int_type, int_type },
        .source_location = .{ .file = "test.janus", .line = 1, .column = 1 },
    };

    const int_float_impl = Implementation{
        .id = 2,
        .func_ptr = @ptrCast(&testing.expect),
        .param_types = &[_]TypeId{ int_type, float_type },
        .source_location = .{ .file = "test.janus", .line = 2, .column = 1 },
    };

    // Create an "any" type for testing fallback behavior
    const any_type = try registry.registerType("any", .table_open, &.{});

    const string_any_impl = Implementation{
        .id = 3,
        .func_ptr = @ptrCast(&testing.expect),
        .param_types = &[_]TypeId{ string_type, any_type },
        .source_location = .{ .file = "test.janus", .line = 3, .column = 1 },
    };

    const implementations = [_]Implementation{ int_int_impl, int_float_impl, string_any_impl };
    try tree.buildTree(&implementations);

    // Test exact matches
    const int_int_args = [_]TypeId{ int_type, int_type };
    const found_int_int = tree.findImplementation(&int_int_args);
    try testing.expect(found_int_int != null);
    try testing.expectEqual(@as(u32, 1), found_int_int.?.id);

    const int_float_args = [_]TypeId{ int_type, float_type };
    const found_int_float = tree.findImplementation(&int_float_args);
    try testing.expect(found_int_float != null);
    try testing.expectEqual(@as(u32, 2), found_int_float.?.id);

    // Test fallback matching
    const string_int_args = [_]TypeId{ string_type, int_type };
    const found_string_int = tree.findImplementation(&string_int_args);
    try testing.expect(found_string_int != null);
    try testing.expectEqual(@as(u32, 3), found_string_int.?.id);
}

test "DecisionTree performance statistics" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = try TypeRegistry.init(allocator);
    defer registry.deinit();

    const int_type = try registry.registerType("int", .primitive, &.{});

    var tree = DecisionTree.init(allocator, &registry);
    defer tree.deinit();

    const impl = Implementation{
        .id = 1,
        .func_ptr = @ptrCast(&testing.expect),
        .param_types = &[_]TypeId{int_type},
        .source_location = .{ .file = "test.janus", .line = 1, .column = 1 },
    };

    const implementations = [_]Implementation{impl};
    try tree.buildTree(&implementations);

    // Perform some lookups
    const args = [_]TypeId{int_type};
    _ = tree.findImplementation(&args);
    _ = tree.findImplementation(&args);
    _ = tree.findImplementation(&args);

    const stats = tree.getStatistics();
    try testing.expectEqual(@as(u64, 3), stats.total_lookups);
    try testing.expectEqual(@as(u64, 3), stats.tree_traversals);
}
