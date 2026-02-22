// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;

/// SignatureAnalyzer - Groups functions by name and arity for multiple dispatch
///
/// This analyzer creates signature groups that participate in multiple dispatch.
/// Functions with the same name and arity are grouped together, and the most
/// specific implementation is selected based on argument types at call sites.
pub const SignatureAnalyzer = struct {
    /// Key for signature grouping (name + arity)
    pub const SignatureKey = struct {
        name_hash: u64,
        arity: u32,

        pub fn init(name: []const u8, arity: u32) SignatureKey {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(name);
            return SignatureKey{
                .name_hash = hasher.final(),
                .arity = arity,
            };
        }

        pub fn eql(self: SignatureKey, other: SignatureKey) bool {
            return self.name_hash == other.name_hash and self.arity == other.arity;
        }

        pub fn hash(self: SignatureKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&self.name_hash));
            hasher.update(std.mem.asBytes(&self.arity));
            return hasher.final();
        }
    };

    /// Context for SignatureKey HashMap
    pub const SignatureKeyContext = struct {
        pub fn hash(self: @This(), key: SignatureKey) u64 {
            _ = self;
            return key.hash();
        }

        pub fn eql(self: @This(), a: SignatureKey, b: SignatureKey) bool {
            _ = self;
            return a.eql(b);
        }
    };

    /// A single implementation within a signature group
    pub const Implementation = struct {
        function_id: FunctionId,
        param_type_ids: []TypeRegistry.TypeId,
        return_type_id: TypeRegistry.TypeId,
        effects: EffectSet,
        source_location: SourceSpan,
        specificity_rank: u32,

        pub fn deinit(self: *Implementation, allocator: std.mem.Allocator) void {
            allocator.free(self.param_type_ids);
        }

        /// Calculate specificity rank for this implementation
        pub fn calculateSpecificityRank(
            param_type_ids: []const TypeRegistry.TypeId,
            type_registry: *const TypeRegistry,
        ) u32 {
            var rank: u32 = 0;

            for (param_type_ids) |type_id| {
                if (type_registry.getTypeInfo(type_id)) |type_info| {
                    rank += type_info.specificity_score;
                }
            }

            return rank;
        }
    };

    /// Group of implementations for the same signature (name + arity)
    pub const SignatureGroup = struct {
        key: SignatureKey,
        name: []const u8,
        implementations: std.ArrayList(Implementation),
        is_sealed: bool, // All types known at compile time

        pub fn init(allocator: std.mem.Allocator, key: SignatureKey, name: []const u8) !SignatureGroup {
            return SignatureGroup{
                .key = key,
                .name = try allocator.dupe(u8, name),
                .implementations = std.ArrayList(Implementation).init(allocator),
                .is_sealed = false,
            };
        }

        pub fn deinit(self: *SignatureGroup, allocator: std.mem.Allocator) void {
            for (self.implementations.items) |*impl| {
                impl.deinit(allocator);
            }
            self.implementations.deinit();
            allocator.free(self.name);
        }

        /// Add an implementation to this signature group
        pub fn addImplementation(self: *SignatureGroup, impl: Implementation) !void {
            // Check for exact duplicate signatures from the same module
            for (self.implementations.items) |existing| {
                if (signaturesEqual(existing.param_type_ids, impl.param_type_ids) and
                    existing.function_id.eql(impl.function_id))
                {
                    return error.DuplicateSignature;
                }
            }

            try self.implementations.append(impl);

            // Sort implementations by specificity rank for efficient lookup
            std.sort.insertion(Implementation, self.implementations.items, {}, compareImplementationSpecificity);
        }

        /// Check if all implementations use sealed types (enables static dispatch)
        pub fn canUseStaticDispatch(self: *const SignatureGroup, type_registry: *const TypeRegistry) bool {
            if (!self.is_sealed) return false;

            for (self.implementations.items) |impl| {
                for (impl.param_type_ids) |type_id| {
                    if (type_registry.getTypeInfo(type_id)) |type_info| {
                        if (!type_info.kind.isSealed()) return false;
                    }
                }
            }

            return true;
        }

        /// Get implementation count
        pub fn getImplementationCount(self: *const SignatureGroup) usize {
            return self.implementations.items.len;
        }
    };

    /// Unique identifier for functions
    pub const FunctionId = struct {
        name: []const u8,
        module: []const u8,
        id: u32,

        pub fn eql(self: FunctionId, other: FunctionId) bool {
            return std.mem.eql(u8, self.name, other.name) and
                std.mem.eql(u8, self.module, other.module) and
                self.id == other.id;
        }

        pub fn hash(self: FunctionId) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(self.name);
            hasher.update(self.module);
            hasher.update(std.mem.asBytes(&self.id));
            return hasher.final();
        }
    };

    /// Effect set for tracking side effects
    pub const EffectSet = struct {
        effects: u32, // Bitset of effects

        pub const PURE: u32 = 0;
        pub const CPU: u32 = 1 << 0;
        pub const IO: u32 = 1 << 1;
        pub const FS: u32 = 1 << 2;
        pub const NET: u32 = 1 << 3;

        pub fn init(effects: u32) EffectSet {
            return EffectSet{ .effects = effects };
        }

        pub fn isPure(self: EffectSet) bool {
            return self.effects == PURE;
        }

        pub fn hasEffect(self: EffectSet, effect: u32) bool {
            return (self.effects & effect) != 0;
        }
    };

    /// Source location for error reporting
    pub const SourceSpan = struct {
        file: []const u8,
        start_line: u32,
        start_col: u32,
        end_line: u32,
        end_col: u32,

        pub fn dummy() SourceSpan {
            return SourceSpan{
                .file = "<unknown>",
                .start_line = 0,
                .start_col = 0,
                .end_line = 0,
                .end_col = 0,
            };
        }
    };

    signatures: std.HashMap(SignatureKey, SignatureGroup, SignatureKeyContext, std.hash_map.default_max_load_percentage),
    type_registry: *TypeRegistry,
    allocator: std.mem.Allocator,
    next_function_id: u32,

    pub fn init(allocator: std.mem.Allocator, type_registry: *TypeRegistry) SignatureAnalyzer {
        return SignatureAnalyzer{
            .signatures = std.HashMap(SignatureKey, SignatureGroup, SignatureKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .type_registry = type_registry,
            .allocator = allocator,
            .next_function_id = 0,
        };
    }

    pub fn deinit(self: *SignatureAnalyzer) void {
        var iterator = self.signatures.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.signatures.deinit();
    }

    /// Add an implementation to the appropriate signature group
    pub fn addImplementation(
        self: *SignatureAnalyzer,
        name: []const u8,
        module: []const u8,
        param_type_ids: []const TypeRegistry.TypeId,
        return_type_id: TypeRegistry.TypeId,
        effects: EffectSet,
        source_location: SourceSpan,
    ) !FunctionId {
        const function_id = FunctionId{
            .name = name,
            .module = module,
            .id = self.next_function_id,
        };
        self.next_function_id += 1;

        const key = SignatureKey.init(name, @intCast(param_type_ids.len));

        // Get or create signature group
        const result = try self.signatures.getOrPut(key);
        if (!result.found_existing) {
            result.value_ptr.* = try SignatureGroup.init(self.allocator, key, name);
        }

        // Create implementation
        const owned_param_types = try self.allocator.dupe(TypeRegistry.TypeId, param_type_ids);
        const specificity_rank = Implementation.calculateSpecificityRank(param_type_ids, self.type_registry);

        const impl = Implementation{
            .function_id = function_id,
            .param_type_ids = owned_param_types,
            .return_type_id = return_type_id,
            .effects = effects,
            .source_location = source_location,
            .specificity_rank = specificity_rank,
        };

        // Add to signature group
        try result.value_ptr.addImplementation(impl);

        return function_id;
    }

    /// Get signature group by name and arity
    pub fn getSignatureGroup(self: *SignatureAnalyzer, name: []const u8, arity: u32) ?*SignatureGroup {
        const key = SignatureKey.init(name, arity);
        return self.signatures.getPtr(key);
    }

    /// Get all signature groups (for analysis and debugging)
    pub fn getAllSignatureGroups(self: *SignatureAnalyzer) std.HashMap(SignatureKey, SignatureGroup, SignatureKeyContext, std.hash_map.default_max_load_percentage).Iterator {
        return self.signatures.iterator();
    }

    /// Mark a signature group as sealed (enables static dispatch optimization)
    pub fn sealSignatureGroup(self: *SignatureAnalyzer, name: []const u8, arity: u32) !void {
        const key = SignatureKey.init(name, arity);
        if (self.signatures.getPtr(key)) |group| {
            group.is_sealed = true;
        } else {
            return error.SignatureGroupNotFound;
        }
    }

    /// Get statistics about signature groups
    pub fn getStatistics(self: *const SignatureAnalyzer) Statistics {
        var stats = Statistics{
            .total_groups = 0,
            .total_implementations = 0,
            .sealed_groups = 0,
            .max_implementations_per_group = 0,
        };

        var iterator = self.signatures.iterator();
        while (iterator.next()) |entry| {
            stats.total_groups += 1;
            stats.total_implementations += entry.value_ptr.getImplementationCount();

            if (entry.value_ptr.is_sealed) {
                stats.sealed_groups += 1;
            }

            const impl_count = entry.value_ptr.getImplementationCount();
            if (impl_count > stats.max_implementations_per_group) {
                stats.max_implementations_per_group = impl_count;
            }
        }

        return stats;
    }

    pub const Statistics = struct {
        total_groups: usize,
        total_implementations: usize,
        sealed_groups: usize,
        max_implementations_per_group: usize,
    };
};

/// Check if two signatures are exactly equal
fn signaturesEqual(sig1: []const TypeRegistry.TypeId, sig2: []const TypeRegistry.TypeId) bool {
    if (sig1.len != sig2.len) return false;

    for (sig1, sig2) |type1, type2| {
        if (type1 != type2) return false;
    }

    return true;
}

/// Compare implementations by specificity rank for sorting
fn compareImplementationSpecificity(context: void, impl1: SignatureAnalyzer.Implementation, impl2: SignatureAnalyzer.Implementation) bool {
    _ = context;
    return impl1.specificity_rank > impl2.specificity_rank;
}

// ===== TESTS =====

test "SignatureAnalyzer basic operations" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer analyzer.deinit();

    // Add an implementation
    const i32_id = type_registry.getTypeId("i32").?;

    const function_id = try analyzer.addImplementation(
        "add",
        "math",
        &[_]TypeRegistry.TypeId{ i32_id, i32_id },
        i32_id,
        SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        SignatureAnalyzer.SourceSpan.dummy(),
    );

    // Test signature group creation
    const group = analyzer.getSignatureGroup("add", 2);
    try std.testing.expect(group != null);
    try std.testing.expectEqual(@as(usize, 1), group.?.getImplementationCount());
    try std.testing.expectEqualStrings("add", group.?.name);

    // Test function ID
    try std.testing.expectEqualStrings("add", function_id.name);
    try std.testing.expectEqualStrings("math", function_id.module);
}

test "SignatureAnalyzer multiple implementations" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer analyzer.deinit();

    const i32_id = type_registry.getTypeId("i32").?;
    const f64_id = type_registry.getTypeId("f64").?;

    // Add multiple implementations for the same signature
    _ = try analyzer.addImplementation(
        "add",
        "math",
        &[_]TypeRegistry.TypeId{ i32_id, i32_id },
        i32_id,
        SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        SignatureAnalyzer.SourceSpan.dummy(),
    );

    _ = try analyzer.addImplementation(
        "add",
        "math",
        &[_]TypeRegistry.TypeId{ f64_id, f64_id },
        f64_id,
        SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        SignatureAnalyzer.SourceSpan.dummy(),
    );

    // Test that both implementations are in the same group
    const group = analyzer.getSignatureGroup("add", 2);
    try std.testing.expect(group != null);
    try std.testing.expectEqual(@as(usize, 2), group.?.getImplementationCount());
}

test "SignatureAnalyzer duplicate signature detection" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer analyzer.deinit();

    const i32_id = type_registry.getTypeId("i32").?;

    // Add first implementation
    _ = try analyzer.addImplementation(
        "add",
        "math",
        &[_]TypeRegistry.TypeId{ i32_id, i32_id },
        i32_id,
        SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        SignatureAnalyzer.SourceSpan.dummy(),
    );

    // Try to add different signature from different module - should succeed
    _ = try analyzer.addImplementation(
        "add",
        "math2",
        &[_]TypeRegistry.TypeId{ i32_id, i32_id },
        i32_id,
        SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        SignatureAnalyzer.SourceSpan.dummy(),
    );

    // Verify both implementations are in the same group
    const group = analyzer.getSignatureGroup("add", 2);
    try std.testing.expect(group != null);
    try std.testing.expectEqual(@as(usize, 2), group.?.getImplementationCount());
}

test "SignatureAnalyzer signature key operations" {
    const key1 = SignatureAnalyzer.SignatureKey.init("add", 2);
    const key2 = SignatureAnalyzer.SignatureKey.init("add", 2);
    const key3 = SignatureAnalyzer.SignatureKey.init("add", 3);
    const key4 = SignatureAnalyzer.SignatureKey.init("sub", 2);

    // Test equality
    try std.testing.expect(key1.eql(key2));
    try std.testing.expect(!key1.eql(key3));
    try std.testing.expect(!key1.eql(key4));

    // Test hashing consistency
    try std.testing.expectEqual(key1.hash(), key2.hash());
}

test "SignatureAnalyzer statistics" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer analyzer.deinit();

    const i32_id = type_registry.getTypeId("i32").?;
    const f64_id = type_registry.getTypeId("f64").?;

    // Add implementations
    _ = try analyzer.addImplementation("add", "math", &[_]TypeRegistry.TypeId{ i32_id, i32_id }, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try analyzer.addImplementation("add", "math", &[_]TypeRegistry.TypeId{ f64_id, f64_id }, f64_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    _ = try analyzer.addImplementation("sub", "math", &[_]TypeRegistry.TypeId{ i32_id, i32_id }, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    // Seal one group
    try analyzer.sealSignatureGroup("add", 2);

    const stats = analyzer.getStatistics();
    try std.testing.expectEqual(@as(usize, 2), stats.total_groups);
    try std.testing.expectEqual(@as(usize, 3), stats.total_implementations);
    try std.testing.expectEqual(@as(usize, 1), stats.sealed_groups);
    try std.testing.expectEqual(@as(usize, 2), stats.max_implementations_per_group);
}

test "SignatureAnalyzer cross-module support" {
    var type_registry = try TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    try type_registry.registerPrimitiveTypes();

    var analyzer = SignatureAnalyzer.init(std.testing.allocator, &type_registry);
    defer analyzer.deinit();

    const i32_id = type_registry.getTypeId("i32").?;

    // Add implementations from different modules - should be allowed
    const func1 = try analyzer.addImplementation("process", "module1", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());
    const func2 = try analyzer.addImplementation("process", "module2", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    // Should succeed - different modules can have same signatures
    const func3 = try analyzer.addImplementation("process", "module3", &[_]TypeRegistry.TypeId{i32_id}, i32_id, SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE), SignatureAnalyzer.SourceSpan.dummy());

    // Verify different modules are tracked
    try std.testing.expectEqualStrings("module1", func1.module);
    try std.testing.expectEqualStrings("module2", func2.module);
    try std.testing.expectEqualStrings("module3", func3.module);

    // Verify all implementations are in the same signature group
    const group = analyzer.getSignatureGroup("process", 1);
    try std.testing.expect(group != null);
    try std.testing.expectEqual(@as(usize, 3), group.?.getImplementationCount());
}
