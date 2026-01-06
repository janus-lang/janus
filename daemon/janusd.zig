// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// janusd - gRPC Oracle Daemon (JSON removed)
const std = @import("std");
const grpc = @import("grpc_bindings");
const OracleGrpcServer = @import("oracle_grpc_server.zig").OracleGrpcServer;

const print = std.debug.print;

const DaemonConfig = struct {
    port: u16 = 7777,
    host: []const u8 = "127.0.0.1",
};

const JanusDaemon = struct {
    allocator: std.mem.Allocator,
    config: DaemonConfig,
    grpc_server: ?OracleGrpcServer = null,
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: DaemonConfig) !JanusDaemon {
        return .{ .allocator = allocator, .config = config };
    }

    pub fn start(self: *JanusDaemon) !void {
        print("🚀 Starting janusd (gRPC) on {s}:{d}\n", .{ self.config.host, self.config.port });
        self.running = true;
        var server = OracleGrpcServer.init(self.allocator);
        try server.start(self.config.host, self.config.port);
        self.grpc_server = server;
        while (self.running) std.time.sleep(1_000_000_000);
    }

    pub fn stop(self: *JanusDaemon) void {
        self.running = false;
        if (self.grpc_server) |*s| s.deinit();
        self.grpc_server = null;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = DaemonConfig{};

    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            config.port = try std.fmt.parseInt(u16, args[i + 1], 10);
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
            config.host = args[i + 1];
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            print("Usage: janusd [--host HOST] [--port PORT]\n", .{});
            return;
        } else {
            print("❌ Unknown argument: {s}\n", .{args[i]});
            return;
        }
    }

    var daemon = try JanusDaemon.init(allocator, config);
    try daemon.start();
}
