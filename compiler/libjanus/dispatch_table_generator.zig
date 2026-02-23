// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;

/// DispatchTableGenerator - Creates compressed multimethod tables for runtime dispatch
///
/// This generator creates efficient dispatch tables that enable O(1) runtime dispatch
/// for common cases and O(log n) dispatch for complex subtype relationships. It uses
/// compressed representations and decision trees to minimize memory usage while
/// maximizing cache locality.
pub const DispatchTableGenerator = struct {
    /// Compressed dispatch table for runtime lookup
    pub const DispatchTable = struct {
        signature_hash: u64,
        implementation_count: u32,

        // Exact match table for O(1) lookup of common cases
        exact_matches: []ExactMatch,

        // Decision tree for subtype-based fallback dispatch
        decision_tree: ?*DecisionTree,

        // Metadata for debugging and optimization
        metadata: TableMetadata,

        pub const ExactMatch = struct {
            type_combination_hash: u64,
            function_id: SignatureAnalyzer.FunctionId,

            pub fn hash(self: ExactMatch) u64 {
                return self.type_combination_hash;
            }

            pub fn eql(self: ExactMatch, other: ExactMatch) bool {
                return self.type_combination_hash == other.type_combination_hash;
            }
        };

        pub const DecisionTree = struct {
            param_index: u8,
            type_branches: std.HashMap(TypeRegistry.TypeId, *DecisionTree, TypeIdContext, std.hash_map.default_max_load_percentage),
            leaf_function: ?SignatureAnalyzer.FunctionId,

            pub const TypeIdContext = struct {
                pub fn hash(self: @This(), key: TypeRegistry.TypeId) u64 {
                    _ = self;
                    return @as(u64, key);
                }

                pub fn eql(self: @This(), a: TypeRegistry.TypeId, b: TypeRegistry.TypeId) bool {
                    _ = self;
                    return a == b;
                }
            };

            pub fn init(allocator: std.mem.Allocator, param_index: u8) DecisionTree {
                return DecisionTree{
                    .param_index = param_index,
                    .type_branches = std.HashMap(TypeRegistry.TypeId, *DecisionTree, TypeIdContext, std.hash_map.default_max_load_percentage).init(allocator),
                    .leaf_function = null,
                };
            }

            pub fn deinit(self: *DecisionTree, allocator: std.mem.Allocator) void {
                var iterator = self.type_branches.iterator();
                while (iterator.next()) |entry| {
                    entry.value_ptr.*.deinit(allocator);
                    allocator.destroy(entry.value_ptr.*);
                }
                self.type_branches.deinit();
            }
        };

        pub const TableMetadata = struct {
            total_memory_bytes: usize,
            exact_match_coverage: f32, // Percentage of calls expected to hit exact matches
            max_tree_depth: u32,
            cache_efficiency_estimate: f32, // 0.0 - 1.0
        };

        pub fn deinit(self: *DispatchTable, allocator: std.mem.Allocator) void {
            allocator.free(self.exact_matches);
            if (self.decision_tree) |tree| {
                tree.deinit(allocator);
                allocator.destroy(tree);
            }
        }
    };

    /// Type combination for hashing and lookup
    pub const TypeCombination = struct {
        types: []const TypeRegistry.TypeId,

        pub fn hash(self: TypeCombination) u64 {
            var hasher = std.hash.Wyhash.init(0);
            for (self.types) |type_id| {
                hasher.update(std.mem.asBytes(&type_id));
            }
            return hasher.final();
        }

        pub fn eql(self: TypeCombination, other: TypeCombination) bool {
            if (self.types.len != other.types.len) return false;
            for (self.types, other.types) |a, b| {
                if (a != b) return false;
            }
            return true;
        }
    };

    /// Statistics about table generation
    pub const GenerationStats = struct {
        total_implementations: usize,
        exact_matches_generated: usize,
        decision_tree_nodes: usize,
        memory_usage_bytes: usize,
        generation_time_ms: u64,
        compression_ratio: f32, // Compared to naive table
    };

    type_registry: *const TypeRegistry,
    signature_analyzer: *SignatureAnalyzer,
    specificity_analyzer: *SpecificityAnalyzer,
    allocator: std.mem.Allocator,

    // Configuration options
    max_exact_matches: usize = 10000, // Limit memory usage
    enable_compression: bool = true,
    optimize_for_cache: bool = true,

    pub fn init(
        allocator: std.mem.Allocator,
        type_registry: *const TypeRegistry,
        signature_analyzer: *SignatureAnalyzer,
        specificity_analyzer: *SpecificityAnalyzer,
    ) DispatchTableGenerator {
        return DispatchTableGenerator{
            .type_registry = type_registry,
            .signature_analyzer = signature_analyzer,
            .specificity_analyzer = specificity_analyzer,
            .allocator = allocator,
        };
    }

    /// Generate dispatch table for a signature group
    pub fn generateTable(
        self: *DispatchTableGenerator,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
    ) !DispatchTable {
        const start_time = std.time.milliTimestamp();

        var table = DispatchTable{
            .signature_hash = self.hashSignature(signature_group),
            .implementation_count = @intCast(signature_group.getImplementationCount()),
            .exact_matches = &.{},
            .decision_tree = null,
            .metadata = undefined,
        };

        // Generate exact matches for common type combinations
        table.exact_matches = try self.generateExactMatches(signature_group);

        // Generate decision tree for subtype-based dispatch
        table.decision_tree = try self.generateDecisionTree(signature_group);

        // Calculate metadata
        const end_time = std.time.milliTimestamp();
        table.metadata = try self.calculateMetadata(&table, signature_group, @intCast(end_time - start_time));

        return table;
    }

    /// Generate exact match entries for common type combinations
    fn generateExactMatches(
        self: *DispatchTableGenerator,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
    ) ![]DispatchTable.ExactMatch {
        var exact_matches: std.ArrayList(DispatchTable.ExactMatch) = .empty;

        // Generate combinations for each implementation
        for (signature_group.implementations.items) |impl| {
            const combinations = try self.enumerateConcreteTypes(impl.param_type_ids);
            defer {
                for (combinations) |combination| {
                    self.allocator.free(combination);
                }
                self.allocator.free(combinations);
            }

            for (combinations) |combination| {
                if (exact_matches.items.len >= self.max_exact_matches) break;

                const type_combo = TypeCombination{ .types = combination };
                const combo_hash = type_combo.hash();

                // Check if this combination is unambiguous
                if (try self.isUnambiguousMatch(signature_group, combination)) {
                    try exact_matches.append(DispatchTable.ExactMatch{
                        .type_combination_hash = combo_hash,
                        .function_id = impl.function_id,
                    });
                }
            }
        }

        // Sort for binary search
        std.sort.insertion(DispatchTable.ExactMatch, exact_matches.items, {}, compareExactMatches);

        return try exact_matches.toOwnedSlice(alloc);
    }

    /// Generate decision tree for subtype-based dispatch
    fn generateDecisionTree(
        self: *DispatchTableGenerator,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
    ) !?*DispatchTable.DecisionTree {
        if (signature_group.getImplementationCount() <= 1) return null;

        const tree = try self.allocator.create(DispatchTable.DecisionTree);
        tree.* = DispatchTable.DecisionTree.init(self.allocator, 0);

        try self.buildDecisionNode(tree, signature_group.implementations.items, 0);

        return tree;
    }

    /// Build a decision tree node recursively
    fn buildDecisionNode(
        self: *DispatchTableGenerator,
        node: *DispatchTable.DecisionTree,
        implementations: []const SignatureAnalyzer.Implementation,
        param_index: u8,
    ) !void {
        if (implementations.len == 0) return;

        if (implementations.len == 1) {
            node.leaf_function = implementations[0].function_id;
            return;
        }

        // If we've exhausted all parameters, pick the most specific
        if (param_index >= implementations[0].param_type_ids.len) {
            // Find most specific implementation
            var most_specific = implementations[0];
            for (implementations[1..]) |impl| {
                if (impl.specificity_rank > most_specific.specificity_rank) {
                    most_specific = impl;
                }
            }
            node.leaf_function = most_specific.function_id;
            return;
        }

        node.param_index = param_index;

        // Group implementations by parameter type at this index
        var type_groups = std.HashMap(TypeRegistry.TypeId, std.ArrayList(SignatureAnalyzer.Implementation), DispatchTable.DecisionTree.TypeIdContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer {
            var iterator = type_groups.iterator();
            while (iterator.next()) |entry| {
                entry.value_ptr.deinit();
            }
            type_groups.deinit();
        }

        for (implementations) |impl| {
            const param_type = impl.param_type_ids[param_index];
            const result = try type_groups.getOrPut(param_type);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(SignatureAnalyzer.Implementation).empty;
            }
            try result.value_ptr.append(impl);
        }

        // Create child nodes for each type
        var type_iterator = type_groups.iterator();
        while (type_iterator.next()) |entry| {
            const param_type = entry.key_ptr.*;
            const type_impls = entry.value_ptr.items;

            const child_node = try self.allocator.create(DispatchTable.DecisionTree);
            child_node.* = DispatchTable.DecisionTree.init(self.allocator, param_index + 1);

            try self.buildDecisionNode(child_node, type_impls, param_index + 1);
            try node.type_branches.put(param_type, child_node);
        }
    }

    /// Enumerate concrete types for a parameter list
    fn enumerateConcreteTypes(self: *DispatchTableGenerator, param_types: []const TypeRegistry.TypeId) ![][]TypeRegistry.TypeId {
        var combinations: std.ArrayList([]TypeRegistry.TypeId) = .empty;

        // For now, just return the exact parameter types
        // In a full implementation, this would generate all concrete subtypes
        const combination = try self.allocator.dupe(TypeRegistry.TypeId, param_types);
        try combinations.append(combination);

        return try combinations.toOwnedSlice(alloc);
    }

    /// Check if a type combination has an unambiguous match
    fn isUnambiguousMatch(
        self: *DispatchTableGenerator,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
        combination: []const TypeRegistry.TypeId,
    ) !bool {
        var result = try self.specificity_analyzer.findMostSpecific(
            signature_group.implementations.items,
            combination,
        );
        defer result.deinit(self.allocator);

        return switch (result) {
            .unique => true,
            .ambiguous, .no_match => false,
        };
    }

    /// Hash a signature group for identification
    fn hashSignature(self: *DispatchTableGenerator, signature_group: *const SignatureAnalyzer.SignatureGroup) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(signature_group.name);
        hasher.update(std.mem.asBytes(&signature_group.key.arity));
        return hasher.final();
    }

    /// Calculate table metadata
    fn calculateMetadata(
        self: *DispatchTableGenerator,
        table: *const DispatchTable,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
        generation_time_ms: u64,
    ) !DispatchTable.TableMetadata {
        _ = generation_time_ms;

        const exact_match_bytes = table.exact_matches.len * @sizeOf(DispatchTable.ExactMatch);
        const tree_bytes = if (table.decision_tree) |tree| self.calculateTreeSize(tree) else 0;
        const total_bytes = exact_match_bytes + tree_bytes;

        // Estimate coverage (simplified)
        const exact_match_coverage = if (signature_group.getImplementationCount() > 0)
            @as(f32, @floatFromInt(table.exact_matches.len)) / @as(f32, @floatFromInt(signature_group.getImplementationCount()))
        else
            0.0;

        return DispatchTable.TableMetadata{
            .total_memory_bytes = total_bytes,
            .exact_match_coverage = @min(exact_match_coverage, 1.0),
            .max_tree_depth = if (table.decision_tree) |tree| self.calculateTreeDepth(tree) else 0,
            .cache_efficiency_estimate = self.estimateCacheEfficiency(table),
        };
    }

    /// Calculate decision tree memory size
    fn calculateTreeSize(self: *DispatchTableGenerator, tree: *const DispatchTable.DecisionTree) usize {
        var size: usize = @sizeOf(DispatchTable.DecisionTree);

        var iterator = tree.type_branches.iterator();
        while (iterator.next()) |entry| {
            size += @sizeOf(TypeRegistry.TypeId) + @sizeOf(*DispatchTable.DecisionTree);
            size += self.calculateTreeSize(entry.value_ptr.*);
        }

        return size;
    }

    /// Calculate maximum tree depth
    fn calculateTreeDepth(self: *DispatchTableGenerator, tree: *const DispatchTable.DecisionTree) u32 {
        if (tree.type_branches.count() == 0) return 1;

        var max_depth: u32 = 0;
        var iterator = tree.type_branches.iterator();
        while (iterator.next()) |entry| {
            const child_depth = self.calculateTreeDepth(entry.value_ptr.*);
            max_depth = @max(max_depth, child_depth);
        }

        return max_depth + 1;
    }

    /// Estimate cache efficiency
    fn estimateCacheEfficiency(self: *DispatchTableGenerator, table: *const DispatchTable) f32 {
        _ = self;

        // Simple heuristic based on table size and structure
        const size_factor: f32 = if (table.metadata.total_memory_bytes < 4096) 1.0 else 0.8;
        const coverage_factor = table.metadata.exact_match_coverage;
        const depth_factor: f32 = if (table.metadata.max_tree_depth < 4) 1.0 else 0.9;

        return size_factor * coverage_factor * depth_factor;
    }

    /// Generate comprehensive statistics about table generation
    pub fn generateStats(
        self: *DispatchTableGenerator,
        table: *const DispatchTable,
        signature_group: *const SignatureAnalyzer.SignatureGroup,
        generation_time_ms: u64,
    ) GenerationStats {
        const naive_table_size = signature_group.getImplementationCount() * 1000; // Rough estimate
        const compression_ratio = if (naive_table_size > 0)
            @as(f32, @floatFromInt(table.metadata.total_memory_bytes)) / @as(f32, @floatFromInt(naive_table_size))
        else
            1.0;

        return GenerationStats{
            .total_implementations = signature_group.getImplementationCount(),
            .exact_matches_generated = table.exact_matches.len,
            .decision_tree_nodes = if (table.decision_tree) |tree| self.countTreeNodes(tree) else 0,
            .memory_usage_bytes = table.metadata.total_memory_bytes,
            .generation_time_ms = generation_time_ms,
            .compression_ratio = compression_ratio,
        };
    }

    /// Count total nodes in decision tree
    fn countTreeNodes(self: *DispatchTableGenerator, tree: *const DispatchTable.DecisionTree) usize {
        var count: usize = 1;

        var iterator = tree.type_branches.iterator();
        while (iterator.next()) |entry| {
            count += self.countTreeNodes(entry.value_ptr.*);
        }

        return count;
    }
};

/// Compare exact matches for sorting
fn compareExactMatches(context: void, a: DispatchTableGenerator.DispatchTable.ExactMatch, b: DispatchTableGenerator.DispatchTable.ExactMatch) bool {
    _ = context;
    return a.type_combination_hash < b.type_combination_hash;
}

// ===== TESTS =====

test "DispatchTableGenerator basic table generation" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var generator = DispatchTableGenerator.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;
    const f64_id = type_registry.getTypeId("f64").?;

    // Add implementations
    _ = try signature_analyzer.addImplementation("test", "module1", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try signature_analyzer.addImplementation("test", "module2", &[_]TypeRegistry.TypeId{f64_id}, f64_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const signature_group = signature_analyzer.getSignatureGroup("test", 1).?;
    var table = try generator.generateTable(signature_group);
    defer table.deinit(std.testing.allocator);

    // Should generate exact matches
    try std.testing.expect(table.exact_matches.len > 0);
    try std.testing.expectEqual(@as(u32, 2), table.implementation_count);
    try std.testing.expect(table.metadata.total_memory_bytes > 0);
}

test "DispatchTableGenerator decision tree generation" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var generator = DispatchTableGenerator.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;
    const f64_id = type_registry.getTypeId("f64").?;
    const string_id = type_registry.getTypeId("string").?;

    // Add multiple implementations to trigger decision tree generation
    _ = try signature_analyzer.addImplementation("test", "module1", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try signature_analyzer.addImplementation("test", "module2", &[_]TypeRegistry.TypeId{f64_id}, f64_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try signature_analyzer.addImplementation("test", "module3", &[_]TypeRegistry.TypeId{string_id}, string_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const signature_group = signature_analyzer.getSignatureGroup("test", 1).?;
    var table = try generator.generateTable(signature_group);
    defer table.deinit(std.testing.allocator);

    // Should generate decision tree for multiple implementations
    try std.testing.expect(table.decision_tree != null);
    try std.testing.expect(table.metadata.max_tree_depth > 0);
}

test "DispatchTableGenerator type combination hashing" {
    var types1 = [_]TypeRegistry.TypeId{ 1, 2, 3 };
    var types2 = [_]TypeRegistry.TypeId{ 1, 2, 3 };
    var types3 = [_]TypeRegistry.TypeId{ 3, 2, 1 };

    const combo1 = DispatchTableGenerator.TypeCombination{ .types = types1[0..] };
    const combo2 = DispatchTableGenerator.TypeCombination{ .types = types2[0..] };
    const combo3 = DispatchTableGenerator.TypeCombination{ .types = types3[0..] };

    // Same combinations should have same hash and be equal
    try std.testing.expectEqual(combo1.hash(), combo2.hash());
    try std.testing.expect(combo1.eql(combo2));

    // Different combinations should have different hashes
    try std.testing.expect(combo1.hash() != combo3.hash());
    try std.testing.expect(!combo1.eql(combo3));
}

test "DispatchTableGenerator statistics generation" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var generator = DispatchTableGenerator.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;
    const f64_id = type_registry.getTypeId("f64").?;

    // Add implementations
    _ = try signature_analyzer.addImplementation("test", "module1", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try signature_analyzer.addImplementation("test", "module2", &[_]TypeRegistry.TypeId{f64_id}, f64_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const signature_group = signature_analyzer.getSignatureGroup("test", 1).?;
    var table = try generator.generateTable(signature_group);
    defer table.deinit(std.testing.allocator);

    const stats = generator.generateStats(&table, signature_group, 100);

    try std.testing.expectEqual(@as(usize, 2), stats.total_implementations);
    try std.testing.expect(stats.exact_matches_generated > 0);
    try std.testing.expect(stats.memory_usage_bytes > 0);
    try std.testing.expectEqual(@as(u64, 100), stats.generation_time_ms);
    try std.testing.expect(stats.compression_ratio > 0);
}

test "DispatchTableGenerator exact match sorting" {
    var matches = [_]DispatchTableGenerator.DispatchTable.ExactMatch{
        .{ .type_combination_hash = 300, .function_id = .{ .name = "c", .module = "test", .id = 3 } },
        .{ .type_combination_hash = 100, .function_id = .{ .name = "a", .module = "test", .id = 1 } },
        .{ .type_combination_hash = 200, .function_id = .{ .name = "b", .module = "test", .id = 2 } },
    };

    std.sort.insertion(DispatchTableGenerator.DispatchTable.ExactMatch, &matches, {}, compareExactMatches);

    try std.testing.expectEqual(@as(u64, 100), matches[0].type_combination_hash);
    try std.testing.expectEqual(@as(u64, 200), matches[1].type_combination_hash);
    try std.testing.expectEqual(@as(u64, 300), matches[2].type_combination_hash);
}

test "DispatchTableGenerator metadata calculation" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var signature_analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(std.testing.allocator, &type_registry);

    var generator = DispatchTableGenerator.init(
        std.testing.allocator,
        &type_registry,
        &signature_analyzer,
        &specificity_analyzer,
    );

    const i32_id = type_registry.getTypeId("i32").?;

    // Add single implementation
    _ = try signature_analyzer.addImplementation("test", "module", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    const signature_group = signature_analyzer.getSignatureGroup("test", 1).?;
    var table = try generator.generateTable(signature_group);
    defer table.deinit(std.testing.allocator);

    // Check metadata is reasonable
    try std.testing.expect(table.metadata.total_memory_bytes > 0);
    try std.testing.expect(table.metadata.exact_match_coverage >= 0.0);
    try std.testing.expect(table.metadata.exact_match_coverage <= 1.0);
    try std.testing.expect(table.metadata.cache_efficiency_estimate >= 0.0);
    try std.testing.expect(table.metadata.cache_efficiency_estimate <= 1.0);
}
