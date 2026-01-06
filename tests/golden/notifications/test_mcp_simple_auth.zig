// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// [N-7] MCP API Key Auth & [N-8] Basic Audit Log
const std = @import("std");
const Golden = @import("../golden.zig");

test "MCP denies insufficient actions" {
    // Agent with only format actions tries to rebuild
    var mcp = try Golden.MCP.start();
    defer mcp.stop();

    const response = try mcp.request(.{
        .method = "mcp.action",
        .params = .{
            .action = "rebuild",
            .args = .{ .snapshot_cid = "blake3:test" },
            .api_key = "formatter-key", // only has format actions
        },
    });

    try Golden.expect_error_code(response, "MC3003"); // ActionNotAllowed

    // Verify audit log entry
    const audit_log = try Golden.read_file(".janus/mcp-audit.jsonl");
    try Golden.assert_contains(audit_log, "\"action\":\"rebuild\"");
    try Golden.assert_contains(audit_log, "\"success\":false");
    try Golden.assert_contains(audit_log, "\"api_key\":\"formatter-key\"");
}

test "MCP allows valid actions" {
    var mcp = try Golden.MCP.start();
    defer mcp.stop();

    const response = try mcp.request(.{
        .method = "mcp.action",
        .params = .{
            .action = "format.file",
            .args = .{ .file_cid = "blake3:test", .dry_run = true },
            .api_key = "formatter-key",
        },
    });

    try Golden.expect_success(response);

    // Verify audit log entry
    const audit_log = try Golden.read_file(".janus/mcp-audit.jsonl");
    try Golden.assert_contains(audit_log, "\"action\":\"format.file\"");
    try Golden.assert_contains(audit_log, "\"success\":true");
    try Golden.assert_contains(audit_log, "\"api_key\":\"formatter-key\"");
}

test "MCP validates API key hash" {
    var mcp = try Golden.MCP.start();
    defer mcp.stop();

    const response = try mcp.request(.{
        .method = "mcp.action",
        .params = .{
            .action = "format.file",
            .args = .{ .file_cid = "blake3:test" },
            .api_key = "invalid-key",
        },
    });

    try Golden.expect_error_code(response, "MC3002"); // InvalidApiKey
}

test "MCP admin key allows all actions" {
    var mcp = try Golden.MCP.start();
    defer mcp.stop();

    const actions = [_][]const u8{ "build", "format.file", "refactor.apply", "test.run" };
    for (actions) |action| {
        const response = try mcp.request(.{
            .method = "mcp.action",
            .params = .{
                .action = action,
                .args = .{ .dry_run = true },
                .api_key = "admin-key",
            },
        });
        try Golden.expect_success(response);
    }
}

test "MCP rate limiting" {
    var mcp = try Golden.MCP.start();
    defer mcp.stop();

    // Send requests rapidly to trigger rate limit
    for (0..150) |_| { // More than 100/min limit
        _ = try mcp.request(.{
            .method = "mcp.action",
            .params = .{
                .action = "format.file",
                .args = .{ .file_cid = "blake3:test" },
                .api_key = "formatter-key",
            },
        });
    }

    // Should eventually get rate limited
    const response = try mcp.request(.{
        .method = "mcp.action",
        .params = .{
            .action = "format.file",
            .args = .{ .file_cid = "blake3:test" },
            .api_key = "formatter-key",
        },
    });

    try Golden.expect_error_code(response, "MC3004"); // RateLimited
}

test "MCP dry-run enforcement" {
    var mcp = try Golden.MCP.start();
    defer mcp.stop();

    // Refactor key requires dry-run first
    const response = try mcp.request(.{
        .method = "mcp.action",
        .params = .{
            .action = "refactor.apply",
            .args = .{ .diff_cid = "blake3:test", .dry_run = false },
            .api_key = "refactor-key",
        },
    });

    try Golden.expect_error_code(response, "MC3005"); // DryRunRequired

    // Dry-run should work
    const dry_response = try mcp.request(.{
        .method = "mcp.action",
        .params = .{
            .action = "refactor.apply",
            .args = .{ .diff_cid = "blake3:test", .dry_run = true },
            .api_key = "refactor-key",
        },
    });

    try Golden.expect_success(dry_response);
}

test "MCP audit log format" {
    var mcp = try Golden.MCP.start();
    defer mcp.stop();

    _ = try mcp.request(.{
        .method = "mcp.action",
        .params = .{
            .action = "format.file",
            .args = .{ .file_cid = "blake3:test" },
            .api_key = "formatter-key",
        },
    });

    const audit_log = try Golden.read_file(".janus/mcp-audit.jsonl");
    const log_entry = try Golden.parse_jsonl_last(audit_log);

    // Verify required fields
    try Golden.json_has(log_entry, "timestamp");
    try Golden.json_eq(log_entry, "action", "format.file");
    try Golden.json_eq(log_entry, "api_key", "formatter-key");
    try Golden.json_eq(log_entry, "success", true);
    try Golden.json_has(log_entry, "duration_ms");

    // Verify timestamp format (ISO 8601)
    const timestamp = try Golden.json_get_string(log_entry, "timestamp");
    try Golden.assert_contains(timestamp, "T");
    try Golden.assert_contains(timestamp, "Z");
}
