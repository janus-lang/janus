// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Type System Tests: Error Union Types
//!
//! Tests that error union type creation and operations work correctly:
//! - Error union type creation (T ! E)
//! - Type deduplication via canonical hashing
//! - Error union type queries (isErrorUnion, getPayload, getError)
//! - Error union type size and alignment calculation

const std = @import("std");
const testing = std.testing;
const semantic = @import("semantic");

test "Type System: Create error union type" {
    const allocator = testing.allocator;

    var type_system = try semantic.TypeSystem.init(allocator);
    defer type_system.deinit();

    // Create i32 ! ErrorType
    const i32_type = type_system.getPrimitiveType(.i32);
    const error_type = type_system.getPrimitiveType(.i32); // Placeholder for error type

    const error_union = try type_system.createErrorUnionType(i32_type, error_type);

    // Verify it's an error union
    try testing.expect(type_system.isErrorUnion(error_union));

    // Verify payload and error types
    const payload = type_system.getErrorUnionPayload(error_union);
    try testing.expect(payload != null);
    try testing.expect(payload.?.id == i32_type.id);

    const err = type_system.getErrorUnionError(error_union);
    try testing.expect(err != null);
    try testing.expect(err.?.id == error_type.id);
}

test "Type System: Error union canonical hashing" {
    const allocator = testing.allocator;

    var type_system = try semantic.TypeSystem.init(allocator);
    defer type_system.deinit();

    const i32_type = type_system.getPrimitiveType(.i32);
    const error_type = type_system.getPrimitiveType(.i64);

    // Create same error union type twice
    const error_union_1 = try type_system.createErrorUnionType(i32_type, error_type);
    const error_union_2 = try type_system.createErrorUnionType(i32_type, error_type);

    // Should be deduplicated (same TypeId)
    try testing.expectEqual(error_union_1.id, error_union_2.id);
}

test "Type System: Error union type queries" {
    const allocator = testing.allocator;

    var type_system = try semantic.TypeSystem.init(allocator);
    defer type_system.deinit();

    const i32_type = type_system.getPrimitiveType(.i32);
    const error_type = type_system.getPrimitiveType(.i64);

    const error_union = try type_system.createErrorUnionType(i32_type, error_type);

    // isErrorUnion should return true
    try testing.expect(type_system.isErrorUnion(error_union));

    // getErrorUnionPayload should return i32
    const payload = type_system.getErrorUnionPayload(error_union);
    try testing.expect(payload != null);
    try testing.expectEqual(i32_type.id, payload.?.id);

    // getErrorUnionError should return i64
    const err = type_system.getErrorUnionError(error_union);
    try testing.expect(err != null);
    try testing.expectEqual(error_type.id, err.?.id);

    // Non-error-union types should return null
    const payload_non_eu = type_system.getErrorUnionPayload(i32_type);
    try testing.expect(payload_non_eu == null);

    const err_non_eu = type_system.getErrorUnionError(i32_type);
    try testing.expect(err_non_eu == null);

    // isErrorUnion should return false for non-error-unions
    try testing.expect(!type_system.isErrorUnion(i32_type));
}

test "Type System: Error union size and alignment" {
    const allocator = testing.allocator;

    var type_system = try semantic.TypeSystem.init(allocator);
    defer type_system.deinit();

    const i32_type = type_system.getPrimitiveType(.i32);
    const i64_type = type_system.getPrimitiveType(.i64);

    const error_union = try type_system.createErrorUnionType(i32_type, i64_type);

    const error_union_info = type_system.getTypeInfo(error_union);

    // Size should be max(i32, i64) + 1 discriminant = 8 + 1 = 9
    try testing.expectEqual(@as(u32, 9), error_union_info.size);

    // Alignment should be max(i32_align, i64_align) = max(4, 8) = 8
    try testing.expectEqual(@as(u32, 8), error_union_info.alignment);
}

test "Type System: Nested error unions" {
    const allocator = testing.allocator;

    var type_system = try semantic.TypeSystem.init(allocator);
    defer type_system.deinit();

    const i32_type = type_system.getPrimitiveType(.i32);
    const error_type_1 = type_system.getPrimitiveType(.i64);
    const error_type_2 = type_system.getPrimitiveType(.bool);

    // Create i32 ! Error1
    const inner_error_union = try type_system.createErrorUnionType(i32_type, error_type_1);

    // Create (i32 ! Error1) ! Error2
    const outer_error_union = try type_system.createErrorUnionType(inner_error_union, error_type_2);

    // Verify outer is error union
    try testing.expect(type_system.isErrorUnion(outer_error_union));

    // Verify outer payload is inner error union
    const outer_payload = type_system.getErrorUnionPayload(outer_error_union);
    try testing.expect(outer_payload != null);
    try testing.expectEqual(inner_error_union.id, outer_payload.?.id);

    // Verify inner is also error union
    try testing.expect(type_system.isErrorUnion(inner_error_union));
}

test "Type System: Different error unions are distinct" {
    const allocator = testing.allocator;

    var type_system = try semantic.TypeSystem.init(allocator);
    defer type_system.deinit();

    const i32_type = type_system.getPrimitiveType(.i32);
    const i64_type = type_system.getPrimitiveType(.i64);
    const error_type_1 = type_system.getPrimitiveType(.bool);
    const error_type_2 = type_system.getPrimitiveType(.f32);

    // Create i32 ! Error1
    const error_union_1 = try type_system.createErrorUnionType(i32_type, error_type_1);

    // Create i64 ! Error1
    const error_union_2 = try type_system.createErrorUnionType(i64_type, error_type_1);

    // Create i32 ! Error2
    const error_union_3 = try type_system.createErrorUnionType(i32_type, error_type_2);

    // All should be different
    try testing.expect(error_union_1.id != error_union_2.id);
    try testing.expect(error_union_1.id != error_union_3.id);
    try testing.expect(error_union_2.id != error_union_3.id);
}
