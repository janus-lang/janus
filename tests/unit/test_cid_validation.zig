// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// CID Validation Tests - Core Utilities Testing
// Task 2.2: Implement CID Comparison and Validation - Testing
//
// These tests verify the CID comparison and validation utilities that are
// essential for reliable incremental compilation decisions.

const std = @import("std");
const testing = std.testing;
const CIDValidator = @import("../../compiler/libjanus/incremental/cid_validation.zig").CIDValidator;
const CIDComparisonResult = @import("../../compiler/libjanus/incremental/cid_validation.zig").CIDComparisonResult;
const IntegrityResult = @import("../../compiler/libjanus/incremental/cid_validation.zig").IntegrityResult;
const BenchmarkResult = @import("../../compiler/libjanus/incremental/cid_validation.zig").BenchmarkResult;
const InterfaceCID = @import("../../compiler/libjanus/incremental/interface_cid.zig").InterfaceCID;
const SemanticCID = @import("../../compiler/libjanus/incremental/compilation_unit.zig").SemanticCID;

test "CID validation - InterfaceCID comparison" {
    std.debug.print("CID validation test - InterfaceCID comparison\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var validator = CIDValidator.init(allocator);

    // Test identical CIDs
    const cid1 = InterfaceCID{ .hash = [_]u8{1} ** 32 };
    const cid2 = InterfaceCID{ .hash = [_]u8{1} ** 32 };

    const result_identical = try validator.compareInterfaceCIDs(cid1, cid2);
    try testing.expect(result_identical.are_equal);
    try testing.expectEqual(@as(u32, 0), result_identical.details.interface_cid.hash_difference_count);

    // Test different CIDs
    const cid3 = InterfaceCID{ .hash = [_]u8{2} ** 32 };
    const result_different = try validator.compareInterfaceCIDs(cid1, cid3);
    try testing.expect(!result_different.are_equal);
    try testing.expectEqual(@as(u32, 32), result_different.details.interface_cid.hash_difference_count);

    // Test partially different CIDs
    var partial_hash = [_]u8{1} ** 32;
    partial_hash[0] = 2; // Change only first byte
    const cid4 = InterfaceCID{ .hash = partial_hash };
    const result_partial = try validator.compareInterfaceCIDs(cid1, cid4);
    try testing.expect(!result_partial.are_equal);
    try testing.expectEqual(@as(u32, 1), result_partial.details.interface_cid.hash_difference_count);
}

test "CID validation - SemanticCID comparison" {
    std.debug.print("CID validation test - SemanticCID comparison\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var validator = CIDValidator.init(allocator);

    // Test identical semantic CIDs
    const semantic_cid1 = SemanticCID{ .hash = [_]u8{10} ** 32 };
    const semantic_cid2 = SemanticCID{ .hash = [_]u8{10} ** 32 };

    const result = try validator.compareSemanticCIDs(semantic_cid1, semantic_cid2);
    try testing.expect(result.are_equal);
    try testing.expectEqual(@as(u32, 0), result.details.semantic_cid.hash_difference_count);

    // Test different semantic CIDs
    const semantic_cid3 = SemanticCID{ .hash = [_]u8{20} ** 32 };
    const result_different = try validator.compareSemanticCIDs(semantic_cid1, semantic_cid3);
    try testing.expect(!result_different.are_equal);
    try testing.expectEqual(@as(u32, 32), result_different.details.semantic_cid.hash_difference_count);
}

test "CID validation - integrity verification" {
    std.debug.print("CID validation test - integrity verification\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var validator = CIDValidator.init(allocator);

    // Test valid hash (random-looking data)
    const valid_hash = [_]u8{ 0x1a, 0x2b, 0x3c, 0x4d, 0x5e, 0x6f, 0x70, 0x81 } ** 4;
    const valid_result = try validator.verifyIntegrity(&valid_hash);
    try testing.expect(valid_result.is_valid);
    try testing.expect(!valid_result.corruption_indicators.all_zeros);
    try testing.expect(!valid_result.corruption_indicators.all_ones);
    try testing.expect(!valid_result.corruption_indicators.pattern_detected);

    // Test corrupted hash (all zeros)
    const zero_hash = [_]u8{0} ** 32;
    const zero_result = try validator.verifyIntegrity(&zero_hash);
    try testing.expect(!zero_result.is_valid);
    try testing.expect(zero_result.corruption_indicators.all_zeros);

    // Test corrupted hash (all ones)
    const ones_hash = [_]u8{0xFF} ** 32;
    const ones_result = try validator.verifyIntegrity(&ones_hash);
    try testing.expect(!ones_result.is_valid);
    try testing.expect(ones_result.corruption_indicators.all_ones);

    // Test pattern detection (repeating 4-byte pattern)
    const pattern_hash = [_]u8{ 0xAB, 0xCD, 0xEF, 0x12 } ** 8;
    const pattern_result = try validator.verifyIntegrity(&pattern_hash);
    try testing.expect(!pattern_result.is_valid);
    try testing.expect(pattern_result.corruption_indicators.pattern_detected);
}

test "CID validation - diagnostics generation" {
    std.debug.print("CID validation test - diagnostics generation\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var validator = CIDValidator.init(allocator);

    // Create a comparison result
    const cid1 = InterfaceCID{ .hash = [_]u8{1} ** 32 };
    const cid2 = InterfaceCID{ .hash = [_]u8{2} ** 32 };
    const comparison_result = try validator.compareInterfaceCIDs(cid1, cid2);

    // Generate diagnostics
    var diagnostics = try validator.generateDiagnostics(&comparison_result);
    defer diagnostics.deinit();

    // Verify diagnostics contain useful information
    try testing.expect(diagnostics.recommendations.items.len > 0);
    try testing.expect(diagnostics.performance_analysis.is_fast); // Should be fast for simple comparison
    try testing.expect(diagnostics.performance_analysis.memory_efficient);
}

test "CID validation - performance benchmarking" {
    std.debug.print("CID validation test - performance benchmarking\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var validator = CIDValidator.init(allocator);

    // Benchmark InterfaceCID comparisons
    const cid1 = InterfaceCID{ .hash = [_]u8{1} ** 32 };
    const cid2 = InterfaceCID{ .hash = [_]u8{1} ** 32 };

    const benchmark_result = try validator.benchmarkComparison(1000, cid1, cid2);

    // Verify benchmark results are reasonable
    try testing.expectEqual(@as(u32, 1000), benchmark_result.iterations);
    try testing.expect(benchmark_result.total_time_ns > 0);
    try testing.expect(benchmark_result.average_time_ns > 0);
    try testing.expect(benchmark_result.operations_per_second > 0);
    try testing.expectEqual(@as(u64, 0), benchmark_result.memory_usage_bytes);

    // Performance should be very fast (sub-microsecond per operation)
    try testing.expect(benchmark_result.average_time_ns < 1000); // Less than 1 microsecond

    std.debug.print("  Benchmark: {} ops/sec, avg {}ns per comparison\n", .{
        benchmark_result.operations_per_second,
        benchmark_result.average_time_ns,
    });
}

test "CID validation - hash difference counting" {
    std.debug.print("CID validation test - hash difference counting\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var validator = CIDValidator.init(allocator);

    // Test various levels of hash differences
    const base_hash = [_]u8{0xAA} ** 32;

    // No differences
    const same_hash = [_]u8{0xAA} ** 32;
    const cid_same = InterfaceCID{ .hash = same_hash };
    const cid_base = InterfaceCID{ .hash = base_hash };
    const result_same = try validator.compareInterfaceCIDs(cid_base, cid_same);
    try testing.expectEqual(@as(u32, 0), result_same.details.interface_cid.hash_difference_count);

    // One byte difference
    var one_diff_hash = [_]u8{0xAA} ** 32;
    one_diff_hash[15] = 0xBB;
    const cid_one_diff = InterfaceCID{ .hash = one_diff_hash };
    const result_one_diff = try validator.compareInterfaceCIDs(cid_base, cid_one_diff);
    try testing.expectEqual(@as(u32, 1), result_one_diff.details.interface_cid.hash_difference_count);

    // Half bytes different
    var half_diff_hash = [_]u8{0xAA} ** 16 ++ [_]u8{0xBB} ** 16;
    const cid_half_diff = InterfaceCID{ .hash = half_diff_hash };
    const result_half_diff = try validator.compareInterfaceCIDs(cid_base, cid_half_diff);
    try testing.expectEqual(@as(u32, 16), result_half_diff.details.interface_cid.hash_difference_count);

    // All bytes different
    const all_diff_hash = [_]u8{0xBB} ** 32;
    const cid_all_diff = InterfaceCID{ .hash = all_diff_hash };
    const result_all_diff = try validator.compareInterfaceCIDs(cid_base, cid_all_diff);
    try testing.expectEqual(@as(u32, 32), result_all_diff.details.interface_cid.hash_difference_count);
}

test "CID validation - entropy calculation" {
    std.debug.print("CID validation test - entropy calculation\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var validator = CIDValidator.init(allocator);

    // Test entropy of different hash patterns

    // Low entropy (all same bytes)
    const low_entropy_hash = [_]u8{0x42} ** 32;
    const low_entropy_result = try validator.verifyIntegrity(&low_entropy_hash);
    try testing.expect(low_entropy_result.corruption_indicators.entropy_score < 1.0);

    // High entropy (varied bytes)
    var high_entropy_hash: [32]u8 = undefined;
    for (&high_entropy_hash, 0..) |*byte, i| {
        byte.* = @as(u8, @intCast(i * 7 + 13)); // Pseudo-random pattern
    }
    const high_entropy_result = try validator.verifyIntegrity(&high_entropy_hash);
    try testing.expect(high_entropy_result.corruption_indicators.entropy_score > 4.0);

    std.debug.print("  Low entropy score: {d:.2}\n", .{low_entropy_result.corruption_indicators.entropy_score});
    std.debug.print("  High entropy score: {d:.2}\n", .{high_entropy_result.corruption_indicators.entropy_score});
}

test "CID validation - performance metrics" {
    std.debug.print("CID validation test - performance metrics\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var validator = CIDValidator.init(allocator);

    // Test that comparison metrics are captured correctly
    const cid1 = InterfaceCID{ .hash = [_]u8{1} ** 32 };
    const cid2 = InterfaceCID{ .hash = [_]u8{2} ** 32 };

    const result = try validator.compareInterfaceCIDs(cid1, cid2);

    // Verify metrics are reasonable
    try testing.expect(result.metrics.comparison_time_ns > 0);
    try testing.expect(result.metrics.comparison_time_ns < 10_000_000); // Less than 10ms
    try testing.expectEqual(@as(u64, 0), result.metrics.memory_used_bytes);
    try testing.expectEqual(@as(u32, 1), result.metrics.hash_operations);

    std.debug.print("  Comparison time: {}ns\n", .{result.metrics.comparison_time_ns});
}

// Test utilities for creating controlled CID validation scenarios

fn createTestInterfaceCID(pattern: u8) InterfaceCID {
    return InterfaceCID{ .hash = [_]u8{pattern} ** 32 };
}

fn createTestSemanticCID(pattern: u8) SemanticCID {
    return SemanticCID{ .hash = [_]u8{pattern} ** 32 };
}

fn createRandomHash(seed: u64) [32]u8 {
    var hash: [32]u8 = undefined;
    var prng = std.rand.DefaultPrng.init(seed);
    const random = prng.random();
    random.bytes(&hash);
    return hash;
}

// Verification utilities for testing CID validation behavior

fn verifyComparisonResult(result: *const CIDComparisonResult, expected_equal: bool) !void {
    try testing.expectEqual(expected_equal, result.are_equal);
    try testing.expect(result.metrics.comparison_time_ns > 0);
    try testing.expect(result.metrics.hash_operations > 0);
}

fn verifyIntegrityResult(result: *const IntegrityResult, expected_valid: bool) !void {
    try testing.expectEqual(expected_valid, result.is_valid);
    try testing.expect(result.corruption_indicators.entropy_score >= 0.0);
    try testing.expect(result.corruption_indicators.entropy_score <= 8.0); // Max theoretical entropy
}

// Performance testing utilities

fn benchmarkCIDOperations(validator: *CIDValidator, iterations: u32) !void {
    const cid1 = createTestInterfaceCID(0xAA);
    const cid2 = createTestInterfaceCID(0xBB);

    const benchmark = try validator.benchmarkComparison(iterations, cid1, cid2);

    std.debug.print("  Benchmark results: {}\n", .{benchmark});

    // Verify performance is acceptable
    try testing.expect(benchmark.operations_per_second > 100_000); // At least 100k ops/sec
    try testing.expect(benchmark.average_time_ns < 10_000); // Less than 10 microseconds
}
