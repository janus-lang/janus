// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Channel Integration Tests - Phase 3
//!
//! Tests for CSP-style message passing channels.
//! Validates: send/recv, buffered channels, close semantics, concurrency safety.

const std = @import("std");
const testing = std.testing;

// Import the runtime's Channel type
const janus_rt = @import("janus_rt");
const Channel = janus_rt.Channel;

// ============================================================================
// Basic Channel Operations
// ============================================================================

test "Channel: basic send and recv on buffered channel" {
    const allocator = testing.allocator;

    var ch = try Channel(i64).initBuffered(allocator, 1);
    defer ch.deinit();

    // Send should not block (buffered)
    try ch.send(42);

    // Recv should return the value
    const value = try ch.recv();
    try testing.expectEqual(@as(i64, 42), value);
}

test "Channel: multiple values in buffered channel" {
    const allocator = testing.allocator;

    var ch = try Channel(i64).initBuffered(allocator, 3);
    defer ch.deinit();

    // Send 3 values
    try ch.send(1);
    try ch.send(2);
    try ch.send(3);

    // Receive in FIFO order
    try testing.expectEqual(@as(i64, 1), try ch.recv());
    try testing.expectEqual(@as(i64, 2), try ch.recv());
    try testing.expectEqual(@as(i64, 3), try ch.recv());
}

test "Channel: close prevents further sends" {
    const allocator = testing.allocator;

    var ch = try Channel(i64).initBuffered(allocator, 1);
    defer ch.deinit();

    ch.close();

    // Send on closed channel should error
    const result = ch.send(42);
    try testing.expectError(error.ChannelClosed, result);
}

test "Channel: recv drains buffer before returning closed error" {
    const allocator = testing.allocator;

    var ch = try Channel(i64).initBuffered(allocator, 2);
    defer ch.deinit();

    // Send values then close
    try ch.send(100);
    try ch.send(200);
    ch.close();

    // Should still receive buffered values
    try testing.expectEqual(@as(i64, 100), try ch.recv());
    try testing.expectEqual(@as(i64, 200), try ch.recv());

    // Now should error
    const result = ch.recv();
    try testing.expectError(error.ChannelClosed, result);
}

test "Channel: trySend returns false when full" {
    const allocator = testing.allocator;

    var ch = try Channel(i64).initBuffered(allocator, 1);
    defer ch.deinit();

    // First send succeeds
    const sent1 = try ch.trySend(1);
    try testing.expect(sent1);

    // Second send fails (buffer full)
    const sent2 = try ch.trySend(2);
    try testing.expect(!sent2);

    // Recv frees space
    _ = try ch.recv();

    // Now can send again
    const sent3 = try ch.trySend(3);
    try testing.expect(sent3);
}

test "Channel: tryRecv returns null when empty" {
    const allocator = testing.allocator;

    var ch = try Channel(i64).initBuffered(allocator, 1);
    defer ch.deinit();

    // Empty channel returns null
    const maybe_value = try ch.tryRecv();
    try testing.expect(maybe_value == null);

    // Send a value
    try ch.send(42);

    // Now returns value
    const value = try ch.tryRecv();
    try testing.expectEqual(@as(?i64, 42), value);
}

test "Channel: len reports current buffer count" {
    const allocator = testing.allocator;

    var ch = try Channel(i64).initBuffered(allocator, 5);
    defer ch.deinit();

    try testing.expectEqual(@as(usize, 0), ch.len());

    try ch.send(1);
    try testing.expectEqual(@as(usize, 1), ch.len());

    try ch.send(2);
    try ch.send(3);
    try testing.expectEqual(@as(usize, 3), ch.len());

    _ = try ch.recv();
    try testing.expectEqual(@as(usize, 2), ch.len());
}

test "Channel: isClosed reports state correctly" {
    const allocator = testing.allocator;

    var ch = try Channel(i64).initBuffered(allocator, 1);
    defer ch.deinit();

    try testing.expect(!ch.isClosed());

    ch.close();

    try testing.expect(ch.isClosed());
}

// ============================================================================
// Concurrent Channel Operations
// ============================================================================

test "Channel: producer-consumer pattern" {
    const allocator = testing.allocator;

    var ch = try Channel(i64).initBuffered(allocator, 10);
    defer ch.deinit();

    const num_items: i64 = 100;
    var sum: i64 = 0;

    // Producer thread
    const producer = try std.Thread.spawn(.{}, struct {
        fn produce(channel: *Channel(i64), count: i64) void {
            var i: i64 = 1;
            while (i <= count) : (i += 1) {
                channel.send(i) catch break;
            }
            channel.close();
        }
    }.produce, .{ ch, num_items });

    // Consumer (main thread)
    while (true) {
        const value = ch.recv() catch break;
        sum += value;
    }

    producer.join();

    // Sum of 1..100 = 5050
    try testing.expectEqual(@as(i64, 5050), sum);
}

test "Channel: multiple producers single consumer" {
    const allocator = testing.allocator;

    const num_producers = 4;
    const items_per_producer: i64 = 25;
    const total_items: i64 = num_producers * items_per_producer;

    // Buffer large enough to hold all items (avoids deadlock when joining before consuming)
    var ch = try Channel(i64).initBuffered(allocator, @as(usize, @intCast(total_items)));
    defer ch.deinit();

    var threads: [num_producers]std.Thread = undefined;

    // Start producers
    for (0..num_producers) |i| {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn produce(channel: *Channel(i64), producer_id: usize, count: i64) void {
                _ = producer_id;
                var j: i64 = 0;
                while (j < count) : (j += 1) {
                    channel.send(1) catch break;
                }
            }
        }.produce, .{ ch, i, items_per_producer });
    }

    // Wait for producers to finish
    for (&threads) |*t| {
        t.join();
    }
    ch.close();

    // Count received items
    var count: i64 = 0;
    while (true) {
        _ = ch.recv() catch break;
        count += 1;
    }

    try testing.expectEqual(total_items, count);
}

// ============================================================================
// C API Tests (for LLVM interop verification)
// ============================================================================

test "Channel C API: create and destroy" {
    const handle = janus_rt.janus_channel_create_i64(5);
    try testing.expect(handle != null);

    janus_rt.janus_channel_destroy_i64(handle);
}

test "Channel C API: send and recv" {
    const handle = janus_rt.janus_channel_create_i64(1);
    defer janus_rt.janus_channel_destroy_i64(handle);

    // Send
    const send_result = janus_rt.janus_channel_send_i64(handle, 42);
    try testing.expectEqual(@as(i32, 0), send_result);

    // Recv
    var err: i32 = 0;
    const value = janus_rt.janus_channel_recv_i64(handle, &err);
    try testing.expectEqual(@as(i32, 0), err);
    try testing.expectEqual(@as(i64, 42), value);
}

test "Channel C API: close and check closed" {
    const handle = janus_rt.janus_channel_create_i64(1);
    defer janus_rt.janus_channel_destroy_i64(handle);

    try testing.expectEqual(@as(i32, 0), janus_rt.janus_channel_is_closed_i64(handle));

    janus_rt.janus_channel_close_i64(handle);

    try testing.expectEqual(@as(i32, 1), janus_rt.janus_channel_is_closed_i64(handle));
}

test "Channel C API: try_send and try_recv" {
    const handle = janus_rt.janus_channel_create_i64(1);
    defer janus_rt.janus_channel_destroy_i64(handle);

    // Try send (should succeed)
    const try_send1 = janus_rt.janus_channel_try_send_i64(handle, 100);
    try testing.expectEqual(@as(i32, 1), try_send1);

    // Try send again (should fail - buffer full)
    const try_send2 = janus_rt.janus_channel_try_send_i64(handle, 200);
    try testing.expectEqual(@as(i32, 0), try_send2);

    // Try recv (should succeed)
    var value: i64 = 0;
    const try_recv = janus_rt.janus_channel_try_recv_i64(handle, &value);
    try testing.expectEqual(@as(i32, 1), try_recv);
    try testing.expectEqual(@as(i64, 100), value);
}

test "Channel C API: len" {
    const handle = janus_rt.janus_channel_create_i64(5);
    defer janus_rt.janus_channel_destroy_i64(handle);

    try testing.expectEqual(@as(i32, 0), janus_rt.janus_channel_len_i64(handle));

    _ = janus_rt.janus_channel_send_i64(handle, 1);
    _ = janus_rt.janus_channel_send_i64(handle, 2);

    try testing.expectEqual(@as(i32, 2), janus_rt.janus_channel_len_i64(handle));
}
