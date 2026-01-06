// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// [N-4] MCP pub/sub
const std = @import("std");
const Golden = @import("../golden.zig");

test "mcp receives diff event" {
    var bus = try Golden.MCP.start();
    defer bus.stop();

    const token = try Golden.create_test_jwt(.{
        .principal = "agent:subscriber",
        .capabilities = &.{"mcp.topic.subscribe:diff.*"},
    });

    _ = try bus.subscribe(&.{"diff.*"}, token);

    const res = try Golden.exec("janus diff A..B --semantic --notify --channels mcp");
    try Golden.expect_success(res);

    const event = try bus.expect_event("diff.semantic");
    try Golden.json_eq(event, "type", "diff.semantic");
    try Golden.json_has(event, "payload_cid");
}

test "mcp topic filtering works correctly" {
    var bus = try Golden.MCP.start();
    defer bus.stop();

    const token = try Golden.create_test_jwt(.{
        .principal = "agent:build-only",
        .capabilities = &.{"mcp.topic.subscribe:build.*"},
    });

    _ = try bus.subscribe(&.{"build.*"}, token);

    // Trigger both build and diff events
    _ = try Golden.exec("janus build --check-no-work --notify --channels mcp");
    _ = try Golden.exec("janus diff A..B --semantic --notify --channels mcp");

    // Should only receive build event
    const event = try bus.expect_event("build.no_work_ok");
    try Golden.json_eq(event, "type", "build.no_work_ok");

    // Should not receive diff event
    try bus.expect_no_event("diff.semantic", 1000); // 1s timeout
}

test "mcp preserves ordering per aggregate" {
    var bus = try Golden.MCP.start();
    defer bus.stop();

    const token = try Golden.create_test_jwt(.{
        .principal = "agent:subscriber",
        .capabilities = &.{"mcp.topic.subscribe:*"},
    });

    _ = try bus.subscribe(&.{"*"}, token);

    // Generate sequence of events for same project
    const commands = [_][]const u8{
        "janus query --expr \"func\" --notify --channels mcp",
        "janus build --check-no-work --notify --channels mcp",
        "janus diff A..B --semantic --notify --channels mcp",
    };

    for (commands) |cmd| {
        _ = try Golden.exec(cmd);
    }

    // Verify events arrive in order
    const events = try bus.collect_events(3, 5000); // 5s timeout
    try Golden.expect(events.len == 3);

    try Golden.json_eq(events[0], "type", "query.result");
    try Golden.json_eq(events[1], "type", "build.no_work_ok");
    try Golden.json_eq(events[2], "type", "diff.semantic");

    // Verify all have same aggregate_id (project)
    const project_id = try Golden.json_get_string(events[0], "source");
    for (events[1..]) |event| {
        const event_project = try Golden.json_get_string(event, "source");
        try Golden.expect(std.mem.eql(u8, project_id, event_project));
    }
}

test "mcp handles multiple subscribers" {
    var bus = try Golden.MCP.start();
    defer bus.stop();

    const token1 = try Golden.create_test_jwt(.{
        .principal = "agent:subscriber1",
        .capabilities = &.{"mcp.topic.subscribe:build.*"},
    });

    const token2 = try Golden.create_test_jwt(.{
        .principal = "agent:subscriber2",
        .capabilities = &.{"mcp.topic.subscribe:build.*"},
    });

    const sub1 = try bus.subscribe(&.{"build.*"}, token1);
    const sub2 = try bus.subscribe(&.{"build.*"}, token2);

    _ = try Golden.exec("janus build --check-no-work --notify --channels mcp");

    // Both subscribers should receive the event
    const event1 = try sub1.expect_event("build.no_work_ok");
    const event2 = try sub2.expect_event("build.no_work_ok");

    // Events should be identical
    try Golden.json_eq_field(event1, event2, "id");
    try Golden.json_eq_field(event1, event2, "payload_cid");
}

test "mcp subscription requires valid capability" {
    var bus = try Golden.MCP.start();
    defer bus.stop();

    const token = try Golden.create_test_jwt(.{
        .principal = "agent:no-subscribe",
        .capabilities = &.{"mcp.action.invoke:format.file"}, // no subscribe capability
    });

    const response = try bus.subscribe_request(&.{"build.*"}, token);
    try Golden.expect_error_code(response, "MC3003"); // InsufficientCapabilities
}

test "mcp ring buffer overflow handling" {
    var bus = try Golden.MCP.start(.{ .ring_buffer_size = 2 }); // tiny buffer
    defer bus.stop();

    const token = try Golden.create_test_jwt(.{
        .principal = "agent:slow-subscriber",
        .capabilities = &.{"mcp.topic.subscribe:*"},
    });

    const sub = try bus.subscribe(&.{"*"}, token);

    // Generate more events than buffer can hold
    for (0..5) |_| {
        _ = try Golden.exec("janus build --check-no-work --notify --channels mcp");
    }

    // Should receive most recent events, older ones dropped
    const events = try sub.collect_events(2, 1000);
    try Golden.expect(events.len == 2);

    // Verify overflow metric is recorded
    const metrics = try bus.get_metrics();
    try Golden.expect(metrics.ring_buffer_overflows > 0);
}
