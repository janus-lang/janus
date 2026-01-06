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

/// Deque<T> - Double-ended queue with circular buffer
///
/// Implements the tri-signature pattern for capability-based security:
/// - :min profile: init(alloc) - basic allocation
/// - :go profile: init(alloc, cap) - with initial capacity
/// - :full profile: init(alloc, cap, ctx) - with capability token
///
/// Uses circular buffer with logical ordering in iterators.
pub fn Deque(comptime T: type) type {
    return struct {
        const Self = @This();

        // Capability tokens for compile-time security
        pub const WriteCapability = struct {};

        /// Internal buffer management
        alloc: mem.Allocator,
        buf: []T = &[_]T{},
        cap: usize = 0,
        head: usize = 0, // logical start index
        tail: usize = 0, // logical end index (one past last element)
        len_: usize = 0,

        /// Initialize a new Deque with the given allocator
        pub fn init(alloc: mem.Allocator) Self {
            return Self{
                .alloc = alloc,
            };
        }

        /// Initialize a new Deque with initial capacity (for :go profile)
        pub fn initWithCapacity(alloc: mem.Allocator, initial_cap: usize) Self {
            return Self{
                .alloc = alloc,
                .cap = initial_cap,
                .buf = &[_]T{},
            };
        }

        /// Initialize a new Deque with capability token (for :full profile)
        pub fn initWithCapability(alloc: mem.Allocator, cap_token: WriteCapability, initial_cap: usize) Self {
            _ = cap_token; // Compile-time capability token for security
            return initWithCapacity(alloc, initial_cap);
        }

        /// Deinitialize the Deque, freeing all allocated memory
        pub fn deinit(self: *Self) void {
            if (self.cap > 0) {
                self.alloc.free(self.buf);
            }
            self.* = undefined; // Sanitize memory
        }

        /// Get the current number of elements
        pub fn len(self: *const Self) usize {
            return self.len_;
        }

        /// Check if the Deque is empty
        pub fn isEmpty(self: *const Self) bool {
            return self.len_ == 0;
        }

        /// Calculate the physical index from logical index
        fn logicalToPhysical(self: *const Self, logical_idx: usize) usize {
            return (self.head + logical_idx) % self.cap;
        }

        /// Grow the buffer to new capacity
        fn grow(self: *Self, new_cap: usize) !void {
            if (new_cap <= self.cap) return;

            const new_buf = try self.alloc.alloc(T, new_cap);

            // Copy elements in logical order
            var i: usize = 0;
            while (i < self.len_) : (i += 1) {
                const src_idx = self.logicalToPhysical(i);
                new_buf[i] = self.buf[src_idx];
            }

            if (self.cap > 0) {
                self.alloc.free(self.buf);
            }

            self.buf = new_buf;
            self.cap = new_cap;
            self.head = 0;
            self.tail = self.len_;
        }

        /// Ensure capacity for at least `need` elements
        fn ensureCapacity(self: *Self, need: usize) !void {
            if (need <= self.cap) return;

            var new_cap = if (self.cap == 0) 4 else self.cap;
            while (new_cap < need) {
                new_cap = new_cap * 3 / 2 + 1;
            }
            try self.grow(new_cap);
        }

        /// Push element to the back (requires WriteCapability)
        pub fn pushBack(self: *Self, value: T, cap: WriteCapability) !void {
            _ = cap; // compile-time guard
            try self.ensureCapacity(self.len_ + 1);

            self.buf[self.tail] = value;
            self.tail = (self.tail + 1) % self.cap;
            self.len_ += 1;
        }

        /// Push element to the front (requires WriteCapability)
        pub fn pushFront(self: *Self, value: T, cap: WriteCapability) !void {
            _ = cap; // compile-time guard
            try self.ensureCapacity(self.len_ + 1);

            self.head = if (self.head == 0) self.cap - 1 else self.head - 1;
            self.buf[self.head] = value;
            self.len_ += 1;
        }

        /// Pop element from the back
        pub fn popBack(self: *Self) ?T {
            if (self.len_ == 0) return null;

            self.tail = if (self.tail == 0) self.cap - 1 else self.tail - 1;
            self.len_ -= 1;
            return self.buf[self.tail];
        }

        /// Pop element from the front
        pub fn popFront(self: *Self) ?T {
            if (self.len_ == 0) return null;

            const value = self.buf[self.head];
            self.head = (self.head + 1) % self.cap;
            self.len_ -= 1;
            return value;
        }

        /// Get element at index (bounds-checked)
        pub fn get(self: *const Self, index: usize) ?*const T {
            if (index >= self.len_) return null;
            const phys_idx = self.logicalToPhysical(index);
            return &self.buf[phys_idx];
        }

        /// Get mutable element at index (bounds-checked)
        pub fn getMut(self: *Self, index: usize) ?*T {
            if (index >= self.len_) return null;
            const phys_idx = self.logicalToPhysical(index);
            return &self.buf[phys_idx];
        }

        /// Get element at index (unchecked, for performance)
        pub fn getUnchecked(self: *const Self, index: usize) *const T {
            const phys_idx = self.logicalToPhysical(index);
            return &self.buf[phys_idx];
        }

        /// Get mutable element at index (unchecked, for performance)
        pub fn getMutUnchecked(self: *Self, index: usize) *T {
            const phys_idx = self.logicalToPhysical(index);
            return &self.buf[phys_idx];
        }

        // ====================
        // Iterator Implementation
        // ====================

        /// Read-only iterator for Deque
        pub const Iterator = struct {
            deque: *const Self,
            index: usize = 0,

            pub fn next(self: *Iterator) ?*const T {
                if (self.index >= self.deque.len_) return null;
                const ptr = self.deque.getUnchecked(self.index);
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

        /// Mutable iterator for Deque (requires WriteCapability)
        pub const MutIterator = struct {
            deque: *Self,
            index: usize = 0,

            pub fn next(self: *MutIterator) ?*T {
                if (self.index >= self.deque.len_) return null;
                const ptr = self.deque.getMutUnchecked(self.index);
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
            return Iterator{ .deque = self };
        }

        /// Get a mutable iterator (requires WriteCapability)
        pub fn mutIterator(self: *Self, cap: WriteCapability) MutIterator {
            _ = cap; // compile-time guard
            return MutIterator{ .deque = self };
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
            try stream.write("Deque");

            try stream.objectField("element");
            try stream.write(@typeName(T));

            try stream.objectField("length");
            try stream.write(self.len_);

            try stream.objectField("capacity");
            try stream.write(self.cap_);

            try stream.objectField("features");
            try stream.beginArray();
            try stream.write("pushBack");
            try stream.write("pushFront");
            try stream.write("popBack");
            try stream.write("popFront");
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
