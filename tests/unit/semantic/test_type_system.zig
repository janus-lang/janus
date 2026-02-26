// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Type System Tests
//!
//! Tests the Type System Foundation including primitive types, composite types,
//! type compatibility checking, and type interner functionality.

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const print = std.debug.print;

const type_system = @import("../../../compiler/semantic/type_system.zig");
const symbol_table = @import("../../../compiler/semantic/symbol_table.zig");

const TypeSystem = type_system.TypeSystem;
const TypeId = type_system.TypeId;

test "Type System - Primitive Types" {
    print("\n🔧 TYPE SYSTEM PRIMITIVE TYPES TEST\n");
    print("===================================\n");

    const allocator = std.testing.allocator;

    const system = try TypeSystem.init(allocator);
    defer system.deinit();

    // Test primitive type access
    print("🧪 Test 1: Primitive Type Access\n");

    const primitives = [_]struct { id: TypeId, name: []const u8 }{
        .{ .id = system.primitives.void, .name = "void" },
        .{ .id = system.primitives.bool, .name = "bool" },
        .{ .id = system.primitives.i32, .name = "i32" },
        .{ .id = system.primitives.f64, .name = "f64" },
        .{ .id = system.primitives.string, .name = "string" },
    };

    for (primitives) |prim| {
        const type_def = system.getType(prim.id);
        try testing.expect(type_def != null);
        try testing.expect(type_def.? == .primitive);

        print("   ✅ {s} type accessible\n", .{prim.name});
    }

    // Test primitive type properties
    print("🧪 Test 2: Primitive Type Properties\n");

    try testing.expect(system.primitives.i32.isPrimitive());
    try testing.expect(system.primitives.string.isPrimitive());

    print("   ✅ Primitive type identification working\n");

    print("🔧 Primitive Types: ALL TESTS PASSED!\n");
}

test "Type System - Function Types" {
    print("\n🔧 TYPE SYSTEM FUNCTION TYPES TEST\n");
    print("==================================\n");

    const allocator = std.testing.allocator;

    const system = try TypeSystem.init(allocator);
    defer system.deinit();

    print("🧪 Test 1: Function Type Creation\n");

    // Create function type: (i32, i32) -> i32
    const params = [_]TypeId{ system.primitives.i32, system.primitives.i32 };
    const func_type_id = try system.createFunctionType(&params, system.primitives.i32, true);

    const func_type = system.getType(func_type_id);
    try testing.expect(func_type != null);
    try testing.expect(func_type.? == .function);

    const func_def = func_type.?.function;
    try testing.expect(func_def.parameters.len == 2);
    try testing.expect(func_def.parameters[0] == system.primitives.i32);
    try testing.expect(func_def.parameters[1] == system.primitives.i32);
    try testing.expect(func_def.return_type == system.primitives.i32);
    try testing.expect(func_def.is_pure == true);

    print("   ✅ Function type creation successful\n");

    print("🧪 Test 2: Function Type Deduplication\n");

    // Create identical function type - should return same ID
    const duplicate_func_type_id = try system.createFunctionType(&params, system.primitives.i32, true);
    try testing.expect(func_type_id == duplicate_func_type_id);

    print("   ✅ Function type deduplication working\n");

    print("🧪 Test 3: Different Function Types\n");

    // Create different function type: (string) -> bool
    const params2 = [_]TypeId{system.primitives.string};
    const func_type_id2 = try system.createFunctionType(&params2, system.primitives.bool, true);

    try testing.expect(func_type_id != func_type_id2);

    print("   ✅ Different function types have different IDs\n");

    print("🔧 Function Types: ALL TESTS PASSED!\n");
}

test "Type System - Array Types" {
    print("\n🔧 TYPE SYSTEM ARRAY TYPES TEST\n");
    print("===============================\n");

    const allocator = std.testing.allocator;

    const system = try TypeSystem.init(allocator);
    defer system.deinit();

    print("🧪 Test 1: Fixed Array Type\n");

    // Create [10]i32
    const fixed_array_id = try system.createArrayType(system.primitives.i32, TypeSystem.Type.ArrayType.ArraySize{ .fixed = 10 });

    const array_type = system.getType(fixed_array_id);
    try testing.expect(array_type != null);
    try testing.expect(array_type.? == .array);

    const array_def = array_type.?.array;
    try testing.expect(array_def.element_type == system.primitives.i32);
    try testing.expect(array_def.size == .fixed);
    try testing.expect(array_def.size.fixed == 10);

    print("   ✅ Fixed array type [10]i32 created\n");

    print("🧪 Test 2: Dynamic Array Type\n");

    // Create []string
    const dynamic_array_id = try system.createArrayType(system.primitives.string, TypeSystem.Type.ArrayType.ArraySize.dynamic);

    const dynamic_type = system.getType(dynamic_array_id);
    try testing.expect(dynamic_type != null);
    try testing.expect(dynamic_type.? == .array);

    const dynamic_def = dynamic_type.?.array;
    try testing.expect(dynamic_def.element_type == system.primitives.string);
    try testing.expect(dynamic_def.size == .dynamic);

    print("   ✅ Dynamic array type []string created\n");

    print("🧪 Test 3: Array Type Deduplication\n");

    // Create identical fixed array - should return same ID
    const duplicate_array_id = try system.createArrayType(system.primitives.i32, TypeSystem.Type.ArrayType.ArraySize{ .fixed = 10 });
    try testing.expect(fixed_array_id == duplicate_array_id);

    print("   ✅ Array type deduplication working\n");

    print("🔧 Array Types: ALL TESTS PASSED!\n");
}

test "Type System - Pointer Types" {
    print("\n🔧 TYPE SYSTEM POINTER TYPES TEST\n");
    print("=================================\n");

    const allocator = std.testing.allocator;

    const system = try TypeSystem.init(allocator);
    defer system.deinit();

    print("🧪 Test 1: Mutable Pointer Type\n");

    // Create *i32
    const mut_ptr_id = try system.createPointerType(system.primitives.i32, .mutable, .non_null);

    const ptr_type = system.getType(mut_ptr_id);
    try testing.expect(ptr_type != null);
    try testing.expect(ptr_type.? == .pointer);

    const ptr_def = ptr_type.?.pointer;
    try testing.expect(ptr_def.pointee_type == system.primitives.i32);
    try testing.expect(ptr_def.mutability == .mutable);
    try testing.expect(ptr_def.nullability == .non_null);

    print("   ✅ Mutable pointer type *i32 created\n");

    print("🧪 Test 2: Const Nullable Pointer Type\n");

    // Create ?*const string
    const const_nullable_ptr_id = try system.createPointerType(system.primitives.string, .immutable, .nullable);

    const const_ptr_type = system.getType(const_nullable_ptr_id);
    try testing.expect(const_ptr_type != null);
    try testing.expect(const_ptr_type.? == .pointer);

    const const_ptr_def = const_ptr_type.?.pointer;
    try testing.expect(const_ptr_def.pointee_type == system.primitives.string);
    try testing.expect(const_ptr_def.mutability == .immutable);
    try testing.expect(const_ptr_def.nullability == .nullable);

    print("   ✅ Const nullable pointer type ?*const string created\n");

    print("🧪 Test 3: Pointer Type Deduplication\n");

    // Create identical pointer - should return same ID
    const duplicate_ptr_id = try system.createPointerType(system.primitives.i32, .mutable, .non_null);
    try testing.expect(mut_ptr_id == duplicate_ptr_id);

    print("   ✅ Pointer type deduplication working\n");

    print("🔧 Pointer Types: ALL TESTS PASSED!\n");
}

test "Type System - Optional Types" {
    print("\n🔧 TYPE SYSTEM OPTIONAL TYPES TEST\n");
    print("==================================\n");

    const allocator = std.testing.allocator;

    const system = try TypeSystem.init(allocator);
    defer system.deinit();

    print("🧪 Test 1: Optional Type Creation\n");

    // Create ?i32
    const optional_i32_id = try system.createOptionalType(system.primitives.i32);

    const opt_type = system.getType(optional_i32_id);
    try testing.expect(opt_type != null);
    try testing.expect(opt_type.? == .optional);

    const opt_def = opt_type.?.optional;
    try testing.expect(opt_def.wrapped_type == system.primitives.i32);

    print("   ✅ Optional type ?i32 created\n");

    print("🧪 Test 2: Nested Optional Types\n");

    // Create ??string (optional optional string)
    const optional_string_id = try system.createOptionalType(system.primitives.string);
    const nested_optional_id = try system.createOptionalType(optional_string_id);

    const nested_type = system.getType(nested_optional_id);
    try testing.expect(nested_type != null);
    try testing.expect(nested_type.? == .optional);

    const nested_def = nested_type.?.optional;
    try testing.expect(nested_def.wrapped_type == optional_string_id);

    print("   ✅ Nested optional type ??string created\n");

    print("🧪 Test 3: Optional Type Deduplication\n");

    // Create identical optional - should return same ID
    const duplicate_opt_id = try system.createOptionalType(system.primitives.i32);
    try testing.expect(optional_i32_id == duplicate_opt_id);

    print("   ✅ Optional type deduplication working\n");

    print("🔧 Optional Types: ALL TESTS PASSED!\n");
}

test "Type System - Type Compatibility" {
    print("\n🔧 TYPE SYSTEM COMPATIBILITY TEST\n");
    print("=================================\n");

    const allocator = std.testing.allocator;

    const system = try TypeSystem.init(allocator);
    defer system.deinit();

    print("🧪 Test 1: Identity Compatibility\n");

    // T = T should always be true
    try testing.expect(system.isAssignable(system.primitives.i32, system.primitives.i32));
    try testing.expect(system.isAssignable(system.primitives.string, system.primitives.string));

    print("   ✅ Identity compatibility working\n");

    print("🧪 Test 2: Primitive Type Promotions\n");

    // Integer promotions: i8 -> i16 -> i32 -> i64
    try testing.expect(system.isAssignable(system.primitives.i8, system.primitives.i16));
    try testing.expect(system.isAssignable(system.primitives.i16, system.primitives.i32));
    try testing.expect(system.isAssignable(system.primitives.i32, system.primitives.i64));

    // But not backwards
    try testing.expect(!system.isAssignable(system.primitives.i32, system.primitives.i16));
    try testing.expect(!system.isAssignable(system.primitives.i64, system.primitives.i32));

    print("   ✅ Integer promotions working correctly\n");

    // Unsigned promotions: u8 -> u16 -> u32 -> u64
    try testing.expect(system.isAssignable(system.primitives.u8, system.primitives.u16));
    try testing.expect(system.isAssignable(system.primitives.u16, system.primitives.u32));

    // Cross-signed promotions (unsigned to larger signed)
    try testing.expect(system.isAssignable(system.primitives.u8, system.primitives.i16));
    try testing.expect(system.isAssignable(system.primitives.u16, system.primitives.i32));

    print("   ✅ Unsigned promotions working correctly\n");

    // Float promotions: f32 -> f64
    try testing.expect(system.isAssignable(system.primitives.f32, system.primitives.f64));
    try testing.expect(!system.isAssignable(system.primitives.f64, system.primitives.f32));

    print("   ✅ Float promotions working correctly\n");

    print("🧪 Test 3: Incompatible Types\n");

    // Incompatible primitive types
    try testing.expect(!system.isAssignable(system.primitives.bool, system.primitives.i32));
    try testing.expect(!system.isAssignable(system.primitives.string, system.primitives.f64));
    try testing.expect(!system.isAssignable(system.primitives.i32, system.primitives.string));

    print("   ✅ Incompatible types correctly rejected\n");

    print("🧪 Test 4: Function Type Compatibility\n");

    // Create function types for compatibility testing
    const params1 = [_]TypeId{system.primitives.i32};
    const params2 = [_]TypeId{system.primitives.i16}; // Smaller int

    const func1_id = try system.createFunctionType(&params1, system.primitives.i32, true);
    const func2_id = try system.createFunctionType(&params2, system.primitives.i64, true);

    // Function types: parameters contravariant, return covariant
    // func1: (i32) -> i32
    // func2: (i16) -> i64
    // func2 should be assignable to func1 because:
    // - i32 (func1 param) is assignable to i16 (func2 param) - contravariant
    // - i64 (func2 return) is assignable to i32 (func1 return) - wait, this is wrong!

    // Actually, let's test correct function subtyping
    const func3_params = [_]TypeId{system.primitives.i64}; // Larger param
    const func3_id = try system.createFunctionType(&func3_params, system.primitives.i16, true); // Smaller return

    // func3: (i64) -> i16 should be assignable to func1: (i32) -> i32
    // Because: i32 -> i64 (contravariant params) and i16 -> i32 (covariant return)
    try testing.expect(system.isAssignable(func3_id, func1_id));

    print("   ✅ Function type compatibility working\n");

    print("🔧 Type Compatibility: ALL TESTS PASSED!\n");
}

test "Type System - Performance Characteristics" {
    print("\n⚡ TYPE SYSTEM PERFORMANCE TEST\n");
    print("==============================\n");

    const allocator = std.testing.allocator;

    const system = try TypeSystem.init(allocator);
    defer system.deinit();

    print("🧪 Test: Large Type System Performance\n");

    const num_types = 1000;

    // Create many function types
    var type_ids = std.ArrayList(TypeId){};
    defer type_ids.deinit();

    const start_time = compat_time.nanoTimestamp();

    for (0..num_types) |i| {
        const params = [_]TypeId{system.primitives.i32};
        const return_type = if (i % 2 == 0) system.primitives.i32 else system.primitives.i64;

        const func_id = try system.createFunctionType(&params, return_type, true);
        try type_ids.append(func_id);
    }

    const creation_time = compat_time.nanoTimestamp();
    const creation_duration = @as(f64, @floatFromInt(creation_time - start_time)) / 1_000_000.0;

    print("   Type creation time: {d:.2f}ms for {} types\n", .{ creation_duration, num_types });

    // Test compatibility checking performance
    var compatibility_checks: u32 = 0;

    for (type_ids.items) |type1| {
        for (type_ids.items) |type2| {
            _ = system.isAssignable(type1, type2);
            compatibility_checks += 1;
        }
    }

    const compatibility_time = compat_time.nanoTimestamp();
    const compatibility_duration = @as(f64, @floatFromInt(compatibility_time - creation_time)) / 1_000_000.0;

    print("   Compatibility checking time: {d:.2f}ms for {} checks\n", .{ compatibility_duration, compatibility_checks });

    // Performance requirements
    const avg_creation_time = creation_duration / @as(f64, @floatFromInt(num_types));
    const avg_compatibility_time = compatibility_duration / @as(f64, @floatFromInt(compatibility_checks));

    print("   Average creation time: {d:.3f}ms per type\n", .{avg_creation_time});
    print("   Average compatibility time: {d:.6f}ms per check\n", .{avg_compatibility_time});

    // Should be sub-millisecond for individual operations
    try testing.expect(avg_creation_time < 1.0);
    try testing.expect(avg_compatibility_time < 0.1);

    print("   ✅ Performance requirements met\n");

    // Test memory usage
    const stats = system.getStatistics();
    print("   Memory usage: {} total types, {} cache entries\n", .{ stats.total_types, stats.cache_entries });

    try testing.expect(stats.total_types >= num_types);

    print("⚡ Performance: ALL TESTS PASSED!\n");
}

test "Type System - Integration Test" {
    print("\n🔗 TYPE SYSTEM INTEGRATION TEST\n");
    print("===============================\n");

    const allocator = std.testing.allocator;

    const system = try TypeSystem.init(allocator);
    defer system.deinit();

    print("🧪 Test: Complex Type Composition\n");

    // Create complex nested types
    // Array of optional pointers to functions: [10]?*fn(string) -> bool

    // 1. Function type: (string) -> bool
    const func_params = [_]TypeId{system.primitives.string};
    const func_type_id = try system.createFunctionType(&func_params, system.primitives.bool, true);

    // 2. Pointer to function: *fn(string) -> bool
    const ptr_to_func_id = try system.createPointerType(func_type_id, .immutable, .non_null);

    // 3. Optional pointer: ?*fn(string) -> bool
    const opt_ptr_id = try system.createOptionalType(ptr_to_func_id);

    // 4. Array of optional pointers: [10]?*fn(string) -> bool
    const array_id = try system.createArrayType(opt_ptr_id, TypeSystem.Type.ArrayType.ArraySize{ .fixed = 10 });

    // Verify the complete type structure
    const array_type = system.getType(array_id).?;
    try testing.expect(array_type == .array);

    const array_def = array_type.array;
    try testing.expect(array_def.size.fixed == 10);

    const opt_type = system.getType(array_def.element_type).?;
    try testing.expect(opt_type == .optional);

    const ptr_type = system.getType(opt_type.optional.wrapped_type).?;
    try testing.expect(ptr_type == .pointer);

    const func_type = system.getType(ptr_type.pointer.pointee_type).?;
    try testing.expect(func_type == .function);

    const func_def = func_type.function;
    try testing.expect(func_def.parameters.len == 1);
    try testing.expect(func_def.parameters[0] == system.primitives.string);
    try testing.expect(func_def.return_type == system.primitives.bool);

    print("   ✅ Complex nested type structure created and verified\n");

    print("🧪 Test: Type System Statistics\n");

    const stats = system.getStatistics();
    print("   Total types: {}\n", .{stats.total_types});
    print("   Primitive types: {}\n", .{stats.primitive_types});
    print("   Custom types: {}\n", .{stats.custom_types});
    print("   Cache entries: {}\n", .{stats.cache_entries});

    try testing.expect(stats.total_types > stats.primitive_types);
    try testing.expect(stats.custom_types > 0);

    print("   ✅ Type system statistics reporting correctly\n");

    print("🔗 Integration: ALL TESTS PASSED!\n");
}
