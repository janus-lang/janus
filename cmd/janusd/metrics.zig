// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub const Tool = enum { compile, query_ast, diagnostics_list, utcp, other };

const Counters = struct {
    total_requests: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    total_errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    status_2xx: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    status_4xx: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    status_5xx: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    compile_calls: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    query_ast_calls: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    diagnostics_calls: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    compile_duration_ns_sum: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    query_ast_duration_ns_sum: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    diagnostics_duration_ns_sum: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
};

var g_counters: Counters = .{};

pub fn record(tool: Tool, status_code: u16, duration_ns: u64) void {
    _ = g_counters.total_requests.fetchAdd(1, .seq_cst);
    if (status_code >= 500) _ = g_counters.status_5xx.fetchAdd(1, .seq_cst)
    else if (status_code >= 400) { _ = g_counters.status_4xx.fetchAdd(1, .seq_cst); _ = g_counters.total_errors.fetchAdd(1, .seq_cst); }
    else if (status_code >= 200 and status_code < 300) _ = g_counters.status_2xx.fetchAdd(1, .seq_cst);

    switch (tool) {
        .compile => {
            _ = g_counters.compile_calls.fetchAdd(1, .seq_cst);
            _ = g_counters.compile_duration_ns_sum.fetchAdd(duration_ns, .seq_cst);
        },
        .query_ast => {
            _ = g_counters.query_ast_calls.fetchAdd(1, .seq_cst);
            _ = g_counters.query_ast_duration_ns_sum.fetchAdd(duration_ns, .seq_cst);
        },
        .diagnostics_list => {
            _ = g_counters.diagnostics_calls.fetchAdd(1, .seq_cst);
            _ = g_counters.diagnostics_duration_ns_sum.fetchAdd(duration_ns, .seq_cst);
        },
        else => {},
    }
}

pub const Snapshot = struct {
    total_requests: u64,
    total_errors: u64,
    status_2xx: u64,
    status_4xx: u64,
    status_5xx: u64,
    compile_calls: u64,
    query_ast_calls: u64,
    diagnostics_calls: u64,
};

pub fn snapshot() Snapshot {
    return .{
        .total_requests = g_counters.total_requests.load(.seq_cst),
        .total_errors = g_counters.total_errors.load(.seq_cst),
        .status_2xx = g_counters.status_2xx.load(.seq_cst),
        .status_4xx = g_counters.status_4xx.load(.seq_cst),
        .status_5xx = g_counters.status_5xx.load(.seq_cst),
        .compile_calls = g_counters.compile_calls.load(.seq_cst),
        .query_ast_calls = g_counters.query_ast_calls.load(.seq_cst),
        .diagnostics_calls = g_counters.diagnostics_calls.load(.seq_cst),
    };
}

pub fn reset() void {
    g_counters = .{};
}

pub fn toolFromName(name: []const u8) Tool {
    if (std.mem.eql(u8, name, "compile")) return .compile;
    if (std.mem.eql(u8, name, "query_ast")) return .query_ast;
    if (std.mem.eql(u8, name, "diagnostics.list")) return .diagnostics_list;
    if (std.mem.eql(u8, name, "utcp")) return .utcp;
    return .other;
}

test "metrics record increments per-tool and status" {
    reset();
    record(.compile, 200, 1_000);
    record(.compile, 400, 2_000);
    record(.query_ast, 200, 500);
    const s = snapshot();
    try std.testing.expectEqual(@as(u64, 3), s.total_requests);
    try std.testing.expectEqual(@as(u64, 1), s.total_errors);
    try std.testing.expectEqual(@as(u64, 2), s.status_2xx);
    try std.testing.expectEqual(@as(u64, 1), s.status_4xx);
    try std.testing.expectEqual(@as(u64, 2), s.compile_calls);
    try std.testing.expectEqual(@as(u64, 1), s.query_ast_calls);
}
