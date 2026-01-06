// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// [N-5] Slack adapter parity with webhook summary
const std = @import("std");
const Golden = @import("../golden.zig");

test "slack summary parity" {
    var webhook_mock = try Golden.MockWebhook.start(.{ .status_seq = &.{200} });
    defer webhook_mock.stop();

    var slack_mock = try Golden.MockWebhook.start(.{ .status_seq = &.{200} });
    defer slack_mock.stop();

    // Send same event to both webhook and slack
    const webhook_cmd = try std.fmt.allocPrint(std.testing.allocator, "janus build --check-no-work --notify --channels webhook --webhook-url {s}", .{webhook_mock.url()});
    defer std.testing.allocator.free(webhook_cmd);

    const slack_cmd = try std.fmt.allocPrint(std.testing.allocator, "janus build --check-no-work --notify --channels slack --slack-webhook {s}", .{slack_mock.url()});
    defer std.testing.allocator.free(slack_cmd);

    _ = try Golden.exec(webhook_cmd);
    _ = try Golden.exec(slack_cmd);

    const webhook_req = webhook_mock.received_requests()[0];
    const slack_req = slack_mock.received_requests()[0];

    // Both should have same core event data
    try Golden.json_eq_field(webhook_req, slack_req, "type");
    try Golden.json_eq_field(webhook_req, slack_req, "payload_cid");
    try Golden.json_eq_field(webhook_req, slack_req, "idempotency_key");

    // Slack should have formatted text field
    try Golden.json_has(slack_req, "text");
    const slack_text = try Golden.json_get_string(slack_req, "text");
    try Golden.assert_contains(slack_text, "Build completed");
    try Golden.assert_contains(slack_text, "no work required");
}

test "slack rate limiting and batching" {
    var slack_mock = try Golden.MockWebhook.start(.{ .status_seq = &.{ 200, 200, 200 } });
    defer slack_mock.stop();

    const slack_cmd = try std.fmt.allocPrint(std.testing.allocator, "janus build --check-no-work --notify --channels slack --slack-webhook {s}", .{slack_mock.url()});
    defer std.testing.allocator.free(slack_cmd);

    // Send multiple events rapidly
    for (0..5) |_| {
        _ = try Golden.exec(slack_cmd);
    }

    // Wait for batching window (5s)
    std.time.sleep(6 * std.time.ns_per_s);

    // Should receive fewer requests than events due to batching
    const requests = slack_mock.received_requests();
    try Golden.expect(requests.len <= 2); // batched into 1-2 messages

    // Verify batch message contains multiple events
    if (requests.len > 0) {
        const batch_text = try Golden.json_get_string(requests[0], "text");
        try Golden.assert_contains(batch_text, "5 events"); // batch summary
    }
}

test "slack message formatting" {
    var slack_mock = try Golden.MockWebhook.start(.{ .status_seq = &.{200} });
    defer slack_mock.stop();

    const cmd = try std.fmt.allocPrint(std.testing.allocator, "janus query --expr \"func main\" --notify --channels slack --slack-webhook {s} --privacy balanced", .{slack_mock.url()});
    defer std.testing.allocator.free(cmd);

    _ = try Golden.exec(cmd);

    const req = slack_mock.received_requests()[0];
    const slack_text = try Golden.json_get_string(req, "text");

    // Verify Slack-specific formatting
    try Golden.assert_contains(slack_text, ":mag:"); // search emoji
    try Golden.assert_contains(slack_text, "Query completed");
    try Golden.assert_contains(slack_text, "1 result"); // result count

    // Should contain link to CAS artifact
    try Golden.assert_contains(slack_text, "View details");
    try Golden.assert_contains(slack_text, "blake3:");

    // Should not contain raw source (privacy balanced)
    try Golden.assert_not_contains(slack_text, "func main");
}

test "discord adapter formatting differences" {
    var discord_mock = try Golden.MockWebhook.start(.{ .status_seq = &.{200} });
    defer discord_mock.stop();

    const cmd = try std.fmt.allocPrint(std.testing.allocator, "janus build --check-no-work --notify --channels discord --discord-webhook {s}", .{discord_mock.url()});
    defer std.testing.allocator.free(cmd);

    _ = try Golden.exec(cmd);

    const req = discord_mock.received_requests()[0];

    // Discord uses embeds instead of plain text
    try Golden.json_has(req, "embeds");
    const embeds = try Golden.json_get_array(req, "embeds");
    try Golden.expect(embeds.len > 0);

    const embed = embeds[0];
    try Golden.json_has(embed, "title");
    try Golden.json_has(embed, "description");
    try Golden.json_has(embed, "color");

    const title = try Golden.json_get_string(embed, "title");
    try Golden.assert_contains(title, "Build Completed");
}

test "telegram adapter character limits" {
    var telegram_mock = try Golden.MockWebhook.start(.{ .status_seq = &.{200} });
    defer telegram_mock.stop();

    // Generate a large query result
    const cmd = try std.fmt.allocPrint(std.testing.allocator, "janus query --expr \"*\" --notify --channels telegram --telegram-webhook {s}", .{telegram_mock.url()});
    defer std.testing.allocator.free(cmd);

    _ = try Golden.exec(cmd);

    const req = telegram_mock.received_requests()[0];
    const text = try Golden.json_get_string(req, "text");

    // Telegram has 4096 character limit
    try Golden.expect(text.len <= 4096);

    // Should contain truncation indicator if needed
    if (text.len >= 4000) {
        try Golden.assert_contains(text, "... (truncated)");
    }
}

test "x twitter adapter link handling" {
    var x_mock = try Golden.MockWebhook.start(.{ .status_seq = &.{200} });
    defer x_mock.stop();

    const cmd = try std.fmt.allocPrint(std.testing.allocator, "janus diff A..B --semantic --notify --channels x --x-webhook {s}", .{x_mock.url()});
    defer std.testing.allocator.free(cmd);

    _ = try Golden.exec(cmd);

    const req = x_mock.received_requests()[0];
    const text = try Golden.json_get_string(req, "text");

    // X/Twitter has 280 character limit
    try Golden.expect(text.len <= 280);

    // Should contain shortened summary
    try Golden.assert_contains(text, "Semantic diff found");

    // Should contain link to full details
    try Golden.assert_contains(text, "Details: ");
    try Golden.assert_contains(text, "blake3:");
}
