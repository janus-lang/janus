// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2025 Janus Project Authors
//
// Allocator Contexts/Regions/Using - Zig Implementation
// This is the working implementation; .jan files are specifications for when
// the Janus compiler is complete enough to compile its own standard library

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Allocator capability kind
pub const AllocKind = enum {
    heap,
    arena,
    region,
    tls,
    custom,
};

/// Allocator capability token
pub const Alloc = struct {
    id: u64,
    kind: AllocKind,
    signature: [8]u8,

    pub fn create(kind: AllocKind) Alloc {
        return .{
            .id = 0xDEADBEEFCAFEBABE, // TODO: Cryptographically secure ID
            .kind = kind,
            .signature = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0 },
        };
    }

    pub fn validate(self: Alloc) bool {
        return self.id != 0 and self.signature.len == 8;
    }
};

/// Allocator context grouping related allocators
pub const AllocContext = struct {
    general: Alloc,
    scratch: Alloc,
    gpu: ?Alloc = null,

    pub fn create(general: Alloc, scratch: Alloc) AllocContext {
        return .{
            .general = general,
            .scratch = scratch,
        };
    }

    pub fn createWithGpu(general: Alloc, scratch: Alloc, gpu: Alloc) AllocContext {
        return .{
            .general = general,
            .scratch = scratch,
            .gpu = gpu,
        };
    }
};

/// Drop trait for deterministic cleanup
pub fn Drop(comptime T: type) type {
    return struct {
        pub fn drop(self: *T) void {
            _ = self;
            // Default implementation - types should override
        }
    };
}

/// Context-bound List implementation
pub fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        len: usize,
        capacity: usize,
        alloc: Allocator,

        pub fn init(allocator: Allocator) !Self {
            return .{
                .items = &[_]T{},
                .len = 0,
                .capacity = 0,
                .alloc = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.capacity > 0) {
                self.alloc.free(self.items);
            }
        }

        pub fn append(self: *Self, item: T) !void {
            if (self.len >= self.capacity) {
                try self.grow();
            }
            self.items[self.len] = item;
            self.len += 1;
        }

        fn grow(self: *Self) !void {
            const new_capacity = if (self.capacity == 0) 4 else self.capacity * 2;
            const new_items = try self.alloc.alloc(T, new_capacity);

            if (self.len > 0) {
                @memcpy(new_items[0..self.len], self.items[0..self.len]);
            }

            if (self.capacity > 0) {
                self.alloc.free(self.items);
            }

            self.items = new_items;
            self.capacity = new_capacity;
        }

        pub fn get(self: *Self, index: usize) ?T {
            if (index >= self.len) return null;
            return self.items[index];
        }
    };
}

// Tests
test "Alloc.create and validate" {
    const alloc = Alloc.create(.heap);
    try std.testing.expect(alloc.validate());
    try std.testing.expectEqual(AllocKind.heap, alloc.kind);
}

test "AllocContext.create" {
    const general = Alloc.create(.heap);
    const scratch = Alloc.create(.arena);
    const ctx = AllocContext.create(general, scratch);

    try std.testing.expectEqual(AllocKind.heap, ctx.general.kind);
    try std.testing.expectEqual(AllocKind.arena, ctx.scratch.kind);
}

test "List basic operations" {
    var list = try List(i32).init(std.testing.allocator);
    defer list.deinit();

    try list.append(42);
    try list.append(84);

    try std.testing.expectEqual(@as(usize, 2), list.len);
    try std.testing.expectEqual(@as(i32, 42), list.get(0).?);
    try std.testing.expectEqual(@as(i32, 84), list.get(1).?);
}
