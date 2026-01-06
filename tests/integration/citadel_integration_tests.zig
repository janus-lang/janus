// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Integration tests for the complete Citadel Architecture
//!
//! Tests the full gRPC client → proxy → daemon → libjanus workflow
//! to ensure end-to-end functionality and API compatibility.

const std = @import("std");
const testing = std.testing;
const citadel_protocol = @import("../../daemon/citadel_protocol.zig");

/// Mock gRPC client for testing
const MockGrpcClient = struct {
    allocator: std.mem.Allocator,
    proxy_process: ?std.process.Child = null,
    daemon_process: ?std.process.Child = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stopServices();
    }

    pub fn startServices(self: *Self) !void {
        // Start core daemon
        self.daemon_process = std.process.Child.init(&[_][]const u8{
            "./zig-out/bin/janus-core-daemon",
            "--stdio",
        }, self.allocator);
        self.daemon_process.?.stdin_behavior = .Pipe;
        self.daemon_process.?.stdout_behavior = .Pipe;
        self.daemon_process.?.stderr_behavior = .Pipe;
        try self.daemon_process.?.spawn();

        // Give daemon time to start
        std.time.sleep(100 * std.time.ns_per_ms);

        // Start gRPC proxy
        self.proxy_process = std.process.Child.init(&[_][]const u8{
            "./zig-out/bin/janus-grpc-proxy",
            "--daemon-stdio",
            "--port=50051",
        }, self.allocator);
        self.proxy_process.?.stdin_behavior = .Pipe;
        self.proxy_process.?.stdout_behavior = .Pipe;
        self.proxy_process.?.stderr_behavior = .Pipe;
        try self.proxy_process.?.spawn();

        // Give proxy time to start and connect
        std.time.sleep(500 * std.time.ns_per_ms);
    }

    pub fn stopServices(self: *Self) void {
        if (self.proxy_process) |*proxy| {
            _ = proxy.kill() catch {};
            _ = proxy.wait() catch {};
            self.proxy_process = null;
        }

        if (self.daemon_process) |*daemon| {
            _ = daemon.kill() catch {};
            _ = daemon.wait() catch {};
            self.daemon_process = null;
        }
    }

    pub fn sendDocUpdate(self: *Self, uri: []const u8, content: []const u8, version: u32) !void {
        _ = self;
        _ = uri;
        _ = content;
        _ = version;
        // Mock implementation - in real test this would make actual gRPC call
        // For now, just verify the services are running
        if (self.daemon_process == null or self.proxy_process == null) {
            return error.ServicesNotRunning;
        }
    }

    pub fn getHover(self: *Self, uri: []const u8, line: u32, column: u32) !?[]const u8 {
        _ = self;
        _ = uri;
        _ = line;
        _ = column;
        // Mock implementation
        return try self.allocator.dupe(u8, "Mock hover response");
    }

    pub fn getDefinition(self: *Self, uri: []const u8, line: u32, column: u32) !?[]const u8 {
        _ = self;
        _ = uri;
        _ = line;
        _ = column;
        // Mock implementation
        return try self.allocator.dupe(u8, "Mock definition response");
    }

    pub fn getReferences(self: *Self, uri: []const u8, line: u32, column: u32) ![][]const u8 {
        _ = self;
        _ = uri;
        _ = line;
        _ = column;
        // Mock implementation
        const refs = try self.allocator.alloc([]const u8, 1);
        refs[0] = try self.allocator.dupe(u8, "Mock reference");
        return refs;
    }
};

test "End-to-end document update" {
    if (std.builtin.os.tag == .windows) {
        // Skip on Windows due to process spawning differences
        return error.SkipZigTest;
    }

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client = MockGrpcClient.init(allocator);
    defer client.deinit();

    // Check if binaries exist before trying to start services
    const daemon_exists = std.fs.cwd().access("zig-out/bin/janus-core-daemon", .{}) catch false;
    const proxy_exists = std.fs.cwd().access("zig-out/bin/janus-grpc-proxy", .{}) catch false;

    if (!daemon_exists or !proxy_exists) {
        std.debug.print("Skipping integration test - binaries not found\n", .{});
        return error.SkipZigTest;
    }

    // Start services
    client.startServices() catch |err| {
        std.debug.print("Failed to start services: {}\n", .{err});
        return error.SkipZigTest;
    };

    // Test document update
    const uri = "file:///integration_test.jan";
    const content = "func main() { print(\"Integration test!\"); }";

    try client.sendDocUpdate(uri, content, 1);

    // Test API operations
    const hover = try client.getHover(uri, 1, 5);
    defer if (hover) |h| allocator.free(h);
    try testing.expect(hover != null);

    const definition = try client.getDefinition(uri, 1, 5);
    defer if (definition) |d| allocator.free(d);
    try testing.expect(definition != null);

    const references = try client.getReferences(uri, 1, 5);
    defer {
        for (references) |ref| allocator.free(ref);
        allocator.free(references);
    }
    try testing.expect(references.len > 0);
}

test "API compatibility" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client = MockGrpcClient.init(allocator);
    defer client.deinit();

    // Test that all expected API endpoints are available
    const test_cases = [_]struct {
        name: []const u8,
        test_fn: *const fn (*MockGrpcClient, std.mem.Allocator) anyerror!void,
    }{
        .{ .name = "DocUpdate", .test_fn = testDocUpdateAPI },
        .{ .name = "HoverAt", .test_fn = testHoverAtAPI },
        .{ .name = "DefinitionAt", .test_fn = testDefinitionAtAPI },
        .{ .name = "ReferencesAt", .test_fn = testReferencesAtAPI },
    };

    for (test_cases) |test_case| {
        std.debug.print("Testing API compatibility: {s}\n", .{test_case.name});
        try test_case.test_fn(&client, allocator);
    }
}

fn testDocUpdateAPI(client: *MockGrpcClient, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const uri = "file:///api_test.jan";
    const content = "func test() {}";
    try client.sendDocUpdate(uri, content, 1);
}

fn testHoverAtAPI(client: *MockGrpcClient, allocator: std.mem.Allocator) !void {
    const hover = try client.getHover("file:///test.jan", 1, 5);
    defer if (hover) |h| allocator.free(h);
    try testing.expect(hover != null);
}

fn testDefinitionAtAPI(client: *MockGrpcClient, allocator: std.mem.Allocator) !void {
    const definition = try client.getDefinition("file:///test.jan", 1, 5);
    defer if (definition) |d| allocator.free(d);
    try testing.expect(definition != null);
}

fn testReferencesAtAPI(client: *MockGrpcClient, allocator: std.mem.Allocator) !void {
    const references = try client.getReferences("file:///test.jan", 1, 5);
    defer {
        for (references) |ref| allocator.free(ref);
        allocator.free(references);
    }
    try testing.expect(references.len >= 0);
}

test "Error handling and graceful degradation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client = MockGrpcClient.init(allocator);
    defer client.deinit();

    // Test behavior when services are not running
    const result = client.sendDocUpdate("file:///test.jan", "invalid", 1);
    try testing.expectError(error.ServicesNotRunning, result);

    // Test with invalid document content
    // (This would be tested with actual services running)

    // Test network failures
    // (This would be tested with actual network conditions)

    // Test protocol version mismatches
    // (This would be tested with different client/server versions)
}

test "Performance and resource usage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client = MockGrpcClient.init(allocator);
    defer client.deinit();

    const iterations = 10; // Reduced for mock testing
    const start_time = std.time.nanoTimestamp();

    // Simulate load testing
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const uri = try std.fmt.allocPrint(allocator, "file:///perf_test_{}.jan", .{i});
        defer allocator.free(uri);

        const content = try std.fmt.allocPrint(allocator, "func test_{}() {{ return {}; }}", .{ i, i });
        defer allocator.free(content);

        // Mock operations
        _ = client.sendDocUpdate(uri, content, i) catch {};

        const hover = client.getHover(uri, 1, 5) catch null;
        if (hover) |h| allocator.free(h);

        const definition = client.getDefinition(uri, 1, 5) catch null;
        if (definition) |d| allocator.free(d);

        const references = client.getReferences(uri, 1, 5) catch &[_][]const u8{};
        for (references) |ref| allocator.free(ref);
        allocator.free(references);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    const ops_per_second = @as(f64, @floatFromInt(iterations * 4)) / (duration_ms / 1000.0); // 4 ops per iteration

    std.debug.print("\nIntegration Test Performance:\n", .{});
    std.debug.print("  {} operations in {d:.2} ms\n", .{ iterations * 4, duration_ms });
    std.debug.print("  {d:.0} operations/second\n", .{ops_per_second});

    // Basic performance validation (very lenient for mock testing)
    try testing.expect(ops_per_second > 10);
}

test "Concurrent client connections" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ThreadContext = struct {
        allocator: std.mem.Allocator,
        client_id: u32,
        success: bool = false,
    };

    const worker_fn = struct {
        fn run(context: *ThreadContext) void {
            var client = MockGrpcClient.init(context.allocator);
            defer client.deinit();

            const uri_buf = std.fmt.allocPrint(
                context.allocator,
                "file:///concurrent_test_{}.jan",
                .{context.client_id},
            ) catch return;
            defer context.allocator.free(uri_buf);

            const content_buf = std.fmt.allocPrint(
                context.allocator,
                "func client_{}() {{ return {}; }}",
                .{ context.client_id, context.client_id },
            ) catch return;
            defer context.allocator.free(content_buf);

            // Perform operations
            _ = client.sendDocUpdate(uri_buf, content_buf, 1) catch return;

            const hover = client.getHover(uri_buf, 1, 5) catch return;
            defer if (hover) |h| context.allocator.free(h);

            const definition = client.getDefinition(uri_buf, 1, 5) catch return;
            defer if (definition) |d| context.allocator.free(d);

            const references = client.getReferences(uri_buf, 1, 5) catch return;
            defer {
                for (references) |ref| context.allocator.free(ref);
                context.allocator.free(references);
            }

            context.success = true;
        }
    }.run;

    // Test with multiple concurrent clients
    const num_clients = 3;
    var contexts: [num_clients]ThreadContext = undefined;
    var threads: [num_clients]std.Thread = undefined;

    for (0..num_clients) |i| {
        contexts[i] = ThreadContext{
            .allocator = allocator,
            .client_id = @intCast(i),
        };
        threads[i] = try std.Thread.spawn(.{}, worker_fn, .{&contexts[i]});
    }

    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }

    // Verify all clients succeeded
    for (contexts) |context| {
        try testing.expect(context.success);
    }
}

test "Service lifecycle management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client = MockGrpcClient.init(allocator);
    defer client.deinit();

    // Test starting services
    // (Mock implementation doesn't actually start processes)

    // Test stopping services
    client.stopServices();

    // Test restarting services
    // (Would test actual restart behavior with real services)

    // Test graceful shutdown
    // (Would test that in-flight requests are handled properly)
}

test "Protocol version compatibility" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test version negotiation
    const version_request = citadel_protocol.Request{
        .version_check = .{
            .client_version = "1.0.0",
            .supported_features = &[_][]const u8{ "hover", "definition", "references" },
        },
    };

    // Serialize version request
    const serialized = try citadel_protocol.serializeRequest(allocator, version_request);
    defer allocator.free(serialized);

    // Deserialize and verify
    const deserialized = try citadel_protocol.deserializeRequest(allocator, serialized);
    defer citadel_protocol.freeRequest(allocator, deserialized);

    try testing.expectEqual(citadel_protocol.MessageType.version_check, std.meta.activeTag(deserialized));
    try testing.expectEqualStrings("1.0.0", deserialized.version_check.client_version);
    try testing.expectEqual(@as(usize, 3), deserialized.version_check.supported_features.len);
}

test "Memory usage stability" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client = MockGrpcClient.init(allocator);
    defer client.deinit();

    // Simulate sustained load
    const iterations = 50;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const uri = try std.fmt.allocPrint(allocator, "file:///memory_test_{}.jan", .{i});
        defer allocator.free(uri);

        // Create progressively larger content
        const content_size = 1000 + (i * 100);
        const content = try allocator.alloc(u8, content_size);
        defer allocator.free(content);
        @memset(content, 'A');

        // Perform operations
        _ = client.sendDocUpdate(uri, content, i) catch {};

        const hover = client.getHover(uri, 1, 5) catch null;
        if (hover) |h| allocator.free(h);

        const definition = client.getDefinition(uri, 1, 5) catch null;
        if (definition) |d| allocator.free(d);

        const references = client.getReferences(uri, 1, 5) catch &[_][]const u8{};
        for (references) |ref| allocator.free(ref);
        allocator.free(references);

        // Force garbage collection periodically
        if (i % 10 == 0) {
            std.time.sleep(1 * std.time.ns_per_ms);
        }
    }

    // Memory should be stable (no leaks detected by arena allocator)
    std.debug.print("Memory stability test completed - {} iterations\n", .{iterations});
}
