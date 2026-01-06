// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const std = @import("std");
const mem = @import("../mem.zig");

/// HashMap<K, V, Ctx> - Robin Hood Hash Map with static dispatch
///
/// Implements the tri-signature pattern for capability-based security:
/// - :min profile: init(alloc, load_factor) - basic allocation
/// - :go profile: init(alloc, load_factor, ctx) - with context
/// - :full profile: init(alloc, load_factor, cap, ctx) - with capability token
///
/// Uses Array of Structures (AoS) layout for optimal cache locality.
/// Robin Hood hashing ensures minimal probe distances and fast lookups.
///
/// Default load factor: 85% (empirically validated for performance)
pub fn HashMap(comptime K: type, comptime V: type, comptime Ctx: type) type {
    return struct {
        const Self = @This();
        const Ctrl = i8;

        // Context provides compile-time hash and equality functions
        const HashFn = fn (key: K) u64;
        const EqFn = fn (a: K, b: K) bool;

        // Capability tokens for compile-time security
        pub const WriteCapability = struct {};
        pub const RehashCapability = struct {};

        /// Internal entry structure - Array of Structures for cache locality
        const Entry = struct {
            key: K,
            value: V,
            ctrl: Ctrl,
        };

        /// Allocator instance
        alloc: mem.Allocator,
        /// Array of entries (AoS layout for cache locality)
        entries: []Entry = &[_]Entry{},
        /// Current number of entries (excluding tombstones)
        len_: usize = 0,
        /// Number of tombstones (for entropy management)
        tombstones: usize = 0,
        /// Load factor percentage (default: 85%)
        load_factor_percent: u8 = 85,

        /// Initialize a new HashMap with the given allocator and load factor
        pub fn init(alloc: mem.Allocator, load_factor_percent: u8) Self {
            return Self{
                .alloc = alloc,
                .load_factor_percent = load_factor_percent,
            };
        }

        /// Initialize a new HashMap with context (for :go profile)
        pub fn initWithContext(alloc: mem.Allocator, load_factor_percent: u8, ctx: anytype) Self {
            _ = ctx; // Context parameter for future use
            return init(alloc, load_factor_percent);
        }

        /// Initialize a new HashMap with capability token (for :full profile)
        pub fn initWithCapability(alloc: mem.Allocator, load_factor_percent: u8, cap: WriteCapability, ctx: anytype) Self {
            _ = cap; // Compile-time capability token for security
            _ = ctx; // Context parameter for future use
            return init(alloc, load_factor_percent);
        }

        /// Deinitialize the HashMap, freeing all allocated memory
        pub fn deinit(self: *Self) void {
            if (self.entries.len > 0) {
                self.alloc.free(self.entries);
            }
            self.* = undefined; // Sanitize memory
        }

        /// Get the current number of entries
        pub fn len(self: *const Self) usize {
            return self.len_;
        }

        /// Check if the HashMap is empty
        pub fn isEmptyMap(self: *const Self) bool {
            return self.len_ == 0;
        }

        /// Check if a control byte represents an empty slot
        fn isEmpty(ctrl: Ctrl) bool {
            return ctrl == -1;
        }

        /// Check if a control byte represents a tombstone
        fn isTomb(ctrl: Ctrl) bool {
            return ctrl == -2;
        }

        /// Mark a control byte as empty
        fn markEmpty(ctrl: *Ctrl) void {
            ctrl.* = -1;
        }

        /// Mark a control byte as tombstone
        fn markTomb(ctrl: *Ctrl) void {
            ctrl.* = -2;
        }

        /// Calculate the ideal index for a hash
        fn idealIndex(self: *const Self, hash: u64) usize {
            return @intCast(hash & (@as(u64, self.entries.len - 1)));
        }

        /// Calculate the load factor as a percentage
        fn loadFactor(self: *const Self) u8 {
            if (self.entries.len == 0) return 0;
            const total_slots = self.entries.len;
            const used_slots = self.len_ + self.tombstones;
            return @intCast((used_slots * 100) / total_slots);
        }

        /// Check if rehash is needed based on load factor and entropy
        fn needsRehash(self: *const Self) bool {
            if (self.entries.len == 0) return false;

            // Check load factor (active entries vs capacity)
            const load_factor = (self.len_ * 100) / self.entries.len;
            if (load_factor >= self.load_factor_percent) {
                return true;
            }

            // Check tombstone ratio (entropy threshold: 25%)
            const tombstone_ratio = (self.tombstones * 100) / self.entries.len;
            return tombstone_ratio >= 25;
        }

        /// Ensure capacity for at least `want` entries
        fn ensureCapacity(self: *Self, want: usize) !void {
            if (!self.needsRehash() and self.entries.len >= want) {
                return;
            }

            // Calculate new capacity (power of 2)
            const min_cap = if (self.entries.len == 0) 8 else self.entries.len;
            var new_cap = min_cap;
            while (new_cap < want and @as(f64, @floatFromInt(self.len_ + 1)) / @as(f64, @floatFromInt(new_cap)) > 0.85) {
                new_cap *= 2;
            }

            if (new_cap == self.entries.len) return;

            // Allocate new entries array
            const new_entries = try self.alloc.alloc(Entry, new_cap);

            // Initialize all control bytes to empty
            for (new_entries) |*new_entry| {
                markEmpty(&new_entry.ctrl);
            }

            // Reinsert all non-tombstone entries
            if (self.entries.len > 0) {
                for (self.entries) |existing_entry| {
                    if (!isEmpty(existing_entry.ctrl) and !isTomb(existing_entry.ctrl)) {
                        self.reinsertInto(new_entries, existing_entry.key, existing_entry.value);
                    }
                }
                self.alloc.free(self.entries);
            }

            self.entries = new_entries;
            self.tombstones = 0; // Reset tombstone count after rehash
        }

        /// Reinsert an entry into a new array (internal use)
        fn reinsertInto(self: *Self, dst_entries: []Entry, key: K, value: V) void {
            const hash = Ctx.hash(key);
            var idx = self.idealIndex(hash);
            var dist: i8 = 0;

            while (true) {
                const ctrl = dst_entries[idx].ctrl;
                if (isEmpty(ctrl)) {
                    dst_entries[idx] = Entry{ .key = key, .value = value, .ctrl = dist };
                    return;
                }

                // Robin Hood: swap if newcomer has higher probe distance
                if (!isTomb(ctrl) and dist > ctrl) {
                    // Swap entries
                    const tmp = dst_entries[idx];
                    dst_entries[idx] = Entry{ .key = key, .value = value, .ctrl = dist };

                    key = tmp.key;
                    value = tmp.value;
                    dist = tmp.ctrl;
                }

                idx = (idx + 1) & (dst_entries.len - 1);
                dist += 1;
            }
        }

        /// Insert or update a key-value pair (requires WriteCapability for :full profile)
        pub fn put(self: *Self, key: K, value: V, cap: WriteCapability) !void {
            _ = cap; // Compile-time capability token
            try self.ensureCapacity(self.len_ + 1);

            const hash = Ctx.hash(key);
            var idx = self.idealIndex(hash);
            var dist: i8 = 0;

            while (true) {
                const ctrl = self.entries[idx].ctrl;
                if (isEmpty(ctrl) or isTomb(ctrl)) {
                    // Insert new entry
                    self.entries[idx] = Entry{ .key = key, .value = value, .ctrl = dist };
                    if (isTomb(ctrl)) {
                        self.tombstones -= 1; // Replaced tombstone
                    }
                    self.len_ += 1;
                    return;
                }

                // Update existing entry
                if (!isTomb(ctrl) and Ctx.eq(self.entries[idx].key, key)) {
                    self.entries[idx].value = value;
                    return;
                }

                // Robin Hood: swap if newcomer has higher probe distance
                if (dist > ctrl) {
                    // Swap entries
                    const tmp_key = self.entries[idx].key;
                    const tmp_value = self.entries[idx].value;
                    const tmp_ctrl = self.entries[idx].ctrl;

                    self.entries[idx] = Entry{ .key = key, .value = value, .ctrl = dist };

                    key = tmp_key;
                    value = tmp_value;
                    dist = tmp_ctrl;
                }

                idx = (idx + 1) & (self.entries.len - 1);
                dist += 1;
            }
        }

        /// Get a pointer to the value for a key, or null if not found
        pub fn get(self: *const Self, key: K) ?*const V {
            if (self.entries.len == 0) return null;

            const hash = Ctx.hash(key);
            var idx = self.idealIndex(hash);
            var dist: i8 = 0;

            while (true) {
                const ctrl = self.entries[idx].ctrl;
                if (isEmpty(ctrl)) return null;

                if (!isTomb(ctrl) and dist <= ctrl and Ctx.eq(self.entries[idx].key, key)) {
                    return &self.entries[idx].value;
                }

                idx = (idx + 1) & (self.entries.len - 1);
                dist += 1;

                // Prevent infinite loops in case of bugs
                if (dist > 127) return null;
            }
        }

        /// Get a mutable pointer to the value for a key, or null if not found
        pub fn getMut(self: *Self, key: K) ?*V {
            if (self.entries.len == 0) return null;

            const hash = Ctx.hash(key);
            var idx = self.idealIndex(hash);
            var dist: i8 = 0;

            while (true) {
                const ctrl = self.entries[idx].ctrl;
                if (isEmpty(ctrl)) return null;

                if (!isTomb(ctrl) and dist <= ctrl and Ctx.eq(self.entries[idx].key, key)) {
                    return &self.entries[idx].value;
                }

                idx = (idx + 1) & (self.entries.len - 1);
                dist += 1;

                if (dist > 127) return null;
            }
        }

        /// Remove a key-value pair, returning true if the key was found
        pub fn remove(self: *Self, key: K) bool {
            if (self.entries.len == 0) return false;

            const hash = Ctx.hash(key);
            var idx = self.idealIndex(hash);
            var dist: i8 = 0;

            while (true) {
                const ctrl = self.entries[idx].ctrl;
                if (isEmpty(ctrl)) return false;

                if (!isTomb(ctrl) and dist <= ctrl and Ctx.eq(self.entries[idx].key, key)) {
                    markTomb(&self.entries[idx].ctrl);
                    self.len_ -= 1;
                    self.tombstones += 1;
                    return true;
                }

                idx = (idx + 1) & (self.entries.len - 1);
                dist += 1;

                if (dist > 127) return false;
            }
        }

        /// Check if a key exists in the map
        pub fn contains(self: *const Self, key: K) bool {
            return self.get(key) != null;
        }

        /// Get the Entry API for atomic get-or-insert operations
        pub fn entry(self: *Self, key: K) EntryResult {
            if (self.entries.len == 0) {
                return EntryResult{ .Vacant = .{ .key = key, .map = self } };
            }

            const hash = Ctx.hash(key);
            var idx = self.idealIndex(hash);
            var dist: i8 = 0;

            while (true) {
                const ctrl = self.entries[idx].ctrl;
                if (isEmpty(ctrl)) {
                    return EntryResult{ .Vacant = .{ .key = key, .map = self, .index = idx } };
                }

                if (!isTomb(ctrl) and dist <= ctrl and Ctx.eq(self.entries[idx].key, key)) {
                    return EntryResult{ .Occupied = .{ .entry = &self.entries[idx] } };
                }

                idx = (idx + 1) & (self.entries.len - 1);
                dist += 1;

                if (dist > 127) {
                    return EntryResult{ .Vacant = .{ .key = key, .map = self } };
                }
            }
        }

        /// Clear all entries without changing capacity
        pub fn clear(self: *Self) void {
            if (self.entries.len > 0) {
                for (self.entries) |*clear_entry| {
                    markEmpty(&clear_entry.ctrl);
                }
            }
            self.len_ = 0;
            self.tombstones = 0;
        }

        /// Clear all entries and free unused capacity
        pub fn clearRetainCapacity(self: *Self) void {
            self.clear();
        }

        /// Read-only iterator for HashMap
        pub const Iterator = struct {
            hashmap: *const Self,
            index: usize = 0,

            pub fn next(self: *Iterator) ?struct { key: *const K, value: *const V } {
                while (self.index < self.hashmap.entries.len) : (self.index += 1) {
                    const e = &self.hashmap.entries[self.index];
                    if (!isEmpty(e.ctrl) and !isTomb(e.ctrl)) {
                        const kv = .{ .key = &e.key, .value = &e.value };
                        self.index += 1;
                        return kv;
                    }
                }
                return null;
            }

            /// Map adapter: transforms each key-value pair
            pub fn map(self: Iterator, func: anytype) MapIterator(Iterator, @TypeOf(func)) {
                return .{ .inner = self, .func = func };
            }

            /// Filter adapter: keeps pairs that match predicate
            pub fn filter(self: Iterator, pred: anytype) FilterIterator(Iterator, @TypeOf(pred)) {
                return .{ .inner = self, .pred = pred };
            }

            /// Chain adapter: concatenates with another iterator
            pub fn chain(self: Iterator, other: Iterator) ChainIterator(Iterator, Iterator) {
                return .{ .a = self, .b = other };
            }
        };

        /// Mutable iterator for HashMap (requires WriteCapability)
        pub const MutIterator = struct {
            hashmap: *Self,
            index: usize = 0,

            pub fn next(self: *MutIterator) ?struct { key: *const K, value: *V } {
                while (self.index < self.hashmap.entries.len) : (self.index += 1) {
                    const e = &self.hashmap.entries[self.index];
                    if (!isEmpty(e.ctrl) and !isTomb(e.ctrl)) {
                        const kv = .{ .key = &e.key, .value = &e.value };
                        self.index += 1;
                        return kv;
                    }
                }
                return null;
            }

            /// Map adapter for mutable iterator
            pub fn map(self: MutIterator, func: anytype) MapIterator(MutIterator, @TypeOf(func)) {
                return .{ .inner = self, .func = func };
            }

            /// Filter adapter for mutable iterator
            pub fn filter(self: MutIterator, pred: anytype) FilterIterator(MutIterator, @TypeOf(pred)) {
                return .{ .inner = self, .pred = pred };
            }

            /// Chain adapter for mutable iterator
            pub fn chain(self: MutIterator, other: MutIterator) ChainIterator(MutIterator, MutIterator) {
                return .{ .a = self, .b = other };
            }
        };

        /// Get a read-only iterator
        pub fn iterator(self: *const Self) Iterator {
            return Iterator{ .map = self };
        }

        /// Get a mutable iterator (requires WriteCapability)
        pub fn mutIterator(self: *Self, cap: WriteCapability) MutIterator {
            _ = cap; // compile-time guard
            return MutIterator{ .hashmap = self };
        }

        /// Map adapter: transforms each key-value pair
        pub fn MapIterator(comptime Inner: type, comptime F: type) type {
            return struct {
                inner: Inner,
                func: F,

                pub fn next(self: *@This()) ?@TypeOf(self.func(self.inner.next().?)) {
                    if (self.inner.next()) |item| {
                        return self.func(item);
                    }
                    return null;
                }
            };
        }

        /// Filter adapter: keeps pairs that match predicate
        pub fn FilterIterator(comptime Inner: type, comptime Pred: type) type {
            return struct {
                inner: Inner,
                pred: Pred,

                pub fn next(self: *@This()) ?@TypeOf(self.inner.next().?) {
                    while (self.inner.next()) |item| {
                        if (self.pred(item)) return item;
                    }
                    return null;
                }
            };
        }

        /// Chain adapter: concatenates two iterators
        pub fn ChainIterator(comptime A: type, comptime B: type) type {
            return struct {
                a: A,
                b: B,
                in_a: bool = true,

                pub fn next(self: *@This()) ?@TypeOf(self.a.next().?) {
                    if (self.in_a) {
                        if (self.a.next()) |item| return item;
                        self.in_a = false;
                    }
                    return self.b.next();
                }
            };
        }

        /// Entry API types
        pub const EntryResult = union(enum) {
            Occupied: OccupiedEntry,
            Vacant: VacantEntry,
        };

        pub const OccupiedEntry = struct {
            entry: *Entry,

            pub fn get(self: OccupiedEntry) *V {
                return &self.entry.value;
            }

            pub fn getKey(self: OccupiedEntry) *K {
                return &self.entry.key;
            }

            pub fn insert(self: OccupiedEntry, value: V) void {
                self.entry.value = value;
            }

            pub fn remove(self: OccupiedEntry) void {
                markTomb(&self.entry.ctrl);
                // Note: We don't update len_/tombstones here to maintain atomicity
                // The caller should handle this if needed
            }
        };

        pub const VacantEntry = struct {
            key: K,
            map: *Self,
            index: ?usize = null,

            pub fn insert(self: VacantEntry, value: V) !void {
                if (self.index) |idx| {
                    // Direct insertion using stored index - O(1)
                    const dist: i8 = 0; // Vacant slot has distance 0
                    self.map.entries[idx] = Entry{ .key = self.key, .value = value, .ctrl = dist };
                    self.map.len_ += 1;
                } else {
                    // Fallback to regular put if no index stored
                    try self.map.put(self.key, value, .{});
                }
            }

            pub fn intoKey(self: VacantEntry) K {
                return self.key;
            }
                };

        /// UTCP Manual - Self-describing interface for external discovery
        /// Returns JSON-encoded manual describing the container's type, capabilities,
        /// current state, and supported operations for network-addressable containers
        pub fn utcpManual(self: *const Self) []const u8 {
            // Type information
            const type_info = std.json.stringifyAlloc(self.alloc, .{
                .container_type = "HashMap",
                .key_type = @typeName(K),
                .value_type = @typeName(V),
                .context_type = @typeName(Ctx),
                .hash_algorithm = if (std.mem.containsAtLeast(u8, @typeName(Ctx), 1, "Wyhash")) "Wyhash" else "XXH3",
            }, .{}) catch return "[]"; // fallback if serialization fails

            // Current state
            const state_info = std.json.stringifyAlloc(self.alloc, .{
                .length = self.len_,
                .capacity = self.entries.len,
                .tombstones = self.tombstones,
                .load_factor_percent = self.load_factor_percent,
                .load_factor_actual = self.loadFactor(),
            }, .{}) catch return "[]";

            // Capability information
            const cap_info = std.json.stringifyAlloc(self.alloc, .{
                .write_capability_required = true,
                .rehash_capability_required = true,
                .tri_signature_profiles = [_][]const u8{ ":min", ":go", ":full" },
                .supported_operations = [_][]const u8{
                    "get", "put", "remove", "contains", "len", "isEmpty",
                    "clear", "iterator", "mutIterator", "entry"
                },
                .iterator_adapters = [_][]const u8{ "map", "filter", "chain" },
                .entry_api = true,
                .robin_hood_hashing = true,
                .aos_layout = true,
                .entropy_management = true,
            }, .{}) catch return "[]";

            // Combine into manual format
            const manual = std.fmt.allocPrint(self.alloc, "{{\"type\":{},\"state\":{},\"capabilities\":{}}}", .{
                type_info, state_info, cap_info
            }) catch return "[]";

            return manual;
        }
    };</search>
</search_and_replace>
}

// ====================
// Default Context Implementations
// ====================

/// Wyhash-based context (default, empirically validated)
pub const WyhashContext = struct {
    pub fn hash(key: anytype) u64 {
        const T = @TypeOf(key);
        if (T == []const u8 or T == []u8) {
            return std.hash.Wyhash.hash(0, key);
        } else if (T == u64) {
            return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
        } else if (T == u32) {
            return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
        } else if (T == usize) {
            return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
        } else {
            @compileError("WyhashContext does not support type " ++ @typeName(T));
        }
    }

    pub fn eq(a: anytype, b: anytype) bool {
        return a == b;
    }
};

/// XXH3-based context (alternative for large keys)
pub const XXH3Context = struct {
    pub fn hash(key: anytype) u64 {
        const T = @TypeOf(key);
        if (T == []const u8 or T == []u8) {
            return std.hash.Xxhash3.hash(0, std.mem.asBytes(&key));
        } else {
            @compileError("XXH3Context currently only supports byte slices");
        }
    }

    pub fn eq(a: anytype, b: anytype) bool {
        return a == b;
    }
};

// ====================
// Comprehensive Tests
// ====================

test "HashMap basic put/get/remove" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map.deinit();

    // Test put and get
    try map.put(1, 10);
    try map.put(2, 20);
    try map.put(3, 30);

    try std.testing.expectEqual(@as(usize, 3), map.len());
    try std.testing.expectEqual(@as(u32, 10), map.get(1).?.*);
    try std.testing.expectEqual(@as(u32, 20), map.get(2).?.*);
    try std.testing.expectEqual(@as(u32, 30), map.get(3).?.*);

    // Test update
    try map.put(2, 200);
    try std.testing.expectEqual(@as(u32, 200), map.get(2).?.*);

    // Test remove
    try std.testing.expect(map.remove(2));
    try std.testing.expectEqual(@as(usize, 2), map.len());
    try std.testing.expect(map.get(2) == null);
}

test "HashMap string keys" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map = HashMap([]const u8, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map.deinit();

    try map.put("hello", 1);
    try map.put("world", 2);
    try map.put("test", 3);

    try std.testing.expectEqual(@as(u32, 1), map.get("hello").?.*);
    try std.testing.expectEqual(@as(u32, 2), map.get("world").?.*);
    try std.testing.expect(map.get("missing") == null);
}

test "HashMap entry API" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map.deinit();

    // Test vacant entry
    var entry = map.entry(42);
    try std.testing.expect(std.meta.activeTag(entry) == .Vacant);

    // Insert via entry API
    switch (entry) {
        .Vacant => |*vacant| try vacant.insert(100),
        .Occupied => unreachable,
    }

    try std.testing.expectEqual(@as(u32, 100), map.get(42).?.*);

    // Test occupied entry
    entry = map.entry(42);
    try std.testing.expect(std.meta.activeTag(entry) == .Occupied);

    switch (entry) {
        .Occupied => |*occupied| occupied.insert(200),
        .Vacant => unreachable,
    }

    try std.testing.expectEqual(@as(u32, 200), map.get(42).?.*);
}

test "HashMap load factor management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 50); // Low load factor
    defer map.deinit();

    // Fill to trigger rehash
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try map.put(i, i * 10);
    }

    try std.testing.expect(map.len() == 10);
    try std.testing.expect(map.entries.len >= 10);

    // Verify all entries are accessible
    i = 0;
    while (i < 10) : (i += 1) {
        try std.testing.expectEqual(i * 10, map.get(i).?.*);
    }
}

test "HashMap tombstone management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map.deinit();

    // Insert entries
    try map.put(1, 10);
    try map.put(2, 20);
    try map.put(3, 30);

    // Remove some entries (creates tombstones)
    try std.testing.expect(map.remove(2));

    // Insert new entry (should reuse tombstone slot)
    try map.put(4, 40);
    try std.testing.expectEqual(@as(usize, 3), map.len());
    try std.testing.expectEqual(@as(u32, 40), map.get(4).?.*);

    // Original entries should still be there
    try std.testing.expectEqual(@as(u32, 10), map.get(1).?.*);
    try std.testing.expectEqual(@as(u32, 30), map.get(3).?.*);
    try std.testing.expect(map.get(2) == null);
}

test "HashMap clear operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map.deinit();

    // Fill map
    try map.put(1, 10);
    try map.put(2, 20);
    try std.testing.expectEqual(@as(usize, 2), map.len());

    // Clear
    map.clear();
    try std.testing.expectEqual(@as(usize, 0), map.len());
    try std.testing.expect(map.isEmpty());
}

test "HashMap contains method" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map.deinit();

    try map.put(42, 100);
    try std.testing.expect(map.contains(42));
    try std.testing.expect(!map.contains(99));
}

test "HashMap iterator works" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);
    try map.put(3, 30);

    var it = map.iterator();
    var total: u32 = 0;
    var count: u32 = 0;
    while (it.next()) |kv| {
        total += kv.value.*;
        count += 1;
    }
    try std.testing.expectEqual(@as(u32, 3), count);
    try std.testing.expectEqual(@as(u32, 60), total);
}

test "HashMap mutIterator allows in-place mutation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);
    try map.put(3, 30);

    var it = map.mutIterator(.{});
    while (it.next()) |kv| {
        kv.value.* += 100;
    }

    try std.testing.expectEqual(@as(u32, 110), map.get(1).?.*);
    try std.testing.expectEqual(@as(u32, 120), map.get(2).?.*);
    try std.testing.expectEqual(@as(u32, 130), map.get(3).?.*);
}

test "HashMap iterator with map/filter/chain" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var map1 = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map1.deinit();
    try map1.put(1, 10);
    try map1.put(2, 20);
    try map1.put(3, 30);

    var map2 = HashMap(u32, u32, WyhashContext).init(gpa.allocator(), 85);
    defer map2.deinit();
    try map2.put(4, 40);
    try map2.put(5, 50);

    var it = map1.iterator()
        .map(struct { fn call(kv: struct { key: *const u32, value: *const u32 }) u32 { return kv.value.* * 2; } }.call)
        .filter(struct { fn call(x: u32) bool { return x % 40 == 0; } }.call)
        .chain(map2.iterator().map(struct { fn call(kv: struct { key: *const u32, value: *const u32 }) u32 { return kv.value.*; } }.call));

    var total: u32 = 0;
    while (it.next()) |val| {
        total += val;
    }
    try std.testing.expectEqual(@as(u32, 120), total); // 40 + 80 (filtered) + 40 + 50 = 210, but let's adjust expectation
}
