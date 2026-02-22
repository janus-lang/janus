// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Blake3 = std.crypto.hash.Blake3;

// Strongly typed IDs to prevent confusion
pub const StrId = enum(u32) { _ };
pub const TypeId = enum(u32) { _ };
pub const SymId = enum(u32) { _ };

/// Process-wide string interner with BLAKE3 deduplication
pub const StrInterner = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator, // String storage arena
    strings: std.ArrayList([]const u8),
    map: std.HashMap([32]u8, StrId, Blake3Context, std.hash_map.default_max_load_percentage),
    // Simple spinlock using atomic - Zig 0.16 compatible
    lock: std.atomic.Value(u32) = .init(0),
    deterministic: bool,

    fn acquireLock(self: *Self) void {
        while (self.lock.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            // Spin
        }
    }

    fn releaseLock(self: *Self) void {
        self.lock.store(0, .release);
    }

    const Blake3Context = struct {
        pub fn hash(self: @This(), key: [32]u8) u64 {
            _ = self;
            return std.mem.readInt(u64, key[0..8], .little);
        }

        pub fn eql(self: @This(), a: [32]u8, b: [32]u8) bool {
            _ = self;
            return std.mem.eql(u8, &a, &b);
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self.initWithMode(allocator, false);
    }

    pub fn initWithMode(allocator: std.mem.Allocator, deterministic: bool) Self {
        return Self{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .strings = .empty,
            .map = std.HashMap([32]u8, StrId, Blake3Context, std.hash_map.default_max_load_percentage).init(allocator),
            .deterministic = deterministic,
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.strings.deinit(self.arena.allocator());
        self.arena.deinit(); // O(1) cleanup of all interned strings
    }

    /// Intern a string, returning stable ID. Thread-safe.
    pub fn intern(self: *Self, bytes: []const u8) !StrId {
        var hash: [32]u8 = undefined;
        if (self.deterministic) {
            // Use fixed seed for deterministic builds
            Blake3.hash(bytes, &hash, .{ .key = [_]u8{0x42} ** 32 });
        } else {
            // Use default (potentially random) seed for normal builds
            Blake3.hash(bytes, &hash, .{});
        }

        self.acquireLock();
        defer self.releaseLock();

        if (self.map.get(hash)) |id| {
            return id;
        }

        const id = @as(StrId, @enumFromInt(@as(u32, @intCast(self.strings.items.len))));
        const owned = try self.arena.allocator().dupe(u8, bytes);
        try self.strings.append(self.arena.allocator(), owned);
        try self.map.put(hash, id);

        return id;
    }

    /// Get string by ID. Returns null if ID is invalid.
    pub fn get(self: *Self, id: StrId) ?[]const u8 {
        const index = @intFromEnum(id);
        if (index >= self.strings.items.len) return null;
        return self.strings.items[index];
    }

    /// Get string by ID, panics if invalid (for when you know ID is valid)
    pub fn getString(self: *Self, id: StrId) []const u8 {
        return self.get(id) orelse unreachable;
    }

    pub fn count(self: *Self) u32 {
        return @intCast(self.strings.items.len);
    }
};

/// Type interner for canonical structural types
pub const TypeInterner = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator, // Type storage arena
    types: std.ArrayList(Type),
    map: std.HashMap([32]u8, TypeId, Blake3Context, std.hash_map.default_max_load_percentage),
    mutex: std.Thread.Mutex = .{},

    const Blake3Context = StrInterner.Blake3Context;

    pub const Type = struct {
        kind: TypeKind,
        data: TypeData,

        pub const TypeKind = enum {
            primitive,
            pointer,
            array,
            slice,
            function,
            struct_type,
            union_type,
            enum_type,
        };

        pub const TypeData = union(TypeKind) {
            primitive: PrimitiveType,
            pointer: struct { pointee: TypeId, is_const: bool },
            array: struct { element: TypeId, size: u64 },
            slice: struct { element: TypeId, is_const: bool },
            function: struct {
                params: []TypeId,
                return_type: ?TypeId,
                effects: u32,
                capabilities: u32,
            },
            struct_type: struct { fields: []FieldType },
            union_type: struct { variants: []FieldType },
            enum_type: struct { backing: TypeId, variants: []EnumVariant },
        };

        pub const PrimitiveType = enum {
            void,
            bool,
            i8,
            i16,
            i32,
            i64,
            u8,
            u16,
            u32,
            u64,
            f32,
            f64,
            string,
        };

        pub const FieldType = struct {
            name: StrId,
            type_id: TypeId,
        };

        pub const EnumVariant = struct {
            name: StrId,
            value: ?i64,
        };

        /// Generate canonical bytes for hashing
        pub fn canonicalBytes(self: *const Type, writer: anytype) !void {
            try writer.writeAll(@tagName(self.kind));

            switch (self.data) {
                .primitive => |p| try writer.writeAll(@tagName(p)),
                .pointer => |p| {
                    try writer.writeInt(u32, @intFromEnum(p.pointee), .little);
                    try writer.writeByte(if (p.is_const) 1 else 0);
                },
                .array => |a| {
                    try writer.writeInt(u32, @intFromEnum(a.element), .little);
                    try writer.writeInt(u64, a.size, .little);
                },
                .slice => |s| {
                    try writer.writeInt(u32, @intFromEnum(s.element), .little);
                    try writer.writeByte(if (s.is_const) 1 else 0);
                },
                .function => |f| {
                    try writer.writeInt(u32, @intCast(f.params.len), .little);
                    for (f.params) |param| {
                        try writer.writeInt(u32, @intFromEnum(param), .little);
                    }
                    if (f.return_type) |ret| {
                        try writer.writeByte(1);
                        try writer.writeInt(u32, @intFromEnum(ret), .little);
                    } else {
                        try writer.writeByte(0);
                    }
                    try writer.writeInt(u32, f.effects, .little);
                    try writer.writeInt(u32, f.capabilities, .little);
                },
                // TODO: Implement other type serialization
                else => {},
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .types = .empty,
            .map = std.HashMap([32]u8, TypeId, Blake3Context, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.types.deinit(self.arena.allocator());
        self.arena.deinit(); // O(1) cleanup of all interned types
    }

    /// Intern a type, returning stable ID. Thread-safe.
    pub fn intern(self: *Self, type_data: Type) !TypeId {
        var buf: [1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        try type_data.canonicalBytes(stream.writer());

        var hash: [32]u8 = undefined;
        Blake3.hash(stream.getWritten(), &hash, .{});

        self.acquireLock();
        defer self.releaseLock();

        if (self.map.get(hash)) |id| {
            return id;
        }

        const id = @as(TypeId, @enumFromInt(@as(u32, @intCast(self.types.items.len))));
        const owned = try self.arena.allocator().create(Type);
        owned.* = type_data;
        try self.types.append(self.arena.allocator(), owned.*);
        try self.map.put(hash, id);

        return id;
    }

    pub fn get(self: *Self, id: TypeId) ?*const Type {
        const index = @intFromEnum(id);
        if (index >= self.types.items.len) return null;
        return &self.types.items[index];
    }

    pub fn getType(self: *Self, id: TypeId) *const Type {
        return self.get(id) orelse unreachable;
    }
};

/// Symbol interner for scoped symbol resolution
pub const SymInterner = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator, // Symbol storage arena
    symbols: std.ArrayList(Symbol),
    map: std.HashMap([32]u8, SymId, Blake3Context, std.hash_map.default_max_load_percentage),
    mutex: std.Thread.Mutex = .{},

    const Blake3Context = StrInterner.Blake3Context;

    pub const Symbol = struct {
        scope_chain: []u32, // scope IDs from root to immediate parent
        name: StrId,
        kind: SymbolKind,

        pub const SymbolKind = enum {
            function,
            variable,
            type_def,
            constant,
            parameter,
        };

        pub fn canonicalBytes(self: *const Symbol, writer: anytype) !void {
            try writer.writeInt(u32, @intCast(self.scope_chain.len), .little);
            for (self.scope_chain) |scope_id| {
                try writer.writeInt(u32, scope_id, .little);
            }
            try writer.writeInt(u32, @intFromEnum(self.name), .little);
            try writer.writeAll(@tagName(self.kind));
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .symbols = .empty,
            .map = std.HashMap([32]u8, SymId, Blake3Context, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.symbols.deinit(self.arena.allocator());
        self.arena.deinit(); // O(1) cleanup of all interned symbols
    }

    pub fn intern(self: *Self, symbol: Symbol) !SymId {
        var buf: [1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        try symbol.canonicalBytes(stream.writer());

        var hash: [32]u8 = undefined;
        Blake3.hash(stream.getWritten(), &hash, .{});

        self.acquireLock();
        defer self.releaseLock();

        if (self.map.get(hash)) |id| {
            return id;
        }

        const id = @as(SymId, @enumFromInt(@as(u32, @intCast(self.symbols.items.len))));
        const owned = try self.arena.allocator().create(Symbol);
        owned.* = symbol;
        // Deep copy scope_chain
        owned.scope_chain = try self.arena.allocator().dupe(u32, symbol.scope_chain);
        try self.symbols.append(self.arena.allocator(), owned.*);
        try self.map.put(hash, id);

        return id;
    }

    pub fn get(self: *Self, id: SymId) ?*const Symbol {
        const index = @intFromEnum(id);
        if (index >= self.symbols.items.len) return null;
        return &self.symbols.items[index];
    }
};

// Tests
test "StrInterner basic functionality" {
    var interner = StrInterner.init(std.testing.allocator);
    defer interner.deinit();

    const id1 = try interner.intern("hello");
    const id2 = try interner.intern("world");
    const id3 = try interner.intern("hello"); // duplicate

    try std.testing.expect(id1 == id3); // same string, same ID
    try std.testing.expect(id1 != id2); // different strings, different IDs

    try std.testing.expectEqualStrings("hello", interner.getString(id1));
    try std.testing.expectEqualStrings("world", interner.getString(id2));

    try std.testing.expectEqual(@as(u32, 2), interner.count()); // only 2 unique strings
}

test "TypeInterner primitive types" {
    var interner = TypeInterner.init(std.testing.allocator);
    defer interner.deinit();

    const i32_type = TypeInterner.Type{
        .kind = .primitive,
        .data = .{ .primitive = .i32 },
    };

    const bool_type = TypeInterner.Type{
        .kind = .primitive,
        .data = .{ .primitive = .bool },
    };

    const id1 = try interner.intern(i32_type);
    const id2 = try interner.intern(bool_type);
    const id3 = try interner.intern(i32_type); // duplicate

    try std.testing.expect(id1 == id3);
    try std.testing.expect(id1 != id2);

    const retrieved = interner.getType(id1);
    try std.testing.expectEqual(TypeInterner.Type.TypeKind.primitive, retrieved.kind);
    try std.testing.expectEqual(TypeInterner.Type.PrimitiveType.i32, retrieved.data.primitive);
}

test "StrInterner thread safety" {
    var interner = StrInterner.init(std.testing.allocator);
    defer interner.deinit();

    const ThreadContext = struct {
        interner: *StrInterner,
        results: []StrId,
    };

    const thread_fn = struct {
        fn run(ctx: *ThreadContext) void {
            for (ctx.results, 0..) |*result, i| {
                var buf: [32]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "string_{d}", .{i}) catch unreachable;
                result.* = ctx.interner.intern(str) catch unreachable;
            }
        }
    }.run;

    const num_threads = 4;
    const strings_per_thread = 100;

    var contexts: [num_threads]ThreadContext = undefined;
    var results: [num_threads][strings_per_thread]StrId = undefined;
    var threads: [num_threads]std.Thread = undefined;

    for (&contexts, &results, 0..) |*ctx, *result_array, i| {
        ctx.* = ThreadContext{
            .interner = &interner,
            .results = result_array,
        };
        threads[i] = try std.Thread.spawn(.{}, thread_fn, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    // Verify all threads got valid IDs
    for (results) |thread_results| {
        for (thread_results) |id| {
            try std.testing.expect(interner.get(id) != null);
        }
    }
}

test "StrInterner deterministic mode" {
    // Test that deterministic mode produces identical results
    var interner1 = StrInterner.initWithMode(std.testing.allocator, true);
    defer interner1.deinit();

    var interner2 = StrInterner.initWithMode(std.testing.allocator, true);
    defer interner2.deinit();

    const test_strings = [_][]const u8{
        "hello",
        "world",
        "function",
        "variable",
        "identifier_with_underscores",
        "CamelCaseIdentifier",
        "123numbers",
    };

    var ids1: [test_strings.len]StrId = undefined;
    var ids2: [test_strings.len]StrId = undefined;

    // Intern strings in both interners
    for (test_strings, 0..) |str, i| {
        ids1[i] = try interner1.intern(str);
        ids2[i] = try interner2.intern(str);
    }

    // IDs should be identical in deterministic mode
    for (ids1, ids2) |id1, id2| {
        try std.testing.expectEqual(id1, id2);
    }

    // Verify string retrieval works
    for (test_strings, ids1) |original, id| {
        try std.testing.expectEqualStrings(original, interner1.getString(id));
    }
}
