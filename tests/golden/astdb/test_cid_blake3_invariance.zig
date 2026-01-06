// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Golden Test: CID Invariance with BLAKE3-256
// Task 1.3: CID computation - Tests for comment/whitespace deltas
// Requirements: SPEC-astdb-query.md section E-1, E-2

const std = @import("std");
const testing = std.testing;

// Import from the build system's module path
const janus = @import("janus_lib");
const astdb = janus.astdb;
const cid = astdb.cid;
const canon = astdb.canon;
const interner = astdb.interner;
const snapshot = astdb.snapshot;

test "Golden: CID invariance under whitespace changes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create two snapshots with identical semantic content but different whitespace
    var str_interner1 = interner.StrInterner.init(allocator, true);
    defer str_interner1.deinit();
    var ss1 = try snapshot.Snapshot.init(allocator, &str_interner1);
    defer ss1.deinit();

    var str_interner2 = interner.StrInterner.init(allocator, true);
    defer str_interner2.deinit();
    var ss2 = try snapshot.Snapshot.init(allocator, &str_interner2);
    defer ss2.deinit();

    // Scenario 1: Integer literal "42" at different positions
    const literal_str1 = try str_interner1.get("42");
    const token_id1 = try ss1.addToken(.int_literal, literal_str1, snapshot.Span{
        .start_byte = 0,
        .end_byte = 2,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 3,
    });
    const node_id1 = try ss1.addNode(.int_literal, token_id1, token_id1, &[_]snapshot.NodeId{});

    const literal_str2 = try str_interner2.get("42");
    const token_id2 = try ss2.addToken(.int_literal, literal_str2, snapshot.Span{
        .start_byte = 100, // Different position due to whitespace
        .end_byte = 102,
        .start_line = 5, // Different line due to comments
        .start_col = 10, // Different column due to indentation
        .end_line = 5,
        .end_col = 12,
    });
    const node_id2 = try ss2.addNode(.int_literal, token_id2, token_id2, &[_]snapshot.NodeId{});

    // CIDs should be identical despite different source positions
    const opts = canon.Canon.Opts{ .deterministic = true };
    const cid1 = try canon.computeCID(&ss1, .{ .node = node_id1 }, opts);
    const cid2 = try canon.computeCID(&ss2, .{ .node = node_id2 }, opts);

    try testing.expectEqualSlices(u8, &cid1, &cid2);
}

test "Golden: CID sensitivity to semantic changes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();
    var ss = try snapshot.Snapshot.init(allocator, &str_interner);
    defer ss.deinit();

    // Create two nodes with different semantic content
    const literal_str1 = try str_interner.get("42");
    const token_id1 = try ss.addToken(.int_literal, literal_str1, snapshot.Span{
        .start_byte = 0,
        .end_byte = 2,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 3,
    });
    const node_id1 = try ss.addNode(.int_literal, token_id1, token_id1, &[_]snapshot.NodeId{});

    const literal_str2 = try str_interner.get("43"); // Different value
    const token_id2 = try ss.addToken(.int_literal, literal_str2, snapshot.Span{
        .start_byte = 0,
        .end_byte = 2,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 3,
    });
    const node_id2 = try ss.addNode(.int_literal, token_id2, token_id2, &[_]snapshot.NodeId{});

    // CIDs should be different for different semantic content
    const opts = canon.Canon.Opts{ .deterministic = true };
    const cid1 = try canon.computeCID(&ss, .{ .node = node_id1 }, opts);
    const cid2 = try canon.computeCID(&ss, .{ .node = node_id2 }, opts);

    try testing.expect(!std.mem.eql(u8, &cid1, &cid2));
}

test "Golden: BLAKE3-256 CID format validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();
    var ss = try snapshot.Snapshot.init(allocator, &str_interner);
    defer ss.deinit();

    // Create a test node
    const test_str = try str_interner.get("test");
    const token_id = try ss.addToken(.identifier, test_str, snapshot.Span{
        .start_byte = 0,
        .end_byte = 4,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 5,
    });
    const node_id = try ss.addNode(.identifier, token_id, token_id, &[_]snapshot.NodeId{});

    // Compute CID
    const opts = canon.Canon.Opts{};
    const computed_cid = try canon.computeCID(&ss, .{ .node = node_id }, opts);

    // Validate CID properties
    try testing.expectEqual(@as(usize, 32), computed_cid.len); // BLAKE3-256 = 32 bytes
    try testing.expect(!cid.CIDUtils.isZero(computed_cid));

    // Test CID utilities
    const hex_str = try cid.CIDUtils.format(computed_cid, allocator);
    defer allocator.free(hex_str);

    try testing.expectEqual(@as(usize, 64), hex_str.len); // 32 bytes * 2 hex chars

    const parsed_cid = try cid.CIDUtils.parse(hex_str);
    try testing.expectEqualSlices(u8, &computed_cid, &parsed_cid);
}

test "Golden: CID determinism across toolchain options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();
    var ss = try snapshot.Snapshot.init(allocator, &str_interner);
    defer ss.deinit();

    // Create a test node
    const func_str = try str_interner.get("main");
    const token_id = try ss.addToken(.identifier, func_str, snapshot.Span{
        .start_byte = 0,
        .end_byte = 4,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 5,
    });
    const node_id = try ss.addNode(.func_decl, token_id, token_id, &[_]snapshot.NodeId{});

    // Test different toolchain options produce different CIDs
    const opts1 = canon.Canon.Opts{
        .deterministic = true,
        .toolchain_version = 1,
        .profile_mask = 0,
        .effect_mask = 0,
    };

    const opts2 = canon.Canon.Opts{
        .deterministic = true,
        .toolchain_version = 2, // Different version
        .profile_mask = 0,
        .effect_mask = 0,
    };

    const opts3 = canon.Canon.Opts{
        .deterministic = true,
        .toolchain_version = 1,
        .profile_mask = 1, // Different profile
        .effect_mask = 0,
    };

    const cid1 = try canon.computeCID(&ss, .{ .node = node_id }, opts1);
    const cid2 = try canon.computeCID(&ss, .{ .node = node_id }, opts2);
    const cid3 = try canon.computeCID(&ss, .{ .node = node_id }, opts3);

    // Different options should produce different CIDs
    try testing.expect(!std.mem.eql(u8, &cid1, &cid2));
    try testing.expect(!std.mem.eql(u8, &cid1, &cid3));
    try testing.expect(!std.mem.eql(u8, &cid2, &cid3));

    // Same options should produce same CIDs
    const cid1_repeat = try canon.computeCID(&ss, .{ .node = node_id }, opts1);
    try testing.expectEqualSlices(u8, &cid1, &cid1_repeat);
}

test "Golden: CID cache performance validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();
    var ss = try snapshot.Snapshot.init(allocator, &str_interner);
    defer ss.deinit();

    var cache = cid.CIDCache.init(allocator);
    defer cache.deinit();

    // Create multiple nodes
    const nodes = [_]snapshot.NodeId{
        blk: {
            const str_id = try str_interner.get("node1");
            const token_id = try ss.addToken(.identifier, str_id, snapshot.Span{
                .start_byte = 0,
                .end_byte = 5,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 6,
            });
            break :blk try ss.addNode(.identifier, token_id, token_id, &[_]snapshot.NodeId{});
        },
        blk: {
            const str_id = try str_interner.get("node2");
            const token_id = try ss.addToken(.identifier, str_id, snapshot.Span{
                .start_byte = 6,
                .end_byte = 11,
                .start_line = 1,
                .start_col = 7,
                .end_line = 1,
                .end_col = 12,
            });
            break :blk try ss.addNode(.identifier, token_id, token_id, &[_]snapshot.NodeId{});
        },
    };

    const opts = canon.Canon.Opts{};

    // First access should populate cache
    for (nodes) |node_id| {
        _ = try cache.getCID(&ss, node_id, opts);
    }

    const stats_after_populate = cache.stats();
    try testing.expectEqual(@as(u32, 2), stats_after_populate.entries);

    // Second access should hit cache
    for (nodes) |node_id| {
        _ = try cache.getCID(&ss, node_id, opts);
    }

    const stats_after_reaccess = cache.stats();
    try testing.expectEqual(@as(u32, 2), stats_after_reaccess.entries); // No new entries
}
