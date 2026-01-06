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

/// SmallVec<T, N> - Vector with inline storage that spills to heap
///
/// Implements the tri-signature pattern for capability-based security:
/// - :min profile: init(alloc) - basic allocation
/// - :go profile: init(alloc, initial_cap) - with initial capacity
/// - :full profile: init(alloc, initial_cap, ctx) - with capability token
///
/// Uses inline storage up to N elements, then spills to heap with Vec-like growth.
pub fn SmallVec(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();

        // Capability tokens for compile-time security
        pub const WriteCapability = struct {};

        /// Internal storage management
        alloc: mem.Allocator,
        /// Inline storage array
        inline_storage: [N]T = undefined,
        /// Whether we're using inline storage (true) or heap (false)
        using_inline: bool = true,
        /// Heap buffer when spilled over
        heap_buf: []T = &[_]T{},
        /// Current capacity
        cap: usize = N,
        /// Current length
        len_: usize = 0,

        /// Initialize a new SmallVec with the given allocator
        pub fn init(alloc: mem.Allocator) Self {
            return Self{
                .alloc = alloc,
            };
        }

        /// Initialize a new SmallVec with initial capacity (for :go profile)
        pub fn initWithCapacity(alloc: mem.Allocator, initial_cap: usize) Self {
            if (initial_cap <= N) {
                return Self{
                    .alloc = alloc,
                };
            } else {
                // Pre-allocate heap buffer if requested capacity > inline
                const heap_buf = alloc.alloc(T, initial_cap) catch &[_]T{};
                return Self{
                    .alloc = alloc,
                    .using_inline = false,
                    .heap_buf = heap_buf,
                    .cap = initial_cap,
                };
            }
        }

        /// Initialize a new SmallVec with capability token (for :full profile)
        pub fn initWithCapability(alloc: mem.Allocator, cap_token: WriteCapability, initial_cap: usize) Self {
            _ = cap_token; // Compile-time capability token for security
            return initWithCapacity(alloc, initial_cap);
        }

        /// Deinitialize the SmallVec, freeing heap allocations
        pub fn deinit(self: *Self) void {
            if (!self.using_inline and self.cap > 0) {
                self.alloc.free(self.heap_buf);
            }
            self.* = undefined; // Sanitize memory
        }

        /// Get the current number of elements
        pub fn len(self: *const Self) usize {
            return self.len_;
        }

        /// Check if the SmallVec is empty
        pub fn isEmpty(self: *const Self) bool {
            return self.len_ == 0;
        }

        /// Get the current data slice (inline or heap)
        fn data(self: *Self) []T {
            return if (self.using_inline)
                self.inline_storage[0..self.cap]
            else
                self.heap_buf[0..self.cap];
        }

        /// Get the current data slice (read-only)
        fn dataConst(self: *const Self) []const T {
            return if (self.using_inline)
                self.inline_storage[0..self.cap]
            else
                self.heap_buf[0..self.cap];
        }

        /// Grow capacity, potentially spilling to heap
        fn grow(self: *Self, new_cap: usize) !void {
            if (new_cap <= self.cap) return;

            if (self.using_inline and new_cap <= N) {
                // Just update capacity within inline storage
                self.cap = new_cap;
                return;
            }

            // Need to spill to heap
            const new_buf = try self.alloc.alloc(T, new_cap);

            // Copy existing data
            const src = if (self.using_inline)
                self.inline_storage[0..self.len_]
            else
                self.heap_buf[0..self.len_];

            @memcpy(new_buf[0..self.len_], src);

            // Free old heap buffer if it exists
            if (!self.using_inline) {
                self.alloc.free(self.heap_buf);
            }

            // Update state
            self.heap_buf = new_buf;
            self.using_inline = false;
            self.cap = new_cap;
        }

        /// Ensure capacity for at least `need` elements
        fn ensureCapacity(self: *Self, need: usize) !void {
            if (need <= self.cap) return;

            var new_cap = if (self.cap == N) N * 2 else self.cap;
            while (new_cap < need) {
                new_cap = new_cap * 3 / 2 + 1;
            }
            try self.grow(new_cap);
        }

        /// Append element (requires WriteCapability)
        pub fn append(self: *Self, value: T, cap: WriteCapability) !void {
            _ = cap; // compile-time guard
            try self.ensureCapacity(self.len_ + 1);

            const data_slice = self.data();
            data_slice[self.len_] = value;
            self.len_ += 1;
        }

        /// Append slice of elements (requires WriteCapability)
        pub fn appendSlice(self: *Self, values: []const T, cap: WriteCapability) !void {
            _ = cap; // compile-time guard
            try self.ensureCapacity(self.len_ + values.len);

            const data_slice = self.data();
            @memcpy(data_slice[self.len_..self.len_ + values.len], values);
            self.len_ += values.len;
        }

        /// Pop element from the back
        pub fn pop(self: *Self) ?T {
            if (self.len_ == 0) return null;

            self.len_ -= 1;
            const data_slice = self.data();
            return data_slice[self.len_];
        }

        /// Get element at index (bounds-checked)
        pub fn get(self: *const Self, index: usize) ?*const T {
            if (index >= self.len_) return null;
            const data_slice = self.dataConst();
            return &data_slice[index];
        }

        /// Get mutable element at index (bounds-checked)
        pub fn getMut(self: *Self, index: usize) ?*T {
            if (index >= self.len_) return null;
            const data_slice = self.data();
            return &data_slice[index];
        }

        /// Get element at index (unchecked, for performance)
        pub fn getUnchecked(self: *const Self, index: usize) *const T {
            const data_slice = self.dataConst();
            return &data_slice[index];
        }

        /// Get mutable element at index (unchecked, for performance)
        pub fn getMutUnchecked(self: *Self, index: usize) *T {
            const data_slice = self.data();
            return &data_slice[index];
        }

        /// Insert element at index (requires WriteCapability)
        pub fn insert(self: *Self, index: usize, value: T, cap: WriteCapability) !void {
            _ = cap; // compile-time guard
            if (index > self.len_) return error.IndexOutOfBounds;

            try self.ensureCapacity(self.len_ + 1);

            // Shift elements right
            var i = self.len_;
            while (i > index) : (i -= 1) {
                const data_slice = self.data();
                data_slice[i] = data_slice[i - 1];
            }

            // Insert new element
            const data_slice = self.data();
            data_slice[index] = value;
            self.len_ += 1;
        }

        /// Remove element at index (requires WriteCapability)
        pub fn remove(self: *Self, index: usize, cap: WriteCapability) !T {
            _ = cap; // compile-time guard
            if (index >= self.len_) return error.IndexOutOfBounds;

            const data_slice = self.data();
            const value = data_slice[index];

            // Shift elements left
            var i = index;
            while (i < self.len_ - 1) : (i += 1) {
                data_slice[i] = data_slice[i + 1];
            }

            self.len_ -= 1;
            return value;
        }

        /// Swap remove element at index (O(1), requires WriteCapability)
        pub fn swapRemove(self: *Self, index: usize, cap: WriteCapability) !T {
            _ = cap; // compile-time guard
            if (index >= self.len_) return error.IndexOutOfBounds;

            const data_slice = self.data();
            const value = data_slice[index];

            // Swap with last element
            const last_index = self.len_ - 1;
            if (index != last_index) {
                data_slice[index] = data_slice[last_index];
            }

            self.len_ -= 1;
            return value;
        }

        // ====================
        // Iterator Implementation
        // ====================

        /// Read-only iterator for SmallVec
        pub const Iterator = struct {
            small_vec: *const Self,
            index: usize = 0,

            pub fn next(self: *Iterator) ?*const T {
                if (self.index >= self.small_vec.len_) return null;
                const ptr = self.small_vec.getUnchecked(self.index);
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

        /// Mutable iterator for SmallVec (requires WriteCapability)
        pub const MutIterator = struct {
            small_vec: *Self,
            index: usize = 0,

            pub fn next(self: *MutIterator) ?*T {
                if (self.index >= self.small_vec.len_) return null;
                const ptr = self.small_vec.getMutUnchecked(self.index);
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
            return Iterator{ .small_vec = self };
        }

        /// Get a mutable iterator (requires WriteCapability)
        pub fn mutIterator(self: *Self, cap: WriteCapability) MutIterator {
            _ = cap; // compile-time guard
            return MutIterator{ .small_vec = self };
        }

        // ====================
        // Iterator Adapters
        // ====================

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

        pub fn utcpManual(self: *const Self, alloc: std.mem.Allocator) ![]const u8 {
            var stream = std.json.StringifyStream.init(alloc);
            defer stream.deinit();

            try stream.beginObject();

            try stream.objectField("type");
            try stream.write("SmallVec");

            try stream.objectField("element");
            try stream.write(@typeName(T));

            try stream.objectField("length");
            try stream.write(self.len_);

            try stream.objectField("capacity");
            try stream.write(self.cap);

            try stream.objectField("inline_capacity");
            try stream.write(N);

            try stream.objectField("features");
            try stream.beginArray();
            try stream.write("append");
            try stream.write("appendSlice");
            try stream.write("pop");
            try stream.write("insert");
            try stream.write("remove");
            try stream.write("swapRemove");
            try stream.endArray();

            try stream.objectField("profile");
            try stream.write(":full");

            try stream.objectField("adapters");
            try stream.beginArray();
            try stream.write("map");
            try stream.write("filter");
            try stream.write("chain");
            try stream.endArray();

            try stream.objectField("capability_tokens");
            try stream.beginArray();
            try stream.write("WriteCapability");
            try stream.endArray();

            try stream.endObject();

            return try stream.toOwnedSlice();
        }
    };
