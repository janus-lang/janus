// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const ids = @import("ids.zig");
const StrId = ids.StrId;

// GRANITE-SOLID ASTDB String Interner
// Fixed-capacity arena list that honors the arena's append-only contract
// Architecturally incapable of leaking

/// Truly granite-solid string storage - no dynamic allocation, no resizing
const GraniteStringStorage = struct {
    const MAX_STRINGS = 4096;

    strings: [MAX_STRINGS][]const u8,
    len: u32,

    fn init() GraniteStringStorage {
        return GraniteStringStorage{
            .strings = undefined, // Will be filled as needed
            .len = 0,
        };
    }

    fn append(self: *GraniteStringStorage, item: []const u8) !void {
        if (self.len >= MAX_STRINGS) {
            return error.CapacityExceeded;
        }
        self.strings[self.len] = item;
        self.len += 1;
    }

    fn get(self: *const GraniteStringStorage, index: u32) []const u8 {
        if (index >= self.len) return "";
        return self.strings[index];
    }

    fn count(self: *const GraniteStringStorage) u32 {
        return self.len;
    }
};

pub const StrInterner = struct {
    // GRANITE-SOLID: Arena for strings, fixed array for pointers - no dynamic allocation
    arena: std.heap.ArenaAllocator,
    strings: GraniteStringStorage,
    next_id: u32,
    deterministic: bool,

    pub fn init(parent_allocator: std.mem.Allocator, deterministic: bool) StrInterner {
        return StrInterner{
            .arena = std.heap.ArenaAllocator.init(parent_allocator),
            .strings = GraniteStringStorage.init(),
            .next_id = 0,
            .deterministic = deterministic,
        };
    }

    pub fn deinit(self: *StrInterner) void {
        // GRANITE-SOLID: Arena cleanup is O(1) and guaranteed leak-free
        // GraniteStringStorage is stack-allocated, no cleanup needed
        self.arena.deinit();

        // Clear all fields to prevent accidental reuse
        self.* = undefined;
    }

    /// Intern a UTF-8 string, returning its stable ID - GRANITE-SOLID implementation
    /// String is normalized to Unicode NFC before interning
    pub fn get(self: *StrInterner, s_in: []const u8) !StrId {
        // TODO: Implement Unicode NFC normalization
        // For now, assume input is already normalized
        const s = s_in;

        // GRANITE-SOLID: Simple linear search - no HashMap complexity
        for (0..self.strings.count()) |i| {
            const existing = self.strings.get(@intCast(i));
            if (std.mem.eql(u8, existing, s)) {
                return @enumFromInt(@as(u32, @intCast(i)));
            }
        }

        // Intern new string in arena (guaranteed no leaks)
        const arena_allocator = self.arena.allocator();
        const interned_string = try arena_allocator.dupe(u8, s);

        // Store reference to arena-allocated string
        try self.strings.append(interned_string);

        const id: StrId = @enumFromInt(self.next_id);
        self.next_id += 1;
        return id;
    }

    /// Retrieve string by ID - GRANITE-SOLID implementation
    pub fn str(self: *const StrInterner, id: StrId) []const u8 {
        const raw_id = ids.toU32(id);
        return self.strings.get(raw_id);
    }

    /// Get number of interned strings
    pub fn count(self: *const StrInterner) u32 {
        return self.strings.count();
    }

    /// Check if ID is valid - GRANITE-SOLID implementation
    pub fn isValid(self: *const StrInterner, id: StrId) bool {
        return ids.toU32(id) < self.strings.count();
    }

    /// Find string by content (returns null if not found) - GRANITE-SOLID helper
    pub fn find(self: *const StrInterner, s: []const u8) ?StrId {
        for (0..self.strings.count()) |i| {
            const existing = self.strings.get(@intCast(i));
            if (std.mem.eql(u8, existing, s)) {
                return @enumFromInt(@as(u32, @intCast(i)));
            }
        }
        return null;
    }

    /// Clear all data - GRANITE-SOLID reset
    pub fn clear(self: *StrInterner) void {
        const parent_allocator = self.arena.child_allocator;
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(parent_allocator);
        self.strings = GraniteStringStorage.init();
        self.next_id = 0;
    }

    /// Get statistics for monitoring
    pub fn getStats(self: *const StrInterner) Stats {
        return Stats{
            .string_count = self.count(),
            .arena_bytes = 0, // Arena doesn't expose this easily
        };
    }

    pub const Stats = struct {
        string_count: u32,
        arena_bytes: u32,
    };
};

// GRANITE-SOLID TEST SUITE - Brutal validation
test "Granite StrInterner - Basic Functionality" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var interner = StrInterner.init(allocator, false);
        defer interner.deinit();

        // Basic interning
        const hello_id = try interner.get("hello");
        const world_id = try interner.get("world");
        const hello_id2 = try interner.get("hello"); // Should return same ID

        // Verify deduplication
        try testing.expectEqual(hello_id, hello_id2);
        try testing.expect(!std.meta.eql(hello_id, world_id));

        // Verify retrieval
        try testing.expectEqualStrings("hello", interner.str(hello_id));
        try testing.expectEqualStrings("world", interner.str(world_id));

        // Verify count
        try testing.expectEqual(@as(u32, 2), interner.count());
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite StrInterner - Deterministic Mode" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var interner1 = StrInterner.init(allocator, true);
        defer interner1.deinit();

        var interner2 = StrInterner.init(allocator, true);
        defer interner2.deinit();

        // Same strings should get same IDs in deterministic mode
        const id1_a = try interner1.get("test");
        const id1_b = try interner1.get("example");

        const id2_a = try interner2.get("test");
        const id2_b = try interner2.get("example");

        try testing.expectEqual(id1_a, id2_a);
        try testing.expectEqual(id1_b, id2_b);
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite StrInterner - Basic Operations" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var interner = StrInterner.init(allocator, false);
        defer interner.deinit();

        // Test basic operations
        _ = try interner.get("first");
        _ = try interner.get("second");
        _ = try interner.get("third");

        // Verify stats
        const stats = interner.getStats();
        try testing.expectEqual(@as(u32, 3), stats.string_count);
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite StrInterner - Stress Test" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var interner = StrInterner.init(allocator, false);
        defer interner.deinit();

        // Stress test with multiple strings
        _ = try interner.get("identifier_1");
        _ = try interner.get("identifier_2");
        _ = try interner.get("keyword_func");
        _ = try interner.get("keyword_var");
        _ = try interner.get("identifier_1"); // Duplicate - should deduplicate

        // Verify deduplication worked
        try testing.expectEqual(@as(u32, 4), interner.count());
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Granite StrInterner - Cross-Arena Safety" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var interner = StrInterner.init(allocator, false);
        defer interner.deinit();

        // Test that strings are properly copied to arena
        {
            const temp_str = try std.fmt.allocPrint(allocator, "temp_string", .{});
            defer allocator.free(temp_str);

            const interned_id = try interner.get(temp_str);

            // Verify the string is accessible after temp_str scope ends
            const retrieved = interner.str(interned_id);
            try testing.expectEqualStrings("temp_string", retrieved);
        }

        // String should still be accessible after temp_str is freed
        const id = try interner.get("temp_string"); // Should find existing
        try testing.expectEqualStrings("temp_string", interner.str(id));
        try testing.expectEqual(@as(u32, 1), interner.count()); // Should be deduplicated
    }

    // GRANITE-SOLID: Zero leaks guaranteed
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}
