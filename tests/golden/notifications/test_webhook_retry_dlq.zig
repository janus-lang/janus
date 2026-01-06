// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// [N-2] Webhook retry & DLQ
const std = @import("std");
const Golden = @import("../golden.zig");

test "webhook retry and DLQ" {
    var mock = try Golden.MockWebhook.start(.{ .status_seq = &.{ 500, 500, 500, 200 } });
    defer mock.stop();

    const res = try Golden.execFmt("janus query --expr \"func\" --notify --channels webhook --webhook-url {s}", .{mock.url()});

    try Golden.jsonl_contains(res.stdout, "idempotency_key");
    try Golden.expect(mock.received_count() == 4); // 3 retries + 1 success
    try Golden.expect(Golden.dlq_count("webhook") == 0);

    // Verify idempotency key was same across retries
    const requests = mock.received_requests();
    for (requests[1..]) |req| {
        try Golden.json_eq_field(requests[0], req, "idempotency_key");
    }
}

test "webhook max retries and DLQ" {
    var mock = try Golden.MockWebhook.start(.{ .status_seq = &.{ 500, 500, 500, 500, 500, 500, 500, 500, 500 } });
    defer mock.stop();

    const res = try Golden.execFmt("janus query --expr \"func\" --notify --channels webhook --webhook-url {s}", .{mock.url()});

    try Golden.expect(mock.received_count() == 8); // max retries
    try Golden.expect(Golden.dlq_count("webhook") == 1); // moved to DLQ

    // Verify DLQ entry contains original event
    const dlq_event = try Golden.dlq_peek("webhook");
    try Golden.json_has(dlq_event, "type", "query.result");
    try Golden.json_has(dlq_event, "idempotency_key");
}

test "webhook HMAC signature validation" {
    var mock = try Golden.MockWebhook.start(.{ .status_seq = &.{200}, .validate_hmac = true });
    defer mock.stop();

    const res = try Golden.execFmt("janus query --expr \"func\" --notify --channels webhook --webhook-url {s} --hmac-key test-key", .{mock.url()});

    try Golden.expect(mock.received_count() == 1);

    const req = mock.received_requests()[0];
    try Golden.assert_header_present(req, "X-Janus-Signature");
    try Golden.assert_hmac_valid(req, "test-key");
}

test "webhook timeout handling" {
    var mock = try Golden.MockWebhook.start(.{ .delay_ms = 5000 }); // 5s delay
    defer mock.stop();

    const res = try Golden.execFmt("janus query --expr \"func\" --notify --channels webhook --webhook-url {s} --timeout-ms 1000", .{mock.url()});

    try Golden.expect_error_code(res, "WB2001"); // WebhookTimeout
    try Golden.expect(Golden.dlq_count("webhook") == 1);
}
