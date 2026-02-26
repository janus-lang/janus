// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Type System Performance Test Suite
//!
//! This test suite validates the performance characteristics of the optimized
//! type system implementation with canonical hashing.

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const TypeCanonicalHasher = @import("../../../compiler/semantic/type_canonical_hash.zig").TypeCanonicalHasher;
const TypeSystem = @import("../../../compiler/semantic/type_system.zig").TypeSystem;
const TypeId = @import("../../../compiler/semantic/type_system.zig").TypeId;
const type_system_benchmark = @import("../../../compiler/semantic/type_system_benchmark.zig");

test "canonical hashing performance scaling" {
    const allocator = testing.allocator;

    var type_system = try TypeSystem.init(allocator);
    defer type_system.deinit();

    // Test scaling from small to large operation counts
    const small_ops = 100;
    const large_ops = 10000; // 100x larger

    // Small scale benchmark
    const start_small = compat_time.nanoTimestamp();
    for (0..small_ops) |i| {
        const param_types = [_]TypeId{type_system.getPrimitiveType(.i32)};
        _ = try type_system.createFunctionType(&param_types, type_system.getPrimitiveType(.i32), .janus_call);

        if (i % 10 == 0) {
            _ = try type_system.createPointerType(type_system.getPrimitiveType(.f64), true);
        }
    }
    const end_small = compat_time.nanoTimestamp();
    const small_time = end_small - start_small;

    // Large scale benchmark
    const start_large = compat_time.nanoTimestamp();
    for (0..large_ops) |i| {
        const param_types = [_]TypeId{type_system.getPrimitiveType(.i32)};
        _ = try type_system.createFunctionType(&param_types, type_system.getPrimitiveType(.i32), .janus_call);

        if (i % 10 == 0) {
            _ = try type_system.createPointerType(type_system.getPrimitiveType(.f64), true);
        }
    }
    const end_large = compat_time.nanoTimestamp();
    const large_time = end_large - start_large;

    // Calculate scaling factor
    const expected_linear_time = small_time * (large_ops / small_ops);
    const actual_scaling = @as(f64, @floatFromInt(large_time)) / @as(f64, @floatFromInt(expected_linear_time));

    // Verify reasonable scaling (should be much better than O(N²))
    try testing.expect(actual_scaling < 5.0); // Allow some overhead, but nowhere near O(N²)
}

test "canonical hash consistency and uniqueness" {
    const allocator = testing.allocator;

    var hasher = TypeCanonicalHasher.init(allocator);
    defer hasher.deinit();

    const TypeSystemModule = @import("../../../compiler/semantic/type_system.zig");

    // Test identical types produce identical hashes
    const type1 = TypeSystemModule.TypeInfo{
        .kind = .{ .primitive = .i32 },
        .size = 4,
        .alignment = 4,
    };

    const type2 = TypeSystemModule.TypeInfo{
        .kind = .{ .primitive = .i32 },
        .size = 4,
        .alignment = 4,
    };

    const hash1 = @import("../../../compiler/semantic/type_canonical_hash.zig").computeCanonicalHash(&type1);
    const hash2 = @import("../../../compiler/semantic/type_canonical_hash.zig").computeCanonicalHash(&type2);

    try testing.expect(hash1 == hash2);

    // Test different types produce different hashes
    const type3 = TypeSystemModule.TypeInfo{
        .kind = .{ .primitive = .f64 },
        .size = 8,
        .alignment = 8,
    };

    const hash3 = @import("../../../compiler/semantic/type_canonical_hash.zig").computeCanonicalHash(&type3);

    try testing.expect(hash1 != hash3);

    // Test hash map operations
    const type_id1 = TypeId{ .id = 1 };
    const type_id2 = TypeId{ .id = 2 };

    try hasher.registerType(&type1, type_id1);
    try hasher.registerType(&type3, type_id2);

    // Find existing types
    const found1 = hasher.findExistingType(&type1);
    const found2 = hasher.findExistingType(&type3);

    try testing.expect(found1 != null and found1.?.id == 1);
    try testing.expect(found2 != null and found2.?.id == 2);
}

test "type deduplication performance" {
    const allocator = testing.allocator;

    var type_system = try TypeSystem.init(allocator);
    defer type_system.deinit();

    const operation_count = 5000;

    const start_time = compat_time.nanoTimestamp();

    // Create many identical types to test deduplication efficiency
    for (0..operation_count) |i| {
        // These should all deduplicate to the same type
        const param_types = [_]TypeId{
            type_system.getPrimitiveType(.i32),
            type_system.getPrimitiveType(.f64),
        };
        const func_type = try type_system.createFunctionType(&param_types, type_system.getPrimitiveType(.bool), .janus_call);

        // Verify deduplication is working
        if (i > 0) {
            // All function types should have the same ID due to deduplication
            try testing.expect(func_type.id == 8); // Should be consistent after primitives
        }

        // Mix in some pointer types
        if (i % 100 == 0) {
            _ = try type_system.createPointerType(type_system.getPrimitiveType(.string), true);
        }
    }

    const end_time = compat_time.nanoTimestamp();
    const total_time_ns = end_time - start_time;
    const total_time_ms = @as(f64, @floatFromInt(total_time_ns)) / 1_000_000.0;
    const ops_per_second = @as(f64, @floatFromInt(operation_count)) / (total_time_ms / 1000.0);

    // Should be very fast due to O(1) hash lookups
    try testing.expect(ops_per_second > 50_000); // At least 50K ops/sec
    try testing.expect(total_time_ms < 200.0); // Less than 200ms
}

test "memory efficiency with canonical hashing" {
    const allocator = testing.allocator;

    var type_system = try TypeSystem.init(allocator);
    defer type_system.deinit();

    // Create many types and verify memory usage is reasonable
    const type_count = 1000;

    for (0..type_count) |i| {
        // Create diverse types to test memory efficiency
        switch (i % 4) {
            0 => {
                const param_types = [_]TypeId{type_system.getPrimitiveType(.i32)};
                _ = try type_system.createFunctionType(&param_types, type_system.getPrimitiveType(.i32), .janus_call);
            },
            1 => {
                _ = try type_system.createPointerType(type_system.getPrimitiveType(.f64), i % 2 == 0);
            },
            2 => {
                const size = @as(u32, @intCast((i % 10) + 1));
                _ = try type_system.createArrayType(type_system.getPrimitiveType(.bool), size);
            },
            3 => {
                _ = try type_system.createSliceType(type_system.getPrimitiveType(.string), i % 2 == 0);
            },
            else => unreachable,
        }
    }
}

test "comprehensive performance benchmark" {
    const allocator = testing.allocator;

    // Run the full benchmark suite
    const results = try type_system_benchmark.runPerformanceBenchmark(allocator);

    // Verify performance meets requirements
    try testing.expect(results.operations_per_second > 10_000); // At least 10K ops/sec
    try testing.expect(results.hash_time_ms < 1000.0); // Less than 1 second for largest test
}
