// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// [N-1] Byte-stable stdout without timestamps
const std = @import("std");
const Golden = @import("../golden.zig");

test "deterministic stdout events" {
    const a = try Golden.exec("janus build --check-no-work --notify --channels stdout --no-timestamps --deterministic");
    const b = try Golden.exec("janus build --check-no-work --notify --channels stdout --no-timestamps --deterministic");
    try Golden.eq_bytes(a.stdout, b.stdout);
}

test "deterministic event envelope structure" {
    const out = try Golden.exec("janus build --check-no-work --notify --channels stdout --no-timestamps --deterministic");
    const event = try Golden.parse_jsonl_first(out.stdout);

    // Verify canonical key order
    const expected_keys = [_][]const u8{ "id", "type", "source", "profile", "deterministic", "privacy_mode", "payload_cid", "payload", "related", "idempotency_key", "sig" };
    try Golden.assert_key_order(event, &expected_keys);

    // Verify deterministic fields
    try Golden.json_eq(event, "deterministic", true);
    try Golden.json_missing(event, "timestamp"); // suppressed with --no-timestamps
}

test "idempotency key stability across runs" {
    const a = try Golden.exec("janus build --check-no-work --notify --channels stdout --no-timestamps --deterministic");
    const b = try Golden.exec("janus build --check-no-work --notify --channels stdout --no-timestamps --deterministic");

    const event_a = try Golden.parse_jsonl_first(a.stdout);
    const event_b = try Golden.parse_jsonl_first(b.stdout);

    try Golden.json_eq_field(event_a, event_b, "idempotency_key");
    try Golden.json_eq_field(event_a, event_b, "payload_cid");
}
