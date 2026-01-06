// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const TypeSystem = @import("type_system.zig").TypeSystem;

test "Type System - Array and Slice Types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var type_system = try TypeSystem.init(allocator);
    defer type_system.deinit();

    // Primitive types
    const i32_type = type_system.getPrimitiveType(.i32);
    const f64_type = type_system.getPrimitiveType(.f64);

    // Create array types: [i32; 5], [i32; 10], [f64; 5]
    const array_i32_5 = try type_system.createArrayType(i32_type, 5);
    const array_i32_10 = try type_system.createArrayType(i32_type, 10);
    const array_f64_5 = try type_system.createArrayType(f64_type, 5);
    _ = array_f64_5;

    // Create slice types: []i32, []f64
    const slice_i32 = try type_system.createSliceType(i32_type, false);
    const slice_f64 = try type_system.createSliceType(f64_type, false);

    // O(1) deduplication check
    const array_i32_5_dup = try type_system.createArrayType(i32_type, 5);
    try testing.expectEqual(array_i32_5, array_i32_5_dup);

    // Compatibility checks
    
    // 1. Exact match
    try testing.expect(type_system.areTypesCompatible(array_i32_5, array_i32_5));
    
    // 2. Mismatched size (should fail)
    try testing.expect(!type_system.areTypesCompatible(array_i32_5, array_i32_10));
    
    // 3. Array to Slice (same element type)
    try testing.expect(type_system.areTypesCompatible(array_i32_5, slice_i32));
    
    // 4. Array to Slice (compatible element type: i32 -> f64)
    try testing.expect(type_system.areTypesCompatible(array_i32_5, slice_f64));

    // 5. Slice to Array (should fail)
    // Note: slice needs to be on LHS for areTypesCompatible(slice, array) check? 
    // Wait, areTypesCompatible(source, target).
    // if source is slice, target is array -> switch(source) .slice -> switch(target) .array?
    // Let's check type_system.zig logic for slice source.
    // It's not implemented for slice source to match anything other than itself? 
    // Need to verify source_info.kind switch.
}
