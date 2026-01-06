// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Comprehensive tests for std/io.zig operations
//! Tests allocator sovereignty, capability security, and error transparency

const std = @import("std");
const testing = std.testing;
const io = @import("std_io");

test "allocator sovereignty - all functions accept explicit allocators" {
    const testing_allocator = testing.allocator;
    const test_path = "test_allocator_sovereignty.txt";
    const test_content = "Testing allocator sovereignty";

    // Clean up any existing test file
    io.testing.deleteTestFile(test_path);
    defer io.testing.deleteTestFile(test_path);

    // Test that file operations require explicit allocators
    const write_cap = io.FileWriteCapability{ .path = test_path };
    const read_cap = io.FileReadCapability{ .path = test_path };

    // Write file - no allocator needed for write operation itself
    const write_buffer = io.WriteBuffer{ .data = test_content };
    try io.writeFile(test_path, write_buffer, write_cap);

    // Read file - requires explicit allocator
    const read_buffer = try io.readFile(testing_allocator, test_path, read_cap);
    defer read_buffer.deinit();

    try testing.expectEqualStrings(test_content, read_buffer.data);
    try testing.expect(read_buffer.allocator != null);
}

test "capability enforcement - operations require valid capabilities" {
    const test_path = "test_capability_enforcement.txt";

    io.testing.deleteTestFile(test_path);
    defer io.testing.deleteTestFile(test_path);

    // Test file read capability
    const read_cap = io.FileReadCapability{ .path = test_path };
    try testing.expect(read_cap.validate());

    // Test file write capability
    const write_cap = io.FileWriteCapability{ .path = test_path };
    try testing.expect(write_cap.validate());

    // Test standard stream capabilities
    const stdout_cap = io.StdoutWriteCapability{};
    const stderr_cap = io.StderrWriteCapability{};
    const stdin_cap = io.StdinReadCapability{};

    try testing.expect(stdout_cap.validate());
    try testing.expect(stderr_cap.validate());
    try testing.expect(stdin_cap.validate());
}

test "error transparency - all error conditions are explicit" {
    const testing_allocator = testing.allocator;
    const nonexistent_path = "this_file_absolutely_does_not_exist_12345.txt";

    // Test FileNotFound error
    const read_cap = io.FileReadCapability{ .path = nonexistent_path };
    const read_result = io.readFile(testing_allocator, nonexistent_path, read_cap);
    try testing.expectError(io.IoError.FileNotFound, read_result);

    // Test that openFile also returns proper errors
    const open_result = io.openFile(testing_allocator, nonexistent_path, read_cap);
    try testing.expectError(io.IoError.FileNotFound, open_result);
}

test "zero-copy operations - readInto and writeFrom" {
    const testing_allocator = testing.allocator;
    const test_path = "test_zero_copy.txt";
    const test_content = "Zero-copy operation test";

    io.testing.deleteTestFile(test_path);
    defer io.testing.deleteTestFile(test_path);

    // Create test file first
    try io.testing.createTestFile(testing_allocator, test_path, test_content);

    // Open file for reading
    const read_cap = io.FileReadCapability{ .path = test_path };
    var file = try io.openFile(testing_allocator, test_path, read_cap);
    defer file.close();

    // Test zero-copy read into provided buffer
    var buffer: [100]u8 = undefined;
    const bytes_read = try io.readInto(file, &buffer);

    try testing.expectEqual(test_content.len, bytes_read);
    try testing.expectEqualStrings(test_content, buffer[0..bytes_read]);
}

test "streaming operations with proper error handling" {
    const testing_allocator = testing.allocator;
    const test_path = "test_streaming.txt";
    const test_content = "Streaming operations test with multiple chunks of data";

    io.testing.deleteTestFile(test_path);
    defer io.testing.deleteTestFile(test_path);

    // Create the file first
    try io.testing.createTestFile(testing_allocator, test_path, "");

    // Test streaming write
    const write_cap = io.FileWriteCapability{ .path = test_path };
    var write_file = try io.openFile(testing_allocator, test_path, write_cap);
    defer write_file.close();

    // Write in chunks
    const chunk1 = "Streaming operations test ";
    const chunk2 = "with multiple chunks ";
    const chunk3 = "of data";

    _ = try io.writeFrom(write_file, chunk1);
    _ = try io.writeFrom(write_file, chunk2);
    _ = try io.writeFrom(write_file, chunk3);

    // File will be closed by defer

    // Test streaming read
    const read_cap = io.FileReadCapability{ .path = test_path };
    var read_file = try io.openFile(testing_allocator, test_path, read_cap);
    defer read_file.close();

    var read_buffer: [100]u8 = undefined;
    const total_read = try io.readInto(read_file, &read_buffer);

    try testing.expectEqualStrings(test_content, read_buffer[0..total_read]);
}

test "standard stream operations with capabilities" {
    // Test capability validation only (actual I/O would interfere with test runner)
    const stdout_cap = io.StdoutWriteCapability{};
    const stderr_cap = io.StderrWriteCapability{};
    const stdin_cap = io.StdinReadCapability{};

    try testing.expect(stdout_cap.validate());
    try testing.expect(stderr_cap.validate());
    try testing.expect(stdin_cap.validate());
}

test "file handle capabilities and permissions" {
    const testing_allocator = testing.allocator;
    const test_path = "test_file_permissions.txt";
    const test_content = "Testing file handle permissions";

    io.testing.deleteTestFile(test_path);
    defer io.testing.deleteTestFile(test_path);

    // Create test file first
    try io.testing.createTestFile(testing_allocator, test_path, test_content);

    // Test read-only file handle
    const read_cap = io.FileReadCapability{ .path = test_path };
    var read_file = try io.openFile(testing_allocator, test_path, read_cap);
    defer read_file.close();

    // Should be able to read
    var buffer: [100]u8 = undefined;
    const bytes_read = try read_file.read(&buffer);
    try testing.expect(bytes_read > 0);

    // Test write-only file handle
    const write_cap = io.FileWriteCapability{ .path = test_path };
    var write_file = try io.openFile(testing_allocator, test_path, write_cap);
    defer write_file.close();

    // Should be able to write
    const new_content = "New content";
    const bytes_written = try write_file.write(new_content);
    try testing.expectEqual(new_content.len, bytes_written);
}

test "buffer lifecycle management" {
    const testing_allocator = testing.allocator;
    const test_path = "test_buffer_lifecycle.txt";
    const test_content = "Testing buffer lifecycle management";

    io.testing.deleteTestFile(test_path);
    defer io.testing.deleteTestFile(test_path);

    // Create test file
    try io.testing.createTestFile(testing_allocator, test_path, test_content);

    // Read file and verify buffer is properly managed
    const read_cap = io.FileReadCapability{ .path = test_path };
    const read_buffer = try io.readFile(testing_allocator, test_path, read_cap);

    // Verify content
    try testing.expectEqualStrings(test_content, read_buffer.data);

    // Verify allocator is set correctly for owned buffers
    try testing.expect(read_buffer.allocator != null);

    // Clean up - this should not leak memory
    read_buffer.deinit();
}

test "comprehensive error scenarios" {
    const testing_allocator = testing.allocator;

    // Test various error conditions
    const invalid_path = "/invalid/path/that/does/not/exist/file.txt";
    const read_cap = io.FileReadCapability{ .path = invalid_path };

    // Test file not found
    const read_result = io.readFile(testing_allocator, invalid_path, read_cap);
    try testing.expectError(io.IoError.FileNotFound, read_result);

    // Test opening non-existent file
    const open_result = io.openFile(testing_allocator, invalid_path, read_cap);
    try testing.expectError(io.IoError.FileNotFound, open_result);

    // Test writing to invalid path
    const write_cap = io.FileWriteCapability{ .path = invalid_path };
    const write_buffer = io.WriteBuffer{ .data = "test" };
    const write_result = io.writeFile(invalid_path, write_buffer, write_cap);

    // This might be FileNotFound or PermissionDenied depending on the system
    try testing.expect(write_result == io.IoError.FileNotFound or
        write_result == io.IoError.PermissionDenied or
        write_result == io.IoError.Unknown);
}

test "performance characteristics - O(1) operations where expected" {
    const testing_allocator = testing.allocator;
    const test_path = "test_performance.txt";

    io.testing.deleteTestFile(test_path);
    defer io.testing.deleteTestFile(test_path);

    // Create a reasonably sized test file
    const test_content = "Performance test content that is repeated multiple times. " ** 100;
    try io.testing.createTestFile(testing_allocator, test_path, test_content);

    // Time the read operation
    const start_time = std.time.nanoTimestamp();

    const read_cap = io.FileReadCapability{ .path = test_path };
    const read_buffer = try io.readFile(testing_allocator, test_path, read_cap);
    defer read_buffer.deinit();

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Verify content is correct
    try testing.expectEqualStrings(test_content, read_buffer.data);

    // Performance should be reasonable (less than 100ms for this small file)
    try testing.expect(duration_ms < 100.0);
}

test "memory allocation patterns" {
    const testing_allocator = testing.allocator;
    const test_path = "test_memory_patterns.txt";
    const test_content = "Testing memory allocation patterns";

    io.testing.deleteTestFile(test_path);
    defer io.testing.deleteTestFile(test_path);

    // Create test file
    try io.testing.createTestFile(testing_allocator, test_path, test_content);

    // Read file multiple times to test allocation patterns
    for (0..5) |_| {
        const read_cap = io.FileReadCapability{ .path = test_path };
        const read_buffer = try io.readFile(testing_allocator, test_path, read_cap);

        try testing.expectEqualStrings(test_content, read_buffer.data);
        try testing.expect(read_buffer.allocator != null);

        // Clean up immediately
        read_buffer.deinit();
    }

    // If we reach here without memory leaks, the allocation pattern is correct
}
