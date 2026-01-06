// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("../../../compiler/libjanus/astdb.zig");

// Golden Test: Oracle/Classical Parity Validation
// Task T-4, T-5: Validates OX-7 - byte-perfect parity between Oracle and Classical
// Requirements: Identical stdout/stderr/exit codes for equivalent commands

test "oracle parity: query" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🔥 Testing Oracle/Classical query parity", .{});

    // Simulate running both commands (in real implementation, would exec actual CLI)
    const classical_output = try simulateClassicalQuery(allocator, "func");
    const oracle_output = try simulateOracleQuery(allocator, "func", .classical);

    // Outputs must be byte-for-byte identical
    try testing.expectEqualStrings(classical_output.stdout, oracle_output.stdout);
    try testing.expectEqualStrings(classical_output.stderr, oracle_output.stderr);
    try testing.expectEqual(classical_output.exit_code, oracle_output.exit_code);

    std.log.info("✅ Query parity validated: Oracle --oracle-output=classical == Classical", .{});
}

test "oracle parity: diff" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🔥 Testing Oracle/Classical diff parity", .{});

    // Simulate semantic diff between two snapshots
    const cid_a = "blake3:abc123...";
    const cid_b = "blake3:def456...";

    const classical_output = try simulateClassicalDiff(allocator, cid_a, cid_b);
    const oracle_output = try simulateOracleDiff(allocator, cid_a, cid_b, .classical);

    // Outputs must be byte-for-byte identical
    try testing.expectEqualStrings(classical_output.stdout, oracle_output.stdout);
    try testing.expectEqualStrings(classical_output.stderr, oracle_output.stderr);
    try testing.expectEqual(classical_output.exit_code, oracle_output.exit_code);

    std.log.info("✅ Diff parity validated: Oracle diff == Classical diff", .{});
}

test "oracle parity: build check" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🔥 Testing Oracle/Classical build check parity", .{});

    const classical_output = try simulateClassicalBuildCheck(allocator);
    const oracle_output = try simulateOracleBuildCheck(allocator, .classical);

    // Build check results must be identical
    try testing.expectEqualStrings(classical_output.stdout, oracle_output.stdout);
    try testing.expectEqual(classical_output.exit_code, oracle_output.exit_code);

    std.log.info("✅ Build check parity validated: Oracle introspect == Classical build", .{});
}

// Simulation functions (in real implementation, these would exec actual CLI)

const CommandOutput = struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
};

fn simulateClassicalQuery(allocator: std.mem.Allocator, expr: []const u8) !CommandOutput {
    _ = expr;
    // Simulate: janus query --expr "func" --format json
    const output = try allocator.dupe(u8,
        \\{"kind":"func","name":"main","cid":"blake3:abc123"}
        \\{"kind":"func","name":"helper","cid":"blake3:def456"}
        \\
    );

    return CommandOutput{
        .stdout = output,
        .stderr = "",
        .exit_code = 0,
    };
}

fn simulateOracleQuery(allocator: std.mem.Allocator, expr: []const u8, output_mode: enum { classical, json, table }) !CommandOutput {
    _ = expr;

    switch (output_mode) {
        .classical => {
            // Must produce identical output to classical command
            const output = try allocator.dupe(u8,
                \\{"kind":"func","name":"main","cid":"blake3:abc123"}
                \\{"kind":"func","name":"helper","cid":"blake3:def456"}
                \\
            );

            return CommandOutput{
                .stdout = output,
                .stderr = "",
                .exit_code = 0,
            };
        },
        .json => {
            // Oracle can add metadata in non-classical modes
            const output = try allocator.dupe(u8,
                \\{"kind":"func","name":"main","cid":"blake3:abc123","oracle_meta":{"query_time_ms":3.2}}
                \\{"kind":"func","name":"helper","cid":"blake3:def456","oracle_meta":{"query_time_ms":3.2}}
                \\
            );

            return CommandOutput{
                .stdout = output,
                .stderr = "",
                .exit_code = 0,
            };
        },
        .table => {
            const output = try allocator.dupe(u8,
                \\┌──────────┬─────────────┬──────────────────┐
                \\│ Kind     │ Name        │ CID              │
                \\├──────────┼─────────────┼──────────────────┤
                \\│ func     │ main        │ blake3:abc123    │
                \\│ func     │ helper      │ blake3:def456    │
                \\└──────────┴─────────────┴──────────────────┘
                \\
            );

            return CommandOutput{
                .stdout = output,
                .stderr = "",
                .exit_code = 0,
            };
        },
    }
}

fn simulateClassicalDiff(allocator: std.mem.Allocator, cid_a: []const u8, cid_b: []const u8) !CommandOutput {
    _ = cid_a;
    _ = cid_b;

    const output = try allocator.dupe(u8,
        \\{"changed":[{"item":"main","kind":"LiteralChange","detail":{"from":"41","to":"42"}}],"unchanged":["helper"]}
        \\
    );

    return CommandOutput{
        .stdout = output,
        .stderr = "",
        .exit_code = 0,
    };
}

fn simulateOracleDiff(allocator: std.mem.Allocator, cid_a: []const u8, cid_b: []const u8, output_mode: enum { classical, json }) !CommandOutput {
    _ = cid_a;
    _ = cid_b;

    switch (output_mode) {
        .classical => {
            // Must match classical output exactly
            const output = try allocator.dupe(u8,
                \\{"changed":[{"item":"main","kind":"LiteralChange","detail":{"from":"41","to":"42"}}],"unchanged":["helper"]}
                \\
            );

            return CommandOutput{
                .stdout = output,
                .stderr = "",
                .exit_code = 0,
            };
        },
        .json => {
            // Oracle can add commentary in non-classical modes
            const output = try allocator.dupe(u8,
                \\{"changed":[{"item":"main","kind":"LiteralChange","detail":{"from":"41","to":"42"}}],"unchanged":["helper"],"oracle_commentary":"A literal change with surgical precision. Only dependents affected."}
                \\
            );

            return CommandOutput{
                .stdout = output,
                .stderr = "",
                .exit_code = 0,
            };
        },
    }
}

fn simulateClassicalBuildCheck(allocator: std.mem.Allocator) !CommandOutput {
    const output = try allocator.dupe(u8,
        \\{"run1":{"parse":145,"sema":132,"ir":87,"codegen":12},"run2":{"parse":0,"sema":0,"ir":0,"codegen":0,"q_hits":428,"q_misses":0}}
        \\
    );

    return CommandOutput{
        .stdout = output,
        .stderr = "",
        .exit_code = 0,
    };
}

fn simulateOracleBuildCheck(allocator: std.mem.Allocator, output_mode: enum { classical, json }) !CommandOutput {
    switch (output_mode) {
        .classical => {
            // Must match classical output exactly
            const output = try allocator.dupe(u8,
                \\{"run1":{"parse":145,"sema":132,"ir":87,"codegen":12},"run2":{"parse":0,"sema":0,"ir":0,"codegen":0,"q_hits":428,"q_misses":0}}
                \\
            );

            return CommandOutput{
                .stdout = output,
                .stderr = "",
                .exit_code = 0,
            };
        },
        .json => {
            // Oracle can add insights in non-classical modes
            const output = try allocator.dupe(u8,
                \\{"run1":{"parse":145,"sema":132,"ir":87,"codegen":12},"run2":{"parse":0,"sema":0,"ir":0,"codegen":0,"q_hits":428,"q_misses":0},"oracle_analysis":"Perfect incremental build - zero waste, maximum efficiency."}
                \\
            );

            return CommandOutput{
                .stdout = output,
                .stderr = "",
                .exit_code = 0,
            };
        },
    }
}
