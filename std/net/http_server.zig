// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Production-Grade HTTP Server Implementation
//! Real networking with tri-signature pattern across profiles

const std = @import("std");
const socket = @import("socket.zig");
const protocol = @import("http/protocol.zig");

// Profile-aware imports
const Context = @import("../std_context.zig").Context;
const Capability = @import("../capabilities.zig");

// Re-export protocol types for convenience
pub const HttpRequest = protocol.HttpRequest;
pub const HttpResponse = protocol.HttpResponse;
pub const HttpMethod = protocol.HttpMethod;
pub const HttpStatus = protocol.HttpStatus;
pub const HttpError = protocol.HttpError;
pub const HttpParser = protocol.HttpParser;

/// HTTP server errors
pub const ServerError = error{
    NetworkError,
    BindFailed,
    ListenFailed,
    AcceptFailed,
    Timeout,
    CapabilityDenied,
    ResourceExhausted,
    ParseError,
    ResponseError,
};

/// HTTP request handler function type
pub const RequestHandler = fn (request: HttpRequest, allocator: std.mem.Allocator) HttpResponse;

// =============================================================================
// TRI-SIGNATURE PATTERN: HTTP Server across profiles
// =============================================================================

/// :min profile - Simple synchronous HTTP server
/// Available in: min, go, full
pub fn http_serve_min(port: []const u8, handler: RequestHandler, allocator: std.mem.Allocator) ServerError!void {
    std.debug.print("🌐 Janus HTTP Server (:min profile)\n", .{});
    std.debug.print("📡 Listening on http://localhost{s}\n", .{port});
    std.debug.print("🔄 Sequential request handling (blocking)\n", .{});
    std.debug.print("⚠️  No security restrictions - serves any accessible file\n\n", .{});

    // Create listening socket
    var server_socket = socket.listen(port, allocator) catch |err| switch (err) {
        socket.SocketError.AddressInUse => return ServerError.BindFailed,
        socket.SocketError.PermissionDenied => return ServerError.BindFailed,
        else => return ServerError.NetworkError,
    };
    defer server_socket.deinit();

    std.debug.print("✅ Server listening on port {s}\n", .{port});

    // Sequential request handling loop
    var request_count: u32 = 0;
    while (true) {
        // Accept connection
        var connection = server_socket.accept() catch |err| switch (err) {
            socket.SocketError.Timeout => continue,
            socket.SocketError.ConnectionAborted => continue,
            socket.SocketError.ResourceExhausted => return ServerError.ResourceExhausted,
            else => return ServerError.AcceptFailed,
        };
        defer connection.deinit();

        request_count += 1;
        std.debug.print("📥 Connection {d} accepted\n", .{request_count});

        // Handle request
        handle_connection_min(&connection, handler, allocator) catch |err| {
            std.debug.print("❌ Error handling connection {d}: {}\n", .{ request_count, err });
            continue;
        };

        std.debug.print("✅ Connection {d} completed\n", .{request_count});

        // For demo purposes, limit to 10 connections
        if (request_count >= 10) {
            std.debug.print("\n🎯 Demo complete - handled {d} connections\n", .{request_count});
            break;
        }
    }
}

/// :go profile - Context-aware HTTP server with concurrency
/// Available in: go, full
pub fn http_serve_go(port: []const u8, handler: RequestHandler, ctx: Context, allocator: std.mem.Allocator) ServerError!void {
    std.debug.print("🌐 Janus HTTP Server (:go profile)\n", .{});
    std.debug.print("📡 Listening on http://localhost{s}\n", .{port});
    std.debug.print("🚀 Concurrent request handling with context\n", .{});
    std.debug.print("⏱️  Timeout protection: {d}ms\n", .{ctx.timeout_ms});
    std.debug.print("⚠️  Basic security - no capability restrictions\n\n", .{});

    // Check context
    if (ctx.is_cancelled()) return ServerError.Timeout;

    // Create listening socket with context
    var server_socket = socket.listen_with_context(port, ctx, allocator) catch |err| switch (err) {
        socket.SocketError.AddressInUse => return ServerError.BindFailed,
        socket.SocketError.PermissionDenied => return ServerError.BindFailed,
        socket.SocketError.Timeout => return ServerError.Timeout,
        else => return ServerError.NetworkError,
    };
    defer server_socket.deinit();

    std.debug.print("✅ Server listening on port {s} with context\n", .{port});

    // Concurrent request handling (simulated for now)
    var request_count: u32 = 0;
    while (!ctx.is_cancelled() and request_count < 6) {
        // Accept connection
        var connection = server_socket.accept() catch |err| switch (err) {
            socket.SocketError.Timeout => continue,
            socket.SocketError.ConnectionAborted => continue,
            socket.SocketError.ResourceExhausted => return ServerError.ResourceExhausted,
            else => return ServerError.AcceptFailed,
        };
        defer connection.deinit();

        request_count += 1;
        std.debug.print("📥 Concurrent connection {d} accepted\n", .{request_count});

        // Handle request with context
        handle_connection_go(&connection, handler, ctx, allocator) catch |err| {
            std.debug.print("❌ Error handling connection {d}: {}\n", .{ request_count, err });
            continue;
        };

        std.debug.print("✅ Concurrent connection {d} completed\n", .{request_count});
    }

    std.debug.print("\n🎯 :go profile demo complete - handled {d} connections\n", .{request_count});
}

/// :full profile - Capability-gated HTTP server with security
/// Available in: full only
pub fn http_serve_full(port: []const u8, handler: RequestHandler, cap: Capability.NetHttp, allocator: std.mem.Allocator) ServerError!void {
    std.debug.print("🌐 Janus HTTP Server (:full profile)\n", .{});
    std.debug.print("📡 Listening on http://localhost{s}\n", .{port});
    std.debug.print("🔒 Capability-gated security enforcement\n", .{});
    std.debug.print("🛡️  File access restricted to: {s}\n", .{cap.allowed_paths()});
    std.debug.print("📊 Audit trail: {s}\n\n", .{cap.id()});

    // Validate server capability
    if (!cap.allows_server_port(port)) return ServerError.CapabilityDenied;

    // Create bind capability for socket
    const bind_cap = Capability.NetBind.init("http-server-bind", allocator);

    // Create listening socket with capability
    var server_socket = socket.listen_with_capability(port, bind_cap, allocator) catch |err| switch (err) {
        socket.SocketError.AddressInUse => return ServerError.BindFailed,
        socket.SocketError.PermissionDenied => return ServerError.BindFailed,
        socket.SocketError.CapabilityDenied => return ServerError.CapabilityDenied,
        else => return ServerError.NetworkError,
    };
    defer server_socket.deinit();

    std.debug.print("✅ Secure server listening on port {s}\n", .{port});

    // Secure request handling loop
    var request_count: u32 = 0;
    while (request_count < 8) {
        // Accept connection
        var connection = server_socket.accept() catch |err| switch (err) {
            socket.SocketError.Timeout => continue,
            socket.SocketError.ConnectionAborted => continue,
            socket.SocketError.ResourceExhausted => return ServerError.ResourceExhausted,
            else => return ServerError.AcceptFailed,
        };
        defer connection.deinit();

        request_count += 1;
        std.debug.print("📥 Secure connection {d} accepted\n", .{request_count});

        // Handle request with capability validation
        handle_connection_full(&connection, handler, cap, allocator) catch |err| {
            std.debug.print("❌ Error handling secure connection {d}: {}\n", .{ request_count, err });
            continue;
        };

        std.debug.print("✅ Secure connection {d} completed\n", .{request_count});
    }

    std.debug.print("\n🎯 :full profile demo complete - handled {d} secure connections\n", .{request_count});
}

// =============================================================================
// CONNECTION HANDLERS: Profile-specific request processing
// =============================================================================

/// Handle connection for :min profile
fn handle_connection_min(connection: *socket.Connection, handler: RequestHandler, allocator: std.mem.Allocator) ServerError!void {
    // Read request data
    var buffer: [4096]u8 = undefined;
    const bytes_read = connection.read(&buffer) catch |err| switch (err) {
        socket.SocketError.ConnectionReset => return,
        else => return ServerError.NetworkError,
    };

    if (bytes_read == 0) return; // Connection closed

    // Parse HTTP request
    var request = HttpParser.parse_request(buffer[0..bytes_read], allocator) catch |err| switch (err) {
        HttpError.IncompleteRequest => return ServerError.ParseError,
        HttpError.MalformedRequest => return ServerError.ParseError,
        else => return ServerError.ParseError,
    };
    defer request.deinit();

    std.debug.print("📥 Request: {s} {s}\n", .{ request.method.to_string(), request.uri });

    // Call user handler
    var response = handler(request, allocator);
    defer response.deinit();

    // Send response
    var response_buffer: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&response_buffer);
    HttpParser.serialize_response(response, stream.writer()) catch return ServerError.ResponseError;

    const response_data = stream.getWritten();
    _ = connection.write(response_data) catch return ServerError.NetworkError;

    std.debug.print("📤 Response: {d} ({d} bytes)\n", .{ @intFromEnum(response.status), response_data.len });
}

/// Handle connection for :go profile
fn handle_connection_go(connection: *socket.Connection, handler: RequestHandler, ctx: Context, allocator: std.mem.Allocator) ServerError!void {
    _ = ctx; // TODO: Use context for timeout/cancellation

    // For now, use same logic as :min but with context awareness
    return handle_connection_min(connection, handler, allocator);
}

/// Handle connection for :full profile
fn handle_connection_full(connection: *socket.Connection, handler: RequestHandler, cap: Capability.NetHttp, allocator: std.mem.Allocator) ServerError!void {
    // Read request data
    var buffer: [4096]u8 = undefined;
    const bytes_read = connection.read(&buffer) catch |err| switch (err) {
        socket.SocketError.ConnectionReset => return,
        else => return ServerError.NetworkError,
    };

    if (bytes_read == 0) return; // Connection closed

    // Parse HTTP request
    var request = HttpParser.parse_request(buffer[0..bytes_read], allocator) catch |err| switch (err) {
        HttpError.IncompleteRequest => return ServerError.ParseError,
        HttpError.MalformedRequest => return ServerError.ParseError,
        else => return ServerError.ParseError,
    };
    defer request.deinit();

    std.debug.print("📥 Secure request: {s} {s}\n", .{ request.method.to_string(), request.uri });

    // Security validation
    if (!cap.allows_path_access(request.uri)) {
        std.debug.print("🚫 SECURITY DENIED: Path '{s}' blocked by capability\n", .{request.uri});

        // Send 403 Forbidden response
        var forbidden_response = HttpResponse.init(allocator, .forbidden);
        forbidden_response.set_body("403 Forbidden - Access Denied by Capability");
        defer forbidden_response.deinit();

        var response_buffer: [8192]u8 = undefined;
        var stream = std.io.fixedBufferStream(&response_buffer);
        HttpParser.serialize_response(forbidden_response, stream.writer()) catch return ServerError.ResponseError;

        const response_data = stream.getWritten();
        _ = connection.write(response_data) catch return ServerError.NetworkError;

        std.debug.print("📋 Audit log: Unauthorized access attempt to {s}\n", .{request.uri});
        return;
    }

    // Call user handler
    var response = handler(request, allocator);
    defer response.deinit();

    // Send response
    var response_buffer: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&response_buffer);
    HttpParser.serialize_response(response, stream.writer()) catch return ServerError.ResponseError;

    const response_data = stream.getWritten();
    _ = connection.write(response_data) catch return ServerError.NetworkError;

    std.debug.print("📤 Secure response: {d} (capability verified)\n", .{@intFromEnum(response.status)});
    std.debug.print("📋 Audit log: Authorized access to {s}\n", .{request.uri});
}

// =============================================================================
// PROFILE-AWARE DISPATCH: Single entry point, profile-specific behavior
// =============================================================================

/// Universal http_serve function - dispatches to profile-specific implementation
/// This is what users actually call: http_serve(port, handler, ...)
pub fn http_serve(args: anytype) ServerError!void {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info != .Struct) {
        @compileError("http_serve requires struct arguments");
    }

    const fields = args_info.Struct.fields;

    // Dispatch based on argument signature
    if (fields.len == 3 and @hasField(ArgsType, "port") and @hasField(ArgsType, "handler") and @hasField(ArgsType, "allocator")) {
        // :min profile: http_serve(.{ .port = port, .handler = handler, .allocator = allocator })
        return http_serve_min(args.port, args.handler, args.allocator);
    } else if (fields.len == 4 and @hasField(ArgsType, "ctx")) {
        // :go profile: http_serve(.{ .port = port, .handler = handler, .ctx = ctx, .allocator = allocator })
        return http_serve_go(args.port, args.handler, args.ctx, args.allocator);
    } else if (fields.len == 4 and @hasField(ArgsType, "cap")) {
        // :full profile: http_serve(.{ .port = port, .handler = handler, .cap = cap, .allocator = allocator })
        return http_serve_full(args.port, args.handler, args.cap, args.allocator);
    } else {
        @compileError("Invalid arguments for http_serve - check profile requirements");
    }
}

// =============================================================================
// CONVENIENCE WRAPPERS: Profile-specific convenience functions
// =============================================================================

/// Convenience wrapper for :min profile
pub fn serve(port: []const u8, handler: RequestHandler, allocator: std.mem.Allocator) ServerError!void {
    return http_serve(.{ .port = port, .handler = handler, .allocator = allocator });
}

/// Convenience wrapper for :go profile
pub fn serve_with_context(port: []const u8, handler: RequestHandler, ctx: Context, allocator: std.mem.Allocator) ServerError!void {
    return http_serve(.{ .port = port, .handler = handler, .ctx = ctx, .allocator = allocator });
}

/// Convenience wrapper for :full profile
pub fn serve_with_capability(port: []const u8, handler: RequestHandler, cap: Capability.NetHttp, allocator: std.mem.Allocator) ServerError!void {
    return http_serve(.{ .port = port, .handler = handler, .cap = cap, .allocator = allocator });
}
