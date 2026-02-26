// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const mimic = @import("mimic_https");

// MIMIC_HTTPS Transport BDD Test Suite
// These tests follow the Gherkin scenarios in features/transport/mimic_https.feature

// ============================================================================
// Test: WebSocket Frame Encoding/Decoding
// ============================================================================

test "MIMIC_HTTPS: Encode and decode WebSocket text frame" {
    const allocator = std.testing.allocator;

    // Given a WebSocket frame with text payload
    const payload = "Hello, World!";
    const mask_key = [4]u8{ 0x12, 0x34, 0x56, 0x78 };

    const frame = mimic.WebSocketFrame{
        .fin = true,
        .opcode = .text,
        .masked = true,
        .payload = payload,
        .mask_key = mask_key,
    };

    // When the frame is encoded to wire format
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    // And the frame is decoded from wire format
    const decoded = try mimic.WebSocketFrame.decode(allocator, encoded);
    defer if (decoded) |d| allocator.free(d.payload);

    // Then the decoded payload equals "Hello, World!"
    try std.testing.expect(decoded != null);
    try std.testing.expectEqualStrings(payload, decoded.?.payload);
    try std.testing.expect(decoded.?.fin);
    try std.testing.expectEqual(mimic.WebSocketFrame.Opcode.text, decoded.?.opcode);
}

test "MIMIC_HTTPS: Encode and decode WebSocket binary frame" {
    const allocator = std.testing.allocator;

    // Given binary payload
    const payload = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD, 0xFC };

    const frame = mimic.WebSocketFrame{
        .fin = true,
        .opcode = .binary,
        .masked = false,
        .payload = &payload,
        .mask_key = [4]u8{ 0, 0, 0, 0 },
    };

    // When encoded and decoded
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    const decoded = try mimic.WebSocketFrame.decode(allocator, encoded);
    defer if (decoded) |d| allocator.free(d.payload);

    // Then payload matches
    try std.testing.expect(decoded != null);
    try std.testing.expectEqualSlices(u8, &payload, decoded.?.payload);
}

test "MIMIC_HTTPS: WebSocket frame with small payload" {
    const allocator = std.testing.allocator;

    // Given a payload of 100 bytes
    const payload = "A" ** 100;

    const frame = mimic.WebSocketFrame{
        .opcode = .binary,
        .masked = false,
        .payload = payload,
        .mask_key = [4]u8{ 0, 0, 0, 0 },
    };

    // When encoded
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    // Then header length is 2 bytes (no extended length)
    try std.testing.expectEqual(@as(usize, 2 + 100), encoded.len);
    // And payload length byte equals 100
    try std.testing.expectEqual(@as(u8, 100), encoded[1] & 0x7F);
}

test "MIMIC_HTTPS: WebSocket frame with medium payload" {
    const allocator = std.testing.allocator;

    // Given a payload of 1000 bytes
    const payload = try allocator.alloc(u8, 1000);
    defer allocator.free(payload);
    @memset(payload, 'B');

    const frame = mimic.WebSocketFrame{
        .opcode = .binary,
        .masked = false,
        .payload = payload,
        .mask_key = [4]u8{ 0, 0, 0, 0 },
    };

    // When encoded
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    // Then header uses 16-bit extended length (126 prefix)
    try std.testing.expectEqual(@as(u8, 126), encoded[1] & 0x7F);
    // And the 2-byte length field equals 1000 (big-endian)
    const length = std.mem.readInt(u16, encoded[2..4], .big);
    try std.testing.expectEqual(@as(u16, 1000), length);
}

test "MIMIC_HTTPS: WebSocket masking is applied correctly" {
    const allocator = std.testing.allocator;

    // Given a payload "ABC"
    const payload = "ABC";
    const mask_key = [4]u8{ 0x01, 0x02, 0x03, 0x04 };

    const frame = mimic.WebSocketFrame{
        .opcode = .text,
        .masked = true,
        .payload = payload,
        .mask_key = mask_key,
    };

    // When encoded
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    // The header should indicate masking
    try std.testing.expect((encoded[1] & 0x80) != 0);

    // When decoded, original payload is recovered
    const decoded = try mimic.WebSocketFrame.decode(allocator, encoded);
    defer if (decoded) |d| allocator.free(d.payload);

    try std.testing.expect(decoded != null);
    try std.testing.expectEqualStrings(payload, decoded.?.payload);
}

// ============================================================================
// Test: Domain Fronting
// ============================================================================

test "MIMIC_HTTPS: Build domain fronting HTTP request" {
    const allocator = std.testing.allocator;

    // Given a domain fronting config
    const request = mimic.DomainFrontingRequest{
        .cover_domain = "cdn.cloudflare.com",
        .real_host = "relay.libertaria.network",
        .path = "/api/v1/stream",
        .user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    };

    // When the HTTP request is built
    const http = try request.build(allocator);
    defer allocator.free(http);

    // Then the request contains expected headers
    try std.testing.expect(std.mem.indexOf(u8, http, "Host: relay.libertaria.network") != null);
    try std.testing.expect(std.mem.indexOf(u8, http, "Upgrade: websocket") != null);
    try std.testing.expect(std.mem.indexOf(u8, http, "Sec-WebSocket-Version: 13") != null);
    try std.testing.expect(std.mem.indexOf(u8, http, "GET /api/v1/stream") != null);
}

// ============================================================================
// Test: Error Handling
// ============================================================================

test "MIMIC_HTTPS: Reject truncated WebSocket frame" {
    const allocator = std.testing.allocator;

    // Given a truncated frame (just header, no payload)
    const truncated = [_]u8{ 0x82, 0x80 }; // Binary frame, masked, claims 0 length but incomplete mask

    // When attempting to decode
    const decoded = try mimic.WebSocketFrame.decode(allocator, &truncated);

    // Then null is returned (incomplete)
    try std.testing.expect(decoded == null);
}

test "MIMIC_HTTPS: Handle incomplete WebSocket header" {
    const allocator = std.testing.allocator;

    // Given only 1 byte of frame data
    const incomplete = [_]u8{0x82};

    // When attempting to decode
    const decoded = try mimic.WebSocketFrame.decode(allocator, &incomplete);

    // Then null is returned
    try std.testing.expect(decoded == null);
}

test "MIMIC_HTTPS: WebSocket frame with payload over 65535" {
    const allocator = std.testing.allocator;

    // Given a large payload (70KB)
    const payload = try allocator.alloc(u8, 70000);
    defer allocator.free(payload);
    @memset(payload, 'X');

    const frame = mimic.WebSocketFrame{
        .opcode = .binary,
        .masked = false,
        .payload = payload,
        .mask_key = [4]u8{ 0, 0, 0, 0 },
    };

    // When encoded
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    // Then header uses 64-bit extended length (127 prefix)
    try std.testing.expectEqual(@as(u8, 127), encoded[1] & 0x7F);

    // Verify roundtrip
    const decoded = try mimic.WebSocketFrame.decode(allocator, encoded);
    defer if (decoded) |d| allocator.free(d.payload);

    try std.testing.expect(decoded != null);
    try std.testing.expectEqual(@as(usize, 70000), decoded.?.payload.len);
}

// ============================================================================
// Test: TLS Configuration
// ============================================================================

test "MIMIC_HTTPS: TLS fingerprint enum variants" {
    // Verify all expected TLS fingerprint types exist
    const chrome = mimic.TlsFingerprint.Chrome120;
    const firefox = mimic.TlsFingerprint.Firefox121;
    const safari = mimic.TlsFingerprint.Safari17;
    const edge = mimic.TlsFingerprint.Edge120;

    _ = chrome;
    _ = firefox;
    _ = safari;
    _ = edge;
}

test "MIMIC_HTTPS: MimicHttpsConfig defaults" {
    const config = mimic.MimicHttpsConfig{};

    try std.testing.expectEqualStrings("cdn.cloudflare.com", config.cover_domain);
    try std.testing.expectEqualStrings("relay.libertaria.network", config.real_endpoint);
    try std.testing.expectEqualStrings("/api/v1/stream", config.ws_path);
    try std.testing.expectEqual(mimic.TlsFingerprint.Chrome120, config.tls_fingerprint);
    try std.testing.expect(config.enable_ech);
    try std.testing.expect(config.ech_config == null);
}

// ============================================================================
// Test: WebSocket Opcodes
// ============================================================================

test "MIMIC_HTTPS: WebSocket control frames" {
    const allocator = std.testing.allocator;

    // Test ping frame
    const ping_frame = mimic.WebSocketFrame{
        .opcode = .ping,
        .masked = true,
        .payload = "",
        .mask_key = [4]u8{ 0xAA, 0xBB, 0xCC, 0xDD },
    };

    const ping_encoded = try ping_frame.encode(allocator);
    defer allocator.free(ping_encoded);

    try std.testing.expectEqual(@as(u8, 0x89), ping_encoded[0]); // FIN=1, opcode=9 (ping)

    // Test pong frame
    const pong_frame = mimic.WebSocketFrame{
        .opcode = .pong,
        .masked = false,
        .payload = "",
        .mask_key = [4]u8{ 0, 0, 0, 0 },
    };

    const pong_encoded = try pong_frame.encode(allocator);
    defer allocator.free(pong_encoded);

    try std.testing.expectEqual(@as(u8, 0x8A), pong_encoded[0]); // FIN=1, opcode=10 (pong)

    // Test close frame
    const close_frame = mimic.WebSocketFrame{
        .opcode = .close,
        .masked = true,
        .payload = "",
        .mask_key = [4]u8{ 0x11, 0x22, 0x33, 0x44 },
    };

    const close_encoded = try close_frame.encode(allocator);
    defer allocator.free(close_encoded);

    try std.testing.expectEqual(@as(u8, 0x88), close_encoded[0]); // FIN=1, opcode=8 (close)
}

test "MIMIC_HTTPS: WebSocket continuation frame" {
    const allocator = std.testing.allocator;

    const frame = mimic.WebSocketFrame{
        .fin = false, // Not final fragment
        .opcode = .continuation,
        .masked = false,
        .payload = "continuation data",
        .mask_key = [4]u8{ 0, 0, 0, 0 },
    };

    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    // FIN=0, opcode=0 (continuation)
    try std.testing.expectEqual(@as(u8, 0x00), encoded[0]);
}
