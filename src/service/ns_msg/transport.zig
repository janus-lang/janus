// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! NS-Msg: Transport Layer Implementation
//!
//! Three backend implementations for message transport:
//! - MemoryTransport: RingBuffer-based, for same-process actors
//! - IPCTransport: Unix domain sockets / named pipes (stubbed for Zig 0.16)
//! - NetworkTransport: TCP with optional TLS (stubbed for Zig 0.16)

const std = @import("std");
const compat_mutex = @import("compat_mutex");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const envelope = @import("envelope.zig");
const effects = @import("effects.zig");
const lwf = @import("lwf.zig");

const Path = types.Path;
const NetworkError = effects.NetworkError;

/// Maximum buffer size for memory transport
const MEMORY_BUFFER_SIZE: usize = 64 * 1024; // 64KB

/// Maximum frame size (Jumbo)
const MAX_FRAME_SIZE: usize = lwf.maxFrameSize(.Jumbo);

/// Ring buffer for memory transport
pub const RingBuffer = struct {
    const Self = @This();

    buffer: []u8,
    head: usize,
    tail: usize,
    allocator: Allocator,
    mutex: compat_mutex.Mutex,

    pub fn init(allocator: Allocator, size: usize) !Self {
        return .{
            .buffer = try allocator.alloc(u8, size),
            .head = 0,
            .tail = 0,
            .allocator = allocator,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (data.len > self.availableWrite()) {
            return error.BufferFull;
        }

        for (data) |byte| {
            self.buffer[self.tail] = byte;
            self.tail = (self.tail + 1) % self.buffer.len;
        }

        return data.len;
    }

    pub fn read(self: *Self, dest: []u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const available = self.availableReadLocked();
        if (available == 0) return 0;

        const to_read = @min(dest.len, available);
        for (0..to_read) |i| {
            dest[i] = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
        }

        return to_read;
    }

    pub fn peek(self: *Self, dest: []u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const available = self.availableReadLocked();
        if (available == 0) return 0;

        const to_peek = @min(dest.len, available);
        var temp_head = self.head;
        for (0..to_peek) |i| {
            dest[i] = self.buffer[temp_head];
            temp_head = (temp_head + 1) % self.buffer.len;
        }

        return to_peek;
    }

    pub fn skip(self: *Self, count: usize) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const available = self.availableReadLocked();
        if (count > available) return error.InsufficientData;

        self.head = (self.head + count) % self.buffer.len;
    }

    fn availableWrite(self: Self) usize {
        return self.buffer.len - self.availableReadLocked() - 1;
    }

    pub fn availableReadLocked(self: Self) usize {
        if (self.tail >= self.head) {
            return self.tail - self.head;
        }
        return self.buffer.len - self.head + self.tail;
    }

    pub fn isEmpty(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.head == self.tail;
    }
};

/// Memory backend - for same-process actors
pub const MemoryTransport = struct {
    const Self = @This();

    buffer: RingBuffer,
    is_closed: bool,

    pub fn init(allocator: Allocator) !Self {
        return .{
            .buffer = try RingBuffer.init(allocator, MEMORY_BUFFER_SIZE),
            .is_closed = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.is_closed = true;
        self.buffer.deinit();
    }

    pub fn send(self: *Self, data: []const u8) !void {
        if (self.is_closed) return NetworkError.NotConnected;
        _ = try self.buffer.write(data);
    }

    pub fn recv(self: *Self, allocator: Allocator) !?[]u8 {
        if (self.is_closed) return NetworkError.NotConnected;

        // Peek LWF header first
        var header_bytes: [lwf.HeaderSize]u8 = undefined;
        const header_read = try self.buffer.peek(&header_bytes);
        if (header_read < lwf.HeaderSize) return null;

        if (!std.mem.eql(u8, header_bytes[0..4], lwf.Magic[0..])) return NetworkError.TransportError;
        const payload_len = try lwf.readPayloadLen(&header_bytes);
        const total_needed = lwf.HeaderSize + @as(usize, payload_len) + lwf.TrailerSize;
        if (total_needed > MAX_FRAME_SIZE) return NetworkError.TransportError;

        // Check if full frame is available
        if (self.buffer.availableReadLocked() < total_needed) return null;

        // Read full frame
        const frame = try allocator.alloc(u8, total_needed);
        errdefer allocator.free(frame);

        const read_len = try self.buffer.read(frame);
        if (read_len != total_needed) {
            allocator.free(frame);
            return NetworkError.TransportError;
        }

        return frame;
    }

    pub fn close(self: *Self) void {
        self.is_closed = true;
    }
};

/// IPC backend - Unix domain sockets (stubbed for Zig 0.16)
pub const IPCTransport = struct {
    const Self = @This();

    socket_path: []const u8,
    allocator: Allocator,
    is_server: bool,
    is_closed: bool,

    pub fn init(allocator: Allocator, path: []const u8) !Self {
        return .{
            .socket_path = try allocator.dupe(u8, path),
            .allocator = allocator,
            .is_server = false,
            .is_closed = false,
        };
    }

    pub fn initServer(allocator: Allocator, path: []const u8) !Self {
        _ = allocator;
        _ = path;
        return error.NotImplemented;
    }

    pub fn connect(self: *Self) !void {
        _ = self;
        return error.NotImplemented;
    }

    pub fn deinit(self: *Self) void {
        self.close();
        self.allocator.free(self.socket_path);
    }

    pub fn accept(self: *Self) !i32 {
        _ = self;
        return error.NotImplemented;
    }

    pub fn send(self: *Self, data: []const u8) !void {
        _ = data;
        if (self.is_closed) return NetworkError.NotConnected;
        return error.NotImplemented;
    }

    pub fn recv(self: *Self, allocator: Allocator) !?[]u8 {
        _ = allocator;
        if (self.is_closed) return NetworkError.NotConnected;
        return error.NotImplemented;
    }

    pub fn close(self: *Self) void {
        self.is_closed = true;
    }
};

/// Address type for network transport (stubbed)
pub const Address = struct {
    host: []const u8,
    port: u16,

    pub fn init(host: []const u8, port: u16) Address {
        return .{ .host = host, .port = port };
    }
};

/// Network backend - TCP with optional TLS (stubbed for Zig 0.16)
pub const NetworkTransport = struct {
    const Self = @This();

    endpoint: Address,
    is_server: bool,
    is_closed: bool,
    use_tls: bool,

    pub fn init(addr: Address) Self {
        return .{
            .endpoint = addr,
            .is_server = false,
            .is_closed = false,
            .use_tls = false,
        };
    }

    pub fn initServer(addr: Address) !Self {
        _ = addr;
        return error.NotImplemented;
    }

    pub fn connect(self: *Self) !void {
        _ = self;
        return error.NotImplemented;
    }

    pub fn deinit(self: *Self) void {
        self.close();
    }

    pub fn accept(self: *Self) !i32 {
        _ = self;
        return error.NotImplemented;
    }

    pub fn send(self: *Self, data: []const u8) !void {
        _ = data;
        if (self.is_closed) return NetworkError.NotConnected;
        return error.NotImplemented;
    }

    pub fn recv(self: *Self, allocator: Allocator) !?[]u8 {
        _ = allocator;
        if (self.is_closed) return NetworkError.NotConnected;
        return error.NotImplemented;
    }

    pub fn close(self: *Self) void {
        self.is_closed = true;
    }

    pub fn enableTLS(self: *Self, tls: bool) void {
        self.use_tls = tls;
    }
};

/// Generic transport interface
pub const Transport = union(enum) {
    const Self = @This();

    memory: *MemoryTransport,
    ipc: *IPCTransport,
    network: *NetworkTransport,

    /// Send raw data through the transport
    pub fn send(self: *Self, data: []const u8) !void {
        switch (self.*) {
            .memory => |t| try t.send(data),
            .ipc => |t| try t.send(data),
            .network => |t| try t.send(data),
        }
    }

    /// Receive raw data from the transport
    pub fn recv(self: *Self, allocator: Allocator) !?[]u8 {
        return switch (self.*) {
            .memory => |t| try t.recv(allocator),
            .ipc => |t| try t.recv(allocator),
            .network => |t| try t.recv(allocator),
        };
    }

    /// Close the transport
    pub fn close(self: *Self) void {
        switch (self.*) {
            .memory => |t| t.close(),
            .ipc => |t| t.close(),
            .network => |t| t.close(),
        }
    }

    /// Check if transport is closed
    pub fn isClosed(self: Self) bool {
        return switch (self) {
            .memory => |t| t.is_closed,
            .ipc => |t| t.is_closed,
            .network => |t| t.is_closed,
        };
    }

    /// Network transports require signed frames.
    pub fn requiresSignature(self: Self) bool {
        return switch (self) {
            .network => true,
            else => false,
        };
    }
};

// Tests
const testing = std.testing;

test "RingBuffer basic operations" {
    const allocator = testing.allocator;

    var rb = try RingBuffer.init(allocator, 256);
    defer rb.deinit();

    const data = "Hello, World!";
    _ = try rb.write(data);

    var dest: [64]u8 = undefined;
    const read_len = try rb.read(&dest);

    try testing.expectEqual(data.len, read_len);
    try testing.expectEqualStrings(data, dest[0..read_len]);
}

test "MemoryTransport send and receive" {
    const allocator = testing.allocator;

    var transport = try MemoryTransport.init(allocator);
    defer transport.deinit();

    const payload = "Test message payload";
    const header: lwf.Header = .{ .service_type = 0xFF00, .frame_class = .Standard };
    const frame = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame);

    try transport.send(frame);

    const received = try transport.recv(allocator);
    try testing.expect(received != null);

    if (received) |data| {
        var parsed = try lwf.decodeFrame(allocator, data, null, .AllowUnsigned);
        defer parsed.deinit(allocator);
        try testing.expectEqualStrings(payload, parsed.payload);
    }
}

test "Transport union dispatch" {
    const allocator = testing.allocator;

    var mem_transport = try MemoryTransport.init(allocator);
    defer mem_transport.deinit();

    var transport = Transport{ .memory = &mem_transport };

    const payload = "Test via union";
    const header: lwf.Header = .{ .service_type = 0xFF00, .frame_class = .Standard };
    const frame = try lwf.encodeFrame(allocator, header, payload, null);
    defer allocator.free(frame);

    try transport.send(frame);

    const received = try transport.recv(allocator);
    try testing.expect(received != null);

    if (received) |msg| {
        var parsed = try lwf.decodeFrame(allocator, msg, null, .AllowUnsigned);
        defer parsed.deinit(allocator);
        try testing.expectEqualStrings(payload, parsed.payload);
    }
}
