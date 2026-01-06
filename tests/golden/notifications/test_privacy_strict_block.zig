// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// [N-3] No leaks in strict mode
const std = @import("std");
const Golden = @import("../golden.zig");

test "strict privacy gate blocks source leakage" {
    const out = try Golden.exec("janus diff A..B --semantic --notify --channels webhook --privacy strict");
    try Golden.expect_error_code(out, "NX1010"); // PrivacyViolation blocked before network
    try Golden.assert_not_contains(out.stderr, "func "); // no symbol names
    try Golden.assert_not_contains(out.stderr, "blake3:"); // no dereferenceable CIDs
}

test "strict mode redacts payload content" {
    const out = try Golden.exec("janus query --expr \"func main\" --notify --channels stdout --privacy strict");
    const event = try Golden.parse_jsonl_first(out.stdout);

    // Verify privacy mode is recorded
    try Golden.json_eq(event, "privacy_mode", "strict");

    // Verify payload is redacted
    const payload = try Golden.json_get_object(event, "payload");
    try Golden.json_has(payload, "summary_count"); // allowed: counts
    try Golden.json_has(payload, "result_type"); // allowed: types
    try Golden.json_missing(payload, "source_text"); // blocked: source
    try Golden.json_missing(payload, "symbol_names"); // blocked: symbols
    try Golden.json_missing(payload, "file_paths"); // blocked: paths
}

test "balanced mode provides pseudonyms" {
    const out = try Golden.exec("janus query --expr \"func main\" --notify --channels stdout --privacy balanced");
    const event = try Golden.parse_jsonl_first(out.stdout);

    try Golden.json_eq(event, "privacy_mode", "balanced");

    const payload = try Golden.json_get_object(event, "payload");
    try Golden.json_has(payload, "symbol_pseudonyms"); // stable pseudonyms
    try Golden.json_missing(payload, "source_text"); // still no source

    // Verify pseudonyms are stable across runs
    const out2 = try Golden.exec("janus query --expr \"func main\" --notify --channels stdout --privacy balanced");
    const event2 = try Golden.parse_jsonl_first(out2.stdout);
    const payload2 = try Golden.json_get_object(event2, "payload");

    try Golden.json_eq_field(payload, payload2, "symbol_pseudonyms");
}

test "local_only mode blocks external channels" {
    const out = try Golden.exec("janus query --expr \"func\" --notify --channels webhook --privacy local_only");
    try Golden.expect_error_code(out, "NX1010"); // PrivacyViolation
    try Golden.assert_contains(out.stderr, "local_only mode blocks external channels");
}

test "local_only allows stdout and file" {
    const out = try Golden.exec("janus query --expr \"func\" --notify --channels stdout,file --privacy local_only");
    try Golden.expect_success(out);

    const event = try Golden.parse_jsonl_first(out.stdout);
    try Golden.json_eq(event, "privacy_mode", "local_only");

    // Verify file was written
    const file_content = try Golden.read_file(".janus/events.jsonl");
    try Golden.assert_contains(file_content, "local_only");
}

test "payload_cid reflects redacted content" {
    // Same query with different privacy modes should have different payload_cids
    const strict_out = try Golden.exec("janus query --expr \"func main\" --notify --channels stdout --privacy strict");
    const balanced_out = try Golden.exec("janus query --expr \"func main\" --notify --channels stdout --privacy balanced");

    const strict_event = try Golden.parse_jsonl_first(strict_out.stdout);
    const balanced_event = try Golden.parse_jsonl_first(balanced_out.stdout);

    const strict_cid = try Golden.json_get_string(strict_event, "payload_cid");
    const balanced_cid = try Golden.json_get_string(balanced_event, "payload_cid");

    try Golden.expect(!std.mem.eql(u8, strict_cid, balanced_cid));
}
