// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Libertaria Wire Frame (LWF) encoding and decoding.
//!
//! This module encodes and parses the fixed LWF header and trailer and
//! provides frame verification utilities.

const std = @import("std");
const crypto = std.crypto;

pub const HeaderSize: usize = 88;
pub const TrailerSize: usize = 68;  // 64-byte Ed25519 signature + 4-byte checksum
pub const Overhead: usize = HeaderSize + TrailerSize;

pub const Magic: [4]u8 = .{ 'L', 'W', 'F', 0x00 };

pub const FrameClass = enum(u8) {
    Micro = 0x00,
    Mini = 0x01,
    Standard = 0x02,
    Big = 0x03,
    Jumbo = 0x04,
    Variable = 0xFF,
};

pub fn maxFrameSize(class: FrameClass) usize {
    return switch (class) {
        .Micro => 128,
        .Mini => 512,
        .Standard => 1350,
        .Big => 4096,
        .Jumbo => 9000,
        .Variable => 9000,
    };
}

pub fn maxPayloadSize(class: FrameClass) usize {
    const size = maxFrameSize(class);
    return if (size > Overhead) size - Overhead else 0;
}

pub const Header = struct {
    magic: [4]u8 = Magic,
    dest_hint: [24]u8 = .{0} ** 24,
    source_hint: [24]u8 = .{0} ** 24,
    session_id: [16]u8 = .{0} ** 16,
    sequence: u32 = 0,
    service_type: u16 = 0,
    payload_len: u16 = 0,
    frame_class: FrameClass = .Standard,
    version: u8 = 0x01,
    flags: u8 = 0,
    entropy_difficulty: u8 = 0,
    timestamp: u64 = 0,
};

pub const Trailer = struct {
    signature: [64]u8,
    checksum: u32,
};

pub const Frame = struct {
    header: Header,
    payload: []const u8,
    signature: [64]u8,
    checksum: u32,
    bytes: []u8,

    pub fn deinit(self: *Frame, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
    }
};

pub const SigningKey = struct {
    keypair: crypto.sign.Ed25519.KeyPair,
};

pub const VerifyKey = struct {
    public_key: crypto.sign.Ed25519.PublicKey,
};

pub const VerifyMode = enum {
    AllowUnsigned,
    RequireSigned,
};

pub const FlagUnsigned: u8 = 0x01;

pub fn encodeFrame(
    allocator: std.mem.Allocator,
    header_in: Header,
    payload: []const u8,
    signing: ?SigningKey,
) ![]u8 {
    var header = header_in;
    if (payload.len > maxPayloadSize(header.frame_class)) return error.PayloadTooLarge;

    header.payload_len = @intCast(payload.len);

    var header_bytes: [HeaderSize]u8 = undefined;
    encodeHeader(header, &header_bytes);

    var signature: [64]u8 = .{0} ** 64;
    if (signing) |s| {
        const msg = try allocator.alloc(u8, HeaderSize + payload.len);
        defer allocator.free(msg);
        @memcpy(msg[0..HeaderSize], &header_bytes);
        @memcpy(msg[HeaderSize..], payload);
        const sig = try s.keypair.sign(msg, null);
        signature = sig.toBytes();
    } else {
        header.flags |= FlagUnsigned;
        encodeHeader(header, &header_bytes);
    }

    const total_len = HeaderSize + payload.len + TrailerSize;
    var out = try allocator.alloc(u8, total_len);
    errdefer allocator.free(out);

    var pos: usize = 0;
    @memcpy(out[pos .. pos + HeaderSize], header_bytes[0..]);
    pos += HeaderSize;
    @memcpy(out[pos .. pos + payload.len], payload);
    pos += payload.len;
    @memcpy(out[pos .. pos + 64], signature[0..]);
    pos += 64;

    const checksum = crc32c(out[0 .. pos]);
    std.mem.writeInt(u32, out[pos..][0..4], checksum, .big);

    return out;
}

pub fn decodeFrame(
    allocator: std.mem.Allocator,
    bytes: []u8,
    verify: ?VerifyKey,
    mode: VerifyMode,
) !Frame {
    if (bytes.len < Overhead) return error.InvalidFrame;

    const header = try decodeHeader(bytes[0..HeaderSize]);
    if (!std.mem.eql(u8, &header.magic, &Magic)) return error.InvalidMagic;

    const payload_len = header.payload_len;
    const payload_len_usize: usize = @as(usize, payload_len);
    const total_len = HeaderSize + payload_len_usize + TrailerSize;
    if (bytes.len < total_len) return error.InvalidLength;

    const payload = bytes[HeaderSize .. HeaderSize + payload_len_usize];
    const sig_start = HeaderSize + payload_len_usize;
    var signature: [64]u8 = undefined;
    @memcpy(&signature, bytes[sig_start .. sig_start + 64]);
    const checksum = std.mem.readInt(u32, bytes[sig_start + 64..][0..4], .big);

    const computed = crc32c(bytes[0 .. sig_start + 64]);
    if (computed != checksum) return error.ChecksumMismatch;

    const is_unsigned = (header.flags & FlagUnsigned) != 0;
    if (mode == .RequireSigned and is_unsigned) return error.UnsignedFrame;

    if (!is_unsigned) {
        if (verify == null) return error.MissingVerifyKey;
        const msg = try allocator.alloc(u8, HeaderSize + payload.len);
        defer allocator.free(msg);
        @memcpy(msg[0..HeaderSize], bytes[0..HeaderSize]);
        @memcpy(msg[HeaderSize..], payload);
        const sig = crypto.sign.Ed25519.Signature.fromBytes(signature);
        try sig.verify(msg, verify.?.public_key);
    }

    return Frame{
        .header = header,
        .payload = payload,
        .signature = signature,
        .checksum = checksum,
        .bytes = bytes,
    };
}

pub fn encodeHeader(header: Header, out: *[HeaderSize]u8) void {
    var pos: usize = 0;
    @memcpy(out[pos .. pos + 4], &header.magic);
    pos += 4;
    @memcpy(out[pos .. pos + 24], &header.dest_hint);
    pos += 24;
    @memcpy(out[pos .. pos + 24], &header.source_hint);
    pos += 24;
    @memcpy(out[pos .. pos + 16], &header.session_id);
    pos += 16;
    std.mem.writeInt(u32, out[pos..][0..4], header.sequence, .big);
    pos += 4;
    std.mem.writeInt(u16, out[pos..][0..2], header.service_type, .big);
    pos += 2;
    std.mem.writeInt(u16, out[pos..][0..2], header.payload_len, .big);
    pos += 2;
    out[pos] = @intFromEnum(header.frame_class);
    pos += 1;
    out[pos] = header.version;
    pos += 1;
    out[pos] = header.flags;
    pos += 1;
    out[pos] = header.entropy_difficulty;
    pos += 1;
    std.mem.writeInt(u64, out[pos..][0..8], header.timestamp, .big);
}

pub fn decodeHeader(bytes: []const u8) !Header {
    if (bytes.len < HeaderSize) return error.InvalidLength;
    var header: Header = .{};
    var pos: usize = 0;
    @memcpy(&header.magic, bytes[pos..][0..4]);
    pos += 4;
    @memcpy(&header.dest_hint, bytes[pos..][0..24]);
    pos += 24;
    @memcpy(&header.source_hint, bytes[pos..][0..24]);
    pos += 24;
    @memcpy(&header.session_id, bytes[pos..][0..16]);
    pos += 16;
    header.sequence = std.mem.readInt(u32, bytes[pos..][0..4], .big);
    pos += 4;
    header.service_type = std.mem.readInt(u16, bytes[pos..][0..2], .big);
    pos += 2;
    header.payload_len = std.mem.readInt(u16, bytes[pos..][0..2], .big);
    pos += 2;
    header.frame_class = @enumFromInt(bytes[pos]);
    pos += 1;
    header.version = bytes[pos];
    pos += 1;
    header.flags = bytes[pos];
    pos += 1;
    header.entropy_difficulty = bytes[pos];
    pos += 1;
    header.timestamp = std.mem.readInt(u64, bytes[pos..][0..8], .big);
    return header;
}

pub fn readPayloadLen(header_bytes: []const u8) !u16 {
    if (header_bytes.len < HeaderSize) return error.InvalidLength;
    return std.mem.readInt(u16, header_bytes[74..][0..2], .big);
}

// CRC32C (Castagnoli) implementation
const CRC32C_POLY: u32 = 0x1EDC6F41;

var crc32c_table: [256]u32 = undefined;
var crc32c_table_initialized: bool = false;

fn crc32c(data: []const u8) u32 {
    if (!crc32c_table_initialized) initTable();
    return crc32cWithTable(data, &crc32c_table);
}

fn initTable() void {
    for (0..256) |i| {
        var crc: u32 = @as(u32, @intCast(i)) << 24;
        var j: u8 = 0;
        while (j < 8) : (j += 1) {
            if ((crc & 0x8000_0000) != 0) {
                crc = (crc << 1) ^ CRC32C_POLY;
            } else {
                crc <<= 1;
            }
        }
        crc32c_table[i] = crc;
    }
    crc32c_table_initialized = true;
}

fn crc32cWithTable(data: []const u8, table: *const [256]u32) u32 {
    var crc: u32 = 0xFFFF_FFFF;
    for (data) |b| {
        const idx = @as(u8, @intCast((crc >> 24) ^ b));
        crc = (crc << 8) ^ table[idx];
    }
    return ~crc;
}

// Tests
const testing = std.testing;

test "lwf header encode/decode" {
    var header: Header = .{};
    header.sequence = 42;
    header.service_type = 0x0A00;
    header.payload_len = 5;
    header.frame_class = .Standard;
    header.timestamp = 123456;

    var buf: [HeaderSize]u8 = undefined;
    encodeHeader(header, &buf);
    const parsed = try decodeHeader(&buf);
    try testing.expectEqual(header.sequence, parsed.sequence);
    try testing.expectEqual(header.service_type, parsed.service_type);
    try testing.expectEqual(header.payload_len, parsed.payload_len);
    try testing.expectEqual(header.frame_class, parsed.frame_class);
    try testing.expectEqual(header.timestamp, parsed.timestamp);
}
