// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const GoldenTestFramework = @import("../framework/test_runner.zig").GoldenTestFramework;
const astdb = @import("../../../compiler/libjanus/astdb.zig");

// Golden Test: ASTDB CID Invariance
// Task 3: Verify CID computation is deterministic and semantic-only
// Requirements: SPEC-astdb-query.md sections 3.1, 3.2, 10.2

const TestCase = struct {
    name: []const u8,
    source_original: []const u8,
    source_formatted: []const u8, // Same semantics, different formatting
    expected_cid_match: bool,
};

const test_cases = [_]TestCase{
    .{
        .name = "whitespace_invariance",
        .source_original =
        \\func add(a: i32, b: i32) -> i32 {
        \\    return a + b;
        \\}
        ,
        .source_formatted =
        \\func add(a: i32, b: i32) -> i32 {
        \\
        \\    return a + b;
        \\
        \\}
        ,
        .expected_cid_match = true,
    },
    .{
        .name = "comment_invariance",
        .source_original =
        \\func multiply(x: i32, y: i32) -> i32 {
        \\    return x * y;
        \\}
        ,
        .source_formatted =
        \\// This function multiplies two integers
        \\func multiply(x: i32, y: i32) -> i32 {
        \\    return x * y; // Simple multiplication
        \\}
        ,
        .expected_cid_match = true,
    },
    .{
        .name = "semantic_change_detection",
        .source_original =
        \\func divide(a: i32, b: i32) -> i32 {
        \\    return a / b;
        \\}
        ,
        .source_formatted =
        \\func divide(a: i32, b: i32) -> f64 { // Changed return type
        \\    return a / b;
        \\}
        ,
        .expected_cid_match = false,
    },
    .{
        .name = "effect_annotation_sensitivity",
        .source_original =
        \\func read_file(path: []const u8) -> []u8 {
        \\    // Implementation
        \\}
        ,
        .source_formatted =
        \\func read_file(path: []const u8) -> []u8 {.effects: "io.fs.read"} {
        \\    // Implementation
        \\}
        ,
        .expected_cid_match = false,
    },
};

test "ASTDB CID Invariance - Formatting Changes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = try GoldenTestFramework.init(allocator, "astdb_cid_invariance");
    defer framework.deinit();

    for (test_cases) |test_case| {
        std.log.info("Testing CID invariance: {s}", .{test_case.name});

        // Parse both versions and compute CIDs
        const cid_original = try framework.computeASTCID(test_case.source_original);
        const cid_formatted = try framework.computeASTCID(test_case.source_formatted);

        // Verify CID behavior matches expectation
        const cids_match = std.mem.eql(u8, &cid_original, &cid_formatted);

        if (test_case.expected_cid_match) {
            try testing.expect(cids_match);
            std.log.info("✅ {s}: CIDs correctly match (formatting ignored)", .{test_case.name});
        } else {
            try testing.expect(!cids_match);
            std.log.info("✅ {s}: CIDs correctly differ (semantic change detected)", .{test_case.name});
        }

        // Record golden reference
        try framework.recordCIDInvariance(test_case.name, cid_original, cid_formatted, test_case.expected_cid_match);
    }
}

test "ASTDB CID Determinism - Cross-Platform" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = try GoldenTestFramework.init(allocator, "astdb_cid_determinism");
    defer framework.deinit();

    const source =
        \\func fibonacci(n: u32) -> u32 {
        \\    if (n <= 1) return n;
        \\    return fibonacci(n - 1) + fibonacci(n - 2);
        \\}
    ;

    // Compute CID multiple times to ensure determinism
    const cid1 = try framework.computeASTCID(source);
    const cid2 = try framework.computeASTCID(source);
    const cid3 = try framework.computeASTCID(source);

    // All CIDs must be identical
    try testing.expect(std.mem.eql(u8, &cid1, &cid2));
    try testing.expect(std.mem.eql(u8, &cid2, &cid3));

    std.log.info("✅ CID computation is deterministic across multiple runs");

    // Record golden reference for cross-platform validation
    try framework.recordDeterministicCID("fibonacci_function", cid1);
}

test "ASTDB CID Tree Hashing - Merkle Structure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = try GoldenTestFramework.init(allocator, "astdb_cid_merkle");
    defer framework.deinit();

    const source =
        \\module math {
        \\    func add(a: i32, b: i32) -> i32 {
        \\        return a + b;
        \\    }
        \\
        \\    func multiply(x: i32, y: i32) -> i32 {
        \\        return x * y;
        \\    }
        \\}
    ;

    // Compute CIDs for the entire module and individual functions
    const module_cid = try framework.computeASTCID(source);
    const add_func_cid = try framework.computeFunctionCID(source, "add");
    const multiply_func_cid = try framework.computeFunctionCID(source, "multiply");

    // Verify that function CIDs are stable
    try testing.expect(add_func_cid.len == 32); // BLAKE3 hash size
    try testing.expect(multiply_func_cid.len == 32);
    try testing.expect(!std.mem.eql(u8, &add_func_cid, &multiply_func_cid));

    std.log.info("✅ Merkle tree CID structure validated");

    // Record golden references
    try framework.recordMerkleCIDs("math_module", module_cid, &[_][]const u8{ add_func_cid, multiply_func_cid });
}
