// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus :service Profile — Chat Server Demo
//!
//! Demonstrates CBC-MN Nursery + HTTP Server + NS-Msg pub/sub
//! Compile: zig build-exe examples/service/chat_server.zig
//! Run: ./chat_server

const std = @import("std");
const service = @import("../../std/service.zig");

const allocator = std.heap.page_allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // 1. Create nursery for structured concurrency
    var nursery = service.Nursery.init(alloc);
    defer nursery.deinit();

    // 2. Start HTTP server (fiber-per-request)
    const server_addr = try std.net.Address.resolveIp("127.0.0.1", 8080);
    var http_server = service.http_server.HttpServer.init(&nursery, server_addr);
    try http_server.start();

    // 3. Subscribe to chat messages
    const sub = try service.ns_msg.subscribe(alloc, "chat.room.general.*");
    defer sub.deinit();

    // 4. Main event loop
    std.debug.print("Chat server running on http://127.0.0.1:8080\n", .{});
    std.debug.print("Subscribe to chat.room.general.* for messages\n", .{});

    while (true) {
        if (sub.recv(alloc)) |msg| {
            defer msg.deinit();
            std.debug.print("Received: {s} from {s}\n", .{ msg.payload.content, msg.path.toString(alloc) catch "unknown" });
        }
    }
}
