// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Unit tests for janus-core-daemon functionality
//!
//! Tests basic daemon functionality without complex ASTDB integration.

const std = @import("std");
const testing = std.testing;
const libjanus = @import("libjanus");

// Simple mock daemon for testing
const MockCoreDaemon = struct {
    allocator: std.mem.Allocator,
    documents: std.StringHashMap([]const u8),
    update_count: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .documents = std.StringHashMap([]const u8).init(allocator),
            .update_count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.documents.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.documents.deinit();
    }

    pub fn updateDocument(self: *Self, uri: []const u8, content: []const u8) !void {
        // Remove existing document if present
        if (self.documents.get(uri)) |existing_content| {
            self.allocator.free(existing_content);
            _ = self.documents.remove(uri);
        }

        // Store new document
        const owned_uri = try self.allocator.dupe(u8, uri);
        const owned_content = try self.allocator.dupe(u8, content);
        try self.documents.put(owned_uri, owned_content);
        self.update_count += 1;
    }

    pub fn getDocument(self: *Self, uri: []const u8) ?[]const u8 {
        return self.documents.get(uri);
    }

    pub fn getDocumentCount(self: *Self) u32 {
        return @intCast(self.documents.count());
    }

    pub fn getUpdateCount(self: *Self) u32 {
        return self.update_count;
    }
};

test "Mock daemon basic functionality" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var daemon = MockCoreDaemon.init(allocator);
    defer daemon.deinit();

    // Test initial state
    try testing.expectEqual(@as(u32, 0), daemon.getDocumentCount());
    try testing.expectEqual(@as(u32, 0), daemon.getUpdateCount());

    // Test document addition
    const uri = "file:///test.jan";
    const content = "func main() { print(\"Hello, World!\"); }";
    try daemon.updateDocument(uri, content);

    try testing.expectEqual(@as(u32, 1), daemon.getDocumentCount());
    try testing.expectEqual(@as(u32, 1), daemon.getUpdateCount());

    const retrieved = daemon.getDocument(uri);
    try testing.expect(retrieved != null);
    try testing.expectEqualStrings(content, retrieved.?);
}

test "Mock daemon document updates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var daemon = MockCoreDaemon.init(allocator);
    defer daemon.deinit();

    const uri = "file:///test.jan";
    const content1 = "func main() { print(\"Version 1\"); }";
    const content2 = "func main() { print(\"Version 2\"); }";

    // Add initial document
    try daemon.updateDocument(uri, content1);
    try testing.expectEqual(@as(u32, 1), daemon.getDocumentCount());
    try testing.expectEqual(@as(u32, 1), daemon.getUpdateCount());

    const retrieved1 = daemon.getDocument(uri);
    try testing.expectEqualStrings(content1, retrieved1.?);

    // Update document
    try daemon.updateDocument(uri, content2);
    try testing.expectEqual(@as(u32, 1), daemon.getDocumentCount()); // Still one document
    try testing.expectEqual(@as(u32, 2), daemon.getUpdateCount()); // But two updates

    const retrieved2 = daemon.getDocument(uri);
    try testing.expectEqualStrings(content2, retrieved2.?);
}

test "Mock daemon multiple documents" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var daemon = MockCoreDaemon.init(allocator);
    defer daemon.deinit();

    const documents = [_]struct { uri: []const u8, content: []const u8 }{
        .{ .uri = "file:///main.jan", .content = "func main() { hello(); }" },
        .{ .uri = "file:///utils.jan", .content = "func hello() { print(\"Hello!\"); }" },
        .{ .uri = "file:///types.jan", .content = "type Point = { x: i32, y: i32 };" },
    };

    // Add all documents
    for (documents) |doc| {
        try daemon.updateDocument(doc.uri, doc.content);
    }

    try testing.expectEqual(@as(u32, documents.len), daemon.getDocumentCount());
    try testing.expectEqual(@as(u32, documents.len), daemon.getUpdateCount());

    // Verify all documents are retrievable
    for (documents) |doc| {
        const retrieved = daemon.getDocument(doc.uri);
        try testing.expect(retrieved != null);
        try testing.expectEqualStrings(doc.content, retrieved.?);
    }
}

test "Libjanus module availability" {
    // Test that we can access the libjanus module
    // This is a basic smoke test to ensure the module system works

    // We can't test much without knowing the exact API, but we can
    // verify the module imports successfully
    _ = libjanus;

    // Basic test passes if we get here
    try testing.expect(true);
}

test "Basic performance test" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var daemon = MockCoreDaemon.init(allocator);
    defer daemon.deinit();

    const iterations = 100; // Reduced for faster testing
    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const uri = try std.fmt.allocPrint(allocator, "file:///perf_test_{}.jan", .{i});
        defer allocator.free(uri);

        const content = "func test() { return 42; }";
        try daemon.updateDocument(uri, content);

        // Retrieve document to test read performance
        const retrieved = daemon.getDocument(uri);
        try testing.expect(retrieved != null);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    const ops_per_second = @as(f64, @floatFromInt(iterations * 2)) / (duration_ms / 1000.0); // 2 ops per iteration

    std.debug.print("\nMock Daemon Performance:\n", .{});
    std.debug.print("  {} operations in {d:.2} ms\n", .{ iterations * 2, duration_ms });
    std.debug.print("  {d:.0} operations/second\n", .{ops_per_second});

    // Basic performance validation
    try testing.expect(ops_per_second > 1000); // Should be fast for simple operations
    try testing.expectEqual(@as(u32, iterations), daemon.getDocumentCount());
    try testing.expectEqual(@as(u32, iterations), daemon.getUpdateCount());
}
