// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Canonical encoding/decoding for query arguments and results
// Task 2.1 - Ensures deterministic query behavior

const std = @import("std");
const Allocator = std.mem.Allocator;
const Blake3 = std.crypto.hash.Blake3;
const context = @import("context.zig");

/// Canonical encoder for query arguments and results
pub const CanonicalEncoder = struct {
    allocator: Allocator,
    buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .buffer = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.de;
    }

    /// Encode query arguments to canonical binary format
    pub fn encodeArgs(self: *Self, args: context.CanonicalArgs) ![]u8 {
        self.buffer.clearRetainingCapacity();

        // Write argument count
        try self.writeU32(@intCast(args.items.len));

        // Write each argument
        for (args.items) |arg| {
            try self.encodeArg(arg);
        }

        return try self.buffer.toOwnedSlice();
    }

    /// Encode query result to canonical binary format
    pub fn encodeResult(self: *Self, result: context.QueryResultData) ![]u8 {
        self.buffer.clearRetainingCapacity();

        // Write result type tag
        try self.writeU8(@intFromEnum(result));

        // Write result data based on type
        switch (result) {
            .symbol_info => |info| try self.encodeSymbolInfo(info),
            .type_info => |info| try self.encodeTypeInfo(info),
            .dispatch_info => |info| try self.encodeDispatchInfo(info),
            .effects_info => |info| try self.encodeEffectsInfo(info),
            .definition_info => |info| try self.encodeDefinitionInfo(info),
            .hover_info => |info| try self.encodeHoverInfo(info),
            .ir_info => |info| try self.encodeIRInfo(info),
        }

        return try self.buffer.toOwnedSlice();
    }

    fn encodeArg(self: *Self, arg: context.QueryArg) !void {
        // Write argument type tag
        try self.writeU8(@intFromEnum(arg));

        switch (arg) {
            .cid => |cid| {
                // CIDs are always 32 bytes (BLAKE3)
                try self.buffer.appendSlice(&cid);
            },
            .scalar => |scalar| {
                // Scalars are encoded as little-endian i64
                try self.writeI64(scalar);
            },
            .string => |str| {
                // Strings are length-prefixed UTF-8
                if (!std.unicode.utf8ValidateSlice(str)) {
                    return error.QE0005_NonCanonicalArg;
                }
                try self.writeU32(@intCast(str.len));
                try self.buffer.appendSlice(str);
            },
        }
    }

    fn encodeSymbolInfo(self: *Self, info: context.SymbolInfo) !void {
        try self.writeString(info.name);
    }

    fn encodeTypeInfo(self: *Self, info: context.TypeInfo) !void {
        try self.writeString(info.type_name);
    }

    fn encodeDispatchInfo(self: *Self, info: context.DispatchInfo) !void {
        try self.writeString(info.selected_function);
    }

    fn encodeEffectsInfo(self: *Self, info: context.EffectsInfo) !void {
        try self.writeU32(@intCast(info.effects.len));
        for (info.effects) |effect| {
            try self.writeString(effect);
        }
    }

    fn encodeDefinitionInfo(self: *Self, info: context.DefinitionInfo) !void {
        try self.writeString(info.location);
    }

    fn encodeHoverInfo(self: *Self, info: context.HoverInfo) !void {
        try self.writeString(info.text);
    }

    fn encodeIRInfo(self: *Self, info: context.IRInfo) !void {
        try self.buffer.appendSlice(&info.ir_cid);
    }

    // Helper methods for writing primitive types
    fn writeU8(self: *Self, value: u8) !void {
        try self.buffer.append(value);
    }

    fn writeU32(self: *Self, value: u32) !void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        try self.buffer.appendSlice(&bytes);
    }

    fn writeI64(self: *Self, value: i64) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(i64, &bytes, value, .little);
        try self.buffer.appendSlice(&bytes);
    }

    fn writeString(self: *Self, str: []const u8) !void {
        try self.writeU32(@intCast(str.len));
        try self.buffer.appendSlice(str);
    }
};

/// Canonical decoder for query arguments and results
pub const CanonicalDecoder = struct {
    allocator: Allocator,
    data: []const u8,
    pos: usize,

    const Self = @This();

    pub fn init(allocator: Allocator, data: []const u8) Self {
        return Self{
            .allocator = allocator,
            .data = data,
            .pos = 0,
        };
    }

    /// Decode canonical binary format to query arguments
    pub fn decodeArgs(self: *Self) !context.CanonicalArgs {
        const arg_count = try self.readU32();
        var args = context.CanonicalArgs.init(self.allocator);

        var i: u32 = 0;
        while (i < arg_count) : (i += 1) {
            const arg = try self.decodeArg();
            try args.append(arg);
        }

        return args;
    }

    /// Decode canonical binary format to query result
    pub fn decodeResult(self: *Self) !context.QueryResultData {
        const result_type = try self.readU8();

        return switch (result_type) {
            0 => context.QueryResultData{ .symbol_info = try self.decodeSymbolInfo() },
            1 => context.QueryResultData{ .type_info = try self.decodeTypeInfo() },
            2 => context.QueryResultData{ .dispatch_info = try self.decodeDispatchInfo() },
            3 => context.QueryResultData{ .effects_info = try self.decodeEffectsInfo() },
            4 => context.QueryResultData{ .definition_info = try self.decodeDefinitionInfo() },
            5 => context.QueryResultData{ .hover_info = try self.decodeHoverInfo() },
            6 => context.QueryResultData{ .ir_info = try self.decodeIRInfo() },
            else => error.InvalidResultType,
        };
    }

    fn decodeArg(self: *Self) !context.QueryArg {
        const arg_type = try self.readU8();

        return switch (arg_type) {
            0 => blk: {
                const cid_bytes = try self.readBytes(32);
                break :blk context.QueryArg{ .cid = cid_bytes[0..32].* };
            },
            1 => context.QueryArg{ .scalar = try self.readI64() },
            2 => blk: {
                const str = try self.readString();
                break :blk context.QueryArg{ .string = str };
            },
            else => error.InvalidArgType,
        };
    }

    fn decodeSymbolInfo(self: *Self) !context.SymbolInfo {
        return context.SymbolInfo{
            .name = try self.readString(),
        };
    }

    fn decodeTypeInfo(self: *Self) !context.TypeInfo {
        return context.TypeInfo{
            .type_name = try self.readString(),
        };
    }

    fn decodeDispatchInfo(self: *Self) !context.DispatchInfo {
        return context.DispatchInfo{
            .selected_function = try self.readString(),
        };
    }

    fn decodeEffectsInfo(self: *Self) !context.EffectsInfo {
        const effect_count = try self.readU32();
        var effects = try self.allocator.alloc([]const u8, effect_count);

        for (effects) |*effect| {
            effect.* = try self.readString();
        }

        return context.EffectsInfo{ .effects = effects };
    }

    fn decodeDefinitionInfo(self: *Self) !context.DefinitionInfo {
        return context.DefinitionInfo{
            .location = try self.readString(),
        };
    }

    fn decodeHoverInfo(self: *Self) !context.HoverInfo {
        return context.HoverInfo{
            .text = try self.readString(),
        };
    }

    fn decodeIRInfo(self: *Self) !context.IRInfo {
        const cid_bytes = try self.readBytes(32);
        return context.IRInfo{
            .ir_cid = cid_bytes[0..32].*,
        };
    }

    // Helper methods for reading primitive types
    fn readU8(self: *Self) !u8 {
        if (self.pos >= self.data.len) return error.UnexpectedEndOfData;
        const value = self.data[self.pos];
        self.pos += 1;
        return value;
    }

    fn readU32(self: *Self) !u32 {
        if (self.pos + 4 > self.data.len) return error.UnexpectedEndOfData;
        const value = std.mem.readInt(u32, self.data[self.pos .. self.pos + 4][0..4], .little);
        self.pos += 4;
        return value;
    }

    fn readI64(self: *Self) !i64 {
        if (self.pos + 8 > self.data.len) return error.UnexpectedEndOfData;
        const value = std.mem.readInt(i64, self.data[self.pos .. self.pos + 8][0..8], .little);
        self.pos += 8;
        return value;
    }

    fn readBytes(self: *Self, count: usize) ![]const u8 {
        if (self.pos + count > self.data.len) return error.UnexpectedEndOfData;
        const bytes = self.data[self.pos .. self.pos + count];
        self.pos += count;
        return bytes;
    }

    fn readString(self: *Self) ![]const u8 {
        const len = try self.readU32();
        const str = try self.readBytes(len);

        // Validate UTF-8
        if (!std.unicode.utf8ValidateSlice(str)) {
            return error.InvalidUTF8;
        }

        return str;
    }
};

/// Validate that encoded data round-trips correctly
pub fn validateRoundTrip(allocator: Allocator, args: context.CanonicalArgs) !bool {
    var encoder = CanonicalEncoder.init(allocator);
    defer encoder.deinit();

    // Encode
    const encoded = try encoder.encodeArgs(args);
    defer allocator.free(encoded);

    // Decode
    var decoder = CanonicalDecoder.init(allocator, encoded);
    const decoded = try decoder.decodeArgs();
    defer decoded.deinit();

    // Compare
    if (args.items.len != decoded.items.len) return false;

    for (args.items, decoded.items) |original, roundtrip| {
        if (!argsEqual(original, roundtrip)) return false;
    }

    return true;
}

fn argsEqual(a: context.QueryArg, b: context.QueryArg) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;

    return switch (a) {
        .cid => |cid_a| std.mem.eql(u8, &cid_a, &b.cid),
        .scalar => |scalar_a| scalar_a == b.scalar,
        .string => |str_a| std.mem.eql(u8, str_a, b.string),
    };
}

/// Compute canonical hash of query arguments for memoization
pub fn computeCanonicalHash(allocator: Allocator, query_id: context.QueryId, args: context.CanonicalArgs) !context.MemoKey {
    var encoder = CanonicalEncoder.init(allocator);
    defer encoder.deinit();

    // Encode arguments to canonical form
    const encoded_args = try encoder.encodeArgs(args);
    defer allocator.free(encoded_args);

    // Hash query ID + canonical arguments
    var hasher = Blake3.init(.{});
    hasher.update(@tagName(query_id));
    hasher.update(encoded_args);

    var hash_bytes: [32]u8 = undefined;
    hasher.final(&hash_bytes);

    return context.MemoKey{ .hash = hash_bytes };
}
