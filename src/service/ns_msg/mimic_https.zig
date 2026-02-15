// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! MIMIC_HTTPS Transport Skin — Censorship-Resistant L0 Transport
//!
//! This module provides WebSocket framing and domain fronting capabilities
//! for tunneling LWF frames through HTTPS to bypass DPI and censorship.
//!
//! RFC-0015: Pluggable Transport Skins (PTS)

const std = @import("std");

/// MIMIC_HTTPS Configuration
pub const MimicHttpsConfig = struct {
    /// Cover domain for SNI (what DPI sees)
    cover_domain: []const u8 = "cdn.cloudflare.com",

    /// Real endpoint (Host header, encrypted in TLS)
    real_endpoint: []const u8 = "relay.libertaria.network",

    /// WebSocket path
    ws_path: []const u8 = "/api/v1/stream",

    /// TLS fingerprint to mimic
    tls_fingerprint: TlsFingerprint = .Chrome120,

    /// Enable ECH (requires ECH config from server)
    enable_ech: bool = true,

    /// ECH config list (base64 encoded, from DNS HTTPS record)
    ech_config: ?[]const u8 = null,
};

/// TLS Client fingerprints for parroting
pub const TlsFingerprint = enum {
    Chrome120,
    Firefox121,
    Safari17,
    Edge120,
};

/// WebSocket frame structure (RFC 6455)
pub const WebSocketFrame = struct {
    fin: bool = true,
    rsv: u3 = 0,
    opcode: Opcode = .binary,
    masked: bool = true,
    payload: []const u8,
    mask_key: [4]u8,

    pub const Opcode = enum(u4) {
        continuation = 0x0,
        text = 0x1,
        binary = 0x2,
        close = 0x8,
        ping = 0x9,
        pong = 0xA,
    };

    /// Serialize frame to wire format (RFC 6455)
    pub fn encode(self: WebSocketFrame, allocator: std.mem.Allocator) ![]u8 {
        const payload_len = self.payload.len;
        var header_len: usize = 2; // Minimum header

        // Determine header size based on payload length
        if (payload_len < 126) {
            header_len = 2;
        } else if (payload_len < 65536) {
            header_len = 4;
        } else {
            header_len = 10;
        }

        if (self.masked) header_len += 4;

        const frame = try allocator.alloc(u8, header_len + payload_len);
        errdefer allocator.free(frame);

        // Byte 0: FIN + RSV + Opcode
        frame[0] = (@as(u8, if (self.fin) 1 else 0) << 7) |
            (@as(u8, self.rsv) << 4) |
            @as(u8, @intFromEnum(self.opcode));

        // Byte 1: MASK + Payload length
        frame[1] = if (self.masked) 0x80 else 0x00;

        if (payload_len < 126) {
            frame[1] |= @as(u8, @intCast(payload_len));
        } else if (payload_len < 65536) {
            frame[1] |= 126;
            std.mem.writeInt(u16, frame[2..4], @intCast(payload_len), .big);
        } else {
            frame[1] |= 127;
            std.mem.writeInt(u64, frame[2..10], payload_len, .big);
        }

        // Mask key and payload
        if (self.masked) {
            const mask_start = header_len - 4;
            @memcpy(frame[mask_start..header_len], &self.mask_key);

            // Apply mask to payload
            for (self.payload, 0..) |b, i| {
                frame[header_len + i] = b ^ self.mask_key[i % 4];
            }
        } else {
            @memcpy(frame[header_len..], self.payload);
        }

        return frame;
    }

    /// Decode frame from wire format (RFC 6455)
    /// Returns null if frame is incomplete
    pub fn decode(allocator: std.mem.Allocator, data: []const u8) !?WebSocketFrame {
        if (data.len < 2) return null;

        const fin = (data[0] & 0x80) != 0;
        const rsv: u3 = @intCast((data[0] & 0x70) >> 4);
        const opcode = @as(Opcode, @enumFromInt(data[0] & 0x0F));
        const masked = (data[1] & 0x80) != 0;

        var payload_len: usize = @intCast(data[1] & 0x7F);
        var header_len: usize = 2;

        if (payload_len == 126) {
            if (data.len < 4) return null;
            payload_len = std.mem.readInt(u16, data[2..4], .big);
            header_len = 4;
        } else if (payload_len == 127) {
            if (data.len < 10) return null;
            payload_len = @intCast(std.mem.readInt(u64, data[2..10], .big));
            header_len = 10;
        }

        var mask_key = [4]u8{ 0, 0, 0, 0 };
        if (masked) {
            if (data.len < header_len + 4) return null;
            @memcpy(&mask_key, data[header_len..][0..4]);
            header_len += 4;
        }

        if (data.len < header_len + payload_len) return null;

        const payload = try allocator.alloc(u8, payload_len);
        errdefer allocator.free(payload);

        if (masked) {
            for (0..payload_len) |i| {
                payload[i] = data[header_len + i] ^ mask_key[i % 4];
            }
        } else {
            @memcpy(payload, data[header_len..][0..payload_len]);
        }

        return WebSocketFrame{
            .fin = fin,
            .rsv = rsv,
            .opcode = opcode,
            .masked = masked,
            .payload = payload,
            .mask_key = mask_key,
        };
    }
};

/// Domain Fronting HTTP Request Builder
pub const DomainFrontingRequest = struct {
    cover_domain: []const u8,
    real_host: []const u8,
    path: []const u8,
    user_agent: []const u8,

    /// Build HTTP request with domain fronting
    /// TLS SNI will contain cover_domain (visible to DPI)
    /// HTTP Host header will contain real_host (encrypted in TLS)
    pub fn build(self: DomainFrontingRequest, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator,
            "GET {s} HTTP/1.1\r\n" ++
                "Host: {s}\r\n" ++
                "User-Agent: {s}\r\n" ++
                "Accept: */*\r\n" ++
                "Accept-Language: en-US,en;q=0.9\r\n" ++
                "Accept-Encoding: gzip, deflate, br\r\n" ++
                "Upgrade: websocket\r\n" ++
                "Connection: Upgrade\r\n" ++
                "Sec-WebSocket-Key: {s}\r\n" ++
                "Sec-WebSocket-Version: 13\r\n" ++
                "\r\n",
            .{
                self.path,
                self.real_host,
                self.user_agent,
                self.generateWebSocketKey(),
            },
        );
    }

    fn generateWebSocketKey(self: DomainFrontingRequest) [24]u8 {
        // RFC 6455: 16-byte nonce, base64 encoded = 24 chars
        // In production: use crypto-secure random
        _ = self;
        return "dGhlIHNhbXBsZSBub25jZQ==".*;
    }
};

/// ECH (Encrypted Client Hello) Configuration
/// Hides the real SNI from network observers
pub const ECHConfig = struct {
    enabled: bool,
    /// ECH public key (from DNS HTTPS record)
    public_key: ?[]const u8,
    /// ECH config ID
    config_id: u16,

    /// Encrypt the inner ClientHello
    pub fn encrypt(self: ECHConfig, inner_hello: []const u8) ![]const u8 {
        // HPKE-based encryption (RFC 9180)
        // Inner ClientHello contains real SNI
        // Outer ClientHello contains cover SNI

        _ = self;
        _ = inner_hello;

        // TODO: HPKE implementation
        return &[_]u8{};
    }
};

/// TLS ClientHello configuration for fingerprint matching
pub const TlsClientHello = struct {
    fingerprint: TlsFingerprint,
    sni: []const u8,
    alpn: []const []const u8,

    /// Generate ClientHello bytes matching browser fingerprint
    pub fn encode(self: TlsClientHello, allocator: std.mem.Allocator) ![]u8 {
        // Simplified: In production, use proper TLS library (BearSSL, rustls)
        // This shows the structure for JA3 fingerprint parroting

        // Chrome 120 JA3 fingerprint:
        // 771,4865-4866-4867-49195-49199-49196-49200-52393-52392-49171-49172-
        // 156-157-47-53,0-23-65281-10-11-35-16-5-13-18-51-45-43-27-17513,29-
        // 23-24,0

        _ = self;
        _ = allocator;

        // TODO: Full TLS ClientHello implementation
        return &[_]u8{};
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "WebSocketFrame encode/decode roundtrip" {
    const allocator = std.testing.allocator;

    const payload = "Hello, WebSocket!";
    const mask_key = [4]u8{ 0x12, 0x34, 0x56, 0x78 };

    const frame = WebSocketFrame{
        .fin = true,
        .opcode = .text,
        .masked = true,
        .payload = payload,
        .mask_key = mask_key,
    };

    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    const decoded = try WebSocketFrame.decode(allocator, encoded);
    defer if (decoded) |d| allocator.free(d.payload);

    try std.testing.expect(decoded != null);
    try std.testing.expectEqualStrings(payload, decoded.?.payload);
    try std.testing.expect(decoded.?.fin);
}

test "WebSocketFrame large payload" {
    const allocator = std.testing.allocator;

    // Payload > 126 bytes (extended length)
    const payload = "A" ** 1000;

    const frame = WebSocketFrame{
        .opcode = .binary,
        .masked = false,
        .payload = payload,
        .mask_key = [4]u8{ 0, 0, 0, 0 },
    };

    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    // Should use 16-bit extended length
    try std.testing.expect(encoded[1] & 0x7F == 126);
}

test "DomainFrontingRequest builds correctly" {
    const allocator = std.testing.allocator;

    const request = DomainFrontingRequest{
        .cover_domain = "cdn.cloudflare.com",
        .real_host = "relay.libertaria.network",
        .path = "/api/v1/stream",
        .user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    };

    const http = try request.build(allocator);
    defer allocator.free(http);

    try std.testing.expect(std.mem.indexOf(u8, http, "Host: relay.libertaria.network") != null);
    try std.testing.expect(std.mem.indexOf(u8, http, "Upgrade: websocket") != null);
}

test "WebSocketFrame decode incomplete frame returns null" {
    const allocator = std.testing.allocator;

    // Just 1 byte - incomplete header
    const incomplete = [_]u8{0x82};
    const decoded = try WebSocketFrame.decode(allocator, &incomplete);
    try std.testing.expect(decoded == null);

    // Header claims 100 bytes but only 2 bytes provided
    const truncated = [_]u8{ 0x82, 100 };
    const decoded2 = try WebSocketFrame.decode(allocator, &truncated);
    try std.testing.expect(decoded2 == null);
}

test "WebSocketFrame unmasked frame" {
    const allocator = std.testing.allocator;

    const payload = "Unmasked data";
    const frame = WebSocketFrame{
        .opcode = .text,
        .masked = false,
        .payload = payload,
        .mask_key = [4]u8{ 0, 0, 0, 0 },
    };

    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    // Check mask bit is not set
    try std.testing.expect((encoded[1] & 0x80) == 0);

    const decoded = try WebSocketFrame.decode(allocator, encoded);
    defer if (decoded) |d| allocator.free(d.payload);

    try std.testing.expect(decoded != null);
    try std.testing.expectEqualStrings(payload, decoded.?.payload);
    try std.testing.expect(!decoded.?.masked);
}
