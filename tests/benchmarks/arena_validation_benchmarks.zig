// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Arena Validation Benchmarks
//!
//! Comprehensive benchmarks demonstrating arena allocation integration
//! for zero-leak validation operations.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import the arena validation proof
const ArenaValidationProof = @import("../../compiler/semantic/arena_validation_proof.zig").ArenaValidationProof;
const ValidationMemoryStats = @import("../../compiler/semantic/arena_validation_proof.zig").ValidationMemoryStats;
const demonstrateZeroLeakValidation = @import("../../compiler/semantic/arena_validation_proof.zig").demonstrateZeroLeakValidation;
const benchmarkArenaCleanup = @import("../../compiler/semantic/arena_validation_proof.zig").benchmarkArenaCleanup;

/// Comprehensive benchmark results
const BenchmarkResults = struct {
    test_name: []const u8,
    iterations: usize,
    avg_duration_ns: i128,
    avg_memory_usage: usize,
    zero_leak_guarantee: bool,
    performance_rating: PerformanceRating,

    const PerformanceRating = enum {
        excellent,
        good,
        acceptable,
        poor,
    };

    pub fn format(self: BenchmarkResults, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            \\BenchmarkResults{{
            \\  Test: {s}
            \\  Iterations: {}
            \\  Avg Duration: {d:.2}μs
            \\  Avg Memory: {d:.2}KB
            \\  Zero Leak: {}
            \\  Rating: {}
            \\}}
        , .{
            self.test_name,
            self.iterations,
            @as(f64, @floatFromInt(self.avg_duration_ns)) / 1000.0,
            @as(f64, @floatFromInt(self.avg_memory_usage)) / 1024.0,
            self.zero_leak_guarantee,
            self.performance_rating,
        });
    }
};

/// Arena validation benchmark suite
pub const ArenaValidationBenchmarks = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ArenaValidationBenchmarks {
        return ArenaValidationBenchmarks{ .allocator = allocator };
    }

    /// Benchmark basic arena validation operations
    pub fn benchmarkBasicOperations(self: *ArenaValidationBenchmarks, iterations: usize) !BenchmarkResults {
        var total_duration: i128 = 0;
        var total_memory: usize = 0;
        var all_zero_leak = true;

        for (0..iterations) |i| {
            var context = ArenaValidationProof.init(self.allocator);
            defer context.deinit();

            // Simulate validation work
            context.simulateValidationWork((i % 100) + 1);

            const stats = context.getStats();
            total_duration += stats.getDuration();
            total_memory += stats.arena_capacity;
            all_zero_leak = all_zero_leak and stats.zero_leak_guaranteed;
        }

        const avg_duration = @divTrunc(total_duration, @as(i128, @intCast(iterations)));
        const avg_memory = total_memory / iterations;

        return BenchmarkResults{
            .test_name = "Basic Operations",
            .iterations = iterations,
            .avg_duration_ns = avg_duration,
            .avg_memory_usage = avg_memory,
            .zero_leak_guarantee = all_zero_leak,
            .performance_rating = ratePerformance(avg_duration),
        };
    }

    /// Benchmark scalability with increasing work sizes
    pub fn benchmarkScalability(self: *ArenaValidationBenchmarks, max_work_size: usize) !BenchmarkResults {
        var total_duration: i128 = 0;
        var total_memory: usize = 0;
        var all_zero_leak = true;
        const iterations = 100;

        for (0..iterations) |i| {
            var context = ArenaValidationProof.init(self.allocator);
            defer context.deinit();

            // Scale work size from 1 to max_work_size
            const work_size = (i * max_work_size / iterations) + 1;
            context.simulateValidationWork(work_size);

            const stats = context.getStats();
            total_duration += stats.getDuration();
            total_memory += stats.arena_capacity;
            all_zero_leak = all_zero_leak and stats.zero_leak_guaranteed;
        }

        const avg_duration = @divTrunc(total_duration, iterations);
        const avg_memory = total_memory / iterations;

        return BenchmarkResults{
            .test_name = "Scalability Test",
            .iterations = iterations,
            .avg_duration_ns = avg_duration,
            .avg_memory_usage = avg_memory,
            .zero_leak_guarantee = all_zero_leak,
            .performance_rating = ratePerformance(avg_duration),
        };
    }

    /// Benchmark cleanup performance (O(1) verification)
    pub fn benchmarkCleanupPerformance(self: *ArenaValidationBenchmarks) !BenchmarkResults {
        const benchmark_result = try benchmarkArenaCleanup(self.allocator, 1000);

        return BenchmarkResults{
            .test_name = "Cleanup Performance",
            .iterations = benchmark_result.total_iterations,
            .avg_duration_ns = benchmark_result.avg_cleanup_time_ns,
            .avg_memory_usage = 0, // Cleanup doesn't use memory
            .zero_leak_guarantee = benchmark_result.zero_leaks_guaranteed,
            .performance_rating = ratePerformance(benchmark_result.avg_cleanup_time_ns),
        };
    }

    /// Benchmark stress test with many contexts
    pub fn benchmarkStressTest(self: *ArenaValidationBenchmarks, context_count: usize) !BenchmarkResults {
        var total_duration: i128 = 0;
        var total_memory: usize = 0;
        var all_zero_leak = true;

        const start_time = std.time.nanoTimestamp();

        for (0..context_count) |i| {
            var context = ArenaValidationProof.init(self.allocator);
            defer context.deinit();

            // Varying work loads
            context.simulateValidationWork((i % 50) + 10);

            const stats = context.getStats();
            total_duration += stats.getDuration();
            total_memory += stats.arena_capacity;
            all_zero_leak = all_zero_leak and stats.zero_leak_guaranteed;
        }

        const end_time = std.time.nanoTimestamp();
        const total_test_duration = end_time - start_time;
        const avg_duration = @divTrunc(total_test_duration, @as(i128, @intCast(context_count)));
        const avg_memory = total_memory / context_count;

        return BenchmarkResults{
            .test_name = "Stress Test",
            .iterations = context_count,
            .avg_duration_ns = avg_duration,
            .avg_memory_usage = avg_memory,
            .zero_leak_guarantee = all_zero_leak,
            .performance_rating = ratePerformance(avg_duration),
        };
    }

    /// Run comprehensive benchmark suite
    pub fn runComprehensiveBenchmarks(self: *ArenaValidationBenchmarks) !void {
        std.log.info("Running Arena Validation Benchmarks...", .{});

        // Basic operations benchmark
        const basic_results = try self.benchmarkBasicOperations(1000);
        std.log.info("{}", .{basic_results});

        // Scalability benchmark
        const scalability_results = try self.benchmarkScalability(1000);
        std.log.info("{}", .{scalability_results});

        // Cleanup performance benchmark
        const cleanup_results = try self.benchmarkCleanupPerformance();
        std.log.info("{}", .{cleanup_results});

        // Stress test benchmark
        const stress_results = try self.benchmarkStressTest(5000);
        std.log.info("{}", .{stress_results});

        // Summary
        std.log.info("\n=== Benchmark Summary ===", .{});
        std.log.info("All tests maintain zero-leak guarantee: {}", .{
            basic_results.zero_leak_guarantee and
                scalability_results.zero_leak_guarantee and
                cleanup_results.zero_leak_guarantee and
                stress_results.zero_leak_guarantee,
        });

        const avg_performance_score = (@intFromEnum(basic_results.performance_rating) +
            @intFromEnum(scalability_results.performance_rating) +
            @intFromEnum(cleanup_results.performance_rating) +
            @intFromEnum(stress_results.performance_rating)) / 4;

        const overall_rating: BenchmarkResults.PerformanceRating = @enumFromInt(avg_performance_score);
        std.log.info("Overall Performance Rating: {}", .{overall_rating});

        if (!basic_results.zero_leak_guarantee or
            !scalability_results.zero_leak_guarantee or
            !cleanup_results.zero_leak_guarantee or
            !stress_results.zero_leak_guarantee)
        {
            return error.ZeroLeakGuaranteeViolated;
        }

        std.log.info("✅ All benchmarks passed with zero-leak guarantee maintained", .{});
    }

    fn ratePerformance(duration_ns: i128) BenchmarkResults.PerformanceRating {
        if (duration_ns < 1000) return .excellent; // < 1μs
        if (duration_ns < 10000) return .serviceod; // < 10μs
        if (duration_ns < 100000) return .acceptable; // < 100μs
        return .poor; // >= 100μs
    }
};

// Benchmark tests
test "basic operations benchmark" {
    var benchmarks = ArenaValidationBenchmarks.init(testing.allocator);
    const results = try benchmarks.benchmarkBasicOperations(100);

    try testing.expect(results.iterations == 100);
    try testing.expect(results.zero_leak_guarantee == true);
    try testing.expect(results.avg_duration_ns >= 0);
}

test "scalability benchmark" {
    var benchmarks = ArenaValidationBenchmarks.init(testing.allocator);
    const results = try benchmarks.benchmarkScalability(500);

    try testing.expect(results.iterations == 100);
    try testing.expect(results.zero_leak_guarantee == true);
    try testing.expect(results.avg_duration_ns >= 0);
}

test "cleanup performance benchmark" {
    var benchmarks = ArenaValidationBenchmarks.init(testing.allocator);
    const results = try benchmarks.benchmarkCleanupPerformance();

    try testing.expect(results.iterations > 0);
    try testing.expect(results.zero_leak_guarantee == true);
    try testing.expect(results.avg_duration_ns >= 0);
    try testing.expect(results.avg_duration_ns < 1000000); // Should be fast (< 1ms)
}

test "stress test benchmark" {
    var benchmarks = ArenaValidationBenchmarks.init(testing.allocator);
    const results = try benchmarks.benchmarkStressTest(1000);

    try testing.expect(results.iterations == 1000);
    try testing.expect(results.zero_leak_guarantee == true);
    try testing.expect(results.avg_duration_ns >= 0);
}

test "benchmark results formatting" {
    const results = BenchmarkResults{
        .test_name = "Test Benchmark",
        .iterations = 100,
        .avg_duration_ns = 5000, // 5μs
        .avg_memory_usage = 2048, // 2KB
        .zero_leak_guarantee = true,
        .performance_rating = .serviceod,
    };

    var buffer: [512]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buffer, "{}", .{results});

    try testing.expect(std.mem.indexOf(u8, formatted, "Test Benchmark") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "100") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "true") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "good") != null);
}

test "performance rating system" {
    const benchmarks = ArenaValidationBenchmarks.init(testing.allocator);

    // Test performance rating thresholds
    try testing.expect(benchmarks.ratePerformance(500) == .excellent);
    try testing.expect(benchmarks.ratePerformance(5000) == .serviceod);
    try testing.expect(benchmarks.ratePerformance(50000) == .acceptable);
    try testing.expect(benchmarks.ratePerformance(500000) == .poor);
}

test "zero-leak guarantee verification" {
    // Use GPA to verify no leaks in benchmark operations
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in benchmark operations!", .{});
        }
    }

    const allocator = gpa.allocator();
    var benchmarks = ArenaValidationBenchmarks.init(allocator);

    // Run a subset of benchmarks
    const basic_results = try benchmarks.benchmarkBasicOperations(50);
    const cleanup_results = try benchmarks.benchmarkCleanupPerformance();

    // Verify zero-leak guarantee
    try testing.expect(basic_results.zero_leak_guarantee == true);
    try testing.expect(cleanup_results.zero_leak_guarantee == true);
}
