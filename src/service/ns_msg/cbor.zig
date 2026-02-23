// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Minimal CBOR encoder/decoder for Libertaria payloads.
//!
//! Scope: RFC-8949 subset
//! - Major types 0-5 (uint, nint, bstr, tstr, array, map)
//! - Major type 7 (bool, null, float16/32/64)
//! - Tags (major type 6)
//! - No indefinite-length items

const std = @import("std");

pub const Error = error{
    InvalidType,
    InvalidLength,
    InvalidValue,
    UnexpectedEof,
    UnsupportedType,
    UnsupportedIndefinite,
    UnknownField,
    MissingField,
    TagMismatch,
};

pub const Bytes = struct {
    data: []const u8,
};

pub const Text = struct {
    data: []const u8,
};

pub fn Tagged(comptime T: type) type {
    return struct {
        tag: u64,
        value: T,
    };
}

const Major = enum(u3) {
    uint = 0,
    nint = 1,
    bstr = 2,
    tstr = 3,
    array = 4,
    map = 5,
    tag = 6,
    simple = 7,
};

const Simple = struct {
    pub const false_val: u8 = 20;
    pub const true_val: u8 = 21;
    pub const null_val: u8 = 22;
    pub const float16: u8 = 25;
    pub const float32: u8 = 26;
    pub const float64: u8 = 27;
};

pub fn encode(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    try encodeValue(&out, value);
    return out.toOwnedSlice(allocator);
}

pub fn decode(comptime T: type, allocator: std.mem.Allocator, data: []const u8) !T {
    var reader = Reader{ .data = data, .pos = 0 };
    const result = try decodeValue(T, allocator, &reader);
    if (reader.pos != data.len) return Error.InvalidLength;
    return result;
}

fn encodeValue(out: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .Bool => {
            try writeSimple(out, if (value) Simple.true_val else Simple.false_val);
        },
        .Int => {
            if (value >= 0) {
                try writeUnsigned(out, @intCast(value));
            } else {
                const n = @as(i64, value);
                try writeNegative(out, n);
            }
        },
        .ComptimeInt => {
            if (value >= 0) {
                try writeUnsigned(out, @intCast(value));
            } else {
                const n = @as(i64, value);
                try writeNegative(out, n);
            }
        },
        .Float => {
            try writeFloat(out, value);
        },
        .Optional => {
            if (value) |v| {
                try encodeValue(out, v);
            } else {
                try writeSimple(out, Simple.null_val);
            }
        },
        .Array => |arr| {
            if (arr.child == u8) {
                try writeText(out, value[0..]);
            } else {
                try writeArray(out, arr.len);
                for (value) |elem| try encodeValue(out, elem);
            }
        },
        .Pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                try writeText(out, value);
                return;
            }
            if (ptr.size == .Slice) {
                try writeArray(out, value.len);
                for (value) |elem| try encodeValue(out, elem);
                return;
            }
            return Error.UnsupportedType;
        },
        .Struct => |sinfo| {
            if (isTaggedType(T, sinfo)) {
                const tag_val: u64 = value.tag;
                try writeTag(out, tag_val);
                try encodeValue(out, value.value);
                return;
            }
            if (T == Bytes) {
                try writeBytes(out, value.data);
                return;
            }
            if (T == Text) {
                try writeText(out, value.data);
                return;
            }

            try writeMap(out, sinfo.fields.len);
            inline for (sinfo.fields) |field| {
                try writeText(out, field.name);
                try encodeValue(out, @field(value, field.name));
            }
        },
        else => return Error.UnsupportedType,
    }
}

fn decodeValue(comptime T: type, allocator: std.mem.Allocator, reader: *Reader) !T {
    const info = @typeInfo(T);

    switch (info) {
        .Bool => return try readBool(reader),
        .Int => return try readInt(T, reader),
        .ComptimeInt => return try readInt(i64, reader),
        .Float => return try readFloat(T, reader),
        .Optional => |opt| {
            if (try peekIsNull(reader)) {
                _ = try readNull(reader);
                return null;
            }
            const v = try decodeValue(opt.child, allocator, reader);
            return v;
        },
        .Array => |arr| {
            if (arr.child == u8) {
                const text = try readText(reader, allocator);
                if (text.len != arr.len) return Error.InvalidLength;
                var out: T = undefined;
                @memcpy(out[0..], text);
                allocator.free(text);
                return out;
            }
            const len = try readArrayLen(reader);
            if (len != arr.len) return Error.InvalidLength;
            var out: T = undefined;
            var i: usize = 0;
            while (i < arr.len) : (i += 1) {
                out[i] = try decodeValue(arr.child, allocator, reader);
            }
            return out;
        },
        .Pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                return try readText(reader, allocator);
            }
            if (ptr.size == .Slice) {
                const len = try readArrayLen(reader);
                var list = try allocator.alloc(ptr.child, len);
                errdefer allocator.free(list);
                for (0..len) |i| {
                    list[i] = try decodeValue(ptr.child, allocator, reader);
                }
                return list;
            }
            return Error.UnsupportedType;
        },
        .Struct => |sinfo| {
            if (isTaggedType(T, sinfo)) {
                const tag_val = try readTag(reader);
                var out: T = undefined;
                out.tag = tag_val;
                out.value = try decodeValue(sinfo.fields[1].type, allocator, reader);
                return out;
            }
            if (T == Bytes) {
                const bytes = try readBytes(reader, allocator);
                return Bytes{ .data = bytes };
            }
            if (T == Text) {
                const text = try readText(reader, allocator);
                return Text{ .data = text };
            }

            const map_len = try readMapLen(reader);
            var out: T = std.mem.zeroes(T);
            var seen: [sinfo.fields.len]bool = .{false} ** sinfo.fields.len;

            var i: usize = 0;
            while (i < map_len) : (i += 1) {
                const key = try readText(reader, allocator);
                defer allocator.free(key);

                var matched = false;
                inline for (sinfo.fields, 0..) |field, fi| {
                    if (std.mem.eql(u8, key, field.name)) {
                        @field(out, field.name) = try decodeValue(field.type, allocator, reader);
                        seen[fi] = true;
                        matched = true;
                        break;
                    }
                }

                if (!matched) {
                    try skipValue(reader, allocator);
                }
            }

            inline for (sinfo.fields, 0..) |field, fi| {
                if (!seen[fi]) {
                    const finfo = @typeInfo(field.type);
                    if (finfo == .Optional) continue;
                    return Error.MissingField;
                }
            }

            return out;
        },
        else => return Error.UnsupportedType,
    }
}

fn isTaggedType(comptime T: type, sinfo: std.builtin.Type.Struct) bool {
    if (sinfo.fields.len != 2) return false;
    if (!std.mem.eql(u8, sinfo.fields[0].name, "tag")) return false;
    if (!std.mem.eql(u8, sinfo.fields[1].name, "value")) return false;
    if (@typeInfo(sinfo.fields[0].type) != .Int) return false;
    return true;
}

const Reader = struct {
    data: []const u8,
    pos: usize,

    fn readByte(self: *Reader) !u8 {
        if (self.pos >= self.data.len) return Error.UnexpectedEof;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readBytes(self: *Reader, n: usize) ![]const u8 {
        if (self.pos + n > self.data.len) return Error.UnexpectedEof;
        const slice = self.data[self.pos .. self.pos + n];
        self.pos += n;
        return slice;
    }
};

fn writeTypeAndLen(out: *std.ArrayList(u8), major: Major, len: u64) !void {
    if (len < 24) {
        try out.append(@as(u8, (@intFromEnum(major) << 5) | @intCast(len)));
    } else if (len <= 0xFF) {
        try out.append(@as(u8, (@intFromEnum(major) << 5) | 24));
        try out.append(@intCast(len));
    } else if (len <= 0xFFFF) {
        try out.append(@as(u8, (@intFromEnum(major) << 5) | 25));
        var buf: [2]u8 = undefined;
        std.mem.writeIntBig(u16, &buf, @intCast(len));
        try out.appendSlice(&buf);
    } else if (len <= 0xFFFF_FFFF) {
        try out.append(@as(u8, (@intFromEnum(major) << 5) | 26));
        var buf: [4]u8 = undefined;
        std.mem.writeIntBig(u32, &buf, @intCast(len));
        try out.appendSlice(&buf);
    } else {
        try out.append(@as(u8, (@intFromEnum(major) << 5) | 27));
        var buf: [8]u8 = undefined;
        std.mem.writeIntBig(u64, &buf, len);
        try out.appendSlice(&buf);
    }
}

fn writeUnsigned(out: *std.ArrayList(u8), v: u64) !void {
    try writeTypeAndLen(out, .uint, v);
}

fn writeNegative(out: *std.ArrayList(u8), v: i64) !void {
    if (v >= 0) return Error.InvalidValue;
    const n = @as(u64, @intCast(-1 - v));
    try writeTypeAndLen(out, .nint, n);
}

fn writeBytes(out: *std.ArrayList(u8), bytes: []const u8) !void {
    try writeTypeAndLen(out, .bstr, bytes.len);
    try out.appendSlice(bytes);
}

fn writeText(out: *std.ArrayList(u8), text: []const u8) !void {
    try writeTypeAndLen(out, .tstr, text.len);
    try out.appendSlice(text);
}

fn writeArray(out: *std.ArrayList(u8), len: usize) !void {
    try writeTypeAndLen(out, .array, len);
}

fn writeMap(out: *std.ArrayList(u8), len: usize) !void {
    try writeTypeAndLen(out, .map, len);
}

fn writeTag(out: *std.ArrayList(u8), tag: u64) !void {
    try writeTypeAndLen(out, .tag, tag);
}

fn writeSimple(out: *std.ArrayList(u8), simple: u8) !void {
    try out.append(@as(u8, (@intFromEnum(Major.simple) << 5) | simple));
}

fn writeFloat(out: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    switch (T) {
        f16 => {
            try out.append(@as(u8, (@intFromEnum(Major.simple) << 5) | Simple.float16));
            var buf: [2]u8 = undefined;
            std.mem.writeIntBig(u16, &buf, @bitCast(value));
            try out.appendSlice(&buf);
        },
        f32 => {
            try out.append(@as(u8, (@intFromEnum(Major.simple) << 5) | Simple.float32));
            var buf: [4]u8 = undefined;
            std.mem.writeIntBig(u32, &buf, @bitCast(value));
            try out.appendSlice(&buf);
        },
        f64 => {
            try out.append(@as(u8, (@intFromEnum(Major.simple) << 5) | Simple.float64));
            var buf: [8]u8 = undefined;
            std.mem.writeIntBig(u64, &buf, @bitCast(value));
            try out.appendSlice(&buf);
        },
        else => return Error.UnsupportedType,
    }
}

fn readTypeAndLen(reader: *Reader) !struct { major: Major, len: u64 } {
    const b = try reader.readByte();
    const major: Major = @enumFromInt(b >> 5);
    const ai: u5 = @intCast(b & 0x1f);
    if (ai < 24) return .{ .major = major, .len = ai };
    switch (ai) {
        24 => return .{ .major = major, .len = try readIntSized(reader, u8) },
        25 => return .{ .major = major, .len = try readIntSized(reader, u16) },
        26 => return .{ .major = major, .len = try readIntSized(reader, u32) },
        27 => return .{ .major = major, .len = try readIntSized(reader, u64) },
        else => return Error.UnsupportedIndefinite,
    }
}

fn readIntSized(reader: *Reader, comptime T: type) !u64 {
    const nbytes = @sizeOf(T);
    const bytes = try reader.readBytes(nbytes);
    const v = std.mem.readIntBig(T, bytes);
    return @as(u64, @intCast(v));
}

fn readUnsigned(reader: *Reader) !u64 {
    const tl = try readTypeAndLen(reader);
    if (tl.major != .uint) return Error.InvalidType;
    return tl.len;
}

fn readNegative(reader: *Reader) !i64 {
    const tl = try readTypeAndLen(reader);
    if (tl.major != .nint) return Error.InvalidType;
    const n = tl.len;
    return -1 - @as(i64, @intCast(n));
}

fn readBool(reader: *Reader) !bool {
    const b = try reader.readByte();
    if (b == (@as(u8, (@intFromEnum(Major.simple) << 5) | Simple.false_val))) return false;
    if (b == (@as(u8, (@intFromEnum(Major.simple) << 5) | Simple.true_val))) return true;
    return Error.InvalidType;
}

fn readNull(reader: *Reader) !void {
    const b = try reader.readByte();
    if (b != (@as(u8, (@intFromEnum(Major.simple) << 5) | Simple.null_val))) return Error.InvalidType;
}

fn peekIsNull(reader: *Reader) !bool {
    if (reader.pos >= reader.data.len) return Error.UnexpectedEof;
    const b = reader.data[reader.pos];
    return b == (@as(u8, (@intFromEnum(Major.simple) << 5) | Simple.null_val));
}

fn readFloat(comptime T: type, reader: *Reader) !T {
    const b = try reader.readByte();
    const major = b >> 5;
    const ai: u5 = @intCast(b & 0x1f);
    if (major != @intFromEnum(Major.simple)) return Error.InvalidType;
    switch (ai) {
        Simple.float16 => {
            const raw = @as(u16, @intCast(try readIntSized(reader, u16)));
            return @as(T, @floatCast(@as(f16, @bitCast(raw))));
        },
        Simple.float32 => {
            const raw = @as(u32, @intCast(try readIntSized(reader, u32)));
            return @as(T, @floatCast(@as(f32, @bitCast(raw))));
        },
        Simple.float64 => {
            const raw = @as(u64, @intCast(try readIntSized(reader, u64)));
            return @as(T, @floatCast(@as(f64, @bitCast(raw))));
        },
        else => return Error.InvalidType,
    }
}

fn readText(reader: *Reader, allocator: std.mem.Allocator) ![]u8 {
    const tl = try readTypeAndLen(reader);
    if (tl.major != .tstr) return Error.InvalidType;
    const bytes = try reader.readBytes(@intCast(tl.len));
    return try allocator.dupe(u8, bytes);
}

fn readBytes(reader: *Reader, allocator: std.mem.Allocator) ![]u8 {
    const tl = try readTypeAndLen(reader);
    if (tl.major != .bstr) return Error.InvalidType;
    const bytes = try reader.readBytes(@intCast(tl.len));
    return try allocator.dupe(u8, bytes);
}

fn readArrayLen(reader: *Reader) !usize {
    const tl = try readTypeAndLen(reader);
    if (tl.major != .array) return Error.InvalidType;
    return @intCast(tl.len);
}

fn readMapLen(reader: *Reader) !usize {
    const tl = try readTypeAndLen(reader);
    if (tl.major != .map) return Error.InvalidType;
    return @intCast(tl.len);
}

fn readTag(reader: *Reader) !u64 {
    const tl = try readTypeAndLen(reader);
    if (tl.major != .tag) return Error.InvalidType;
    return tl.len;
}

fn readInt(comptime T: type, reader: *Reader) !T {
    if (reader.pos >= reader.data.len) return Error.UnexpectedEof;
    const b = reader.data[reader.pos];
    const major: Major = @enumFromInt(b >> 5);
    if (major == .uint) {
        const u = try readUnsigned(reader);
        return @as(T, @intCast(u));
    }
    if (major == .nint) {
        const n = try readNegative(reader);
        return @as(T, @intCast(n));
    }
    return Error.InvalidType;
}

fn skipValue(reader: *Reader, allocator: std.mem.Allocator) !void {
    const tl = try readTypeAndLen(reader);
    switch (tl.major) {
        .uint, .nint => return,
        .bstr, .tstr => {
            _ = try reader.readBytes(@intCast(tl.len));
        },
        .array => {
            var i: usize = 0;
            while (i < tl.len) : (i += 1) {
                try skipValue(reader, allocator);
            }
        },
        .map => {
            var i: usize = 0;
            while (i < tl.len) : (i += 1) {
                try skipValue(reader, allocator);
                try skipValue(reader, allocator);
            }
        },
        .tag => {
            try skipValue(reader, allocator);
        },
        .simple => {
            const ai: u5 = @intCast(reader.data[reader.pos - 1] & 0x1f);
            switch (ai) {
                Simple.false_val, Simple.true_val, Simple.null_val => return,
                Simple.float16 => _ = try reader.readBytes(2),
                Simple.float32 => _ = try reader.readBytes(4),
                Simple.float64 => _ = try reader.readBytes(8),
                else => return Error.InvalidType,
            }
        },
    }
}

// Tests
const testing = std.testing;

test "cbor encode/decode basic types" {
    const allocator = testing.allocator;

    const encoded_u = try encode(allocator, @as(u64, 42));
    defer allocator.free(encoded_u);
    const decoded_u = try decode(u64, allocator, encoded_u);
    try testing.expectEqual(@as(u64, 42), decoded_u);

    const encoded_i = try encode(allocator, @as(i64, -5));
    defer allocator.free(encoded_i);
    const decoded_i = try decode(i64, allocator, encoded_i);
    try testing.expectEqual(@as(i64, -5), decoded_i);

    const encoded_b = try encode(allocator, true);
    defer allocator.free(encoded_b);
    const decoded_b = try decode(bool, allocator, encoded_b);
    try testing.expectEqual(true, decoded_b);

    const encoded_s = try encode(allocator, "hello");
    defer allocator.free(encoded_s);
    const decoded_s = try decode([]u8, allocator, encoded_s);
    defer allocator.free(decoded_s);
    try testing.expectEqualStrings("hello", decoded_s);
}

test "cbor encode/decode struct" {
    const allocator = testing.allocator;

    const Obj = struct {
        a: u64,
        b: bool,
        c: []const u8,
    };

    const obj = Obj{ .a = 7, .b = true, .c = "hi" };
    const encoded = try encode(allocator, obj);
    defer allocator.free(encoded);

    const decoded = try decode(Obj, allocator, encoded);
    defer allocator.free(decoded.c);
    try testing.expectEqual(@as(u64, 7), decoded.a);
    try testing.expectEqual(true, decoded.b);
    try testing.expectEqualStrings("hi", decoded.c);
}
