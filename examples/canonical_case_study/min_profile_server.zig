// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Task 4: :min Profile Handler - The Trojan Horse
//
// This implements the familiar, boring HTTP server that looks exactly like Go.
// Target: Developers learning Janus or migrating from Go
// Proof Point: "This looks exactly like Go - I can adopt this safely"

const std = @import("std");
const print = std.debug.print;

// Simple HTTP server implementation for :min profile
// Demonstrates: Basic file serving without security restrictions
// Behavior: Serve /README.md, /index.html, any file (Go-familiar patterns)

const HttpServer = struct {
    allocator: std.mem.Allocator,
    port: u16,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, port: u16) Self {
        return Self{
            .allocator = allocator,
            .port = port,
        };
    }

    pub fn serve(self: *Self) !void {
        print("🌐 Janus Web Server Starting (:min profile)...\n", .{});
        print("📡 Listening on http://localhost:{d}\n", .{self.port});
        print("📁 Serving files from current directory\n", .{});
        print("🎯 Profile: :min (Simple, blocking, Go-familiar)\n", .{});
        print("⚡ THE TROJAN HORSE: Familiar patterns that infiltrate conservative environments\n\n", .{});

        // Simulate server loop - in real implementation would use actual HTTP library
        print("🔄 Server loop started (simulation mode)\n", .{});
        print("📥 Simulating requests to demonstrate :min profile behavior...\n\n", .{});

        // Demonstrate typical request handling
        try self.simulateRequest("GET", "/");
        try self.simulateRequest("GET", "/README.md");
        try self.simulateRequest("GET", "/public/index.html");
        try self.simulateRequest("GET", "/secret/config.txt");

        print("\n✅ :min Profile Handler demonstration complete!\n", .{});
        print("🎯 PROOF POINT: This looks exactly like Go - safe for adoption\n", .{});
    }

    fn simulateRequest(self: *Self, method: []const u8, path: []const u8) !void {
        print("📥 Request: {s} {s}\n", .{ method, path });

        // Route handling - same logic as webserver.jan
        if (std.mem.eql(u8, path, "/")) {
            try self.serveFile("public/index.html");
            return;
        }

        if (std.mem.eql(u8, path, "/about")) {
            try self.serveFile("public/about.html");
            return;
        }

        if (std.mem.eql(u8, path, "/style.css")) {
            try self.serveFile("public/style.css");
            return;
        }

        // Static file serving - :min profile serves ANY file (no restrictions)
        if (std.mem.startsWith(u8, path, "/public/")) {
            try self.serveStaticFile(path);
            return;
        }

        // :min profile behavior: Attempts to serve ANY file (including secrets)
        // This demonstrates the "familiar but unsafe" behavior
        if (std.mem.eql(u8, path, "/secret/config.txt") or
            std.mem.eql(u8, path, "/README.md"))
        {
            try self.serveFile(path[1..]); // Remove leading slash
            return;
        }

        // 404 for unknown paths
        self.errorResponse(404, "Not Found");
    }

    fn serveFile(self: *Self, path: []const u8) !void {
        print("📄 Serving file: {s}\n", .{path});

        // :min profile: fs.read(path, allocator) - unrestricted access
        // Simulate file reading
        const content = self.readFileSimulation(path);

        if (content) |file_content| {
            const content_type = self.getContentType(path);
            print("✅ 200 OK - {s} ({d} bytes, {s})\n", .{ path, file_content.len, content_type });
            print("📤 Response: Content served successfully\n\n", .{});
        } else {
            print("❌ File read failed: File not found\n", .{});
            self.errorResponse(404, "File not found");
        }
    }

    fn serveStaticFile(self: *Self, path: []const u8) !void {
        // Remove leading slash for file system access
        const file_path = if (std.mem.startsWith(u8, path, "/")) path[1..] else path;
        try self.serveFile(file_path);
    }

    fn errorResponse(self: *Self, status: u16, message: []const u8) void {
        _ = self;
        print("❌ {d} {s}\n", .{ status, message });
        print("📤 Response: Error page served\n\n", .{});
    }

    fn readFileSimulation(self: *Self, path: []const u8) ?[]const u8 {
        _ = self;

        // Simulate file content based on path
        if (std.mem.eql(u8, path, "public/index.html")) {
            return "<!DOCTYPE html><html><head><title>Janus :min Profile</title></head><body><h1>Welcome to Janus</h1><p>This is the :min profile - simple and familiar!</p></body></html>";
        }

        if (std.mem.eql(u8, path, "public/about.html")) {
            return "<!DOCTYPE html><html><head><title>About</title></head><body><h1>About Janus</h1><p>Progressive profiles without rewrites!</p></body></html>";
        }

        if (std.mem.eql(u8, path, "public/style.css")) {
            return "body { font-family: Arial, sans-serif; margin: 40px; } h1 { color: #333; }";
        }

        if (std.mem.eql(u8, path, "README.md")) {
            return "# Janus Web Server\n\nThis demonstrates the :min profile behavior.\nNotice: ANY file can be served - no security restrictions!\n";
        }

        if (std.mem.eql(u8, path, "secret/config.txt")) {
            return "SECRET_API_KEY=abc123\nDATABASE_PASSWORD=supersecret\n# This file should NOT be served in :full profile!";
        }

        return null; // File not found
    }

    fn getContentType(self: *Self, path: []const u8) []const u8 {
        _ = self;

        if (std.mem.endsWith(u8, path, ".html")) return "text/html";
        if (std.mem.endsWith(u8, path, ".css")) return "text/css";
        if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
        if (std.mem.endsWith(u8, path, ".json")) return "application/json";
        if (std.mem.endsWith(u8, path, ".txt")) return "text/plain";
        if (std.mem.endsWith(u8, path, ".md")) return "text/markdown";
        return "application/octet-stream";
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 JANUS CANONICAL CASE STUDY - TASK 4\n", .{});
    print("🎯 :min Profile Handler - The Trojan Horse\n", .{});
    print("==================================================\n\n", .{});

    var server = HttpServer.init(allocator, 8080);
    try server.serve();

    print("\n==================================================\n", .{});
    print("🎉 TASK 4 COMPLETE: :min Profile Handler Implemented\n", .{});
    print("✅ PROOF POINT: Familiar, Go-like HTTP server behavior\n", .{});
    print("🎯 TARGET ACHIEVED: Conservative developers can adopt safely\n", .{});
    print("⚡ THE TROJAN HORSE: Ready to infiltrate conservative environments\n", .{});
}
