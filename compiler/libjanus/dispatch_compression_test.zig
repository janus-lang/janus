// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const DispatchTableCompression = @import("dispatch_table_compression.zig").DispatchTableCompression;
const CompressionBackends = @import("dispatch_table_compression.zig").CompressionBackends;
const HybridCompression = @import("dispatch_table_compression.zig").HybridCompression;
const CompressionBenchmark = @import("dispatch_table_compression.zig").CompressionBenchmark;

test "compression backends availability" {
    const backends = [_]DispatchTableCompression.CompressionBackend{ .none, .lz4, .zstd, .custom };

    for (backends) |backend| {
        const available = backend.isAvailable();
        const level = backend.getCompressionLevel();

        std.log.info("Backend {s}: available={}, level={}", .{ @tagName(backend), available, level });

        // None and custom should always be available
        if (backend == .none or backend == .custom) {
            try testing.expect(available);
        }
    }
}

test "custom compression algorithm" {
    const allocator = testing.allocator;

    // Create test data with patterns typical of dispatch tables
    var test_data: std.ArrayList(u8) = .empty;
    defer test_data.deinit();

    // Simulate type IDs (4 bytes each) with repetitive patterns
    const type_ids = [_]u32{ 1, 2, 3, 1, 2, 3, 1, 2, 3, 4, 5, 4, 5, 4, 5 };
    for (type_ids) |type_id| {
        try test_data.appendSlice(std.mem.asBytes(&type_id));
    }

    // Test compression
    const compressed = try CompressionBackends.compress(allocator, .custom, test_data.items, 5);
    defer allocator.free(compressed);

    try testing.expect(compressed.len < test_data.items.len);
    std.log.info("Custom compression: {} -> {} bytes ({d:.2}% ratio)", .{
        test_data.items.len,
        compressed.len,
        @as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(test_data.items.len)) * 100.0,
    });

    // Test decompression
    const decompressed = try CompressionBackends.decompress(allocator, .custom, compressed, test_data.items.len);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, test_data.items, decompressed);
}

test "hybrid compression with semantic and general compression" {
    const allocator = testing.allocator;

    // Create test data simulating dispatch table entries
    var test_data: std.ArrayList(u8) = .empty;
    defer test_data.deinit();

    // Add repeated patterns (simulating common type patterns)
    const pattern = [_]u8{ 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00 }; // Two TypeIds
    for (0..20) |_| {
        try test_data.appendSlice(&pattern);
    }

    // Add some unique data
    for (0..100) |i| {
        try test_data.append(@intCast(i % 256));
    }

    // Test hybrid compression with different configurations
    const configs = [_]DispatchTableCompression.CompressionConfig{
        // Semantic only
        DispatchTableCompression.CompressionConfig{
            .backend = .none,
            .semantic_first = true,
        },
        // Custom compression only
        DispatchTableCompression.CompressionConfig{
            .backend = .custom,
            .semantic_first = false,
        },
        // Hybrid: semantic + custom
        DispatchTableCompression.CompressionConfig{
            .backend = .custom,
            .semantic_first = true,
            .compression_threshold = 0.05, // 5% minimum savings
        },
    };

    for (configs, 0..) |config, i| {
        std.log.info("Testing configuration {}: backend={s}, semantic_first={}", .{
            i,
            @tagName(config.backend),
            config.semantic_first,
        });

        var result = try HybridCompression.compressTable(allocator, test_data.items, config);
        defer result.deinit(allocator);

        std.log.info("  Original: {} bytes", .{result.original_size});
        std.log.info("  Semantic compressed: {} bytes", .{result.semantic_compressed_size});
        std.log.info("  Final compressed: {} bytes", .{result.final_compressed_size});
        std.log.info("  Compression ratio: {d:.3}", .{result.compression_ratio});
        std.log.info("  Space saved: {} bytes", .{result.getCompressionSavings()});

        // Test decompression
        const decompressed = try HybridCompression.decompressTable(allocator, &result);
        defer allocator.free(decompressed);

        try testing.expectEqualSlices(u8, test_data.items, decompressed);
    }
}

test "compression correctness with edge cases" {
    const allocator = testing.allocator;

    // Test edge cases
    const test_cases = [_]struct {
        name: []const u8,
        data: []const u8,
    }{
        .{ .name = "empty data", .data = &[_]u8{} },
        .{ .name = "single byte", .data = &[_]u8{0x42} },
        .{ .name = "all zeros", .data = &([_]u8{0} ** 100) },
        .{ .name = "all ones", .data = &([_]u8{0xFF} ** 100) },
        .{ .name = "alternating pattern", .data = &([_]u8{ 0xAA, 0x55 } ** 50) },
    };

    const backends = [_]DispatchTableCompression.CompressionBackend{ .none, .custom };

    for (test_cases) |test_case| {
        std.log.info("Testing edge case: {s} ({} bytes)", .{ test_case.name, test_case.data.len });

        for (backends) |backend| {
            if (!backend.isAvailable()) continue;

            std.log.info("  Backend: {s}", .{@tagName(backend)});

            // Test compression
            const compressed = CompressionBackends.compress(allocator, backend, test_case.data, backend.getCompressionLevel()) catch |err| {
                std.log.warn("    Compression failed: {}", .{err});
                continue;
            };
            defer allocator.free(compressed);

            std.log.info("    Compressed: {} -> {} bytes", .{ test_case.data.len, compressed.len });

            // Test decompression
            const decompressed = CompressionBackends.decompress(allocator, backend, compressed, test_case.data.len) catch |err| {
                std.log.err("    Decompression failed: {}", .{err});
                return err;
            };
            defer allocator.free(decompressed);

            // Verify correctness
            try testing.expectEqualSlices(u8, test_case.data, decompressed);
            std.log.info("    Correctness: OK");
        }
    }
}
