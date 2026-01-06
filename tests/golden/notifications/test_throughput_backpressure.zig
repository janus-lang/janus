// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// [N-6] 10k/min throughput with backpressure
const std = @import("std");
const Golden = @import("../golden.zig");

test "throughput & backpressure" {
    const res = try Golden.exec("janus notify flood --rate 10000/min --duration 60s --channels file");
    try Golden.expect_success(res);

    const metrics = try Golden.parse_json(res.stdout);

    // Verify throughput requirements
    const p99_enqueue_ms = try Golden.json_get_f64(metrics, "p99_enqueue_ms");
    try Golden.expect(p99_enqueue_ms <= 10.0);

    const dropped = try Golden.json_get_u64(metrics, "dropped");
    try Golden.expect(dropped == 0);

    const total_events = try Golden.json_get_u64(metrics, "total_events");
    try Golden.expect(total_events >= 10000); // should handle full load
}

test "backpressure engages under extreme load" {
    const res = try Golden.exec("janus notify flood --rate 50000/min --duration 30s --channels file");
    try Golden.expect_success(res);

    const metrics = try Golden.parse_json(res.stdout);

    // Under extreme load, backpressure should engage
    const backpressure_events = try Golden.json_get_u64(metrics, "backpressure_events");
    try Golden.expect(backpressure_events > 0);

    // But no events should be dropped (spilled to CAS instead)
    const dropped = try Golden.json_get_u64(metrics, "dropped");
    try Golden.expect(dropped == 0);

    const spilled_to_cas = try Golden.json_get_u64(metrics, "spilled_to_cas");
    try Golden.expect(spilled_to_cas > 0);
}

test "file channel atomic writes under load" {
    const res = try Golden.exec("janus notify flood --rate 1000/min --duration 10s --channels file --concurrent-writers 4");
    try Golden.expect_success(res);

    // Verify file integrity - should be valid JSONL
    const file_content = try Golden.read_file(".janus/events.jsonl");
    const lines = std.mem.split(u8, file_content, "\n");

    var valid_lines: u32 = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Each line should be valid JSON
        _ = try Golden.parse_json(line);
        valid_lines += 1;
    }

    try Golden.expect(valid_lines > 100); // should have many events

    // Verify no corruption metrics
    const metrics = try Golden.parse_json(res.stdout);
    const write_errors = try Golden.json_get_u64(metrics, "file_write_errors");
    try Golden.expect(write_errors == 0);
}

test "webhook channel handles slow endpoints" {
    var slow_mock = try Golden.MockWebhook.start(.{
        .status_seq = &.{200},
        .delay_ms = 2000, // 2s delay per request
    });
    defer slow_mock.stop();

    const cmd = try std.fmt.allocPrint(std.testing.allocator, "janus notify flood --rate 100/min --duration 10s --channels webhook --webhook-url {s}", .{slow_mock.url()});
    defer std.testing.allocator.free(cmd);

    const res = try Golden.exec(cmd);
    try Golden.expect_success(res);

    const metrics = try Golden.parse_json(res.stdout);

    // Should queue requests when webhook is slow
    const queued_requests = try Golden.json_get_u64(metrics, "webhook_queued");
    try Golden.expect(queued_requests > 0);

    // Should not drop events due to slow webhook
    const dropped = try Golden.json_get_u64(metrics, "dropped");
    try Golden.expect(dropped == 0);
}

test "memory usage remains bounded under load" {
    const res = try Golden.exec("janus notify flood --rate 5000/min --duration 60s --channels file --memory-limit 100MB");
    try Golden.expect_success(res);

    const metrics = try Golden.parse_json(res.stdout);

    const peak_memory_mb = try Golden.json_get_f64(metrics, "peak_memory_mb");
    try Golden.expect(peak_memory_mb <= 100.0);

    // Should use CAS spillover to maintain memory bounds
    const spilled_to_cas = try Golden.json_get_u64(metrics, "spilled_to_cas");
    if (peak_memory_mb > 80.0) {
        try Golden.expect(spilled_to_cas > 0);
    }
}

test "multiple channels maintain independent throughput" {
    var webhook_mock = try Golden.MockWebhook.start(.{ .status_seq = &.{200} });
    defer webhook_mock.stop();

    const cmd = try std.fmt.allocPrint(std.testing.allocator, "janus notify flood --rate 2000/min --duration 30s --channels stdout,file,webhook --webhook-url {s}", .{webhook_mock.url()});
    defer std.testing.allocator.free(cmd);

    const res = try Golden.exec(cmd);
    try Golden.expect_success(res);

    const metrics = try Golden.parse_json(res.stdout);

    // Each channel should handle its share of events
    const stdout_events = try Golden.json_get_u64(metrics, "stdout_events");
    const file_events = try Golden.json_get_u64(metrics, "file_events");
    const webhook_events = try Golden.json_get_u64(metrics, "webhook_events");

    try Golden.expect(stdout_events > 800); // ~1000 events per channel
    try Golden.expect(file_events > 800);
    try Golden.expect(webhook_events > 800);

    // Channel failures should not affect others
    const channel_failures = try Golden.json_get_object(metrics, "channel_failures");
    const stdout_failures = try Golden.json_get_u64(channel_failures, "stdout");
    const file_failures = try Golden.json_get_u64(channel_failures, "file");

    try Golden.expect(stdout_failures == 0);
    try Golden.expect(file_failures == 0);
}

test "graceful degradation under resource pressure" {
    // Simulate resource pressure with limited file descriptors
    const res = try Golden.exec("janus notify flood --rate 10000/min --duration 30s --channels file --max-fds 10");
    try Golden.expect_success(res);

    const metrics = try Golden.parse_json(res.stdout);

    // Should adapt to resource constraints
    const resource_pressure_events = try Golden.json_get_u64(metrics, "resource_pressure_events");
    try Golden.expect(resource_pressure_events > 0);

    // Should maintain service despite constraints
    const total_events = try Golden.json_get_u64(metrics, "total_events");
    try Golden.expect(total_events > 1000); // reduced but still functional

    const dropped = try Golden.json_get_u64(metrics, "dropped");
    try Golden.expect(dropped == 0); // no data loss
}
