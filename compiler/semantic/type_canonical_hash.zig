// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Type Canonical Hashing - O(1) Type Deduplication
//!
//! Provides canonical hashing for type deduplication in the Janus type system.
//! This ensures that identical types are represented by the same TypeId,
//! enabling O(1) type operations and eliminating the O(N²) brute-force searches.

const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.HashMap;

// Type system imports
const type_system = @import("type_system.zig");
const TypeId = type_system.TypeId;
const TypeInfo = type_system.TypeInfo;
const TypeKind = type_system.TypeKind;

/// Canonical hasher for type deduplication
pub const TypeCanonicalHasher = struct {
    allocator: Allocator,
    type_to_id: HashMap(u64, TypeId, HashContext, std.hash_map.default_max_load_percentage),
    next_id: TypeId,

    const HashContext = struct {
        pub fn hash(self: @This(), key: u64) u64 {
            _ = self;
            return key;
        }
        pub fn eql(self: @This(), a: u64, b: u64) bool {
            _ = self;
            return a == b;
        }
    };

    pub fn init(allocator: Allocator) TypeCanonicalHasher {
        return TypeCanonicalHasher{
            .allocator = allocator,
            .type_to_id = HashMap(u64, TypeId, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .next_id = TypeId{ .id = 1 }, // Start from 1, reserve 0 for invalid
        };
    }

    pub fn deinit(self: *TypeCanonicalHasher) void {
        self.type_to_id.deinit();
    }

    /// Find existing type by canonical hash - O(1) operation
    pub fn findExistingType(self: *TypeCanonicalHasher, type_info: *const TypeInfo) ?TypeId {
        const hash = computeCanonicalHash(type_info);
        return self.type_to_id.get(hash);
    }

    /// Register new type with canonical hash - O(1) operation
    pub fn registerType(self: *TypeCanonicalHasher, type_info: *const TypeInfo, type_id: TypeId) !void {
        const hash = computeCanonicalHash(type_info);
        try self.type_to_id.put(hash, type_id);
    }

    /// Get next available type ID
    pub fn getNextId(self: *TypeCanonicalHasher) TypeId {
        const id = self.next_id;
        self.next_id = TypeId{ .id = self.next_id.id + 1 };
        return id;
    }
};

/// Compute canonical hash for a type - deterministic and collision-resistant
pub fn computeCanonicalHash(type_info: *const TypeInfo) u64 {
    var hasher = std.hash.Wyhash.init(0);

    // Hash the type discriminant (not the full union which includes pointers)
    const discriminant = @intFromEnum(type_info.kind);
    hasher.update(std.mem.asBytes(&discriminant));
    hasher.update(std.mem.asBytes(&type_info.size));
    hasher.update(std.mem.asBytes(&type_info.alignment));

    // Hash type-specific data based on canonical TypeKind
    switch (type_info.kind) {
        .primitive => |prim| {
            hasher.update(std.mem.asBytes(&prim));
        },
        .tensor => |t| {
            hasher.update(std.mem.asBytes(&t.element_type));
            hasher.update(std.mem.asBytes(&t.rank));
            for (t.dims) |d| hasher.update(std.mem.asBytes(&d));
            if (t.memspace) |ms| {
                const msi: u8 = @intFromEnum(ms);
                hasher.update(std.mem.asBytes(&msi));
            } else {
                const none: u8 = 255;
                hasher.update(std.mem.asBytes(&none));
            }
        },
        .pointer => |ptr| {
            hasher.update(std.mem.asBytes(&ptr.pointee_type));
            hasher.update(std.mem.asBytes(&ptr.is_mutable));
        },
        .array => |arr| {
            hasher.update(std.mem.asBytes(&arr.element_type));
            hasher.update(std.mem.asBytes(&arr.size));
        },
        .slice => |slice| {
            hasher.update(std.mem.asBytes(&slice.element_type));
            hasher.update(std.mem.asBytes(&slice.is_mutable));
        },
        .range => |range| {
            hasher.update(std.mem.asBytes(&range.element_type));
            hasher.update(std.mem.asBytes(&range.is_inclusive));
        },
        .function => |func| {
            for (func.parameter_types) |param_type| {
                hasher.update(std.mem.asBytes(&param_type));
            }
            hasher.update(std.mem.asBytes(&func.return_type));
            hasher.update(std.mem.asBytes(&func.calling_convention));
        },
        .structure => |struct_info| {
            hasher.update(struct_info.name);
            for (struct_info.fields) |field| {
                hasher.update(field.name);
                hasher.update(std.mem.asBytes(&field.type_id));
                hasher.update(std.mem.asBytes(&field.offset));
            }
        },
        .enumeration => |enum_info| {
            hasher.update(enum_info.name);
            hasher.update(std.mem.asBytes(&enum_info.underlying_type));
            for (enum_info.variants) |variant| {
                hasher.update(variant.name);
                hasher.update(std.mem.asBytes(&variant.value));
            }
        },
        .optional => |opt| {
            hasher.update(std.mem.asBytes(&opt.inner_type));
        },
        .error_union => |err_union| {
            hasher.update(std.mem.asBytes(&err_union.error_type));
            hasher.update(std.mem.asBytes(&err_union.payload_type));
        },
        .generic => |generic| {
            hasher.update(generic.name);
            for (generic.type_parameters) |param| {
                hasher.update(param.name);
                if (param.constraint) |constraint| {
                    hasher.update(std.mem.asBytes(&constraint));
                }
            }
        },
        .allocator => |alloc_info| {
            hasher.update(std.mem.asBytes(&alloc_info.allocator_kind));
        },
        .context_bound => |ctx_info| {
            hasher.update(std.mem.asBytes(&ctx_info.inner_type));
            hasher.update(std.mem.asBytes(&ctx_info.allocator_type));
            hasher.update(std.mem.asBytes(&ctx_info.allocator_kind));
        },
        .inference_var => |id| {
            hasher.update(std.mem.asBytes(&id));
        },
    }

    return hasher.final();
}

// Tests
test "canonical hash consistency" {
    const testing = std.testing;

    const type1 = TypeInfo{
        .kind = TypeKind{ .primitive = .i32 },
        .size = 4,
        .alignment = 4,
    };

    const type2 = TypeInfo{
        .kind = TypeKind{ .primitive = .i32 },
        .size = 4,
        .alignment = 4,
    };

    const hash1 = computeCanonicalHash(&type1);
    const hash2 = computeCanonicalHash(&type2);

    try testing.expect(hash1 == hash2);
}

test "type canonical hasher" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var hasher = TypeCanonicalHasher.init(allocator);
    defer hasher.deinit();

    const type_info = TypeInfo{
        .kind = TypeKind{ .primitive = .i32 },
        .size = 4,
        .alignment = 4,
    };

    // First lookup should return null
    try testing.expect(hasher.findExistingType(&type_info) == null);

    // Register the type
    const type_id = hasher.getNextId();
    try hasher.registerType(&type_info, type_id);

    // Second lookup should return the registered ID
    const found_type = hasher.findExistingType(&type_info);
    try testing.expect(found_type != null);
    try testing.expect(found_type.?.eql(type_id));
}
