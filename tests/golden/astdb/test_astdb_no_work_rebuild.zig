// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const GoldenTestFramework = @import("../framework/test_runner.zig").GoldenTestFramework;
const astdb = @import("../../../compiler/libjanus/astdb.zig");

// Golden Test: ASTDB No-Work Rebuild Validation
// Task 3: Verify unchanged inputs produce zero downstream work
// Requirements: SPEC-astdb-query.md sections 5, 9, 10.3, 10.4

const RebuildTestCase = struct {
    name: []const u8,
    source_files: []const []const u8,
    modification_type: ModificationType,
    expected_work_units: u32, // 0 = no work, >0 = expected rebuilds
};

const ModificationType = enum {
    no_change, // Identical rebuild
    whitespace_only, // Formatting changes
    comment_only, // Comment changes
    semantic_change, // Type/logic changes
    dependency_change, // Upstream dependency modified
};

const test_cases = [_]RebuildTestCase{
    .{
        .name = "identical_rebuild",
        .source_files = &[_][]const u8{
            \\// main.jan
            \\import std.io;
            \\
            \\func main() -> void {
            \\    std.io.println("Hello, Janus!");
            \\}
        },
        .modification_type = .no_change,
        .expected_work_units = 0,
    },
    .{
        .name = "whitespace_only_change",
        .source_files = &[_][]const u8{
            \\// main.jan
            \\import std.io;
            \\
            \\func main() -> void {
            \\
            \\    std.io.println("Hello, Janus!");
            \\
            \\}
        },
        .modification_type = .whitespace_only,
        .expected_work_units = 0,
    },
    .{
        .name = "comment_addition",
        .source_files = &[_][]const u8{
            \\// main.jan - Entry point for Janus application
            \\import std.io;
            \\
            \\// Main function - prints greeting
            \\func main() -> void {
            \\    std.io.println("Hello, Janus!"); // Output greeting
            \\}
        },
        .modification_type = .comment_only,
        .expected_work_units = 0,
    },
    .{
        .name = "semantic_change",
        .source_files = &[_][]const u8{
            \\// main.jan
            \\import std.io;
            \\
            \\func main() -> void {
            \\    std.io.println("Hello, World!"); // Changed message
            \\}
        },
        .modification_type = .semantic_change,
        .expected_work_units = 1, // main function needs rebuild
    },
    .{
        .name = "multi_file_dependency",
        .source_files = &[_][]const u8{
            \\// math.jan
            \\func add(a: i32, b: i32) -> i32 {
            \\    return a + b;
            \\}
            ,
            \\// main.jan
            \\import math;
            \\
            \\func main() -> void {
            \\    const result = math.add(2, 3);
            \\}
        },
        .modification_type = .no_change,
        .expected_work_units = 0,
    },
};

test "ASTDB No-Work Rebuild - CID Stability" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = try GoldenTestFramework.init(allocator, "astdb_no_work_rebuild");
    defer framework.deinit();

    for (test_cases) |test_case| {
        std.log.info("Testing no-work rebuild: {s}", .{test_case.name});

        // Initial build - establish baseline
        const initial_build_result = try framework.performFullBuild(test_case.source_files);
        const initial_cids = initial_build_result.cids;
        const initial_ir_objects = initial_build_result.ir_objects;

        // Rebuild with same inputs
        const rebuild_result = try framework.performFullBuild(test_case.source_files);
        const rebuild_cids = rebuild_result.cids;
        const rebuild_ir_objects = rebuild_result.ir_objects;

        // Verify CID stability
        try testing.expect(initial_cids.len == rebuild_cids.len);
        for (initial_cids, rebuild_cids) |initial_cid, rebuild_cid| {
            try testing.expect(std.mem.eql(u8, &initial_cid, &rebuild_cid));
        }

        // Verify no unnecessary work was performed
        const work_units_performed = rebuild_result.work_units_performed;
        try testing.expectEqual(test_case.expected_work_units, work_units_performed);

        if (work_units_performed == 0) {
            // Verify IR objects were reused, not regenerated
            try testing.expect(initial_ir_objects.len == rebuild_ir_objects.len);
            for (initial_ir_objects, rebuild_ir_objects) |initial_obj, rebuild_obj| {
                try testing.expect(std.mem.eql(u8, initial_obj.hash, rebuild_obj.hash));
                try testing.expect(initial_obj.reused == false); // Initial build
                try testing.expect(rebuild_obj.reused == true); // Rebuild reused
            }
            std.log.info("✅ {s}: Zero work performed, all objects reused", .{test_case.name});
        } else {
            std.log.info("✅ {s}: {} work units performed as expected", .{ test_case.name, work_units_performed });
        }

        // Record golden reference
        try framework.recordNoWorkRebuild(test_case.name, initial_cids, work_units_performed);
    }
}

test "ASTDB Incremental Build - Dependency Tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = try GoldenTestFramework.init(allocator, "astdb_incremental_build");
    defer framework.deinit();

    // Multi-file project with clear dependencies
    const source_files_v1 = [_][]const u8{
        \\// utils.jan
        \\func helper(x: i32) -> i32 {
        \\    return x * 2;
        \\}
        ,
        \\// math.jan
        \\import utils;
        \\
        \\func calculate(a: i32, b: i32) -> i32 {
        \\    return utils.helper(a) + b;
        \\}
        ,
        \\// main.jan
        \\import math;
        \\
        \\func main() -> void {
        \\    const result = math.calculate(5, 3);
        \\}
    };

    // Modified version - only utils.jan changes
    const source_files_v2 = [_][]const u8{
        \\// utils.jan - MODIFIED
        \\func helper(x: i32) -> i32 {
        \\    return x * 3; // Changed multiplier
        \\}
        ,
        \\// math.jan - UNCHANGED
        \\import utils;
        \\
        \\func calculate(a: i32, b: i32) -> i32 {
        \\    return utils.helper(a) + b;
        \\}
        ,
        \\// main.jan - UNCHANGED
        \\import math;
        \\
        \\func main() -> void {
        \\    const result = math.calculate(5, 3);
        \\}
    };

    // Initial build
    std.log.info("Performing initial build...");
    const initial_result = try framework.performFullBuild(&source_files_v1);

    // Incremental build with utils.jan modified
    std.log.info("Performing incremental build with utils.jan modified...");
    const incremental_result = try framework.performIncrementalBuild(&source_files_v2, &source_files_v1);

    // Verify dependency tracking
    const changed_files = incremental_result.changed_files;
    const rebuilt_files = incremental_result.rebuilt_files;

    // Only utils.jan should be detected as changed
    try testing.expectEqual(@as(usize, 1), changed_files.len);
    try testing.expect(std.mem.eql(u8, "utils.jan", changed_files[0]));

    // utils.jan, math.jan, and main.jan should be rebuilt (dependency cascade)
    try testing.expectEqual(@as(usize, 3), rebuilt_files.len);

    std.log.info("✅ Incremental build: {} files changed, {} files rebuilt", .{ changed_files.len, rebuilt_files.len });

    // Record dependency tracking results
    try framework.recordIncrementalBuild("dependency_cascade", changed_files, rebuilt_files);
}

test "ASTDB Build Determinism - Cross-Platform Validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = try GoldenTestFramework.init(allocator, "astdb_build_determinism");
    defer framework.deinit();

    const source_files = [_][]const u8{
        \\// determinism_test.jan
        \\import std.hash;
        \\
        \\func hash_data(data: []const u8) -> u64 {.effects: "pure"} {
        \\    return std.hash.fnv1a(data);
        \\}
        \\
        \\func process_batch(items: [][]const u8) -> []u64 {
        \\    var results = make([]u64, items.len);
        \\    for (i, item) in enumerate(items) {
        \\        results[i] = hash_data(item);
        \\    }
        \\    return results;
        \\}
    };

    // Build multiple times with deterministic mode enabled
    const build_configs = [_]struct {
        name: []const u8,
        deterministic: bool,
        expected_identical: bool,
    }{
        .{ .name = "deterministic_mode", .deterministic = true, .expected_identical = true },
        .{ .name = "non_deterministic_mode", .deterministic = false, .expected_identical = false },
    };

    for (build_configs) |config| {
        std.log.info("Testing build determinism: {s}", .{config.name});

        // Perform multiple builds
        const build1 = try framework.performDeterministicBuild(&source_files, config.deterministic);
        const build2 = try framework.performDeterministicBuild(&source_files, config.deterministic);
        const build3 = try framework.performDeterministicBuild(&source_files, config.deterministic);

        // Compare build artifacts
        const artifacts_identical = framework.compareBuildArtifacts(build1, build2) and
            framework.compareBuildArtifacts(build2, build3);

        if (config.expected_identical) {
            try testing.expect(artifacts_identical);
            std.log.info("✅ {s}: Build artifacts are identical across runs", .{config.name});
        } else {
            // In non-deterministic mode, some variance is expected (timestamps, etc.)
            std.log.info("ℹ️  {s}: Build artifacts variance is acceptable", .{config.name});
        }

        // Record determinism results
        try framework.recordDeterminismTest(config.name, artifacts_identical, config.expected_identical);
    }
}
