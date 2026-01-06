// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Unit tests for Citadel Protocol serialization/deserialization
//!
//! Tests the core MessagePack protocol that enables communication between
//! janus-core-daemon and janus-grpc-proxy without external dependencies.

const std = @import("std");
const testing = std.testing;
const citadel_protocol = @import("citadel_protocol");

test "Protocol version creation" {
    const version = citadel_protocol.ProtocolVersion.current();
    try testing.expectEqual(@as(u16, 1), version.major);
    try testing.expectEqual(@as(u16, 0), version.coreor);
    try testing.expectEqual(@as(u16, 0), version.patch);
}

test "Protocol version compatibility" {
    const v1 = citadel_protocol.ProtocolVersion{ .major = 1, .coreor = 0, .patch = 0 };
    const v2 = citadel_protocol.ProtocolVersion{ .major = 1, .coreor = 1, .patch = 0 };
    const v3 = citadel_protocol.ProtocolVersion{ .major = 2, .coreor = 0, .patch = 0 };

    try testing.expect(v1.isCompatible(v2)); // Same major version
    try testing.expect(!v1.isCompatible(v3)); // Different major version
}

test "RequestType string conversion" {
    const request_types = [_]citadel_protocol.RequestType{
        .version_request,
        .ping,
        .doc_update,
        .hover_at,
        .definition_at,
        .references_at,
        .shutdown,
    };

    for (request_types) |req_type| {
        const str = req_type.toString();
        const parsed = citadel_protocol.RequestType.fromString(str);
        try testing.expectEqual(req_type, parsed.?);
    }
}

test "Position and Range structures" {
    const pos1 = citadel_protocol.Position{ .line = 10, .character = 25 };
    const pos2 = citadel_protocol.Position{ .line = 10, .character = 30 };

    const range = citadel_protocol.Range{ .start = pos1, .end = pos2 };

    try testing.expectEqual(@as(u32, 10), range.start.line);
    try testing.expectEqual(@as(u32, 25), range.start.character);
    try testing.expectEqual(@as(u32, 30), range.end.character);
}

test "Location structure" {
    const location = citadel_protocol.Location{
        .uri = "file:///test.jan",
        .range = citadel_protocol.Range{
            .start = citadel_protocol.Position{ .line = 1, .character = 5 },
            .end = citadel_protocol.Position{ .line = 1, .character = 10 },
        },
    };

    try testing.expectEqualStrings("file:///test.jan", location.uri);
    try testing.expectEqual(@as(u32, 1), location.range.start.line);
    try testing.expectEqual(@as(u32, 5), location.range.start.character);
}

test "ProtocolError constants" {
    try testing.expectEqualStrings("INVALID_REQUEST", citadel_protocol.ProtocolError.INVALID_REQUEST);
    try testing.expectEqualStrings("DOCUMENT_NOT_FOUND", citadel_protocol.ProtocolError.DOCUMENT_NOT_FOUND);
    try testing.expectEqualStrings("PARSE_ERROR", citadel_protocol.ProtocolError.PARSE_ERROR);
    try testing.expectEqualStrings("INTERNAL_ERROR", citadel_protocol.ProtocolError.INTERNAL_ERROR);
}

test "Request payload structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test DocUpdateRequestPayload
    const doc_update = citadel_protocol.DocUpdateRequestPayload{
        .uri = "file:///test.jan",
        .content = "func main() {}",
        .version = 1,
    };

    try testing.expectEqualStrings("file:///test.jan", doc_update.uri);
    try testing.expectEqualStrings("func main() {}", doc_update.content);
    try testing.expectEqual(@as(?u32, 1), doc_update.version);

    // Test HoverAtRequestPayload
    const hover_at = citadel_protocol.HoverAtRequestPayload{
        .uri = "file:///test.jan",
        .position = citadel_protocol.Position{ .line = 1, .character = 5 },
    };

    try testing.expectEqualStrings("file:///test.jan", hover_at.uri);
    try testing.expectEqual(@as(u32, 1), hover_at.position.line);
    try testing.expectEqual(@as(u32, 5), hover_at.position.character);

    _ = allocator; // Suppress unused variable warning
}

test "Response payload structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test DocUpdateResponsePayload
    const doc_response = citadel_protocol.DocUpdateResponsePayload{
        .success = true,
        .snapshot_id = "snapshot_123",
        .parse_time_ns = 1000000,
        .token_count = 42,
        .node_count = 15,
    };

    try testing.expect(doc_response.success);
    try testing.expectEqualStrings("snapshot_123", doc_response.snapshot_id.?);
    try testing.expectEqual(@as(?u64, 1000000), doc_response.parse_time_ns);
    try testing.expectEqual(@as(?u32, 42), doc_response.token_count);
    try testing.expectEqual(@as(?u32, 15), doc_response.node_count);

    // Test HoverInfo
    const hover_info = citadel_protocol.HoverInfo{
        .markdown = "**function** main() -> void",
        .range = citadel_protocol.Range{
            .start = citadel_protocol.Position{ .line = 1, .character = 1 },
            .end = citadel_protocol.Position{ .line = 1, .character = 10 },
        },
    };

    try testing.expectEqualStrings("**function** main() -> void", hover_info.markdown);
    try testing.expectEqual(@as(u32, 1), hover_info.range.start.line);

    _ = allocator; // Suppress unused variable warning
}

test "Frame size limits" {
    try testing.expectEqual(@as(u32, 16 * 1024 * 1024), citadel_protocol.MAX_MESSAGE_SIZE);
    try testing.expectEqual(@as(u32, 4), citadel_protocol.FRAME_HEADER_SIZE);
}

test "Request timestamp generation" {
    const timestamp1 = citadel_protocol.Request.getTimestamp();
    std.time.sleep(1 * std.time.ns_per_ms); // Sleep 1ms
    const timestamp2 = citadel_protocol.Request.getTimestamp();

    try testing.expect(timestamp2 > timestamp1);
}
