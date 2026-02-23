// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Production-Grade Socket Abstraction
//! Platform-agnostic networking layer with tri-signature pattern

const std = @import("std");
const builtin = @import("builtin");
const Context = @import("../std_context.zig").Context;
const Capability = @import("../capabilities.zig");

/// Socket handle abstraction across platforms
const SocketHandle = switch (builtin.os.tag) {
    .linux, .macos => std.posix.socket_t,
    .windows => std.os.windows.ws2_32.SOCKET,
    else => @compileError("Unsupported platform for socket implementation"),
};

/// Socket errors with detailed context
pub const SocketError = error{
    /// Network-level errors
    NetworkUnreachable,
    ConnectionRefused,
    ConnectionReset,
    ConnectionAborted,
    Timeout,

    /// System-level errors
    AddressInUse,
    AddressNotAvailable,
    PermissionDenied,
    ResourceExhausted,

    /// Protocol-level errors
    InvalidAddress,
    InvalidPort,
    Protocold,

    /// Capability-level errors
    CapabilityDenied,
    InsufficientPermissions,

    /// Generic errors
    SystemError,
    UnexpectedError,
};

/// Socket address abstraction
pub const SocketAddress = struct {
    family: AddressFamily,
    data: AddressData,

    const AddressFamily = enum {
        ipv4,
        ipv6,
        unix,
    };

    const AddressData = union(AddressFamily) {
        ipv4: struct {
            addr: [4]u8,
            port: u16,
        },
        ipv6: struct {
            addr: [16]u8,
            port: u16,
            flowinfo: u32,
            scope_id: u32,
        },
        unix: struct {
            path: []const u8,
        },
    };

    /// Parse address from string representation
    pub fn parse(addr_str: []const u8, allocator: std.mem.Allocator) SocketError!SocketAddress {
        _ = allocator;

        // Simple IPv4 parsing for initial implementation
        if (std.mem.startsWith(u8, addr_str, ":")) {
            // Port-only format ":8080"
            const port_str = addr_str[1..];
            const port = std.fmt.parseInt(u16, port_str, 10) catch return SocketError.InvalidPort;

            return SocketAddress{
                .family = .ipv4,
                .data = .{
                    .ipv4 = .{
                        .addr = [4]u8{ 0, 0, 0, 0 }, // INADDR_ANY
                        .port = port,
                    },
                },
            };
        }

        // TODO: Implement full address parsing (IPv4, IPv6, Unix sockets)
        return SocketError.InvalidAddress;
    }

    /// Convert to platform-specific sockaddr
    pub fn to_sockaddr(self: SocketAddress, allocator: std.mem.Allocator) SocketError![]u8 {
        _ = allocator;

        switch (self.data) {
            .ipv4 => |ipv4| {
                // Create sockaddr_in structure
                var sockaddr = std.mem.zeroes([16]u8); // sizeof(sockaddr_in)

                // Set address family (AF_INET = 2)
                sockaddr[0] = 2;
                sockaddr[1] = 0;

                // Set port (network byte order)
                const port_be = std.mem.nativeToBig(u16, ipv4.port);
                std.mem.copy(u8, sockaddr[2..4], std.mem.asBytes(&port_be));

                // Set IP address
                std.mem.copy(u8, sockaddr[4..8], &ipv4.addr);

                return sockaddr[0..16];
            },
            else => return SocketError.ProtocolNotSupported,
        }
    }
};

/// Production-grade socket with tri-signature pattern
pub const Socket = struct {
    handle: SocketHandle,
    address: SocketAddress,
    allocator: std.mem.Allocator,
    is_listening: bool,

    const Self = @This();

    // =============================================================================
    // TRI-SIGNATURE PATTERN: Socket creation across profiles
    // =============================================================================

    /// :min profile - Simple socket creation
    /// Available in: min, go, full
    pub fn listen_min(address: SocketAddress, allocator: std.mem.Allocator) SocketError!Socket {
        return create_socket(address, allocator, null, null);
    }

    /// :go profile - Context-aware socket creation
    /// Available in: go, full
    pub fn listen_go(address: SocketAddress, ctx: Context, allocator: std.mem.Allocator) SocketError!Socket {
        if (ctx.is_cancelled()) return SocketError.Timeout;
        return create_socket(address, allocator, ctx, null);
    }

    /// :full profile - Capability-gated socket creation
    /// Available in: full only
    pub fn listen_full(address: SocketAddress, cap: Capability.NetBind, allocator: std.mem.Allocator) SocketError!Socket {
        // Validate capability before creating socket
        if (!cap.allows_bind_address(address)) {
            return SocketError.CapabilityDenied;
        }

        return create_socket(address, allocator, null, cap);
    }

    /// Internal socket creation implementation
    fn create_socket(address: SocketAddress, allocator: std.mem.Allocator, ctx: ?Context, cap: ?Capability.NetBind) SocketError!Socket {
        _ = ctx; // TODO: Use context for timeout/cancellation
        _ = cap; // TODO: Use capability for audit logging

        // Create socket based on address family
        const domain = switch (address.family) {
            .ipv4 => std.posix.AF.INET,
            .ipv6 => std.posix.AF.INET6,
            .unix => std.posix.AF.UNIX,
        };

        const socket_type = std.posix.SOCK.STREAM;
        const protocol = std.posix.IPPROTO.TCP;

        // Create the socket
        const handle = std.posix.socket(domain, socket_type, protocol) catch |err| switch (err) {
            error.AddressFamilyNotSupported => return SocketError.ProtocolNotSupported,
            error.ProtocolNotSupported => return SocketError.ProtocolNotSupported,
            error.PermissionDenied => return SocketError.PermissionDenied,
            error.ProcessFdQuotaExceeded => return SocketError.ResourceExhausted,
            error.SystemFdQuotaExceeded => return SocketError.ResourceExhausted,
            error.SystemResources => return SocketError.ResourceExhausted,
            else => return SocketError.SystemError,
        };

        // Set socket options
        try set_socket_options(handle);

        // Bind to address
        const sockaddr = try address.to_sockaddr(allocator);
        defer allocator.free(sockaddr);

        std.posix.bind(handle, @ptrCast(sockaddr.ptr), @intCast(sockaddr.len)) catch |err| switch (err) {
            error.AddressInUse => return SocketError.AddressInUse,
            error.AddressNotAvailable => return SocketError.AddressNotAvailable,
            error.PermissionDenied => return SocketError.PermissionDenied,
            else => return SocketError.SystemError,
        };

        // Start listening
        std.posix.listen(handle, 128) catch |err| switch (err) {
            error.SocketNotBound => return SocketError.SystemError,
            error.OperationNotSupported => return SocketError.ProtocolNotSupported,
            else => return SocketError.SystemError,
        };

        return Socket{
            .handle = handle,
            .address = address,
            .allocator = allocator,
            .is_listening = true,
        };
    }

    /// Set production-grade socket options
    fn set_socket_options(handle: SocketHandle) SocketError!void {
        // Enable address reuse
        const reuse_addr: c_int = 1;
        std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&reuse_addr)) catch return SocketError.SystemError;

        // Set TCP_NODELAY for low latency
        const no_delay: c_int = 1;
        std.posix.setsockopt(handle, std.posix.IPPROTO.TCP, std.posix.TCP.NODELAY, std.mem.asBytes(&no_delay)) catch return SocketError.SystemError;

        // TODO: Add more production options (keep-alive, buffer sizes, etc.)
    }

    /// Accept incoming connection
    pub fn accept(self: *Socket) SocketError!Connection {
        if (!self.is_listening) return SocketError.SystemError;

        var client_addr: std.posix.sockaddr = undefined;
        var client_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

        const client_handle = std.posix.accept(self.handle, &client_addr, &client_addr_len, 0) catch |err| switch (err) {
            error.WouldBlock => return SocketError.Timeout,
            error.ConnectionAborted => return SocketError.ConnectionAborted,
            error.ProcessFdQuotaExceeded => return SocketError.ResourceExhausted,
            error.SystemFdQuotaExceeded => return SocketError.ResourceExhausted,
            error.SystemResources => return SocketError.ResourceExhausted,
            error.ProtocolFailure => return SocketError.SystemError,
            error.BlockedByFirewall => return SocketError.PermissionDenied,
            else => return SocketError.SystemError,
        };

        return Connection{
            .handle = client_handle,
            .allocator = self.allocator,
            .is_connected = true,
        };
    }

    /// Close socket and cleanup resources
    pub fn close(self: *Socket) void {
        if (self.is_listening) {
            std.posix.close(self.handle);
            self.is_listening = false;
        }
    }

    /// Deinitialize socket
    pub fn deinit(self: *Socket) void {
        self.close();
    }
};

/// Network connection abstraction
pub const Connection = struct {
    handle: SocketHandle,
    allocator: std.mem.Allocator,
    is_connected: bool,

    const Self = @This();

    /// Read data from connection
    pub fn read(self: *Connection, buffer: []u8) SocketError!usize {
        if (!self.is_connected) return SocketError.ConnectionReset;

        // std.posix.read removed in Zig 0.16 — use linux syscall
        const rc = std.os.linux.read(self.handle, buffer.ptr, buffer.len);
        const signed: isize = @bitCast(rc);
        if (signed < 0) {
            const e = std.os.linux.E;
            const errno: e = @enumFromInt(@as(u16, @intCast(-signed)));
            return switch (errno) {
                e.AGAIN, e.WOULDBLOCK => 0,
                e.CONNRESET => SocketError.ConnectionReset,
                e.PIPE => SocketError.ConnectionReset,
                e.BADF => SocketError.SystemError,
                else => SocketError.SystemError,
            };
        }
        return rc;
    }

    /// Write data to connection
    pub fn write(self: *Connection, data: []const u8) SocketError!usize {
        if (!self.is_connected) return SocketError.ConnectionReset;

        // std.posix.write removed in Zig 0.16 — use linux syscall
        const wrc = std.os.linux.write(self.handle, data.ptr, data.len);
        const wsigned: isize = @bitCast(wrc);
        if (wsigned < 0) {
            const e = std.os.linux.E;
            const errno: e = @enumFromInt(@as(u16, @intCast(-wsigned)));
            return switch (errno) {
                e.PIPE => SocketError.ConnectionReset,
                e.CONNRESET => SocketError.ConnectionReset,
                e.BADF => SocketError.SystemError,
                e.DQUOT => SocketError.ResourceExhausted,
                e.FBIG => SocketError.ResourceExhausted,
                e.NOSPC => SocketError.ResourceExhausted,
                else => SocketError.SystemError,
            };
        }
        const bytes_written = wrc;

        return bytes_written;
    }

    /// Close connection
    pub fn close(self: *Connection) void {
        if (self.is_connected) {
            std.posix.close(self.handle);
            self.is_connected = false;
        }
    }

    /// Deinitialize connection
    pub fn deinit(self: *Connection) void {
        self.close();
    }
};

// =============================================================================
// CONVENIENCE FUNCTIONS: Profile-specific socket creation
// =============================================================================

/// Create listening socket for :min profile
pub fn listen(address_str: []const u8, allocator: std.mem.Allocator) SocketError!Socket {
    const address = try SocketAddress.parse(address_str, allocator);
    return Socket.listen_min(address, allocator);
}

/// Create listening socket for :go profile
pub fn listen_with_context(address_str: []const u8, ctx: Context, allocator: std.mem.Allocator) SocketError!Socket {
    const address = try SocketAddress.parse(address_str, allocator);
    return Socket.listen_go(address, ctx, allocator);
}

/// Create listening socket for :full profile
pub fn listen_with_capability(address_str: []const u8, cap: Capability.NetBind, allocator: std.mem.Allocator) SocketError!Socket {
    const address = try SocketAddress.parse(address_str, allocator);
    return Socket.listen_full(address, cap, allocator);
}
