// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Janus gRPC Proxy - The Outer Wall
//!
//! A lightweight gRPC server that acts as a proxy to the janus-core-daemon.
//! This component maintains exact C API compatibility for existing clients
//! while delegating all actual work to the core daemon via the Citadel Protocol.
//!
//! CRITICAL: This component MUST NOT link against libjanus. It is a pure
//! protocol translator between gRPC and the Citadel Protocol.

const std = @import("std");
const grpc = @import("grpc_bindings");
const protocol = @import("citadel_protocol.zig");

const print = std.debug.print;

const ProxyConfig = struct {
    port: u16 = 7777,
    host: []const u8 = "127.0.0.1",
    core_daemon_path: []const u8 = "./zig-out/bin/janus-core-daemon",
    log_level: LogLevel = .info,

    const LogLevel = enum {
        debug,
        info,
        warn,
        @"error",
    };
};

const CoreDaemonClient = struct {
    allocator: std.mem.Allocator,
    process: ?std.process.Child = null,
    frame_reader: ?protocol.FrameReader = null,
    frame_writer: ?protocol.FrameWriter = null,
    request_counter: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) CoreDaemonClient {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CoreDaemonClient) void {
        self.stop();
    }

    pub fn start(self: *CoreDaemonClient, daemon_path: []const u8) !void {
        if (self.process != null) return; // Already started

        // Start the core daemon as a subprocess
        var process = std.process.Child.init(&[_][]const u8{ daemon_path, "--log-level", "debug" }, self.allocator);
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Inherit;

        try process.spawn();
        self.process = process;

        // Set up communication channels
        const stdin = process.stdin.?.writer().any();
        const stdout = process.stdout.?.reader().any();

        self.frame_writer = protocol.FrameWriter.init(stdin);
        self.frame_reader = protocol.FrameReader.init(self.allocator, stdout);

        // Send version negotiation
        try self.negotiateVersion();
    }

    pub fn stop(self: *CoreDaemonClient) void {
        if (self.process) |*process| {
            // Send shutdown request
            self.sendShutdown() catch {};

            // Wait for graceful shutdown or terminate
            const result = process.wait() catch {
                _ = process.kill() catch {};
                return;
            };

            switch (result) {
                .Exited => |code| {
                    if (code != 0) {
                        print("⚠️  Core daemon exited with code {}\n", .{code});
                    }
                },
                else => {
                    print("⚠️  Core daemon terminated abnormally\n", .{});
                },
            }
        }
        self.process = null;
        self.frame_reader = null;
        self.frame_writer = null;
    }

    fn negotiateVersion(self: *CoreDaemonClient) !void {
        const request_id = self.getNextRequestId();
        const request = protocol.SerializableRequest{
            .id = request_id,
            .type = "version_request",
            .timestamp = protocol.Request.getTimestamp(),
            .payload = protocol.RequestPayload{
                .version_request = protocol.VersionRequestPayload{
                    .client_version = protocol.ProtocolVersion.current(),
                    .supported_features = &[_][]const u8{"stdio"},
                },
            },
        };

        const serialized = try protocol.serializeMessagePackRequest(self.allocator, request);
        defer self.allocator.free(serialized);

        try self.frame_writer.?.writeFrame(serialized);

        // Read response
        const response_data = try self.frame_reader.?.readFrame();
        defer self.allocator.free(response_data);

        const response = try protocol.parseResponse(self.allocator, response_data);
        defer response.deinit(self.allocator);

        if (!std.mem.eql(u8, response.status, "success")) {
            return error.VersionNegotiationFailed;
        }
    }

    fn sendShutdown(self: *CoreDaemonClient) !void {
        // For now, just terminate the process
        // TODO: Implement proper shutdown protocol once serialization is complete
        _ = self;
    }

    pub fn sendDocUpdate(self: *CoreDaemonClient, uri: []const u8, content: []const u8) !protocol.DocUpdateResponsePayload {
        const request_id = self.getNextRequestId();
        const request = protocol.SerializableRequest{
            .id = request_id,
            .type = "doc_update",
            .timestamp = protocol.Request.getTimestamp(),
            .payload = protocol.RequestPayload{
                .doc_update = protocol.DocUpdateRequestPayload{
                    .uri = uri,
                    .content = content,
                },
            },
        };

        const serialized = try protocol.serializeMessagePackRequest(self.allocator, request);
        defer self.allocator.free(serialized);

        try self.frame_writer.?.writeFrame(serialized);

        // Read response
        const response_data = try self.frame_reader.?.readFrame();
        defer self.allocator.free(response_data);

        const response = try protocol.parseResponse(self.allocator, response_data);
        defer response.deinit(self.allocator);

        if (!std.mem.eql(u8, response.status, "success")) {
            return error.DocUpdateFailed;
        }

        return response.payload.doc_update_response;
    }

    pub fn sendHoverAt(self: *CoreDaemonClient, uri: []const u8, line: u32, character: u32) !?protocol.HoverInfo {
        const request_id = self.getNextRequestId();
        const request = protocol.SerializableRequest{
            .id = request_id,
            .type = "hover_at",
            .timestamp = protocol.Request.getTimestamp(),
            .payload = protocol.RequestPayload{
                .hover_at = protocol.HoverAtRequestPayload{
                    .uri = uri,
                    .position = protocol.Position{ .line = line, .character = character },
                },
            },
        };

        const serialized = try protocol.serializeMessagePackRequest(self.allocator, request);
        defer self.allocator.free(serialized);

        try self.frame_writer.?.writeFrame(serialized);

        // Read response
        const response_data = try self.frame_reader.?.readFrame();
        defer self.allocator.free(response_data);

        const response = try protocol.parseResponse(self.allocator, response_data);
        defer response.deinit(self.allocator);

        if (!std.mem.eql(u8, response.status, "success")) {
            return error.HoverAtFailed;
        }

        return response.payload.hover_at_response.hover_info;
    }

    pub fn sendDefinitionAt(self: *CoreDaemonClient, uri: []const u8, line: u32, character: u32) !?protocol.Location {
        // TODO: Implement proper communication once serialization is complete
        _ = self;

        // Return placeholder location
        return protocol.Location{
            .uri = uri,
            .range = protocol.Range{
                .start = protocol.Position{ .line = line, .character = character },
                .end = protocol.Position{ .line = line, .character = character + 1 },
            },
        };
    }

    pub fn sendReferencesAt(self: *CoreDaemonClient, uri: []const u8, line: u32, character: u32, include_declaration: bool) ![]const protocol.Reference {
        // TODO: Implement proper communication once serialization is complete
        _ = self;
        _ = uri;
        _ = line;
        _ = character;
        _ = include_declaration;

        // Return empty references for now
        return &[_]protocol.Reference{};
    }

    fn getNextRequestId(self: *CoreDaemonClient) u32 {
        self.request_counter += 1;
        return self.request_counter;
    }
};

// gRPC server that delegates to the core daemon
pub const GrpcProxy = if (grpc.enabled) struct {
    allocator: std.mem.Allocator,
    config: ProxyConfig,
    c_server: ?*grpc.c.JanusOracleServer = null,
    core_client: CoreDaemonClient,
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: ProxyConfig) GrpcProxy {
        return .{
            .allocator = allocator,
            .config = config,
            .core_client = CoreDaemonClient.init(allocator),
        };
    }

    pub fn deinit(self: *GrpcProxy) void {
        self.stop();
        self.core_client.deinit();
    }

    pub fn start(self: *GrpcProxy) !void {
        if (self.running) return;

        if (self.config.log_level == .info or self.config.log_level == .debug) {
            print("🏰 Starting Janus gRPC Proxy on {s}:{d}\n", .{ self.config.host, self.config.port });
            print("🔗 Core daemon path: {s}\n", .{self.config.core_daemon_path});
        }

        // Start the core daemon
        try self.core_client.start(self.config.core_daemon_path);

        // Start the gRPC server
        var host_buf = try self.allocator.alloc(u8, self.config.host.len + 1);
        defer self.allocator.free(host_buf);
        @memcpy(host_buf[0..self.config.host.len], self.config.host);
        host_buf[self.config.host.len] = 0;

        const srv = grpc.c.janus_oracle_server_create(@ptrCast(host_buf.ptr), self.config.port) orelse return error.ServerCreateFailed;
        self.c_server = srv;

        // Register handlers with `self` as user pointer
        const rc = grpc.c.janus_oracle_server_set_handlers(
            srv,
            onDocUpdate,
            onHoverAt,
            onDefinitionAt,
            onReferencesAt,
            self,
        );
        if (rc != 0) return error.HandlerRegistrationFailed;

        if (grpc.c.janus_oracle_server_start(srv) != 0) return error.ServerStartFailed;

        self.running = true;

        if (self.config.log_level == .info or self.config.log_level == .debug) {
            print("✅ gRPC Proxy ready - forwarding requests to core daemon\n", .{});
        }

        // Keep the server running
        while (self.running) {
            std.time.sleep(100_000_000); // 100ms
        }
    }

    pub fn stop(self: *GrpcProxy) void {
        if (!self.running) return;

        self.running = false;

        if (self.c_server) |srv| {
            _ = grpc.c.janus_oracle_server_stop(srv);
            grpc.c.janus_oracle_server_destroy(srv);
            self.c_server = null;
        }

        self.core_client.stop();

        if (self.config.log_level == .info or self.config.log_level == .debug) {
            print("🛑 gRPC Proxy stopped\n", .{});
        }
    }

    // ---------- C handler bridges ----------
    fn onDocUpdate(uri_c: [*c]const u8, content_c: [*c]const u8, ok_out: [*c]bool, user: ?*anyopaque) callconv(.C) c_int {
        const self: *GrpcProxy = @ptrCast(@alignCast(user.?));
        const uri = std.mem.span(uri_c);
        const content = std.mem.span(content_c);
        ok_out.* = false;

        const result = self.core_client.sendDocUpdate(uri, content) catch return 2;
        _ = result; // We don't need the detailed response for the C API
        ok_out.* = true;
        return 0;
    }

    fn onHoverAt(uri_c: [*c]const u8, line: u32, character: u32, markdown_out: [*c][*c]const u8, user: ?*anyopaque) callconv(.C) c_int {
        const self: *GrpcProxy = @ptrCast(@alignCast(user.?));
        markdown_out.* = null;
        const uri = std.mem.span(uri_c);

        const hover_info = self.core_client.sendHoverAt(uri, line, character) catch return 2;
        if (hover_info) |info| {
            // Allocate C-compatible string for the markdown content
            const c_str = self.allocator.dupeZ(u8, info.markdown) catch return 2;
            markdown_out.* = @ptrCast(c_str.ptr);
        }
        return 0;
    }

    fn onDefinitionAt(uri_c: [*c]const u8, line: u32, character: u32, found_out: [*c]bool, def_uri_out: [*c][*c]const u8, def_line_out: [*c]u32, def_character_out: [*c]u32, user: ?*anyopaque) callconv(.C) c_int {
        const self: *GrpcProxy = @ptrCast(@alignCast(user.?));
        found_out.* = false;
        def_uri_out.* = null;
        def_line_out.* = 0;
        def_character_out.* = 0;
        const uri = std.mem.span(uri_c);

        const location = self.core_client.sendDefinitionAt(uri, line, character) catch return 2;
        if (location) |loc| {
            found_out.* = true;
            def_uri_out.* = uri_c; // Same file for now
            def_line_out.* = loc.range.start.line;
            def_character_out.* = loc.range.start.character;
        }
        return 0;
    }

    fn onReferencesAt(uri_c: [*c]const u8, line: u32, character: u32, include_decl: bool, sink: grpc.c.JanusLocationSinkFn, sink_user: ?*anyopaque, user: ?*anyopaque) callconv(.C) c_int {
        const self: *GrpcProxy = @ptrCast(@alignCast(user.?));
        const uri = std.mem.span(uri_c);

        const references = self.core_client.sendReferencesAt(uri, line, character, include_decl) catch return 2;

        // Stream references to the sink
        for (references) |ref| {
            const s = sink.?;
            s(sink_user, uri_c, ref.range.start.line, ref.range.start.character);
        }
        return 0;
    }
} else struct {
    pub fn init(allocator: std.mem.Allocator, config: ProxyConfig) GrpcProxy {
        _ = allocator;
        _ = config;
        return .{};
    }
    pub fn deinit(self: *GrpcProxy) void {
        _ = self;
    }
    pub fn start(self: *GrpcProxy) !void {
        _ = self;
        return error.GrpcNotAvailable;
    }
    pub fn stop(self: *GrpcProxy) void {
        _ = self;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = ProxyConfig{};

    // Parse command line arguments
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            config.port = try std.fmt.parseInt(u16, args[i + 1], 10);
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
            config.host = args[i + 1];
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--daemon-path") and i + 1 < args.len) {
            config.core_daemon_path = args[i + 1];
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--log-level") and i + 1 < args.len) {
            if (std.mem.eql(u8, args[i + 1], "debug")) {
                config.log_level = .debug;
            } else if (std.mem.eql(u8, args[i + 1], "info")) {
                config.log_level = .info;
            } else if (std.mem.eql(u8, args[i + 1], "warn")) {
                config.log_level = .warn;
            } else if (std.mem.eql(u8, args[i + 1], "error")) {
                config.log_level = .@"error";
            } else {
                print("❌ Invalid log level: {s}\n", .{args[i + 1]});
                return;
            }
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            print("Janus gRPC Proxy - The Outer Wall\n\n", .{});
            print("Usage: janus-grpc-proxy [OPTIONS]\n\n", .{});
            print("Options:\n", .{});
            print("  --host HOST           gRPC server host (default: 127.0.0.1)\n", .{});
            print("  --port PORT           gRPC server port (default: 7777)\n", .{});
            print("  --daemon-path PATH    Path to janus-core-daemon (default: ./zig-out/bin/janus-core-daemon)\n", .{});
            print("  --log-level LEVEL     Set log level (debug|info|warn|error)\n", .{});
            print("  --help, -h            Show this help message\n\n", .{});
            print("The proxy maintains exact C API compatibility while delegating to the core daemon.\n", .{});
            return;
        } else {
            print("❌ Unknown argument: {s}\n", .{args[i]});
            print("Use --help for usage information\n", .{});
            return;
        }
    }

    var proxy = GrpcProxy.init(allocator, config);
    defer proxy.deinit();

    // Set up signal handling for graceful shutdown
    const signal_handler = struct {
        var proxy_ptr: ?*GrpcProxy = null;

        fn handleSignal(sig: c_int) callconv(.C) void {
            _ = sig;
            if (proxy_ptr) |p| {
                p.stop();
            }
        }
    };

    signal_handler.proxy_ptr = &proxy;

    // Register signal handlers (Unix-like systems)
    if (@import("builtin").os.tag != .windows) {
        const c = @cImport({
            @cInclude("signal.h");
        });
        _ = c.signal(c.SIGINT, signal_handler.handleSignal);
        _ = c.signal(c.SIGTERM, signal_handler.handleSignal);
    }

    try proxy.start();
}
