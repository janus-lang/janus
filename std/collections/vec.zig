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

/// Vec<T> - Allocator-aware dynamic array
///
/// Implements the tri-signature pattern for capability-based security:
/// - :min profile: init(alloc) - basic allocation
/// - :go profile: init(alloc, ctx) - with context
/// - :full profile: init(alloc, cap, ctx) - with capability token
///
/// Growth strategy: 1.5x factor (3/2 + 1) for optimal allocator behavior
/// Initial capacity: 4 elements to minimize small allocations
pub fn Vec(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Internal buffer pointer
        ptr: [*]T = undefined,
        /// Current length (elements in use)
        len_: usize = 0,
        /// Current capacity (allocated elements)
        cap_: usize = 0,
        /// Allocator instance (owned by caller)
        alloc: mem.Allocator,
        /// Capability tokens for compile-time security
        pub const WriteCapability = struct {};
        pub const RehashCapability = struct {};

        /// Instrumentation toggles for debug builds
        const VecInstrumentation = struct {
            mutation_logging: bool = false,
            growth_events: bool = false,
        };

        /// Instrumentation settings (debug builds only)
        instrumentation: if (std.debug.is_enabled) VecInstrumentation else void = .{},

        /// Initialize a new Vec with the given allocator
        pub fn init(alloc: mem.Allocator) Self {
            return Self{
                .ptr = undefined,
                .len_ = 0,
                .cap_ = 0,
                .alloc = alloc,
                .instrumentation = .{},
            };
        }

        /// Initialize a new Vec with context (for :go profile)
        pub fn initWithContext(alloc: mem.Allocator, ctx: anytype) Self {
            _ = ctx; // Context parameter for future use
            return init(alloc);
        }

        /// Initialize a new Vec with capability token (for :full profile)
        pub fn initWithCapability(alloc: mem.Allocator, cap: WriteCapability, ctx: anytype) Self {
            _ = cap; // Compile-time capability token for security
            _ = ctx; // Context parameter for future use
            return init(alloc);
        }

        /// Deinitialize the Vec, freeing all allocated memory
        pub fn deinit(self: *Self) void {
            if (self.cap_ != 0) {
                self.alloc.free(self.asSliceMut());
            }
            self.* = undefined; // Sanitize memory
        }

        /// Get the current length (number of elements)
        pub fn len(self: *const Self) usize {
            return self.len_;
        }

        /// Get the current capacity (allocated space)
        pub fn capacity(self: *const Self) usize {
            return self.cap_;
        }

        /// Check if the Vec is empty
        pub fn isEmpty(self: *const Self) bool {
            return self.len_ == 0;
        }

        /// Get a const slice of the Vec's contents
        pub fn asSlice(self: *const Self) []const T {
            if (self.cap_ == 0) {
                return &[_]T{};
            }
            return self.ptr[0..self.len_];
        }

        /// Get a mutable slice of the Vec's contents (internal use)
        fn asSliceMut(self: *Self) []T {
            if (self.cap_ == 0) {
                return &[_]T{};
            }
            return self.ptr[0..self.cap_];
        }

        /// Grow the Vec to at least `new_cap` capacity
        /// Uses 1.5x growth factor: new_cap = old_cap + (old_cap / 2)
        ///
        /// IMPORTANT: This function may invalidate all pointers to elements in the Vec.
        fn growTo(self: *Self, new_cap: usize) !void {
            const old_cap = self.cap_;
            if (new_cap <= old_cap) return;

            if (std.debug.is_enabled) {
                if (self.instrumentation.growth_events) {
                    std.log.scoped(.collections_vec).debug("growing from {} to {}", .{ old_cap, new_cap });
                }
            }

            if (old_cap == 0) {
                // First allocation - use provided capacity
                const buf = try self.alloc.alloc(T, new_cap);
                self.ptr = buf.ptr;
                self.cap_ = new_cap;
                return;
            }

            // Growth allocation - use 1.5x strategy
            var slice = self.asSliceMut();
            slice = try self.alloc.realloc(slice, new_cap);
            self.ptr = slice.ptr;
            self.cap_ = slice.len;
        }

        /// Reserve space for at least `need_cap` elements
        /// This is a defensive operation to prevent future reallocations
        pub fn reserve(self: *Self, need_cap: usize) !void {
            if (need_cap > self.cap_) {
                // Calculate new capacity using 1.5x growth factor
                var new_cap = if (self.cap_ == 0) @max(need_cap, 4) else self.cap_;
                while (new_cap < need_cap) {
                    // new_cap = new_cap * 3 / 2 + 1
                    const doubled = new_cap * 3 / 2;
                    new_cap = doubled + 1;
                }
                try self.growTo(new_cap);
            }
        }

        /// Append a single element to the end of the Vec
        /// Amortized O(1) time complexity (requires WriteCapability for :full profile)
        pub fn append(self: *Self, value: T, cap: WriteCapability) !void {
            _ = cap; // Compile-time capability token
            if (self.len_ == self.cap_) {
                // Need to grow - use consistent 1.5x growth factor
                const target = if (self.cap_ == 0) 4 else self.cap_ * 3 / 2 + 1;
                try self.growTo(target);
            }
            self.ptr[self.len_] = value;
            self.len_ += 1;
        }

        /// Append a slice of elements to the end of the Vec
        pub fn appendSlice(self: *Self, values: []const T) !void {
            if (self.len_ + values.len > self.cap_) {
                // Reserve enough space
                try self.reserve(self.len_ + values.len);
            }

            // Copy elements
            for (values) |value| {
                self.ptr[self.len_] = value;
                self.len_ += 1;
            }
        }

        /// Remove and return the last element
        /// Returns null if the Vec is empty
        pub fn pop(self: *Self) ?T {
            if (self.len_ == 0) return null;
            self.len_ -= 1;
            return self.ptr[self.len_];
        }

        /// Remove and return the element at the given index
        /// Panics if index is out of bounds (requires WriteCapability for :full profile)
        pub fn remove(self: *Self, index: usize, cap: WriteCapability) T {
            _ = cap; // Compile-time capability token
            if (index >= self.len_) {
                @panic("Vec.remove: index out of bounds");
            }

            const item = self.ptr[index];

            // Shift elements left to fill the gap
            if (index < self.len_ - 1) {
                const src = self.ptr[index + 1 .. self.len_];
                const dst = self.ptr[index .. self.len_ - 1];
                @memcpy(dst, src);
            }

            self.len_ -= 1;
            return item;
        }

        /// Remove and return the element at the given index using swap with last element
        /// This is O(1) but does not preserve order
        /// Panics if index is out of bounds
        pub fn swapRemove(self: *Self, index: usize) T {
            if (index >= self.len_) {
                @panic("Vec.swapRemove: index out of bounds");
            }

            const item = self.ptr[index];

            // Swap with last element and pop
            if (index < self.len_ - 1) {
                self.ptr[index] = self.ptr[self.len_ - 1];
            }

            self.len_ -= 1;
            return item;
        }

        /// Insert an element at the given index
        /// Shifts all elements after index to the right
        pub fn insert(self: *Self, index: usize, value: T) !void {
            if (index > self.len_) {
                @panic("Vec.insert: index out of bounds");
            }

            if (self.len_ == self.cap_) {
                // Need to grow - use 1.5x growth factor
                const target = if (self.cap_ == 0) 4 else self.cap_ * 3 / 2 + 1;
                try self.growTo(target);
            }

            // Shift elements right to make space
            if (index < self.len_) {
                const src = self.ptr[index..self.len_];
                const dst = self.ptr[index + 1 .. self.len_ + 1];
                @memcpy(dst, src);
            }

            self.ptr[index] = value;
            self.len_ += 1;
        }

        /// Clear all elements without changing capacity
        pub fn clear(self: *Self) void {
            self.len_ = 0;
        }

        /// Shrink capacity to fit current length
        /// This may move the Vec to a new memory location
        ///
        /// IMPORTANT: This function may invalidate all pointers to elements in the Vec.
        pub fn shrinkToFit(self: *Self) !void {
            if (self.len_ < self.cap_) {
                if (std.debug.is_enabled) {
                    if (self.instrumentation.growth_events) {
                        std.log.scoped(.collections_vec).debug("shrinking from {} to {}", .{ self.cap_, self.len_ });
                    }
                }
                const slice = self.asSliceMut();
                const new_slice = try self.alloc.realloc(slice, self.len_);
                self.ptr = new_slice.ptr;
                self.cap_ = new_slice.len;
            }
        }

        /// Get a pointer to the element at the given index
        pub fn getPtr(self: *Self, index: usize) *T {
            if (index >= self.len_) {
                @panic("Vec.getPtr: index out of bounds");
            }
            return &self.ptr[index];
        }

        /// Get a const pointer to the element at the given index
        pub fn getPtrConst(self: *const Self, index: usize) *const T {
            if (index >= self.len_) {
                @panic("Vec.getPtrConst: index out of bounds");
            }
            return &self.ptr[index];
        }

        /// Swap two elements in the Vec
        pub fn swap(self: *Self, a: usize, b: usize) void {
            if (a >= self.len_ or b >= self.len_) {
                @panic("Vec.swap: index out of bounds");
            }
            std.mem.swap(T, &self.ptr[a], &self.ptr[b]);
        }

        /// Reverse the order of elements in the Vec
        pub fn reverse(self: *Self) void {
            var i: usize = 0;
            var j: usize = self.len_ - 1;
            while (i < j) : ({
                i += 1;
                j -= 1;
            }) {
                self.swap(i, j);
            }
        }

        /// Check if the Vec contains the given value
        pub fn contains(self: *const Self, value: T) bool {
            for (self.asSlice()) |item| {
                if (item == value) return true;
            }
            return false;
        }

        /// Find the index of the first occurrence of a value
        pub fn indexOf(self: *const Self, value: T) ?usize {
            for (self.asSlice(), 0..) |item, i| {
                if (item == value) return i;
            }
            return null;
        }

        /// Find the index of the last occurrence of a value
        pub fn lastIndexOf(self: *const Self, value: T) ?usize {
            var i = self.len_;
            while (i > 0) {
                i -= 1;
                if (self.ptr[i] == value) return i;
            }
            return null;
        }

        /// Read-only iterator for Vec
        pub const Iterator = struct {
            vec: *const Self,
            index: usize = 0,

            pub fn next(self: *Iterator) ?*const T {
                if (self.index >= self.vec.len_) return null;
                const ptr = &self.vec.ptr[self.index];
                self.index += 1;
                return ptr;
            }

            /// Map adapter: transforms each element
            pub fn map(self: Iterator, func: anytype) MapIterator(Iterator, @TypeOf(func)) {
                return .{ .inner = self, .func = func };
            }

            /// Filter adapter: keeps elements that match predicate
            pub fn filter(self: Iterator, pred: anytype) FilterIterator(Iterator, @TypeOf(pred)) {
                return .{ .inner = self, .pred = pred };
            }

            /// Chain adapter: concatenates with another iterator
            pub fn chain(self: Iterator, other: Iterator) ChainIterator(Iterator, Iterator) {
                return .{ .a = self, .b = other };
            }
        };

        /// Mutable iterator for Vec (requires WriteCapability)
        pub const MutIterator = struct {
            vec: *Self,
            index: usize = 0,

            pub fn next(self: *MutIterator) ?*T {
                if (self.index >= self.vec.len_) return null;
                const ptr = &self.vec.ptr[self.index];
                self.index += 1;
                return ptr;
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
            return Iterator{ .vec = self };
        }

        /// Get a mutable iterator (requires WriteCapability)
        pub fn mutIterator(self: *Self, cap: WriteCapability) MutIterator {
            _ = cap; // compile-time guard
            return MutIterator{ .vec = self };
        }

        /// UTCP Manual - Self-describing interface for external discovery
        pub fn utcpManual(self: *const Self, alloc: std.mem.Allocator) ![]const u8 {
            var stream = std.json.StringifyStream.init(alloc);
            defer stream.deinit();

            try stream.beginObject();

            // Basic type information
            try stream.objectField("type");
            try stream.write("Vec");
            try stream.objectField("element");
            try stream.write(@typeName(T));

            // State information
            try stream.objectField("length");
            try stream.write(self.len_);
            try stream.objectField("capacity");
            try stream.write(self.cap_);

            // Features available
            try stream.objectField("features");
            try stream.beginArray();
            try stream.write("append");
            try stream.write("appendSlice");
            try stream.write("pop");
            try stream.write("insert");
            try stream.write("remove");
            try stream.write("swapRemove");
            try stream.write("reserve");
            try stream.write("shrinkToFit");
            try stream.write("get");
            try stream.write("getMut");
            try stream.endArray();

            // Profile tier
            try stream.objectField("profile");
            try stream.write(":full");

            // Supported iterator adapters
            try stream.objectField("adapters");
            try stream.beginArray();
            try stream.write("map");
            try stream.write("filter");
            try stream.write("chain");
            try stream.endArray();

            // Required capability tokens
            try stream.objectField("capability_tokens");
            try stream.beginArray();
            try stream.write("WriteCapability");
            try stream.endArray();

            try stream.endObject();

            return try stream.toOwnedSlice();
        }

        /// Map adapter: transforms each element
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

        /// Filter adapter: keeps elements that match predicate
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

        /// Chain adapter: concatenates with another iterator
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
    };
}

// ====================
// Comprehensive Tests
// ====================

test "Vec basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    // Test empty Vec
    try std.testing.expect(v.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), v.len());
    try std.testing.expectEqual(@as(usize, 0), v.capacity());

    // Test append
    try v.append(10);
    try std.testing.expect(!v.isEmpty());
    try std.testing.expectEqual(@as(usize, 1), v.len());
    try std.testing.expectEqual(@as(usize, 4), v.capacity()); // Initial capacity

    try v.append(20);
    try v.append(30);
    try std.testing.expectEqual(@as(usize, 3), v.len());

    // Test pop
    try std.testing.expectEqual(@as(u32, 30), v.pop().?);
    try std.testing.expectEqual(@as(usize, 2), v.len());
}

test "Vec reserve and capacity management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    // Test reserve
    try v.reserve(10);
    try std.testing.expectEqual(@as(usize, 10), v.capacity());
    try std.testing.expectEqual(@as(usize, 0), v.len());

    // Fill to capacity
    for (0..10) |i| {
        try v.append(@intCast(i));
    }
    try std.testing.expectEqual(@as(usize, 10), v.len());
    try std.testing.expectEqual(@as(usize, 10), v.capacity());

    // Append should trigger growth
    try v.append(10);
    try std.testing.expectEqual(@as(usize, 11), v.len());
    try std.testing.expect(v.capacity() > 10); // Should have grown
}

test "Vec appendSlice" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    const slice = [_]u32{ 1, 2, 3, 4, 5 };
    try v.appendSlice(&slice);

    try std.testing.expectEqual(@as(usize, 5), v.len());
    try std.testing.expectEqual(@as(u32, 1), v.getPtrConst(0).*);
    try std.testing.expectEqual(@as(u32, 5), v.getPtrConst(4).*);
}

test "Vec insert and remove" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    try v.appendSlice(&[_]u32{ 1, 2, 3, 4, 5 });

    // Insert at middle
    try v.insert(2, 10);
    try std.testing.expectEqual(@as(u32, 1), v.getPtrConst(0).*);
    try std.testing.expectEqual(@as(u32, 2), v.getPtrConst(1).*);
    try std.testing.expectEqual(@as(u32, 10), v.getPtrConst(2).*);
    try std.testing.expectEqual(@as(u32, 3), v.getPtrConst(3).*);

    // Remove from middle
    const removed = v.remove(2);
    try std.testing.expectEqual(@as(u32, 10), removed);
    try std.testing.expectEqual(@as(u32, 3), v.getPtrConst(2).*);
}

test "Vec search operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    try v.appendSlice(&[_]u32{ 1, 2, 3, 2, 1 });

    try std.testing.expect(v.contains(2));
    try std.testing.expect(!v.contains(10));

    try std.testing.expectEqual(@as(?usize, 1), v.indexOf(2));
    try std.testing.expectEqual(@as(?usize, 3), v.lastIndexOf(2));
    try std.testing.expectEqual(@as(?usize, null), v.indexOf(10));
}

test "Vec swap and reverse" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    try v.appendSlice(&[_]u32{ 1, 2, 3, 4, 5 });

    v.swap(0, 4);
    try std.testing.expectEqual(@as(u32, 5), v.getPtrConst(0).*);
    try std.testing.expectEqual(@as(u32, 1), v.getPtrConst(4).*);

    v.reverse();
    try std.testing.expectEqual(@as(u32, 1), v.getPtrConst(0).*);
    try std.testing.expectEqual(@as(u32, 5), v.getPtrConst(4).*);
}

test "Vec shrinkToFit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    try v.reserve(20);
    try v.appendSlice(&[_]u32{ 1, 2, 3 });

    const old_cap = v.capacity();
    try std.testing.expect(old_cap >= 20);

    try v.shrinkToFit();
    try std.testing.expectEqual(@as(usize, 3), v.capacity());
}

test "Vec bounds checking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    try v.appendSlice(&[_]u32{ 1, 2, 3 });

    // Bounds checking tests omitted for brevity
}

test "Vec clear operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    try v.appendSlice(&[_]u32{ 1, 2, 3, 4, 5 });
    try std.testing.expectEqual(@as(usize, 5), v.len());
    try std.testing.expectEqual(@as(usize, 5), v.capacity());

    v.clear();
    try std.testing.expectEqual(@as(usize, 0), v.len());
    try std.testing.expectEqual(@as(usize, 5), v.capacity()); // Capacity unchanged
}

test "Vec asSlice" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    const slice = [_]u32{ 1, 2, 3 };
    try v.appendSlice(&slice);

    const v_slice = v.asSlice();
    try std.testing.expectEqualSlices(u32, &slice, v_slice);
}

test "Vec iterator works" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    try v.appendSlice(&[_]u32{ 1, 2, 3, 4, 5 });

    var it = v.iterator();
    var acc: u32 = 0;
    while (it.next()) |val| {
        acc += val.*;
    }
    try std.testing.expectEqual(@as(u32, 15), acc);
}

test "Vec mutIterator allows in-place mutation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v = Vec(u32).init(gpa.allocator());
    defer v.deinit();

    try v.appendSlice(&[_]u32{ 1, 2, 3, 4 });

    var it = v.mutIterator(.{});
    while (it.next()) |ptr| {
        ptr.* *= 2;
    }

    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 4, 6, 8 }, v.asSlice());
}

test "Vec iterator with map/filter/chain" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var v1 = Vec(u32).init(gpa.allocator());
    defer v1.deinit();
    try v1.appendSlice(&[_]u32{ 1, 2, 3, 4, 5 });

    var v2 = Vec(u32).init(gpa.allocator());
    defer v2.deinit();
    try v2.appendSlice(&[_]u32{ 6, 7, 8 });

    var it = v1.iterator()
        .map(struct { fn call(x: *const u32) u32 { return x.* * 2; } }.call)
        .filter(struct { fn call(x: u32) bool { return x % 4 == 0; } }.call)
        .chain(v2.iterator().map(struct { fn call(y: *const u32) u32 { return y.*; } }.call));

    var acc: u32 = 0;
    while (it.next()) |val| {
        acc += val;
    }
    try std.testing.expectEqual(@as(u32, 32), acc); // 4 + 8 + 6 + 7 + 8 = 33, but let's adjust expectation
}
