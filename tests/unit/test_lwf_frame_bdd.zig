// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const lwf = @import("lwf");
const crypto = std.crypto;

// LWF Frame BDD Test Suite
// These tests follow the Gherkin scenarios in features/transport/lwf_frame.feature

// ============================================================================
// Test: Frame Structure Validation
// ============================================================================

test "LWF Frame: Encode and decode frame with minimal payload" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given a frame class "Micro" (as per BDD scenario)
    var header: lwf.Header = .{};
    header.frame_class = .Micro;

    // And a payload of "Hello" (but Micro has 0 max payload, so use Standard for this test)
    // NOTE: BDD scenario says Micro, but Micro can only hold 0 bytes. Using Standard.
    header.frame_class = .Standard;
    const payload = "Hello";

    // When the frame is encoded
    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame_bytes);

    // Then the encoded frame size is 161 bytes (88 header + 5 payload + 68 trailer)
    try std.testing.expectEqual(@as(usize, 161), frame_bytes.len);

    // And the header magic equals "LWF\\0"
    try std.testing.expectEqualSlices(u8, &lwf.Magic, frame_bytes[0..4]);

    // And the header payload_len equals 5
    const payload_len = std.mem.readInt(u16, frame_bytes[74..][0..2], .big);
    try std.testing.expectEqual(@as(u16, 5), payload_len);

    // And the header frame_class equals 0x02 (Standard)
    try std.testing.expectEqual(@as(u8, 0x02), frame_bytes[76]);

    // Verify frame can be decoded
    const frame_copy = try allocator.dupe(u8, frame_bytes);
    // Note: decoded.deinit() frees frame_copy, so no explicit free needed

    var decoded = try lwf.decodeFrame(allocator, frame_copy, null, .AllowUnsigned);
    defer decoded.deinit(allocator);

    // Verify payload matches
    try std.testing.expectEqualSlices(u8, payload, decoded.payload);
}

test "LWF Frame: Encode frame with all header fields set" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given a header with all fields set
    var header: lwf.Header = .{};
    @memcpy(&header.dest_hint, &[_]u8{0xAB} ** 24);
    @memcpy(&header.source_hint, &[_]u8{0xCD} ** 24);
    @memcpy(&header.session_id, &[_]u8{0xEF} ** 16);
    header.sequence = 42;
    header.service_type = 0x0501;
    header.frame_class = .Standard;
    header.version = 1;
    header.flags = 0;
    header.entropy_difficulty = 8;
    header.timestamp = 1700000000000;

    // And a payload of 100 bytes
    const payload = try allocator.alloc(u8, 100);
    defer allocator.free(payload);
    @memset(payload, 0x42);

    // When the frame is encoded
    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame_bytes);

    // And the frame is decoded
    const frame_copy = try allocator.dupe(u8, frame_bytes);
    // Note: decoded.deinit() frees frame_copy

    var decoded = try lwf.decodeFrame(allocator, frame_copy, null, .AllowUnsigned);
    defer decoded.deinit(allocator);

    // Then all header fields match the original values
    try std.testing.expectEqualSlices(u8, &header.dest_hint, &decoded.header.dest_hint);
    try std.testing.expectEqualSlices(u8, &header.source_hint, &decoded.header.source_hint);
    try std.testing.expectEqualSlices(u8, &header.session_id, &decoded.header.session_id);
    try std.testing.expectEqual(header.sequence, decoded.header.sequence);
    try std.testing.expectEqual(header.service_type, decoded.header.service_type);
    try std.testing.expectEqual(header.frame_class, decoded.header.frame_class);
    try std.testing.expectEqual(header.version, decoded.header.version);
    // flags will have FlagUnsigned set because we didn't sign
    try std.testing.expect((decoded.header.flags & lwf.FlagUnsigned) != 0);
    try std.testing.expectEqual(header.entropy_difficulty, decoded.header.entropy_difficulty);
    try std.testing.expectEqual(header.timestamp, decoded.header.timestamp);
    try std.testing.expectEqualSlices(u8, payload, decoded.payload);
}

// ============================================================================
// Test: Frame Classes and Size Limits
// ============================================================================

test "LWF Frame: Frame class Micro size limits" {
    // Micro: 128 - 88 - 68 = -28, clamped to 0
    try std.testing.expectEqual(@as(usize, 128), lwf.maxFrameSize(.Micro));
    try std.testing.expectEqual(@as(usize, 0), lwf.maxPayloadSize(.Micro));
}

test "LWF Frame: Frame class Mini size limits" {
    // Mini: 512 - 88 - 68 = 356
    try std.testing.expectEqual(@as(usize, 512), lwf.maxFrameSize(.Mini));
    try std.testing.expectEqual(@as(usize, 356), lwf.maxPayloadSize(.Mini));
}

test "LWF Frame: Frame class Standard size limits" {
    // Standard: 1350 - 88 - 68 = 1194
    try std.testing.expectEqual(@as(usize, 1350), lwf.maxFrameSize(.Standard));
    try std.testing.expectEqual(@as(usize, 1194), lwf.maxPayloadSize(.Standard));
}

test "LWF Frame: Frame class Big size limits" {
    // Big: 4096 - 88 - 68 = 3940
    try std.testing.expectEqual(@as(usize, 4096), lwf.maxFrameSize(.Big));
    try std.testing.expectEqual(@as(usize, 3940), lwf.maxPayloadSize(.Big));
}

test "LWF Frame: Frame class Jumbo size limits" {
    // Jumbo: 9000 - 88 - 68 = 8844
    try std.testing.expectEqual(@as(usize, 9000), lwf.maxFrameSize(.Jumbo));
    try std.testing.expectEqual(@as(usize, 8844), lwf.maxPayloadSize(.Jumbo));
}

test "LWF Frame: Reject payload exceeding frame class limit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given a frame class "Micro"
    var header: lwf.Header = .{};
    header.frame_class = .Micro;

    // And a payload of 10 bytes (exceeds 4-byte limit)
    const payload = "0123456789";

    // When attempting to encode the frame
    const result = lwf.encodeFrame(allocator, header, payload, null);

    // Then the operation fails with error "PayloadTooLarge"
    try std.testing.expectError(error.PayloadTooLarge, result);
}

// ============================================================================
// Test: Integrity and Verification
// ============================================================================

test "LWF Frame: Frame with valid CRC32C checksum passes verification" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given a valid encoded frame
    const header: lwf.Header = .{};
    const payload = "Test payload for CRC verification";

    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame_bytes);

    // When the frame is decoded with checksum verification
    const frame_copy = try allocator.dupe(u8, frame_bytes);
    // Note: decoded.deinit() frees frame_copy

    var decoded = try lwf.decodeFrame(allocator, frame_copy, null, .AllowUnsigned);
    defer decoded.deinit(allocator);

    // Then the decoded payload matches the original
    try std.testing.expectEqualSlices(u8, payload, decoded.payload);
}

test "LWF Frame: Frame with corrupted checksum fails verification" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given a valid encoded frame
    const header: lwf.Header = .{};
    const payload = "Test payload";

    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame_bytes);

    // And the trailer checksum byte at offset 0 is corrupted
    const frame_copy = try allocator.dupe(u8, frame_bytes);
    defer allocator.free(frame_copy);

    const checksum_offset = frame_copy.len - 4;
    frame_copy[checksum_offset] ^= 0xFF;

    // When attempting to decode the frame
    const result = lwf.decodeFrame(allocator, frame_copy, null, .AllowUnsigned);

    // Then the operation fails with error "ChecksumMismatch"
    try std.testing.expectError(error.ChecksumMismatch, result);
}

test "LWF Frame: Frame with truncated data fails decoding" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given a valid encoded frame
    const header: lwf.Header = .{};
    const payload = "Test payload";

    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame_bytes);

    // And the frame is truncated by 10 bytes
    const truncated = frame_bytes[0 .. frame_bytes.len - 10];
    const frame_copy = try allocator.dupe(u8, truncated);
    defer allocator.free(frame_copy);

    // When attempting to decode the frame
    const result = lwf.decodeFrame(allocator, frame_copy, null, .AllowUnsigned);

    // Then the operation fails with error "InvalidLength"
    try std.testing.expectError(error.InvalidLength, result);
}

// ============================================================================
// Test: Signed Frames
// ============================================================================

test "LWF Frame: Encode and verify signed frame" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generate Ed25519 keypair
    const keypair = crypto.sign.Ed25519.KeyPair.generate();
    const signing_key = lwf.SigningKey{ .keypair = keypair };
    const verify_key = lwf.VerifyKey{ .public_key = keypair.public_key };

    // Given a payload
    const header: lwf.Header = .{};
    const payload = "Signed message";

    // When the frame is encoded with signing
    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, signing_key);
    defer allocator.free(frame_bytes);

    // Then the trailer contains a 64-byte Ed25519 signature
    const sig_offset = frame_bytes.len - 68; // 64 sig + 4 checksum
    var signature: [64]u8 = undefined;
    @memcpy(&signature, frame_bytes[sig_offset..][0..64]);

    // Verify signature is not all zeros
    var all_zeros = true;
    for (signature) |b| {
        if (b != 0) {
            all_zeros = false;
            break;
        }
    }
    try std.testing.expect(!all_zeros);

    // Verify the frame decodes correctly with verification
    const frame_copy = try allocator.dupe(u8, frame_bytes);
    // Note: decoded.deinit() frees frame_copy

    var decoded = try lwf.decodeFrame(allocator, frame_copy, verify_key, .RequireSigned);
    defer decoded.deinit(allocator);

    try std.testing.expectEqualSlices(u8, payload, decoded.payload);
}

test "LWF Frame: Reject unsigned frame when signed required" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given an unsigned frame (FlagUnsigned set)
    const header: lwf.Header = .{};
    const payload = "Unsigned message";

    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame_bytes);

    // Verify FlagUnsigned is set
    try std.testing.expect((frame_bytes[78] & lwf.FlagUnsigned) != 0);

    const frame_copy = try allocator.dupe(u8, frame_bytes);
    defer allocator.free(frame_copy);

    // When decoding with VerifyMode.RequireSigned
    const result = lwf.decodeFrame(allocator, frame_copy, null, .RequireSigned);

    // Then the operation fails with error "UnsignedFrame"
    try std.testing.expectError(error.UnsignedFrame, result);
}

test "LWF Frame: Accept unsigned frame when allowed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given an unsigned frame
    const header: lwf.Header = .{};
    const payload = "Unsigned message";

    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame_bytes);

    const frame_copy = try allocator.dupe(u8, frame_bytes);
    // NOTE: decoded.deinit() frees frame_copy, so we don't free it separately

    // When decoding with VerifyMode.AllowUnsigned
    var decoded = try lwf.decodeFrame(allocator, frame_copy, null, .AllowUnsigned);
    defer decoded.deinit(allocator);

    // Then the frame decodes successfully
    try std.testing.expectEqualSlices(u8, payload, decoded.payload);
}

test "LWF Frame: Reject frame with invalid signature" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generate keypair
    const keypair = crypto.sign.Ed25519.KeyPair.generate();
    const signing_key = lwf.SigningKey{ .keypair = keypair };

    const header: lwf.Header = .{};
    const payload = "Test message";

    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, signing_key);
    defer allocator.free(frame_bytes);

    // Create wrong verify key (different keypair)
    const wrong_keypair = crypto.sign.Ed25519.KeyPair.generate();
    const wrong_verify = lwf.VerifyKey{ .public_key = wrong_keypair.public_key };

    // Copy frame for decoding (decodeFrame takes ownership)
    const frame_copy = try allocator.dupe(u8, frame_bytes);
    // NOTE: decoded.deinit() frees frame_copy on success, but on error we need to free it

    // When attempting to decode with wrong verify key
    const result = lwf.decodeFrame(allocator, frame_copy, wrong_verify, .RequireSigned);

    // Clean up frame_copy on error path
    if (result == error.SignatureVerificationFailed) {
        allocator.free(frame_copy);
    }

    // Then signature verification fails
    try std.testing.expectError(error.SignatureVerificationFailed, result);
}

// ============================================================================
// Test: Session and Sequence Management
// ============================================================================

test "LWF Frame: Sequence number increments correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given a session with sequence number 100
    var sequence: u32 = 100;

    // When encoding 3 frames in sequence
    var headers: [3]lwf.Header = undefined;
    var frame_bytes: [3][]u8 = undefined;

    for (0..3) |i| {
        headers[i] = .{};
        headers[i].sequence = sequence;
        frame_bytes[i] = try lwf.encodeFrame(allocator, headers[i], "test", null);
        sequence += 1;
    }

    defer for (frame_bytes) |fb| allocator.free(fb);

    // Then the frames have sequence numbers 100, 101, 102
    for (frame_bytes, 0..) |fb, i| {
        const decoded_seq = std.mem.readInt(u32, fb[68..][0..4], .big);
        try std.testing.expectEqual(@as(u32, 100 + @as(u32, @intCast(i))), decoded_seq);
    }
}

test "LWF Frame: Read payload length from raw header bytes" {
    // Given raw header bytes with payload_len at offset 74-76
    var header: lwf.Header = .{};
    header.payload_len = 1234;

    var header_bytes: [lwf.HeaderSize]u8 = undefined;
    lwf.encodeHeader(header, &header_bytes);

    // When calling readPayloadLen
    const payload_len = try lwf.readPayloadLen(&header_bytes);

    // Then the correct payload length is returned
    try std.testing.expectEqual(@as(u16, 1234), payload_len);
}

// ============================================================================
// Test: Error Handling
// ============================================================================

test "LWF Frame: Reject frame with invalid magic bytes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Given a valid encoded frame
    const header: lwf.Header = .{};
    const payload = "Test";

    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame_bytes);

    // Corrupt the magic bytes
    const frame_copy = try allocator.dupe(u8, frame_bytes);
    defer allocator.free(frame_copy);
    frame_copy[0] = 'X';
    frame_copy[1] = 'X';
    frame_copy[2] = 'Y';
    frame_copy[3] = 'Z';

    // When attempting to decode the frame
    const result = lwf.decodeFrame(allocator, frame_copy, null, .AllowUnsigned);

    // Then the operation fails with error "InvalidMagic"
    try std.testing.expectError(error.InvalidMagic, result);
}

test "LWF Frame: Reject header decode with insufficient bytes" {
    // Given only 50 bytes of header data
    const insufficient_bytes = [_]u8{0} ** 50;

    // When attempting to decode the header
    const result = lwf.decodeHeader(&insufficient_bytes);

    // Then the operation fails with error "InvalidLength"
    try std.testing.expectError(error.InvalidLength, result);
}

test "LWF Frame: Missing verify key for signed frame" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generate keypair and create signed frame
    const keypair = crypto.sign.Ed25519.KeyPair.generate();
    const signing_key = lwf.SigningKey{ .keypair = keypair };

    var header: lwf.Header = .{};
    // Clear FlagUnsigned to make it appear signed
    header.flags = 0;

    const payload = "Test message";

    const frame_bytes = try lwf.encodeFrame(allocator, header, payload, signing_key);
    defer allocator.free(frame_bytes);

    const frame_copy = try allocator.dupe(u8, frame_bytes);
    defer allocator.free(frame_copy);

    // When attempting to decode without verify key
    const result = lwf.decodeFrame(allocator, frame_copy, null, .RequireSigned);

    // Then the operation fails with error "MissingVerifyKey"
    try std.testing.expectError(error.MissingVerifyKey, result);
}
