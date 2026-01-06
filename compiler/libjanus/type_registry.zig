// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

/// TypeId provides efficient type identification and comparison
pub const TypeId = struct {
    id: u32,

    pub const INVALID = TypeId{ .id = 0 };
    pub const I32 = TypeId{ .id = 1 };
    pub const F64 = TypeId{ .id = 2 };
    pub const BOOL = TypeId{ .id = 3 };
    pub const STRING = TypeId{ .id = 4 };

    pub fn equals(self: TypeId, other: TypeId) bool {
        return self.id == other.id;
    }

    pub fn hash(self: TypeId) u64 {
        return std.hash.int(self.id);
    }
};

/// Type represents a complete type with metadata
pub const Type = struct {
    id: TypeId,
    name: []const u8,
    kind: TypeKind,
    generic_params: []Type,

    pub const TypeKind = enum {
        primitive,
        struct_type,
        enum_type,
        function_type,
        generic_param,
        generic_instance,
    };

    pub fn equals(self: *const Type, other: *const Type) bool {
        if (!self.id.equals(other.id)) return false;
        if (self.kind != other.kind) return false;

        // For generic instances, compare parameters
        if (self.kind == .generic_instance) {
            if (self.generic_params.len != other.generic_params.len) return false;
            for (self.generic_params, other.generic_params) |param1, param2| {
                if (!param1.equals(&param2)) return false;
            }
        }

        return true;
    }

    pub fn isSubtypeOf(self: *const Type, other: *const Type) bool {
        // For now, only exact matches are subtypes
        // This will be expanded for inhernce hierarchies
        return self.equals(other);
    }

    pub fn getSpecificity(self: *const Type) u32 {
        // More specific types have higher specificity scores
        return switch (self.kind) {
            .primitive => 100,
            .struct_type => 200,
            .enum_type => 150,
            .function_type => 300,
            .generic_param => 50,
            .generic_instance => 250,
        };
    }
};

/// TypeRegistry manages type registration and lookup
pub const TypeRegistry = struct {
    allocator: Allocator,
    types: std.HashMap(TypeId, *Type, TypeIdContext, std.hash_map.default_max_load_percentage),
    name_to_id: std.HashMap([]const u8, TypeId, StringContext, std.hash_map.default_max_load_percentage),
    next_id: u32,

    const TypeIdContext = struct {
        pub fn hash(self: @This(), key: TypeId) u64 {
            _ = self;
            return key.hash();
        }

        pub fn eql(self: @This(), a: TypeId, b: TypeId) bool {
            _ = self;
            return a.equals(b);
        }
    };

    const StringContext = struct {
        pub fn hash(self: @This(), key: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(key);
        }

        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    pub fn init(allocator: Allocator) TypeRegistry {
        var registry = TypeRegistry{
            .allocator = allocator,
            .types = std.HashMap(TypeId, *Type, TypeIdContext, std.hash_map.default_max_load_percentage).init(allocator),
            .name_to_id = std.HashMap([]const u8, TypeId, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .next_id = 5, // Start after built-in types
        };

        // Register built-in types
        registry.registerBuiltinTypes() catch unreachable;

        return registry;
    }

    pub fn deinit(self: *TypeRegistry) void {
        var iterator = self.types.iterator();
        while (iterator.next()) |entry| {
            const type_obj = entry.value_ptr.*;
            // Free the name if it was allocated (not for built-in types)
            if (type_obj.id.id >= 5) { // Custom types start at id 5
                self.allocator.free(type_obj.name);
            }
            self.allocator.destroy(type_obj);
        }
        self.types.deinit();
        self.name_to_id.deinit();
    }

    fn registerBuiltinTypes(self: *TypeRegistry) !void {
        try self.registerPrimitive(TypeId.I32, "i32");
        try self.registerPrimitive(TypeId.F64, "f64");
        try self.registerPrimitive(TypeId.BOOL, "bool");
        try self.registerPrimitive(TypeId.STRING, "string");
    }

    fn registerPrimitive(self: *TypeRegistry, id: TypeId, name: []const u8) !void {
        const type_obj = try self.allocator.create(Type);
        type_obj.* = Type{
            .id = id,
            .name = name,
            .kind = .primitive,
            .generic_params = &[_]Type{},
        };

        try self.types.put(id, type_obj);
        try self.name_to_id.put(name, id);
    }

    pub fn registerType(self: *TypeRegistry, name: []const u8, kind: Type.TypeKind) !TypeId {
        const id = TypeId{ .id = self.next_id };
        self.next_id += 1;

        const type_obj = try self.allocator.create(Type);
        type_obj.* = Type{
            .id = id,
            .name = try self.allocator.dupe(u8, name),
            .kind = kind,
            .generic_params = &[_]Type{},
        };

        try self.types.put(id, type_obj);
        try self.name_to_id.put(type_obj.name, id);

        return id;
    }

    pub fn getType(self: *const TypeRegistry, id: TypeId) ?*Type {
        return self.types.get(id);
    }

    pub fn getTypeByName(self: *const TypeRegistry, name: []const u8) ?*Type {
        const id = self.name_to_id.get(name) orelse return null;
        return self.getType(id);
    }

    pub fn areCompatible(self: *const TypeRegistry, from: *const Type, to: *const Type) bool {
        _ = self; // Registry not used for basic compatibility

        // Exact match is always compatible
        if (from.equals(to)) return true;

        // Check subtype relationship
        if (from.isSubtypeOf(to)) return true;

        // No implicit conversions - must be explicit
        return false;
    }

    pub fn getSpecificityDistance(self: *const TypeRegistry, from: *const Type, to: *const Type) ?u32 {
        _ = self;

        if (from.equals(to)) return 0;
        if (from.isSubtypeOf(to)) return 1;

        // No implicit conversion path
        return null;
    }
};

// Tests
test "TypeRegistry basic operations" {
    var registry = TypeRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Test built-in types
    const i32_type = registry.getTypeByName("i32").?;
    const f64_type = registry.getTypeByName("f64").?;

    try std.testing.expect(i32_type.id.equals(TypeId.I32));
    try std.testing.expect(f64_type.id.equals(TypeId.F64));

    // Test type compatibility
    try std.testing.expect(registry.areCompatible(i32_type, i32_type));
    try std.testing.expect(!registry.areCompatible(i32_type, f64_type));
}

test "TypeRegistry custom types" {
    var registry = TypeRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Register custom type
    const custom_id = try registry.registerType("MyStruct", .struct_type);
    const custom_type = registry.getType(custom_id).?;

    try std.testing.expect(custom_type.kind == .struct_type);
    try std.testing.expectEqualStrings(custom_type.name, "MyStruct");

    // Test lookup by name
    const found_type = registry.getTypeByName("MyStruct").?;
    try std.testing.expect(found_type.id.equals(custom_id));
}
