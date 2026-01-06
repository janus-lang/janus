// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const ids = @import("ids.zig");
const snapshot = @import("granite_snapshot.zig");
const canon = @import("canon.zig");

// ASTDB Content ID (CID) - BLAKE3 hashing of normalized semantic content
// Task 1: AST Persistence Layer - Content-addressed storage with deterministic hashing
// Requirements: SPEC-astdb-query.md section 3.2, 5, 9, 10.2

const CID = ids.CID;
const NodeId = ids.NodeId;
const DeclId = ids.DeclId;
const Snapshot = snapshot.Snapshot;
const Canon = canon.Canon;

/// CID computation options that affect hash domain separation
pub const CIDOpts = Canon.Opts;

/// Compute CID for an AST node
pub fn cidOfNode(ss: *const Snapshot, node_id: NodeId, opts: CIDOpts) !CID {
    return canon.computeCID(ss, .{ .node = node_id }, opts);
}

/// Compute CID for a declaration
pub fn cidOfDecl(ss: *const Snapshot, decl_id: DeclId, opts: CIDOpts) !CID {
    return canon.computeCID(ss, .{ .decl = decl_id }, opts);
}

/// Compute CID with default options (deterministic mode)
pub fn cidOf(ss: *const Snapshot, subject: ids.CIDSubject) !CID {
    const opts = CIDOpts{
        .deterministic = true,
        .toolchain_version = 1,
        .profile_mask = 0,
        .effect_mask = 0,
        .safety_level = 1,
        .fastmath = false,
        .target_triple = "unknown-unknown-unknown",
    };
    const canon_opts = canon.Canon.Opts{
        .deterministic = opts.deterministic,
        .toolchain_version = opts.toolchain_version,
        .profile_mask = opts.profile_mask,
        .effect_mask = opts.effect_mask,
        .safety_level = opts.safety_level,
        .fastmath = opts.fastmath,
        .target_triple = opts.target_triple,
    };
    return canon.computeCID(ss, subject, canon_opts);
}

/// CID cache for memoization - maps (NodeId, CIDOpts) -> CID
pub const CIDCache = struct {
    cache: std.HashMap(CacheKey, CID, CacheKeyContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    const CacheKey = struct {
        node_id: NodeId,
        opts_hash: u64,
    };

    const CacheKeyContext = struct {
        pub fn hash(self: @This(), key: CacheKey) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&key.node_id));
            hasher.update(std.mem.asBytes(&key.opts_hash));
            return hasher.final();
        }

        pub fn eql(self: @This(), a: CacheKey, b: CacheKey) bool {
            _ = self;
            return std.meta.eql(a.node_id, b.node_id) and a.opts_hash == b.opts_hash;
        }
    };

    pub fn init(allocator: std.mem.Allocator) CIDCache {
        return CIDCache{
            .cache = std.HashMap(CacheKey, CID, CacheKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CIDCache) void {
        self.cache.deinit();
    }

    /// Get cached CID or compute and cache it
    pub fn getCID(self: *CIDCache, ss: *const Snapshot, node_id: NodeId, opts: CIDOpts) !CID {
        const opts_hash = hashOpts(opts);
        const key = CacheKey{ .node_id = node_id, .opts_hash = opts_hash };

        if (self.cache.get(key)) |cached_cid| {
            return cached_cid;
        }

        // Compute and cache
        const cid = try cidOfNode(ss, node_id, opts);
        try self.cache.put(key, cid);
        return cid;
    }

    /// Clear cache (for testing or memory management)
    pub fn clear(self: *CIDCache) void {
        self.cache.clearRetainingCapacity();
    }

    /// Get cache statistics
    pub fn stats(self: *const CIDCache) struct { entries: u32, capacity: u32 } {
        return .{
            .entries = @as(u32, @intCast(self.cache.count())),
            .capacity = @as(u32, @intCast(self.cache.capacity())),
        };
    }

    fn hashOpts(opts: CIDOpts) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&opts.profile_mask));
        hasher.update(std.mem.asBytes(&opts.effect_mask));
        hasher.update(std.mem.asBytes(&opts.toolchain_version));
        hasher.update(std.mem.asBytes(&opts.safety_level));
        hasher.update(std.mem.asBytes(&opts.fastmath));
        hasher.update(std.mem.asBytes(&opts.deterministic));
        hasher.update(opts.target_triple);
        return hasher.final();
    }
};

/// CID validation and integrity checking
pub const CIDValidator = struct {
    /// Verify that a CID matches the expected content
    pub fn validate(ss: *const Snapshot, subject: ids.CIDSubject, expected_cid: CID, opts: CIDOpts) !bool {
        const computed_cid = try canon.computeCID(ss, subject, opts);
        return std.mem.eql(u8, &expected_cid, &computed_cid);
    }

    /// Batch validate multiple CIDs
    pub fn validateBatch(ss: *const Snapshot, subjects: []const ids.CIDSubject, expected_cids: []const CID, opts: CIDOpts) ![]bool {
        if (subjects.len != expected_cids.len) return error.LengthMismatch;

        var results = try std.heap.page_allocator.alloc(bool, subjects.len);
        for (subjects, expected_cids, 0..) |subject, expected_cid, i| {
            results[i] = try validate(ss, subject, expected_cid, opts);
        }
        return results;
    }
};

/// CID utilities for debugging and analysis
pub const CIDUtils = struct {
    /// Format CID as hex string for debugging
    pub fn format(cid: CID, allocator: std.mem.Allocator) ![]u8 {
        const hex_chars = "0123456789abcdef";
        var result = try allocator.alloc(u8, 64);
        for (cid, 0..) |byte, i| {
            result[i * 2] = hex_chars[byte >> 4];
            result[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        return result;
    }

    /// Parse CID from hex string
    pub fn parse(hex_str: []const u8) !CID {
        if (hex_str.len != 64) return error.InvalidLength; // 32 bytes * 2 hex chars

        var cid: CID = undefined;
        for (0..32) |i| {
            const hex_byte = hex_str[i * 2 .. i * 2 + 2];
            cid[i] = try std.fmt.parseInt(u8, hex_byte, 16);
        }
        return cid;
    }

    /// Compare CIDs for sorting/ordering
    pub fn compare(a: CID, b: CID) std.math.Order {
        return std.mem.order(u8, &a, &b);
    }

    /// Check if CID is zero (invalid/uninitialized)
    pub fn isZero(cid: CID) bool {
        return std.mem.allEqual(u8, &cid, 0);
    }

    /// Generate a zero CID (for testing)
    pub fn zero() CID {
        return [_]u8{0} ** 32;
    }
};

test "CID computation basic" {
    const testing = std.testing;
    const interner = @import("granite_interner.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var ss = try Snapshot.init(allocator, &str_interner);
    defer ss.deinit();

    // Create a simple node
    const hello_str = try str_interner.get("hello");
    const token_id = try ss.addToken(.identifier, hello_str, snapshot.Span{
        .start_byte = 0,
        .end_byte = 5,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 6,
    });

    const node_id = try ss.addNode(.identifier, token_id, token_id, &[_]NodeId{});

    // Compute CID
    const cid = try cidOf(ss, .{ .node = node_id });

    // Verify CID properties
    try testing.expectEqual(@as(usize, 32), cid.len);
    try testing.expect(!CIDUtils.isZero(cid));

    // Same computation should yield same result
    const cid2 = try cidOf(ss, .{ .node = node_id });
    try testing.expectEqualSlices(u8, &cid, &cid2);
}

test "CID cache functionality" {
    const testing = std.testing;
    const interner = @import("granite_interner.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var ss = try Snapshot.init(allocator, &str_interner);
    defer ss.deinit();

    var cache = CIDCache.init(allocator);
    defer cache.deinit();

    // Create a node
    const test_str = try str_interner.get("test");
    const token_id = try ss.addToken(.identifier, test_str, snapshot.Span{
        .start_byte = 0,
        .end_byte = 4,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 5,
    });

    const node_id = try ss.addNode(.identifier, token_id, token_id, &[_]NodeId{});

    const opts = CIDOpts{};

    // First access should compute and cache
    const cid1 = try cache.getCID(ss, node_id, opts);
    const stats1 = cache.stats();
    try testing.expectEqual(@as(u32, 1), stats1.entries);

    // Second access should hit cache
    const cid2 = try cache.getCID(ss, node_id, opts);
    const stats2 = cache.stats();
    try testing.expectEqual(@as(u32, 1), stats2.entries); // No new entries

    // CIDs should be identical
    try testing.expectEqualSlices(u8, &cid1, &cid2);
}

test "CID validation" {
    const testing = std.testing;
    const interner = @import("granite_interner.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var str_interner = interner.StrInterner.init(allocator, true);
    defer str_interner.deinit();

    var ss = try Snapshot.init(allocator, &str_interner);
    defer ss.deinit();

    // Create a node
    const value_str = try str_interner.get("42");
    const token_id = try ss.addToken(.int_literal, value_str, snapshot.Span{
        .start_byte = 0,
        .end_byte = 2,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 3,
    });

    const node_id = try ss.addNode(.int_literal, token_id, token_id, &[_]NodeId{});

    const opts = CIDOpts{};
    const cid = try cidOfNode(ss, node_id, opts);

    // Validation should pass for correct CID
    try testing.expect(try CIDValidator.validate(ss, .{ .node = node_id }, cid, opts));

    // Validation should fail for incorrect CID
    const wrong_cid = CIDUtils.zero();
    try testing.expect(!try CIDValidator.validate(ss, .{ .node = node_id }, wrong_cid, opts));
}

test "CID utilities" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test zero CID
    const zero_cid = CIDUtils.zero();
    try testing.expect(CIDUtils.isZero(zero_cid));

    // Test format and parse
    var test_cid: CID = undefined;
    for (0..32) |i| {
        test_cid[i] = @as(u8, @intCast(i));
    }

    const hex_str = try CIDUtils.format(test_cid, allocator);
    defer allocator.free(hex_str);

    const parsed_cid = try CIDUtils.parse(hex_str);
    try testing.expectEqualSlices(u8, &test_cid, &parsed_cid);

    // Test comparison
    const cid_a = CIDUtils.zero();
    var cid_b = CIDUtils.zero();
    cid_b[0] = 1;

    try testing.expectEqual(std.math.Order.lt, CIDUtils.compare(cid_a, cid_b));
    try testing.expectEqual(std.math.Order.gt, CIDUtils.compare(cid_b, cid_a));
    try testing.expectEqual(std.math.Order.eq, CIDUtils.compare(cid_a, cid_a));
}
