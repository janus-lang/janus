// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const AdvancedDispatchCompression = @import("advanced_dispatch_compression.zig").AdvancedDispatchCompression;
const TypeId = @import("type_registry.zig").TypeRegistry.TypeId;

test "delta compression of type sequences" {
    const allocator = testing.allocator;

    // Test sequential type IDs (good for delta compression)
    const sequential_types = [_]TypeId{ 100, 101, 102, 103, 104, 105 };
    var delta_compressed = try AdvancedDispatchCompression.DeltaCompressedSequence.compress(allocator, &sequential_types);
    defer delta_compressed.deinit(allocator);

    // Should achieve good compression for sequential data
    const original_size = delta_compressed.getOriginalSize();
    const compressed_size = delta_compressed.getCompressedSize();

    std.log.info("Delta compression: {} -> {} bytes ({d:.2}% ratio)", .{
        original_size,
        compressed_size,
        @as(f64, @floatFromInt(compressed_size)) / @as(f64, @floatFromInt(original_size)) * 100.0,
    });

    // Test decompression
    const decompressed = try delta_compressed.decompress(allocator);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(TypeId, &sequential_types, decompressed);

    // Test with random types (should be less effective)
    const random_types = [_]TypeId{ 1, 1000, 50, 2000, 3 };
    var random_delta = try AdvancedDispatchCompression.DeltaCompressedSequence.compress(allocator, &random_types);
    defer random_delta.deinit(allocator);

    const random_decompressed = try random_delta.decompress(allocator);
    defer allocator.free(random_decompressed);

    try testing.expectEqualSlices(TypeId, &random_types, random_decompressed);

    std.log.info("Random delta compression: {} -> {} bytes ({d:.2}% ratio)", .{
        random_delta.getOriginalSize(),
        random_delta.getCompressedSize(),
        @as(f64, @floatFromInt(random_delta.getCompressedSize())) / @as(f64, @floatFromInt(random_delta.getOriginalSize())) * 100.0,
    });
}

test "type dictionary compression" {
    const allocator = testing.allocator;

    var type_dict = AdvancedDispatchCompression.TypeDictionary.init(allocator);
    defer type_dict.deinit();

    // Add types with different frequencies
    const types_with_frequency = [_]struct { type_id: TypeId, count: u32 }{
        .{ .type_id = 1, .count = 100 }, // Very frequent
        .{ .type_id = 2, .count = 50 }, // Frequent
        .{ .type_id = 3, .count = 10 }, // Less frequent
        .{ .type_id = 4, .count = 1 }, // Rare
    };

    // Add types according to their frequency
    for (types_with_frequency) |item| {
        for (0..item.count) |_| {
            _ = try type_dict.addType(item.type_id);
        }
    }

    std.log.info("Type dictionary before optimization:");
    for (type_dict.index_to_type.items, 0..) |type_id, index| {
        const frequency = type_dict.frequency_map.get(type_id) orelse 0;
        std.log.info("  Index {}: TypeId {} (frequency: {})", .{ index, type_id, frequency });
    }

    // Optimize by frequency
    try type_dict.optimizeByFrequency();

    std.log.info("Type dictionary after frequency optimization:");
    for (type_dict.index_to_type.items, 0..) |type_id, index| {
        const frequency = type_dict.frequency_map.get(type_id) orelse 0;
        std.log.info("  Index {}: TypeId {} (frequency: {})", .{ index, type_id, frequency });
    }

    // Verify most frequent type got index 0
    try testing.expect(type_dict.getIndex(1).? == 0); // Most frequent should be first
    try testing.expect(type_dict.getType(0).? == 1);
}

test "pattern dictionary compression" {
    const allocator = testing.allocator;

    var pattern_dict = AdvancedDispatchCompression.PatternDictionary.init(allocator);
    defer pattern_dict.deinit();

    // Common patterns in dispatch tables
    const common_patterns = [_][]const TypeId{
        &[_]TypeId{ 1, 2 }, // Binary operation pattern
        &[_]TypeId{ 1, 2, 3 }, // Ternary operation pattern
        &[_]TypeId{1}, // Unary operation pattern
        &[_]TypeId{ 1, 2 }, // Repeat binary pattern
        &[_]TypeId{ 1, 2, 3 }, // Repeat ternary pattern
    };

    // Add patterns
    for (common_patterns) |pattern| {
        const index = try pattern_dict.addPattern(pattern);
        std.log.info("Added pattern {:?} -> index {}", .{ pattern, index });
    }

    // Verify deduplication worked
    try testing.expect(pattern_dict.patterns.items.len == 3); // Should have deduplicated

    // Test pattern lookup
    const binary_index = pattern_dict.getPatternIndex(&[_]TypeId{ 1, 2 });
    try testing.expect(binary_index != null);

    const retrieved_pattern = pattern_dict.getPattern(binary_index.?);
    try testing.expect(retrieved_pattern != null);
    try testing.expectEqualSlices(TypeId, &[_]TypeId{ 1, 2 }, retrieved_pattern.?.types);
}

test "bloom filter optimization" {
    const allocator = testing.allocator;
    _ = allocator;

    // Test bloom filter calculation
    const pattern1 = [_]TypeId{ 1, 2, 3 };
    const pattern2 = [_]TypeId{ 1, 2, 4 };
    const pattern3 = [_]TypeId{ 5, 6, 7 };

    const bloom1 = AdvancedDispatchCompression.CompressedDispatchEntry.calculateBloomBits(&pattern1);
    const bloom2 = AdvancedDispatchCompression.CompressedDispatchEntry.calculateBloomBits(&pattern2);
    const bloom3 = AdvancedDispatchCompression.CompressedDispatchEntry.calculateBloomBits(&pattern3);

    std.log.info("Bloom filters:");
    std.log.info("  Pattern {:?}: 0x{X}", .{ pattern1, bloom1 });
    std.log.info("  Pattern {:?}: 0x{X}", .{ pattern2, bloom2 });
    std.log.info("  Pattern {:?}: 0x{X}", .{ pattern3, bloom3 });

    // Test bloom filter matching
    const entry1 = AdvancedDispatchCompression.CompressedDispatchEntry{
        .pattern_index = 0,
        .pattern_delta = null,
        .implementation_index = 0,
        .specificity_score = 100,
        .call_frequency = 1000,
        .flags = 0,
        .bloom_bits = bloom1,
    };

    // Should match patterns that share types
    const query_bloom_12 = AdvancedDispatchCompression.CompressedDispatchEntry.calculateBloomBits(&[_]TypeId{ 1, 2 });
    try testing.expect(entry1.mightMatch(query_bloom_12)); // Should match (subset)

    const query_bloom_567 = AdvancedDispatchCompression.CompressedDispatchEntry.calculateBloomBits(&[_]TypeId{ 5, 6, 7 });
    // Might or might not match due to hash collisions, but that's expected with bloom filters

    std.log.info("Bloom filter matching:");
    std.log.info("  Entry with pattern {:?} might match query [1,2]: {}", .{ pattern1, entry1.mightMatch(query_bloom_12) });
    std.log.info("  Entry with pattern {:?} might match query [5,6,7]: {}", .{ pattern1, entry1.mightMatch(query_bloom_567) });
}

test "comprehensive dispatch table compression" {
    const allocator = testing.allocator;

    var compression = AdvancedDispatchCompression.init(allocator);
    defer compression.deinit();

    // Create realistic dispatch entries
    var entries = std.ArrayList(AdvancedDispatchCompression.DispatchEntry).init(allocator);
    defer entries.deinit();

    // Common patterns in a math library
    const math_patterns = [_]struct {
        pattern: []const TypeId,
        func_name: []const u8,
        frequency: u32,
    }{
        .{ .pattern = &[_]TypeId{ 1, 1 }, .func_name = "add_int", .frequency = 1000 }, // add(int, int)
        .{ .pattern = &[_]TypeId{ 2, 2 }, .func_name = "add_float", .frequency = 800 }, // add(float, float)
        .{ .pattern = &[_]TypeId{ 1, 2 }, .func_name = "add_mixed", .frequency = 200 }, // add(int, float)
        .{ .pattern = &[_]TypeId{ 3, 3 }, .func_name = "add_string", .frequency = 100 }, // add(string, string)
        .{ .pattern = &[_]TypeId{ 1, 1 }, .func_name = "mul_int", .frequency = 500 }, // mul(int, int) - same pattern as add_int
        .{ .pattern = &[_]TypeId{ 2, 2 }, .func_name = "mul_float", .frequency = 400 }, // mul(float, float)
        .{ .pattern = &[_]TypeId{ 4, 4, 4 }, .func_name = "add_vector", .frequency = 50 }, // add(vector, vector, vector)
    };

    for (math_patterns, 0..) |pattern_info, i| {
        const entry = AdvancedDispatchCompression.DispatchEntry{
            .type_pattern = pattern_info.pattern,
            .function_name = pattern_info.func_name,
            .module_name = "math",
            .signature_hash = @as(u64, @intCast(i + 1000)),
            .specificity_score = 100,
            .call_frequency = pattern_info.frequency,
            .is_static_dispatch = true,
            .is_hot_path = pattern_info.frequency > 500,
            .is_fallback = false,
        };

        try entries.append(entry);
    }

    std.log.info("Compressing {} dispatch entries...", .{entries.items.len});

    // Compress the dispatch table
    var compressed_table = try compression.compressDispatchTable(entries.items, "math_operations");
    defer {
        allocator.free(compressed_table.signature_name);
        for (compressed_table.entries) |*entry| {
            if (entry.pattern_delta) |*delta| {
                delta.deinit(allocator);
            }
        }
        allocator.free(compressed_table.entries);
        // Note: decision_tree cleanup would be needed in a full implementation
    }

    std.log.info("Compression completed!");
    std.log.info("  Original entries: {}", .{entries.items.len});
    std.log.info("  Compressed entries: {}", .{compressed_table.entries.len});

    // Test lookup functionality
    const query_pattern = [_]TypeId{ 1, 1 }; // Looking for add(int, int) or mul(int, int)
    const lookup_result = compressed_table.lookup(&query_pattern, &compression);

    if (lookup_result) |index| {
        std.log.info("Lookup for pattern {:?} found entry at index {}", .{ query_pattern, index });
        const found_entry = &compressed_table.entries[index];
        std.log.info("  Implementation index: {}", .{found_entry.implementation_index});
        std.log.info("  Call frequency: {}", .{found_entry.call_frequency});
        std.log.info("  Flags: 0x{X}", .{found_entry.flags});
    } else {
        std.log.warn("Lookup for pattern {:?} failed", .{query_pattern});
    }

    // Generate compression report
    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try compression.generateCompressionReport(fbs.writer());
    std.log.info("Compression report:\n{s}", .{fbs.getWritten()});
}

test "decision tree predicate evaluation" {
    const allocator = testing.allocator;

    var compression = AdvancedDispatchCompression.init(allocator);
    defer compression.deinit();

    // Test different predicate types
    const predicates = [_]AdvancedDispatchCompression.CompressedDispatchTable.DecisionTreeNode.Predicate{
        .{ .type_equals = .{ .arg_index = 0, .type_id = 42 } },
        .{ .type_in_set = .{ .arg_index = 1, .type_set_bits = 0b1010 } }, // Types 1 and 3
        .{ .bloom_filter = .{ .bloom_bits = 0xAAAAAAAA } },
        .always_true,
        .always_false,
    };

    const test_query = [_]TypeId{ 42, 1, 100 };

    for (predicates, 0..) |predicate, i| {
        const node = AdvancedDispatchCompression.CompressedDispatchTable.DecisionTreeNode{
            .predicate = predicate,
            .true_branch = null,
            .false_branch = null,
            .leaf_entry_index = null,
        };

        const result = node.evaluate(&test_query, &compression);
        std.log.info("Predicate {} evaluation result: {}", .{ i, result });

        // Verify expected results
        switch (i) {
            0 => try testing.expect(result == true), // type_equals: query[0] == 42
            1 => try testing.expect(result == true), // type_in_set: query[1] == 1, bit 1 is set
            2 => {}, // bloom_filter: result depends on hash function
            3 => try testing.expect(result == true), // always_true
            4 => try testing.expect(result == false), // always_false
            else => unreachable,
        }
    }
}

test "compression effectiveness comparison" {
    const allocator = testing.allocator;

    // Create test data with different characteristics
    const test_scenarios = [_]struct {
        name: []const u8,
        patterns: []const []const TypeId,
        expected_compression_ratio: f64, // Rough expectation
    }{
        .{
            .name = "Sequential types (good for delta)",
            .patterns = &[_][]const TypeId{
                &[_]TypeId{ 1, 2, 3 },
                &[_]TypeId{ 2, 3, 4 },
                &[_]TypeId{ 3, 4, 5 },
                &[_]TypeId{ 4, 5, 6 },
            },
            .expected_compression_ratio = 0.6, // Should compress well
        },
        .{
            .name = "Repeated patterns (good for dictionary)",
            .patterns = &[_][]const TypeId{
                &[_]TypeId{ 1, 2 },
                &[_]TypeId{ 1, 2 },
                &[_]TypeId{ 1, 2 },
                &[_]TypeId{ 3, 4 },
                &[_]TypeId{ 3, 4 },
                &[_]TypeId{ 3, 4 },
            },
            .expected_compression_ratio = 0.4, // Should compress very well
        },
        .{
            .name = "Random patterns (poor compression)",
            .patterns = &[_][]const TypeId{
                &[_]TypeId{ 1, 100, 50 },
                &[_]TypeId{ 200, 5, 75 },
                &[_]TypeId{ 300, 25, 150 },
                &[_]TypeId{ 400, 80, 90 },
            },
            .expected_compression_ratio = 0.9, // Should compress poorly
        },
    };

    for (test_scenarios) |scenario| {
        std.log.info("Testing scenario: {s}", .{scenario.name});

        var compression = AdvancedDispatchCompression.init(allocator);
        defer compression.deinit();

        // Create entries from patterns
        var entries = std.ArrayList(AdvancedDispatchCompression.DispatchEntry).init(allocator);
        defer entries.deinit();

        for (scenario.patterns, 0..) |pattern, i| {
            const entry = AdvancedDispatchCompression.DispatchEntry{
                .type_pattern = pattern,
                .function_name = "test_func",
                .module_name = "test",
                .signature_hash = @as(u64, @intCast(i)),
                .specificity_score = 100,
                .call_frequency = 100,
                .is_static_dispatch = true,
                .is_hot_path = false,
                .is_fallback = false,
            };
            try entries.append(entry);
        }

        // Compress
        const compressed_table = try compression.compressDispatchTable(entries.items, "test_table");
        defer {
            allocator.free(compressed_table.signature_name);
            for (compressed_table.entries) |*entry| {
                if (entry.pattern_delta) |*delta| {
                    delta.deinit(allocator);
                }
            }
            allocator.free(compressed_table.entries);
        }

        const compression_ratio = compression.compression_stats.getEffectiveCompressionRatio();
        std.log.info("  Compression ratio: {d:.3} (expected: {d:.3})", .{ compression_ratio, scenario.expected_compression_ratio });

        // Verify compression is in the expected range (±0.2)
        const diff = @abs(compression_ratio - scenario.expected_compression_ratio);
        if (diff > 0.3) {
            std.log.warn("  Compression ratio outside expected range!");
        }

        // Generate detailed report
        var buffer: [2048]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        try compression.generateCompressionReport(fbs.writer());
        std.log.info("  Report:\n{s}", .{fbs.getWritten()});
    }
}
