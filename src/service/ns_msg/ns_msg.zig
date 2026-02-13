// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! NS-Msg: Main API Facade
//! Ties Router + Transport + Envelope serialization for pub/sub

const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("types.zig");
const router = @import("router.zig");
const transport = @import("transport.zig");
const envelope = @import("envelope.zig");
const lwf = @import("lwf.zig");
const cbor = @import("cbor.zig");

const Path = types.Path;
const Transport = transport.Transport;
const Router = router.Router;
const SensorReading = envelope.SensorReading;

pub const NoRoute = error{NoRoute};
pub const MissingSignature = error{MissingSignature};

pub const NsMsg = struct {
    const Self = @This();

    allocator: Allocator,
    router: Router,
    next_sequence: u32,

    pub fn init(allocator: Allocator) !Self {
        return .{
            .allocator = allocator,
            .router = Router.init(allocator),
            .next_sequence = 1,
        };
    }

    pub fn deinit(self: *Self) void {
        self.router.deinit();
    }

    pub fn addLocalRoute(self: *Self, pattern: []const u8, trans: *Transport) !void {
        try self.router.addLocalRoute(pattern, trans);
    }

    pub fn route(self: *Self, path_str: []const u8) !?*Transport {
        var path = try Path.parse(self.allocator, path_str);
        defer path.deinit();
        return self.router.route(path);
    }

    pub const FrameMeta = struct {
        dest_hint: [24]u8 = .{0} ** 24,
        source_hint: [24]u8 = .{0} ** 24,
        session_id: [16]u8 = .{0} ** 16,
        flags: u8 = 0,
        entropy_difficulty: u8 = 0,
        timestamp: u64 = 0,
        frame_class: lwf.FrameClass = .Standard,
    };

    /// Publish typed payload to path using LWF framing and CBOR payload.
    /// The caller supplies the service_type according to protocol registry.
    pub fn publish(
        self: *Self,
        path_str: []const u8,
        service_type: u16,
        meta: FrameMeta,
        payload: anytype,
        signing: ?lwf.SigningKey,
    ) !void {
        var path = try Path.parse(self.allocator, path_str);
        defer path.deinit();

        const maybe_trans = self.router.route(path);
        if (maybe_trans == null) return NoRoute.NoRoute;
        const trans = maybe_trans.?;

        if (trans.requiresSignature() and signing == null) return MissingSignature;

        const payload_bytes = try cbor.encode(self.allocator, payload);
        defer self.allocator.free(payload_bytes);

        var header: lwf.Header = .{
            .dest_hint = meta.dest_hint,
            .source_hint = meta.source_hint,
            .session_id = meta.session_id,
            .sequence = self.next_sequence,
            .service_type = service_type,
            .payload_len = @intCast(payload_bytes.len),
            .frame_class = meta.frame_class,
            .version = 0x01,
            .flags = meta.flags,
            .entropy_difficulty = meta.entropy_difficulty,
            .timestamp = if (meta.timestamp == 0) @intCast(std.time.nanoTimestamp()) else meta.timestamp,
        };

        self.next_sequence +%= 1;

        const frame_bytes = try lwf.encodeFrame(self.allocator, header, payload_bytes, signing);
        defer self.allocator.free(frame_bytes);

        try trans.send(frame_bytes);
    }

    /// Receive a raw LWF frame from transport.
    pub fn recvFrame(
        self: *Self,
        trans: *Transport,
        verify: ?lwf.VerifyKey,
    ) !?lwf.Frame {
        _ = self;
        const frame_bytes = try trans.recv(self.allocator) orelse return null;

        const mode: lwf.VerifyMode = if (trans.requiresSignature()) .RequireSigned else .AllowUnsigned;
        const frame = try lwf.decodeFrame(self.allocator, frame_bytes, verify, mode);
        return frame;
    }

    /// Receive and decode a CBOR payload from a frame.
    pub fn recvPayload(
        self: *Self,
        trans: *Transport,
        verify: ?lwf.VerifyKey,
        comptime T: type,
    ) !?struct { header: lwf.Header, payload: T } {
        var frame = try self.recvFrame(trans, verify) orelse return null;
        defer frame.deinit(self.allocator);

        const payload = try cbor.decode(T, self.allocator, frame.payload);
        return .{ .header = frame.header, .payload = payload };
    }

    /// Publish sensor reading to path (compat helper).
    pub fn publishSensor(
        self: *Self,
        path_str: []const u8,
        service_type: u16,
        meta: FrameMeta,
        reading: SensorReading,
        signing: ?lwf.SigningKey,
    ) !void {
        try self.publish(path_str, service_type, meta, reading, signing);
    }

    /// Receive sensor reading from transport (compat helper).
    pub fn recvSensor(
        self: *Self,
        trans: *Transport,
        verify: ?lwf.VerifyKey,
    ) !?SensorReading {
        const result = try self.recvPayload(trans, verify, SensorReading) orelse return null;
        return result.payload;
    }
};
